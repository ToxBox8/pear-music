package app.libremusic.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * «No me interesa» en Descubrir (2.7 de x.1.1). Se guarda sólo en el móvil (`reels_skip.json`: id, artista y fecha).
 * La canción no vuelve a salir; el artista baja de peso y, con 3 «No me interesa» en 30 días, sale de Descubrir otros
 * 30 días (no se veta para siempre). Igual que `ReelsSkip` en iOS.
 */
object ReelsSkip {
    data class Entry(val id: String, val artist: String, val at: Long)

    const val DAY_MS = 86_400_000L
    const val WINDOW_MS = 30 * DAY_MS
    const val ARTIST_LIMIT = 3

    private val _entries = MutableStateFlow<List<Entry>>(emptyList())
    val entries: StateFlow<List<Entry>> = _entries.asStateFlow()
    private var file: File? = null

    fun init(c: Context) {
        val f = File(c.filesDir, "reels_skip.json").also { file = it }
        _entries.value = runCatching {
            val a = JSONArray(f.readText())
            (0 until a.length()).map { a.getJSONObject(it).let { o -> Entry(o.getString("id"), o.optString("artist"), o.optLong("at")) } }
        }.getOrDefault(emptyList())
    }

    fun add(song: Song, now: Long = System.currentTimeMillis()) = save(_entries.value.filter { it.id != song.id } + Entry(song.id, primaryArtistOf(song.artist), now))
    fun remove(id: String) = save(_entries.value.filter { it.id != id })
    fun clear() = save(emptyList())

    private fun save(list: List<Entry>) {
        _entries.value = list
        file?.let { f ->
            runCatching {
                f.writeText(JSONArray(list.map { JSONObject().put("id", it.id).put("artist", it.artist).put("at", it.at) }).toString())
            }
        }
    }

    /** Fuera las canciones marcadas y las de los artistas con [ARTIST_LIMIT] marcas en los últimos 30 días. */
    fun filter(items: List<Song>, entries: List<Entry> = _entries.value, now: Long = System.currentTimeMillis()): List<Song> {
        val ids = entries.map { it.id }.toSet()
        val artists = blockedArtists(entries, now)
        return items.filter { it.id !in ids && primaryArtistOf(it.artist).lowercase() !in artists }
    }

    /** Artistas con [ARTIST_LIMIT] marcas en menos de 30 días, durante los 30 días siguientes a la última de ellas. */
    fun blockedArtists(entries: List<Entry>, now: Long): Set<String> =
        entries.filter { it.artist.isNotBlank() }.groupBy { primaryArtistOf(it.artist).lowercase() }.filterValues { list ->
            val t = list.map { it.at }.sorted()
            (ARTIST_LIMIT - 1 until t.size).any { i -> t[i] - t[i - ARTIST_LIMIT + 1] < WINDOW_MS && now - t[i] < WINDOW_MS }
        }.keys

    /** «Artista y Otro», «Artista, Otro» o «Artista feat. Otro» → «Artista» (la misma regla que `primaryArtist`). */
    fun primaryArtistOf(artist: String): String =
        artist.replace(Regex("""\s*(,| y | & | x | feat\.? | ft\.? | · ).*$""", RegexOption.IGNORE_CASE), "").trim()
}
