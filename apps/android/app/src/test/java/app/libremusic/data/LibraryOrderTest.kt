package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Test

class LibraryOrderTest {
    private val a = Playlist(id = "A", name = "Rock", songs = listOf(Song("1", "x", "y", null)))
    private val b = Playlist(id = "B", name = "ambiente", songs = emptyList())
    private val c = Playlist(id = "C", name = "Zumba", songs = listOf(Song("1", "x", "y", null), Song("2", "x", "y", null)))
    private val all = listOf(a, b, c) // en orden de creación

    @Test fun recentFirstWithSmartLists() =
        assertEquals(listOf("downloads", "favorites", "C", "B", "A"), LibraryOrder.keys(all, "recent", emptyList(), true))

    @Test fun nameAtoZAndZtoA() {
        assertEquals(listOf("B", "A", "C"), LibraryOrder.keys(all, "name", emptyList(), false))
        assertEquals(listOf("C", "A", "B"), LibraryOrder.keys(all, "nameDesc", emptyList(), false))
    }

    @Test fun customKeepsOrderAndAppendsNew() =
        assertEquals(
            listOf("B", "favorites", "A", "downloads", "C"),
            LibraryOrder.keys(all, "custom", listOf("B", "favorites", "gone", "A", "downloads"), true),
        )

    @Test fun smartListsLeaveTheCarousel() =
        assertEquals(listOf("A", "C"), LibraryOrder.keys(all, "custom", listOf("favorites", "A", "C"), false).filter { it != "B" })
}
