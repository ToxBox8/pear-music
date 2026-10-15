package app.libremusic.data


import app.libremusic.L
import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Calendar
import java.util.concurrent.Executors

/**
 * Estadísticas de escucha, sólo en este móvil (`stats.json`, fuera de `library.json`: no se exportan ni se mezclan con
 * la biblioteca). Cuenta una escucha cuando la canción suena 30 s (o la mitad, si dura menos de un minuto).
 * Formato común con iOS:
 * `{"version":1,"songs":{"<videoId>":{"title","artist","thumbnail"}},"plays":[["<videoId>",<segundos epoch>],…]}`.
 */
object PlayStats {
    enum class Period(val key: String, private val titleEs: String) { Month("month", L("Este mes")), Year("year", L("Este año")), All("all", "Siempre") ;
    val title: String get() = L(titleEs)
}

    data class Play(val id: String, val at: Long)
    data class Data(val songs: Map<String, Song> = emptyMap(), val plays: List<Play> = emptyList())
    data class Summary(
        val plays: Int,
        val songs: Int,
        val artists: Int,
        val topSongs: List<Pair<Song, Int>>,
        val topArtists: List<Pair<String, Int>>,
    )

    /** Escuchas guardadas como mucho (unos años de uso intenso); se borran las más antiguas. */
    const val MAX_PLAYS = 50_000
    /** Segundos que tiene que sonar una canción para contar. */
    const val COUNT_AFTER_MS = 30_000L

    private val _data = MutableStateFlow(Data())
    val data: StateFlow<Data> = _data.asStateFlow()
    private var file: File? = null
    private val io = Executors.newSingleThreadExecutor()

    fun init(context: Context) {
        val f = File(context.filesDir, "stats.json")
        file = f
        _data.value = runCatching { decode(JSONObject(f.readText())) }.getOrDefault(Data())
    }

    /** ¿Cuenta ya como escuchada? [durationMs] ≤ 0 si aún no se sabe. */
    fun shouldCount(positionMs: Long, durationMs: Long): Boolean =
        positionMs >= COUNT_AFTER_MS || (durationMs in 1 until 60_000 && positionMs >= durationMs / 2)

    fun record(song: Song, atSeconds: Long = System.currentTimeMillis() / 1000) {
        val d = _data.value
        val next = Data(d.songs + (song.id to song), (d.plays + Play(song.id, atSeconds)).takeLast(MAX_PLAYS))
        _data.value = next
        save(next)
    }

    fun clear() {
        _data.value = Data()
        save(Data())
    }

    /** Inicio del periodo en segundos epoch (hora local), o 0 para «Siempre». */
    fun since(period: Period, nowMs: Long = System.currentTimeMillis()): Long {
        if (period == Period.All) return 0
        val cal = Calendar.getInstance().apply {
            timeInMillis = nowMs
            if (period == Period.Year) set(Calendar.MONTH, Calendar.JANUARY)
            set(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        return cal.timeInMillis / 1000
    }

    fun summary(d: Data, sinceSeconds: Long, top: Int = 10): Summary {
        val plays = d.plays.filter { it.at >= sinceSeconds }
        val bySong = plays.groupingBy { it.id }.eachCount()
        val songs = bySong.mapNotNull { (id, n) -> d.songs[id]?.let { it to n } }
            .sortedWith(compareByDescending<Pair<Song, Int>> { it.second }.thenBy { it.first.title.lowercase() })
        val byArtist = songs.groupBy { app.libremusic.ui.primaryArtist(it.first.artist) }.mapValues { (_, l) -> l.sumOf { it.second } }
            .toList().sortedWith(compareByDescending<Pair<String, Int>> { it.second }.thenBy { it.first.lowercase() })
        return Summary(plays.size, bySong.size, byArtist.size, songs.take(top), byArtist.take(5))
    }

    fun encode(d: Data): JSONObject = JSONObject()
        .put("version", 1)
        .put("songs", JSONObject().apply {
            d.songs.forEach { (id, s) -> put(id, JSONObject().put("title", s.title).put("artist", s.artist).put("thumbnail", s.thumbnail ?: JSONObject.NULL)) }
        })
        .put("plays", JSONArray(d.plays.map { JSONArray().put(it.id).put(it.at) }))

    fun decode(o: JSONObject): Data {
        val songsJ = o.optJSONObject("songs") ?: JSONObject()
        val songs = songsJ.keys().asSequence().associateWith { id ->
            val s = songsJ.getJSONObject(id)
            Song(id, s.optString("title"), s.optString("artist"), s.optString("thumbnail").takeIf { !s.isNull("thumbnail") && it.isNotEmpty() })
        }
        val arr = o.optJSONArray("plays") ?: JSONArray()
        val plays = (0 until arr.length()).map { arr.getJSONArray(it).let { p -> Play(p.getString(0), p.getLong(1)) } }
        return Data(songs, plays)
    }

    private fun save(d: Data) {
        val f = file ?: return
        io.execute {
            runCatching {
                val tmp = File(f.parentFile, "stats.json.tmp")
                tmp.writeText(encode(d).toString())
                tmp.renameTo(f)
            }
        }
    }
}
