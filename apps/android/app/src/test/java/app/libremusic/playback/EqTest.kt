package app.libremusic.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Curvas del ecualizador: planas en «No» y con la forma que dice su nombre. */
class EqTest {
    private val bands = listOf(60.0, 230.0, 910.0, 3600.0, 14000.0) // las 5 bandas típicas de Android

    @Test fun offIsFlat() = bands.forEach { assertEquals(0.0, Eq.gainDb(Eq.Preset.Off, it), 0.0) }

    @Test fun shapes() {
        assertTrue(Eq.gainDb(Eq.Preset.Bass, 60.0) >= 5.9)
        assertEquals(0.0, Eq.gainDb(Eq.Preset.Bass, 3600.0), 0.0)
        assertTrue(Eq.gainDb(Eq.Preset.Treble, 14000.0) >= 4.9)
        assertEquals(0.0, Eq.gainDb(Eq.Preset.Treble, 230.0), 0.0)
        assertTrue(Eq.gainDb(Eq.Preset.Vocal, 3600.0) > 3.0 && Eq.gainDb(Eq.Preset.Vocal, 60.0) < 0)
        assertTrue(Eq.gainDb(Eq.Preset.Small, 60.0) < -4.0 && Eq.gainDb(Eq.Preset.Small, 1500.0) > 2.0)
    }

    @Test fun neverAboveSixDb() = Eq.Preset.entries.forEach { p ->
        (20..20000 step 50).forEach { hz -> assertTrue("$p a $hz Hz", Eq.gainDb(p, hz.toDouble()) <= 6.0) }
    }
}
