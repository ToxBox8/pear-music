package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class FichaTest {
    private val context get() = RuntimeEnvironment.getApplication()

    @Test fun idEsElMismoResumenQueElDelSoporte() {
        // libremusic-soporte guarda los 12 primeros bytes del SHA-256 del id en minúsculas: la ficha empieza igual.
        val id = Ficha.id(" 3F2504E0-4F89-11D3-9A0C-0305E82C3301 ")
        assertEquals(64, id.length)
        assertEquals(Ficha.id("3f2504e0-4f89-11d3-9a0c-0305e82c3301"), id)
    }

    @Test fun cuerpoConLosCamposPermitidos() {
        val b = Ficha.body(context, "abc", 12, "sugerencia", "1.0.1")
        val keys = b.keys().asSequence().toSet()
        assertEquals(setOf("ficha", "platform", "channel", "app_version", "os_version", "device_model", "ticket", "kind"), keys)
        assertEquals("sugerencia", b.getString("kind"))
        assertEquals("error", Ficha.body(context, "abc", 1, "otra", "1.0.1").getString("kind"))
        // Sin telemetría (usr, sin consentimiento) no va su identificador.
        assertFalse(b.has("install"))
        Telemetry.setConsent(context, true)
        assertTrue(Ficha.body(context, "abc", 12, "error", "1.0.1").getString("install").matches(Regex("[a-f0-9]{32}")))
        Telemetry.setConsent(context, false)
    }
}
