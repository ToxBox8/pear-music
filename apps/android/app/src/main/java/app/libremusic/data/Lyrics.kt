package app.libremusic.data


import app.libremusic.L
import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.abs

/** Letra de una canción: sincronizada (líneas con su tiempo) o sólo texto. */
data class Lyrics(val lines: List<Line>, val plain: String?, val instrumental: Boolean = false) {
    data class Line(val timeMs: Long, val text: String)

    val synced: Boolean get() = lines.isNotEmpty()

    /** Índice de la línea que suena en [positionMs], o -1 antes de la primera. */
    fun indexAt(positionMs: Long): Int {
        var lo = 0
        var hi = lines.lastIndex
        var found = -1
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            if (lines[mid].timeMs <= positionMs) { found = mid; lo = mid + 1 } else hi = mid - 1
        }
        return found
    }

    fun toJson(): JSONObject = JSONObject()
        .put("synced", JSONArray(lines.map { JSONArray().put(it.timeMs).put(it.text) }))
        .put("plain", plain)
        .put("instrumental", instrumental)

    companion object {
        private val TAG = Regex("""\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?]""")

        /** Lee el formato LRC: «[mm:ss.xx] texto», con varias marcas por línea; se ignoran las cabeceras ([ar:], [ti:]…). */
        fun parseLrc(lrc: String): List<Line> = lrc.lineSequence().flatMap { raw ->
            val tags = TAG.findAll(raw).toList()
            if (tags.isEmpty() || tags.first().range.first != 0) return@flatMap emptySequence()
            val text = raw.substring(tags.last().range.last + 1).trim()
            tags.asSequence().map { m ->
                val (mm, ss, frac) = m.destructured
                val ms = when (frac.length) { 0 -> 0; 1 -> frac.toInt() * 100; 2 -> frac.toInt() * 10; else -> frac.take(3).toInt() }
                Line(mm.toLong() * 60_000 + ss.toLong() * 1000 + ms, text)
            }
        }.sortedBy { it.timeMs }.toList()

        fun fromJson(o: JSONObject): Lyrics {
            val arr = o.optJSONArray("synced") ?: JSONArray()
            val lines = (0 until arr.length()).map { arr.getJSONArray(it).let { l -> Line(l.getLong(0), l.getString(1)) } }
            return Lyrics(lines, o.optString("plain").ifEmpty { null }.takeIf { !o.isNull("plain") }, o.optBoolean("instrumental"))
        }

        /** Título sin «(Official Video)», «[Lyrics]», «- Remastered»… para buscar la letra. */
        fun cleanTitle(title: String): String = title
            .replace(Regex("""\s*[(\[][^)\]]*\b(official|video|audio|lyrics?|letra|visuali[sz]er|hd|4k|mv|clip)\b[^)\]]*[)\]]""", RegexOption.IGNORE_CASE), "")
            .replace(Regex("""\s+-\s+.*\bremaster(ed)?\b.*$""", RegexOption.IGNORE_CASE), "")
            .trim()

        /** Primer artista de «A, B & C» o «A feat. B». */
        fun mainArtist(artist: String): String =
            artist.split(Regex("""\s*(,|&| feat\.? | ft\.? | x | y )\s*""", RegexOption.IGNORE_CASE)).first().trim()
    }
}

/**
 * Letras de LRCLIB (lrclib.net: gratis, sin cuenta ni clave). Se busca por título y artista y se elige la de duración
 * más parecida, mejor si está sincronizada. Se guardan en `cache/lyrics/<videoId>.json` (también «no hay letra»,
 * durante 7 días), así que las canciones descargadas tienen letra sin conexión. Mismas reglas que `LyricsClient` en iOS.
 */
object LyricsClient {
    private const val BASE = "https://lrclib.net/api"
    private const val USER_AGENT = "PearMusic (https://github.com/ToxBox8/pear-music)"
    private const val NONE_TTL_MS = 7L * 24 * 3600 * 1000
    private val memory = object : LinkedHashMap<String, Lyrics?>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Lyrics?>?) = size > 50
    }

    /** Deja una letra en memoria (capturas de pantalla). */
    internal fun seed(id: String, lyrics: Lyrics?) = synchronized(memory) { memory[id] = lyrics }

    /** Letra de [song]; null si no hay. Lanza excepción sólo si falla la red y no hay nada guardado. */
    suspend fun lyrics(context: Context, song: Song, durationSec: Double): Lyrics? = withContext(Dispatchers.IO) {
        synchronized(memory) { if (memory.containsKey(song.id)) return@withContext memory[song.id] }
        val file = File(context.cacheDir, "lyrics/${song.id}.json")
        if (file.exists()) {
            val o = runCatching { JSONObject(file.readText()) }.getOrNull()
            if (o != null) {
                val none = o.optBoolean("none")
                if (!none || System.currentTimeMillis() - file.lastModified() < NONE_TTL_MS) {
                    val l = if (none) null else Lyrics.fromJson(o)
                    synchronized(memory) { memory[song.id] = l }
                    return@withContext l
                }
            }
        }
        val found = fetch(song, durationSec)
        // Sin la duración se elige a ciegas entre versiones: no se guarda, para repetir la búsqueda cuando se sepa.
        if (durationSec <= 0) return@withContext found
        file.parentFile?.mkdirs()
        runCatching { file.writeText((found?.toJson() ?: JSONObject().put("none", true)).toString()) }
        synchronized(memory) { memory[song.id] = found }
        found
    }

    private fun fetch(song: Song, durationSec: Double): Lyrics? {
        val title = Lyrics.cleanTitle(song.title)
        val artist = Lyrics.mainArtist(song.artist)
        val candidates = search(mapOf("track_name" to title, "artist_name" to artist))
            .ifEmpty { search(mapOf("q" to "$title $artist")) }
        return pick(candidates, durationSec)
    }

    /** La de duración más parecida (±10 s; sin duración conocida, cualquiera), prefiriendo las sincronizadas. */
    internal fun pick(candidates: List<JSONObject>, durationSec: Double): Lyrics? {
        val near = candidates.filter { durationSec <= 0 || abs(it.optDouble("duration", 0.0) - durationSec) <= 10 }
        val best = near.sortedWith(
            compareByDescending<JSONObject> { !it.isNull("syncedLyrics") && it.optString("syncedLyrics").isNotBlank() }
                .thenBy { if (durationSec <= 0) 0.0 else abs(it.optDouble("duration", 0.0) - durationSec) },
        ).firstOrNull() ?: return null
        if (best.optBoolean("instrumental")) return Lyrics(emptyList(), null, instrumental = true)
        val synced = best.optString("syncedLyrics").takeIf { !best.isNull("syncedLyrics") }?.let(Lyrics::parseLrc).orEmpty()
        val plain = best.optString("plainLyrics").takeIf { !best.isNull("plainLyrics") && it.isNotBlank() }
        return if (synced.isEmpty() && plain == null) null else Lyrics(synced, plain)
    }

    private fun search(params: Map<String, String>): List<JSONObject> {
        val url = "$BASE/search".toHttpUrl().newBuilder().apply { params.forEach { (k, v) -> addQueryParameter(k, v) } }.build()
        val req = Request.Builder().url(url).header("User-Agent", USER_AGENT).build()
        YTClient.http.newCall(req).execute().use { r ->
            if (!r.isSuccessful) throw java.io.IOException(L("LRCLIB respondió {0}", r.code))
            val arr = JSONArray(r.body?.string() ?: "[]")
            return (0 until arr.length()).map { arr.getJSONObject(it) }
        }
    }
}
