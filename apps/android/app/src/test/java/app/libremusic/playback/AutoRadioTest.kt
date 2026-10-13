package app.libremusic.playback

import app.libremusic.data.Song
import org.junit.Assert.assertEquals
import org.junit.Test

/** Radio infinita: no repite lo que ya está en la cola ni dentro de la propia radio, y añade como mucho BATCH. */
class AutoRadioTest {
    private fun s(id: String) = Song(id, "t$id", "a", null)

    @Test fun skipsQueuedAndDuplicates() {
        val out = AutoRadio.fresh(listOf(s("a"), s("b"), s("b"), s("c")), setOf("a"))
        assertEquals(listOf("b", "c"), out.map { it.id })
    }

    @Test fun capsTheBatch() {
        assertEquals(AutoRadio.BATCH, AutoRadio.fresh((1..60).map { s("$it") }, emptySet()).size)
    }
}
