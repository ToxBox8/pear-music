package app.libremusic.data

import okhttp3.Request
import org.json.JSONObject
import java.net.URLEncoder
import java.text.Normalizer

/**
 * Discografía completa de un artista (Fase 3.1; lo eligió Toxbox: «las dos»). La base es YouTube Music
 * («Ver todo», lo que se puede escuchar); se completa con **MusicBrainz** (API pública y documentada,
 * https://musicbrainz.org/doc/MusicBrainz_API): los discos oficiales que YouTube Music no tiene salen como «No
 * disponible para escuchar». MusicBrainz pide un User-Agent con contacto y como mucho 1 petición por segundo.
 * Igual que `Discography` en iOS.
 */
object Discography {
    private const val MB = "https://musicbrainz.org/ws/2"
    private const val UA = "PearMusic/1.0 ( https://github.com/ToxBox8/pear-music )"

    enum class Kind { Album, Single }

    /** Un disco de MusicBrainz: título, año y si es álbum o single/EP. */
    data class MbRelease(val title: String, val year: String, val kind: Kind)

    /** Un disco de la discografía: o se puede escuchar (de YouTube Music) o sólo se sabe que existe. */
    sealed interface Item {
        data class Playable(val collection: RemoteCollection) : Item
        data class Missing(val release: MbRelease) : Item
    }

    private val cache = HashMap<String, List<MbRelease>>()
    @Volatile private var lastCall = 0L

    /** Minúsculas, sin tildes, sin «(feat. …)», «- Single», signos ni espacios: para comparar títulos y nombres. */
    fun normalize(s: String): String = Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD)
        .replace(Regex("\\p{Mn}+"), "")
        .replace(Regex("\\((feat|ft|with|con)[^)]*\\)|\\[(feat|ft)[^]]*]|\\s-\\s(single|ep)$"), "")
        .replace(Regex("[^\\p{L}\\p{N}]+"), "")

    private fun get(url: String): JSONObject? {
        synchronized(this) {
            val wait = 1100 - (System.currentTimeMillis() - lastCall)
            if (wait > 0) Thread.sleep(wait)
            lastCall = System.currentTimeMillis()
        }
        return runCatching {
            YTClient.http.newCall(Request.Builder().url(url).header("User-Agent", UA).header("Accept", "application/json").build())
                .execute().use { if (it.isSuccessful) JSONObject(it.body!!.string()) else null }
        }.getOrNull()
    }

    /** Discos oficiales del artista en MusicBrainz (sin recopilatorios, directos ni remezclas), o null sin red. */
    fun musicBrainz(artistName: String): List<MbRelease>? {
        val key = normalize(artistName)
        cache[key]?.let { return it }
        val q = URLEncoder.encode("artist:\"${artistName.replace("\"", "")}\"", "UTF-8")
        val found = get("$MB/artist?query=$q&limit=5&fmt=json")?.optJSONArray("artists") ?: return null
        // Sólo si el nombre coincide de verdad: mejor no completar que completar con otro artista.
        val mbid = (0 until found.length()).map { found.getJSONObject(it) }
            .firstOrNull { it.optInt("score") >= 90 && normalize(it.optString("name")) == key }?.optString("id") ?: return emptyList<MbRelease>().also { cache[key] = it }
        val out = mutableListOf<MbRelease>()
        var offset = 0
        do {
            val page = get("$MB/release-group?artist=$mbid&type=album|ep|single&limit=100&offset=$offset&fmt=json") ?: break
            val groups = page.optJSONArray("release-groups") ?: break
            for (i in 0 until groups.length()) {
                val g = groups.getJSONObject(i)
                if ((g.optJSONArray("secondary-types")?.length() ?: 0) > 0) continue
                val kind = if (g.optString("primary-type") == "Album") Kind.Album else Kind.Single
                out += MbRelease(g.optString("title"), g.optString("first-release-date").take(4), kind)
            }
            offset += groups.length()
        } while (groups.length() == 100 && offset < page.optInt("release-group-count") && offset < 400)
        cache[key] = out
        return out
    }

    /**
     * YouTube Music primero (en su orden) y detrás, de lo que MusicBrainz conoce del mismo tipo, lo que YouTube Music
     * no tiene, del más nuevo al más viejo.
     */
    fun merge(yt: List<RemoteCollection>, mb: List<MbRelease>, kind: Kind): List<Item> {
        val have = yt.map { normalize(it.title) }.toHashSet()
        val missing = mb.filter { it.kind == kind && normalize(it.title) !in have }
            .distinctBy { normalize(it.title) }
            .sortedByDescending { it.year }
        return yt.map { Item.Playable(it) } + missing.map { Item.Missing(it) }
    }
}
