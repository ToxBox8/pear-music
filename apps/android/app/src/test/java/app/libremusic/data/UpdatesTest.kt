package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdatesTest {
    @Test fun versiones() {
        assertEquals(1, Updates.compare("1.0.0", "0.9.5"))
        assertEquals(-1, Updates.compare("0.9.5", "1.0.0-pre1"))
        assertEquals(1, Updates.compare("1.0.0", "1.0.0-pre3"))
        assertEquals(1, Updates.compare("1.0.0-pre10", "1.0.0-pre9"))
        assertEquals(0, Updates.compare("v1.0.0", "1.0.0"))
        assertEquals(0, Updates.compare("1.0.0-pre1-dev", "1.0.0-pre1"))
        assertEquals(1, Updates.compare("1.0.1", "1.0"))
    }

    private val r = Updates.Release("1.0.0", "t", listOf("a"), "https://x/a.apk", "a".repeat(64))

    @Test fun recordarmeMañana() {
        val now = 1_000_000L
        assertTrue(Updates.shouldShow(r, "0.9.5", null, 0, now))
        assertFalse(Updates.shouldShow(r, "0.9.5", "1.0.0", now + Updates.SNOOZE_MS, now + 1000))
        assertTrue(Updates.shouldShow(r, "0.9.5", "1.0.0", now + Updates.SNOOZE_MS, now + Updates.SNOOZE_MS + 1))
        // Aplazar una versión no aplaza la siguiente.
        assertTrue(Updates.shouldShow(r.copy(version = "1.0.1"), "0.9.5", "1.0.0", now + Updates.SNOOZE_MS, now))
        assertFalse(Updates.shouldShow(r, "1.0.0", null, 0, now))
    }

    @Test fun json() {
        val ok = """{"android":{"version":"1.0.0","title":"T","highlights":["x","y"],"apk":"https://a/b.apk","sha256":"${"A".repeat(64)}"}}"""
        assertEquals(listOf("x", "y"), Updates.parse(ok)!!.highlights)
        // Sin https o sin hash válido no se acepta: nunca se instala algo que no se pueda comprobar.
        assertNull(Updates.parse(ok.replace("https://", "http://")))
        assertNull(Updates.parse(ok.replace("A".repeat(64), "zz")))
        // El version.json antiguo (sólo versión y fecha) no da aviso con descarga.
        assertNull(Updates.parse("""{"android":{"version":"0.9.5","date":"2026-10-14"}}"""))
    }

    @Test fun modoSeguroSóloArreglos() {
        val ok = """{"android":{"version":"1.0.1","apk":"https://a/b.apk","sha256":"${"a".repeat(64)}","fix":true}}"""
        assertTrue(Updates.parse(ok)!!.fix)
        assertFalse(Updates.parse(ok.replace(",\"fix\":true", ""))!!.fix)
        // Kill switch en nivel 2: la versión mala no se ofrece; la que la arregla, sí.
        assertFalse(Updates.allowed(r, restricted = true))
        assertTrue(Updates.allowed(r.copy(fix = true), restricted = true))
        assertTrue(Updates.allowed(r, restricted = false))
    }
}
