import Foundation
import SwiftUI

/// Letra de una canción: sincronizada (líneas con su tiempo) o sólo texto. Mismo modelo que `Lyrics` en Android.
struct Lyrics: Codable, Equatable {
    struct Line: Codable, Equatable { let time: Double; let text: String }
    let lines: [Line]
    let plain: String?
    var instrumental = false

    var synced: Bool { !lines.isEmpty }

    /// Índice de la línea que suena en `position` (segundos), o -1 antes de la primera.
    func index(at position: Double) -> Int {
        var lo = 0, hi = lines.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= position { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }

    private static let tag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)

    /// Lee el formato LRC: «[mm:ss.xx] texto», con varias marcas por línea; se ignoran las cabeceras ([ar:], [ti:]…).
    static func parseLRC(_ lrc: String) -> [Line] {
        var out: [Line] = []
        for raw in lrc.components(separatedBy: "\n") {
            let ns = raw as NSString
            let tags = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let first = tags.first, first.range.location == 0, let last = tags.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for m in tags {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                out.append(Line(time: mm * 60 + ss + frac, text: text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Título sin «(Official Video)», «[Lyrics]», «- Remastered»… para buscar la letra.
    static func cleanTitle(_ title: String) -> String {
        var t = title.replacingOccurrences(
            of: #"\s*[(\[][^)\]]*\b(official|video|audio|lyrics?|letra|visuali[sz]er|hd|4k|mv|clip)\b[^)\]]*[)\]]"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+-\s+.*\bremaster(ed)?\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Primer artista de «A, B & C» o «A feat. B».
    static func mainArtist(_ artist: String) -> String {
        let r = artist.range(of: #"\s*(,|&| feat\.? | ft\.? | x | y )\s*"#, options: [.regularExpression, .caseInsensitive])
        return String(r.map { artist[..<$0.lowerBound] } ?? Substring(artist)).trimmingCharacters(in: .whitespaces)
    }
}

/// Letras de LRCLIB (lrclib.net: gratis, sin cuenta ni clave). Mismas reglas que `LyricsClient` en Android: búsqueda
/// por título y artista, la de duración más parecida (±10 s), mejor sincronizada, y caché en disco (también «no hay
/// letra», 7 días) para tener letra sin conexión en lo descargado.
enum LyricsClient {
    private static let base = "https://lrclib.net/api"
    private static let noneTTL: TimeInterval = 7 * 24 * 3600
    @MainActor private static var memory: [String: Lyrics?] = [:]

    private struct Cached: Codable { let none: Bool; let lyrics: Lyrics? }
    private struct Candidate: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static func cacheURL(_ id: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id).json")
    }

    /// Letra de `song`; nil si no hay. Lanza error sólo si falla la red y no hay nada guardado.
    @MainActor static func lyrics(for song: Song, duration: Double) async throws -> Lyrics? {
        if let hit = memory[song.id] { return hit }
        let url = cacheURL(song.id)
        if let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Cached.self, from: data) {
            let age = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date().timeIntervalSince($0) } ?? 0
            if !c.none || age < noneTTL {
                memory[song.id] = c.lyrics
                return c.lyrics
            }
        }
        let title = Lyrics.cleanTitle(song.title), artist = Lyrics.mainArtist(song.artist)
        var candidates = try await search(["track_name": title, "artist_name": artist])
        if candidates.isEmpty { candidates = try await search(["q": "\(title) \(artist)"]) }
        let found = pick(candidates, duration: duration)
        // Sin la duración se elige a ciegas entre versiones: no se guarda, para repetir la búsqueda cuando se sepa.
        guard duration > 0 else { return found }
        if let data = try? JSONEncoder().encode(Cached(none: found == nil, lyrics: found)) { try? data.write(to: url) }
        memory[song.id] = found
        return found
    }

    private static func pick(_ cs: [Candidate], duration: Double) -> Lyrics? {
        let near = cs.filter { duration <= 0 || abs(($0.duration ?? 0) - duration) <= 10 }
        func isSynced(_ c: Candidate) -> Bool { !(c.syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let best = near.sorted { a, b in
            if isSynced(a) != isSynced(b) { return isSynced(a) }
            return abs((a.duration ?? 0) - duration) < abs((b.duration ?? 0) - duration)
        }.first
        guard let best else { return nil }
        if best.instrumental == true { return Lyrics(lines: [], plain: nil, instrumental: true) }
        let lines = Lyrics.parseLRC(best.syncedLyrics ?? "")
        let plain = best.plainLyrics.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return lines.isEmpty && plain == nil ? nil : Lyrics(lines: lines, plain: plain)
    }

    private static func search(_ params: [String: String]) async throws -> [Candidate] {
        var comps = URLComponents(string: "\(base)/search")!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.setValue("PearMusic (https://github.com/ToxBox8/pear-music)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([Candidate].self, from: data)
    }
}

/// Lo que ocupa el sitio de la carátula al pulsar el botón de la cola.
enum PlayerPanel: String { case queue, lyrics }

/// Letra de la canción que suena (pestaña «Letra» junto a «Cola»). Sincronizada: la línea actual resaltada y
/// centrada; tocar una línea salta a ese momento. Mismo aspecto que `LyricsView` en Android.
struct LyricsView: View {
    let song: Song
    @EnvironmentObject var player: Player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Load: Equatable { case loading, ready(Lyrics?), failed }
    @State private var load: Load = .loading
    @State private var attempt = 0
    /// `player.duration` y `player.progress` viven en `player.clock`, que esta vista no observa: se copian aquí para
    /// volver a buscar la letra al saber la duración y para mover la línea al saltar con la música en pausa.
    @State private var durationKnown = false
    @State private var progressTick = 0.0

    var body: some View {
        Group {
            switch load {
            case .loading: ProgressView()
            case .failed:
                VStack(spacing: 12) {
                    Text(L("No se pudo cargar la letra")).font(.headline)
                    Text(L("Revisa la conexión e inténtalo otra vez.")).font(.subheadline).foregroundStyle(.secondary)
                    Button { attempt += 1 } label: { Label(L("Reintentar"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                }
            case .ready(let lyrics):
                if let lyrics {
                    if lyrics.instrumental { note("Instrumental") }
                    else if lyrics.synced { synced(lyrics) }
                    else {
                        ScrollView {
                            VStack(alignment: .leading) {
                                Text(lyrics.plain ?? "").font(.title3.weight(.semibold))
                                credit
                            }
                            .padding(.horizontal, 24).padding(.vertical, 16)
                        }
                    }
                } else { note(L("No hay letra para esta canción")) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(player.clock.$duration) { if ($0 > 0) != durationKnown { durationKnown = $0 > 0 } }
        .onReceive(player.clock.$progress) { if !player.isPlaying { progressTick = $0 } }
        .task(id: "\(song.id)-\(attempt)-\(durationKnown)") {
            load = .loading
            do { load = .ready(try await LyricsClient.lyrics(for: song, duration: player.duration)) }
            catch { load = .failed }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(.secondary)
    }

    private var credit: some View {
        Text(L("Letra de LRCLIB")).font(.caption).foregroundStyle(.tertiary).padding(.vertical, 20)
    }

    private func synced(_ lyrics: Lyrics) -> some View {
        // El progreso llega cada 0,5 s; entre medias se calcula en cada fotograma para que la línea cambie a tiempo.
        TimelineView(.animation(paused: !player.isPlaying)) { ctx in
            let position = player.isPlaying ? player.clock.progress(at: ctx.date, playing: true, rate: player.rate) : progressTick
            let current = lyrics.index(at: position)
            SyncedLyricsList(lyrics: lyrics, current: current, reduceMotion: reduceMotion) { player.seek(to: $0) }
        }
    }
}

private struct SyncedLyricsList: View {
    let lyrics: Lyrics
    let current: Int
    let reduceMotion: Bool
    let onSeek: (Double) -> Void
    @State private var userScrolledAt = Date.distantPast

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 140)
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { i, line in
                        Button { onSeek(line.time) } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title3.bold())
                                .foregroundStyle(i == current ? Color.primary : Color.secondary.opacity(i < current ? 0.55 : 1))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24).padding(.vertical, 9)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(i)
                        .animation(.uiEaseOut(0.3), value: current)
                    }
                    Text(L("Letra de LRCLIB")).font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.vertical, 20)
                    Color.clear.frame(height: 200)
                }
            }
            .simultaneousGesture(DragGesture().onChanged { _ in userScrolledAt = Date() })
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                         .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onChange(of: current) { i in
                // Si la persona está moviendo la letra, se le deja 3 s antes de volver a seguir la canción.
                guard i >= 0, Date().timeIntervalSince(userScrolledAt) > 3 else { return }
                if reduceMotion { proxy.scrollTo(i, anchor: .center) }
                else { withAnimation(.uiEaseOut(0.5)) { proxy.scrollTo(i, anchor: .center) } }
            }
            .onAppear { if current >= 0 { proxy.scrollTo(current, anchor: .center) } }
        }
    }
}
