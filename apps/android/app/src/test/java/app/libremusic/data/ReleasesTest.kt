package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.Calendar

/** Novedades: qué artistas se miran, qué cuenta como reciente y cómo se intercalan. */
@RunWith(RobolectricTestRunner::class)
class ReleasesTest {
    private fun c(id: String, year: Int) = RemoteCollection(id, id, "Single • X • $year", null)

    @Test fun topArtistsWeighPlays() {
        val saved = listOf(Song("1", "a", "Rosalía", null), Song("2", "b", "Rosalía y C. Tangana", null), Song("3", "c", "Bad Bunny", null))
        val plays = PlayStats.Data(mapOf("3" to saved[2]), List(3) { PlayStats.Play("3", it.toLong()) })
        assertEquals(listOf("Bad Bunny", "Rosalía"), Releases.topArtists(saved, plays))
    }

    @Test fun minYearIncludesLastYearEarlyInTheYear() {
        val jan = Calendar.getInstance().apply { set(2027, Calendar.JANUARY, 10) }
        val jun = Calendar.getInstance().apply { set(2027, Calendar.JUNE, 10) }
        assertEquals(2026, Releases.minYear(jan))
        assertEquals(2027, Releases.minYear(jun))
    }

    @Test fun interleavesAndFilters() {
        val out = Releases.pick(listOf(listOf(c("a1", 2026), c("a2", 2026), c("a3", 2020)), listOf(c("b1", 2026))), 2026)
        assertEquals(listOf("a1", "b1", "a2"), out.map { it.id })
    }
}
