package app.libremusic.data

import org.robolectric.RuntimeEnvironment
import android.content.Context
import app.libremusic.ui.theme.Prefs
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Fase 3: la copia de Pear Music perdía las portadas propias y el orden de las playlists. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LibraryBackupTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()

    @Test fun portadasYOrdenViajanAOtroMóvil() {
        Prefs.init(context)
        val a = Library(context)
        val viaje = a.createPlaylist("Viaje")
        val gym = a.createPlaylist("Gym")
        val cover = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 1, 2, 3)
        a.coverFile(viaje.id).writeBytes(cover)
        Prefs.setPlaylistSort("manual")
        Prefs.setPlaylistOrder(listOf(gym.id, viaje.id))
        val json = a.exportJson()

        // «Otro móvil»: sin biblioteca, sin portadas y sin orden.
        context.filesDir.listFiles()?.forEach { it.deleteRecursively() }
        Prefs.setPlaylistOrder(emptyList())
        Prefs.setPlaylistSort("recent")
        val b = Library(context)
        b.importJson(json)

        assertEquals(setOf("Viaje", "Gym"), b.data.value.playlists.map { it.name }.toSet())
        assertArrayEquals(cover, b.coverFile(viaje.id).readBytes())
        assertEquals(listOf(gym.id, viaje.id), Prefs.playlistOrder.value)
        assertEquals("manual", Prefs.playlistSort.value)
    }

    @Test fun elOrdenPropioSeRespeta() {
        assertEquals(listOf("A", "B", "C"), mergeOrder(listOf("A", "B"), listOf("C", "A")))
        assertEquals(listOf("C", "A"), mergeOrder(emptyList(), listOf("C", "A")))
    }

    @Test fun sinPortadasParaLaNube() {
        Prefs.init(context)
        val a = Library(context)
        val p = a.createPlaylist("Con foto")
        a.coverFile(p.id).writeBytes(byteArrayOf(1, 2, 3))
        assertTrue(a.exportJson().contains("\"covers\""))
        assertTrue(!a.exportJson(covers = false).contains("\"covers\""))
    }
}
