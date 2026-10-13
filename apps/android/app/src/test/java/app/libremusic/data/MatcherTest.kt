package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Emparejar pistas de Apple Music con resultados de YouTube Music (mismas reglas que iOS). */
class MatcherTest {
    private fun c(id: String, title: String, artist: String, album: String = "", duration: Double? = null) =
        YTClient.Candidate(Song(id, title, artist, null), album, duration)

    private val results = listOf(
        c("studio", "Hotel California", "Eagles", "Legacy", 392.0),
        c("karaoke", "Hotel California (In The Style Of 'The Eagles')", "Zoom Karaoke", "Pop Classics", 397.0),
        c("live", "Hotel California (Live)", "The Eagles", "Live at the Summit", 423.0),
        c("mtv", "Hotel California (Live On MTV, 1994)", "Eagles", "Hell Freezes Over", 433.0),
    )

    @Test
    fun studioVersion() =
        assertEquals("studio", Matcher.best("Hotel California", "Eagles", "Hotel California", 391.0, results, 20)?.id)

    @Test
    fun liveVersionIsNotTheStudioOne() =
        assertEquals("live", Matcher.best("Hotel California (Live)", "Eagles", "", 422.0, results, 20)?.id)

    @Test
    fun albumAndDurationPickTheExactLive() =
        assertEquals("mtv", Matcher.best("Hotel California (Live on MTV, 1994)", "Eagles", "Hell Freezes Over", 432.0, results, 20)?.id)

    @Test
    fun noMatchInsteadOfAnotherSong() =
        assertNull(Matcher.best("Bohemian Rhapsody", "Queen", "", 355.0, results, 20))
}
