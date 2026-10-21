package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** 2.7 de x.1.1: «No me interesa» en Descubrir. */
class ReelsSkipTest {
    private val day = ReelsSkip.DAY_MS
    private val now = 1_800_000_000_000L
    private fun song(id: String, artist: String) = Song(id, "t$id", artist, null)
    private fun skip(id: String, artist: String, daysAgo: Int) = ReelsSkip.Entry(id, artist, now - daysAgo * day)

    @Test fun laCancionMarcadaNoVuelveEn50Reels() {
        // Generador falso: 50 reels con la canción marcada repetida entre medias.
        val feed = (0 until 50).map { if (it % 7 == 0) song("x", "Otro") else song("s$it", "Artista $it") }
        val shown = ReelsSkip.filter(feed, listOf(skip("x", "Otro", 0)), now)
        assertTrue(shown.none { it.id == "x" })
        assertEquals(feed.count { it.id != "x" }, shown.size)
    }

    @Test fun tresMarcasEn30DiasSacanAlArtista30Dias() {
        val three = listOf(skip("a", "Bad Bunny", 20), skip("b", "Bad Bunny", 10), skip("c", "Bad Bunny y Otro", 5))
        assertEquals(setOf("bad bunny"), ReelsSkip.blockedArtists(three, now))
        assertTrue(ReelsSkip.filter(listOf(song("d", "Bad Bunny, Otro")), three, now).isEmpty())
        // 30 días después de la tercera, vuelve.
        assertEquals(emptySet<String>(), ReelsSkip.blockedArtists(three, now + 26 * day))
    }

    @Test fun dosMarcasOMuySeparadasNoBastan() {
        assertEquals(emptySet<String>(), ReelsSkip.blockedArtists(listOf(skip("a", "X", 3), skip("b", "X", 1)), now))
        assertEquals(emptySet<String>(), ReelsSkip.blockedArtists(listOf(skip("a", "X", 80), skip("b", "X", 40), skip("c", "X", 1)), now))
    }
}
