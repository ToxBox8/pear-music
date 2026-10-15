package app.libremusic.data

import org.json.JSONObject

/** Canción o vídeo de YouTube Music. Mismo modelo que `Song` en iOS (Client.swift). */
data class Song(
    val id: String, // videoId
    val title: String,
    val artist: String,
    val thumbnail: String?,
) {
    /** Misma carátula a otra resolución (las URLs de YouTube Music admiten =wN-hN). */
    fun thumb(px: Int): String? {
        val t = thumbnail ?: return null
        return if (THUMB_SIZE.containsMatchIn(t)) t.replace(THUMB_SIZE, "=w$px-h$px-l90-rj") else t
    }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("title", title)
        .put("artist", artist)
        .put("thumbnail", thumbnail ?: JSONObject.NULL)

    companion object {
        private val THUMB_SIZE = Regex("=w\\d+-h\\d+[^/]*$")

        fun fromJson(o: JSONObject): Song = Song(
            id = o.getString("id"),
            title = o.optString("title"),
            artist = o.optString("artist"),
            thumbnail = if (o.isNull("thumbnail")) null else o.optString("thumbnail").ifBlank { null },
        )
    }
}

/** Álbum, single o playlist pública de YouTube Music (se abre sin iniciar sesión). */
data class RemoteCollection(
    val id: String, // browseId: "MPREb_…" (álbum) o "VL…" (playlist)
    val title: String,
    val subtitle: String,
    val thumbnail: String?,
) {
    fun thumb(px: Int): String? = Song(id, title, subtitle, thumbnail).thumb(px)
}

/** Artista de YouTube Music (browseId "UC…"), en la búsqueda y en su página. */
data class RemoteArtist(val id: String, val name: String, val subtitle: String, val thumbnail: String?)

/** Lo que devuelve una búsqueda: canciones, álbumes (y singles/EP) y artistas, por separado. */
data class SearchResults(
    val songs: List<Song> = emptyList(),
    val albums: List<RemoteCollection> = emptyList(),
    val artists: List<RemoteArtist> = emptyList(),
) {
    val isEmpty: Boolean get() = songs.isEmpty() && albums.isEmpty() && artists.isEmpty()
}

/** Página de un artista: sus canciones más escuchadas, álbumes y singles/EP. */
data class ArtistPage(
    val name: String,
    val thumbnail: String?,
    val songs: List<Song>,
    val albums: List<RemoteCollection>,
    val singles: List<RemoteCollection>,
    /** «Ver todo» de cada sección (página de discografía de YouTube Music), si la hay. */
    val albumsMore: BrowseRef? = null,
    val singlesMore: BrowseRef? = null,
)

/** Una página de YouTube Music a la que se llega con browseId + params (p. ej. la discografía completa). */
data class BrowseRef(val browseId: String, val params: String?)

/** «Álbum • Beyoncé • 2024» → «Beyoncé · 2024»; los singles y EP conservan el tipo (como albumLine en iOS). */
fun albumLine(subtitle: String): String =
    subtitle.split(" • ").filter { it != "Álbum" && it != "Album" && it.isNotEmpty() }.joinToString(" · ")

sealed interface HomeItem {
    val key: String

    data class SongItem(val song: Song) : HomeItem {
        override val key get() = "s" + song.id
    }

    data class CollectionItem(val collection: RemoteCollection) : HomeItem {
        override val key get() = "c" + collection.id
    }
}

data class HomeShelf(val title: String, val items: List<HomeItem>)
