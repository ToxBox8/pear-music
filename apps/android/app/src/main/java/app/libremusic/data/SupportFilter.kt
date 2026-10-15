package app.libremusic.data

import java.text.Normalizer

/**
 * Primera capa contra reportes no genuinos, antes de gastar el envío: las mismas reglas que el Worker
 * (`services/soporte/src/spam.js`: texto sin sentido, repetición e insultos). Igual que `SupportFilter` en iOS.
 * Si algo cambia allí, se cambia aquí y en iOS en el mismo commit. Devuelve null si se puede enviar, o el motivo.
 */
object SupportFilter {
    private val VOWELS = Regex("[aeiouáéíóúüàèìòùâêîôûäëïöy]", RegexOption.IGNORE_CASE)
    private val STRONG = listOf(
        "hijo de puta", "hija de puta", "hijoputa", "subnormal", "retrasado", "gilipollas", "malparido", "maricon",
        "puta madre que te pario", "me cago en tu", "muerete", "ojala te mueras", "te voy a matar", "kill yourself",
        "kys", "son of a bitch", "motherfucker", "retard", "faggot",
    )
    private val MILD = setOf(
        "puta", "puto", "mierda", "joder", "cabron", "cabrona", "imbecil", "idiota", "estupido", "estupida", "tonto",
        "tonta", "pendejo", "pendeja", "capullo", "zorra", "coño", "cono", "polla", "fuck", "fucking", "shit", "bitch",
        "asshole", "dick", "cunt", "stupid", "idiot", "moron",
    )

    private fun plain(s: String) = Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")

    fun problem(raw: String): String? = textProblem(raw) ?: abuseProblem(raw)

    fun textProblem(raw: String): String? {
        val text = raw.trim()
        val urls = Regex("https?://|www\\.", RegexOption.IGNORE_CASE).findAll(text).count()
        if (urls > 2) return "Demasiados enlaces. Cuenta qué ha pasado con tus palabras."
        val noUrls = text.replace(Regex("\\S*(https?://|www\\.)\\S*", RegexOption.IGNORE_CASE), " ")
        val letters = Regex("\\p{L}").findAll(noUrls).count()
        val visible = noUrls.replace(Regex("\\s"), "").length
        if (visible == 0 || letters.toDouble() / visible < 0.5) return "El texto no se entiende. Cuenta qué ha pasado con palabras."
        if (Regex("(.)\\1{5,}").containsMatchIn(noUrls)) return "El texto no se entiende (hay letras repetidas). Cuenta qué ha pasado."
        val real = Regex("\\p{L}+").findAll(noUrls.lowercase()).map { it.value }.filter { it.length >= 2 }.toList()
        if (real.size < 3) return "Cuenta un poco más qué ha pasado (al menos una frase)."
        val distinct = real.toSet().size
        if (distinct < minOf(3, real.size) || (real.size >= 6 && distinct.toDouble() / real.size < 0.3)) {
            return "El texto se repite mucho. Cuenta qué ha pasado."
        }
        val odd = real.count { (it.length >= 4 && !VOWELS.containsMatchIn(it)) || Regex("[^aeiouáéíóúüy\\s]{5,}", RegexOption.IGNORE_CASE).containsMatchIn(it) }
        if (odd.toDouble() / real.size > 0.34) return "El texto no se entiende. Cuenta qué ha pasado con palabras."
        val vowels = Regex("[aeiouáéíóúü]", RegexOption.IGNORE_CASE).findAll(noUrls).count()
        if (letters >= 20 && (vowels.toDouble() / letters < 0.2 || vowels.toDouble() / letters > 0.75)) {
            return "El texto no se entiende. Cuenta qué ha pasado con palabras."
        }
        return null
    }

    fun abuseProblem(raw: String): String? {
        val text = plain(raw)
        if (STRONG.any { text.contains(it) }) return "El mensaje tiene insultos. Cuéntanos qué ha fallado sin ellos y lo miramos encantados."
        val words = Regex("\\p{L}+").findAll(text).map { it.value }.toList()
        val mild = words.count { it in MILD }
        if (mild >= 3 || (words.isNotEmpty() && mild.toDouble() / words.size > 0.15)) {
            return "El mensaje tiene demasiadas palabrotas. Cuéntanos qué ha fallado con calma y lo miramos."
        }
        return null
    }
}
