package app.libremusic.ui

import androidx.compose.runtime.MonotonicFrameClock
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Reloj de fotogramas que avanza 16 ms cada vez, sin esperar (las animaciones de Compose lo necesitan). */
private object RelojInstantaneo : MonotonicFrameClock {
    private var t = 0L
    override suspend fun <R> withFrameNanos(onFrame: (Long) -> R): R {
        t += 16_000_000
        return onFrame(t)
    }
}

/** Reloj que nunca da el siguiente fotograma: deja la animación de soltar a medias. */
private object RelojParado : MonotonicFrameClock {
    override suspend fun <R> withFrameNanos(onFrame: (Long) -> R): R = awaitCancellation()
}

class TabPagerTest {
    private val tabs = listOf(Tab.Discover, Tab.Home, Tab.Library)

    private fun pager(index: Int = 1) = TabPager().apply { width = 1000f; this.index = index }

    @Test fun `quieto no hay posición ni vecina`() {
        val p = pager()
        assertNull(p.position())
        assertEquals(0f, p.screenX(Tab.Home, Tab.Home, tabs))
        assertNull(p.screenX(Tab.Library, Tab.Home, tabs))
    }

    @Test fun `arrastrar a la izquierda enseña la siguiente y la barra la sigue`() {
        val p = pager()
        p.dragBy(-400f, tabs)
        assertEquals(-400f, p.screenX(Tab.Home, Tab.Home, tabs))
        assertEquals(600f, p.screenX(Tab.Library, Tab.Home, tabs))
        assertNull(p.screenX(Tab.Discover, Tab.Home, tabs))
        assertEquals(1.4f, p.position()!!, 0.0001f)
    }

    @Test fun `sin pestaña a ese lado se resiste`() {
        val p = pager(index = 2)
        p.dragBy(-1000f, tabs)
        assertEquals(-200f, p.screenX(Tab.Library, Tab.Library, tabs))
    }

    @Test fun `soltar pasada la mitad cambia de pestaña`() = runBlocking(RelojInstantaneo) {
        val p = pager()
        p.dragBy(-600f, tabs)
        var committed: Tab? = null
        p.settle(this, 0f, 1f, reduceMotion = true, tabs) { committed = it }.join()
        assertEquals(Tab.Library, committed)
        assertEquals(2, p.index)
        assertEquals(0f, p.offset)
    }

    @Test fun `soltar antes de la mitad vuelve`() = runBlocking(RelojInstantaneo) {
        val p = pager()
        p.dragBy(-300f, tabs)
        var committed: Tab? = null
        p.settle(this, 0f, 1f, reduceMotion = true, tabs) { committed = it }.join()
        assertNull(committed)
        assertEquals(1, p.index)
        assertEquals(0f, p.offset)
    }

    @Test fun `un lanzamiento rápido cambia aunque no llegue a la mitad`() = runBlocking(RelojInstantaneo) {
        val p = pager()
        p.dragBy(-150f, tabs)
        var committed: Tab? = null
        p.settle(this, -3000f, 1f, reduceMotion = true, tabs) { committed = it }.join()
        assertEquals(Tab.Library, committed)
    }

    @Test fun `lanzar hacia atrás lo devuelve aunque pase de la mitad`() = runBlocking(RelojInstantaneo) {
        val p = pager()
        p.dragBy(-700f, tabs)
        var committed: Tab? = null
        p.settle(this, 3000f, 1f, reduceMotion = true, tabs) { committed = it }.join()
        assertNull(committed)
    }

    @Test fun `atrapar la animación da la pestaña por hecha sin saltos`() = runBlocking(RelojParado) {
        val scope = this
        val p = pager()
        p.dragBy(-700f, tabs)
        var committed: Tab? = null
        p.settle(scope, 0f, 1f, reduceMotion = true, tabs) { committed = it }
        // La animación aún no ha corrido: la pantalla sigue en -700 cuando llega el dedo.
        p.catchSettle { committed = it }
        assertEquals(Tab.Library, committed)
        assertEquals(2, p.index)
        // La Biblioteca estaba en -700 + 1000 = 300 y sigue ahí, ahora como pestaña actual.
        assertEquals(300f, p.offset)
    }

    // runBlocking espera a las corrutinas lanzadas en su ámbito: el settle de cada prueba termina antes del assert.
}
