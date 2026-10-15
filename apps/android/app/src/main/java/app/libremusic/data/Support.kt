package app.libremusic.data


import app.libremusic.L
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
import okhttp3.RequestBody.Companion.toRequestBody
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
    /** «error» (Informar de un error) o «sugerencia» (Buzón de sugerencias). */
    val kind: String = "error",
) {
    val isEmpty get() = email.isBlank() && text.isBlank() && photos.isEmpty()

    fun toJson(): JSONObject = JSONObject().put("id", id).put("email", email).put("text", text)
        .put("photos", JSONArray(photos)).put("updated", updated).put("kind", kind)

    companion object {
        fun fromJson(o: JSONObject) = SupportDraft(
            id = o.optString("id").ifEmpty { UUID.randomUUID().toString() },
            email = o.optString("email"),
            text = o.optString("text"),
            photos = o.optJSONArray("photos")?.let { a -> (0 until a.length()).map { a.getString(it) } }.orEmpty(),
            updated = o.optLong("updated"),
            kind = if (o.optString("kind") == "sugerencia") "sugerencia" else "error",
        )
    }
}

/** Borradores guardados en el móvil (`filesDir/support/drafts.json`, cifrado), el más reciente primero. */
class SupportStore(private val dir: File, private val box: Box = SecureBox) {
    private val file = File(dir, "drafts.json")
    private val _drafts = MutableStateFlow(load())
    val drafts: StateFlow<List<SupportDraft>> = _drafts.asStateFlow()

    private fun load(): List<SupportDraft> = runCatching {
        val bytes = file.readBytes()
        // Hasta la 0.9.5 se guardaba en claro (empieza por «[»): se lee y se vuelve a guardar cifrado.
        val legacy = bytes.isNotEmpty() && bytes[0] == '['.code.toByte()
        val a = JSONArray(String(if (legacy) bytes else box.open(bytes)))
        (0 until a.length()).map { SupportDraft.fromJson(a.getJSONObject(it)) }.also { if (legacy) write(it) }
    }.getOrDefault(emptyList()).sortedByDescending { it.updated }

    private fun persist(list: List<SupportDraft>) {
        _drafts.value = list.sortedByDescending { it.updated }
        write(_drafts.value)
    }

    /** El correo y el texto van cifrados con [SecureBox] (ver docs/SEGURIDAD.md). */
    private fun write(list: List<SupportDraft>) {
        val json = JSONArray().apply { list.forEach { put(it.toJson()) } }.toString()
        // Si el Keystore falla (raro, pero pasa en algún móvil), el borrador se queda sólo en memoria: nunca en claro
        // en el disco, y nunca un cierre de la app al salir del formulario.
        runCatching { dir.mkdirs(); file.writeBytes(box.seal(json.toByteArray())) }
            .onFailure { Logs.w("Support", "No se pudo guardar el borrador cifrado: ${it.javaClass.simpleName}") }
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

    /** Resultado de enviar: `error` null si ha llegado; si el servidor lo rechazó por el contenido, `denialId`
     *  permite apelar (`appeal`). */
    data class Result(val error: String?, val denialId: String? = null, val ticket: Int? = null)

    /** El id anónimo con el que se piden las respuestas del soporte, sólo si ya se envió algo desde aquí. */
    fun sentDeviceId(context: Context): String? {
        val sp = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        return if (sp.getBoolean("supportSent", false)) sp.getString("supportDeviceId", null) else null
    }

    private fun deviceId(context: Context): String {
        val sp = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        return sp.getString("supportDeviceId", null) ?: UUID.randomUUID().toString().also {
            sp.edit().putString("supportDeviceId", it).apply()
        }
    }

    /** Envía el reporte. */
    suspend fun send(context: Context, d: SupportDraft, appVersion: String): Result = withContext(Dispatchers.IO) {
        if (Incident.restricted) return@withContext Result(L("El soporte está en pausa mientras resolvemos un incidente. Tu reporte se queda en Borradores."))
        val deviceId = deviceId(context)
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("email", d.email.trim())
            .addFormDataPart("text", d.text.trim())
            .addFormDataPart("platform", "android")
            .addFormDataPart("appVersion", appVersion)
            .addFormDataPart("os", "Android ${android.os.Build.VERSION.RELEASE}")
            .addFormDataPart("model", "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}")
            .addFormDataPart("deviceId", deviceId)
            .addFormDataPart("kind", d.kind)
            .apply {
                d.photos.map(::File).filter { it.exists() }.forEachIndexed { i, f ->
                    addFormDataPart("photo$i", "foto-${i + 1}.jpg", f.asRequestBody("image/jpeg".toMediaType()))
                }
            }
            .build()
        try {
            YTClient.http.newCall(Request.Builder().url(ENDPOINT).post(body).build()).execute().use { res ->
                val json = runCatching { JSONObject(res.body?.string().orEmpty()) }.getOrNull()
                if (res.isSuccessful) {
                    // Desde ahora la campana pregunta por las respuestas a sus tickets.
                    context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putBoolean("supportSent", true).apply()
                    val ticket = json?.optInt("ticket")?.takeIf { it > 0 }
                    // La ficha de este móvil, unida al ticket (el formulario lo avisa antes de enviar).
                    if (ticket != null) Ficha.send(context, deviceId, ticket, d.kind, appVersion)
                    return@use Result(null, ticket = ticket)
                }
                Result(
                    json?.optString("error")?.ifEmpty { null } ?: L("El servidor de soporte no responde ({0}). Prueba más tarde.", res.code),
                    json?.optString("denialId")?.ifEmpty { null },
                )
            }
        } catch (e: java.io.IOException) {
            Result(L("Sin conexión. Inténtalo cuando tengas internet."))
        }
    }

    /** Apela un rechazo (sólo desde el móvil que lo envió). Devuelve null si ha llegado, o el motivo. */
    suspend fun appeal(context: Context, denialId: String, email: String, text: String): String? = withContext(Dispatchers.IO) {
        val body = JSONObject().put("denialId", denialId).put("deviceId", deviceId(context)).put("email", email.trim()).put("text", text.trim())
            .toString().toRequestBody("application/json".toMediaType())
        try {
            YTClient.http.newCall(Request.Builder().url(ENDPOINT.replace("/report", "/appeal")).post(body).build()).execute().use { res ->
                if (res.isSuccessful) null
                else runCatching { JSONObject(res.body?.string().orEmpty()).optString("error") }.getOrNull()?.ifEmpty { null }
                    ?: L("El servidor de soporte no responde ({0}). Prueba más tarde.", res.code)
            }
        } catch (e: java.io.IOException) {
            L("Sin conexión. Inténtalo cuando tengas internet.")
        }
    }
}
