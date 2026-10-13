package app.libremusic.playback

import app.libremusic.data.LibraryData
import app.libremusic.data.Playlist
import app.libremusic.data.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BrowseTreeTest {
    private val a = Song("a", "A", "x", null)
    private val b = Song("b", "B", "y", null)
    private val library = LibraryData(
        favorites = listOf(a),
        playlists = listOf(Playlist(id = "P1", name = "Viaje", songs = listOf(a, b))),
        recents = listOf(b),
    )

    @Test
    fun leafIdsRoundTrip() {
        val id = BrowseTree.leafId(BrowseTree.playlistFolder("P1"), "b")
        assertEquals("playlist:P1" to "b", BrowseTree.parseLeaf(id))
        assertNull(BrowseTree.parseLeaf("dQw4w9WgXcQ"))
    }

    @Test
    fun foldersResolveToSongs() {
        assertEquals(listOf(a), BrowseTree.songsIn(BrowseTree.FAVORITES, library, emptyList()))
        assertEquals(listOf(b), BrowseTree.songsIn(BrowseTree.DOWNLOADS, library, listOf(b)))
        assertEquals(listOf(a, b), BrowseTree.songsIn("playlist:P1", library, emptyList()))
        assertNull(BrowseTree.songsIn("playlist:nope", library, emptyList()))
        assertNull(BrowseTree.songsIn(BrowseTree.ROOT, library, emptyList()))
    }
}
