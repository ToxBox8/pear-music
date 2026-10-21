package app.libremusic.jam

import app.libremusic.data.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** 2.6 de x.1.1: «cada uno en su móvil». Relojes falsos: el del anfitrión va 5 s por delante del nuestro. */
class JamSyncTest {
    private val song = Song("abc", "Canción", "Artista", null)

    @Test fun relojConLasMedidasMasRapidas() {
        // El anfitrión va +5000 ms. Ida y vuelta de 40 ms (simétrica) y otra lenta de 400 ms (asimétrica, falsea).
        val fast = JamSync.sample(t0 = 1_000, th = 6_020, t1 = 1_040)
        val fast2 = JamSync.sample(t0 = 2_000, th = 7_010, t1 = 2_020)
        val slow = JamSync.sample(t0 = 3_000, th = 8_350, t1 = 3_400)
        assertEquals(40, fast.rtt)
        assertEquals(5_000L, JamSync.offset(listOf(slow, fast, fast2)))
        assertNull(JamSync.offset(emptyList()))
    }

    @Test fun posicionEsperada() {
        val play = JamMessage.Play(song, positionMs = 30_000, atMs = 106_000, playing = true)
        // Ahora aquí son las 102 000 → allí, 107 000: 1 s después del mensaje.
        assertEquals(31_000, JamSync.expected(play, localNow = 102_000, offset = 5_000))
        assertEquals(30_000, JamSync.expected(play.copy(playing = false), localNow = 200_000, offset = 5_000))
    }

    @Test fun correcciones() {
        assertEquals(JamSync.Correction.None, JamSync.correct(10_000, 10_040))
        assertEquals(JamSync.Correction.Speed(JamSync.FASTER), JamSync.correct(10_000, 9_900))
        assertEquals(JamSync.Correction.Speed(JamSync.SLOWER), JamSync.correct(10_000, 10_100))
        assertEquals(JamSync.Correction.Seek(10_000), JamSync.correct(10_000, 9_000))
    }

    @Test fun mensajesNuevosIdaYVuelta() {
        val play = JamMessage.Play(song, 1_234, 5_678, true)
        assertEquals(play, JamMessage.decode(play.encode()))
        assertEquals(JamMessage.Play(null, 0, 1, false), JamMessage.decode(JamMessage.Play(null, 0, 1, false).encode()))
        assertEquals(JamMessage.Pong(1, 2), JamMessage.decode(JamMessage.Pong(1, 2).encode()))
        // Un anfitrión antiguo no manda «mode»: un altavoz.
        val old = JamState("Jam", "ABC234", "Ana", listOf("Ana"), emptyList())
        val json = old.toJson().apply { remove("mode") }
        assertEquals(JamSync.SPEAKER, JamState.fromJson(json).mode)
        assertEquals(JamSync.EVERYONE, JamState.fromJson(old.copy(mode = JamSync.EVERYONE).toJson()).mode)
    }
}
