package app.libremusic.playback

import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import app.libremusic.data.Song
import app.libremusic.data.YTClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Radio infinita (ajuste `autoplay`, activado por defecto): cuando empieza la última canción de la cola y el bucle
 * está apagado, se añaden canciones parecidas (la radio de YouTube Music de esa canción). Va en el servicio, así que
 * sigue con la app cerrada, en la notificación y en Android Auto. Mismas reglas que iOS.
 */
object AutoRadio {
    @Volatile var enabled = true
    /** Canciones que se añaden cada vez. */
    const val BATCH = 20

    private var scope: CoroutineScope? = null
    private var lastSeed: String? = null

    /** Las de [radio] que no están ya en la cola ni repetidas, como mucho [BATCH]. */
    fun fresh(radio: List<Song>, queueIds: Set<String>): List<Song> =
        radio.filter { it.id !in queueIds }.distinctBy { it.id }.take(BATCH)

    fun attach(player: Player) {
        val s = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        scope = s
        player.addListener(object : Player.Listener {
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) = check(player, s)
        })
    }

    fun detach() {
        scope?.cancel()
        scope = null
    }

    private fun check(player: Player, scope: CoroutineScope) {
        val seed = player.currentMediaItem?.mediaId ?: return
        if (!enabled || player.repeatMode != Player.REPEAT_MODE_OFF) return
        if (player.currentMediaItemIndex != player.mediaItemCount - 1 || seed == lastSeed) return
        lastSeed = seed
        scope.launch {
            val radio = withContext(Dispatchers.IO) { runCatching { YTClient.radio(seed) }.getOrDefault(emptyList()) }
            // Si mientras tanto ha cambiado la cola (otra lista, otra canción), no se toca.
            if (player.currentMediaItem?.mediaId != seed || player.currentMediaItemIndex != player.mediaItemCount - 1) return@launch
            val ids = (0 until player.mediaItemCount).map { player.getMediaItemAt(it).mediaId }.toSet()
            val more = fresh(radio, ids)
            if (more.isNotEmpty()) player.addMediaItems(more.map(Song::toMediaItem))
        }
    }
}
