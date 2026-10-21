package app.libremusic.data

import android.content.Context
import android.content.SharedPreferences
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Cliente mínimo de la API interna (InnerTube) de YouTube Music.
 * Port de `YTClient` (apps/ios/Sources/Client.swift): mismas peticiones y misma cadena de clientes.
 * ⚠️ API no oficial: versiones y parámetros pueden cambiar y romper la app.
 *
 * Todas las funciones de red son bloqueantes: llámalas desde Dispatchers.IO.
 */
object YTClient {
    private const val WEB_REMIX_VERSION = "1.20240918.01.00"
    private const val MUSIC = "https://music.youtube.com/youtubei/v1"
    private const val SONGS_PARAMS = "EgWKAQIIAWoKEAkQBRAKEAMQBA=="
    private const val VIDEOS_PARAMS = "EgWKAQIQAWoKEAkQBRAKEAMQBA=="
    private const val ALBUMS_PARAMS = "EgWKAQIYAWoKEAkQBRAKEAMQBA=="
    private const val ARTISTS_PARAMS = "EgWKAQIgAWoKEAkQBRAKEAMQBA=="
    private val JSON_TYPE = "application/json; charset=utf-8".toMediaType()
    private val ORIGIN = mapOf("Origin" to "https://music.youtube.com")
    // También en los idiomas en que se pide Inicio (1.8 de x.1.1): catalán, euskera, inglés y portugués.
    private val KINDS = setOf(
        "Canción", "Vídeo", "Video", "Song", "Episodio", "Álbum", "Single", "EP",
        "Cançó", "Àlbum", "Abestia", "Bideoa", "Albuma", "Album", "Episode", "Música",
    )
    private val DURATION = Regex("^\\d+:\\d{2}(:\\d{2})?$")

    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    private var prefs: SharedPreferences? = null

    /**
     * Identificador de visitante; se reenvía al pedir el audio. Sin él YouTube suele responder
     * "confirma que no eres un bot". Caduca a los [VISITOR_TTL_MS]: uno viejo hace que YouTube dé
     * URLs de audio que luego rechaza con 403 (visto en un móvil con uno de hacía un día).
     */
    @Volatile
    var visitorData: String? = null
        private set

    private const val VISITOR_TTL_MS = 3 * 24 * 60 * 60 * 1000L

    fun init(context: Context) {
        prefs = context.getSharedPreferences("youtube", Context.MODE_PRIVATE)
        val at = prefs?.getLong("visitorDataAt", 0L) ?: 0L
        visitorData = prefs?.getString("visitorData", null)
            ?.takeIf { System.currentTimeMillis() - at < VISITOR_TTL_MS }
    }

    private fun saveVisitorData(value: String) {
        if (value == visitorData) return
        visitorData = value
        prefs?.edit()?.putString("visitorData", value)?.putLong("visitorDataAt", System.currentTimeMillis())?.apply()
    }

    /** Olvida el identificador de visitante (tras un 403): la próxima petición pide uno nuevo. */
    fun resetVisitorData() {
        visitorData = null
        prefs?.edit()?.remove("visitorData")?.remove("visitorDataAt")?.apply()
    }

    /**
     * Siempre en «es» salvo Inicio ([home], 1.8 de x.1.1): al leer búsquedas y artistas se reconocen los tipos
     * («Canción», «Álbum»…) en español.
     */
    private fun webContext(hl: String = "es"): JSONObject = JSONObject().put(
        "client",
        JSONObject()
            .put("clientName", "WEB_REMIX")
            .put("clientVersion", WEB_REMIX_VERSION)
            .put("hl", hl),
    )

    fun post(url: String, body: JSONObject, headers: Map<String, String>): JSONObject {
        val request = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody(JSON_TYPE))
            .apply { headers.forEach { (k, v) -> header(k, v) } }
            .build()
        http.newCall(request).execute().use { response ->
            val text = response.body?.string() ?: throw IOException("respuesta vacía")
            return JSONObject(text)
        }
    }

    private fun rememberVisitorData(json: JSONObject) {
        json.optJSONObject("responseContext")?.optString("visitorData")
            ?.takeIf { it.isNotEmpty() }
            ?.let(::saveVisitorData)
    }

    fun ensureVisitorData() {
        if (visitorData != null) return
        runCatching {
            post("$MUSIC/visitor_id?prettyPrint=false", JSONObject().put("context", webContext()), ORIGIN)
        }.getOrNull()?.let(::rememberVisitorData)
    }

    // region Búsqueda

    fun search(query: String): List<Song> = searchCandidates(query).map { it.song }

    /** Búsqueda con álbum y duración (para elegir la versión correcta). [videos]: vídeos en vez de canciones. */
    fun searchCandidates(query: String, videos: Boolean = false): List<Candidate> {
        val body = JSONObject()
            .put("context", webContext())
            .put("query", query)
            .put("params", if (videos) VIDEOS_PARAMS else SONGS_PARAMS)
        val json = post("$MUSIC/search?prettyPrint=false", body, ORIGIN)
        rememberVisitorData(json)
        return parseCandidates(json)
    }

    /**
     * Canciones, álbumes y artistas a la vez (tres búsquedas filtradas en paralelo), como
     * `searchAll` en iOS. Sólo falla si fallan las tres; si una falla, su sección sale vacía.
     */
    fun searchAll(query: String): SearchResults {
        // Modo seguro (Fase 4): sin búsqueda remota; la música guardada y descargada sigue funcionando.
        if (Incident.restricted) throw java.io.IOException("La búsqueda está en pausa mientras resolvemos un incidente.")
        val pool = java.util.concurrent.Executors.newFixedThreadPool(3)
        try {
            val songs = pool.submit<List<Song>?> { runCatching { search(query) }.getOrNull() }
            val albums = pool.submit<List<Any>?> { runCatching { searchBrowsable(query, ALBUMS_PARAMS) }.getOrNull() }
            val artists = pool.submit<List<Any>?> { runCatching { searchBrowsable(query, ARTISTS_PARAMS) }.getOrNull() }
            val s = songs.get(); val al = albums.get(); val ar = artists.get()
            if (s == null && al == null && ar == null) throw IOException("No se pudo buscar")
            return SearchResults(
                songs = s.orEmpty(),
                albums = al.orEmpty().filterIsInstance<RemoteCollection>(),
                artists = ar.orEmpty().filterIsInstance<RemoteArtist>(),
            )
        } finally {
            pool.shutdown()
        }
    }

    /** Artistas que coinciden con [query] (búsqueda filtrada). */
    fun searchArtists(query: String): List<RemoteArtist> = searchBrowsable(query, ARTISTS_PARAMS).filterIsInstance<RemoteArtist>()

    /** Álbumes o artistas de una búsqueda filtrada (filas con browseId en vez de videoId). */
    private fun searchBrowsable(query: String, params: String): List<Any> {
        val body = JSONObject().put("context", webContext()).put("query", query).put("params", params)
        val json = post("$MUSIC/search?prettyPrint=false", body, ORIGIN)
        val out = mutableListOf<Any>()
        collect(json, "musicResponsiveListItemRenderer") { item ->
            val bid = item.optJSONObject("navigationEndpoint")?.optJSONObject("browseEndpoint")?.optString("browseId").orEmpty()
            val cols = item.optJSONArray("flexColumns") ?: return@collect
            fun text(i: Int) = runsText(cols.optJSONObject(i)?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")?.optJSONObject("text"))
            val url = lastUrl(item.optJSONObject("thumbnail")?.optJSONObject("musicThumbnailRenderer")?.optJSONObject("thumbnail")?.optJSONArray("thumbnails"))
            when {
                // «Álbum • Beyoncé • 2024»: se guarda tal cual (collectionSongs saca el artista del 2.º trozo).
                bid.startsWith("MPREb") -> out += RemoteCollection(bid, text(0), text(1), url)
                // «Artista • 435 M usuarios mensuales» → «435 M usuarios mensuales».
                bid.startsWith("UC") -> out += RemoteArtist(bid, text(0), text(1).split(" • ").drop(1).joinToString(" • "), url)
            }
        }
        return out
    }

    /**
     * Página de un artista. Los álbumes de su página sólo traen el año: se les pone
     * «Álbum • Artista • año» para que se vean igual que en la búsqueda y collectionSongs sepa el artista.
     */
    fun artist(artist: RemoteArtist): ArtistPage {
        val json = browse(JSONObject().put("browseId", artist.id))
        val headerWrap = json.optJSONObject("header")
        val header = headerWrap?.keys()?.asSequence()?.firstOrNull()?.let { headerWrap.optJSONObject(it) }
        val name = runsText(header?.optJSONObject("title")).ifEmpty { artist.name }
        var headerThumb: String? = null
        collect(header, "musicThumbnailRenderer") { mtr ->
            if (headerThumb == null) headerThumb = lastUrl(mtr.optJSONObject("thumbnail")?.optJSONArray("thumbnails"))
        }
        var songs = emptyList<Song>()
        collect(json, "musicShelfRenderer") { shelf -> if (songs.isEmpty()) songs = parseSongs(shelf) }
        val carousels = mutableListOf<List<RemoteCollection>>()
        val more = mutableListOf<BrowseRef?>()
        collect(json, "musicCarouselShelfRenderer") { shelf ->
            val items = mutableListOf<RemoteCollection>()
            collect(shelf, "musicTwoRowItemRenderer") { item ->
                val c = (parseTwoRow(item) as? HomeItem.CollectionItem)?.collection ?: return@collect
                if (!c.id.startsWith("MPREb")) return@collect
                val parts = c.subtitle.split(" • ")
                val kind = if (parts.size > 1) parts[0] else "Álbum"
                val year = parts.last()
                items += c.copy(subtitle = listOf(kind, name, year).filter { it.isNotEmpty() }.joinToString(" • "))
            }
            if (items.isNotEmpty()) {
                carousels += items
                // «Ver todo» de la sección: la página de discografía completa (lo que hace SimpMusic).
                val end = shelf.optJSONObject("header")?.optJSONObject("musicCarouselShelfBasicHeaderRenderer")
                    ?.optJSONObject("moreContentButton")?.optJSONObject("buttonRenderer")
                    ?.optJSONObject("navigationEndpoint")?.optJSONObject("browseEndpoint")
                more += end?.optString("browseId")?.ifEmpty { null }?.let { BrowseRef(it, end.optString("params").ifEmpty { null }) }
            }
        }
        return ArtistPage(
            name = name,
            thumbnail = headerThumb ?: artist.thumbnail,
            songs = songs.map { if (it.artist.isEmpty()) it.copy(artist = name) else it },
            albums = carousels.getOrNull(0).orEmpty(),
            singles = carousels.getOrNull(1).orEmpty(),
            albumsMore = more.getOrNull(0),
            singlesMore = more.getOrNull(1),
        )
    }

    /**
     * Discografía completa de una sección del artista («Ver todo»): YouTube Music la devuelve entera en una
     * cuadrícula. Mismo formato de subtítulo que [artist] («Single • Artista • 2024»).
     */
    fun discography(ref: BrowseRef, artistName: String): List<RemoteCollection> {
        val body = JSONObject().put("browseId", ref.browseId)
        ref.params?.let { body.put("params", it) }
        val json = browse(body)
        val out = mutableListOf<RemoteCollection>()
        val seen = HashSet<String>()
        collect(json, "musicTwoRowItemRenderer") { item ->
            val c = (parseTwoRow(item) as? HomeItem.CollectionItem)?.collection ?: return@collect
            if (!c.id.startsWith("MPREb") || !seen.add(c.id)) return@collect
            val parts = c.subtitle.split(" • ")
            val kind = if (parts.size > 1) parts[0] else "Álbum"
            out += c.copy(subtitle = listOf(kind, artistName, parts.last()).filter { it.isNotEmpty() }.joinToString(" • "))
        }
        return out
    }

    /** El artista con ese nombre exacto (sin tildes ni mayúsculas), para abrir su perfil desde un álbum o una canción. */
    fun findArtist(name: String): RemoteArtist? {
        val key = Discography.normalize(name)
        val artists = searchAll(name).artists
        return artists.firstOrNull { Discography.normalize(it.name) == key } ?: artists.firstOrNull()?.takeIf { key.isNotEmpty() && Discography.normalize(it.name).startsWith(key) }
    }

    fun suggestions(query: String): List<String> {
        val body = JSONObject().put("context", webContext()).put("input", query)
        val json = post("$MUSIC/music/get_search_suggestions?prettyPrint=false", body, ORIGIN)
        val out = LinkedHashSet<String>()
        collect(json, "searchSuggestionRenderer") { item ->
            val text = runsText(item.optJSONObject("suggestion"))
            if (text.isNotEmpty()) out += text
        }
        return out.take(8)
    }

    // region Inicio y colecciones (igual que Client.swift en iOS)

    private fun browse(body: JSONObject, hl: String = "es"): JSONObject {
        ensureVisitorData()
        body.put("context", webContext(hl))
        return post("$MUSIC/browse?prettyPrint=false", body, ORIGIN)
    }

    /** Recomendaciones de YouTube Music para la pantalla Inicio (sin sesión). */
    fun home(): List<HomeShelf> {
        // Los títulos de las estanterías («Selecciones rápidas»…) vienen de YouTube: en el idioma de la app.
        val json = browse(JSONObject().put("browseId", "FEmusic_home"), app.libremusic.I18n.youtubeHl)
        val shelves = mutableListOf<HomeShelf>()
        collect(json, "musicCarouselShelfRenderer") { shelf ->
            val header = shelf.optJSONObject("header")?.optJSONObject("musicCarouselShelfBasicHeaderRenderer")
            val items = parseSongs(shelf).map<Song, HomeItem> { HomeItem.SongItem(it) }.toMutableList()
            collect(shelf, "musicTwoRowItemRenderer") { parseTwoRow(it)?.let(items::add) }
            if (items.isNotEmpty()) shelves += HomeShelf(runsText(header?.optJSONObject("title")), items)
        }
        return shelves
    }

    private fun parseTwoRow(item: JSONObject): HomeItem? {
        val title = runsText(item.optJSONObject("title"))
        val subtitle = runsText(item.optJSONObject("subtitle"))
        val thumbs = item.optJSONObject("thumbnailRenderer")?.optJSONObject("musicThumbnailRenderer")
            ?.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
        val url = lastUrl(thumbs)
        val nav = item.optJSONObject("navigationEndpoint")
        nav?.optJSONObject("watchEndpoint")?.optString("videoId")?.takeIf { it.isNotEmpty() }?.let {
            return HomeItem.SongItem(Song(it, title, subtitle, url))
        }
        val bid = nav?.optJSONObject("browseEndpoint")?.optString("browseId").orEmpty()
        if (bid.startsWith("MPREb") || bid.startsWith("VL")) {
            return HomeItem.CollectionItem(RemoteCollection(bid, title, subtitle, url))
        }
        return null
    }

    /** Canciones de un álbum o playlist pública. Los álbumes no traen carátula por pista: se usa la del álbum. */
    fun collectionSongs(c: RemoteCollection): List<Song> {
        val parts = c.subtitle.split(" • ")
        val fallbackArtist = if (parts.size > 1) parts[1] else c.subtitle
        val all = mutableListOf<Song>()
        val seen = HashSet<String>()
        var json = browse(JSONObject().put("browseId", c.id))
        repeat(10) {
            for (s in parseSongs(json)) {
                if (!seen.add(s.id)) continue
                all += Song(s.id, s.title, s.artist.ifEmpty { fallbackArtist }, s.thumbnail ?: c.thumbnail)
            }
            val token = continuationToken(json) ?: return all
            json = browse(JSONObject().put("continuation", token))
        }
        return all
    }

    private fun continuationToken(json: JSONObject): String? {
        var tok: String? = null
        collect(json, "continuationCommand") { if (tok == null) tok = it.optString("token").ifEmpty { null } }
        if (tok == null) collect(json, "nextContinuationData") { if (tok == null) tok = it.optString("continuation").ifEmpty { null } }
        return tok
    }

    // endregion

    /** "Radio" de una canción: unas 50 canciones parecidas (se usa para continuar la cola). */
    fun radio(videoId: String): List<Song> {
        ensureVisitorData()
        val body = JSONObject()
            .put("context", webContext())
            .put("videoId", videoId)
            .put("playlistId", "RDAMVM$videoId")
            .put("isAudioOnly", true)
        val json = post("$MUSIC/next?prettyPrint=false", body, ORIGIN)
        val out = mutableListOf<Song>()
        val seen = hashSetOf(videoId)
        collect(json, "playlistPanelVideoRenderer") { item ->
            val vid = item.optString("videoId")
            if (vid.isEmpty() || !seen.add(vid)) return@collect
            val thumbs = item.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
            val artist = runsText(item.optJSONObject("shortBylineText")).split(" • ").first()
            out += Song(vid, runsText(item.optJSONObject("title")), artist, lastUrl(thumbs))
        }
        return out
    }

    /**
     * Título, artista y carátula de una lista de canciones por su id, en el mismo orden (0.6 de x.1.1: una playlist
     * compartida por QR sólo lleva los ids). La cola de YouTube Music (`music/get_queue`) da hasta 50 de golpe. Las
     * que no vengan se quedan fuera.
     */
    fun songs(ids: List<String>): List<Song> {
        ensureVisitorData()
        val found = HashMap<String, Song>()
        ids.distinct().chunked(50).forEach { chunk ->
            val body = JSONObject().put("context", webContext()).put("videoIds", org.json.JSONArray(chunk))
            val json = runCatching { post("$MUSIC/music/get_queue?prettyPrint=false", body, ORIGIN) }.getOrNull() ?: return@forEach
            collect(json, "playlistPanelVideoRenderer") { item ->
                val vid = item.optString("videoId")
                if (vid.isEmpty() || vid in found) return@collect
                val thumbs = item.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
                val artist = runsText(item.optJSONObject("shortBylineText")).split(" • ").first()
                found[vid] = Song(vid, runsText(item.optJSONObject("title")), artist, lastUrl(thumbs))
            }
        }
        return ids.mapNotNull { found[it] }
    }

    /** Resultado de búsqueda con el álbum y la duración (s), como `Candidate` en iOS. */
    data class Candidate(val song: Song, val album: String, val duration: Double?)

    /** Extrae canciones/vídeos de cualquier respuesta (búsqueda o lista). */
    fun parseSongs(json: Any): List<Song> = parseCandidates(json).map { it.song }

    fun parseCandidates(json: Any): List<Candidate> {
        val out = mutableListOf<Candidate>()
        val seen = HashSet<String>()
        collect(json, "musicResponsiveListItemRenderer") { item ->
            var vid: String? = item.optJSONObject("playlistItemData")?.optString("videoId")?.ifEmpty { null }
            if (vid == null) {
                collect(item, "watchEndpoint") { endpoint ->
                    if (vid == null) vid = endpoint.optString("videoId").ifEmpty { null }
                }
            }
            val videoId = vid ?: return@collect
            val cols = item.optJSONArray("flexColumns") ?: return@collect
            if (videoId in seen || cols.length() == 0) return@collect

            fun runs(i: Int): List<String> {
                if (i >= cols.length()) return emptyList()
                val arr = cols.optJSONObject(i)
                    ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                    ?.optJSONObject("text")
                    ?.optJSONArray("runs") ?: return emptyList()
                return (0 until arr.length()).mapNotNull { arr.optJSONObject(it)?.optString("text") }
            }

            val title = runs(0).firstOrNull() ?: "Sin título"
            // "Artista y Otro • Álbum • 3:08": el primer segmento son los artistas completos.
            val raw = runs(1).joinToString("").split(" • ").map { it.trim() }
            val duration = raw.firstOrNull { DURATION.matches(it) }
                ?.split(":")?.fold(0.0) { acc, part -> acc * 60 + (part.toDoubleOrNull() ?: 0.0) }
            val segments = raw.filter { it.isNotEmpty() && it !in KINDS && !DURATION.matches(it) }
            val thumbs = item.optJSONObject("thumbnail")
                ?.optJSONObject("musicThumbnailRenderer")
                ?.optJSONObject("thumbnail")
                ?.optJSONArray("thumbnails")
            seen += videoId
            out += Candidate(
                Song(videoId, title, segments.firstOrNull().orEmpty(), lastUrl(thumbs)),
                segments.getOrNull(1).orEmpty(), duration,
            )
        }
        return out
    }

    // endregion

    // region URL de audio: prueba varios clientes hasta que uno devuelva una URL directa

    /** [durationMs]: duración de la canción si YouTube la da (Descubrir empieza directo en el estribillo). */
    /**
     * [loudnessDb]: cuánto más fuerte (positivo) o más flojo que la referencia de YouTube suena la canción
     * (`playerConfig.audioConfig.loudnessDb`); lo usa `Normalizer` para igualar el volumen entre canciones.
     */
    data class StreamInfo(val url: String, val userAgent: String, val durationMs: Long? = null, val loudnessDb: Double? = null)

    private class Profile(val name: String, val client: JSONObject, val userAgent: String)

    // Sólo VISIONOS da URLs sin «PO token» (yt-dlp, 2026-10). IOS responde sin URLs y las de
    // ANDROID_VR dan 403 a los pocos segundos desde 2026-08, así que se han quitado. Lo que
    // VISIONOS no sirve se busca en otra subida de la misma canción ([alternatives]).
    private fun profiles(): List<Profile> = listOf(
        Profile(
            "VISIONOS",
            JSONObject()
                .put("clientName", "VISIONOS").put("clientVersion", "1.02")
                .put("deviceMake", "Apple").put("deviceModel", "RealityDevice17,1")
                .put("osName", "visionOS").put("osVersion", "26.5.23O471").put("hl", "es"),
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
        ),
    )

    fun streamUrl(videoId: String, lowQuality: Boolean = false): StreamInfo {
        ensureVisitorData()
        val problems = mutableListOf<String>()
        for (p in profiles()) {
            try {
                val headers = mutableMapOf("User-Agent" to p.userAgent)
                visitorData?.let {
                    p.client.put("visitorData", it)
                    headers["X-Goog-Visitor-Id"] = it
                }
                val body = JSONObject()
                    .put("context", JSONObject().put("client", p.client))
                    .put("videoId", videoId)
                    .put("contentCheckOk", true)
                    .put("racyCheckOk", true)
                val json = post("https://www.youtube.com/youtubei/v1/player?prettyPrint=false", body, headers)
                val url = bestAudioUrl(json.optJSONObject("streamingData")?.optJSONArray("adaptiveFormats"), lowQuality)
                val duration = json.optJSONObject("videoDetails")?.optString("lengthSeconds")?.toLongOrNull()?.times(1000)
                val loudness = json.optJSONObject("playerConfig")?.optJSONObject("audioConfig")
                    ?.optDouble("loudnessDb", Double.NaN)?.takeIf { !it.isNaN() }
                if (url != null) return StreamInfo(url, p.userAgent, duration, loudness)
                val status = json.optJSONObject("playabilityStatus")
                val reason = status?.optString("reason").orEmpty()
                problems += reason.ifEmpty { "${p.name}: ${status?.optString("status") ?: "sin_estado"}" }
            } catch (e: Exception) {
                problems += "${p.name}: error de red/JSON"
            }
        }
        throw IOException(problems.joinToString(" | "))
    }

    /** Otras subidas de la misma canción (audio oficial, videoclip…), como `alternatives` en iOS. */
    fun alternatives(title: String, artist: String, exclude: String): List<Song> {
        val query = "$title $artist"
        val pool = runCatching { searchCandidates(query) }.getOrDefault(emptyList()) +
            runCatching { searchCandidates(query, videos = true) }.getOrDefault(emptyList())
        return app.libremusic.data.Matcher.ranked(title, artist, "", 0.0, pool.filter { it.song.id != exclude })
            .filter { it.score >= 60 }
            .take(3)
            .map { it.song }
    }

    private val alternateId = java.util.concurrent.ConcurrentHashMap<String, String>()

    /**
     * Como [streamUrl], pero si YouTube no deja reproducir esa subida prueba otras de la misma
     * canción (playableStream en iOS). Sin título no se puede buscar otra.
     */
    fun playableStream(videoId: String, title: String?, artist: String?, lowQuality: Boolean = false): StreamInfo {
        alternateId[videoId]?.let { alt -> runCatching { return streamUrl(alt, lowQuality) } }
        try {
            return streamUrl(videoId, lowQuality)
        } catch (e: IOException) {
            if (!title.isNullOrBlank()) {
                for (other in alternatives(title, artist.orEmpty(), videoId)) {
                    val info = runCatching { streamUrl(other.id, lowQuality) }.getOrNull() ?: continue
                    alternateId[videoId] = other.id
                    return info
                }
            }
            // VISIONOS no sirve el contenido «para niños» y ningún cliente sin cuenta lo da (2026-10).
            if (e.message.orEmpty().contains("no está disponible")) {
                throw IOException("YouTube no deja escuchar esta canción sin cuenta (suele pasar con el contenido para niños) y no hay otra versión.")
            }
            throw e
        }
    }

    /**
     * El audio de más calidad con URL directa (o el de menos, con «Ahorro de datos»). Se prefiere **Opus** (WebM,
     * ~160 kbps en «Máxima»), que suena mejor que el AAC de 128 kbps al mismo tamaño; si no viene o el móvil no
     * tiene decodificador de Opus, AAC (audio/mp4). iOS se queda con AAC: AVPlayer no reproduce WebM.
     */
    fun bestAudioUrl(formats: JSONArray?, lowest: Boolean = false, opus: Boolean = OpusSupport.available): String? {
        if (formats == null) return null
        fun pick(mime: String): JSONObject? {
            var best: JSONObject? = null
            for (i in 0 until formats.length()) {
                val f = formats.optJSONObject(i) ?: continue
                if (!f.optString("mimeType").startsWith(mime) || !f.has("url")) continue
                val current = best
                val better = if (lowest) f.optInt("bitrate") < (current?.optInt("bitrate") ?: Int.MAX_VALUE)
                else f.optInt("bitrate") > (current?.optInt("bitrate") ?: -1)
                if (current == null || better) best = f
            }
            return best
        }
        val best = (if (opus) pick("audio/webm") else null) ?: pick("audio/mp4")
        return best?.optString("url")?.ifEmpty { null }
    }

    // endregion

    // region Utilidades JSON

    fun runsText(node: JSONObject?): String {
        val runs = node?.optJSONArray("runs") ?: return ""
        return (0 until runs.length()).joinToString("") { runs.optJSONObject(it)?.optString("text").orEmpty() }
    }

    private fun lastUrl(thumbs: JSONArray?): String? {
        if (thumbs == null || thumbs.length() == 0) return null
        return thumbs.optJSONObject(thumbs.length() - 1)?.optString("url")?.ifEmpty { null }
    }

    /** Recorre todo el árbol JSON y llama a [found] con cada objeto bajo la clave [key]. */
    fun collect(node: Any?, key: String, found: (JSONObject) -> Unit) {
        when (node) {
            is JSONObject -> {
                val keys = node.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    val v = node.opt(k)
                    if (k == key && v is JSONObject) found(v) else collect(v, key, found)
                }
            }
            is JSONArray -> for (i in 0 until node.length()) collect(node.opt(i), key, found)
        }
    }

    // endregion
}
