package app.libremusic.jam

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class JamLinkTest {
    @Test
    fun readsCodeFromLink() =
        assertEquals("ABC234", JamLink.codeFrom("libremusic://jam/ABC234"))

    @Test
    fun readsLowercaseCodeFromLink() =
        assertEquals("ABC234", JamLink.codeFrom("libremusic://jam/abc234"))

    @Test
    fun readsBareCode() =
        assertEquals("XYZ789", JamLink.codeFrom("  xyz789 "))

    @Test
    fun rejectsAmbiguousCharacters() =
        // 0, O, 1 e I no forman parte del alfabeto (igual que en iOS)
        assertNull(JamLink.codeFrom("AB1O0I"))

    @Test
    fun rejectsWrongLength() {
        assertNull(JamLink.codeFrom("ABC23"))
        assertNull(JamLink.codeFrom("ABC2345"))
    }

    @Test
    fun rejectsOtherLinks() =
        assertNull(JamLink.codeFrom("https://example.com/jam/ABC234"))

    @Test
    fun buildsLink() =
        assertEquals("libremusic://jam/ABC234", JamLink.link("ABC234"))
}
