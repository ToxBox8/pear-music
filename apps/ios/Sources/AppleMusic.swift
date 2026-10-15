import Foundation
import MediaPlayer

// Importación de playlists de Apple Music por dos vías:
//  1. Enlace compartido (music.apple.com/…/playlist/…): la página pública incluye
//     todas las pistas en un JSON ("serialized-server-data"). No hace falta cuenta.
//  2. La biblioteca de la app Música del iPhone (MediaPlayer), con permiso del usuario.
// Después cada pista se busca en YouTube Music para crear la playlist local.

/// Una canción de fuera (Apple Music, Spotify, CSV). Mismos campos que `AMTrack` en Android.
struct AMTrack: Hashable, Codable {
    let title: String
    let artist: String
    /// Álbum y duración (s): deciden entre versiones (directo, remix, remaster…).
    var album: String = ""
    var duration: Double = 0
    /// Si lo hay, el criterio principal: suele llevar directo a la grabación exacta.
    var isrc: String? = nil
    /// Distingue la versión explícita de la limpia.
    var explicit: Bool? = nil
}

struct AMPlaylist: Identifiable {
    let id: String
    let name: String
    let tracks: [AMTrack]
    let artwork: URL?
}

enum AppleMusicImporter {
    enum Failure: LocalizedError {
        case badLink, noTracks, denied
        var errorDescription: String? {
            switch self {
            case .badLink: return L("Pega un enlace de music.apple.com (Compartir → Copiar enlace).")
            case .noTracks: return L("No se encontraron canciones. ¿La playlist es pública?")
            case .denied: return L("Sin permiso para leer la app Música. Actívalo en Ajustes → Pear Music.")
            }
        }
    }

    private static let safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    // MARK: Enlace público
    static func fetchPublic(_ link: String) async throws -> AMPlaylist {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        // El texto compartido puede traer más palabras alrededor del enlace.
        let urlString = trimmed.components(separatedBy: .whitespacesAndNewlines).first { $0.contains("music.apple.com") } ?? trimmed
        guard let url = URL(string: urlString), url.host?.hasSuffix("music.apple.com") == true else { throw Failure.badLink }

        var req = URLRequest(url: url)
        req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        let html = String(decoding: data, as: UTF8.self)

        var tracks: [AMTrack] = []
        if let json = script(in: html, attribute: #"id="serialized-server-data""#),
           let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) {
            visit(root) { d in
                guard (d["contentDescriptor"] as? [String: Any])?["kind"] as? String == "song",
                      let title = d["title"] as? String, let artist = d["artistName"] as? String else { return }
                let album = ((d["tertiaryLinks"] as? [[String: Any]])?.first?["title"] as? String) ?? ""
                let ms = (d["duration"] as? Double) ?? Double((d["duration"] as? Int) ?? 0)
                tracks.append(AMTrack(title: title, artist: artist, album: album, duration: ms / 1000))
            }
        }

        var name = L("Playlist de Apple Music")
        if let ld = script(in: html, attribute: #"type="application/ld+json""#),
           let obj = try? JSONSerialization.jsonObject(with: Data(ld.utf8)) as? [String: Any] {
            if let n = obj["name"] as? String { name = n }
            // Respaldo si cambia el formato: JSON-LD trae títulos (sin artista).
            if tracks.isEmpty, let list = obj["track"] as? [[String: Any]] {
                tracks = list.compactMap { ($0["name"] as? String).map { AMTrack(title: $0, artist: "") } }
            }
        }
        guard !tracks.isEmpty else { throw Failure.noTracks }

        // og:image es apaisada (1200x630); se pide la versión cuadrada para la portada.
        let artwork = meta(in: html, property: "og:image")
            .map { $0.replacingOccurrences(of: #"/\d+x\d+[^/?]*\.jpg(\?.*)?$"#, with: "/600x600bb.jpg", options: .regularExpression) }
            .flatMap(URL.init)
        return AMPlaylist(id: url.absoluteString, name: name, tracks: tracks, artwork: artwork)
    }

    private static func script(in html: String, attribute: String) -> String? {
        let pattern = "<script[^>]*" + NSRegularExpression.escapedPattern(for: attribute) + "[^>]*>(.*?)</script>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    private static func meta(in html: String, property: String) -> String? {
        let pattern = #"<meta[^>]*property=""# + NSRegularExpression.escapedPattern(for: property) + #""[^>]*content="([^"]+)""#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r]).replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func visit(_ node: Any, _ found: ([String: Any]) -> Void) {
        if let d = node as? [String: Any] {
            found(d)
            d.values.forEach { visit($0, found) }
        } else if let a = node as? [Any] {
            a.forEach { visit($0, found) }
        }
    }

    // MARK: Biblioteca de la app Música
    static func requestLibraryAccess() async -> Bool {
        if MPMediaLibrary.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { c in
            MPMediaLibrary.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    static func libraryPlaylists() -> [AMPlaylist] {
        let lists = (MPMediaQuery.playlists().collections as? [MPMediaPlaylist]) ?? []
        return lists.compactMap { pl in
            let tracks = pl.items.compactMap { item -> AMTrack? in
                guard let t = item.title else { return nil }
                return AMTrack(title: t, artist: item.artist ?? "", album: item.albumTitle ?? "", duration: item.playbackDuration)
            }
            guard !tracks.isEmpty else { return nil }
            return AMPlaylist(id: String(pl.persistentID), name: pl.name ?? "Playlist", tracks: tracks, artwork: nil)
        }
    }

    // MARK: Emparejar con YouTube Music (4 búsquedas en paralelo, conserva el orden)
    static func match(_ tracks: [AMTrack], progress: @escaping @MainActor (Int) -> Void) async -> [Song] {
        var results = [Song?](repeating: nil, count: tracks.count)
        var done = 0
        await withTaskGroup(of: (Int, Song?).self) { group in
            var next = 0
            while next < min(4, tracks.count) {
                let i = next, t = tracks[i]
                next += 1
                group.addTask { (i, await YTClient.bestMatch(t)) }
            }
            while let (i, song) = await group.next() {
                results[i] = song
                done += 1
                await progress(done)
                if next < tracks.count {
                    let j = next, t = tracks[j]
                    next += 1
                    group.addTask { (j, await YTClient.bestMatch(t)) }
                }
            }
        }
        var seen = Set<String>()
        return results.compactMap { $0 }.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Emparejar versiones
/// Puntúa resultados de YouTube Music contra una canción conocida (título, artista, álbum y
/// duración). Antes se quitaba todo lo que iba entre paréntesis, así que «Canción (Live)» y
/// «Canción» eran iguales y se colaba otra versión; ahora las etiquetas de versión cuentan.
/// Mismas reglas que `Matcher` en Android (AppleMusic.kt).
enum Matcher {
    struct Scored { let song: Song; let score: Int }

    /// Etiquetas de versión y las palabras que las delatan.
    private static let tags: [(String, [String])] = [
        ("live", ["live", "en vivo", "en directo", "directo", "ao vivo", "concert"]),
        ("remix", ["remix", "rmx", "mix"]),
        ("acoustic", ["acoustic", "acustic", "acustico", "acustica", "unplugged", "stripped"]),
        ("instrumental", ["instrumental", "karaoke", "backing track"]),
        ("cover", ["cover", "originally performed", "in the style of", "tribute", "made famous"]),
        ("sped", ["sped up", "speed up", "nightcore"]),
        ("slowed", ["slowed", "reverb"]),
        ("remaster", ["remaster", "remastered", "remasterizado"]),
        ("demo", ["demo"]),
        ("edit", ["radio edit", "edit"]),
        ("clean", ["clean", "clean version", "censored", "radio version"]),
        ("extended", ["extended"]),
        ("version", ["version"]),
        ("orchestral", ["orchestral", "symphonic", "piano version"]),
    ]
    /// Diferencias de poca importancia (mismo audio o casi).
    private static let minor: Set<String> = ["remaster", "version", "edit"]

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    static func versionTags(_ s: String) -> Set<String> {
        let t = fold(s)
        return Set(tags.filter { _, words in
            words.contains { t.range(of: "\\b" + NSRegularExpression.escapedPattern(for: $0) + "\\b", options: .regularExpression) != nil }
        }.map(\.0))
    }

    /// Título sin paréntesis, sin « - …» y sin «feat.»: la canción en sí.
    static func base(_ s: String) -> String {
        var t = fold(s)
        for p in [#"\s*[\(\[].*?[\)\]]"#, #"\s+-\s+.*$"#, #"\s+(feat\.?|ft\.?|con|with)\s+.*$"#, #"[^\p{L}\p{N}\s]"#] {
            t = t.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func artists(_ s: String) -> [String] {
        fold(s).replacingOccurrences(of: #",|&| y | and | x | feat\.? | ft\.? "#, with: "|", options: .regularExpression)
            .split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Segundos de diferencia que se aceptan como «la misma grabación» (Ajustes › Avanzado, `matchTolerance`).
    static var tolerance: Double {
        let v = UserDefaults.standard.integer(forKey: "matchTolerance")
        return Double(v > 0 ? v : 4)
    }

    static func score(title: String, artist: String, album: String, duration: Double, _ c: YTClient.Candidate, explicit: Bool? = nil) -> Int {
        var score = 0
        let bt = base(title), bc = base(c.song.title)
        if bt == bc { score += 50 }
        else if !bt.isEmpty && !bc.isEmpty && (bc.contains(bt) || bt.contains(bc)) { score += 15 }
        else { score -= 60 }

        var want = versionTags(title)
        if versionTags(album).contains("live") { want.insert("live") }
        let got = versionTags(c.song.title)
        // Explícita en el origen: una versión «clean» no vale; limpia en el origen: se prefiere la «clean».
        if explicit == false && got.contains("clean") { want.insert("clean") }
        for t in got.subtracting(want) { score -= minor.contains(t) ? 10 : 45 }
        for t in want.subtracting(got) { score -= minor.contains(t) ? 5 : 25 }

        let wanted = artists(artist), have = fold(c.song.artist)
        if let first = wanted.first {
            if have.contains(first) { score += 40 }
            else if wanted.contains(where: { have.contains($0) }) { score += 25 }
            else { score -= 40 }
        }
        if !album.isEmpty, !c.album.isEmpty, base(album) == base(c.album) { score += 20 }
        if duration > 0, let d = c.duration {
            let diff = abs(duration - d)
            let tol = tolerance
            score += diff <= min(2, tol) ? 25 : diff <= tol ? 18 : diff <= tol * 2.5 ? 0 : -30
        }
        return score
    }

    /// De mejor a peor (a igualdad, el orden de YouTube).
    static func ranked(title: String, artist: String, album: String, duration: Double, in candidates: [YTClient.Candidate], explicit: Bool? = nil) -> [Scored] {
        candidates.prefix(10).enumerated()
            .map { (i, c) in (i, Scored(song: c.song, score: score(title: title, artist: artist, album: album, duration: duration, c, explicit: explicit))) }
            .sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
            .map(\.1)
    }

    /// Confianza de una coincidencia: buena, para revisar a mano o no encontrada.
    enum Confidence: String, Codable { case good = "Good", review = "Review", none = "None" }

    static let good = 90
    static let minimum = 20

    /// Buena con ≥ 90 puntos y sin empate; para revisar entre 20 y 90, o si la segunda está a menos de 8
    /// puntos y es otra canción (otro título o artista); no encontrada por debajo de 20. Igual que Android.
    static func confidence(_ ranked: [Scored]) -> Confidence {
        guard let top = ranked.first, top.score >= minimum else { return .none }
        var tie = false
        if ranked.count > 1 {
            let second = ranked[1]
            tie = top.score - second.score < 8
                && (base(second.song.title) != base(top.song.title) || fold(second.song.artist) != fold(top.song.artist))
        }
        return top.score >= good && !tie ? .good : .review
    }

    static func best(title: String, artist: String, album: String, duration: Double, in candidates: [YTClient.Candidate], minScore: Int) -> Song? {
        guard let top = ranked(title: title, artist: artist, album: album, duration: duration, in: candidates).first,
              top.score >= minScore else { return nil }
        return top.song
    }
}
