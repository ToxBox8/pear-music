package app.libremusic.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Letras: formato LRC, línea actual, limpieza del título y elección entre los resultados de LRCLIB. */
@RunWith(RobolectricTestRunner::class)
class LyricsTest {
    @Test fun parsesLrc() {
        val lines = Lyrics.parseLrc("[ar:The Weeknd]\n[00:13.13] Yeah\n[00:27.16][01:02.5] I've been tryna call\n[1:05] Fin\nbasura")
        assertEquals(listOf(13_130L, 27_160L, 62_500L, 65_000L), lines.map { it.timeMs })
        assertEquals("I've been tryna call", lines[2].text)
        val l = Lyrics(lines, null)
        assertEquals(-1, l.indexAt(1_000))
        assertEquals(0, l.indexAt(13_130))
        assertEquals(1, l.indexAt(30_000))
        assertEquals(3, l.indexAt(999_999))
    }

    @Test fun cleansTitles() {
        assertEquals("Blinding Lights", Lyrics.cleanTitle("Blinding Lights (Official Video)"))
        assertEquals("Hey Jude", Lyrics.cleanTitle("Hey Jude - Remastered 2015"))
        assertEquals("Song (Live)", Lyrics.cleanTitle("Song (Live) [Official Audio]"))
        assertEquals("Bad Bunny", Lyrics.mainArtist("Bad Bunny, Jhay Cortez & J Balvin"))
        assertEquals("Drake", Lyrics.mainArtist("Drake feat. Rihanna"))
    }

    @Test fun picksClosestSynced() {
        fun c(d: Double, synced: String?, plain: String? = "texto") =
            JSONObject().put("duration", d).put("syncedLyrics", synced ?: JSONObject.NULL).put("plainLyrics", plain ?: JSONObject.NULL)
        val picked = LyricsClient.pick(listOf(c(201.0, null), c(204.0, "[00:01.00] a"), c(260.0, "[00:02.00] b")), 200.0)!!
        assertTrue(picked.synced)
        assertEquals("a", picked.lines.single().text)
        assertNull(LyricsClient.pick(listOf(c(260.0, "[00:02.00] b")), 200.0))
        assertEquals(false, LyricsClient.pick(listOf(c(200.0, null)), 200.0)!!.synced)
        assertTrue(LyricsClient.pick(listOf(c(200.0, null, null).put("instrumental", true)), 200.0)!!.instrumental)
    }

    @Test fun jsonRoundTrip() {
        val l = Lyrics(Lyrics.parseLrc("[00:01.00] uno\n[00:02.00] dos"), "uno\ndos")
        assertEquals(l, Lyrics.fromJson(JSONObject(l.toJson().toString())))
    }
}
