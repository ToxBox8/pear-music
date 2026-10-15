package app.libremusic.playback


import app.libremusic.L
import android.media.audiofx.Equalizer
import kotlin.math.log2

/**
 * Ecualizador con unos pocos ajustes hechos (ajuste `equalizer`), sobre el `Equalizer` del sistema enganchado a la
 * sesión de audio de ExoPlayer. Cada ajuste es una curva de ganancia por frecuencia; se aplica a las bandas que
 * tenga el móvil (suelen ser 5). Sólo Android: iOS reproduce HLS con AVPlayer, que no deja procesar el audio.
 */
object Eq {
    enum class Preset(val key: String, private val titleEs: String, private val subtitleEs: String) {
        Off("off", "No", L("El sonido tal cual")),
        Bass("bass", L("Más graves"), L("Bajos y bombos con más cuerpo")),
        Vocal("vocal", L("Voces claras"), L("Voces y pódcast más presentes")),
        Treble("treble", L("Más agudos"), L("Más brillo y detalle")),
        Small("small", L("Altavoz pequeño"), L("Para el altavoz del móvil o uno portátil")),
        ;
    val title: String get() = L(titleEs)
    val subtitle: String get() = L(subtitleEs)

        companion object {
            fun of(key: String?) = entries.firstOrNull { it.key == key } ?: Off
        }
    }

    @Volatile var preset = Preset.Off
        set(v) { field = v; apply() }

    private var eq: Equalizer? = null

    /** Ganancia en dB de [preset] a [hz]: curvas suaves (rampas en octavas) para que no suene «a efecto». */
    fun gainDb(preset: Preset, hz: Double): Double {
        val oct = log2(hz.coerceAtLeast(20.0) / 1000.0) // 0 = 1 kHz; -2 = 250 Hz; +2 = 4 kHz
        fun ramp(from: Double, to: Double) = ((oct - from) / (to - from)).coerceIn(0.0, 1.0)
        return when (preset) {
            Preset.Off -> 0.0
            Preset.Bass -> 6.0 * (1 - ramp(-3.0, -1.0))
            Preset.Vocal -> -3.0 * (1 - ramp(-3.0, -2.0)) + 4.0 * ramp(-1.0, 0.5) * (1 - ramp(2.0, 3.0))
            Preset.Treble -> 5.0 * ramp(1.0, 3.0)
            Preset.Small -> -6.0 * (1 - ramp(-3.0, -1.5)) + 3.0 * ramp(-1.0, 0.0) * (1 - ramp(1.5, 2.5))
        }
    }

    /** Lo llama [PlaybackService] con la sesión de audio de ExoPlayer (y otra vez si cambia). */
    fun attach(audioSessionId: Int) {
        release()
        if (audioSessionId == 0) return
        eq = runCatching { Equalizer(0, audioSessionId) }.onFailure { app.libremusic.data.Logs.w("Eq", "Sin ecualizador: ${it.message}") }.getOrNull()
        apply()
    }

    fun release() {
        eq?.release()
        eq = null
    }

    private fun apply() {
        val e = eq ?: return
        runCatching {
            val (min, max) = e.bandLevelRange.let { it[0].toInt() to it[1].toInt() }
            for (b in 0 until e.numberOfBands) {
                val hz = e.getCenterFreq(b.toShort()) / 1000.0 // miliherzios → Hz
                val mb = (gainDb(preset, hz) * 100).toInt().coerceIn(min, max)
                e.setBandLevel(b.toShort(), mb.toShort())
            }
            e.enabled = preset != Preset.Off
        }.onFailure { app.libremusic.data.Logs.w("Eq", "No se pudo aplicar: ${it.message}") }
    }
}
