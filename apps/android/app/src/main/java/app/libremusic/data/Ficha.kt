package app.libremusic.data

import android.content.Context
import app.libremusic.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Ficha del dispositivo e instalaciones activas (15-10-2026, lo pidió Toxbox; docs/TELEMETRIA.md).
 *
 * - **Ficha:** al enviar un reporte o una sugerencia (el formulario lo avisa) se manda a `pear-music-api` la ficha
 *   de este móvil con el número de ticket: plataforma, variante, versión, sistema y modelo. Si la telemetría está
 *   activada, también su identificador, para que el panel una el ticket con el rendimiento. El id de la ficha es el
 *   SHA-256 del id anónimo del soporte (el mismo resumen que guarda `libremusic-soporte`).
 * - **Activos:** una vez al día la app suma uno al contador de su versión. No lleva ningún identificador.
 * - **Decisión sobre la telemetría:** tras contestar la privacidad, «sí» o «no» (y la anterior si cambia, para
 *   restarla). Sólo contadores, sin identificador.
 *
 * Igual que `Ficha` en iOS.
 */
object Ficha {
    private const val BASE = "https://pear-music-api.8toxbox8-69a.workers.dev/v1"

    fun id(supportDeviceId: String): String =
        MessageDigest.getInstance("SHA-256").digest(supportDeviceId.trim().lowercase().toByteArray())
            .joinToString("") { "%02x".format(it) }

    /** El cuerpo que se envía (para los tests). */
    fun body(context: Context, supportDeviceId: String, ticket: Int, kind: String, appVersion: String): JSONObject =
        JSONObject()
            .put("ficha", id(supportDeviceId))
            .put("platform", "android")
            .put("channel", BuildConfig.CHANNEL)
            .put("app_version", appVersion)
            .put("os_version", "Android ${android.os.Build.VERSION.RELEASE}")
            .put("device_model", "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}".take(64))
            .put("ticket", ticket)
            .put("kind", if (kind == "sugerencia") "sugerencia" else "error")
            .apply { Telemetry.installIfEnabled(context)?.let { put("install", it) } }

    /** Tras un reporte con número de ticket. Nunca falla hacia fuera: si no llega, el ticket sigue igual. */
    suspend fun send(context: Context, supportDeviceId: String, ticket: Int, kind: String, appVersion: String) = withContext(Dispatchers.IO) {
        runCatching { post("/ficha", body(context, supportDeviceId, ticket, kind, appVersion)) }
    }

    /** Una vez al día (UTC): suma uno a las instalaciones activas de esta versión. */
    suspend fun pingActive(context: Context, today: LocalDate = LocalDate.now(ZoneOffset.UTC)) = withContext(Dispatchers.IO) {
        if (Incident.restricted) return@withContext
        val prefs = context.getSharedPreferences("ficha", Context.MODE_PRIVATE)
        if (prefs.getString("activeDay", null) == today.toString()) return@withContext
        val body = JSONObject().put("platform", "android").put("channel", BuildConfig.CHANNEL).put("app_version", BuildConfig.VERSION_NAME)
        val answer = runCatching { postForJson("/activo", body) }.getOrNull() ?: return@withContext
        prefs.edit().putString("activeDay", today.toString()).apply()
        // «Forzar extracción» del panel (2.12 de x.1.1): Telemetry decide si se atiende (consentimiento y texto).
        answer.optString("orden").takeIf { it.isNotEmpty() && it != "null" }?.let { Telemetry.sendForced(context, it) }
    }

    /** Manda la decisión sobre la telemetría si aún no se ha mandado o ha cambiado. */
    suspend fun reportDecision(context: Context) = withContext(Dispatchers.IO) {
        if (Incident.restricted) return@withContext
        if (context.getSharedPreferences("settings", Context.MODE_PRIVATE).getLong("termsAcceptedAt", 0) == 0L) return@withContext
        val prefs = context.getSharedPreferences("ficha", Context.MODE_PRIVATE)
        val now = if (Telemetry.consented(context)) "si" else "no"
        val sent = prefs.getString("decision", null)
        if (sent == now) return@withContext
        val body = JSONObject().put("platform", "android").put("channel", BuildConfig.CHANNEL)
            .put("app_version", BuildConfig.VERSION_NAME).put("decision", now).apply { sent?.let { put("antes", it) } }
        if (runCatching { post("/consentimiento", body) }.getOrDefault(false)) prefs.edit().putString("decision", now).apply()
    }

    /** El cuerpo de la respuesta si fue bien (vacío = `{}`), o null. */
    private fun postForJson(path: String, body: JSONObject): JSONObject? =
        YTClient.http.newCall(
            Request.Builder().url(BASE + path).post(body.toString().toRequestBody("application/json".toMediaType())).build(),
        ).execute().use { r -> if (!r.isSuccessful) null else runCatching { JSONObject(r.body?.string().orEmpty()) }.getOrDefault(JSONObject()) }

    private fun post(path: String, body: JSONObject): Boolean =
        YTClient.http.newCall(
            Request.Builder().url(BASE + path).post(body.toString().toRequestBody("application/json".toMediaType())).build(),
        ).execute().use { it.isSuccessful }
}
