import Foundation
import Compression
import SQLite3

// Importar playlists de fuera (Fase 2D): Spotify (enlace público o CSV de Exportify) y SimpMusic (su copia
// .backup). Spotify sólo da metadatos: cada canción se busca en YouTube Music y se empareja (Matcher). Nunca
// se descarga nada al importar. Mismas reglas que `ExternalImport.kt` en Android.

struct ImportFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Spotify por enlace
enum SpotifyImporter {
    private static let userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

    /// El id de un enlace `open.spotify.com/playlist/<id>` (también con /intl-es/ o `spotify:playlist:<id>`).
    static func playlistID(_ link: String) -> String? {
        guard let r = link.range(of: #"playlist[/:][A-Za-z0-9]{22}"#, options: .regularExpression) else { return nil }
        return String(link[r].suffix(22))
    }

    static func isSpotify(_ link: String) -> Bool {
        link.contains("spotify.com") || link.trimmingCharacters(in: .whitespaces).hasPrefix("spotify:")
    }

    /// La página de inserción (`/embed/playlist/<id>`) trae el nombre, la portada y, de cada canción, título,
    /// artistas, duración y si es explícita. Sin cuenta ni claves. Llega hasta ~100 canciones; para listas más
    /// largas, el CSV de Exportify.
    static func fetchPublic(_ link: String) async throws -> AMPlaylist {
        guard let id = playlistID(link), let url = URL(string: "https://open.spotify.com/embed/playlist/\(id)") else {
            throw ImportFailure("Pega el enlace de una playlist de Spotify (Compartir → Copiar enlace).")
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ImportFailure("Spotify no deja ver esa playlist. ¿Es pública?") }
        return try parseEmbed(String(decoding: data, as: UTF8.self))
    }

    static func parseEmbed(_ html: String) throws -> AMPlaylist {
        let unreadable = ImportFailure("No se pudo leer la playlist. Prueba con el CSV de Exportify.")
        guard let r = html.range(of: #"<script id="__NEXT_DATA__"[^>]*>"#, options: .regularExpression),
              let end = html.range(of: "</script>", range: r.upperBound..<html.endIndex),
              let root = try? JSONSerialization.jsonObject(with: Data(html[r.upperBound..<end.lowerBound].utf8)) as? [String: Any],
              let entity = (((root["props"] as? [String: Any])?["pageProps"] as? [String: Any])?["state"] as? [String: Any])
                .flatMap({ ($0["data"] as? [String: Any])?["entity"] as? [String: Any] })
        else { throw unreadable }
        let list = entity["trackList"] as? [[String: Any]] ?? []
        let tracks = list.compactMap { t -> AMTrack? in
            guard let title = t["title"] as? String, !title.isEmpty else { return nil }
            return AMTrack(title: title,
                           artist: ((t["subtitle"] as? String) ?? "").replacingOccurrences(of: "\u{00a0}", with: " "),
                           duration: ((t["duration"] as? Double) ?? 0) / 1000,
                           explicit: t["isExplicit"] as? Bool)
        }
        guard !tracks.isEmpty else { throw ImportFailure("La playlist está vacía o no es pública.") }
        let cover = ((entity["coverArt"] as? [String: Any])?["sources"] as? [[String: Any]])?.first?["url"] as? String
        let name = (entity["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Playlist de Spotify"
        return AMPlaylist(id: UUID().uuidString, name: name, tracks: tracks, artwork: cover.flatMap(URL.init(string:)))
    }
}

// MARK: - CSV de Exportify
enum ExportifyCSV {
    /// Las cabeceras de Exportify cambian con el idioma; el orden no. Posiciones desde «Track URI».
    private static let name = 1, artists = 3, album = 5, duration = 12, explicitCol = 14, isrcCol = 16

    static func parse(fileName: String, text: String) throws -> AMPlaylist {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        let rows = Self.rows(body)
        guard rows.count >= 2 else { throw ImportFailure("El archivo no tiene canciones.") }
        guard let start = rows[1].firstIndex(where: { $0.hasPrefix("spotify:track:") || $0.hasPrefix("spotify:local:") }) else {
            throw ImportFailure("No parece un CSV de Exportify (falta la columna «Track URI»).")
        }
        let isrcIndex = rows[0].firstIndex { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("ISRC") == .orderedSame } ?? start + isrcCol
        let tracks = rows.dropFirst().compactMap { r -> AMTrack? in
            func col(_ i: Int) -> String { i < r.count ? r[i].trimmingCharacters(in: .whitespaces) : "" }
            let title = col(start + name)
            guard !title.isEmpty else { return nil }
            let explicitText = col(start + explicitCol).lowercased()
            let isrc = col(isrcIndex)
            return AMTrack(title: title,
                           artist: col(start + artists).replacingOccurrences(of: "\\,", with: ","),
                           album: col(start + album),
                           duration: (Double(col(start + duration)) ?? 0) / 1000,
                           isrc: isrc.isEmpty ? nil : isrc,
                           explicit: explicitText == "true" ? true : explicitText == "false" ? false : nil)
        }
        guard !tracks.isEmpty else { throw ImportFailure("El archivo no tiene canciones.") }
        var title = (fileName as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
        if title.trimmingCharacters(in: .whitespaces).isEmpty { title = "Playlist de Spotify" }
        return AMPlaylist(id: UUID().uuidString, name: title, tracks: tracks, artwork: nil)
    }

    /// CSV con comillas dobles (RFC 4180): comas y saltos de línea dentro de comillas, "" = comilla.
    static func rows(_ text: String) -> [[String]] {
        var out: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if quoted && ch == "\"" && i + 1 < chars.count && chars[i + 1] == "\"" { cell.append("\""); i += 1 }
            else if ch == "\"" { quoted.toggle() }
            else if !quoted && ch == "," { row.append(cell); cell = "" }
            else if !quoted && (ch == "\n" || ch == "\r" || ch == "\r\n") {
                if ch == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(cell); cell = ""
                if row.contains(where: { !$0.isEmpty }) { out.append(row) }
                row = []
            } else { cell.append(ch) }
            i += 1
        }
        row.append(cell)
        if row.contains(where: { !$0.isEmpty }) { out.append(row) }
        return out
    }
}

// MARK: - Copia de SimpMusic
/// Una playlist de SimpMusic: sus canciones ya son de YouTube Music (por videoId), sin emparejar.
struct SimpPlaylist: Identifiable {
    let id = UUID()
    let name: String
    let songs: [Song]
    let cover: URL?
}

enum SimpMusicBackup {
    /// Nombre de la base de datos dentro del ZIP (`DB_NAME` en SimpMusic).
    static let database = "Music Database"

    /// Lee el `.backup` (ZIP con la base SQLite de SimpMusic, esquema 27): sus playlists en orden
    /// (`local_playlist` + `pair_song_local_playlist`) y, si las hay, «Canciones que te gustan» (`song.liked`).
    static func read(_ url: URL) throws -> [SimpPlaylist] {
        let zip = try Data(contentsOf: url, options: .alwaysMapped)
        guard let db = try ZipReader.entry(named: database, in: zip) else {
            throw ImportFailure("No es una copia de SimpMusic (en SimpMusic: Ajustes › Copia de seguridad).")
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("simpmusic-\(UUID().uuidString).db")
        try db.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try readDatabase(tmp)
    }

    static func readDatabase(_ url: URL) throws -> [SimpPlaylist] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            throw ImportFailure("La copia de SimpMusic está dañada.")
        }
        defer { sqlite3_close(db) }
        var out: [SimpPlaylist] = []
        for row in query(db, "SELECT id, title, thumbnail FROM local_playlist ORDER BY id") {
            let songs = self.songs(db, "SELECT s.videoId, s.title, s.artistName, s.thumbnails FROM pair_song_local_playlist p "
                + "JOIN song s ON s.videoId = p.songId WHERE p.playlistId = \(Int(row[0] ?? "0") ?? 0) AND p.inPlaylist = 1 ORDER BY p.position")
            out.append(SimpPlaylist(name: row[1] ?? "Playlist", songs: songs, cover: row[2].flatMap(URL.init(string:))))
        }
        let liked = songs(db, "SELECT videoId, title, artistName, thumbnails FROM song WHERE liked = 1 ORDER BY favoriteAt DESC")
        if !liked.isEmpty { out.insert(SimpPlaylist(name: "Canciones que te gustan (SimpMusic)", songs: liked, cover: nil), at: 0) }
        return out
    }

    private static func songs(_ db: OpaquePointer, _ sql: String) -> [Song] {
        query(db, sql).compactMap { r in
            guard let id = r[0] else { return nil }
            let thumb = r[3].flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil }
            return Song(id: id, title: r[1] ?? "", artist: r[2] ?? "", thumbnail: thumb)
        }
    }

    private static func query(_ db: OpaquePointer, _ sql: String) -> [[String?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [[String?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(stmt)).map { i in
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            })
        }
        return rows
    }
}

/// Lector mínimo de ZIP (sin cifrar, sin ZIP64): busca un archivo por su nombre en el directorio central y
/// lo descomprime (guardado o DEFLATE). iOS no trae ninguna API para descomprimir ZIP.
enum ZipReader {
    static func entry(named name: String, in zip: Data) throws -> Data? {
        func u16(_ o: Int) -> Int { Int(zip[zip.startIndex + o]) | Int(zip[zip.startIndex + o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let count = zip.count
        // Fin del directorio central: firma 0x06054b50 en los últimos 64 KB.
        var eocd = -1
        var o = count - 22
        while o >= max(0, count - 65_557) {
            if u32(o) == 0x06054b50 { eocd = o; break }
            o -= 1
        }
        guard eocd >= 0 else { throw ImportFailure("El archivo no es un ZIP válido.") }
        let entries = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<entries {
            guard p + 46 <= count, u32(p) == 0x02014b50 else { break }
            let method = u16(p + 10)
            let compressed = u32(p + 20), size = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let local = u32(p + 42)
            let entryName = String(decoding: zip[(zip.startIndex + p + 46)..<(zip.startIndex + p + 46 + nameLen)], as: UTF8.self)
            if (entryName as NSString).lastPathComponent == name {
                if compressed == 0xFFFFFFFF || size == 0xFFFFFFFF || local == 0xFFFFFFFF {
                    throw ImportFailure("La copia es demasiado grande. En SimpMusic, haz la copia sin las descargas.")
                }
                let start = local + 30 + u16(local + 26) + u16(local + 28)
                guard start + compressed <= count else { throw ImportFailure("El archivo está cortado.") }
                let raw = zip[(zip.startIndex + start)..<(zip.startIndex + start + compressed)]
                if method == 0 { return Data(raw) }
                guard method == 8 else { throw ImportFailure("Compresión no admitida.") }
                return inflate(Data(raw), size: size)
            }
            p += 46 + nameLen + extraLen + commentLen
        }
        return nil
    }

    /// DEFLATE puro (lo que guarda un ZIP) con el framework Compression.
    private static func inflate(_ data: Data, size: Int) -> Data? {
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? out : nil
    }
}

// MARK: - Emparejado de una lista entera
/// El resultado de una canción: la elegida (si hay), su confianza y los candidatos para elegir a mano.
struct TrackMatch: Codable {
    let track: AMTrack
    let choice: Song?
    let confidence: Matcher.Confidence
    let candidates: [ScoredSong]

    struct ScoredSong: Codable {
        let song: Song
        let score: Int
    }
}

enum ImportMatcher {
    /// Busca cada canción en YouTube Music, 3 a la vez y con una pausa corta entre búsquedas para no
    /// saturar a YouTube; reintenta 2 veces si falla la red. Con ISRC lo busca primero por el ISRC. Guarda
    /// el avance en `job` para poder seguir si se corta.
    @MainActor static func matchAll(_ job: ImportJob, progress: @escaping @MainActor (Int) -> Void) async {
        let tracks = job.playlist.tracks
        var next = 0
        await withTaskGroup(of: (Int, TrackMatch).self) { group in
            func launch() {
                while next < tracks.count, job.results[next] != nil { next += 1 }
                guard next < tracks.count else { return }
                let i = next, t = tracks[i]
                next += 1
                group.addTask {
                    let m = await matchOne(t)
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    return (i, m)
                }
            }
            for _ in 0..<3 { launch() }
            while let (i, m) = await group.next() {
                await MainActor.run {
                    job.record(i, m)
                    progress(job.results.count)
                }
                launch()
            }
        }
    }

    static func matchOne(_ t: AMTrack) async -> TrackMatch {
        var pool: [YTClient.Candidate] = []
        var seen = Set<String>()
        func add(_ list: [YTClient.Candidate]) { for c in list where seen.insert(c.song.id).inserted { pool.append(c) } }
        // El ISRC suele llevar directo a la grabación exacta.
        if let isrc = t.isrc { add(await search(isrc)) }
        add(await search("\(t.title) \(t.artist.split(separator: ",").first.map(String.init) ?? t.artist)"))
        let ranked = Matcher.ranked(title: t.title, artist: t.artist, album: t.album, duration: t.duration, in: pool, explicit: t.explicit)
        let confidence = Matcher.confidence(ranked)
        return TrackMatch(track: t, choice: confidence == .good ? ranked.first?.song : nil, confidence: confidence,
                          candidates: ranked.prefix(5).map { .init(song: $0.song, score: $0.score) })
    }

    private static func search(_ q: String) async -> [YTClient.Candidate] {
        for attempt in 0..<3 {
            if let r = try? await YTClient.searchCandidates(q) { return r }
            try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
        }
        return []
    }
}

/// Una importación en curso guardada en `Documents/import_job.json`, para seguir donde se quedó si se cierra
/// la app o se corta la red. Se usa siempre desde el hilo principal (la vista y `ImportMatcher.matchAll`).
final class ImportJob: ObservableObject {
    struct Saved: Codable {
        let name: String
        let artwork: URL?
        let tracks: [AMTrack]
        var results: [String: TrackMatch]
    }

    let playlist: AMPlaylist
    @Published private(set) var results: [Int: TrackMatch] = [:]

    private static var file: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("import_job.json")
    }

    init(playlist: AMPlaylist, results: [Int: TrackMatch] = [:]) {
        self.playlist = playlist
        self.results = results
    }

    func record(_ i: Int, _ m: TrackMatch) {
        results[i] = m
        let saved = Saved(name: playlist.name, artwork: playlist.artwork, tracks: playlist.tracks,
                          results: Dictionary(uniqueKeysWithValues: results.map { (String($0.key), $0.value) }))
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: Self.file, options: .atomic) }
    }

    func discard() { try? FileManager.default.removeItem(at: Self.file) }

    /// La importación a medias, si la hay.
    static func pending() -> ImportJob? {
        guard let data = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        let results = Dictionary(uniqueKeysWithValues: s.results.compactMap { k, v in Int(k).map { ($0, v) } })
        return ImportJob(playlist: AMPlaylist(id: UUID().uuidString, name: s.name, tracks: s.tracks, artwork: s.artwork), results: results)
    }
}
