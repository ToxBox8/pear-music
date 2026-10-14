package app.libremusic.avisos

import app.libremusic.ui.haceCuanto
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Instant

/** Avisos: el contrato del JSON (versión 1), la regla de 48 h sin repetir y «hace cuánto» (igual que la web e iOS). */
@RunWith(RobolectricTestRunner::class)
class AvisosTest {
    private val ahora = Instant.parse("2026-10-14T12:00:00Z")

    private fun json(estado: String = "ok", version: Int = 1, avisos: String = "") =
        """{"version":$version,"estado":"$estado","actualizado":"2026-10-14T12:00:00Z","avisos":[$avisos]}"""

    private fun aviso(id: String, fecha: String, tipo: String = "aviso", enlace: String = "null") =
        """{"id":"$id","tipo":"$tipo","titulo":"T$id","texto":"","enlace":$enlace,"fecha":"$fecha","editado":null}"""

    @Test fun parseaAvisos() {
        val l = AvisosRepo.parsear(json(avisos = aviso("1", "2026-10-14T11:00:00Z", "importante", "\"https://x.dev\"") + "," + aviso("2", "2026-10-13T11:00:00Z")))
        assertEquals(2, l.size)
        assertTrue(l[0].importante)
        assertEquals("https://x.dev", l[0].enlace)
        assertNull(l[1].enlace)
        assertEquals("", l[1].texto)
    }

    @Test fun soloEnlacesHttp() =
        assertNull(AvisosRepo.parsear(json(avisos = aviso("1", "2026-10-14T11:00:00Z", enlace = "\"intent://x#Intent;end\""))).single().enlace)

    @Test fun sinConfigurarEsListaVacia() = assertEquals(emptyList<Aviso>(), AvisosRepo.parsear(json("sin_configurar")))

    @Test fun errorYVersionDesconocidaFallan() {
        assertThrows(IllegalStateException::class.java) { AvisosRepo.parsear(json("error")) }
        assertThrows(IllegalStateException::class.java) { AvisosRepo.parsear(json(version = 2)) }
    }

    @Test fun notificaSoloNuevosDeLas48hYUnaVez() {
        val ctx = org.robolectric.RuntimeEnvironment.getApplication()
        val l = AvisosRepo.parsear(json(avisos = aviso("nuevo", "2026-10-14T10:00:00Z") + "," + aviso("viejo", "2026-10-10T10:00:00Z")))
        assertEquals(listOf("nuevo"), AvisosRepo.pendientesDeNotificar(ctx, l, ahora).map { it.id })
        assertEquals(emptyList<String>(), AvisosRepo.pendientesDeNotificar(ctx, l, ahora).map { it.id })
    }

    @Test fun haceCuantoComoLaWeb() {
        assertEquals("ahora mismo", haceCuanto(ahora.minusSeconds(20), ahora))
        assertEquals("hace 5 min", haceCuanto(ahora.minusSeconds(300), ahora))
        assertEquals("hace 3 h", haceCuanto(ahora.minusSeconds(3 * 3600), ahora))
        assertEquals("ayer", haceCuanto(ahora.minusSeconds(26 * 3600), ahora))
        assertEquals("hace 3 días", haceCuanto(ahora.minusSeconds(3 * 86400), ahora))
        assertEquals("1 oct 2026", haceCuanto(Instant.parse("2026-10-01T12:00:00Z"), ahora))
    }
}
