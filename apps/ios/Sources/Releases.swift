import Foundation

/// «Novedades de tus artistas» en Inicio: lo que han sacado este año (o el anterior, en enero y febrero) los artistas
/// que más escuchas. Mismas reglas y caché de un día que `Releases` en Android.
enum Releases {
    static let artistsCount = 8
    static let max = 12
    private static let ttl: TimeInterval = 24 * 3600

    /// Los `n` artistas que más escuchas: escuchas de las estadísticas (×2) + canciones guardadas.
    @MainActor static func topArtists(saved: [Song], n: Int = artistsCount) -> [String] {
        var score: [String: Int] = [:]
        saved.forEach { score[primaryArtist($0.artist), default: 0] += 1 }
        let stats = PlayStats.shared
        stats.plays.forEach { p in if let s = stats.songs[p.id] { score[primaryArtist(s.artist), default: 0] += 2 } }
        return score.filter { $0.key != "Desconocido" && !$0.key.isEmpty }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.lowercased() < $1.key.lowercased() }
            .prefix(n).map(\.key)
    }

    /// Año mínimo que cuenta como novedad: este año, o también el pasado en enero y febrero.
    static func minYear(_ date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return (c.year ?? 0) - ((c.month ?? 12) <= 2 ? 1 : 0)
    }

    static func year(of c: RemoteCollection) -> Int? {
        c.subtitle.components(separatedBy: " • ").last.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Lanzamientos recientes de cada artista, intercalados (uno de cada artista por turno) y como mucho `max`.
    static func pick(_ byArtist: [[RemoteCollection]], minYear: Int) -> [RemoteCollection] {
        let lists = byArtist.map { l in
            l.enumerated().filter { (year(of: $0.element) ?? 0) >= minYear }
                .sorted { (year(of: $0.element) ?? 0, -$0.offset) > (year(of: $1.element) ?? 0, -$1.offset) }
                .map(\.element)
        }
        var out: [RemoteCollection] = []
        var i = 0
        while out.count < max, lists.contains(where: { $0.count > i }) {
            for l in lists where l.count > i && !out.contains(where: { $0.id == l[i].id }) { out.append(l[i]) }
            i += 1
        }
        return Array(out.prefix(max))
    }

    private struct Cached: Codable {
        let key: String
        let items: [Item]
        struct Item: Codable { let id, title, subtitle: String; let thumbnail: URL? }
    }

    static func load(artists: [String]) async -> [RemoteCollection] {
        guard !artists.isEmpty else { return [] }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("releases.json")
        let key = artists.joined(separator: "|")
        if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(date) < ttl,
           let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Cached.self, from: data), c.key == key {
            return c.items.map { RemoteCollection(id: $0.id, title: $0.title, subtitle: $0.subtitle, thumbnail: $0.thumbnail) }
        }
        let pages = await withTaskGroup(of: (Int, [RemoteCollection]).self) { group in
            for (i, name) in artists.enumerated() {
                group.addTask {
                    let folded = LocalSearch.fold(name)
                    guard let found = try? await YTClient.searchArtists(name),
                          let a = found.first(where: { LocalSearch.fold($0.name) == folded }),
                          let page = try? await YTClient.artist(a) else { return (i, []) }
                    return (i, page.albums + page.singles)
                }
            }
            var out = Array(repeating: [RemoteCollection](), count: artists.count)
            for await (i, l) in group { out[i] = l }
            return out
        }
        let items = pick(pages, minYear: minYear())
        let cached = Cached(key: key, items: items.map { .init(id: $0.id, title: $0.title, subtitle: $0.subtitle, thumbnail: $0.thumbnail) })
        if let data = try? JSONEncoder().encode(cached) { try? data.write(to: url) }
        return items
    }
}
