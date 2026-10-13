@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package app.libremusic.playback

import android.net.Uri
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Un 403 de YouTube pide identificador y URL nuevos y se reintenta una sola vez. */
@RunWith(RobolectricTestRunner::class)
class RetryForbiddenTest {
    private class Fake(private val codes: MutableList<Int>) : BaseDataSource(true) {
        var opens = 0
        override fun open(dataSpec: DataSpec): Long {
            opens++
            val code = codes.removeFirstOrNull() ?: 206
            if (code != 206) throw HttpDataSource.InvalidResponseCodeException(
                code, null, null, emptyMap(), dataSpec, ByteArray(0),
            )
            return 10
        }
        override fun read(buffer: ByteArray, offset: Int, length: Int) = -1
        override fun getUri(): Uri? = null
        override fun close() {}
    }

    private val track = DataSpec(trackUri("abc"))

    @Test
    fun retriesOnceAfterForbidden() {
        val fake = Fake(mutableListOf(403))
        val renewed = mutableListOf<String>()
        val source = MediaGraph.RetryForbiddenDataSource(fake) { renewed += it }
        assertEquals(10L, source.open(track))
        assertEquals(2, fake.opens)
        assertEquals(listOf("abc"), renewed)
    }

    @Test
    fun givesUpAfterSecondForbidden() {
        val fake = Fake(mutableListOf(403, 403))
        val source = MediaGraph.RetryForbiddenDataSource(fake) {}
        assertThrows(HttpDataSource.InvalidResponseCodeException::class.java) { source.open(track) }
        assertEquals(2, fake.opens)
    }

    @Test
    fun otherErrorsAreNotRetried() {
        val fake = Fake(mutableListOf(404))
        val source = MediaGraph.RetryForbiddenDataSource(fake) { error("no debe renovar") }
        assertThrows(HttpDataSource.InvalidResponseCodeException::class.java) { source.open(track) }
        assertEquals(1, fake.opens)
    }
}
