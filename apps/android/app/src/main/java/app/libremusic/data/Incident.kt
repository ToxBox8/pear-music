package app.libremusic.data


import app.libremusic.L
import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.json.JSONObject

/**
 * Estado de incidencias firmado (Fase 4, kill switch; docs/RUNBOOK-INCIDENTES.md). La app lleva sólo la clave
 * pública Ed25519; el estado lo firma el PC de Toxbox y lo sirve el Worker `pear-music-estado`, aparte de la web y
 * del repo. Niveles: 0 normal, 1 aviso (banner que caduca solo), 2 modo seguro (se apagan las funciones remotas de
 * riesgo), 3 bloqueo total (pantalla de mantenimiento).
 *
 * **Falla en abierto:** sin red, sin estado, con firma mala o caducado, la app sigue como estaba (el último estado
 * válido, mientras no caduque). Nunca se acepta un contador menor que el último visto (anti-rollback).
 * Igual que `Incident` en iOS.
 */
object Incident {
    const val URL = "https://pear-music-estado.8toxbox8-69a.workers.dev/estado"
    const val PUBLIC_KEY = "XBII1upMDF2PUHjTFrJwYEyHbbiUM3TT2O+9kHuTlgI="
    private const val PREFS = "incident"

    data class State(val level: Int = 0, val message: String = "", val counter: Long = 0)

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** Modo seguro o bloqueo: se apagan actualizaciones, búsqueda remota, soporte, telemetría y cuenta. */
    val restricted: Boolean get() = _state.value.level >= 2

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Comprueba la firma y devuelve el contenido, o null. */
    fun verify(payload: String, sigB64: String, publicKeyB64: String = PUBLIC_KEY): JSONObject? = runCatching {
        val signer = Ed25519Signer()
        signer.init(false, Ed25519PublicKeyParameters(java.util.Base64.getDecoder().decode(publicKeyB64), 0))
        val bytes = payload.toByteArray(Charsets.UTF_8)
        signer.update(bytes, 0, bytes.size)
        if (signer.verifySignature(java.util.Base64.getDecoder().decode(sigB64))) JSONObject(payload) else null
    }.getOrNull()

    /** El nivel que vale ahora: 0 si caducó; el aviso, sólo [ttlHours] desde que se vio por primera vez. */
    fun effective(p: JSONObject, firstSeenMs: Long, nowMs: Long): State {
        val expired = p.optLong("expiresAt") * 1000 < nowMs
        val ttl = if (p.isNull("ttlHours")) null else p.optLong("ttlHours")
        val aged = ttl != null && nowMs > firstSeenMs + ttl * 3_600_000
        val level = if (expired || aged) 0 else p.optInt("level").coerceIn(0, 3)
        return State(level, if (level == 0) "" else p.optString("message"), p.optLong("counter"))
    }

    /** Al arrancar: el último estado válido guardado (sin red también vale, hasta que caduque). */
    fun load(c: Context, nowMs: Long = System.currentTimeMillis()) {
        val p = prefs(c)
        val payload = p.getString("payload", null) ?: return
        val json = runCatching { JSONObject(payload) }.getOrNull() ?: return
        _state.value = effective(json, p.getLong("firstSeen", nowMs), nowMs)
    }

    /** Pide el estado al Worker (al abrir la app). Cualquier fallo deja el estado como estaba. */
    suspend fun refresh(c: Context, nowMs: Long = System.currentTimeMillis()) = withContext(Dispatchers.IO) {
        val body = runCatching {
            YTClient.http.newCall(Request.Builder().url(URL).build()).execute().use { if (it.code == 200) it.body?.string() else null }
        }.getOrNull() ?: return@withContext
        accept(c, body, nowMs)
    }

    /** Acepta un sobre { payload, sig } si está bien firmado y su contador no es viejo. */
    fun accept(c: Context, envelope: String, nowMs: Long, publicKeyB64: String = PUBLIC_KEY): Boolean {
        val e = runCatching { JSONObject(envelope) }.getOrNull() ?: return false
        val payload = e.optString("payload")
        val p = verify(payload, e.optString("sig"), publicKeyB64) ?: return false
        val prefs = prefs(c)
        val counter = p.optLong("counter")
        val last = prefs.getLong("counter", 0)
        if (counter < last) return false // anti-rollback
        val firstSeen = if (counter == last) prefs.getLong("firstSeen", nowMs) else nowMs
        prefs.edit().putString("payload", payload).putLong("counter", counter).putLong("firstSeen", firstSeen).apply()
        _state.value = effective(p, firstSeen, nowMs)
        return true
    }
}

/**
 * Botón de pánico de Pear Dev (Fase 4): publica uno de los estados prefirmados en el PC, con contraseña y código
 * TOTP. El Worker no puede firmar nada; sólo publica lo firmado. Sólo existe en la variante dev.
 */
object Panic {
    private const val BASE = "https://pear-music-estado.8toxbox8-69a.workers.dev/panico"

    /** Respuesta del Worker: código HTTP y su JSON. */
    suspend fun call(path: String, body: JSONObject): Pair<Int, JSONObject> = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(BASE + path).post(body.toString().toRequestBody("application/json".toMediaType())).build()
        runCatching {
            YTClient.http.newCall(req).execute().use { it.code to (runCatching { JSONObject(it.body?.string().orEmpty()) }.getOrNull() ?: JSONObject()) }
        }.getOrElse { 0 to JSONObject().put("error", L("Sin conexión con el servidor de estado.")) }
    }
}
