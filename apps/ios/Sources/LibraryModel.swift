import Foundation

// Modelo de la biblioteca (library.json, docs/LIBRARY_FORMAT.md). Sólo Foundation: se prueba en Linux con
// scripts/test-linux.sh. La persistencia y la interfaz siguen en Store.swift. Mismo formato y reglas que
// data/Library.kt y data/PlaylistFolders.kt en Android.

struct Playlist: Identifiable, Codable {
    var id = UUID()
    var name: String
    var songs: [Song] = []
    var icon: String?       // SF Symbol elegido (si no hay foto)
    var tint: Int?          // índice en PlaylistStyle.palettes
    /// Si es un álbum guardado («Tus álbumes»): no sale en Playlists. docs/LIBRARY_FORMAT.md
    var album: AlbumInfo?
    /// Fijado arriba en Biblioteca e Inicio para abrirlo de un toque (Fase 3.3). nil = no.
    var pinned: Bool?
    /// Carpeta en la que está (3.0, bloque 1). nil = fuera de las carpetas. Los álbumes no van en carpetas.
    var folder: String?
}

extension Playlist {
    /// Igual que el decodificador sintetizado (mismas claves obligatorias), salvo `folder`: si no es un texto se
    /// lee como «sin carpeta» en vez de hacer fallar toda la biblioteca. Al declararlo en una extensión, Swift
    /// mantiene el inicializador por miembros.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        songs = try c.decode([Song].self, forKey: .songs)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        tint = try c.decodeIfPresent(Int.self, forKey: .tint)
        album = try c.decodeIfPresent(AlbumInfo.self, forKey: .album)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned)
        folder = (try? c.decodeIfPresent(String.self, forKey: .folder)) ?? nil
    }
}

/// Datos de un álbum de YouTube Music guardado como lista. Mismo formato que `AlbumInfo` en Android.
struct AlbumInfo: Codable, Hashable {
    var browseId: String    // "MPREb_…"
    var artist: String?
    var year: String?

    /// Del subtítulo de YouTube Music: «Álbum • Artista • 2024» o «Artista • 2024».
    init(browseId: String, subtitle: String) {
        self.browseId = browseId
        let parts = subtitle.components(separatedBy: " • ").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && ![L("Álbum"), "Album", "Single", "EP"].contains($0) }
        if let last = parts.last, last.count == 4, Int(last) != nil {
            year = last
            artist = parts.dropLast().first
        } else {
            artist = parts.first
        }
    }

    /// «Artista · 2024», lo que haya.
    var line: String { [artist, year].compactMap { $0 }.joined(separator: " · ") }
}

// MARK: - Carpetas de playlists (3.0, bloque 1)

/// Una carpeta para ordenar las playlists. Puede estar dentro de otra (`parent`), hasta 3 niveles.
/// En el código se llama `PlaylistFolder` para no confundirla con las «carpetas» de Tu música (`MusicOrder`).
struct PlaylistFolder: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var parent: String?
    /// Reservados (opcionales): la portada de una carpeta es el mosaico de lo que guarda. Se conservan al
    /// importar y exportar.
    var icon: String?
    var tint: Int?

    init(id: String = UUID().uuidString, name: String, parent: String? = nil, icon: String? = nil, tint: Int? = nil) {
        self.id = id; self.name = name; self.parent = parent; self.icon = icon; self.tint = tint
    }

    /// `id` y `name` tienen que ser textos; lo demás, si no es del tipo esperado, se lee como si no estuviera.
    /// Igual que `PlaylistFolder.fromJson` en Android.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        parent = (try? c.decodeIfPresent(String.self, forKey: .parent)) ?? nil
        icon = (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? nil
        tint = (try? c.decodeIfPresent(Int.self, forKey: .tint)) ?? nil
    }
}

/// Una lista que se salta los elementos que no se pueden leer, en vez de fallar entera.
struct LossyList<T: Decodable>: Decodable {
    var items: [T] = []
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            if let item = try? c.decode(T.self) { items.append(item) } else { _ = try? c.decode(Skip.self) }
        }
    }
}

/// Lo que puede ir en una carpeta. `Playlist` lo cumple; los tests de Linux usan el suyo.
protocol FolderMember {
    var memberID: String { get }
    var folder: String? { get set }
    /// Los álbumes guardados no van en carpetas.
    var canBeInFolder: Bool { get }
}

extension Playlist: FolderMember {
    var memberID: String { id.uuidString }
    var canBeInFolder: Bool { album == nil }
}

/// Reglas de las carpetas. Mismos nombres, casos y resultados que `PlaylistFolders` en Android
/// (los casos comunes están en shared/library/).
enum PlaylistFolders {
    static let maxDepth = 3
    static let defaultName = "Carpeta"

    /// Deja las carpetas listas para usar:
    /// - sin id → fuera; id repetido → se queda la primera; nombre vacío → «Carpeta»;
    /// - un `parent` que no existe, que es ella misma o que forma un ciclo → sin carpeta (arriba del todo);
    /// - si quedaría a más de 3 niveles → sin carpeta (y lo suyo la sigue).
    static func normalize(_ folders: [PlaylistFolder]) -> [PlaylistFolder] {
        var seen = Set<String>()
        var list: [PlaylistFolder] = []
        for var f in folders {
            let id = f.id.trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            f.id = id
            let name = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
            f.name = name.isEmpty ? defaultName : name
            if let p = f.parent?.trimmingCharacters(in: .whitespaces), !p.isEmpty { f.parent = p } else { f.parent = nil }
            list.append(f)
        }
        let ids = Set(list.map(\.id))
        var parent: [String: String] = [:]
        for f in list { if let p = f.parent, ids.contains(p), p != f.id { parent[f.id] = p } }
        // Ciclos: las carpetas que, subiendo por sus padres, vuelven a sí mismas se quedan arriba del todo.
        var inCycle = Set<String>()
        for f in list {
            var seenUp: Set<String> = [f.id]
            var cur = parent[f.id]
            while let c = cur {
                if c == f.id { inCycle.insert(f.id); break }
                if !seenUp.insert(c).inserted { break } // ciclo más arriba, no la incluye
                cur = parent[c]
            }
        }
        for id in inCycle { parent[id] = nil }
        // Niveles: de arriba abajo; la que pasaría de 3 sube arriba del todo.
        var depth: [String: Int] = [:]
        func level(_ id: String) -> Int {
            if let d = depth[id] { return d }
            var d = 1
            if let p = parent[id] {
                d = level(p) + 1
                if d > maxDepth { parent[id] = nil; d = 1 }
            }
            depth[id] = d
            return d
        }
        for f in list { _ = level(f.id) }
        return list.map { var f = $0; f.parent = parent[f.id]; return f }
    }

    /// Quita la carpeta a lo que no puede tenerla: álbumes y carpetas que no existen.
    static func clean<M: FolderMember>(_ members: [M], folders: [PlaylistFolder]) -> [M] {
        let ids = Set(folders.map(\.id))
        return members.map { m in
            guard let f = m.folder else { return m }
            var m = m
            if !m.canBeInFolder || !ids.contains(f) { m.folder = nil }
            return m
        }
    }

    /// Importar = unir: se añaden las carpetas que no existan (por id); las tuyas no cambian.
    static func merge(_ local: [PlaylistFolder], _ incoming: [PlaylistFolder]) -> [PlaylistFolder] {
        var ids = Set(local.map(\.id))
        return normalize(local + incoming.filter { ids.insert($0.id).inserted })
    }

    /// Nivel de una carpeta: 1 arriba del todo; 0 para «sin carpeta» (nil).
    static func depth(_ id: String?, in folders: [PlaylistFolder]) -> Int {
        guard let id else { return 0 }
        let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var d = 0
        var cur: String? = id
        while let c = cur, let f = byID[c], d <= folders.count { d += 1; cur = f.parent }
        return d
    }

    /// Cuántos niveles ocupa una carpeta con todo lo que tiene dentro (1 si no tiene subcarpetas).
    static func height(_ id: String, in folders: [PlaylistFolder]) -> Int {
        let children = folders.filter { $0.parent == id }
        return 1 + (children.map { height($0.id, in: folders) }.max() ?? 0)
    }

    /// La carpeta y todas las que tiene dentro, a cualquier nivel.
    static func subtree(_ id: String, in folders: [PlaylistFolder]) -> Set<String> {
        var out: Set<String> = [id]
        var frontier = [id]
        while let cur = frontier.popLast() {
            for f in folders where f.parent == cur && out.insert(f.id).inserted { frontier.append(f.id) }
        }
        return out
    }

    /// Se puede crear una carpeta dentro de `parent` (nil = arriba del todo).
    static func canCreate(in parent: String?, folders: [PlaylistFolder]) -> Bool {
        depth(parent, in: folders) < maxDepth
    }

    /// Se puede mover la carpeta `id` dentro de `target` (nil = arriba del todo): no dentro de sí misma ni de
    /// las suyas, y sin pasar de 3 niveles.
    static func canMove(_ id: String, to target: String?, folders: [PlaylistFolder]) -> Bool {
        if let target, subtree(id, in: folders).contains(target) { return false }
        return depth(target, in: folders) + height(id, in: folders) <= maxDepth
    }

    /// Borrar una carpeta: lo que tenía dentro (carpetas y playlists) sube un nivel. Nunca borra playlists.
    static func delete<M: FolderMember>(_ id: String, folders: [PlaylistFolder], members: [M]) -> ([PlaylistFolder], [M]) {
        guard let gone = folders.first(where: { $0.id == id }) else { return (folders, members) }
        let up = gone.parent
        let nextFolders = folders.filter { $0.id != id }.map { f -> PlaylistFolder in
            var f = f
            if f.parent == id { f.parent = up }
            return f
        }
        let nextMembers = members.map { m -> M in
            var m = m
            if m.folder == id { m.folder = up }
            return m
        }
        return (nextFolders, nextMembers)
    }

    /// De la de arriba del todo a ésta: para «En Gimnasio › Pierna» y el botón de atrás.
    static func path(_ id: String?, in folders: [PlaylistFolder]) -> [PlaylistFolder] {
        let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [PlaylistFolder] = []
        var cur = id
        while let c = cur, let f = byID[c], out.count <= folders.count { out.insert(f, at: 0); cur = f.parent }
        return out
    }

    /// Lo que suena con «Reproducir» en una carpeta: sus playlists y las de sus subcarpetas, en el orden de la lista.
    static func members<M: FolderMember>(of id: String, folders: [PlaylistFolder], in all: [M]) -> [M] {
        let inside = subtree(id, in: folders)
        return all.filter { m in m.folder.map(inside.contains) ?? false }
    }
}

// MARK: - Orden de Tu música › Playlists (antes, del carrusel)
/// Mismas reglas que `LibraryOrder` en Android. Claves: el id de cada playlist y "downloads" /
/// "favorites". `sort`: "recent", "name" (A-Z), "nameDesc" (Z-A), "count" o "custom" (a mano).
enum LibraryOrder {
    static let downloads = "downloads"
    static let favorites = "favorites"

    static func keys(_ playlists: [Playlist], sort: String, order: [String], smartInPlaylists: Bool) -> [String] {
        let smart = smartInPlaylists ? [downloads, favorites] : []
        let byRecent = playlists.reversed().map(\.id.uuidString)
        if sort == "custom" {
            let all = smart + byRecent
            var seen = Set<String>()
            let kept = order.filter { all.contains($0) && seen.insert($0).inserted }
            // Lo nuevo (una playlist recién creada o importada) va al final del orden propio.
            return kept + all.filter { !seen.contains($0) }
        }
        let byName: (Playlist, Playlist) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let sorted: [Playlist]
        switch sort {
        case "name": sorted = playlists.sorted(by: byName)
        case "nameDesc": sorted = playlists.sorted { byName($1, $0) }
        case "count": sorted = playlists.sorted { $0.songs.count > $1.songs.count }
        default: sorted = playlists.reversed()
        }
        return smart + sorted.map(\.id.uuidString)
    }

    static func decode(_ raw: String) -> [String] { raw.split(separator: "\n").map(String.init) }

    /// Mete el orden `moved` (sólo playlists, el de la cuadrícula de Playlists) en el orden completo `full` sin mover
    /// Descargadas ni Favoritos (2.9 de x.1.1).
    static func merge(_ full: [String], _ moved: [String]) -> [String] {
        let set = Set(moved)
        var next = moved.makeIterator()
        return full.map { set.contains($0) ? (next.next() ?? $0) : $0 }
    }

    /// «Tus álbumes»: como se guardaron o, con «custom», el orden propio; lo nuevo va al final.
    static func albums(_ albums: [Playlist], sort: String, order: [String]) -> [Playlist] {
        guard sort == "custom" else { return albums }
        let byID = Dictionary(albums.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        let kept = order.filter { byID[$0] != nil && seen.insert($0).inserted }
        return kept.compactMap { byID[$0] } + albums.filter { !seen.contains($0.id.uuidString) }
    }

    /// «Fijados» (x.1.1): siempre en el orden propio; lo recién fijado va al final.
    static func pinned(_ pinned: [Playlist], order: [String]) -> [Playlist] {
        albums(pinned, sort: "custom", order: order)
    }
}

extension LibraryOrder {
    /// Las claves de un nivel de Tu música › Playlists (`folder` nil = arriba del todo), en el orden en que se ven:
    /// Descargadas y Favoritos (sólo arriba del todo y si van «en Playlists»), las carpetas y las playlists. Las
    /// carpetas se ordenan con el mismo criterio que las playlists («count»: canciones de todo lo que tienen dentro;
    /// «custom»: su sitio en `order`, lo nuevo al final). Igual que `LibraryOrder.level` en Android.
    static func level(_ folder: String?, playlists: [Playlist], folders: [PlaylistFolder], sort: String, order: [String],
                      smartInPlaylists: Bool) -> [String] {
        let here = playlists.filter { $0.folder == folder }
        let keys = Self.keys(here, sort: sort, order: order, smartInPlaylists: folder == nil && smartInPlaylists)
        let mine = folders.filter { $0.parent == folder }
        let byName: (PlaylistFolder, PlaylistFolder) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let sorted: [PlaylistFolder]
        switch sort {
        case "custom":
            var seen = Set<String>()
            let ids = Set(mine.map(\.id))
            let kept = order.filter { ids.contains($0) && seen.insert($0).inserted }
            let byID = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            sorted = kept.compactMap { byID[$0] } + mine.filter { !seen.contains($0.id) }
        case "name": sorted = mine.sorted(by: byName)
        case "nameDesc": sorted = mine.sorted { byName($1, $0) }
        case "count":
            let songs = Dictionary(mine.map { f in
                (f.id, PlaylistFolders.members(of: f.id, folders: folders, in: playlists).reduce(0) { $0 + $1.songs.count })
            }, uniquingKeysWith: { a, _ in a })
            sorted = mine.sorted { (songs[$0.id] ?? 0) > (songs[$1.id] ?? 0) }
        default: sorted = mine.reversed()
        }
        // Detrás de las listas inteligentes que vayan delante y antes de la primera playlist.
        let at = keys.firstIndex { $0 != downloads && $0 != favorites } ?? keys.endIndex
        return Array(keys[..<at]) + sorted.map(\.id) + Array(keys[at...])
    }

    /// El orden de todos los niveles seguidos, tal como se ven con `sort`. Al pasar a «A mano» arrastrando en un
    /// nivel, los demás se quedan como estaban en vez de saltar.
    static func materialize(playlists: [Playlist], folders: [PlaylistFolder], sort: String, order: [String],
                            smartInPlaylists: Bool) -> [String] {
        var out: [String] = []
        var pending: [String?] = [nil]
        var visited = Set<String>()
        while !pending.isEmpty {
            let f = pending.removeFirst()
            out += level(f, playlists: playlists, folders: folders, sort: sort, order: order, smartInPlaylists: smartInPlaylists)
            for sub in folders where sub.parent == f && visited.insert(sub.id).inserted { pending.append(sub.id) }
        }
        return out
    }

    /// Guarda el orden nuevo de un nivel (`moved`, todo lo que se ve en él) en el orden completo, que pasa a «A mano».
    static func reorder(level moved: [String], playlists: [Playlist], folders: [PlaylistFolder], sort: String,
                        order: [String], smartInPlaylists: Bool) -> [String] {
        var full = sort == "custom" ? order : materialize(playlists: playlists, folders: folders, sort: sort,
                                                          order: order, smartInPlaylists: smartInPlaylists)
        let known = Set(full)
        full += moved.filter { !known.contains($0) }
        return merge(full, moved)
    }
}

// MARK: - El archivo library.json

/// Lo que guarda `Library` en library.json (y la parte común de «Exportar copia»). Los órdenes, las portadas y
/// `musicOrder` van aparte (los añade `Library.exportData`).
struct LibraryFile: Codable {
    static let maxRecents = 40

    var favorites: [Song]
    var playlists: [Playlist]
    var recents: [Song]?
    /// Carpetas de playlists (3.0). Sólo se escribe si hay alguna: sin carpetas, library.json queda como antes.
    var folders: [PlaylistFolder]?

    init(favorites: [Song], playlists: [Playlist], recents: [Song]?, folders: [PlaylistFolder]?) {
        self.favorites = favorites; self.playlists = playlists; self.recents = recents
        self.folders = folders?.isEmpty == false ? folders : nil
    }

    /// Como el sintetizado, pero una carpeta que no se puede leer se salta en vez de tumbar la biblioteca.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try c.decode([Song].self, forKey: .favorites)
        playlists = try c.decode([Playlist].self, forKey: .playlists)
        recents = try c.decodeIfPresent([Song].self, forKey: .recents)
        folders = (try? c.decodeIfPresent(LossyList<PlaylistFolder>.self, forKey: .folders))??.items
    }

    /// Lee library.json (o una copia) y deja las carpetas listas: sin huérfanas, ciclos ni más de 3 niveles, y
    /// sin carpeta en los álbumes ni en las playlists cuya carpeta no existe.
    static func decode(_ data: Data) throws -> LibraryFile {
        var file = try JSONDecoder().decode(LibraryFile.self, from: data)
        let folders = PlaylistFolders.normalize(file.folders ?? [])
        file.folders = folders.isEmpty ? nil : folders
        file.playlists = PlaylistFolders.clean(file.playlists, folders: folders)
        return file
    }

    /// Importar = unir, sin borrar nada: favoritas y recientes por id de canción, playlists y carpetas por id. Lo que
    /// ya estaba no cambia (tampoco de carpeta); lo nuevo llega en su carpeta si existe. Igual que `LibraryData.merge`.
    func merging(_ other: LibraryFile) -> LibraryFile {
        var favIDs = Set(favorites.map(\.id))
        var listIDs = Set(playlists.map(\.id))
        let mine = recents ?? []
        var recentIDs = Set(mine.map(\.id))
        let folders = PlaylistFolders.merge(self.folders ?? [], other.folders ?? [])
        return LibraryFile(
            favorites: favorites + other.favorites.filter { favIDs.insert($0.id).inserted },
            playlists: PlaylistFolders.clean(playlists + other.playlists.filter { listIDs.insert($0.id).inserted }, folders: folders),
            recents: Array((mine + (other.recents ?? []).filter { recentIDs.insert($0.id).inserted }).prefix(Self.maxRecents)),
            folders: folders)
    }
}
