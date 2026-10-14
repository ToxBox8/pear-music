package app.libremusic.playback

import android.media.audiofx.LoudnessEnhancer
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.LoadControl
import app.libremusic.ui.theme.Prefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlin.math.pow

// Mejoras de audio de 0.9.4 (lo pidió Toxbox: «mejora el audio»).

/**
 * Búfer para audio: hasta 2 min por delante (una canción en Opus a ~160 kbps son unos 2,4 MB) para aguantar cortes
 * de red sin que se pare, y 30 s por detrás para que retroceder unos segundos no vuelva a descargar.
 * Arranca con 1 s cargado, como Media3 por defecto, y tras un corte espera 2,5 s para no volver a cortarse enseguida.
 */
fun audioLoadControl(): LoadControl =
    DefaultLoadControl
        .Builder()
        .setBufferDurationsMs(
            /* minBufferMs = */ 30_000,
            /* maxBufferMs = */ 120_000,
            /* bufferForPlaybackMs = */ 1_000,
            /* bufferForPlaybackAfterRebufferMs = */ 2_500,
        ).setBackBuffer(30_000, /* retainBackBufferFromKeyframe = */ true)
        .build()

/**
 * Pide por adelantado la URL de las dos siguientes canciones de la cola. Antes cada canción se resolvía justo al
 * empezar (una petición a YouTube de 0,5–2 s), y eso se oía como un silencio o un tirón entre canciones; ahora
 * ExoPlayer encuentra la URL ya resuelta y puede ir cargando la siguiente mientras suena la actual.
 */
object Prefetch {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun attach(player: ExoPlayer) {
        player.addListener(
            object : Player.Listener {
                override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) = next(player)

                override fun onTimelineChanged(timeline: Timeline, reason: Int) = next(player)
            },
        )
    }

    private fun next(player: ExoPlayer) {
        val low = Prefs.quality.value == "low"
        val songs = mutableListOf<app.libremusic.data.Song>()
        var i = player.nextMediaItemIndex
        while (i != C.INDEX_UNSET && songs.size < 2) {
            songs += player.getMediaItemAt(i).toSong()
            i = player.currentTimeline.getNextWindowIndex(i, player.repeatMode, player.shuffleModeEnabled)
        }
        if (songs.isEmpty()) return
        // Las descargadas suenan desde el móvil: no hace falta su URL.
        val pending = songs.filter { it.id !in app.libremusic.download.Downloads.songs.value.map { s -> s.id } }
        scope.launch { pending.forEach { StreamResolver.prefetch(it, low) } }
    }
}

/**
 * Iguala el volumen entre canciones (ajuste `normalize`, por defecto sí) con la sonoridad que da YouTube de cada una
 * (`loudnessDb`, respecto a su referencia): las más fuertes bajan con el volumen del reproductor y las más flojas
 * suben hasta 4 dB con `LoudnessEnhancer`, que tiene limitador y no satura. Como «Normalizar volumen» de SimpMusic.
 */
object Normalizer {
    private const val MAX_BOOST_DB = 4.0
    private var enhancer: LoudnessEnhancer? = null
    private var player: ExoPlayer? = null

    fun attach(player: ExoPlayer) {
        this.player = player
        player.addListener(
            object : Player.Listener {
                override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) = apply()

                // La sonoridad se conoce al resolver la URL, que puede ser después de la transición.
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_READY) apply()
                }

                override fun onAudioSessionIdChanged(audioSessionId: Int) {
                    attachEnhancer(audioSessionId)
                    apply()
                }
            },
        )
        attachEnhancer(player.audioSessionId)
    }

    private fun attachEnhancer(sessionId: Int) {
        enhancer?.release()
        enhancer =
            if (sessionId == C.AUDIO_SESSION_ID_UNSET) {
                null
            } else {
                runCatching { LoudnessEnhancer(sessionId) }
                    .onFailure { Log.w("Normalizer", "Sin LoudnessEnhancer: ${it.message}") }
                    .getOrNull()
            }
    }

    /** Vuelve a calcular la ganancia de la canción actual (también al cambiar el ajuste). */
    fun apply() {
        val p = player ?: return
        val id = p.currentMediaItem?.toSong()?.id
        val db = if (Prefs.normalize.value && id != null) StreamResolver.loudnessDb(id) else null
        if (db == null || db == 0.0) {
            VolumeMix.norm = 1f
            setBoost(0.0)
            return
        }
        if (db > 0) {
            // Más fuerte que la referencia: se baja (como hace YouTube), sin pasar de -12 dB.
            VolumeMix.norm = 10.0.pow(-db.coerceAtMost(12.0) / 20.0).toFloat()
            setBoost(0.0)
        } else {
            VolumeMix.norm = 1f
            setBoost((-db).coerceAtMost(MAX_BOOST_DB))
        }
    }

    private fun setBoost(db: Double) {
        val e = enhancer ?: return
        runCatching {
            e.setTargetGain((db * 100).toInt())
            e.enabled = db > 0.0
        }
    }
}
