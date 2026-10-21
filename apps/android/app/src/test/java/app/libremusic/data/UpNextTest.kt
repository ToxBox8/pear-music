package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Test

class UpNextTest {
    private val list = listOf("a", "b", "c", "d")

    @Test fun firstGoesRightAfterTheCurrentSong() = assertEquals(2, UpNext.insertAt(list, 1, emptySet()))

    @Test fun nextOnesGoBehindTheQueuedOnes() {
        val withTwo = listOf("a", "b", "q1", "q2", "c", "d")
        assertEquals(4, UpNext.insertAt(withTwo, 1, setOf("q1", "q2")))
    }

    @Test fun atTheEndOfTheList() = assertEquals(4, UpNext.insertAt(list, 3, emptySet()))
}
