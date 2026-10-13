package app.libremusic.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * «Novedades de tus artistas» en Inicio: lo que han sacado este año (o el anterior, en enero y febrero) los artistas
 * que más escuchas. Sale de la página de cada artista en YouTube Music, que sólo da el año. Se guarda un día
 * (`cache/releases.json`) para no repetir 16 peticiones cada vez que se abre Inicio. Igual que `Releases` en iOS.
 */
object Releases {
    const val ARTISTS = 8
    const val MAX = 12
    private const val TTL_MS = 24L * 3600 * 1000

    /** Los [n] artistas que más escuchas: escuchas de las estadísticas + canciones guardadas. */
    fun topArtists(saved: List<Song>, plays: PlayStats.Data, n: Int = ARTISTS): List<String> {
        val score = mutableMapOf<String, Int>()
        saved.forEach { score.merge(app.libremusic.ui.primaryArtist(it.artist), 1, Int::plus) }
        plays.plays.forEach { p -> plays.songs[p.id]?.let { score.merge(app.libremusic.ui.primaryArtist(it.artist), 2, Int::plus) } }
        return score.filterKeys { it != "Desconocido" }.entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key.lowercase() })
            .take(n).map { it.key }
    }

    /** Año mínimo que cuenta como novedad: este año, o también el pasado en enero y febrero. */
    fun minYear(cal: Calendar = Calendar.getInstance()): Int =
        cal.get(Calendar.YEAR) - if (cal.get(Calendar.MONTH) <= Calendar.FEBRUARY) 1 else 0

    /** Año de «Single • Artista • 2026». */
    fun yearOf(c: RemoteCollection): Int? = c.subtitle.split(" • ").lastOrNull()?.trim()?.toIntOrNull()

    /** Lanzamientos recientes de cada artista, intercalados (uno de cada artista por turno) y como mucho [MAX]. */
    fun pick(byArtist: List<List<RemoteCollection>>, minYear: Int): List<RemoteCollection> {
        val lists = byArtist.map { l -> l.filter { (yearOf(it) ?: 0) >= minYear }.sortedByDescending { yearOf(it) } }
        val out = mutableListOf<RemoteCollection>()
        var i = 0
        while (out.size < MAX && lists.any { it.size > i }) {
            lists.forEach { l -> l.getOrNull(i)?.let { if (out.none { o -> o.id == it.id }) out += it } }
            i++
        }
        return out.take(MAX)
    }

    suspend fun load(context: Context, artists: List<String>, force: Boolean = false): List<RemoteCollection> = withContext(Dispatchers.IO) {
        if (artists.isEmpty()) return@withContext emptyList()
        val file = File(context.cacheDir, "releases.json")
        val key = artists.joinToString("|")
        if (!force && file.exists() && System.currentTimeMillis() - file.lastModified() < TTL_MS) {
            runCatching {
                val o = JSONObject(file.readText())
                if (o.optString("key") == key) return@withContext decode(o.getJSONArray("items"))
            }
        }
        val pages = coroutineScope {
            artists.map { name ->
                async {
                    runCatching {
                        val folded = LocalSearch.fold(name)
                        val found = YTClient.searchArtists(name)
                        val a = found.firstOrNull { LocalSearch.fold(it.name) == folded } ?: return@runCatching emptyList()
                        val page = YTClient.artist(a)
                        page.albums + page.singles
                    }.getOrDefault(emptyList())
                }
            }.awaitAll()
        }
        val items = pick(pages, minYear())
        runCatching { file.writeText(JSONObject().put("key", key).put("items", encode(items)).toString()) }
        items
    }

    private fun encode(l: List<RemoteCollection>) = JSONArray(l.map {
        JSONObject().put("id", it.id).put("title", it.title).put("subtitle", it.subtitle).put("thumbnail", it.thumbnail ?: JSONObject.NULL)
    })

    private fun decode(a: JSONArray) = (0 until a.length()).map { i ->
        a.getJSONObject(i).let { RemoteCollection(it.getString("id"), it.getString("title"), it.getString("subtitle"), it.optString("thumbnail").takeIf { t -> t.isNotEmpty() && t != "null" }) }
    }
}
