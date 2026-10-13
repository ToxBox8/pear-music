package app.libremusic.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.ZipInputStream

// Importar playlists de fuera (Fase 2D): Spotify (enlace público o CSV de Exportify) y SimpMusic (su copia
// .backup). Spotify sólo da metadatos: cada canción se busca en YouTube Music y se empareja (Matcher). Nunca
// se descarga nada al importar. Mismas reglas que `ExternalImport.swift` en iOS.

class ImportException(message: String) : Exception(message)

// MARK: Spotify por enlace ------------------------------------------------------------------------

object SpotifyImporter {
    private const val UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

    /** El id de un enlace `open.spotify.com/playlist/<id>` (también con /intl-es/ o `spotify:playlist:<id>`). */
    fun playlistId(link: String): String? =
        Regex("(?:playlist[/:])([A-Za-z0-9]{22})").find(link)?.groupValues?.get(1)

    fun isSpotify(link: String) = "spotify.com" in link || link.trim().startsWith("spotify:")

    /**
     * La página de inserción (`/embed/playlist/<id>`) trae el nombre, la portada y, de cada canción, título,
     * artistas, duración y si es explícita. Sin cuenta ni claves. Llega hasta ~100 canciones; para listas
     * más largas, el CSV de Exportify.
     */
    suspend fun fetchPublic(link: String): AMPlaylist = withContext(Dispatchers.IO) {
        val id = playlistId(link) ?: throw ImportException("Pega el enlace de una playlist de Spotify (Compartir → Copiar enlace).")
        val html = YTClient.http.newCall(Request.Builder().url("https://open.spotify.com/embed/playlist/$id").header("User-Agent", UA).build())
            .execute().use { if (it.isSuccessful) it.body?.string().orEmpty() else throw ImportException("Spotify no deja ver esa playlist. ¿Es pública?") }
        parseEmbed(html)
    }

    fun parseEmbed(html: String): AMPlaylist {
        val json = Regex("<script id=\"__NEXT_DATA__\"[^>]*>(.*?)</script>", RegexOption.DOT_MATCHES_ALL).find(html)?.groupValues?.get(1)
            ?: throw ImportException("No se pudo leer la playlist. Prueba con el CSV de Exportify.")
        val entity = JSONObject(json).optJSONObject("props")?.optJSONObject("pageProps")?.optJSONObject("state")
            ?.optJSONObject("data")?.optJSONObject("entity") ?: throw ImportException("No se pudo leer la playlist. Prueba con el CSV de Exportify.")
        val list = entity.optJSONArray("trackList") ?: JSONArray()
        val tracks = (0 until list.length()).mapNotNull { i ->
            val t = list.optJSONObject(i) ?: return@mapNotNull null
            val title = t.optString("title").ifEmpty { return@mapNotNull null }
            AMTrack(
                title, t.optString("subtitle").replace(' ', ' '),
                duration = t.optDouble("duration", 0.0) / 1000, explicit = t.optBoolean("isExplicit"),
            )
        }
        if (tracks.isEmpty()) throw ImportException("La playlist está vacía o no es pública.")
        val cover = entity.optJSONObject("coverArt")?.optJSONArray("sources")?.optJSONObject(0)?.optString("url")?.ifEmpty { null }
        return AMPlaylist(entity.optString("name").ifEmpty { "Playlist de Spotify" }, tracks, cover)
    }
}

// MARK: CSV de Exportify --------------------------------------------------------------------------

object ExportifyCsv {
    /** Las cabeceras de Exportify cambian con el idioma; el orden no. Posiciones desde «Track URI». */
    private const val NAME = 1
    private const val ARTISTS = 3
    private const val ALBUM = 5
    private const val DURATION = 12
    private const val EXPLICIT = 14
    private const val ISRC = 16

    fun parse(name: String, text: String): AMPlaylist {
        val rows = rows(text.removePrefix("﻿"))
        if (rows.size < 2) throw ImportException("El archivo no tiene canciones.")
        val header = rows.first()
        // La columna de «Track URI» es la que tiene spotify:track:… en la primera fila de datos.
        val start = rows[1].indexOfFirst { it.startsWith("spotify:track:") || it.startsWith("spotify:local:") }
        if (start < 0) throw ImportException("No parece un CSV de Exportify (falta la columna «Track URI»).")
        val isrcCol = header.indexOfFirst { it.trim().equals("ISRC", ignoreCase = true) }.takeIf { it >= 0 } ?: (start + ISRC)
        val tracks = rows.drop(1).mapNotNull { r ->
            fun col(i: Int) = r.getOrNull(i)?.trim().orEmpty()
            val title = col(start + NAME).ifEmpty { return@mapNotNull null }
            AMTrack(
                title,
                col(start + ARTISTS).replace("\\,", ","),
                col(start + ALBUM),
                (col(start + DURATION).toDoubleOrNull() ?: 0.0) / 1000,
                col(isrcCol).ifEmpty { null },
                col(start + EXPLICIT).lowercase().let { if (it == "true") true else if (it == "false") false else null },
            )
        }
        if (tracks.isEmpty()) throw ImportException("El archivo no tiene canciones.")
        return AMPlaylist(name.substringBeforeLast('.').replace('_', ' ').ifBlank { "Playlist de Spotify" }, tracks, null)
    }

    /** CSV con comillas dobles (RFC 4180): comas y saltos de línea dentro de comillas, "" = comilla. */
    fun rows(text: String): List<List<String>> {
        val out = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val cell = StringBuilder()
        var quoted = false
        var i = 0
        while (i < text.length) {
            val ch = text[i]
            when {
                quoted && ch == '"' && text.getOrNull(i + 1) == '"' -> { cell.append('"'); i++ }
                ch == '"' -> quoted = !quoted
                !quoted && ch == ',' -> { row.add(cell.toString()); cell.clear() }
                !quoted && (ch == '\n' || ch == '\r') -> {
                    if (ch == '\r' && text.getOrNull(i + 1) == '\n') i++
                    row.add(cell.toString()); cell.clear()
                    if (row.any { it.isNotEmpty() }) out.add(row)
                    row = mutableListOf()
                }
                else -> cell.append(ch)
            }
            i++
        }
        row.add(cell.toString())
        if (row.any { it.isNotEmpty() }) out.add(row)
        return out
    }
}

// MARK: Copia de SimpMusic ------------------------------------------------------------------------

/** Una playlist de SimpMusic: sus canciones ya son de YouTube Music (por videoId), sin emparejar. */
data class SimpPlaylist(val name: String, val songs: List<Song>, val cover: String?)

object SimpMusicBackup {
    /** Nombre de la base de datos dentro del ZIP (`DB_NAME` en SimpMusic). */
    private const val DB = "Music Database"

    /**
     * Lee el `.backup` (ZIP con la base SQLite de SimpMusic, esquema 27): sus playlists en orden
     * (`local_playlist` + `pair_song_local_playlist`) y, si las hay, «Canciones que te gustan» (`song.liked`).
     */
    suspend fun read(context: Context, uri: Uri): List<SimpPlaylist> = withContext(Dispatchers.IO) {
        val tmp = File(context.cacheDir, "simpmusic.db")
        try {
            var found = false
            context.contentResolver.openInputStream(uri)?.use { input ->
                ZipInputStream(input.buffered()).use { zip ->
                    generateSequence { zip.nextEntry }.forEach { e ->
                        if (!found && e.name.substringAfterLast('/') == DB) {
                            tmp.outputStream().use { zip.copyTo(it) }
                            found = true
                        }
                    }
                }
            }
            if (!found) throw ImportException("No es una copia de SimpMusic (en SimpMusic: Ajustes › Copia de seguridad).")
            readDatabase(tmp)
        } finally {
            tmp.delete()
            File(tmp.path + "-journal").delete()
        }
    }

    fun readDatabase(file: File): List<SimpPlaylist> {
        val db = runCatching { SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY) }
            .getOrElse { throw ImportException("La copia de SimpMusic está dañada.") }
        return db.use {
            val out = mutableListOf<SimpPlaylist>()
            it.rawQuery("SELECT id, title, thumbnail FROM local_playlist ORDER BY id", null).use { c ->
                while (c.moveToNext()) {
                    val songs = songs(
                        it,
                        "SELECT s.videoId, s.title, s.artistName, s.thumbnails FROM pair_song_local_playlist p " +
                            "JOIN song s ON s.videoId = p.songId WHERE p.playlistId = ? AND p.inPlaylist = 1 ORDER BY p.position",
                        arrayOf(c.getLong(0).toString()),
                    )
                    out += SimpPlaylist(c.getString(1) ?: "Playlist", songs, c.getString(2))
                }
            }
            val liked = songs(it, "SELECT videoId, title, artistName, thumbnails FROM song WHERE liked = 1 ORDER BY favoriteAt DESC", null)
            if (liked.isNotEmpty()) out.add(0, SimpPlaylist("Canciones que te gustan (SimpMusic)", liked, null))
            out
        }
    }

    private fun songs(db: SQLiteDatabase, sql: String, args: Array<String>?): List<Song> =
        db.rawQuery(sql, args).use { c ->
            buildList {
                while (c.moveToNext()) {
                    val id = c.getString(0) ?: continue
                    add(Song(id, c.getString(1) ?: "", c.getString(2) ?: "", c.getString(3)?.takeIf { it.startsWith("http") }))
                }
            }
        }
}

// MARK: Emparejado de una lista entera ------------------------------------------------------------

/** El resultado de una canción: la elegida (si hay), su confianza y los candidatos para elegir a mano. */
data class TrackMatch(
    val track: AMTrack,
    val choice: Song?,
    val confidence: Matcher.Confidence,
    val candidates: List<Matcher.Scored>,
)

object ImportMatcher {
    /**
     * Busca cada canción en YouTube Music, 3 a la vez y con una pausa corta entre búsquedas para no
     * saturar a YouTube; reintenta 2 veces si falla la red. Con ISRC lo busca primero por el ISRC. Guarda
     * el avance en [job] para poder seguir si se corta.
     */
    suspend fun matchAll(tracks: List<AMTrack>, job: ImportJob?, progress: (Int) -> Unit): List<TrackMatch> = coroutineScope {
        val gate = Semaphore(3)
        val done = AtomicInteger(job?.results?.size ?: 0)
        tracks.mapIndexed { i, t ->
            async(Dispatchers.IO) {
                job?.results?.get(i)?.let { return@async it }
                gate.withPermit {
                    val m = matchOne(t)
                    job?.record(i, m)
                    progress(done.incrementAndGet())
                    delay(120)
                    m
                }
            }
        }.map { it.await() }
    }

    fun matchOne(t: AMTrack): TrackMatch {
        val pool = LinkedHashMap<String, YTClient.Candidate>()
        // El ISRC suele llevar directo a la grabación exacta.
        t.isrc?.let { isrc -> search(isrc).forEach { pool.putIfAbsent(it.song.id, it) } }
        search("${t.title} ${t.artist.split(",").first()}").forEach { pool.putIfAbsent(it.song.id, it) }
        val ranked = Matcher.ranked(t.title, t.artist, t.album, t.duration, pool.values.toList(), t.explicit)
        val confidence = Matcher.confidence(ranked)
        return TrackMatch(t, ranked.firstOrNull()?.takeIf { confidence == Matcher.Confidence.Good }?.song, confidence, ranked.take(5))
    }

    private fun search(q: String): List<YTClient.Candidate> {
        repeat(3) { attempt ->
            runCatching { return YTClient.searchCandidates(q) }
            Thread.sleep(400L * (attempt + 1))
        }
        return emptyList()
    }
}

/**
 * Una importación en curso guardada en `filesDir/import_job.json`, para seguir donde se quedó si se cierra
 * la app o se corta la red.
 */
class ImportJob(private val file: File, val playlist: AMPlaylist) {
    val results = java.util.concurrent.ConcurrentHashMap<Int, TrackMatch>()

    @Synchronized fun record(i: Int, m: TrackMatch) {
        results[i] = m
        runCatching { file.writeText(toJson().toString()) }
    }

    fun discard() { file.delete() }

    private fun toJson(): JSONObject = JSONObject()
        .put("name", playlist.name).put("artwork", playlist.artwork ?: JSONObject.NULL)
        .put("tracks", JSONArray().apply { playlist.tracks.forEach { put(trackJson(it)) } })
        .put("results", JSONObject().apply { results.forEach { (i, m) -> put(i.toString(), matchJson(m)) } })

    companion object {
        fun file(context: Context) = File(context.filesDir, "import_job.json")

        fun start(context: Context, playlist: AMPlaylist) = ImportJob(file(context), playlist)

        /** La importación a medias, si la hay. */
        fun pending(context: Context): ImportJob? = runCatching {
            val o = JSONObject(file(context).readText())
            val tracks = o.getJSONArray("tracks").let { a -> (0 until a.length()).map { trackFrom(a.getJSONObject(it)) } }
            val job = ImportJob(file(context), AMPlaylist(o.getString("name"), tracks, o.optString("artwork").ifEmpty { null }.takeIf { it != "null" }))
            val r = o.getJSONObject("results")
            r.keys().forEach { k -> job.results[k.toInt()] = matchFrom(tracks[k.toInt()], r.getJSONObject(k)) }
            job
        }.getOrNull()

        private fun trackJson(t: AMTrack) = JSONObject().put("title", t.title).put("artist", t.artist).put("album", t.album)
            .put("duration", t.duration).put("isrc", t.isrc ?: JSONObject.NULL).put("explicit", t.explicit ?: JSONObject.NULL)

        private fun trackFrom(o: JSONObject) = AMTrack(
            o.optString("title"), o.optString("artist"), o.optString("album"), o.optDouble("duration", 0.0),
            o.optString("isrc").ifEmpty { null }.takeIf { it != "null" },
            if (o.isNull("explicit")) null else o.optBoolean("explicit"),
        )

        private fun matchJson(m: TrackMatch) = JSONObject()
            .put("choice", m.choice?.toJson() ?: JSONObject.NULL).put("confidence", m.confidence.name)
            .put("candidates", JSONArray().apply { m.candidates.forEach { put(JSONObject().put("song", it.song.toJson()).put("score", it.score)) } })

        private fun matchFrom(t: AMTrack, o: JSONObject) = TrackMatch(
            t,
            o.optJSONObject("choice")?.let(Song::fromJson),
            Matcher.Confidence.valueOf(o.optString("confidence", "None")),
            o.optJSONArray("candidates")?.let { a ->
                (0 until a.length()).map { val c = a.getJSONObject(it); Matcher.Scored(Song.fromJson(c.getJSONObject("song")), c.optInt("score")) }
            }.orEmpty(),
        )
    }
}
