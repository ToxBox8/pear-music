package app.libremusic.playback

import android.os.Handler
import android.os.Looper
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer

/**
 * Volumen propio de la app (no el del sistema) = temporizador × fundido. Así el temporizador para dormir y el fundido
 * entre canciones no se pisan.
 */
object VolumeMix {
    var player: ExoPlayer? = null
    var sleep = 1f
        set(v) { field = v; apply() }
    var fade = 1f
        set(v) { field = v; apply() }

    private fun apply() { player?.volume = (sleep * fade).coerceIn(0f, 1f) }
}

/**
 * Fundido entre canciones (ajuste `crossfade`, en segundos; 0 = no). La canción baja de volumen en sus últimos N
 * segundos y la siguiente entra subiendo en N/2. No se solapan (eso pediría dos reproductores): es un fundido a
 * negro corto, que suaviza los cambios bruscos. Mismas reglas que `Fade` en iOS.
 */
object Fade {
    /** Opciones del ajuste. */
    val options = listOf(0, 3, 6, 10)
    @Volatile var seconds = 0

    /** Factor de volumen en [positionMs] de una canción de [durationMs]; [hasNext]: si al acabar suena otra. */
    fun factor(positionMs: Long, durationMs: Long, hasNext: Boolean, seconds: Int = this.seconds): Float {
        if (seconds <= 0 || durationMs <= 0) return 1f
        val fadeOut = if (hasNext) ((durationMs - positionMs) / (seconds * 1000f)).coerceIn(0f, 1f) else 1f
        val fadeIn = (positionMs / (seconds * 500f)).coerceIn(0f, 1f)
        // En canciones muy cortas los dos fundidos se juntarían y no se oiría entera: se usa el mayor de los dos.
        return if (durationMs < seconds * 3000L) maxOf(fadeIn, fadeOut) else minOf(fadeIn, fadeOut)
    }

    private val handler by lazy { Handler(Looper.getMainLooper()) }

    fun attach(p: ExoPlayer) {
        VolumeMix.player = p
        handler.post(object : Runnable {
            override fun run() {
                val hasNext = p.hasNextMediaItem() || p.repeatMode != Player.REPEAT_MODE_OFF
                VolumeMix.fade = if (p.isPlaying) factor(p.currentPosition, p.duration, hasNext) else VolumeMix.fade.takeIf { seconds > 0 } ?: 1f
                handler.postDelayed(this, if (seconds > 0 && p.isPlaying) 100 else 500)
            }
        })
    }

    fun detach() {
        handler.removeCallbacksAndMessages(null)
        VolumeMix.player = null
    }
}
