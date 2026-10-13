package app.libremusic.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LibraryDataTest {

    /** Así escribe iOS `library.json` (JSONEncoder de Swift: barras escapadas, opcionales omitidos). */
    private val iosJson = """
        {"favorites":[{"id":"abc","title":"Golden Hour","artist":"JVKE","thumbnail":"https:\/\/lh3.example\/a=w120-h120"}],
         "playlists":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"Viaje","songs":[{"id":"def","title":"Midnight City","artist":"M83"}],"tint":3}],
         "recents":[]}
    """.trimIndent()

    @Test
    fun readsIosLibrary() {
        val data = LibraryData.fromJson(JSONObject(iosJson))
        assertEquals("https://lh3.example/a=w120-h120", data.favorites.single().thumbnail)
        val playlist = data.playlists.single()
        assertEquals("E621E1F8-C36C-495A-93FC-0C247A3E6E5F", playlist.id)
        assertEquals(3, playlist.tint)
        assertNull(playlist.icon)
        assertNull(playlist.songs.single().thumbnail)
    }

    @Test
    fun roundTripKeepsEverything() {
        val data = LibraryData.fromJson(JSONObject(iosJson))
        assertEquals(data, LibraryData.fromJson(data.toJson()))
    }

    @Test
    fun mergeDoesNotDuplicate() {
        val a = LibraryData(favorites = listOf(Song("1", "A", "x", null)))
        val b = LibraryData(
            favorites = listOf(Song("1", "A", "x", null), Song("2", "B", "y", null)),
            playlists = listOf(Playlist(id = "P", name = "Lista")),
        )
        val merged = a.merge(b).merge(b)
        assertEquals(listOf("1", "2"), merged.favorites.map { it.id })
        assertEquals(listOf("P"), merged.playlists.map { it.id })
    }

    @Test
    fun recentsAreCapped() {
        val many = (1..60).map { Song("$it", "t", "a", null) }
        assertEquals(LibraryData.MAX_RECENTS, LibraryData().merge(LibraryData(recents = many)).recents.size)
    }

    /** «Tus álbumes»: el álbum va en `album` y no sale entre las playlists; sin él, todo sigue igual. */
    @Test
    fun albumsAreSeparatedFromPlaylists() {
        val json = """
            {"favorites":[],"playlists":[
              {"id":"A","name":"Viaje","songs":[]},
              {"id":"B","name":"Currents","songs":[],"album":{"browseId":"MPREb_x","artist":"Tame Impala","year":"2015"}}
            ]}
        """.trimIndent()
        val data = LibraryData.fromJson(JSONObject(json))
        assertEquals(listOf("A"), data.userPlaylists.map { it.id })
        assertEquals(listOf("B"), data.albums.map { it.id })
        assertEquals("Tame Impala · 2015", data.album("MPREb_x")?.album?.line)
        assertEquals(data, LibraryData.fromJson(data.toJson()))
        assertNull(LibraryData.fromJson(JSONObject(iosJson)).playlists.single().album)
    }

    @Test
    fun albumInfoFromSubtitle() {
        assertEquals(AlbumInfo("id", "Bad Bunny", "2025"), AlbumInfo.from("id", "Álbum • Bad Bunny • 2025"))
        assertEquals(AlbumInfo("id", "Rosalía", "2022"), AlbumInfo.from("id", "Rosalía • 2022"))
        assertEquals(AlbumInfo("id", "Daft Punk", null), AlbumInfo.from("id", "Álbum • Daft Punk"))
    }
}
