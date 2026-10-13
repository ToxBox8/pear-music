package app.libremusic.playback

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import app.libremusic.data.Song
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * Última cola que sonó (canciones, posición en la cola y en la canción), en `files/last_queue.json`. Sirve para
 * retomar la música con la app cerrada: el botón de reproducir del widget, los auriculares o la pantalla de bloqueo
 * llegan al servicio con el reproductor vacío y Media3 pide qué sonar a `onPlaybackResumption`.
 * Como mucho [MAX] canciones alrededor de la actual, para que el archivo no crezca con la radio infinita.
 */
object LastQueue {
    data class Saved(val songs: List<Song>, val index: Int, val positionMs: Long)

    const val MAX = 200
    private val io = Executors.newSingleThreadExecutor()
    @Volatile private var cached: Saved? = null
    private var file: File? = null

    fun init(context: Context) {
        if (file == null) file = File(context.filesDir, "last_queue.json")
    }

    /** Lo último guardado (también lo que leyó el disco al arrancar el proceso), o null si nunca sonó nada. */
    fun load(context: Context): Saved? {
        init(context)
        cached?.let { return it }
        val f = file ?: return null
        return runCatching { decode(JSONObject(f.readText())) }.getOrNull()?.also { cached = it }
    }

    /** Engancha el guardado al reproductor: al cambiar de canción o de cola y al pausar. */
    fun attach(context: Context, player: Player) {
        init(context)
        player.addListener(object : Player.Listener {
            override fun onEvents(p: Player, events: Player.Events) {
                if (events.containsAny(Player.EVENT_MEDIA_ITEM_TRANSITION, Player.EVENT_TIMELINE_CHANGED, Player.EVENT_IS_PLAYING_CHANGED)) {
                    save(p)
                }
            }
        })
    }

    fun save(player: Player) {
        val count = player.mediaItemCount
        if (count == 0) return
        val current = player.currentMediaItemIndex.coerceIn(0, count - 1)
        val from = (current - MAX / 2).coerceAtLeast(0)
        val to = minOf(count, from + MAX)
        val songs = (from until to).map { player.getMediaItemAt(it).toSong() }
        val saved = Saved(songs, current - from, player.currentPosition.coerceAtLeast(0))
        cached = saved
        val f = file ?: return
        val text = encode(saved).toString()
        io.execute {
            runCatching {
                val tmp = File(f.parentFile, "last_queue.json.tmp")
                tmp.writeText(text)
                tmp.renameTo(f)
            }
        }
    }

    fun mediaItems(saved: Saved): List<MediaItem> = saved.songs.map(Song::toMediaItem)

    fun encode(s: Saved): JSONObject = JSONObject()
        .put("index", s.index)
        .put("positionMs", s.positionMs)
        .put("songs", JSONArray().apply {
            s.songs.forEach { put(JSONObject().put("id", it.id).put("title", it.title).put("artist", it.artist).put("thumbnail", it.thumbnail ?: JSONObject.NULL)) }
        })

    fun decode(o: JSONObject): Saved? {
        val arr = o.optJSONArray("songs") ?: return null
        val songs = (0 until arr.length()).map { i ->
            arr.getJSONObject(i).let { Song(it.getString("id"), it.optString("title"), it.optString("artist"), it.optString("thumbnail").takeIf { t -> !it.isNull("thumbnail") && t.isNotEmpty() }) }
        }
        if (songs.isEmpty()) return null
        return Saved(songs, o.optInt("index").coerceIn(0, songs.size - 1), o.optLong("positionMs").coerceAtLeast(0))
    }
}
