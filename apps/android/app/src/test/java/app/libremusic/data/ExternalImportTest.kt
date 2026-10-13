package app.libremusic.data

import android.database.sqlite.SQLiteDatabase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Importar de Spotify (enlace y CSV de Exportify) y de SimpMusic, y la confianza del emparejado. */
@RunWith(RobolectricTestRunner::class)
class ExternalImportTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun spotifyLinks() {
        assertEquals("37i9dQZF1DXcBWIGoYBM5M", SpotifyImporter.playlistId("https://open.spotify.com/intl-es/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc"))
        assertEquals("37i9dQZF1DXcBWIGoYBM5M", SpotifyImporter.playlistId("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"))
        assertNull(SpotifyImporter.playlistId("https://open.spotify.com/track/3zOYmiNOuyDL0ClxJcEJ0T"))
    }

    /** Recorte real de la página de inserción de Spotify (2026-10-13). */
    @Test fun spotifyEmbed() {
        val html = """<html><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":
            {"name":"Today’s Top Hits","coverArt":{"sources":[{"url":"https://i.scdn.co/image/x"}]},"trackList":[
            {"title":"Stop The Wedding!","subtitle":"Ashe","duration":198840,"isExplicit":false},
            {"title":"Golden","subtitle":"HUNTR/X, EJAE","duration":194000,"isExplicit":true}]}}}}}}</script></html>"""
        val pl = SpotifyImporter.parseEmbed(html)
        assertEquals("Today’s Top Hits", pl.name)
        assertEquals(2, pl.tracks.size)
        assertEquals(198.84, pl.tracks[0].duration, 0.01)
        assertEquals("HUNTR/X, EJAE", pl.tracks[1].artist)
        assertEquals(true, pl.tracks[1].explicit)
        assertEquals("https://i.scdn.co/image/x", pl.artwork)
    }

    /** Cabeceras en español (Exportify las traduce), comas escapadas en artistas y comillas. */
    @Test fun exportifyCsv() {
        val csv = "﻿\"URI de la canción\",\"Nombre de la canción\",\"URI(s) del artista\",\"Nombre(s) del artista\",\"URI del álbum\",\"Nombre del álbum\",\"a\",\"b\",\"c\",\"d\",\"e\",\"f\",\"Duración de la canción (ms)\",\"g\",\"Explícito\",\"h\",\"ISRC\"\n" +
            "\"spotify:track:1\",\"Hotel California - 2013 Remaster\",\"x\",\"Eagles\",\"y\",\"Hotel California (2013 Remaster)\",\"\",\"\",\"\",\"\",\"1\",\"1\",\"391376\",\"\",\"false\",\"80\",\"USEE11300353\"\n" +
            "\"spotify:track:2\",\"Say \"\"Hi\"\"\",\"x\",\"Simon\\, Garfunkel, Otro\",\"y\",\"Álbum, con coma\",\"\",\"\",\"\",\"\",\"1\",\"2\",\"200000\",\"\",\"true\",\"10\",\"\"\n"
        val pl = ExportifyCsv.parse("Mi_lista.csv", csv)
        assertEquals("Mi lista", pl.name)
        assertEquals(2, pl.tracks.size)
        assertEquals("USEE11300353", pl.tracks[0].isrc)
        assertEquals(391.376, pl.tracks[0].duration, 0.001)
        assertEquals(false, pl.tracks[0].explicit)
        assertEquals("Say \"Hi\"", pl.tracks[1].title)
        assertEquals("Simon, Garfunkel, Otro", pl.tracks[1].artist)
        assertEquals("Álbum, con coma", pl.tracks[1].album)
        assertNull(pl.tracks[1].isrc)
    }

    /** Base de datos con el esquema de SimpMusic (27): orden por posición y «Me gusta» aparte. */
    @Test fun simpMusicDatabase() {
        val f = tmp.newFile("Music Database")
        f.delete()
        SQLiteDatabase.openOrCreateDatabase(f, null).use { db ->
            db.execSQL("CREATE TABLE song (videoId TEXT PRIMARY KEY, title TEXT, artistName TEXT, thumbnails TEXT, liked INTEGER, favoriteAt INTEGER)")
            db.execSQL("CREATE TABLE local_playlist (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, thumbnail TEXT)")
            db.execSQL("CREATE TABLE pair_song_local_playlist (id INTEGER PRIMARY KEY AUTOINCREMENT, playlistId INTEGER, songId TEXT, position INTEGER, inPlaylist INTEGER)")
            db.execSQL("INSERT INTO song VALUES ('a','Uno','Ana','https://t/a',0,NULL),('b','Dos','Bea',NULL,1,5),('c','Tres','Cris',NULL,0,NULL)")
            db.execSQL("INSERT INTO local_playlist (title, thumbnail) VALUES ('Viaje', NULL)")
            db.execSQL("INSERT INTO pair_song_local_playlist (playlistId, songId, position, inPlaylist) VALUES (1,'c',0,1),(1,'a',1,1),(1,'b',2,0)")
        }
        val lists = SimpMusicBackup.readDatabase(f)
        assertEquals(listOf("Canciones que te gustan (SimpMusic)", "Viaje"), lists.map { it.name })
        assertEquals(listOf("b"), lists[0].songs.map { it.id })
        assertEquals(listOf("c", "a"), lists[1].songs.map { it.id })
        assertEquals("https://t/a", lists[1].songs[1].thumbnail)
    }

    private fun scored(vararg s: Pair<String, Int>) = s.map { (t, n) -> Matcher.Scored(Song(t, t, "Ana", null), n) }

    @Test fun confidence() {
        assertEquals(Matcher.Confidence.Good, Matcher.confidence(scored("Uno" to 120, "Otra" to 30)))
        // Empate entre dos canciones distintas: no se elige sola.
        assertEquals(Matcher.Confidence.Review, Matcher.confidence(scored("Uno" to 120, "Otra" to 115)))
        assertEquals(Matcher.Confidence.Review, Matcher.confidence(scored("Uno" to 60)))
        assertEquals(Matcher.Confidence.None, Matcher.confidence(scored("Uno" to 5)))
        assertEquals(Matcher.Confidence.None, Matcher.confidence(emptyList()))
    }

    /** La tolerancia de duración (Ajustes › Avanzado) decide si 6 s de diferencia todavía puntúan. */
    @Test fun durationTolerance() {
        val cand = YTClient.Candidate(Song("x", "Uno", "Ana", null), "", 206.0)
        Matcher.tolerance = 4
        val strict = Matcher.score("Uno", "Ana", "", 200.0, cand)
        Matcher.tolerance = 10
        val loose = Matcher.score("Uno", "Ana", "", 200.0, cand)
        Matcher.tolerance = 4
        assertEquals(18, loose - strict)
    }
}
