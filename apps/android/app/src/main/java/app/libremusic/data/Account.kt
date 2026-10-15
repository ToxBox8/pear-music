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
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Cuenta opcional (Fase 2.1, ADR 0001): entrar con un código al correo y guardar la biblioteca en la nube
 * **cifrada en el móvil**. La clave de cifrado es la **clave de recuperación** (128 bits aleatorios, 26
 * caracteres) que sólo conoce el usuario: el servidor guarda un blob que no puede leer. Sin cuenta, la app
 * funciona igual. Igual que `Account` en iOS.
 *
 * En el móvil: el token de sesión y la clave de recuperación, cifrados con [SecureBox] en `filesDir/account`.
 */
object Account {
    const val BASE = "https://pear-music-api.8toxbox8-69a.workers.dev/v1/cuenta"
    private val JSON = "application/json".toMediaType()

    data class State(val email: String? = null, val hasKey: Boolean = false, val lastSync: Long = 0, val version: Int = 0, val cloudHasLibrary: Boolean = false)

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()
    private var dir: File? = null

    fun init(context: Context) {
        dir = File(context.filesDir, "account").apply { mkdirs() }
        _state.value = load()
    }

    // region Guardado local cifrado

    private fun read(name: String): String? = runCatching { String(SecureBox.open(File(dir, name).readBytes())) }.getOrNull()
    private fun write(name: String, value: String?) {
        val f = File(dir ?: return, name)
        if (value == null) { f.delete(); return }
        // Sin Keystore no se guarda (nunca en claro): la sesión dura hasta cerrar la app.
        runCatching { f.writeBytes(SecureBox.seal(value.toByteArray())) }
            .onFailure { Logs.w("Account", "No se pudo guardar cifrado: ${it.javaClass.simpleName}") }
    }

    private fun load(): State {
        val meta = read("meta")?.let(::JSONObject)
        return State(
            meta?.optString("email")?.ifEmpty { null }, read("key") != null, meta?.optLong("lastSync") ?: 0,
            meta?.optInt("version") ?: 0, meta?.optBoolean("cloud") ?: false,
        )
    }

    private fun saveMeta(s: State) {
        write("meta", JSONObject().put("email", s.email).put("lastSync", s.lastSync).put("version", s.version).put("cloud", s.cloudHasLibrary).toString())
        _state.value = s.copy(hasKey = read("key") != null)
    }

    private val token get() = read("token")

    // endregion

    // region Clave de recuperación y cifrado de la biblioteca

    private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ" // Crockford: sin I, L, O ni U

    /** 16 bytes aleatorios → 26 caracteres en grupos de 4 («7K2M-…»). */
    fun newRecoveryKey(): String {
        val bytes = ByteArray(16).also { SecureRandom().nextBytes(it) }
        var bits = 0
        var value = 0
        val out = StringBuilder()
        for (b in bytes) {
            value = (value shl 8) or (b.toInt() and 0xff)
            bits += 8
            while (bits >= 5) { out.append(ALPHABET[(value shr (bits - 5)) and 31]); bits -= 5 }
        }
        if (bits > 0) out.append(ALPHABET[(value shl (5 - bits)) and 31])
        return out.chunked(4).joinToString("-")
    }

    /** Normaliza lo que escribe el usuario (sin guiones ni espacios, O→0, I/L→1) o null si no es una clave. */
    fun normalizeKey(raw: String): String? {
        val k = raw.uppercase().replace(Regex("[\\s-]"), "").replace('O', '0').replace('I', '1').replace('L', '1')
        return k.takeIf { it.length == 26 && it.all { c -> c in ALPHABET } }?.chunked(4)?.joinToString("-")
    }

    private fun aesKey(recovery: String): SecretKeySpec =
        SecretKeySpec(MessageDigest.getInstance("SHA-256").digest("pear-music-library-v1:${recovery.replace("-", "")}".toByteArray()), "AES")

    fun encrypt(plain: ByteArray, recovery: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, aesKey(recovery)) }
        return java.util.Base64.getEncoder().encodeToString(byteArrayOf(1) + c.iv + c.doFinal(plain))
    }

    fun decrypt(blob: String, recovery: String): ByteArray {
        val bytes = java.util.Base64.getDecoder().decode(blob)
        require(bytes.size > 29 && bytes[0] == 1.toByte())
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, aesKey(recovery), GCMParameterSpec(128, bytes, 1, 12))
        return c.doFinal(bytes, 13, bytes.size - 13)
    }

    // endregion

    // region Servidor

    class ApiError(message: String) : Exception(message)

    private fun call(method: String, path: String, body: JSONObject? = null, auth: Boolean = false): Pair<Int, JSONObject> {
        if (Incident.restricted) throw ApiError(L("La cuenta está en pausa mientras resolvemos un incidente."))
        val b = Request.Builder().url(BASE + path)
        if (auth) b.header("Authorization", "Bearer ${token ?: throw ApiError("Vuelve a entrar en tu cuenta.")}")
        // POST y PUT necesitan cuerpo aunque no lleven datos.
        b.method(method, (body ?: if (method == "POST" || method == "PUT") JSONObject() else null)?.toString()?.toRequestBody(JSON))
        return try {
            YTClient.http.newCall(b.build()).execute().use { res ->
                res.code to (runCatching { JSONObject(res.body?.string().orEmpty()) }.getOrNull() ?: JSONObject())
            }
        } catch (e: java.io.IOException) {
            throw ApiError(L("Sin conexión. Inténtalo cuando tengas internet."))
        }
    }

    private fun Pair<Int, JSONObject>.ok(): JSONObject {
        if (first !in 200..299) throw ApiError(second.optString("error").ifEmpty { L("El servidor no responde ({0}). Prueba más tarde.", first) })
        return second
    }

    /** ¿Se pueden crear cuentas ahora? (sin red o sin servidor, no). */
    suspend fun available(): Boolean = withContext(Dispatchers.IO) {
        runCatching { call("GET", "/disponible").ok().optBoolean("available") }.getOrDefault(false)
    }

    suspend fun requestCode(email: String) = withContext(Dispatchers.IO) { call("POST", "/codigo", JSONObject().put("email", email.trim())).ok(); Unit }

    /** Entra. Devuelve si la cuenta ya tenía una biblioteca guardada (entonces hace falta la clave). */
    suspend fun signIn(email: String, code: String): Boolean = withContext(Dispatchers.IO) {
        val r = call("POST", "/entrar", JSONObject().put("email", email.trim()).put("code", code.trim())).ok()
        write("token", r.getString("token"))
        saveMeta(State(email = email.trim().lowercase(), cloudHasLibrary = r.optBoolean("hasLibrary")))
        r.optBoolean("hasLibrary")
    }

    /** Guarda la clave de recuperación (nueva o escrita por el usuario). */
    fun setRecoveryKey(key: String) {
        write("key", key)
        _state.value = _state.value.copy(hasKey = true)
    }

    fun recoveryKey(): String? = read("key")

    /** La clave escrita no abría la copia: se olvida para volver a pedirla. */
    fun setRecoveryKeyCleared() {
        write("key", null)
        _state.value = _state.value.copy(hasKey = false)
    }

    /**
     * Sube la biblioteca cifrada. Si otro móvil subió una más nueva, primero la trae y une. Con [overwrite]
     * (clave nueva: «empezar de cero»), la copia antigua de la nube, que ya no se puede abrir, se sustituye.
     */
    suspend fun upload(library: Library, overwrite: Boolean = false) = withContext(Dispatchers.IO) {
        val key = recoveryKey() ?: throw ApiError(L("Falta la clave de recuperación."))
        // Con portadas si caben en el límite de la nube (2 MB tras cifrar y pasar a base64); si no, sin ellas.
        val json = withContext(Dispatchers.Main) { library.exportJson().takeIf { it.length < 1_400_000 } ?: library.exportJson(covers = false) }
        val put = { base: Int -> call("PUT", "/biblioteca", JSONObject().put("blob", encrypt(json.toByteArray(), key)).put("baseVersion", base), auth = true) }
        var r = put(_state.value.version)
        if (r.first == 409) {
            if (overwrite) {
                r = put(r.second.optInt("version"))
            } else {
                download(library)
                r = put(_state.value.version)
            }
        }
        val v = r.ok().getInt("version")
        saveMeta(_state.value.copy(version = v, lastSync = System.currentTimeMillis(), cloudHasLibrary = true))
    }

    /** Trae la biblioteca de la nube y la une con la del móvil (no borra nada). */
    suspend fun download(library: Library): Pair<Int, Int> = withContext(Dispatchers.IO) {
        val key = recoveryKey() ?: throw ApiError(L("Falta la clave de recuperación."))
        val r = call("GET", "/biblioteca", auth = true)
        if (r.first == 404) return@withContext 0 to 0
        val j = r.ok()
        val plain = runCatching { decrypt(j.getString("blob"), key) }.getOrElse {
            throw ApiError(L("La clave de recuperación no es la de esta cuenta."))
        }
        val added = withContext(Dispatchers.Main) { library.importJson(String(plain)) }
        saveMeta(_state.value.copy(version = j.getInt("version"), lastSync = System.currentTimeMillis()))
        added
    }

    /** Cerrar sesión en este móvil (la biblioteca del móvil se queda). */
    suspend fun signOut() = withContext(Dispatchers.IO) {
        runCatching { call("POST", "/salir", auth = true) }
        clearLocal()
    }

    /** Borrar la cuenta y todo lo guardado en el servidor, al momento. */
    suspend fun delete() = withContext(Dispatchers.IO) {
        call("DELETE", "", auth = true).ok()
        clearLocal()
    }

    private fun clearLocal() {
        listOf("token", "key", "meta").forEach { write(it, null) }
        _state.value = State()
    }

    // endregion
}
