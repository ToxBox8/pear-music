package app.libremusic.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.text.Normalizer
import java.util.concurrent.atomic.AtomicInteger

// Importar una playlist de Apple Music desde su enlace compartido (port de AppleMusic.swift).
// La página pública incluye las pistas en un JSON ("serialized-server-data"); cada pista se busca
// después en YouTube Music. La otra vía de iOS (la app Música del iPhone) no existe en Android.

/**
 * Una canción de fuera (Apple Music, Spotify, CSV). [album] y [duration] (s) deciden entre versiones
 * (directo, remix, remaster…); [isrc], si lo hay, es el criterio principal; [explicit] distingue la versión
 * explícita de la limpia.
 */
data class AMTrack(
    val title: String,
    val artist: String,
    val album: String = "",
    val duration: Double = 0.0,
    val isrc: String? = null,
    val explicit: Boolean? = null,
)
data class AMPlaylist(val name: String, val tracks: List<AMTrack>, val artwork: String?)

class AppleMusicException(message: String) : Exception(message)

object AppleMusicImporter {
    private const val SAFARI_UA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    suspend fun fetchPublic(link: String): AMPlaylist = withContext(Dispatchers.IO) {
        val trimmed = link.trim()
        val urlString = trimmed.split(Regex("\\s+")).firstOrNull { "music.apple.com" in it } ?: trimmed
        val host = runCatching { java.net.URI(urlString).host }.getOrNull()
        if (host == null || !host.endsWith("music.apple.com")) {
            throw AppleMusicException("Pega un enlace de music.apple.com (Compartir → Copiar enlace).")
        }
        val html = YTClient.http.newCall(Request.Builder().url(urlString).header("User-Agent", SAFARI_UA).build())
            .execute().use { it.body?.string().orEmpty() }

        val tracks = mutableListOf<AMTrack>()
        script(html, "id=\"serialized-server-data\"")?.let { json ->
            runCatching { visit(parse(json)) { d ->
                if (d.optJSONObject("contentDescriptor")?.optString("kind") == "song") {
                    val title = d.optString("title")
                    val artist = d.optString("artistName")
                    val album = d.optJSONArray("tertiaryLinks")?.optJSONObject(0)?.optString("title").orEmpty()
                    if (title.isNotEmpty() && d.has("artistName")) tracks += AMTrack(title, artist, album, d.optDouble("duration", 0.0) / 1000)
                }
            } }
        }
        var name = "Playlist de Apple Music"
        script(html, "type=\"application/ld+json\"")?.let { ld ->
            runCatching {
                val obj = JSONObject(ld)
                obj.optString("name").takeIf { it.isNotEmpty() }?.let { name = it }
                if (tracks.isEmpty()) obj.optJSONArray("track")?.let { arr ->
                    for (i in 0 until arr.length()) arr.optJSONObject(i)?.optString("name")?.takeIf { it.isNotEmpty() }?.let { tracks += AMTrack(it, "") }
                }
            }
        }
        if (tracks.isEmpty()) throw AppleMusicException("No se encontraron canciones. ¿La playlist es pública?")
        val artwork = meta(html, "og:image")?.replace(Regex("/\\d+x\\d+[^/?]*\\.jpg(\\?.*)?$"), "/600x600bb.jpg")
        AMPlaylist(name, tracks, artwork)
    }

    private fun parse(text: String): Any = if (text.trimStart().startsWith("[")) JSONArray(text) else JSONObject(text)

    private fun script(html: String, attribute: String): String? =
        Regex("<script[^>]*" + Regex.escape(attribute) + "[^>]*>(.*?)</script>", RegexOption.DOT_MATCHES_ALL).find(html)?.groupValues?.get(1)

    private fun meta(html: String, property: String): String? =
        Regex("<meta[^>]*property=\"" + Regex.escape(property) + "\"[^>]*content=\"([^\"]+)\"").find(html)?.groupValues?.get(1)?.replace("&amp;", "&")

    private fun visit(node: Any?, found: (JSONObject) -> Unit) {
        when (node) {
            is JSONObject -> {
                found(node)
                node.keys().forEach { visit(node.opt(it), found) }
            }
            is JSONArray -> for (i in 0 until node.length()) visit(node.opt(i), found)
        }
    }

    /** Busca cada pista en YouTube Music, 4 a la vez, conservando el orden. */
    suspend fun match(tracks: List<AMTrack>, progress: (Int) -> Unit): List<Song> = coroutineScope {
        val gate = Semaphore(4)
        val done = AtomicInteger(0)
        val results = tracks.map { t ->
            async(Dispatchers.IO) {
                gate.withPermit {
                    val s = bestMatch(t)
                    progress(done.incrementAndGet())
                    s
                }
            }
        }.map { it.await() }
        val seen = HashSet<String>()
        results.filterNotNull().filter { seen.add(it.id) }
    }

    /**
     * La canción de YouTube Music que corresponde a una pista de Apple Music (bestMatch en iOS).
     * Sin ninguna que encaje devuelve null en vez de coger otra versión o un karaoke.
     */
    fun bestMatch(t: AMTrack): Song? {
        val results = runCatching { YTClient.searchCandidates("${t.title} ${t.artist}") }.getOrNull() ?: return null
        return Matcher.best(t.title, t.artist, t.album, t.duration, results, minScore = 20)
    }
}

/**
 * Puntúa resultados de YouTube Music contra una canción conocida: título, etiquetas de versión
 * (directo, remix, acústica…), artista, álbum y duración. Mismas reglas que `Matcher` en iOS.
 */
object Matcher {
    data class Scored(val song: Song, val score: Int)

    private val tags: List<Pair<String, List<String>>> = listOf(
        "live" to listOf("live", "en vivo", "en directo", "directo", "ao vivo", "concert"),
        "remix" to listOf("remix", "rmx", "mix"),
        "acoustic" to listOf("acoustic", "acustic", "acustico", "acustica", "unplugged", "stripped"),
        "instrumental" to listOf("instrumental", "karaoke", "backing track"),
        "cover" to listOf("cover", "originally performed", "in the style of", "tribute", "made famous"),
        "sped" to listOf("sped up", "speed up", "nightcore"),
        "slowed" to listOf("slowed", "reverb"),
        "remaster" to listOf("remaster", "remastered", "remasterizado"),
        "demo" to listOf("demo"),
        "edit" to listOf("radio edit", "edit"),
        "clean" to listOf("clean", "clean version", "censored", "radio version"),
        "extended" to listOf("extended"),
        "version" to listOf("version"),
        "orchestral" to listOf("orchestral", "symphonic", "piano version"),
    )
    /** Diferencias de poca importancia (mismo audio o casi). */
    private val minor = setOf("remaster", "version", "edit")

    fun fold(s: String): String = Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")

    fun versionTags(s: String): Set<String> {
        val t = fold(s)
        return tags.filter { (_, words) -> words.any { Regex("\\b" + Regex.escape(it) + "\\b").containsMatchIn(t) } }.map { it.first }.toSet()
    }

    /** Título sin paréntesis, sin « - …» y sin «feat.»: la canción en sí. */
    fun base(s: String): String {
        var t = fold(s)
        for (p in listOf("\\s*[(\\[].*?[)\\]]", "\\s+-\\s+.*$", "\\s+(feat\\.?|ft\\.?|con|with)\\s+.*$", "[^\\p{L}\\p{N}\\s]")) {
            t = t.replace(Regex(p), "")
        }
        return t.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
    }

    fun artists(s: String): List<String> =
        fold(s).replace(Regex(",|&| y | and | x | feat\\.? | ft\\.? "), "|").split("|").map { it.trim() }.filter { it.isNotEmpty() }

    /** Segundos de diferencia que se aceptan como «la misma grabación» (Ajustes › Avanzado). */
    @Volatile var tolerance: Int = 4

    fun score(title: String, artist: String, album: String, duration: Double, c: YTClient.Candidate, explicit: Boolean? = null): Int {
        var score = 0
        val bt = base(title)
        val bc = base(c.song.title)
        score += when {
            bt == bc -> 50
            bt.isNotEmpty() && bc.isNotEmpty() && (bc.contains(bt) || bt.contains(bc)) -> 15
            else -> -60
        }
        val want = versionTags(title).toMutableSet()
        if ("live" in versionTags(album)) want += "live"
        // Explícita en el origen: una versión «clean» no vale; limpia en el origen: se prefiere la «clean».
        if (explicit == false && "clean" in versionTags(c.song.title)) want += "clean"
        val got = versionTags(c.song.title)
        for (t in got - want) score -= if (t in minor) 10 else 45
        for (t in want - got) score -= if (t in minor) 5 else 25

        val wanted = artists(artist)
        val have = fold(c.song.artist)
        wanted.firstOrNull()?.let { first ->
            score += when {
                have.contains(first) -> 40
                wanted.any { have.contains(it) } -> 25
                else -> -40
            }
        }
        if (album.isNotEmpty() && c.album.isNotEmpty() && base(album) == base(c.album)) score += 20
        val d = c.duration
        if (duration > 0 && d != null) {
            val diff = kotlin.math.abs(duration - d)
            score += when {
                diff <= minOf(2, tolerance) -> 25
                diff <= tolerance -> 18
                diff <= tolerance * 2.5 -> 0
                else -> -30
            }
        }
        return score
    }

    /** De mejor a peor (a igualdad, el orden de YouTube). */
    fun ranked(title: String, artist: String, album: String, duration: Double, candidates: List<YTClient.Candidate>, explicit: Boolean? = null): List<Scored> =
        candidates.take(10).map { Scored(it.song, score(title, artist, album, duration, it, explicit)) }.sortedByDescending { it.score }

    /** Confianza de una coincidencia: buena, para revisar a mano o no encontrada. */
    enum class Confidence { Good, Review, None }

    const val GOOD = 90
    const val MIN = 20

    /**
     * Buena con ≥ [GOOD] puntos y sin empate; para revisar entre [MIN] y [GOOD], o si la segunda está a menos
     * de 8 puntos y es otra canción (otro título o artista); no encontrada por debajo de [MIN].
     */
    fun confidence(ranked: List<Scored>): Confidence {
        val top = ranked.firstOrNull() ?: return Confidence.None
        if (top.score < MIN) return Confidence.None
        val second = ranked.getOrNull(1)
        val tie = second != null && top.score - second.score < 8 &&
            (base(second.song.title) != base(top.song.title) || fold(second.song.artist) != fold(top.song.artist))
        return if (top.score >= GOOD && !tie) Confidence.Good else Confidence.Review
    }

    fun best(title: String, artist: String, album: String, duration: Double, candidates: List<YTClient.Candidate>, minScore: Int): Song? =
        ranked(title, artist, album, duration, candidates).firstOrNull()?.takeIf { it.score >= minScore }?.song
}
