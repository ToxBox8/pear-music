package app.libremusic.playback

import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import app.libremusic.data.PlayStats

/** Apunta en [PlayStats] cada canción que suena lo bastante (va en el servicio: cuenta también con la app cerrada). */
object PlayCounter {
    private val handler by lazy { Handler(Looper.getMainLooper()) }
    private var counted: String? = null
    private var currentKey: String? = null

    fun attach(player: Player) {
        player.addListener(object : Player.Listener {
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                // Cada vez que empieza una canción (también al repetirla) puede volver a contar.
                currentKey = mediaItem?.mediaId?.let { "$it@${System.nanoTime()}" }
            }
        })
        currentKey = player.currentMediaItem?.mediaId?.let { "$it@${System.nanoTime()}" }
        handler.post(object : Runnable {
            override fun run() {
                val key = currentKey
                if (player.isPlaying && key != null && key != counted &&
                    PlayStats.shouldCount(player.currentPosition, player.duration.coerceAtLeast(0))
                ) {
                    counted = key
                    player.currentMediaItem?.toSong()?.let { PlayStats.record(it) }
                }
                handler.postDelayed(this, 1000)
            }
        })
    }

    fun detach() = handler.removeCallbacksAndMessages(null)
}
