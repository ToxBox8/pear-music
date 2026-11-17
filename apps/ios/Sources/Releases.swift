import Foundation

/// «Novedades de tus artistas» en Inicio: lo que han sacado este año (o el anterior, en enero y febrero) los artistas
/// que sigues y, si sigues a menos de 8, los que más escuchas. Las reglas (quién sale, qué se pide, «Nuevo», orden)
/// están en `ReleaseMix` (ReleasesModel.swift); aquí, las peticiones y la caché. Igual que `Releases` en Android.
enum Releases {
    static let artistsCount = ReleaseMix.artists

    /// Los `n` artistas que más escuchas: escuchas de las estadísticas (×2) + canciones guardadas.
    @MainActor static func topArtists(saved: [Song], n: Int = artistsCount) -> [String] {
        var score: [String: Int] = [:]
        saved.forEach { score[primaryArtist($0.artist), default: 0] += 1 }
        let stats = PlayStats.shared
        stats.plays.forEach { p in if let s = stats.songs[p.id] { score[primaryArtist(s.artist), default: 0] += 2 } }
        return score.filter { $0.key != "Desconocido" && $0.key != L("Desconocido") && !$0.key.isEmpty }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.lowercased() < $1.key.lowercased() }
            .prefix(n).map(\.key)
    }

    static func minYear(_ date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return ReleaseMix.minYear(year: c.year ?? 0, month: c.month ?? 12)
    }

    /// Caché del móvil (no va en library.json). La de antes de la 3.0 (`releases.json`) se borra.
    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("releases-v3.json")
    }

    private static func readCache() -> ReleasesCache {
        guard let data = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(ReleasesCache.self, from: data) else {
            return ReleasesCache()
        }
        return c
    }

    private enum Fetched {
        /// Página del artista (con el `browseId` si se ha buscado por nombre).
        case page(ReleaseSource, browseId: String, items: [ReleaseItem])
        /// Buscado por nombre y no está en YouTube Music.
        case notFound(ReleaseSource)
        /// Sin red o error: no se toca lo guardado.
        case failed
    }

    private static func fetch(_ s: ReleaseSource) async -> Fetched {
        var id = s.browseId
        if id == nil {
            let folded = LocalSearch.fold(s.name)
            guard let found = try? await YTClient.searchArtists(s.name) else { return .failed }
            guard let a = found.first(where: { LocalSearch.fold($0.name) == folded }) else { return .notFound(s) }
            id = a.id
        }
        guard let id, let page = try? await YTClient.artist(RemoteArtist(id: id, name: s.name, subtitle: "", thumbnail: nil)) else {
            return .failed
        }
        let items = (page.albums + page.singles).map { ReleaseItem(id: $0.id, title: $0.title, subtitle: $0.subtitle, thumbnail: $0.thumbnail) }
        return .page(s, browseId: id, items: items)
    }

    /// Pide lo que toque (como mucho 8 artistas, cada uno como mucho cada 6 h), lo guarda y devuelve lo que sale en
    /// Inicio. Sin red, lo último que se guardó.
    static func load(followed: [FollowedArtist], top: [String]) async -> [ReleasePick] {
        if DemoCatalog.isActive { return DemoCatalog.releases }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let topPairs = top.map { (name: $0, folded: LocalSearch.fold($0)) }
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent().appendingPathComponent("releases.json"))
        var cache = ReleaseMix.prune(readCache(), followed: followed, topFolded: topPairs.map(\.folded))
        let due = ReleaseMix.toRefresh(ReleaseMix.sources(followed: followed, top: topPairs, resolved: cache.resolved,
                                                          fold: LocalSearch.fold), cache: cache, now: now)
        let results = await withTaskGroup(of: Fetched.self) { group in
            for s in due { group.addTask { await fetch(s) } }
            var out: [Fetched] = []
            for await r in group { out.append(r) }
            return out
        }
        for r in results {
            switch r {
            case let .page(s, browseId, items):
                if s.browseId == nil { cache = ReleaseMix.resolve(cache, folded: LocalSearch.fold(s.name), browseId: browseId) }
                cache = ReleaseMix.record(cache, key: browseId, name: s.name, items: items, now: now)
            case let .notFound(s):
                cache = ReleaseMix.resolve(cache, folded: LocalSearch.fold(s.name), browseId: nil)
                cache = ReleaseMix.record(cache, key: s.key, name: s.name, items: [], now: now)
            case .failed:
                break
            }
        }
        if !due.isEmpty, let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
        let sources = ReleaseMix.sources(followed: followed, top: topPairs, resolved: cache.resolved, fold: LocalSearch.fold)
        return ReleaseMix.pick(sources, cache: cache, now: now, minYear: minYear())
    }
}

extension ReleasePick {
    var collection: RemoteCollection {
        RemoteCollection(id: item.id, title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail)
    }
}
