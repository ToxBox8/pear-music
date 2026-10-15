package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Test

class DiscographyTest {
    @Test fun normalizar() {
        assertEquals("unverano", Discography.normalize("Un Verano"))
        assertEquals("titimepregunto", Discography.normalize("Tití me preguntó"))
        assertEquals("labot", Discography.normalize("La Bot (feat. Fulano)"))
        assertEquals("elclub", Discography.normalize("EL CLúB - Single"))
    }

    @Test fun completaConLoQueFalta() {
        val yt = listOf(RemoteCollection("MPREb_1", "Un Verano Sin Ti", "Álbum • Bad Bunny • 2022", null))
        val mb = listOf(
            Discography.MbRelease("Un verano sin ti", "2022", Discography.Kind.Album),
            Discography.MbRelease("X 100pre", "2018", Discography.Kind.Album),
            Discography.MbRelease("Te descuidó", "2018", Discography.Kind.Single),
        )
        val albums = Discography.merge(yt, mb, Discography.Kind.Album)
        assertEquals(2, albums.size)
        assertEquals("MPREb_1", (albums[0] as Discography.Item.Playable).collection.id)
        assertEquals("X 100pre", (albums[1] as Discography.Item.Missing).release.title)
        assertEquals(1, Discography.merge(emptyList(), mb, Discography.Kind.Single).size)
    }
}
