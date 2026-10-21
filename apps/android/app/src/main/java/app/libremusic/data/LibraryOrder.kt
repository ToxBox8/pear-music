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

    /**
     * Mete el orden [moved] (sólo playlists, el de la cuadrícula de Playlists) en el orden completo [full] sin mover
     * Descargadas ni Favoritos (2.9 de x.1.1).
     */
    fun merge(full: List<String>, moved: List<String>): List<String> {
        val set = moved.toSet()
        val next = moved.iterator()
        return full.map { if (it in set && next.hasNext()) next.next() else it }
    }

    /** «Fijados» (x.1.1): siempre en el orden propio; lo recién fijado va al final. */
    fun pinned(pinned: List<Playlist>, order: List<String>): List<Playlist> = albums(pinned, "custom", order)

    /** «Tus álbumes»: como se guardaron o, con «custom», el orden propio; lo nuevo va al final. */
    fun albums(albums: List<Playlist>, sort: String, order: List<String>): List<Playlist> {
        if (sort != "custom") return albums
        val byId = albums.associateBy { it.id }
        val kept = order.filter { it in byId }.distinct()
        return kept.mapNotNull { byId[it] } + albums.filter { it.id !in kept }
    }
}
