import Foundation

// Reglas de «Novedades de tus artistas» (Inicio), sólo Foundation: se prueban en Linux con scripts/test-linux.sh.
// Las peticiones a YouTube Music están en Releases.swift. Mismos nombres, casos y resultados que `ReleaseMix` en
// Android (data/Releases.kt).

/// Un lanzamiento (álbum, single o EP) de la página de un artista. YouTube Music sólo da el año, al final del
/// subtítulo: «Single • Michael Bennet • 2026».
struct ReleaseItem: Codable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var thumbnail: URL?

    var year: Int? {
        subtitle.components(separatedBy: " • ").last.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// Lo que se guarda en `releases-v3.json` (caché del móvil; no va en library.json ni viaja con la copia).
struct ReleasesCache: Codable {
    /// Por artista (clave: su `browseId`, o `name:<nombre plegado>` si es de los más escuchados y no se encontró).
    var artists: [String: Entry] = [:]
    /// De los más escuchados: nombre plegado → `browseId`, para no volver a buscarlo.
    var resolved: [String: String] = [:]

    struct Entry: Codable, Hashable {
        var name: String
        /// Cuándo se pidió su página por última vez (ms).
        var fetchedAt: Int64
        var items: [ReleaseItem]
        /// Cuándo se vio por primera vez cada lanzamiento (ms). 0 = estaba ya en la primera consulta: nunca es «Nuevo».
        var seen: [String: Int64]
    }
}

/// Un artista del que se enseñan novedades.
struct ReleaseSource: Hashable {
    /// Clave en `ReleasesCache.artists`.
    var key: String
    /// `browseId` si se sabe (los seguidos siempre); nil = hay que buscarlo por nombre.
    var browseId: String?
    var name: String
    var followed: Bool
}

/// Un lanzamiento elegido para Inicio, con su marca «Nuevo».
struct ReleasePick: Hashable {
    var item: ReleaseItem
    var isNew: Bool
}

enum ReleaseMix {
    /// Artistas que se vuelven a consultar en cada carga, y de los más escuchados cuántos completan.
    static let artists = 8
    static let max = 12
    /// Como mucho una consulta por artista cada 6 h.
    static let ttl: Int64 = 6 * 3600 * 1000
    /// «Nuevo» dura 7 días desde que se ve por primera vez.
    static let newFor: Int64 = 7 * 24 * 3600 * 1000
    static let namePrefix = "name:"

    /// Año mínimo que cuenta como novedad: este año, o también el pasado en enero y febrero.
    static func minYear(year: Int, month: Int) -> Int { year - (month <= 2 ? 1 : 0) }

    /// Qué artistas salen: todos los seguidos (en su orden) y, si son menos de 8, los más escuchados que no sigues
    /// hasta llegar a 8. `top` va de más a menos escuchado, con su nombre plegado (`LocalSearch.fold`).
    static func sources(followed: [FollowedArtist], top: [(name: String, folded: String)],
                        resolved: [String: String], fold: (String) -> String) -> [ReleaseSource] {
        var out = followed.map { ReleaseSource(key: $0.browseId, browseId: $0.browseId, name: $0.name, followed: true) }
        let followedIDs = Set(followed.map(\.browseId))
        let followedNames = Set(followed.map { fold($0.name) })
        for t in top where out.count < artists {
            guard !followedNames.contains(t.folded) else { continue }
            let id = resolved[t.folded].flatMap { $0.isEmpty ? nil : $0 }
            if let id, followedIDs.contains(id) { continue }
            let key = id ?? namePrefix + t.folded
            guard !out.contains(where: { $0.key == key }) else { continue }
            out.append(ReleaseSource(key: key, browseId: id, name: t.name, followed: false))
        }
        return out
    }

    /// Los que toca volver a pedir: sin consultar o consultados hace 6 h o más; primero los que nunca se pidieron y
    /// después los más antiguos. Como mucho 8 (con muchos seguidos, por turnos).
    static func toRefresh(_ sources: [ReleaseSource], cache: ReleasesCache, now: Int64) -> [ReleaseSource] {
        let stale = sources.enumerated().compactMap { (i, s) -> (Int, Int64, ReleaseSource)? in
            guard let e = cache.artists[s.key] else { return (i, Int64.min, s) }
            return now - e.fetchedAt >= ttl ? (i, e.fetchedAt, s) : nil
        }
        return stale.sorted { ($0.1, $0.0) < ($1.1, $1.0) }.prefix(artists).map(\.2)
    }

    /// Guarda lo que se acaba de pedir de un artista. La primera consulta de cada artista no marca nada como nuevo;
    /// en las siguientes, lo que no se había visto nunca se marca con la hora de ahora.
    static func record(_ cache: ReleasesCache, key: String, name: String, items: [ReleaseItem], now: Int64) -> ReleasesCache {
        var cache = cache
        var seen = cache.artists[key]?.seen
        let first = seen == nil
        var s = seen ?? [:]
        for item in items where s[item.id] == nil { s[item.id] = first ? 0 : now }
        seen = s
        cache.artists[key] = ReleasesCache.Entry(name: name, fetchedAt: now, items: items, seen: s)
        return cache
    }

    /// Un artista de los más escuchados que se ha encontrado: su entrada pasa a ir por `browseId` (si ya estaba por
    /// `browseId`, por ejemplo porque lo seguías antes, se conserva lo visto).
    static func resolve(_ cache: ReleasesCache, folded: String, browseId: String?) -> ReleasesCache {
        var cache = cache
        cache.resolved[folded] = browseId ?? ""
        if let browseId, let old = cache.artists.removeValue(forKey: namePrefix + folded), cache.artists[browseId] == nil {
            cache.artists[browseId] = old
        }
        return cache
    }

    /// Quita lo que ya no hace falta: artistas que no sigues ni están entre tus 8 más escuchados.
    static func prune(_ cache: ReleasesCache, followed: [FollowedArtist], topFolded: [String]) -> ReleasesCache {
        var cache = cache
        let names = Set(topFolded)
        cache.resolved = cache.resolved.filter { names.contains($0.key) }
        var keep = Set(followed.map(\.browseId))
        for f in topFolded {
            keep.insert(namePrefix + f)
            if let id = cache.resolved[f], !id.isEmpty { keep.insert(id) }
        }
        cache.artists = cache.artists.filter { keep.contains($0.key) }
        return cache
    }

    static func isNew(_ id: String, in entry: ReleasesCache.Entry, now: Int64) -> Bool {
        guard let at = entry.seen[id], at > 0 else { return false }
        return now - at < newFor
    }

    /// Lo que sale en Inicio: primero lo marcado «Nuevo», después lo de los seguidos y luego lo de los más
    /// escuchados; en cada grupo, uno de cada artista por turno (el artista con lo más reciente, antes) y como mucho
    /// 12 en total. Sólo lanzamientos de `minYear` o después; sin red, sale lo último que se guardó.
    static func pick(_ sources: [ReleaseSource], cache: ReleasesCache, now: Int64, minYear: Int) -> [ReleasePick] {
        typealias Lists = [[ReleasePick]]
        var fresh: Lists = [], followed: Lists = [], top: Lists = []
        var freshAt: [Int64] = []
        for s in sources {
            guard let e = cache.artists[s.key] else { continue }
            let recent = e.items.enumerated().filter { ($0.element.year ?? 0) >= minYear }
                .sorted { (($0.element.year ?? 0), -$0.offset) > (($1.element.year ?? 0), -$1.offset) }
                .map(\.element)
            let new = recent.filter { isNew($0.id, in: e, now: now) }.map { ReleasePick(item: $0, isNew: true) }
            let rest = recent.filter { !isNew($0.id, in: e, now: now) }.map { ReleasePick(item: $0, isNew: false) }
            if !new.isEmpty {
                fresh.append(new)
                freshAt.append(new.compactMap { e.seen[$0.item.id] }.max() ?? 0)
            }
            if !rest.isEmpty { if s.followed { followed.append(rest) } else { top.append(rest) } }
        }
        // Lo nuevo, lo último en aparecer antes; el resto, el artista con el lanzamiento más reciente antes.
        let freshSorted = zip(fresh, freshAt).enumerated().sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }
            .map(\.element.0)
        func byYear(_ l: Lists) -> Lists {
            l.enumerated().sorted { (($0.element.first?.item.year ?? 0), -$0.offset) > (($1.element.first?.item.year ?? 0), -$1.offset) }
                .map(\.element)
        }
        var out: [ReleasePick] = []
        var ids = Set<String>()
        for group in [freshSorted, byYear(followed), byYear(top)] {
            var i = 0
            while out.count < max, group.contains(where: { $0.count > i }) {
                for l in group where l.count > i && out.count < max && ids.insert(l[i].item.id).inserted { out.append(l[i]) }
                i += 1
            }
        }
        return out
    }
}
