import Foundation

struct Song: Identifiable, Hashable, Codable {
    let id: String          // videoId
    let title: String
    let artist: String
    let thumbnail: URL?

    /// Misma carátula a otra resolución (las URLs de YouTube Music admiten =wN-hN).
    func thumb(_ px: Int) -> URL? {
        guard let t = thumbnail?.absoluteString,
              let r = t.range(of: "=w\\d+-h\\d+[^/]*$", options: .regularExpression) else { return thumbnail }
        return URL(string: t.replacingCharacters(in: r, with: "=w\(px)-h\(px)-l90-rj")) ?? thumbnail
    }
}

enum YTError: LocalizedError {
    case noStream, badResponse, detail(String)
    var errorDescription: String? {
        switch self {
        case .detail(let d): return d
        case .noStream: return "sin stream"
        case .badResponse: return "respuesta inválida"
        }
    }
}

struct StreamInfo { let url: URL; let userAgent: String; var isHLS = false }

/// Álbum, single o playlist pública de YouTube Music (se abre sin iniciar sesión).
struct RemoteCollection: Identifiable, Hashable {
    let id: String          // browseId: "MPREb_…" (álbum) o "VL…" (playlist)
    let title: String
    let subtitle: String
    let thumbnail: URL?
}

enum HomeItem: Identifiable, Hashable {
    case song(Song)
    case collection(RemoteCollection)
    var id: String {
        switch self {
        case .song(let s): return "s" + s.id
        case .collection(let c): return "c" + c.id
        }
    }
}

struct HomeShelf: Identifiable {
    let id = UUID()
    let title: String
    let items: [HomeItem]
}

/// Artista de YouTube Music (browseId "UC…"), en la búsqueda y en su página.
struct RemoteArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let thumbnail: URL?
}

/// Lo que devuelve una búsqueda: canciones, álbumes (y singles/EP) y artistas, por separado.
struct SearchResults {
    var songs: [Song] = []
    var albums: [RemoteCollection] = []
    var artists: [RemoteArtist] = []
    var isEmpty: Bool { songs.isEmpty && albums.isEmpty && artists.isEmpty }
}

/// Página de un artista: sus canciones más escuchadas, álbumes y singles/EP.
struct ArtistPage {
    let name: String
    let thumbnail: URL?
    let songs: [Song]
    let albums: [RemoteCollection]
    let singles: [RemoteCollection]
    /// «Ver todo» de cada sección (página de discografía de YouTube Music), si la hay.
    var albumsMore: BrowseRef? = nil
    var singlesMore: BrowseRef? = nil
}

/// Una página de YouTube Music a la que se llega con browseId + params (p. ej. la discografía completa).
struct BrowseRef: Hashable { let browseId: String; let params: String? }

struct RemotePlaylist: Identifiable {
    let id: String          // playlistId (sin el prefijo "VL")
    let title: String
    let subtitle: String
    let thumbnail: URL?
}

enum SearchFilter: String, CaseIterable, Identifiable {
    case songs, videos, albums, artists, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .songs: return "Canciones"
        case .videos: return "Vídeos"
        case .albums: return "Álbumes"
        case .artists: return "Artistas"
        case .all: return "Todo"
        }
    }
    var params: String? {
        switch self {
        case .songs: return "EgWKAQIIAWoKEAkQBRAKEAMQBA=="
        case .videos: return "EgWKAQIQAWoKEAkQBRAKEAMQBA=="
        case .albums: return "EgWKAQIYAWoKEAkQBRAKEAMQBA=="
        case .artists: return "EgWKAQIgAWoKEAkQBRAKEAMQBA=="
        case .all: return nil
        }
    }
}

/// Cliente mínimo de la API interna (InnerTube) de YouTube Music.
/// ⚠️ API no oficial: versiones/parámetros pueden cambiar y romper la app.
enum YTClient {
    static let iosUA = "com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)"
    /// Identificador de visitante; se reenvía al pedir el audio. Sin él YouTube suele responder
    /// "confirma que no eres un bot". Se guarda para no depender de haber buscado antes, pero caduca
    /// a los 3 días: uno viejo hace que YouTube dé URLs que luego rechaza con 403 (visto en Android).
    static var visitorData: String? = {
        let at = UserDefaults.standard.object(forKey: "visitorDataAt") as? Date ?? .distantPast
        guard Date().timeIntervalSince(at) < 3 * 24 * 3600 else { return nil }
        return UserDefaults.standard.string(forKey: "visitorData")
    }() {
        didSet {
            guard visitorData != oldValue else { return }
            UserDefaults.standard.set(visitorData, forKey: "visitorData")
            UserDefaults.standard.set(visitorData == nil ? nil : Date(), forKey: "visitorDataAt")
        }
    }

    /// Olvida el identificador de visitante (tras un fallo del audio): la próxima petición pide otro.
    static func resetVisitorData() { visitorData = nil }

    static func ensureVisitorData() async {
        guard visitorData == nil else { return }
        let json = try? await post("https://music.youtube.com/youtubei/v1/visitor_id?prettyPrint=false",
                                   body: ["context": webContext], headers: ["Origin": "https://music.youtube.com"])
        if let vd = (json?["responseContext"] as? [String: Any])?["visitorData"] as? String { visitorData = vd }
    }

    static let webContext: [String: Any] =
        ["client": ["clientName": "WEB_REMIX", "clientVersion": "1.20240918.01.00", "hl": "es"]]

    /// Sesión propia con tiempos límite: sin esto una conexión colgada deja la búsqueda
    /// o la descarga esperando 60 s (el valor por defecto) o más.
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 300
        return URLSession(configuration: c)
    }()

    static func post(_ url: String, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if headers["Cookie"] != nil { req.httpShouldHandleCookies = false }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw YTError.badResponse }
        return json
    }

    /// Petición a music.youtube.com con la sesión del usuario (cookies + SAPISIDHASH).
    static func authedPost(_ endpoint: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard let headers = Auth.headers() else { throw YTError.detail("No has iniciado sesión.") }
        let json = try await post("https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false", body: body, headers: headers)
        if let err = json["error"] as? [String: Any] {
            throw YTError.detail((err["message"] as? String) ?? "YouTube rechazó la sesión. Vuelve a iniciar sesión.")
        }
        return json
    }

    // MARK: Búsqueda
    static func search(_ query: String, filter: SearchFilter = .songs) async throws -> [Song] {
        var body: [String: Any] = ["context": webContext, "query": query]
        if let p = filter.params { body["params"] = p }
        let json = try await post("https://music.youtube.com/youtubei/v1/search?prettyPrint=false",
                                  body: body, headers: ["Origin": "https://music.youtube.com"])
        if let vd = (json["responseContext"] as? [String: Any])?["visitorData"] as? String { visitorData = vd }
        return parseSongs(json)
    }

    /// Canciones, álbumes y artistas a la vez (tres búsquedas filtradas en paralelo). Sólo falla si
    /// fallan las tres; si una falla, su sección sale vacía.
    static func searchAll(_ query: String) async throws -> SearchResults {
        // Modo seguro (Fase 4): sin búsqueda remota; la música guardada y descargada sigue funcionando.
        if Incident.restricted { throw YTError.detail("La búsqueda está en pausa mientras resolvemos un incidente.") }
        async let songs = try? search(query)
        async let albums = try? searchBrowsable(query, filter: .albums)
        async let artists = try? searchBrowsable(query, filter: .artists)
        let (s, al, ar) = await (songs, albums, artists)
        if s == nil && al == nil && ar == nil { throw URLError(.cannotLoadFromNetwork) }
        return SearchResults(
            songs: s ?? [],
            albums: (al ?? []).compactMap { if case .collection(let c) = $0 { return c } else { return nil } },
            artists: (ar ?? []).compactMap { if case .artist(let a) = $0 { return a } else { return nil } }
        )
    }

    private enum Browsable { case collection(RemoteCollection), artist(RemoteArtist) }

    /// Artistas que coinciden con `query` (búsqueda filtrada).
    static func searchArtists(_ query: String) async throws -> [RemoteArtist] {
        try await searchBrowsable(query, filter: .artists).compactMap { if case .artist(let a) = $0 { return a } else { return nil } }
    }

    /// Álbumes o artistas de una búsqueda filtrada (filas con browseId en vez de videoId).
    private static func searchBrowsable(_ query: String, filter: SearchFilter) async throws -> [Browsable] {
        var body: [String: Any] = ["context": webContext, "query": query]
        if let p = filter.params { body["params"] = p }
        let json = try await post("https://music.youtube.com/youtubei/v1/search?prettyPrint=false", body: body, headers: origin)
        var out: [Browsable] = []
        collect(json, key: "musicResponsiveListItemRenderer") { item in
            guard let bid = ((item["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
                  let cols = item["flexColumns"] as? [[String: Any]], !cols.isEmpty else { return }
            func text(_ i: Int) -> String {
                guard cols.indices.contains(i) else { return "" }
                return runsText((cols[i]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"])
            }
            let thumbs = (((item["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let url = (thumbs?.last?["url"] as? String).flatMap(URL.init)
            if bid.hasPrefix("MPREb") {
                // "Álbum • Beyoncé • 2024": se guarda tal cual (collectionSongs saca el artista del 2.º trozo).
                out.append(.collection(RemoteCollection(id: bid, title: text(0), subtitle: text(1), thumbnail: url)))
            } else if bid.hasPrefix("UC") {
                // "Artista • 435 M usuarios mensuales" → "435 M usuarios mensuales".
                let sub = text(1).components(separatedBy: " • ").dropFirst().joined(separator: " • ")
                out.append(.artist(RemoteArtist(id: bid, name: text(0), subtitle: sub, thumbnail: url)))
            }
        }
        return out
    }

    /// Página de un artista. Los álbumes de su página sólo traen el año: se les pone «Álbum • Artista • año»
    /// para que se vean igual que en la búsqueda y `collectionSongs` sepa el artista.
    static func artist(_ artist: RemoteArtist) async throws -> ArtistPage {
        let json = try await browse(["browseId": artist.id])
        let header = (json["header"] as? [String: Any])?.values.first as? [String: Any]
        let name = runsText(header?["title"]).isEmpty ? artist.name : runsText(header?["title"])
        var headerThumb: URL?
        collect(header ?? [:], key: "musicThumbnailRenderer") { mtr in
            let thumbs = (mtr["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            if headerThumb == nil { headerThumb = (thumbs?.last?["url"] as? String).flatMap(URL.init) }
        }
        var songs: [Song] = []
        var carousels: [[RemoteCollection]] = []
        var more: [BrowseRef?] = []
        collect(json, key: "musicShelfRenderer") { shelf in
            if songs.isEmpty { songs = parseSongs(shelf) }
        }
        collect(json, key: "musicCarouselShelfRenderer") { shelf in
            var items: [RemoteCollection] = []
            collect(shelf, key: "musicTwoRowItemRenderer") { item in
                guard case .collection(let c)? = parseTwoRow(item), c.id.hasPrefix("MPREb") else { return }
                let parts = c.subtitle.components(separatedBy: " • ")
                let kind = parts.count > 1 ? parts[0] : "Álbum"
                let year = parts.last ?? ""
                items.append(RemoteCollection(id: c.id, title: c.title, subtitle: [kind, name, year].filter { !$0.isEmpty }.joined(separator: " • "), thumbnail: c.thumbnail))
            }
            if !items.isEmpty {
                carousels.append(items)
                // «Ver todo» de la sección: la página de discografía completa (lo que hace SimpMusic).
                let header = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
                let button = (header?["moreContentButton"] as? [String: Any])?["buttonRenderer"] as? [String: Any]
                let end = (button?["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
                more.append((end?["browseId"] as? String).map { BrowseRef(browseId: $0, params: end?["params"] as? String) })
            }
        }
        return ArtistPage(name: name, thumbnail: headerThumb ?? artist.thumbnail,
                          songs: songs.map { Song(id: $0.id, title: $0.title, artist: $0.artist.isEmpty ? name : $0.artist, thumbnail: $0.thumbnail) },
                          albums: carousels.first ?? [], singles: carousels.count > 1 ? carousels[1] : [],
                          albumsMore: more.first ?? nil, singlesMore: more.count > 1 ? more[1] : nil)
    }

    /// Discografía completa de una sección («Ver todo»): YouTube Music la devuelve entera en una cuadrícula.
    static func discography(_ ref: BrowseRef, artist name: String) async throws -> [RemoteCollection] {
        var body: [String: Any] = ["browseId": ref.browseId]
        if let p = ref.params { body["params"] = p }
        let json = try await browse(body)
        var out: [RemoteCollection] = []
        var seen = Set<String>()
        collect(json, key: "musicTwoRowItemRenderer") { item in
            guard case .collection(let c)? = parseTwoRow(item), c.id.hasPrefix("MPREb"), seen.insert(c.id).inserted else { return }
            let parts = c.subtitle.components(separatedBy: " • ")
            let kind = parts.count > 1 ? parts[0] : "Álbum"
            out.append(RemoteCollection(id: c.id, title: c.title, subtitle: [kind, name, parts.last ?? ""].filter { !$0.isEmpty }.joined(separator: " • "), thumbnail: c.thumbnail))
        }
        return out
    }

    /// El artista con ese nombre exacto (sin tildes ni mayúsculas), para abrir su perfil desde un álbum o una canción.
    static func findArtist(_ name: String) async -> RemoteArtist? {
        let key = Discography.normalize(name)
        guard let artists = try? await searchAll(name).artists else { return nil }
        return artists.first { Discography.normalize($0.name) == key }
            ?? artists.first.flatMap { !key.isEmpty && Discography.normalize($0.name).hasPrefix(key) ? $0 : nil }
    }

    static func suggestions(_ query: String) async throws -> [String] {
        let json = try await post("https://music.youtube.com/youtubei/v1/music/get_search_suggestions?prettyPrint=false",
                                  body: ["context": webContext, "input": query],
                                  headers: ["Origin": "https://music.youtube.com"])
        var out: [String] = []
        collect(json, key: "searchSuggestionRenderer") { item in
            let runs = ((item["suggestion"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
            let t = runs.compactMap { $0["text"] as? String }.joined()
            if !t.isEmpty && !out.contains(t) { out.append(t) }
        }
        return Array(out.prefix(8))
    }

    /// Extrae canciones/vídeos de cualquier respuesta (búsqueda o lista).
    static func parseSongs(_ json: Any) -> [Song] { parseCandidates(json).map(\.song) }

    /// Resultado de búsqueda con el álbum y la duración, para elegir la versión correcta.
    struct Candidate {
        let song: Song
        let album: String
        let duration: Double?
    }

    static func parseCandidates(_ json: Any) -> [Candidate] {
        var out: [Candidate] = []
        var seen = Set<String>()
        collect(json, key: "musicResponsiveListItemRenderer") { item in
            var vid = (item["playlistItemData"] as? [String: Any])?["videoId"] as? String
            if vid == nil { collect(item, key: "watchEndpoint") { if vid == nil { vid = $0["videoId"] as? String } } }
            guard let videoId = vid, !seen.contains(videoId),
                  let cols = item["flexColumns"] as? [[String: Any]], !cols.isEmpty else { return }
            func runs(_ i: Int) -> [String] {
                guard cols.indices.contains(i) else { return [] }
                let r = (cols[i]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] as? [String: Any]
                return ((r?["runs"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }
            }
            let title = runs(0).first ?? "Sin título"
            // "Artista y Otro • Álbum • 3:08": el primer segmento son los artistas completos
            // (los conectores " y " / ", " vienen como runs sueltos).
            let kinds: Set<String> = ["Canción", "Vídeo", "Video", "Song", "Episodio", "Álbum", "Single", "EP"]
            let raw = runs(1).joined().components(separatedBy: " • ").map { $0.trimmingCharacters(in: .whitespaces) }
            let duration = raw.lazy.compactMap(Self.seconds).first
            let segments = raw.filter { !$0.isEmpty && !kinds.contains($0) && Self.seconds($0) == nil }
            let thumbs = (((item["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let url = (thumbs?.last?["url"] as? String).flatMap(URL.init)
            seen.insert(videoId)
            out.append(Candidate(song: Song(id: videoId, title: title, artist: segments.first ?? "", thumbnail: url),
                                 album: segments.count > 1 ? segments[1] : "", duration: duration))
        }
        return out
    }

    /// "3:08" / "1:02:03" → segundos.
    private static func seconds(_ text: String) -> Double? {
        guard text.range(of: #"^\d+:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil else { return nil }
        return text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    static func runsText(_ node: Any?) -> String {
        (((node as? [String: Any])?["runs"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined()
    }

    private static let origin = ["Origin": "https://music.youtube.com"]
    private static func browse(_ body: [String: Any]) async throws -> [String: Any] {
        await ensureVisitorData()
        var b = body
        b["context"] = webContext
        return try await post("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false", body: b, headers: origin)
    }

    // MARK: Inicio (recomendaciones de YouTube Music, sin sesión)
    static func home() async throws -> [HomeShelf] {
        let json = try await browse(["browseId": "FEmusic_home"])
        var shelves: [HomeShelf] = []
        collect(json, key: "musicCarouselShelfRenderer") { shelf in
            let header = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
            var items: [HomeItem] = parseSongs(shelf).map { .song($0) }
            collect(shelf, key: "musicTwoRowItemRenderer") { if let it = parseTwoRow($0) { items.append(it) } }
            if !items.isEmpty { shelves.append(HomeShelf(title: runsText(header?["title"]), items: items)) }
        }
        return shelves
    }

    private static func parseTwoRow(_ item: [String: Any]) -> HomeItem? {
        let title = runsText(item["title"]), subtitle = runsText(item["subtitle"])
        let thumbs = (((item["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let url = (thumbs?.last?["url"] as? String).flatMap(URL.init)
        let nav = item["navigationEndpoint"] as? [String: Any]
        if let vid = (nav?["watchEndpoint"] as? [String: Any])?["videoId"] as? String {
            return .song(Song(id: vid, title: title, artist: subtitle, thumbnail: url))
        }
        if let bid = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
           bid.hasPrefix("MPREb") || bid.hasPrefix("VL") {
            return .collection(RemoteCollection(id: bid, title: title, subtitle: subtitle, thumbnail: url))
        }
        return nil
    }

    /// Canciones de un álbum o playlist pública. Los álbumes no traen carátula por pista: se usa la del álbum.
    static func collectionSongs(_ c: RemoteCollection) async throws -> [Song] {
        let parts = c.subtitle.components(separatedBy: " • ")
        let fallbackArtist = parts.count > 1 ? parts[1] : c.subtitle
        var all: [Song] = []
        var seen = Set<String>()
        var json = try await browse(["browseId": c.id])
        for _ in 0..<10 {
            for s in parseSongs(json) where !seen.contains(s.id) {
                seen.insert(s.id)
                all.append(Song(id: s.id, title: s.title,
                                artist: s.artist.isEmpty ? fallbackArtist : s.artist,
                                thumbnail: s.thumbnail ?? c.thumbnail))
            }
            guard let token = continuationToken(json) else { break }
            json = try await browse(["continuation": token])
        }
        return all
    }

    /// "Radio" de una canción: ~50 canciones parecidas. Se usa para «Para ti».
    static func radio(for videoId: String) async throws -> [Song] {
        await ensureVisitorData()
        let json = try await post("https://music.youtube.com/youtubei/v1/next?prettyPrint=false",
                                  body: ["context": webContext, "videoId": videoId,
                                         "playlistId": "RDAMVM" + videoId, "isAudioOnly": true],
                                  headers: origin)
        var out: [Song] = []
        var seen: Set<String> = [videoId]
        collect(json, key: "playlistPanelVideoRenderer") { item in
            guard let vid = item["videoId"] as? String, !seen.contains(vid) else { return }
            seen.insert(vid)
            let thumbs = (item["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let artist = runsText(item["shortBylineText"]).components(separatedBy: " • ").first ?? ""
            out.append(Song(id: vid, title: runsText(item["title"]), artist: artist,
                            thumbnail: (thumbs?.last?["url"] as? String).flatMap(URL.init)))
        }
        return out
    }

    /// La canción de YouTube Music que corresponde a una pista de Apple Music. Puntúa título,
    /// etiquetas de versión (directo, remix, acústica…), artista, álbum y duración, para no
    /// coger otra versión ni una versión de karaoke. Sin ninguna que encaje devuelve nil.
    static func bestMatch(_ t: AMTrack) async -> Song? {
        guard let results = try? await searchCandidates("\(t.title) \(t.artist)") else { return nil }
        return Matcher.best(title: t.title, artist: t.artist, album: t.album, duration: t.duration, in: results, minScore: 20)
    }

    static func searchCandidates(_ query: String, filter: SearchFilter = .songs) async throws -> [Candidate] {
        var body: [String: Any] = ["context": webContext, "query": query]
        if let p = filter.params { body["params"] = p }
        let json = try await post("https://music.youtube.com/youtubei/v1/search?prettyPrint=false",
                                  body: body, headers: ["Origin": "https://music.youtube.com"])
        if let vd = (json["responseContext"] as? [String: Any])?["visitorData"] as? String { visitorData = vd }
        return parseCandidates(json)
    }

    /// Otras subidas de la misma canción (audio oficial, videoclip, «Topic»…) para cuando la
    /// original no se puede reproducir sin cuenta (contenido para niños, edad…).
    static func alternatives(for song: Song) async -> [Song] {
        let query = "\(song.title) \(song.artist)"
        async let songs = try? searchCandidates(query, filter: .songs)
        async let videos = try? searchCandidates(query, filter: .videos)
        let pool = ((await songs) ?? []) + ((await videos) ?? [])
        return Matcher.ranked(title: song.title, artist: song.artist, album: "", duration: 0, in: pool.filter { $0.song.id != song.id })
            .filter { $0.score >= 60 }
            .prefix(3)
            .map(\.song)
    }

    // MARK: Biblioteca del usuario (requiere sesión)
    static func userPlaylists() async throws -> [RemotePlaylist] {
        let json = try await authedPost("browse", ["context": webContext, "browseId": "FEmusic_liked_playlists"])
        var out: [RemotePlaylist] = []
        collect(json, key: "musicTwoRowItemRenderer") { item in
            guard let bid = ((item["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
                  bid.hasPrefix("VL") else { return }
            func text(_ key: String) -> String {
                let runs = (item[key] as? [String: Any])?["runs"] as? [[String: Any]]
                return (runs ?? []).compactMap { $0["text"] as? String }.joined()
            }
            let thumbs = (((item["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let url = (thumbs?.last?["url"] as? String).flatMap(URL.init)
            let id = String(bid.dropFirst(2))
            if !out.contains(where: { $0.id == id }) {
                out.append(RemotePlaylist(id: id, title: text("title"), subtitle: text("subtitle"), thumbnail: url))
            }
        }
        return out
    }

    /// Todas las canciones de una lista (sigue las páginas de continuación). "LM" = Canciones que te gustan.
    static func playlistSongs(_ playlistId: String) async throws -> [Song] {
        var all: [Song] = []
        var seen = Set<String>()
        var json = try await authedPost("browse", ["context": webContext, "browseId": "VL" + playlistId])
        for _ in 0..<15 {
            for s in parseSongs(json) where !seen.contains(s.id) { seen.insert(s.id); all.append(s) }
            guard let token = continuationToken(json) else { break }
            json = try await authedPost("browse", ["context": webContext, "continuation": token])
        }
        return all
    }

    private static func continuationToken(_ json: Any) -> String? {
        var tok: String?
        collect(json, key: "continuationCommand") { tok = $0["token"] as? String }
        if tok == nil { collect(json, key: "nextContinuationData") { tok = $0["continuation"] as? String } }
        return tok
    }

    // MARK: URL de audio: prueba varios clientes hasta que uno devuelva URL directa
    private struct Profile { let name: String; let client: [String: Any]; let ua: String }

    // Sólo VISIONOS da URLs sin «PO token» (yt-dlp, 2026-10). IOS responde sin URLs y las de
    // ANDROID_VR dan 403 a los pocos segundos desde 2026-08, así que se han quitado. Lo que
    // VISIONOS no sirve se busca en otra subida de la misma canción (`alternatives`).
    private static let profiles: [Profile] = [
        Profile(name: "VISIONOS",
                client: ["clientName": "VISIONOS", "clientVersion": "1.02",
                         "deviceMake": "Apple", "deviceModel": "RealityDevice17,1",
                         "osName": "visionOS", "osVersion": "26.5.23O471", "hl": "es"],
                ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15")
    ]

    /// Con `preferHLS` devuelve la lista HLS de sólo audio (formato nativo de AVPlayer);
    /// si no hay, o para descargas, la URL directa del .m4a.
    static func streamURL(videoId: String, best: Bool = false, preferHLS: Bool = false) async throws -> StreamInfo {
        await ensureVisitorData()
        let lowData = !best && UserDefaults.standard.string(forKey: "quality") == "low"
        var problems: [String] = []
        for p in profiles {
            do {
                var client = p.client
                var headers = ["User-Agent": p.ua]
                if let vd = visitorData { client["visitorData"] = vd; headers["X-Goog-Visitor-Id"] = vd }
                let body: [String: Any] = ["context": ["client": client], "videoId": videoId,
                                           "contentCheckOk": true, "racyCheckOk": true]
                let json = try await post("https://www.youtube.com/youtubei/v1/player?prettyPrint=false",
                                          body: body, headers: headers)
                let streaming = json["streamingData"] as? [String: Any]
                if preferHLS, let master = streaming?["hlsManifestUrl"] as? String,
                   let audio = try? await hlsAudioPlaylist(master, userAgent: p.ua, low: lowData) {
                    return StreamInfo(url: audio, userAgent: p.ua, isHLS: true)
                }
                let formats = (streaming?["adaptiveFormats"] as? [[String: Any]]) ?? []
                let candidates = formats
                    .filter { ($0["mimeType"] as? String)?.hasPrefix("audio/mp4") == true && $0["url"] != nil }
                let byRate: ([String: Any], [String: Any]) -> Bool = { ($0["bitrate"] as? Int ?? 0) < ($1["bitrate"] as? Int ?? 0) }
                let audio = lowData ? candidates.min(by: byRate) : candidates.max(by: byRate)
                if let str = audio?["url"] as? String, let url = URL(string: str) {
                    return StreamInfo(url: url, userAgent: p.ua)
                }
                let ps = json["playabilityStatus"] as? [String: Any]
                let status = ps?["status"] as? String ?? "sin_estado"
                let reason = ps?["reason"] as? String ?? ""
                problems.append(reason.isEmpty ? "\(p.name): \(status)" : reason)
            } catch {
                problems.append("\(p.name): error de red/JSON")
            }
        }
        throw YTError.detail(problems.joined(separator: " | "))
    }

    /// Como `streamURL`, pero si YouTube no deja reproducir esa subida prueba otras de la misma
    /// canción. Devuelve también el videoId que ha sonado de verdad.
    static func playableStream(for song: Song, best: Bool = false, preferHLS: Bool = false) async throws -> (StreamInfo, String) {
        if let alt = alternateID[song.id], let info = try? await streamURL(videoId: alt, best: best, preferHLS: preferHLS) {
            return (info, alt)
        }
        do {
            return (try await streamURL(videoId: song.id, best: best, preferHLS: preferHLS), song.id)
        } catch {
            for other in await alternatives(for: song) {
                if let info = try? await streamURL(videoId: other.id, best: best, preferHLS: preferHLS) {
                    alternateID[song.id] = other.id
                    return (info, other.id)
                }
            }
            // VISIONOS no sirve el contenido «para niños» y ningún cliente sin cuenta lo da (2026-10).
            if let yt = error as? YTError, case .detail(let d) = yt, d.contains("no está disponible") {
                throw YTError.detail("YouTube no deja escuchar esta canción sin cuenta (suele pasar con el contenido para niños) y no hay otra versión.")
            }
            throw error
        }
    }

    /// videoId que no se puede reproducir → otra subida que sí (mientras la app está abierta).
    private static let alternateLock = NSLock()
    private static var alternateStore: [String: String] = [:]
    private static var alternateID: [String: String] {
        get { alternateLock.lock(); defer { alternateLock.unlock() }; return alternateStore }
        set { alternateLock.lock(); alternateStore = newValue; alternateLock.unlock() }
    }

    // MARK: Descarga
    /// Descarga la canción completa y devuelve un archivo temporal (.aac o .m4a).
    /// Se baja por segmentos HLS (≈3 s por canción, 4 a la vez): pedir el .m4a entero
    /// de una sola vez hace que YouTube corte la conexión a los ~100 s.
    static func downloadAudio(song: Song, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let videoId = song.id
        let (info, _) = try await playableStream(for: song, best: true, preferHLS: true)
        let ua = info.userAgent
        if info.isHLS {
            let listData = try await fetch(info.url, ua: ua)
            let list = String(decoding: listData, as: UTF8.self)
            let segments = list.split(whereSeparator: \.isNewline).map(String.init)
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }.compactMap(URL.init)
            guard !segments.isEmpty else { throw YTError.noStream }
            var parts = [Data?](repeating: nil, count: segments.count)
            var done = 0
            try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                var next = 0
                while next < min(4, segments.count) {
                    let i = next, u = segments[i]
                    next += 1
                    group.addTask { (i, try await fetch(u, ua: ua)) }
                }
                while let (i, data) = try await group.next() {
                    parts[i] = data
                    done += 1
                    await progress(Double(done) / Double(segments.count))
                    if next < segments.count {
                        let j = next, u = segments[j]
                        next += 1
                        group.addTask { (j, try await fetch(u, ua: ua)) }
                    }
                }
            }
            var audio = Data()
            for part in parts { if let part { audio.append(stripID3(part)) } }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(videoId).aac")
            try audio.write(to: file, options: .atomic)
            return file
        }
        // Sin HLS: el .m4a directo en trozos de 1 MB.
        var audio = Data()
        var total = Int.max
        while audio.count < total {
            let end = audio.count + 1_048_575
            var req = URLRequest(url: info.url)
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            req.setValue("bytes=\(audio.count)-\(end)", forHTTPHeaderField: "Range")
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                throw YTError.badResponse
            }
            if http.statusCode == 200 { audio = data; break }
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let size = range.split(separator: "/").last.flatMap({ Int($0) }) { total = size }
            audio.append(data)
            if total != Int.max { await progress(Double(audio.count) / Double(total)) }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(videoId).m4a")
        try audio.write(to: file, options: .atomic)
        return file
    }

    private static func fetch(_ url: URL, ua: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { throw YTError.badResponse }
        return data
    }

    /// Cada segmento HLS empieza con una etiqueta ID3; se quita para dejar AAC (ADTS) limpio.
    private static func stripID3(_ data: Data) -> Data {
        let b = [UInt8](data.prefix(10))
        guard b.count == 10, b[0] == 0x49, b[1] == 0x44, b[2] == 0x33 else { return data }
        let size = (Int(b[6]) << 21) | (Int(b[7]) << 14) | (Int(b[8]) << 7) | Int(b[9])
        guard data.count > 10 + size else { return data }
        return data.subdata(in: (data.startIndex + 10 + size)..<data.endIndex)
    }

    /// Del manifiesto HLS maestro (que trae también vídeo) elige la pista de sólo audio:
    /// itag 234 ≈ AAC 128 kbps, 233 ≈ AAC 48 kbps.
    private static func hlsAudioPlaylist(_ master: String, userAgent: String, low: Bool) async throws -> URL? {
        guard let url = URL(string: master) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        let text = String(decoding: data, as: UTF8.self)
        let re = try NSRegularExpression(pattern: #"#EXT-X-MEDIA:URI="([^"]+)",TYPE=AUDIO,GROUP-ID="(\d+)""#)
        let tracks: [(itag: Int, url: String)] = re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let u = Range(m.range(at: 1), in: text), let g = Range(m.range(at: 2), in: text),
                  let itag = Int(text[g]) else { return nil }
            return (itag, String(text[u]))
        }
        let pick = low ? tracks.min { $0.itag < $1.itag } : tracks.max { $0.itag < $1.itag }
        return pick.flatMap { URL(string: $0.url) }
    }

    // Recorre el JSON recursivamente buscando un nombre de clave
    static func collect(_ node: Any, key: String, _ found: ([String: Any]) -> Void) {
        if let d = node as? [String: Any] {
            for (k, v) in d {
                if k == key, let item = v as? [String: Any] { found(item) } else { collect(v, key: key, found) }
            }
        } else if let a = node as? [Any] {
            a.forEach { collect($0, key: key, found) }
        }
    }
}
