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

    /** Fase 3.2: el QR lleva la dirección del anfitrión para entrar sin esperar a la búsqueda en la Wi-Fi. */
    @Test fun enlaceDirecto() {
        val link = JamLink.link("ABC234", "192.168.1.20:41234")
        org.junit.Assert.assertEquals("libremusic://jam/ABC234?h=192.168.1.20:41234", link)
        org.junit.Assert.assertEquals("ABC234", JamLink.codeFrom(link))
        org.junit.Assert.assertEquals("192.168.1.20" to 41234, JamLink.directFrom(link))
        // Sólo redes locales y puertos válidos: nunca se conecta a una IP pública por un QR.
        org.junit.Assert.assertNull(JamLink.directFrom("libremusic://jam/ABC234?h=8.8.8.8:41234"))
        org.junit.Assert.assertNull(JamLink.directFrom("libremusic://jam/ABC234?h=10.0.0.5:80"))
        org.junit.Assert.assertNull(JamLink.directFrom("libremusic://jam/ABC234?h=300.1.1.1:41234"))
        org.junit.Assert.assertNull(JamLink.directFrom("libremusic://jam/ABC234"))
        org.junit.Assert.assertEquals("10.0.0.5" to 50000, JamLink.directFrom("libremusic://jam/ABC234?h=10.0.0.5:50000"))
    }
}
