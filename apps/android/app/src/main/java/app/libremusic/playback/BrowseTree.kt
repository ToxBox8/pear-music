package app.libremusic.playback

import app.libremusic.data.LibraryData
import app.libremusic.data.Song

/**
 * Árbol de navegación para Android Auto y otros navegadores de medios:
 *   root → Favoritas · Descargadas · Recientes · Playlists → playlist:<id>
 * Las canciones llevan el id "<carpeta>/<videoId>" para poder reproducir la carpeta entera
 * empezando por la elegida.
 */
object BrowseTree {
    const val ROOT = "root"
    const val FAVORITES = "favorites"
    const val DOWNLOADS = "downloads"
    const val RECENTS = "recents"
    const val PLAYLISTS = "playlists"
    private const val PLAYLIST_PREFIX = "playlist:"

    val topFolders = listOf(FAVORITES, DOWNLOADS, RECENTS, PLAYLISTS)

    fun playlistFolder(id: String) = "$PLAYLIST_PREFIX$id"

    fun leafId(folder: String, videoId: String) = "$folder/$videoId"

    /** "<carpeta>/<videoId>" → (carpeta, videoId); null si es un videoId suelto. */
    fun parseLeaf(mediaId: String): Pair<String, String>? {
        val slash = mediaId.lastIndexOf('/')
        if (slash <= 0 || slash == mediaId.length - 1) return null
        return mediaId.substring(0, slash) to mediaId.substring(slash + 1)
    }

    /** Canciones de una carpeta (null si la carpeta no existe o no es de canciones). */
    fun songsIn(folder: String, library: LibraryData, downloads: List<Song>): List<Song>? = when {
        folder == FAVORITES -> library.favorites
        folder == DOWNLOADS -> downloads
        folder == RECENTS -> library.recents
        folder.startsWith(PLAYLIST_PREFIX) ->
            library.playlists.firstOrNull { it.id == folder.removePrefix(PLAYLIST_PREFIX) }?.songs
        else -> null
    }
}
