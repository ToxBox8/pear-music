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
    const val URL = "https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev/version.json"
    private const val CHECK_EVERY_MS = 6 * 3_600_000L
    const val SNOOZE_MS = 24 * 3_600_000L

    data class Release(
        val version: String, val title: String, val highlights: List<String>, val apk: String, val sha256: String,
        val fix: Boolean = false,
        /** «minima_recomendada» (0.5 de x.1.1): por debajo, el aviso de versión antigua no se puede quitar más de 24 h. */
        val minimum: String? = null,
    )

    private fun prefs(context: Context) = context.getSharedPreferences("updates", Context.MODE_PRIVATE)

    // MARK: Firma de publicación (fase de seguridad S4, x.1.1)

    /**
     * Clave pública Ed25519 de publicación (32 bytes en base64). La privada vive fuera de línea (USB de Toxbox,
     * `tools/publicar/firmar.mjs`). Creada el 21-10-2026; vacía, no se comprobaría nada.
     */
    const val PUBLISH_KEY = "8mBhBBxlDG8xNXRUxUuOEqFd4nSnCQtj7UFB8z6bbEk="

    enum class Signature { Good, Missing, Bad, NoKey }

    /**
     * x.1.1 «verificar y avisar»: sin firma se sigue (y se apunta); con firma que no cuadra **no se ofrece descargar**.
     * En la versión siguiente, sin firma tampoco.
     */
    fun signature(body: ByteArray, sigB64: String?, publicKeyB64: String = PUBLISH_KEY): Signature = when {
        publicKeyB64.isEmpty() -> Signature.NoKey
        sigB64.isNullOrBlank() -> Signature.Missing
        runCatching {
            val v = org.bouncycastle.crypto.signers.Ed25519Signer()
            v.init(false, org.bouncycastle.crypto.params.Ed25519PublicKeyParameters(java.util.Base64.getDecoder().decode(publicKeyB64), 0))
            v.update(body, 0, body.size)
            v.verifySignature(java.util.Base64.getDecoder().decode(sigB64.trim()))
        }.getOrDefault(false) -> Signature.Good
        else -> Signature.Bad
    }

    // MARK: Versión simulada (2.2 de x.1.1, sólo Pear Dev): la app se cree otra versión para ver el aviso sin instalar.

    private val _simulated = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    val simulated: kotlinx.coroutines.flow.StateFlow<String?> = _simulated

    fun loadSimulated(context: Context) {
        _simulated.value = if (BuildConfig.ADMIN_TOOLS) prefs(context).getString("fakeVersion", null) else null
    }

    /** Pone (o quita, con null) la versión simulada y olvida la última comprobación para que se vea al volver. */
    fun simulate(context: Context, version: String?) {
        if (!BuildConfig.ADMIN_TOOLS) return
        prefs(context).edit().putString("fakeVersion", version).remove("checked").remove("snoozeVersion").remove("staleUntil").apply()
        _simulated.value = version
    }

    private fun installed(): String = _simulated.value ?: BuildConfig.VERSION_NAME

    // MARK: Versión antigua (0.5 de x.1.1)

    /** Días con una versión nueva sin actualizar a partir de los que se avisa. */
    const val STALE_DAYS = 21
    private const val STALE_MS = STALE_DAYS * 86_400_000L
    /** Menores por detrás (1.1 → 1.3) a partir de las que se avisa. */
    const val STALE_MINORS = 2

    /** Cuántas versiones menores va por detrás; otra mayor cuenta como muchas. */
    fun minorsBehind(installed: String, latest: String): Int {
        fun core(v: String) = v.trim().removePrefix("v").substringBefore('-').split('.').map { it.toIntOrNull() ?: 0 } + listOf(0, 0)
        val (ia, ib) = core(installed); val (la, lb) = core(latest)
        return when { la > ia -> 99; la < ia -> 0; else -> (lb - ib).coerceAtLeast(0) }
    }

    /** ¿Es antigua? Por debajo de la mínima recomendada, 2 menores por detrás o 21 días sin actualizar. */
    fun isStale(installed: String, latest: String?, minimum: String?, pendingSince: Long, now: Long): Boolean {
        if (latest == null || compare(latest, installed) <= 0) return false
        return (minimum != null && compare(installed, minimum) < 0) || minorsBehind(installed, latest) >= STALE_MINORS ||
            (pendingSince > 0 && now - pendingSince >= STALE_MS)
    }

    /** Si hay que enseñar el aviso de versión antigua (en Inicio): `true` = no se puede quitar más de 24 h. */
    private val _stale = kotlinx.coroutines.flow.MutableStateFlow<Boolean?>(null)
    val stale: kotlinx.coroutines.flow.StateFlow<Boolean?> = _stale

    private fun refreshStale(context: Context, now: Long) {
        val p = prefs(context)
        val latest = p.getString("latest", null)
        val minimum = p.getString("minimum", null)
        val old = isStale(installed(), latest, minimum, p.getLong("pendingSince", 0), now)
        _stale.value = if (old && now >= p.getLong("staleUntil", 0)) minimum != null && compare(installed(), minimum) < 0 else null
    }

    /** «Actualizar» desde el aviso de versión antigua: se vuelve a mirar ya, aunque se hubiera aplazado. */
    fun forceRecheck(context: Context) {
        prefs(context).edit().remove("checked").remove("snoozeVersion").remove("snoozeUntil").apply()
    }

    /** «Ahora no»: 24 h si está por debajo de la mínima, 3 días si no. */
    fun dismissStale(context: Context, now: Long = System.currentTimeMillis()) {
        val hard = _stale.value == true
        prefs(context).edit().putLong("staleUntil", now + if (hard) SNOOZE_MS else 3 * SNOOZE_MS).apply()
        _stale.value = null
    }

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
            a.optString("minima_recomendada").ifEmpty { null },
        ).takeIf { it.apk.startsWith("https://") && it.sha256.matches(Regex("[a-f0-9]{64}")) }
    }.getOrNull()

    /** ¿Hay que enseñar el aviso de esta versión ahora? (más nueva y no aplazada). */
    fun shouldShow(release: Release, installed: String, snoozedVersion: String?, snoozedUntil: Long, now: Long): Boolean =
        compare(release.version, installed) > 0 && !(snoozedVersion == release.version && now < snoozedUntil)

    /** La versión nueva que hay que enseñar, o null. Nunca lanza: sin red no pasa nada. */
    suspend fun check(context: Context, now: Long = System.currentTimeMillis()): Release? = withContext(Dispatchers.IO) {
        loadSimulated(context)
        // Pear Dev sólo comprueba con una versión simulada (2.2 de x.1.1): así se ve el aviso sin instalar nada.
        if (BuildConfig.CHANNEL != "usr" && _simulated.value == null) return@withContext null
        val p = prefs(context)
        refreshStale(context, now)
        if (now - p.getLong("checked", 0) < CHECK_EVERY_MS && p.getString("pending", null) == null) return@withContext null
        val body = runCatching {
            YTClient.http.newCall(Request.Builder().url(URL).build()).execute().use { if (it.isSuccessful) it.body!!.bytes() else null }
        }.getOrNull() ?: return@withContext null
        val sig = runCatching {
            YTClient.http.newCall(Request.Builder().url("$URL.sig").build()).execute().use { if (it.isSuccessful) it.body!!.string() else null }
        }.getOrNull()
        when (signature(body, sig)) {
            Signature.Bad -> { Logs.w("Updates", "version.json con firma que no cuadra: no se ofrece"); return@withContext null }
            Signature.Missing -> Logs.i("Updates", "version.json sin firma (x.1.1 aún lo acepta)")
            else -> Unit
        }
        val release = parse(String(body, Charsets.UTF_8)) ?: return@withContext null
        val newer = compare(release.version, installed()) > 0
        p.edit().putLong("checked", now).putString("pending", release.version.takeIf { newer })
            .putString("latest", release.version).putString("minimum", release.minimum)
            // Desde cuándo hay una versión nueva sin instalar (para los 21 días).
            .putLong("pendingSince", if (!newer) 0 else p.getLong("pendingSince", 0).takeIf { it > 0 } ?: now).apply()
        refreshStale(context, now)
        release.takeIf {
            allowed(it, Incident.restricted) &&
                shouldShow(it, installed(), p.getString("snoozeVersion", null), p.getLong("snoozeUntil", 0), now)
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
