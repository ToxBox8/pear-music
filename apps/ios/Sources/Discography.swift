import Foundation

/// Discografía completa de un artista (Fase 3.1), igual que `Discography` en Android: YouTube Music («Ver todo»,
/// lo que se puede escuchar) completada con **MusicBrainz** (API pública y documentada); lo que YouTube Music no
/// tiene sale como «No disponible para escuchar». MusicBrainz pide User-Agent con contacto y 1 petición por segundo.
enum Discography {
    enum Kind { case album, single }
    struct MbRelease: Hashable { let title: String; let year: String; let kind: Kind }
    enum Item: Hashable { case playable(RemoteCollection), missing(MbRelease) }

    private static let ua = "PearMusic/2.0 ( https://github.com/ToxBox8/pear-music )"
    private actor Throttle {
        var last = Date.distantPast
        func wait() async {
            let gap = Date().timeIntervalSince(last)
            if gap < 1.1 { try? await Task.sleep(nanoseconds: UInt64((1.1 - gap) * 1_000_000_000)) }
            last = Date()
        }
    }
    private static let throttle = Throttle()
    private static let cache = NSCache<NSString, NSArray>()

    /// Minúsculas, sin tildes, sin «(feat. …)», «- Single», signos ni espacios.
    static func normalize(_ s: String) -> String {
        var t = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        t = t.replacingOccurrences(of: #"\((feat|ft|with|con)[^)]*\)|\[(feat|ft)[^\]]*\]|\s-\s(single|ep)$"#, with: "", options: .regularExpression)
        return t.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "", options: .regularExpression)
    }

    private static func get(_ url: URL) async -> [String: Any]? {
        await throttle.wait()
        var r = URLRequest(url: url)
        r.setValue(ua, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: r), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Discos oficiales del artista (sin recopilatorios, directos ni remezclas), o nil sin red.
    static func musicBrainz(_ artistName: String) async -> [MbRelease]? {
        let key = normalize(artistName)
        if let hit = cache.object(forKey: key as NSString) as? [MbRelease] { return hit }
        var c = URLComponents(string: "https://musicbrainz.org/ws/2/artist")!
        c.queryItems = [.init(name: "query", value: "artist:\"\(artistName.replacingOccurrences(of: "\"", with: ""))\""), .init(name: "limit", value: "5"), .init(name: "fmt", value: "json")]
        guard let found = (await get(c.url!))?["artists"] as? [[String: Any]] else { return nil }
        // Sólo si el nombre coincide de verdad: mejor no completar que completar con otro artista.
        guard let mbid = found.first(where: { ($0["score"] as? Int ?? 0) >= 90 && normalize($0["name"] as? String ?? "") == key })?["id"] as? String else {
            cache.setObject([] as NSArray, forKey: key as NSString)
            return []
        }
        var out: [MbRelease] = []
        var offset = 0
        while offset < 400 {
            var g = URLComponents(string: "https://musicbrainz.org/ws/2/release-group")!
            g.queryItems = [.init(name: "artist", value: mbid), .init(name: "type", value: "album|ep|single"), .init(name: "limit", value: "100"),
                            .init(name: "offset", value: String(offset)), .init(name: "fmt", value: "json")]
            guard let page = await get(g.url!), let groups = page["release-groups"] as? [[String: Any]] else { break }
            for r in groups where ((r["secondary-types"] as? [Any]) ?? []).isEmpty {
                out.append(MbRelease(title: r["title"] as? String ?? "", year: String((r["first-release-date"] as? String ?? "").prefix(4)),
                                     kind: (r["primary-type"] as? String) == "Album" ? .album : .single))
            }
            offset += groups.count
            if groups.count < 100 || offset >= (page["release-group-count"] as? Int ?? 0) { break }
        }
        cache.setObject(out as NSArray, forKey: key as NSString)
        return out
    }

    /// YouTube Music primero (en su orden) y detrás lo que falta de MusicBrainz del mismo tipo, del más nuevo al más viejo.
    static func merge(_ yt: [RemoteCollection], _ mb: [MbRelease], kind: Kind) -> [Item] {
        let have = Set(yt.map { normalize($0.title) })
        var seen = Set<String>()
        let missing = mb.filter { $0.kind == kind && !have.contains(normalize($0.title)) && seen.insert(normalize($0.title)).inserted }
            .sorted { $0.year > $1.year }
        return yt.map(Item.playable) + missing.map(Item.missing)
    }
}
