package app.libremusic.data


import app.libremusic.L
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import app.libremusic.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Avisos de versión nueva (Fase 2.2). Lee `version.json` de la web (versión, novedades, APK y su SHA-256) como
 * mucho cada 6 h al abrir la app. «Recordarme mañana» lo aplaza 24 h. «Descargar» baja el APK, comprueba el
 * SHA-256 y abre el instalador del sistema: mismo paquete y misma firma, así que Android **actualiza encima**
 * y se conservan la biblioteca, los ajustes y las canciones descargadas. Si el hash no cuadra, no se instala.
 *
 * Sólo en la variante usr: pref y dev son otras apps y el APK público no las actualizaría. En modo seguro (kill switch
 * nivel 2 o más) sólo se ofrecen las versiones marcadas como arreglo (`"fix": true` en `version.json`).
 * Igual que `Updates` en iOS (que abre AltStore/SideStore porque iOS no deja instalar desde la app).
 */
object Updates {
    const val URL = "https://libremusic-landing.8toxbox8-69a.workers.dev/version.json"
    private const val CHECK_EVERY_MS = 6 * 3_600_000L
    const val SNOOZE_MS = 24 * 3_600_000L

    data class Release(
        val version: String, val title: String, val highlights: List<String>, val apk: String, val sha256: String,
        val fix: Boolean = false,
    )

    private fun prefs(context: Context) = context.getSharedPreferences("updates", Context.MODE_PRIVATE)

    /** -1, 0 o 1. Semver con pre-releases: 1.0.0-pre1 < 1.0.0-pre2 < 1.0.0. Ignora sufijos de variante. */
    fun compare(a: String, b: String): Int {
        fun parts(v: String): Pair<List<Int>, String?> {
            val clean = v.trim().removePrefix("v").removeSuffix("-dev").removeSuffix("-pref").removeSuffix("-debug").removeSuffix("-perf")
            val core = clean.substringBefore('-')
            val pre = clean.substringAfter('-', "").ifEmpty { null }
            return core.split('.').map { it.toIntOrNull() ?: 0 }.let { it + List(3 - it.size.coerceAtMost(3)) { 0 } } to pre
        }
        val (ca, pa) = parts(a)
        val (cb, pb) = parts(b)
        for (i in 0 until 3) if (ca[i] != cb[i]) return ca[i].compareTo(cb[i])
        return when {
            pa == pb -> 0
            pa == null -> 1
            pb == null -> -1
            else -> {
                val na = Regex("\\d+").find(pa)?.value?.toIntOrNull()
                val nb = Regex("\\d+").find(pb)?.value?.toIntOrNull()
                if (na != null && nb != null && pa.replace(Regex("\\d+"), "") == pb.replace(Regex("\\d+"), "")) na.compareTo(nb) else pa.compareTo(pb)
            }
        }
    }

    fun parse(json: String): Release? = runCatching {
        val a = JSONObject(json).getJSONObject("android")
        val hl = a.optJSONArray("highlights")
        Release(
            a.getString("version"), a.optString("title"),
            (0 until (hl?.length() ?: 0)).map { hl!!.getString(it) },
            a.getString("apk"), a.getString("sha256").lowercase(), a.optBoolean("fix"),
        ).takeIf { it.apk.startsWith("https://") && it.sha256.matches(Regex("[a-f0-9]{64}")) }
    }.getOrNull()

    /** ¿Hay que enseñar el aviso de esta versión ahora? (más nueva y no aplazada). */
    fun shouldShow(release: Release, installed: String, snoozedVersion: String?, snoozedUntil: Long, now: Long): Boolean =
        compare(release.version, installed) > 0 && !(snoozedVersion == release.version && now < snoozedUntil)

    /** La versión nueva que hay que enseñar, o null. Nunca lanza: sin red no pasa nada. */
    suspend fun check(context: Context, now: Long = System.currentTimeMillis()): Release? = withContext(Dispatchers.IO) {
        if (BuildConfig.CHANNEL != "usr") return@withContext null
        val p = prefs(context)
        if (now - p.getLong("checked", 0) < CHECK_EVERY_MS && p.getString("pending", null) == null) return@withContext null
        val release = runCatching {
            YTClient.http.newCall(Request.Builder().url(URL).build()).execute().use { if (it.isSuccessful) parse(it.body!!.string()) else null }
        }.getOrNull() ?: return@withContext null
        p.edit().putLong("checked", now).putString("pending", release.version.takeIf { compare(it, BuildConfig.VERSION_NAME) > 0 }).apply()
        release.takeIf {
            allowed(it, Incident.restricted) &&
                shouldShow(it, BuildConfig.VERSION_NAME, p.getString("snoozeVersion", null), p.getLong("snoozeUntil", 0), now)
        }
    }

    /** En modo seguro sólo se ofrece una versión de arreglo: frena la mala sin bloquear la que la corrige. */
    fun allowed(release: Release, restricted: Boolean): Boolean = !restricted || release.fix

    fun snooze(context: Context, release: Release, now: Long = System.currentTimeMillis()) {
        prefs(context).edit().putString("snoozeVersion", release.version).putLong("snoozeUntil", now + SNOOZE_MS).apply()
    }

    private fun sha256(file: File): String = MessageDigest.getInstance("SHA-256").let { d ->
        file.inputStream().use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) { val n = input.read(buf); if (n < 0) break; d.update(buf, 0, n) }
        }
        d.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * Baja el APK a la caché, comprueba el SHA-256 y devuelve el archivo (o null y el motivo). Si ya está bajado y
     * cuadra (p. ej. tras dar el permiso de instalar), no se vuelve a descargar.
     */
    suspend fun download(context: Context, release: Release, progress: (Int) -> Unit): Pair<File?, String?> = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "updates")
        val file = File(dir, "pear-music-${release.version}.apk")
        if (file.isFile && runCatching { sha256(file) }.getOrNull() == release.sha256) return@withContext file to null
        dir.deleteRecursively(); dir.mkdirs()
        val digest = MessageDigest.getInstance("SHA-256")
        val ok = runCatching {
            YTClient.http.newCall(Request.Builder().url(release.apk).build()).execute().use { res ->
                if (!res.isSuccessful) return@use false
                val body = res.body ?: return@use false
                val total = body.contentLength().takeIf { it > 0 }
                var read = 0L
                body.byteStream().use { input ->
                    file.outputStream().use { out ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            digest.update(buf, 0, n)
                            read += n
                            total?.let { progress((read * 100 / it).toInt()) }
                        }
                    }
                }
                true
            }
        }.getOrDefault(false)
        if (!ok) return@withContext null to L("No se pudo descargar. Prueba con otra conexión.")
        val hash = digest.digest().joinToString("") { "%02x".format(it) }
        if (hash != release.sha256) {
            file.delete()
            return@withContext null to L("La descarga no coincide con la publicada y no se ha instalado, por seguridad.")
        }
        file to null
    }

    /** Abre el instalador del sistema; si falta el permiso de «instalar apps desconocidas», sus ajustes. */
    fun install(context: Context, apk: File): Boolean {
        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return false
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
        context.startActivity(
            Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        return true
    }
}
