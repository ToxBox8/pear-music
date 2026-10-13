package app.libremusic.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Playlist local. Mismos campos que `Playlist` en iOS (Store.swift). */
data class Playlist(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val name: String,
    val songs: List<Song> = emptyList(),
    val icon: String? = null, // SF Symbol en iOS; se conserva al importar/exportar
    val tint: Int? = null,
    /** Si es un álbum guardado («Tus álbumes»): no sale en Playlists. docs/LIBRARY_FORMAT.md */
    val album: AlbumInfo? = null,
) {
    val isAlbum: Boolean get() = album != null

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("songs", songsToJson(songs))
        .apply {
            icon?.let { put("icon", it) }
            tint?.let { put("tint", it) }
            album?.let { put("album", it.toJson()) }
        }

    companion object {
        fun fromJson(o: JSONObject) = Playlist(
            id = o.optString("id").ifEmpty { UUID.randomUUID().toString().uppercase() },
            name = o.optString("name").ifEmpty { "Playlist" },
            songs = songsFromJson(o.optJSONArray("songs")),
            icon = if (o.has("icon") && !o.isNull("icon")) o.optString("icon") else null,
            tint = if (o.has("tint") && !o.isNull("tint")) o.optInt("tint") else null,
            album = o.optJSONObject("album")?.let(AlbumInfo::fromJson),
        )
    }
}

/** Datos de un álbum de YouTube Music guardado como lista. Mismo formato que `AlbumInfo` en iOS. */
data class AlbumInfo(val browseId: String, val artist: String? = null, val year: String? = null) {
    /** «Artista · 2024», lo que haya. */
    val line: String get() = listOfNotNull(artist, year).joinToString(" · ")

    fun toJson(): JSONObject = JSONObject().put("browseId", browseId).apply {
        artist?.let { put("artist", it) }
        year?.let { put("year", it) }
    }

    companion object {
        fun fromJson(o: JSONObject): AlbumInfo? {
            val id = o.optString("browseId").ifEmpty { return null }
            fun opt(k: String) = if (o.has(k) && !o.isNull(k)) o.optString(k).ifEmpty { null } else null
            return AlbumInfo(id, opt("artist"), opt("year"))
        }

        /** Del subtítulo de YouTube Music: «Álbum • Artista • 2024» o «Artista • 2024». */
        fun from(browseId: String, subtitle: String): AlbumInfo {
            val parts = subtitle.split(" • ").map { it.trim() }
                .filter { it.isNotEmpty() && it !in setOf("Álbum", "Album", "Single", "EP") }
            val last = parts.lastOrNull()
            return if (last != null && last.length == 4 && last.all { it.isDigit() }) {
                AlbumInfo(browseId, parts.dropLast(1).firstOrNull(), last)
            } else {
                AlbumInfo(browseId, parts.firstOrNull(), null)
            }
        }
    }
}

internal fun songsToJson(songs: List<Song>): JSONArray = JSONArray().apply { songs.forEach { put(it.toJson()) } }

internal fun songsFromJson(arr: JSONArray?): List<Song> {
    if (arr == null) return emptyList()
    return (0 until arr.length()).mapNotNull { i -> arr.optJSONObject(i)?.let { runCatching { Song.fromJson(it) }.getOrNull() } }
}

data class LibraryData(
    val favorites: List<Song> = emptyList(),
    val playlists: List<Playlist> = emptyList(),
    val recents: List<Song> = emptyList(),
) {
    /** Las playlists del usuario, sin los álbumes guardados (ésos van en «Tus álbumes»). */
    val userPlaylists: List<Playlist> get() = playlists.filterNot { it.isAlbum }
    /** «Tus álbumes»: los álbumes guardados o descargados desde su página, el último primero. */
    val albums: List<Playlist> get() = playlists.filter { it.isAlbum }.asReversed()
    fun album(browseId: String): Playlist? = playlists.firstOrNull { it.album?.browseId == browseId }

    /** Formato `library.json` de iOS; ver docs/LIBRARY_FORMAT.md. */
    fun toJson(): JSONObject = JSONObject()
        .put("favorites", songsToJson(favorites))
        .put("playlists", JSONArray().apply { playlists.forEach { put(it.toJson()) } })
        .put("recents", songsToJson(recents))

    companion object {
        const val MAX_RECENTS = 40

        fun fromJson(o: JSONObject) = LibraryData(
            favorites = songsFromJson(o.optJSONArray("favorites")),
            playlists = o.optJSONArray("playlists")?.let { arr ->
                (0 until arr.length()).mapNotNull { arr.optJSONObject(it)?.let(Playlist::fromJson) }
            }.orEmpty(),
            recents = songsFromJson(o.optJSONArray("recents")),
        )
    }

    /** Une otra biblioteca sin duplicar: canciones por id, playlists por id. */
    fun merge(other: LibraryData): LibraryData {
        val favIds = favorites.map { it.id }.toHashSet()
        val playlistIds = playlists.map { it.id }.toHashSet()
        val recentIds = recents.map { it.id }.toHashSet()
        return copy(
            favorites = favorites + other.favorites.filter { favIds.add(it.id) },
            playlists = playlists + other.playlists.filter { playlistIds.add(it.id) },
            recents = (recents + other.recents.filter { recentIds.add(it.id) }).take(MAX_RECENTS),
        )
    }
}

/**
 * Biblioteca guardada en el dispositivo (equivalente a `Library` de Store.swift en iOS).
 * Se guarda en `library.json` con el mismo formato que iOS.
 */
class Library(context: Context) {
    private val file = File(context.filesDir, "library.json")
    /** Fotos de portada de las playlists: covers/<id>.jpg, como Documents/covers en iOS. */
    private val coversDir = File(context.filesDir, "covers").apply { mkdirs() }

    /** Sube cada vez que cambia una foto de portada, para que la interfaz la vuelva a leer. */
    private val _coverVersion = MutableStateFlow(0)
    val coverVersion: StateFlow<Int> = _coverVersion.asStateFlow()
    private val legacyFavorites = File(context.filesDir, "favorites.json") // versión 0.2.0
    private val _data = MutableStateFlow(load())
    val data: StateFlow<LibraryData> = _data.asStateFlow()

    private fun update(change: (LibraryData) -> LibraryData) {
        val next = change(_data.value)
        _data.value = next
        file.writeText(next.toJson().toString())
    }

    // region Favoritos

    fun isFavorite(id: String): Boolean = _data.value.favorites.any { it.id == id }

    fun toggleFavorite(song: Song) = update { d ->
        if (d.favorites.any { it.id == song.id }) {
            d.copy(favorites = d.favorites.filterNot { it.id == song.id })
        } else {
            d.copy(favorites = listOf(song) + d.favorites)
        }
    }

    // endregion

    // region Recientes

    fun markPlayed(song: Song) = update { d ->
        d.copy(recents = (listOf(song) + d.recents.filterNot { it.id == song.id }).take(LibraryData.MAX_RECENTS))
    }

    // endregion

    // region Playlists

    fun createPlaylist(name: String, songs: List<Song> = emptyList()): Playlist {
        val playlist = Playlist(name = name.trim().ifEmpty { "Playlist" }, songs = songs)
        update { it.copy(playlists = it.playlists + playlist) }
        return playlist
    }

    fun deletePlaylist(id: String) {
        update { d -> d.copy(playlists = d.playlists.filterNot { it.id == id }) }
        coverFile(id).delete()
        _coverVersion.value++
    }

    /** Cambia nombre, icono o color de una playlist. */
    fun updatePlaylist(id: String, change: (Playlist) -> Playlist) = update { d ->
        d.copy(playlists = d.playlists.map { if (it.id == id) change(it) else it })
    }

    fun coverFile(id: String): File = File(coversDir, "$id.jpg")

    /** Guarda la foto reducida a 700 px (JPEG), como iOS; null la quita. */
    fun setCover(id: String, jpegOrImage: ByteArray?) {
        val f = coverFile(id)
        if (jpegOrImage == null) {
            f.delete()
        } else {
            val bmp = android.graphics.BitmapFactory.decodeByteArray(jpegOrImage, 0, jpegOrImage.size) ?: return
            val scale = minOf(1f, 700f / maxOf(bmp.width, bmp.height))
            val out = if (scale < 1f) {
                android.graphics.Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true)
            } else {
                bmp
            }
            f.outputStream().use { out.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, it) }
        }
        _coverVersion.value++
    }

    /** Crea una playlist ya rellena (guardar un álbum, importar). Color al azar, como iOS. */
    fun importPlaylist(name: String, songs: List<Song>, cover: ByteArray? = null, album: AlbumInfo? = null): Playlist {
        val playlist = Playlist(name = name.trim().ifEmpty { "Playlist" }, songs = songs, tint = (0 until 8).random(), album = album)
        update { it.copy(playlists = it.playlists + playlist) }
        if (cover != null) setCover(playlist.id, cover)
        return playlist
    }

    fun addToPlaylist(playlistId: String, song: Song) = update { d ->
        d.copy(
            playlists = d.playlists.map { p ->
                if (p.id == playlistId && p.songs.none { it.id == song.id }) p.copy(songs = p.songs + song) else p
            },
        )
    }

    fun removeFromPlaylist(playlistId: String, songId: String) = update { d ->
        d.copy(
            playlists = d.playlists.map { p ->
                if (p.id == playlistId) p.copy(songs = p.songs.filterNot { it.id == songId }) else p
            },
        )
    }

    // endregion

    // region Exportar / importar

    fun exportJson(): String = _data.value.toJson().toString(2)

    /** Añade lo que no estuviera ya. Devuelve cuántas canciones favoritas y playlists se han añadido. */
    fun importJson(text: String): Pair<Int, Int> {
        val incoming = LibraryData.fromJson(JSONObject(text))
        val before = _data.value
        update { it.merge(incoming) }
        val after = _data.value
        return (after.favorites.size - before.favorites.size) to (after.playlists.size - before.playlists.size)
    }

    // endregion

    private fun load(): LibraryData {
        runCatching { return LibraryData.fromJson(JSONObject(file.readText())) }
        // Migración desde 0.2.0, que solo guardaba favoritos.
        return runCatching { LibraryData(favorites = songsFromJson(JSONArray(legacyFavorites.readText()))) }
            .getOrDefault(LibraryData())
    }
}
