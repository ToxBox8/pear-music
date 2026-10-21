package app.libremusic.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 2.10 de x.1.1: la barra SimpMusic sólo se despliega sola si está plegada, en Inicio y con la opción puesta. */
class BarIdleTest {
    @Test fun espera() = assertEquals(1_500L, BarIdle.DELAY_MS)

    @Test fun cuandoSeDespliega() {
        assertTrue(BarIdle.restores(enabled = true, collapsed = true, onHome = true))
        assertFalse("ya desplegada", BarIdle.restores(enabled = true, collapsed = false, onHome = true))
        assertFalse("fuera de Inicio", BarIdle.restores(enabled = true, collapsed = true, onHome = false))
        assertFalse("con la opción quitada", BarIdle.restores(enabled = false, collapsed = true, onHome = true))
    }
}
