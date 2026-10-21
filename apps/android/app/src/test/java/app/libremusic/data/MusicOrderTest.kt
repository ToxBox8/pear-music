package app.libremusic.data

import app.libremusic.ui.theme.Prefs
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** 2.9 de x.1.1: «Playlists» entra arriba en «Tu música» también para quien ya tenía un orden propio. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MusicOrderTest {
    @Test fun carpetaNuevaEnSuSitio() {
        assertEquals("playlists", Prefs.decodeMusicOrder("songs,albums,downloads,favorites,artists,recents,stats").first())
        assertEquals(listOf("playlists", "songs", "albums"), Prefs.decodeMusicOrder("songs,albums,downloads,favorites,artists,recents,stats").take(3))
        assertEquals(Prefs.MUSIC_DEFAULT, Prefs.decodeMusicOrder(null))
        assertEquals(Prefs.MUSIC_DEFAULT, Prefs.decodeMusicOrder("raro,otro"))
    }
}
