package app.libremusic.jam

import app.libremusic.data.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class JamProtocolTest {
    private val song = Song("dQw4w9WgXcQ", "Canción", "Artista", "https://example.com/a.jpg")
    private val state = JamState("Jam de Ana", "ABC234", "Ana", listOf("Ana", "Luis"), listOf(JamEntry(song, "Luis")))

    @Test
    fun everyMessageRoundTrips() {
        val messages = listOf(
            JamMessage.Hello("Luis", "ABC234"),
            JamMessage.State(state),
            JamMessage.Add(JamEntry(song, "Luis")),
            JamMessage.Remove("dQw4w9WgXcQ"),
            JamMessage.Ended,
            JamMessage.Error("bad_code"),
        )
        messages.forEach { assertEquals(it, JamMessage.decode(it.encode())) }
    }

    @Test
    fun linesFollowTheSpec() {
        val line = JamMessage.Remove("x").encode()
        assertTrue(line.contains("\"v\":2"))
        assertTrue(line.contains("\"type\":\"remove\""))
        assertTrue(line.contains("\"songID\":\"x\""))
        assertTrue('\n' !in JamMessage.State(state).encode())
    }

    @Test
    fun ignoresUnknownOrBrokenLines() {
        assertNull(JamMessage.decode("{\"v\":3,\"type\":\"sync\"}"))
        assertNull(JamMessage.decode("no es json"))
    }

    @Test
    fun hostRulesAvoidDuplicates() {
        assertEquals(1, JamRules.add(state, JamEntry(song, "Ana")).entries.size)
        assertEquals(0, JamRules.remove(state, song.id).entries.size)
        assertEquals("Luis (2)", JamRules.uniqueName(state, "Luis"))
        assertEquals("Marta", JamRules.uniqueName(state, " Marta "))
    }
}
