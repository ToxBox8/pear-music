package app.libremusic.data

import android.content.Context
import app.libremusic.BuildConfig
import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519KeyGenerationParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.json.JSONObject
import java.net.InetAddress
import java.net.ServerSocket
import java.security.SecureRandom
import java.util.Base64

/**
 * Llave del panel de telemetría (Fase 4b, sólo Pear Dev; lo eligió Toxbox: «llave en Pear Dev por cable»).
 *
 * Pear Dev tiene un par Ed25519 propio (la privada cifrada con `SecureBox`, nunca sale del móvil). La pública se pone
 * una vez en el Worker (`PANEL_PUBLIC_KEY`). Con el interruptor encendido, Pear Dev escucha **sólo en 127.0.0.1:8765**
 * y da llaves de 5 minutos a la página escondida de la web, que llega al móvil por el cable con
 * `adb forward tcp:8765 tcp:8765`. Sin el móvil enchufado no hay llave, y sin llave el Worker no enseña nada.
 * Se apaga sola a los 10 minutos. `GET /hola` sólo dice que está ahí: la web lo usa para enseñar o esconder la
 * telemetría (sin el móvil enchufado, la página es un 404 y el menú no la enseña).
 */
object PanelKey {
    const val PORT = 8765
    const val ORIGIN = "https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev"
    private const val PREFS = "panel_key"
    private const val TTL_MS = 5 * 60_000L
    private const val AUTO_OFF_MS = 10 * 60_000L

    @Volatile private var server: ServerSocket? = null
    @Volatile var until = 0L
        private set
    val running get() = server != null

    private fun privateKey(c: Context): Ed25519PrivateKeyParameters {
        val p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        p.getString("sealed", null)?.let { sealed ->
            runCatching { return Ed25519PrivateKeyParameters(SecureBox.open(Base64.getDecoder().decode(sealed)), 0) }
        }
        val gen = Ed25519KeyPairGenerator().apply { init(Ed25519KeyGenerationParameters(SecureRandom())) }
        val key = gen.generateKeyPair().private as Ed25519PrivateKeyParameters
        p.edit().putString("sealed", Base64.getEncoder().encodeToString(SecureBox.seal(key.encoded))).apply()
        return key
    }

    /** La pública en base64: va en `PANEL_PUBLIC_KEY` del Worker pear-music-api. */
    fun publicKey(c: Context): String = Base64.getEncoder().encodeToString(privateKey(c).generatePublicKey().encoded)

    /** «Panel <payload>.<firma>», en base64url, caduca en 5 min. */
    fun token(key: Ed25519PrivateKeyParameters, now: Long = System.currentTimeMillis()): String {
        val nonce = ByteArray(9).also { SecureRandom().nextBytes(it) }
        val payload = JSONObject().put("exp", now + TTL_MS).put("n", nonce.joinToString("") { "%02x".format(it) }).toString().toByteArray()
        val sig = Ed25519Signer().run { init(true, key); update(payload, 0, payload.size); generateSignature() }
        val b64u = Base64.getUrlEncoder().withoutPadding()
        return "Panel ${b64u.encodeToString(payload)}.${b64u.encodeToString(sig)}"
    }

    fun start(c: Context) {
        if (!BuildConfig.ADMIN_TOOLS || server != null) return
        val key = privateKey(c.applicationContext)
        val socket = ServerSocket(PORT, 4, InetAddress.getByName("127.0.0.1"))
        server = socket
        until = System.currentTimeMillis() + AUTO_OFF_MS
        Logs.i("PanelKey", "llave del panel encendida (127.0.0.1:$PORT, 10 min)")
        Thread {
            while (!socket.isClosed) {
                if (System.currentTimeMillis() > until) { stop(); break }
                runCatching {
                    socket.soTimeout = 1000
                    socket.accept().use { s ->
                        s.soTimeout = 3000
                        val head = s.getInputStream().bufferedReader().let { r -> generateSequence { r.readLine()?.takeIf { it.isNotEmpty() } }.take(40).toList() }
                        val first = head.firstOrNull().orEmpty()
                        val origin = head.firstOrNull { it.startsWith("Origin:", ignoreCase = true) }?.substringAfter(":")?.trim()
                        val cors = "Access-Control-Allow-Origin: $ORIGIN\r\nAccess-Control-Allow-Private-Network: true\r\nAccess-Control-Allow-Methods: GET\r\nVary: Origin\r\n"
                        val (status, body) = when {
                            origin != ORIGIN -> "403 Forbidden" to """{"error":"Sólo para la web de Pear Music."}"""
                            first.startsWith("OPTIONS ") -> "204 No Content" to ""
                            // La web pregunta esto para saber si enseña la telemetría (sin llave).
                            first.startsWith("GET /hola ") -> "200 OK" to """{"ok":true}"""
                            first.startsWith("GET /llave ") -> "200 OK" to JSONObject().put("llave", token(key)).toString()
                            else -> "404 Not Found" to "{}"
                        }
                        val bytes = body.toByteArray()
                        s.getOutputStream().write(("HTTP/1.1 $status\r\n$cors" + "Content-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n").toByteArray() + bytes)
                    }
                }
            }
        }.apply { isDaemon = true; name = "PanelKey" }.start()
    }

    fun stop() {
        server?.let { runCatching { it.close() } }
        server = null
        until = 0L
    }
}
