package app.libremusic.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Estadísticas: cuándo cuenta una escucha, resumen por periodo y el formato de stats.json. */
@RunWith(RobolectricTestRunner::class)
class PlayStatsTest {
    private fun s(id: String, artist: String) = Song(id, "t$id", artist, null)

    @Test fun countsAfter30sOrHalfOfShortSongs() {
        assertFalse(PlayStats.shouldCount(29_000, 200_000))
        assertTrue(PlayStats.shouldCount(30_000, 200_000))
        assertTrue(PlayStats.shouldCount(21_000, 40_000))
        assertFalse(PlayStats.shouldCount(19_000, 40_000))
        assertFalse(PlayStats.shouldCount(10_000, 0))
    }

    @Test fun summaryByPeriod() {
        val songs = mapOf("a" to s("a", "Rosalía"), "b" to s("b", "Rosalía feat. X"), "c" to s("c", "Bad Bunny"))
        val plays = listOf(PlayStats.Play("a", 100), PlayStats.Play("a", 2_000), PlayStats.Play("b", 2_100), PlayStats.Play("c", 2_200), PlayStats.Play("a", 2_300))
        val all = PlayStats.summary(PlayStats.Data(songs, plays), 0)
        assertEquals(5, all.plays)
        assertEquals(3, all.songs)
        assertEquals(2, all.artists)
        assertEquals("a" to 3, all.topSongs.first().let { it.first.id to it.second })
        assertEquals("Rosalía" to 4, all.topArtists.first())
        assertEquals(4, PlayStats.summary(PlayStats.Data(songs, plays), 1_000).plays)
    }

    @Test fun jsonRoundTrip() {
        val d = PlayStats.Data(mapOf("a" to Song("a", "T", "A", "https://x")), listOf(PlayStats.Play("a", 42)))
        assertEquals(d, PlayStats.decode(JSONObject(PlayStats.encode(d).toString())))
    }
}
