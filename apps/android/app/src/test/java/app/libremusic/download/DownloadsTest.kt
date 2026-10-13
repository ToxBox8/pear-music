package app.libremusic.download

import androidx.media3.exoplayer.offline.Download
import app.libremusic.data.Song
import org.junit.Assert.assertEquals
import org.junit.Test

/** «Descargar todo» sólo pide las canciones de la lista que se descarga. */
class DownloadsTest {
    private fun song(id: String) = Song(id, id, "x", null)

    @Test
    fun pendingOnlyFromTheList() {
        val list = listOf(song("a"), song("b"), song("c"))
        val status = mapOf(
            "a" to DownloadStatus(Download.STATE_COMPLETED, 100f),
            "b" to DownloadStatus(Download.STATE_DOWNLOADING, 40f),
            // De otra playlist: no debe aparecer.
            "z" to DownloadStatus(Download.STATE_QUEUED, 0f),
        )
        assertEquals(listOf("c"), Downloads.pendingOf(list, status).map { it.id })
    }

    @Test
    fun failedAndRepeatedSongsAreRequestedOnce() {
        val list = listOf(song("a"), song("a"), song("b"))
        val status = mapOf("a" to DownloadStatus(Download.STATE_FAILED, 0f))
        assertEquals(listOf("a", "b"), Downloads.pendingOf(list, status).map { it.id })
    }
}
