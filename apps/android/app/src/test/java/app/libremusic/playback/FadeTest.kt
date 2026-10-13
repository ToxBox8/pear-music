package app.libremusic.playback

import org.junit.Assert.assertEquals
import org.junit.Test

/** Fundido entre canciones: baja al final si hay siguiente, sube al empezar, y nada con el ajuste en «No». */
class FadeTest {
    @Test fun off() = assertEquals(1f, Fade.factor(199_000, 200_000, hasNext = true, seconds = 0), 0f)

    @Test fun fadesOutOnlyWithNext() {
        assertEquals(1f, Fade.factor(100_000, 200_000, true, 6), 0f)
        assertEquals(0.5f, Fade.factor(197_000, 200_000, true, 6), 0.001f)
        assertEquals(1f, Fade.factor(197_000, 200_000, false, 6), 0f)
    }

    @Test fun fadesIn() {
        assertEquals(0f, Fade.factor(0, 200_000, true, 6), 0f)
        assertEquals(0.5f, Fade.factor(1_500, 200_000, true, 6), 0.001f)
        assertEquals(1f, Fade.factor(3_000, 200_000, true, 6), 0f)
    }

    @Test fun shortSongsNeverGoSilent() {
        assertEquals(1f, Fade.factor(0, 20_000, true, 10), 0f)
        assertEquals(1f, Fade.factor(19_000, 20_000, true, 10), 0f)
    }
}
