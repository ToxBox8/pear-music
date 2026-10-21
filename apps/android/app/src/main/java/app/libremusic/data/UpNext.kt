package app.libremusic.data

/**
 * Cola de verdad (sugerencia del ticket 7): lo que se añade a la cola suena justo después de la canción actual y, si
 * ya habías añadido otras, detrás de ellas, no al final de la playlist o de la radio. [queued] son los ids añadidos así
 * que aún no han sonado. Igual que `UpNext` en iOS.
 */
object UpNext {
    /** Dónde meter una canción nueva: tras la actual, saltando las que ya están en la cola. */
    fun insertAt(ids: List<String>, current: Int, queued: Set<String>): Int {
        var at = (current + 1).coerceIn(0, ids.size)
        while (at < ids.size && ids[at] in queued) at++
        return at
    }
}
