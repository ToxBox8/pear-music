package app.libremusic.data

import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.zip.Deflater
import java.util.zip.Inflater

/**
 * Compartir una playlist con un QR, sin servidor (0.6 de x.1.1). El QR es un enlace
 * `libremusic://playlist?v=1&d=<datos>`; `datos` = JSON `{"n": nombre, "i": ids seguidos (11 caracteres cada uno),
 * "ic": icono, "t": color}` comprimido con deflate sin cabecera y en base64url. Sólo van los ids, en orden: el título
 * y el artista se piden a YouTube Music al importar (así caben hasta [MAX_SONGS] en un QR que se lee desde otra
 * pantalla). Una foto propia no viaja. Formato: docs/LIBRARY_FORMAT.md › Compartir. Igual que `PlaylistShare` en iOS.
 */
object PlaylistShare {
    const val MAX_SONGS = 150
    private const val MAX_NAME = 100
    private const val PREFIX = "libremusic://playlist?v=1&d="
    private val ID = Regex("^[A-Za-z0-9_-]{11}$")

    data class Payload(val name: String, val ids: List<String>, val icon: String? = null, val tint: Int? = null)

    /** El enlace de la playlist, o null si no hay canciones o son demasiadas para un QR. */
    fun link(name: String, ids: List<String>, icon: String?, tint: Int?): String? {
        if (ids.isEmpty() || ids.size > MAX_SONGS || ids.any { !ID.matches(it) }) return null
        val o = JSONObject().put("n", name.take(MAX_NAME)).put("i", ids.joinToString(""))
        icon?.let { o.put("ic", it.take(64)) }
        tint?.let { o.put("t", it) }
        return PREFIX + java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(deflate(o.toString().toByteArray()))
    }

    /** Lo que trae un enlace (o el texto de un QR), o null si no es una playlist válida. Nunca lanza. */
    fun decode(text: String?): Payload? = runCatching {
        val t = text?.trim() ?: return null
        if (!t.startsWith(PREFIX)) return null
        val data = java.util.Base64.getUrlDecoder().decode(t.removePrefix(PREFIX).substringBefore('&').substringBefore('#'))
        val o = JSONObject(String(inflate(data)))
        val joined = o.getString("i")
        if (joined.isEmpty() || joined.length % 11 != 0 || joined.length / 11 > MAX_SONGS) return null
        val ids = joined.chunked(11)
        if (ids.any { !ID.matches(it) }) return null
        Payload(o.optString("n").take(MAX_NAME), ids, o.optString("ic").ifEmpty { null }?.take(64), if (o.has("t")) o.optInt("t") else null)
    }.getOrNull()

    /** El enlace recibido al abrir la app (cámara del sistema o «Compartir enlace»): la raíz enseña la vista previa. */
    val incoming = MutableStateFlow<Payload?>(null)
    fun receive(text: String?) { decode(text)?.let { incoming.value = it } }

    private fun deflate(bytes: ByteArray): ByteArray {
        val d = Deflater(Deflater.BEST_COMPRESSION, true).apply { setInput(bytes); finish() }
        val out = ByteArrayOutputStream()
        val buf = ByteArray(1024)
        while (!d.finished()) out.write(buf, 0, d.deflate(buf))
        d.end()
        return out.toByteArray()
    }

    /** Con tope: unos datos maliciosos no pueden inflarse a gigas. */
    private fun inflate(bytes: ByteArray, max: Int = 64 * 1024): ByteArray {
        val i = Inflater(true).apply { setInput(bytes) }
        val out = ByteArrayOutputStream()
        val buf = ByteArray(1024)
        while (!i.finished()) {
            val n = i.inflate(buf)
            if (n == 0 && (i.needsInput() || i.needsDictionary())) break
            out.write(buf, 0, n)
            if (out.size() > max) throw IllegalArgumentException("demasiado grande")
        }
        i.end()
        return out.toByteArray()
    }
}
