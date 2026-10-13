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

    fun link(code: String): String = "libremusic://jam/$code"
}
