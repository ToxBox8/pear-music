package app.libremusic.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** «Sin añadir»: el formato de import_pending.json (común con iOS) ida y vuelta. */
@RunWith(RobolectricTestRunner::class)
class PendingImportsTest {
    @Test fun roundTrip() {
        val m = mapOf(
            "p1" to listOf(AMTrack("Song", "Artist", "Album", 201.5, "USUM71900001", true), AMTrack("Otra", "B")),
        )
        assertEquals(m, PendingImports.decode(JSONObject(PendingImports.encode(m).toString())))
    }
}
