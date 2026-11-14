import Foundation

/// «No me interesa» en Descubrir (2.7 de x.1.1). Se guarda sólo en el iPhone (`reels_skip.json`: id, artista y fecha).
/// La canción no vuelve a salir; el artista baja de peso y, con 3 «No me interesa» en 30 días, sale de Descubrir otros
/// 30 días (no se veta para siempre). Igual que `ReelsSkip` en Android.
@MainActor
final class ReelsSkip: ObservableObject {
    struct Entry: Codable, Equatable { let id: String; let artist: String; let at: Double }

    static let shared = ReelsSkip()
    nonisolated static let day: Double = 86_400
    nonisolated static let window: Double = 30 * day
    nonisolated static let artistLimit = 3

    @Published private(set) var entries: [Entry] = []
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("reels_skip.json")

    private init() {
        entries = (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))) ?? []
    }

    func add(_ song: Song, now: Date = Date()) {
        save(entries.filter { $0.id != song.id } + [Entry(id: song.id, artist: primaryArtist(song.artist), at: now.timeIntervalSince1970)])
    }
    func remove(_ id: String) { save(entries.filter { $0.id != id }) }
    func clear() { save([]) }

    private func save(_ list: [Entry]) {
        entries = list
        try? JSONEncoder().encode(list).write(to: url, options: .atomic)
    }

    /// Fuera las canciones marcadas y las de los artistas con `artistLimit` marcas en 30 días.
    func filter(_ items: [Song], now: Date = Date()) -> [Song] { Self.filter(items, entries: entries, now: now.timeIntervalSince1970) }

    nonisolated static func filter(_ items: [Song], entries: [Entry], now: Double) -> [Song] {
        let ids = Set(entries.map(\.id))
        let artists = blockedArtists(entries, now: now)
        return items.filter { !ids.contains($0.id) && !artists.contains(primaryArtist($0.artist).lowercased()) }
    }

    /// Artistas con `artistLimit` marcas en menos de 30 días, durante los 30 días siguientes a la última de ellas.
    nonisolated static func blockedArtists(_ entries: [Entry], now: Double) -> Set<String> {
        let groups = Dictionary(grouping: entries.filter { !$0.artist.isEmpty }) { primaryArtist($0.artist).lowercased() }
        return Set(groups.compactMap { artist, list in
            let t = list.map(\.at).sorted()
            guard t.count >= artistLimit else { return nil }
            let hit = (artistLimit - 1 ..< t.count).contains { i in t[i] - t[i - artistLimit + 1] < window && now - t[i] < window }
            return hit ? artist : nil
        })
    }
}
