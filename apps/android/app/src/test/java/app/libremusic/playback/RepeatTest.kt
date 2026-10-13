package app.libremusic.playback

import androidx.media3.common.Player
import org.junit.Assert.assertEquals
import org.junit.Test

/** El bucle va no → lista → canción → no, y se guarda con los mismos valores que iOS. */
class RepeatTest {
    @Test
    fun cycles() {
        assertEquals(Player.REPEAT_MODE_ALL, Repeat.next(Player.REPEAT_MODE_OFF))
        assertEquals(Player.REPEAT_MODE_ONE, Repeat.next(Player.REPEAT_MODE_ALL))
        assertEquals(Player.REPEAT_MODE_OFF, Repeat.next(Player.REPEAT_MODE_ONE))
    }

    @Test
    fun keysMatchIos() {
        for (m in listOf(Player.REPEAT_MODE_OFF, Player.REPEAT_MODE_ALL, Player.REPEAT_MODE_ONE)) {
            assertEquals(m, Repeat.fromKey(Repeat.key(m)))
        }
        assertEquals(listOf("off", "all", "one"), listOf(Player.REPEAT_MODE_OFF, Player.REPEAT_MODE_ALL, Player.REPEAT_MODE_ONE).map(Repeat::key))
        assertEquals(Player.REPEAT_MODE_OFF, Repeat.fromKey(null))
    }
}
