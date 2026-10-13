package app.libremusic.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Canciones de una importación (Spotify, Apple Music, CSV) que no se añadieron —«para revisar» sin elegir o no
 * encontradas—, por playlist, para volver a buscarlas más tarde desde la propia playlist. Sólo en este móvil
 * (`import_pending.json`, fuera de `library.json`). Mismo formato que iOS:
 * `{"<playlistId>":[{"title","artist","album","duration","isrc","explicit"},…]}`.
 */
object PendingImports {
    private val _all = MutableStateFlow<Map<String, List<AMTrack>>>(emptyMap())
    val all: StateFlow<Map<String, List<AMTrack>>> = _all.asStateFlow()
    private var file: File? = null

    fun init(context: Context) {
        val f = File(context.filesDir, "import_pending.json")
        file = f
        _all.value = runCatching { decode(JSONObject(f.readText())) }.getOrDefault(emptyMap())
    }

    fun set(playlistId: String, tracks: List<AMTrack>) {
        _all.value = if (tracks.isEmpty()) _all.value - playlistId else _all.value + (playlistId to tracks)
        save()
    }

    fun remove(playlistId: String, track: AMTrack) = set(playlistId, _all.value[playlistId].orEmpty() - track)

    fun encode(m: Map<String, List<AMTrack>>): JSONObject = JSONObject().apply {
        m.forEach { (id, l) ->
            put(id, JSONArray(l.map {
                JSONObject().put("title", it.title).put("artist", it.artist).put("album", it.album).put("duration", it.duration)
                    .put("isrc", it.isrc ?: JSONObject.NULL).put("explicit", it.explicit ?: JSONObject.NULL)
            }))
        }
    }

    fun decode(o: JSONObject): Map<String, List<AMTrack>> = o.keys().asSequence().associateWith { id ->
        val a = o.getJSONArray(id)
        (0 until a.length()).map { i ->
            val t = a.getJSONObject(i)
            AMTrack(
                t.optString("title"), t.optString("artist"), t.optString("album"), t.optDouble("duration", 0.0),
                t.optString("isrc").takeIf { !t.isNull("isrc") && it.isNotEmpty() },
                if (t.isNull("explicit") || !t.has("explicit")) null else t.getBoolean("explicit"),
            )
        }
    }

    private fun save() {
        val f = file ?: return
        runCatching { f.writeText(encode(_all.value).toString()) }
    }
}
