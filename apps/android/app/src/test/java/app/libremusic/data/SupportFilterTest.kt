package app.libremusic.data

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** Mismos casos que `services/soporte/test/spam.test.js`: la app y el Worker tienen que decidir lo mismo. */
class SupportFilterTest {
    @Test fun genuino() {
        assertNull(SupportFilter.problem("La app se cierra al abrir la cola de reproducción"))
        assertNull(SupportFilter.problem("Esto es una mierda, la app se cierra al abrir la cola"))
        assertNull(SupportFilter.problem("When I tap download on an album nothing happens"))
    }

    @Test fun basura() {
        assertNotNull(SupportFilter.problem("asdfghjkl qwrtzxcv bnmlkjh"))
        assertNotNull(SupportFilter.problem("aaaaaaaaaaaaaa"))
        assertNotNull(SupportFilter.problem("hola hola hola hola hola hola hola"))
        assertNotNull(SupportFilter.problem("!!!! ???? #### $$$$"))
        assertNotNull(SupportFilter.problem("mira https://a.com https://b.com https://c.com"))
    }

    @Test fun insultos() {
        assertNotNull(SupportFilter.problem("eres un gilipollas, la app no va"))
        assertNotNull(SupportFilter.problem("puta mierda de app joder"))
        assertNotNull(SupportFilter.problem("Eres un SUBNORMAL"))
    }
}
