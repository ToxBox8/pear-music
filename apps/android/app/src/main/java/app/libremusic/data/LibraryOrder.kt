package app.libremusic.data

/**
 * Orden del carrusel de Playlists (igual que `LibraryOrder` en iOS). Las claves son el id de cada
 * playlist y [DOWNLOADS] / [FAVORITES] para las listas automáticas.
 *
 * - [sort]: "recent", "name" (A-Z), "nameDesc" (Z-A), "count" o "custom" (a mano, con [order]).
 * - [smartInPlaylists]: Descargadas y Favoritos van en el carrusel (si no, en «Tu música»).
 */
object LibraryOrder {
    const val DOWNLOADS = "downloads"
    const val FAVORITES = "favorites"

    fun keys(playlists: List<Playlist>, sort: String, order: List<String>, smartInPlaylists: Boolean): List<String> {
        val smart = if (smartInPlaylists) listOf(DOWNLOADS, FAVORITES) else emptyList()
        val byRecent = playlists.reversed().map { it.id }
        if (sort == "custom") {
            val all = smart + byRecent
            val kept = order.filter { it in all }.distinct()
            // Lo nuevo (una playlist recién creada o importada) va al final del orden propio.
            return kept + all.filter { it !in kept }
        }
        val sorted = when (sort) {
            "name" -> playlists.sortedBy { it.name.lowercase() }
            "nameDesc" -> playlists.sortedByDescending { it.name.lowercase() }
            "count" -> playlists.sortedByDescending { it.songs.size }
            else -> playlists.reversed()
        }
        return smart + sorted.map { it.id }
    }
}
