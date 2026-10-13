package app.libremusic.playback

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Temporizador para dormir: cuenta atrás, bajada de volumen y textos (los mismos que iOS). */
@RunWith(RobolectricTestRunner::class)
class SleepTimerTest {
    private var clock = 1_000_000L

    @After fun tearDown() = SleepTimer.cancel()

    @Test fun countdownAndLabels() {
        SleepTimer.now = { clock }
        assertNull(SleepTimer.label())
        SleepTimer.start(15)
        assertEquals(15 * 60_000L, SleepTimer.remainingMs())
        assertEquals("Se para en 15 min", SleepTimer.label())
        clock += 14 * 60_000L + 1
        assertEquals("Se para en 1 min", SleepTimer.label())
        clock += 60_000L - 46_000L
        assertEquals("Se para en 46 s", SleepTimer.label())
        SleepTimer.endOfSong()
        assertEquals("Se para al acabar la canción", SleepTimer.label())
        assertNull(SleepTimer.remainingMs())
        SleepTimer.cancel()
        assertEquals(SleepTimer.State.Off, SleepTimer.state.value)
    }

    @Test fun fadeOnlyInTheLastSeconds() {
        assertEquals(1f, SleepTimer.volumeFor(60_000), 0f)
        assertEquals(1f, SleepTimer.volumeFor(SleepTimer.FADE_SECONDS * 1000L), 0f)
        assertEquals(0.5f, SleepTimer.volumeFor(SleepTimer.FADE_SECONDS * 500L), 0.001f)
        assertEquals(0f, SleepTimer.volumeFor(0), 0f)
    }
}
