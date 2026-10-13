package app.libremusic.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

/**
 * «Informar de un error» (Fase 4C). Mismos límites que el Worker (`services/soporte/src/limits.js`) y que
 * `SupportLimits` en iOS.
 */
object SupportLimits {
    const val MAX_PHOTOS = 4
    const val MAX_PHOTO_BYTES = 1_500_000
    const val MIN_TEXT = 10
    const val MAX_TEXT = 4000
    /** Lado mayor de las fotos al reescalarlas: se leen bien y pesan poco. */
    const val PHOTO_SIDE = 1600

    private val EMAIL = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$")
    fun validEmail(email: String) = email.length <= 254 && EMAIL.matches(email.trim())
    fun validText(text: String) = text.trim().length in MIN_TEXT..MAX_TEXT
}

/** Un reporte a medias o que no se pudo enviar. Las fotos ya están comprimidas en `filesDir/support/<id>/`. */
data class SupportDraft(
    val id: String = UUID.randomUUID().toString(),
    val email: String = "",
    val text: String = "",
    val photos: List<String> = emptyList(),
    val updated: Long = System.currentTimeMillis(),
) {
    val isEmpty get() = email.isBlank() && text.isBlank() && photos.isEmpty()

    fun toJson(): JSONObject = JSONObject().put("id", id).put("email", email).put("text", text)
        .put("photos", JSONArray(photos)).put("updated", updated)

    companion object {
        fun fromJson(o: JSONObject) = SupportDraft(
            id = o.optString("id").ifEmpty { UUID.randomUUID().toString() },
            email = o.optString("email"),
            text = o.optString("text"),
            photos = o.optJSONArray("photos")?.let { a -> (0 until a.length()).map { a.getString(it) } }.orEmpty(),
            updated = o.optLong("updated"),
        )
    }
}

/** Borradores guardados en el móvil (`filesDir/support/drafts.json`), el más reciente primero. */
class SupportStore(private val dir: File) {
    private val file = File(dir, "drafts.json")
    private val _drafts = MutableStateFlow(load())
    val drafts: StateFlow<List<SupportDraft>> = _drafts.asStateFlow()

    private fun load(): List<SupportDraft> = runCatching {
        val a = JSONArray(file.readText())
        (0 until a.length()).map { SupportDraft.fromJson(a.getJSONObject(it)) }
    }.getOrDefault(emptyList()).sortedByDescending { it.updated }

    private fun persist(list: List<SupportDraft>) {
        _drafts.value = list.sortedByDescending { it.updated }
        dir.mkdirs()
        file.writeText(JSONArray().apply { _drafts.value.forEach { put(it.toJson()) } }.toString())
    }

    /** Guarda (o quita, si está vacío) el borrador. */
    fun save(d: SupportDraft) {
        val rest = _drafts.value.filterNot { it.id == d.id }
        persist(if (d.isEmpty) rest else rest + d.copy(updated = System.currentTimeMillis()))
    }

    /** Borra el borrador y sus fotos (al enviarlo bien o al eliminarlo). */
    fun delete(id: String) {
        File(dir, id).deleteRecursively()
        persist(_drafts.value.filterNot { it.id == id })
    }

    fun photoDir(id: String) = File(dir, id).apply { mkdirs() }

    companion object {
        @Volatile private var instance: SupportStore? = null
        fun get(context: Context) = instance ?: synchronized(this) {
            instance ?: SupportStore(File(context.filesDir, "support")).also { instance = it }
        }
    }
}

object SupportClient {
    /** El Worker de `services/soporte`. La URL del webhook de Discord nunca está en la app. */
    const val ENDPOINT = "https://libremusic-soporte.8toxbox8-69a.workers.dev/report"

    /**
     * Copia una foto elegida en el borrador: girada según su EXIF, reescalada a [SupportLimits.PHOTO_SIDE] y
     * guardada como JPEG nuevo, así no viaja ningún metadato (ni la ubicación). Baja la calidad hasta que
     * pese menos de [SupportLimits.MAX_PHOTO_BYTES].
     */
    suspend fun importPhoto(context: Context, uri: Uri, into: File): File? = withContext(Dispatchers.IO) {
        runCatching {
            val resolver = context.contentResolver
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= SupportLimits.PHOTO_SIDE) sample *= 2
            val raw = resolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
            } ?: return@runCatching null
            val rotation = resolver.openInputStream(uri)?.use {
                when (android.media.ExifInterface(it).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1)) {
                    android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
            } ?: 0f
            val scale = minOf(1f, SupportLimits.PHOTO_SIDE.toFloat() / maxOf(raw.width, raw.height))
            val m = Matrix().apply { postScale(scale, scale); postRotate(rotation) }
            val bmp = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, m, true)
            var quality = 85
            var bytes: ByteArray
            do {
                bytes = ByteArrayOutputStream().use { out -> bmp.compress(Bitmap.CompressFormat.JPEG, quality, out); out.toByteArray() }
                quality -= 10
            } while (bytes.size > SupportLimits.MAX_PHOTO_BYTES && quality > 30)
            if (bytes.size > SupportLimits.MAX_PHOTO_BYTES) return@runCatching null
            File(into, "${UUID.randomUUID()}.jpg").apply { writeBytes(bytes) }
        }.getOrNull()
    }

    /** Envía el reporte. Devuelve null si ha llegado, o el motivo para enseñárselo al usuario. */
    suspend fun send(context: Context, d: SupportDraft, appVersion: String): String? = withContext(Dispatchers.IO) {
        val sp = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val deviceId = sp.getString("supportDeviceId", null) ?: UUID.randomUUID().toString().also {
            sp.edit().putString("supportDeviceId", it).apply()
        }
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("email", d.email.trim())
            .addFormDataPart("text", d.text.trim())
            .addFormDataPart("platform", "android")
            .addFormDataPart("appVersion", appVersion)
            .addFormDataPart("os", "Android ${android.os.Build.VERSION.RELEASE}")
            .addFormDataPart("model", "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}")
            .addFormDataPart("deviceId", deviceId)
            .apply {
                d.photos.map(::File).filter { it.exists() }.forEachIndexed { i, f ->
                    addFormDataPart("photo$i", "foto-${i + 1}.jpg", f.asRequestBody("image/jpeg".toMediaType()))
                }
            }
            .build()
        try {
            YTClient.http.newCall(Request.Builder().url(ENDPOINT).post(body).build()).execute().use { res ->
                if (res.isSuccessful) null
                else runCatching { JSONObject(res.body?.string().orEmpty()).optString("error") }.getOrNull()?.ifEmpty { null }
                    ?: "El servidor de soporte no responde (${res.code}). Prueba más tarde."
            }
        } catch (e: java.io.IOException) {
            "Sin conexión. Inténtalo cuando tengas internet."
        }
    }
}
