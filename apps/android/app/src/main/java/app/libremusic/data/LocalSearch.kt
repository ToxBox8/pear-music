package app.libremusic.data

import java.text.Normalizer

/**
 * Filtro de listas de la biblioteca (Playlists, Artistas, Álbumes…): ignora mayúsculas y acentos
 * («beyonce» encuentra «Beyoncé») y exige todas las palabras en cualquier orden. Mismas reglas que
 * `LocalSearch` en iOS.
 */
object LocalSearch {
    private val marks = Regex("\\p{Mn}+")

    fun fold(s: String): String = marks.replace(Normalizer.normalize(s, Normalizer.Form.NFD), "").lowercase().trim()

    fun words(query: String): List<String> = fold(query).split(' ').filter { it.isNotEmpty() }

    /** [folded]: el texto de cada elemento ya pasado por [fold] (se calcula una vez por lista, no por letra). */
    fun <T> filter(items: List<T>, folded: List<String>, query: String): List<T> {
        val w = words(query)
        if (w.isEmpty()) return items
        return items.filterIndexed { i, _ -> w.all { folded[i].contains(it) } }
    }

    fun <T> filter(items: List<T>, query: String, text: (T) -> String): List<T> = filter(items, items.map { fold(text(it)) }, query)
}
