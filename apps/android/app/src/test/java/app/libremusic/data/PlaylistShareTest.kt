package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 0.6 de x.1.1: compartir una playlist con un QR, sin servidor. */
class PlaylistShareTest {
    private val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    // Ids al azar (con semilla fija): se comprimen tan poco como los de verdad.
    private fun ids(n: Int) = java.util.Random(42).let { r -> (0 until n).map { String(CharArray(11) { alphabet[r.nextInt(alphabet.length)] }) } }

    @Test fun idaYVueltaCon1_100y150Canciones() {
        for (n in listOf(1, 100, PlaylistShare.MAX_SONGS)) {
            val list = ids(n)
            val link = PlaylistShare.link("Atardecer en Cádiz", list, "sun.max.fill", 3)!!
            val back = PlaylistShare.decode(link)!!
            assertEquals(list, back.ids)
            assertEquals("Atardecer en Cádiz", back.name)
            assertEquals("sun.max.fill", back.icon)
            assertEquals(3, back.tint)
        }
    }

    @Test fun cabeEnUnQr() {
        // Un QR en modo binario admite como mucho 2953 bytes (versión 40, corrección L).
        val link = PlaylistShare.link("Una lista con un nombre bastante largo", ids(PlaylistShare.MAX_SONGS), null, null)!!
        assertTrue("${link.length} caracteres", link.length < 2_953)
    }

    @Test fun demasiadasOVaciaONoValida() {
        assertNull(PlaylistShare.link("x", ids(PlaylistShare.MAX_SONGS + 1), null, null))
        assertNull(PlaylistShare.link("x", emptyList(), null, null))
        assertNull(PlaylistShare.decode("libremusic://playlist?v=1&d=basura!!"))
        assertNull(PlaylistShare.decode("https://otra.web/x"))
        assertNull(PlaylistShare.decode(null))
    }
}
