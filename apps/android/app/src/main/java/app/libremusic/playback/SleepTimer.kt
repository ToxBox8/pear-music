package app.libremusic.playback

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Temporizador para dormir: para la música a los N minutos (bajando el volumen los últimos segundos) o al acabar
 * la canción. Vive en el proceso, no en la pantalla: sigue contando con la app cerrada mientras el servicio suene.
 * Mismas opciones y textos que `SleepTimer` en iOS.
 */
object SleepTimer {
    sealed interface State {
        data object Off : State
        /** [endsAt] en `SystemClock.elapsedRealtime()`, que no cambia si se cambia la hora del móvil. */
        data class At(val endsAt: Long, val minutes: Int) : State
        data object EndOfSong : State
    }

    /** Minutos que se ofrecen en el menú. */
    val presets = listOf(5, 15, 30, 45, 60, 90)
    /** Segundos finales en los que el volumen baja hasta 0. */
    const val FADE_SECONDS = 12

    private val _state = MutableStateFlow<State>(State.Off)
    val state: StateFlow<State> = _state.asStateFlow()

    private val handler by lazy { Handler(Looper.getMainLooper()) }
    private var player: ExoPlayer? = null
    var now: () -> Long = SystemClock::elapsedRealtime

    /** Lo llama [PlaybackService] al crear el reproductor. */
    fun attach(p: ExoPlayer) {
        player = p
        p.addListener(object : Player.Listener {
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                // Se ha parado al final de la canción: el temporizador ya ha cumplido.
                if (!playWhenReady && reason == Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM && _state.value == State.EndOfSong) {
                    p.pauseAtEndOfMediaItems = false
                    _state.value = State.Off
                }
            }
        })
    }

    fun detach() {
        cancel()
        player = null
    }

    fun start(minutes: Int) {
        reset()
        _state.value = State.At(now() + minutes * 60_000L, minutes)
        handler.post(tick)
    }

    fun endOfSong() {
        reset()
        _state.value = State.EndOfSong
        player?.pauseAtEndOfMediaItems = true
    }

    fun cancel() {
        reset()
        _state.value = State.Off
    }

    /** Milisegundos que quedan, o null si no hay cuenta atrás. */
    fun remainingMs(state: State = _state.value): Long? = (state as? State.At)?.let { (it.endsAt - now()).coerceAtLeast(0) }

    /** Volumen para los milisegundos que quedan: 1 hasta los últimos [FADE_SECONDS] y luego baja hasta 0. */
    fun volumeFor(remainingMs: Long): Float = (remainingMs / (FADE_SECONDS * 1000f)).coerceIn(0f, 1f)

    /** «Se para en 12 min», «Se para en 45 s», «Al acabar la canción». */
    fun label(state: State = _state.value): String? = when (state) {
        State.Off -> null
        State.EndOfSong -> "Se para al acabar la canción"
        is State.At -> {
            val s = ((remainingMs(state) ?: 0) + 999) / 1000
            if (s >= 60) "Se para en ${(s + 59) / 60} min" else "Se para en $s s"
        }
    }

    private fun reset() {
        handler.removeCallbacks(tick)
        VolumeMix.sleep = 1f
        player?.pauseAtEndOfMediaItems = false
    }

    private val tick = object : Runnable {
        override fun run() {
            val left = remainingMs() ?: return
            val p = player
            if (left <= 0) {
                p?.pause()
                VolumeMix.sleep = 1f
                _state.value = State.Off
                return
            }
            VolumeMix.sleep = volumeFor(left)
            // Se reemite el estado para que la etiqueta de la pantalla avance.
            _state.value = (_state.value as State.At).copy()
            handler.postDelayed(this, if (left <= FADE_SECONDS * 1000L) 200 else 1000)
        }
    }
}
