package app.libremusic.data


import app.libremusic.L
import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.view.Choreographer
import app.libremusic.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.security.SecureRandom

/**
 * Telemetría de rendimiento (Fase 2.1, ADR 0001). **Apagada por defecto**: sin el consentimiento, que es
 * separado de la cuenta y se retira en Ajustes › Ayuda y soporte › Tus datos, no se mide ni se envía nada.
 * Qué se envía, exactamente, en docs/TELEMETRIA.md (y el servidor rechaza cualquier otro campo):
 * plataforma, variante, versión de la app y del sistema, modelo, arranque en ms, FPS medianos, % de fotogramas
 * lentos, memoria y minutos de la sesión, con un identificador aleatorio de la instalación que no se relaciona
 * con la cuenta. Igual que `Telemetry` en iOS.
 *
 * **Fase 4b: un informe por semana.** Cada sesión se apunta en el móvil (`week` en las preferencias) y, cuando
 * empieza una semana ISO nueva, se envía el resumen de la anterior (medianas y número de sesiones). **Pear Dev es
 * sólo manual** (lo decidió Toxbox el 15-10-2026): mide siempre en el móvil, nunca envía sola, y «Enviar ahora»
 * manda la semana en curso con los campos que elija.
 */
object Telemetry {
    const val ENDPOINT = "https://pear-music-api.8toxbox8-69a.workers.dev/v1/telemetria"
    private const val PREFS = "telemetry"

    /** Desde que arranca el proceso (lo apunta la Application) hasta el primer fotograma. */
    @Volatile var processStart = 0L
    @Volatile private var startupMs: Long? = null
    private var sessionStart = 0L
    private val frames = ArrayList<Long>(4096)
    private var lastFrame = 0L
    private var sampling = false

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun enabled(c: Context) = BuildConfig.ADMIN_TOOLS || prefs(c).getBoolean("consent", false)

    /** null = aún no se ha preguntado (la guía inicial lo pregunta). */
    fun asked(c: Context) = prefs(c).contains("consent")

    /** Lo que contestó la persona (en Pear Dev se mide siempre, pero la decisión es la suya). */
    fun consented(c: Context) = prefs(c).getBoolean("consent", false)

    /** El identificador de la telemetría, sólo si está activada (para unirla a la ficha del soporte). */
    fun installIfEnabled(c: Context): String? = if (enabled(c)) install(c) else null

    /**
     * Versión del texto de consentimiento que se enseña. La 2 añadirá «y a veces antes, si el responsable lo pide»
     * (2.12 de x.1.1): **hasta que Toxbox apruebe ese texto, sigue en 1** y nadie recibe el resumen «forzado».
     */
    const val CONSENT_TEXT = 1
    /** Desde qué texto aceptado se atiende «forzar». */
    private const val FORCED_FROM_TEXT = 2

    fun setConsent(c: Context, on: Boolean) {
        val was = enabled(c)
        prefs(c).edit().putBoolean("consent", on).putLong("consentAt", System.currentTimeMillis()).putInt("consentText", if (on) CONSENT_TEXT else 0).apply()
        if (was && !on) withdrawLater(c.applicationContext)
    }

    private fun install(c: Context): String = prefs(c).getString("install", null) ?: ByteArray(16).also { SecureRandom().nextBytes(it) }
        .joinToString("") { "%02x".format(it) }.also { prefs(c).edit().putString("install", it).apply() }

    private val callback = object : Choreographer.FrameCallback {
        override fun doFrame(now: Long) {
            if (!sampling) return
            if (lastFrame != 0L && frames.size < 20_000) frames += now - lastFrame
            if (startupMs == null && processStart > 0) startupMs = SystemClock.elapsedRealtime() - processStart
            lastFrame = now
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    /** Al pasar a primer plano (hilo principal). */
    fun onForeground(c: Context) {
        if (!enabled(c) || sampling) return
        sampling = true
        sessionStart = SystemClock.elapsedRealtime()
        frames.clear()
        lastFrame = 0L
        Choreographer.getInstance().postFrameCallback(callback)
    }

    /** Al pasar a segundo plano: apunta la sesión en la semana (hilo principal) y envía la semana anterior si toca. */
    suspend fun onBackground(c: Context) {
        if (!sampling) return
        sampling = false
        if (!enabled(c)) return
        record(c, session())
        startupMs = -1 // el arranque sólo cuenta en la primera sesión del proceso
        flushIfDue(c)
    }

    /** Lo medido en esta sesión. */
    private fun session(): JSONObject {
        val sorted = frames.sorted()
        val medianNs = sorted.getOrNull(sorted.size / 2)
        val budget = 1_000_000_000L / 60
        val rt = Runtime.getRuntime()
        return JSONObject().apply {
            startupMs?.takeIf { it in 0..119_999 }?.let { put("startup_ms", it) }
            medianNs?.let { put("fps_median", (1e9 / it).coerceIn(0.0, 240.0)) }
            if (sorted.isNotEmpty()) put("jank_percent", sorted.count { it > budget * 3 / 2 } * 100.0 / sorted.size)
            put("memory_mb", ((rt.totalMemory() - rt.freeMemory() + android.os.Debug.getNativeHeapAllocatedSize()) / 1_048_576).toInt())
            put("session_minutes", ((SystemClock.elapsedRealtime() - sessionStart) / 60_000).toInt().coerceIn(0, 1439))
        }
    }

    /** Semana ISO, «2026-W42». */
    fun isoWeek(date: java.time.LocalDate = java.time.LocalDate.now()): String =
        "%d-W%02d".format(date.get(java.time.temporal.IsoFields.WEEK_BASED_YEAR), date.get(java.time.temporal.IsoFields.WEEK_OF_WEEK_BASED_YEAR))

    /** Las sesiones de la semana guardadas: { week, sessions: [ {…}, … ] } (como mucho 200). */
    private fun bucket(c: Context): JSONObject =
        prefs(c).getString("week", null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject().put("week", isoWeek()).put("sessions", org.json.JSONArray())

    @Synchronized
    fun record(c: Context, session: JSONObject, week: String = isoWeek()) {
        var b = bucket(c)
        if (b.optString("week") != week) {
            // La semana anterior aún sin enviar se guarda aparte hasta que salga.
            if ((b.optJSONArray("sessions")?.length() ?: 0) > 0) prefs(c).edit().putString("pending", b.toString()).apply()
            b = JSONObject().put("week", week).put("sessions", org.json.JSONArray())
        }
        val list = b.getJSONArray("sessions")
        if (list.length() < 200) list.put(session)
        prefs(c).edit().putString("week", b.toString()).apply()
    }

    /** Resumen de una semana: medianas de cada medida y número de sesiones. */
    fun summarize(c: Context, b: JSONObject, kind: String, only: Set<String>? = null): JSONObject {
        val list = b.optJSONArray("sessions") ?: org.json.JSONArray()
        fun median(key: String): Double? = (0 until list.length()).mapNotNull { i -> list.getJSONObject(i).let { if (it.has(key)) it.getDouble(key) else null } }
            .sorted().let { if (it.isEmpty()) null else it[it.size / 2] }
        val all = JSONObject()
            .put("os_version", Build.VERSION.RELEASE.take(32))
            .put("device_model", "${Build.MANUFACTURER} ${Build.MODEL}".take(64))
            .put("sessions", list.length())
            .apply {
                median("startup_ms")?.let { put("startup_ms", it.toLong()) }
                median("fps_median")?.let { put("fps_median", Math.round(it * 10) / 10.0) }
                median("jank_percent")?.let { put("jank_percent", Math.round(it * 10) / 10.0) }
                median("memory_mb")?.let { put("memory_mb", it.toInt()) }
                median("session_minutes")?.let { put("session_minutes", it.toInt()) }
            }
        val out = JSONObject()
            .put("install", install(c))
            .put("platform", "android")
            .put("channel", BuildConfig.CHANNEL)
            .put("app_version", BuildConfig.VERSION_NAME)
            .put("week", b.optString("week", isoWeek()))
            .put("kind", kind)
        all.keys().forEach { k -> if (only == null || k in only) out.put(k, all.get(k)) }
        return out
    }

    /** Envía la semana que ya acabó (al salir de la app y desde el AvisosWorker). Si falla, se reintenta luego. */
    suspend fun flushIfDue(c: Context) = withContext(Dispatchers.IO) {
        if (!enabled(c) || Incident.restricted || BuildConfig.ADMIN_TOOLS) return@withContext // Pear Dev: sólo «Enviar ahora»
        val now = isoWeek()
        val b = bucket(c)
        if (b.optString("week") != now && (b.optJSONArray("sessions")?.length() ?: 0) > 0) {
            prefs(c).edit().putString("pending", b.toString()).putString("week", JSONObject().put("week", now).put("sessions", org.json.JSONArray()).toString()).apply()
        }
        val pending = prefs(c).getString("pending", null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return@withContext
        if (runCatching { post(summarize(c, pending, "semanal")) }.getOrDefault(false)) prefs(c).edit().remove("pending").apply()
    }

    /**
     * «Forzar extracción» del panel (2.12 de x.1.1): la orden llega en el latido diario (`/v1/activo`). Sólo la
     * atiende quien aceptó un texto que lo dice, en la variante pública; Pear Dev y pref no tienen envío automático.
     * Manda la semana en curso una vez por orden.
     */
    suspend fun sendForced(c: Context, orden: String) = withContext(Dispatchers.IO) {
        if (BuildConfig.CHANNEL != "usr" || !consented(c) || Incident.restricted) return@withContext
        if (prefs(c).getInt("consentText", 0) < FORCED_FROM_TEXT || prefs(c).getString("lastOrden", null) == orden) return@withContext
        if (runCatching { post(summarize(c, bucket(c), "forzado")) }.getOrDefault(false)) prefs(c).edit().putString("lastOrden", orden).apply()
    }

    /** Campos que se pueden elegir en «Enviar ahora» de Pear Dev. */
    val CHOOSABLE get() = listOf(
        "os_version" to L("Versión del sistema"), "device_model" to "Modelo", "sessions" to "Sesiones",
        "startup_ms" to "Arranque", "fps_median" to "FPS", "jank_percent" to "Tirones", "memory_mb" to "Memoria", "session_minutes" to L("Minutos por sesión"),
    )

    /** Pear Dev: manda ya la semana en curso con los campos elegidos. Devuelve el informe enviado, o null si falló. */
    suspend fun sendNow(c: Context, only: Set<String>): JSONObject? = withContext(Dispatchers.IO) {
        if (!BuildConfig.ADMIN_TOOLS) return@withContext null
        val report = summarize(c, bucket(c), "manual", only)
        if (runCatching { post(report) }.getOrDefault(false)) report else null
    }

    private fun post(body: JSONObject): Boolean =
        YTClient.http.newCall(
            Request.Builder().url(ENDPOINT).post(body.toString().toRequestBody("application/json".toMediaType())).build(),
        ).execute().use { it.isSuccessful }

    /** Retirar el consentimiento: se pide al servidor que borre lo de esta instalación y se cambia el
     *  identificador, así lo que se mande si se vuelve a aceptar no se puede unir con lo anterior. */
    private fun withdrawLater(c: Context) {
        val old = prefs(c).getString("install", null) ?: return
        prefs(c).edit().remove("install").remove("week").remove("pending").apply()
        Thread { deleteRemote(old) }.start()
    }

    /** Para «Borrar todos mis datos» (fuera del hilo principal): borra lo enviado desde esta instalación. */
    fun deleteRemoteBlocking(c: Context) {
        prefs(c).getString("install", null)?.let(::deleteRemote)
    }

    private fun deleteRemote(install: String) = runCatching {
        YTClient.http.newBuilder().callTimeout(java.time.Duration.ofSeconds(3)).build().newCall(
            Request.Builder().url(ENDPOINT).delete(JSONObject().put("install", install).toString().toRequestBody("application/json".toMediaType())).build(),
        ).execute().close()
    }
}
