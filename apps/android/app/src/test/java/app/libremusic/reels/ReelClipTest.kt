package app.libremusic.reels

import org.junit.Assert.assertEquals
import org.junit.Test

class ReelClipTest {
    @Test
    fun longSongStartsNearTheChorus() {
        val start = ReelClip.start(200_000)
        assertEquals(70_000, start)
        assertEquals(100_000, ReelClip.end(start, 200_000))
    }

    @Test
    fun shortSongStartsAtTheBeginning() {
        assertEquals(0, ReelClip.start(50_000))
        assertEquals(30_000, ReelClip.end(0, 50_000))
    }

    @Test
    fun clipNeverPassesTheEnd() {
        assertEquals(24_600, ReelClip.end(0, 25_000))
    }

    @Test
    fun unknownDurationUsesFullClip() {
        assertEquals(0, ReelClip.start(0))
        assertEquals(30_000, ReelClip.end(0, 0))
    }
}
