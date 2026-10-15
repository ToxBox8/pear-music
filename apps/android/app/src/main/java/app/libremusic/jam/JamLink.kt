package app.libremusic.jam

import java.net.URI

/**
 * Código y enlace del Jam, compatibles con la app iOS (`JamService.code(from:)`).
 * Especificación: docs/JAM_PROTOCOL.md.
 */
object JamLink {
    /** Sin 0, O, 1 ni I para evitar confusiones al dictar el código. */
    const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    const val CODE_LENGTH = 6

    /** Mayúsculas, solo caracteres del alfabeto, como mucho 6. */
    fun normalize(raw: String): String =
        raw.uppercase().filter { it in ALPHABET }.take(CODE_LENGTH)

    /** Acepta `libremusic://jam/ABC234` o el código suelto. Devuelve null si no es válido. */
    fun codeFrom(text: String?): String? {
        if (text.isNullOrBlank()) return null
        val trimmed = text.trim()
        val uri = runCatching { URI(trimmed) }.getOrNull()
        if (uri?.scheme == "libremusic" && uri.host == "jam") {
            val last = uri.path.orEmpty().trim('/').substringAfterLast('/')
            return normalize(last).takeIf { it.length == CODE_LENGTH }
        }
        val code = normalize(trimmed)
        return code.takeIf { it.length == CODE_LENGTH && trimmed.length == CODE_LENGTH }
    }

    /**
     * Enlace del QR. Con [direct] («192.168.1.20:41234», la dirección del anfitrión en la Wi-Fi) quien lo escanea se
     * conecta directamente sin esperar a la búsqueda de la red (Fase 3.2). Las versiones viejas sólo leen la ruta,
     * así que ignoran `?h=`.
     */
    fun link(code: String, direct: String? = null): String =
        "libremusic://jam/$code" + (direct?.let { "?h=$it" } ?: "")

    private val DIRECT = Regex("^(\\d{1,3}(?:\\.\\d{1,3}){3}):(\\d{2,5})$")

    /** La dirección directa del enlace (IPv4 privada y puerto), o null. Sólo redes locales: nunca una IP pública. */
    fun directFrom(text: String?): Pair<String, Int>? {
        val query = runCatching { URI(text?.trim() ?: return null).rawQuery }.getOrNull() ?: return null
        val h = query.split("&").firstOrNull { it.startsWith("h=") }?.removePrefix("h=") ?: return null
        val m = DIRECT.matchEntire(java.net.URLDecoder.decode(h, "UTF-8")) ?: return null
        val ip = m.groupValues[1]
        val port = m.groupValues[2].toIntOrNull()?.takeIf { it in 1024..65535 } ?: return null
        val o = ip.split(".").map { it.toInt() }
        if (o.any { it > 255 }) return null
        val private = o[0] == 10 || (o[0] == 172 && o[1] in 16..31) || (o[0] == 192 && o[1] == 168)
        return if (private) ip to port else null
    }
}
