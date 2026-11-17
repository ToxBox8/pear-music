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
    /// Sólo el `id` es obligatorio (un UUID). Lo demás se lee como en Android (`Playlist.fromJson`): sin nombre es
    /// «Playlist», las canciones que no se pueden leer se saltan y un `icon`, `tint`, `album`, `pinned` o `folder`
    /// de otro tipo es como si no estuviera, en vez de hacer fallar toda la biblioteca. Al declararlo en una
    /// extensión, Swift mantiene el inicializador por miembros.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let n = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        name = n.isEmpty ? "Playlist" : n
        songs = StoredSong.list(c, .songs) ?? []
        icon = (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? nil
        tint = (try? c.decodeIfPresent(Int.self, forKey: .tint)) ?? nil
        album = (try? c.decodeIfPresent(AlbumInfo.self, forKey: .album)) ?? nil
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? nil
        folder = (try? c.decodeIfPresent(String.self, forKey: .folder)) ?? nil
    }
}

/// Una canción de library.json leída como en Android (`Song.fromJson`): sólo el `id` es obligatorio; sin título o
/// artista quedan vacíos, y una carátula que no es una dirección es como si no estuviera.
struct StoredSong: Decodable {
    let song: Song
    private enum Keys: String, CodingKey { case id, title, artist, thumbnail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let id = try c.decode(String.self, forKey: .id)
        func text(_ k: Keys) -> String? { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
        let thumb = text(.thumbnail).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : URL(string: $0) }
        song = Song(id: id, title: text(.title) ?? "", artist: text(.artist) ?? "", thumbnail: thumb)
    }

    /// La lista de `key` sin las canciones que no se pueden leer; nil si la clave falta o no es una lista.
    static func list<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [Song]? {
        ((try? c.decodeIfPresent(LossyList<StoredSong>.self, forKey: key)) ?? nil)?.items.map(\.song)
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

/// Una carpeta para ordenar las playlists (`folders`) o los álbumes guardados (`albumFolders`, 3.0, T15). Puede estar
/// dentro de otra (`parent`, del mismo árbol), hasta 3 niveles. En el código se llama `PlaylistFolder` para no
/// confundirla con las «carpetas» de Tu música (`MusicOrder`).
struct PlaylistFolder: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var parent: String?
    /// Icono y color propios (T16, docs/LIBRARY_FORMAT.md): uno de los 24 `PlaylistIcons.names` y un índice de las
    /// paletas de playlist. Lo que no se conoce se conserva tal cual y se pinta como si no estuviera (`shownIcon`,
    /// `shownTint`), para que una versión futura con más iconos no los pierda al pasar por ésta.
    var icon: String?
    var tint: Int?

    init(id: String = UUID().uuidString, name: String, parent: String? = nil, icon: String? = nil, tint: Int? = nil) {
        self.id = id; self.name = name; self.parent = parent; self.icon = icon; self.tint = tint
    }

    /// `id` y `name` tienen que ser textos; lo demás, si no es del tipo esperado, se lee como si no estuviera: un
    /// `icon` vacío o que no es texto, o un `tint` que no es un número entero (`3.0` vale; `"3"` no).
    /// Igual que `PlaylistFolder.fromJson` en Android.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        parent = (try? c.decodeIfPresent(String.self, forKey: .parent)) ?? nil
        let i = (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? nil
        icon = i?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? i : nil
        // Como Android (un `Int` de 32 bits): fuera de ese rango, como si no estuviera.
        tint = WholeNumber.decode(c, .tint).flatMap { Int32(exactly: $0) }.map(Int.init)
    }

    /// El icono que se pinta: sólo si es uno de los 24. Sin él, la portada es el mosaico.
    var shownIcon: String? { icon.flatMap { PlaylistIcons.names.contains($0) ? $0 : nil } }
    /// El color que se pinta: sólo de 0 a 7 y con `shownIcon` (un `tint` suelto se conserva y no se pinta). Sin él,
    /// el icono va sobre el papel washi de la carpeta.
    var shownTint: Int? {
        guard shownIcon != nil, let tint, PlaylistIcons.paletteRange.contains(tint) else { return nil }
        return tint
    }
}

/// Los iconos que se pueden elegir para una playlist o una carpeta (los de `PlaylistStyle.icons`, que es esta lista)
/// y cuántas paletas hay (`playlistPalettes` de shared/design/tokens.json; el test de Linux lo comprueba). Mismo orden
/// que `SfIcons.playlistIcons` / `FolderLook` en Android.
enum PlaylistIcons {
    static let names = [
        "music.note.list", "heart.fill", "star.fill", "flame.fill", "bolt.fill", "moon.stars.fill",
        "sun.max.fill", "car.fill", "figure.run", "dumbbell.fill", "headphones", "guitars.fill",
        "pianokeys", "mic.fill", "party.popper.fill", "cup.and.saucer.fill", "book.fill", "leaf.fill",
        "airplane", "gamecontroller.fill", "sparkles", "cloud.rain.fill", "beach.umbrella.fill", "bed.double.fill"
    ]
    static let paletteRange = 0..<8
}

/// Un número entero de JSON, aunque venga con decimales a cero (`3.0`), como `wholeNumber` en Android. nil si falta,
/// no es un número o tiene decimales.
enum WholeNumber {
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int64? {
        if let n = (try? c.decodeIfPresent(Int64.self, forKey: key)) ?? nil { return n }
        guard let d = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil, d == d.rounded(),
              abs(d) < 9.0e18 else { return nil }
        return Int64(d)
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
    /// Un álbum guardado: su carpeta se busca en `albumFolders`, no en `folders` (T15).
    var isAlbumMember: Bool { get }
}

extension Playlist: FolderMember {
    var memberID: String { id.uuidString }
    var isAlbumMember: Bool { album != nil }
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
            // Espacios y saltos de línea, como `trim()` en Android: un id «F040\n» es la carpeta «F040» en las dos.
            let id = f.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            f.id = id
            let name = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
            f.name = name.isEmpty ? defaultName : name
            if let p = f.parent?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty { f.parent = p } else { f.parent = nil }
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

    /// Quita la carpeta a lo que no puede tenerla: una playlist busca la suya en `folders` y un álbum en
    /// `albumFolders` (T15); si no está en su árbol, queda sin carpeta aunque ese id exista en el otro.
    static func clean<M: FolderMember>(_ members: [M], folders: [PlaylistFolder], albumFolders: [PlaylistFolder] = []) -> [M] {
        let ids = Set(folders.map(\.id)), albumIDs = Set(albumFolders.map(\.id))
        return members.map { m in
            guard let f = m.folder else { return m }
            var m = m
            if !(m.isAlbumMember ? albumIDs : ids).contains(f) { m.folder = nil }
            return m
        }
    }

    /// El árbol de carpetas de álbumes listo para usar (T15): normalizado como `folders` y sin las que repiten el id
    /// de una carpeta de playlists (gana `folders`; lo que tenían dentro sube arriba del todo).
    static func albumTree(_ albumFolders: [PlaylistFolder], excluding folders: [PlaylistFolder]) -> [PlaylistFolder] {
        let taken = Set(folders.map(\.id))
        return normalize(normalize(albumFolders).filter { !taken.contains($0.id) })
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

    /// Se puede meter la carpeta `id` en una carpeta nueva de arriba del todo («Nueva carpeta» de «Mover a…»): con
    /// 3 niveles dentro ya no cabe en ninguna.
    static func canMoveIntoNew(_ id: String, folders: [PlaylistFolder]) -> Bool {
        1 + height(id, in: folders) <= maxDepth
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
        // Los mismos criterios que Playlists en el ⋯ de Tus álbumes (prompt 2-0); «recent» es el orden guardado.
        let byName: (Playlist, Playlist) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        switch sort {
        case "name": return albums.sorted(by: byName)
        case "nameDesc": return albums.sorted { byName($1, $0) }
        case "count": return albums.sorted { $0.songs.count > $1.songs.count }
        case "custom": break
        default: return albums
        }
        let byID = Dictionary(albums.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        let kept = order.filter { byID[$0] != nil && seen.insert($0).inserted }
        return kept.compactMap { byID[$0] } + albums.filter { !seen.contains($0.id.uuidString) }
    }

    /// Guarda el orden nuevo de «Tus álbumes» (`moved`, ids de álbum) sin perder las claves `folder:<id>` que
    /// hubiera en `albumOrder` (T15: la 3.0 no las pinta, pero las conserva en su sitio). Los ids de álbumes que ya no
    /// están se quitan, como hasta ahora.
    static func savingAlbums(_ moved: [String], into old: [String]) -> [String] {
        let set = Set(moved)
        let kept = old.filter { folderID($0) != nil || set.contains($0) }
        let known = Set(kept)
        return merge(kept + moved.filter { !known.contains($0) }, moved)
    }

    /// Las claves `folder:` de `albumOrder` que valen: las de carpetas de álbumes que existen, en su orden y sin
    /// repetir. Las de una carpeta que no existe se ignoran (no se borran).
    static func albumFolderKeys(_ order: [String], albumFolders: [PlaylistFolder]) -> [String] {
        let ids = Set(albumFolders.map(\.id))
        var seen = Set<String>()
        return order.filter { k in folderID(k).map { ids.contains($0) } == true && seen.insert(k).inserted }
    }

    /// «Fijados» (x.1.1): siempre en el orden propio; lo recién fijado va al final.
    static func pinned(_ pinned: [Playlist], order: [String]) -> [Playlist] {
        albums(pinned, sort: "custom", order: order)
    }
}

extension LibraryOrder {
    /// Prefijo de las carpetas en `playlistOrder` y en las claves de la cuadrícula. Sin él, una carpeta con el mismo
    /// id que una playlist (o llamada «downloads»/«favorites», en una copia hecha a mano) daría una clave repetida.
    static let folderPrefix = "folder:"
    static func key(folder id: String) -> String { folderPrefix + id }
    /// El id de la carpeta de una clave, o nil si la clave no es de una carpeta.
    static func folderID(_ key: String) -> String? {
        key.hasPrefix(folderPrefix) ? String(key.dropFirst(folderPrefix.count)) : nil
    }

    /// Las claves de un nivel de Tu música › Playlists (`folder` nil = arriba del todo), en el orden en que se ven:
    /// Descargadas y Favoritos (sólo arriba del todo y si van «en Playlists»), las carpetas (`folder:<id>`) y las
    /// playlists. Las
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
            let byID = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let kept = order.compactMap(folderID).filter { byID[$0] != nil && seen.insert($0).inserted }
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
        return Array(keys[..<at]) + sorted.map { key(folder: $0.id) } + Array(keys[at...])
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
    /// Al pasar de otro orden, el completo se monta siempre con Descargadas y Favoritos en su sitio de arriba (si no
    /// van «en Playlists», `keys` las salta): arrastrar dentro de una carpeta, donde no se ven, no las manda al final.
    static func reorder(level moved: [String], playlists: [Playlist], folders: [PlaylistFolder], sort: String,
                        order: [String]) -> [String] {
        var full = sort == "custom" ? order : materialize(playlists: playlists, folders: folders, sort: sort,
                                                          order: order, smartInPlaylists: true)
        let known = Set(full)
        full += moved.filter { !known.contains($0) }
        return merge(full, moved)
    }
}

// MARK: - Orden de «Tu música»

/// Orden de las carpetas de «Tu música» (`musicOrder`, separadas por comas). Igual que `Prefs.musicOrder` en Android.
enum MusicOrder {
    // «playlists» (2.9 de x.1.1): la carpeta con todas las playlists, arriba del todo.
    static let defaults = ["playlists", "downloads", "favorites", "albums", "songs", "artists", "recents", "stats"]
    /// Lo guardado más lo que falte, sin repetir ni desconocidos. Lo que falta entra en su sitio de fábrica (así
    /// «Playlists» sale arriba también a quien ya tenía un orden propio).
    static func decode(_ raw: String?) -> [String] {
        var seen = Set<String>()
        var out = (raw ?? "").split(separator: ",").map(String.init).filter { defaults.contains($0) && seen.insert($0).inserted }
        if out.isEmpty { return defaults }
        for (i, k) in defaults.enumerated() where !out.contains(k) { out.insert(k, at: min(i, out.count)) }
        return out
    }
}

extension MusicOrder {
    /// Sube (`delta` < 0) o baja un puesto el apartado `key` entre los que se ven (`visible`) y devuelve el orden
    /// completo (`all`): los que no se ven (Descargadas y Favoritos «en Playlists») conservan su sitio. Sin cambios si
    /// ya está en el borde o no se ve. Igual que `Prefs.movedMusic` en Android.
    static func moved(_ key: String, by delta: Int, visible: [String], all: [String]) -> [String] {
        guard let i = visible.firstIndex(of: key) else { return all }
        let j = i + (delta < 0 ? -1 : 1)
        guard delta != 0, visible.indices.contains(j) else { return all }
        var next = visible
        next.swapAt(i, j)
        let shown = Set(visible)
        var it = next.makeIterator()
        return all.map { shown.contains($0) ? (it.next() ?? $0) : $0 }
    }
}

// MARK: - Artistas seguidos (3.0, bloque 1)

/// Un artista que sigues desde su página. Sus lanzamientos salen en Inicio › Novedades. Mismo formato que
/// `FollowedArtist` en Android (docs/LIBRARY_FORMAT.md).
struct FollowedArtist: Identifiable, Codable, Hashable {
    var id: String { browseId }
    /// Id del canal de YouTube Music («UC…»).
    var browseId: String
    var name: String
    var thumbnail: URL?
    /// Desde cuándo lo sigues, en milisegundos desde 1970 (como `at` de las estadísticas).
    var since: Int64

    init(browseId: String, name: String, thumbnail: URL? = nil, since: Int64) {
        self.browseId = browseId; self.name = name; self.thumbnail = thumbnail; self.since = since
    }

    /// `browseId` y `name` tienen que ser textos; `thumbnail` o `since` de otro tipo se leen como si no estuvieran.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        browseId = try c.decode(String.self, forKey: .browseId)
        name = try c.decode(String.self, forKey: .name)
        thumbnail = (try? c.decodeIfPresent(URL.self, forKey: .thumbnail)) ?? nil
        since = (try? c.decodeIfPresent(Int64.self, forKey: .since)) ?? 0
    }
}

/// Reglas de los seguidos. Mismos nombres, casos y resultados que `FollowedArtists` en Android.
enum FollowedArtists {
    static let max = 500

    /// Sin `browseId` (o vacío) → fuera; repetido → se queda el primero (con el `since` más antiguo); nombre vacío →
    /// el `browseId`; como mucho 500 (los primeros: la lista va del último que sigues al primero).
    static func normalize(_ list: [FollowedArtist]) -> [FollowedArtist] {
        var out: [FollowedArtist] = []
        var index: [String: Int] = [:]
        for var a in list {
            let id = a.browseId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            if let i = index[id] {
                if a.since > 0 && (out[i].since == 0 || a.since < out[i].since) { out[i].since = a.since }
                continue
            }
            a.browseId = id
            let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
            a.name = name.isEmpty ? id : name
            if a.since < 0 { a.since = 0 }
            index[id] = out.count
            out.append(a)
        }
        return Array(out.prefix(max))
    }

    /// Importar = unir por `browseId`: se añaden los que no sigues (detrás); los tuyos se quedan como están, salvo
    /// `since`, que pasa a ser el más antiguo. Nunca se deja de seguir a nadie (los «dejar de seguir» no viajan).
    static func merge(_ local: [FollowedArtist], _ incoming: [FollowedArtist]) -> [FollowedArtist] {
        normalize(local + incoming)
    }

    /// Seguir: va el primero. nil si ya hay 500. Si ya lo seguías, no cambia nada.
    static func follow(_ artist: FollowedArtist, in list: [FollowedArtist]) -> [FollowedArtist]? {
        if list.contains(where: { $0.browseId == artist.browseId }) { return list }
        guard list.count < max, !artist.browseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return normalize([artist] + list)
    }

    static func unfollow(_ browseId: String, in list: [FollowedArtist]) -> [FollowedArtist] {
        list.filter { $0.browseId != browseId }
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
    /// Artistas seguidos (3.0). Como `folders`: sólo se escribe si sigues a alguno.
    var followedArtists: [FollowedArtist]?
    /// Carpetas de álbumes (3.0, T15): otro árbol, con la misma forma que `folders`. La 3.0 las lee, arregla, conserva
    /// y exporta, pero aún no tiene pantalla. Sólo se escribe si hay alguna.
    var albumFolders: [PlaylistFolder]?

    init(favorites: [Song], playlists: [Playlist], recents: [Song]?, folders: [PlaylistFolder]?,
         followedArtists: [FollowedArtist]? = nil, albumFolders: [PlaylistFolder]? = nil) {
        self.favorites = favorites; self.playlists = playlists; self.recents = recents
        self.folders = folders?.isEmpty == false ? folders : nil
        self.followedArtists = followedArtists?.isEmpty == false ? followedArtists : nil
        self.albumFolders = albumFolders?.isEmpty == false ? albumFolders : nil
    }

    /// Tolerante, como `LibraryData.fromJson` en Android: una canción, playlist o carpeta que no se puede leer se
    /// salta en vez de tumbar la biblioteca, y una lista que falta está vacía. Lo que tiene que ser es un objeto.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favorites = StoredSong.list(c, .favorites) ?? []
        playlists = ((try? c.decodeIfPresent(LossyList<Playlist>.self, forKey: .playlists)) ?? nil)?.items ?? []
        recents = StoredSong.list(c, .recents)
        folders = (try? c.decodeIfPresent(LossyList<PlaylistFolder>.self, forKey: .folders))??.items
        followedArtists = (try? c.decodeIfPresent(LossyList<FollowedArtist>.self, forKey: .followedArtists))??.items
        albumFolders = (try? c.decodeIfPresent(LossyList<PlaylistFolder>.self, forKey: .albumFolders))??.items
    }

    /// Cuántas canciones y playlists tiene: para saber si al leer se saltó algo (`LibraryDisk`).
    var itemCount: Int {
        favorites.count + (recents?.count ?? 0) + playlists.count + playlists.reduce(0) { $0 + $1.songs.count }
    }

    /// Lee library.json (o una copia) y deja los dos árboles de carpetas listos: sin huérfanas, ciclos ni más de 3
    /// niveles, sin carpetas de álbumes que repitan el id de una de playlists, y sin carpeta en las playlists y los
    /// álbumes cuya carpeta no está en su árbol.
    static func decode(_ data: Data) throws -> LibraryFile {
        var file = try JSONDecoder().decode(LibraryFile.self, from: data)
        let folders = PlaylistFolders.normalize(file.folders ?? [])
        file.folders = folders.isEmpty ? nil : folders
        let albumFolders = PlaylistFolders.albumTree(file.albumFolders ?? [], excluding: folders)
        file.albumFolders = albumFolders.isEmpty ? nil : albumFolders
        file.playlists = PlaylistFolders.clean(file.playlists, folders: folders, albumFolders: albumFolders)
        let followed = FollowedArtists.normalize(file.followedArtists ?? [])
        file.followedArtists = followed.isEmpty ? nil : followed
        return file
    }

    /// Importar = unir, sin borrar nada: favoritas y recientes por id de canción, playlists, álbumes y los dos árboles
    /// de carpetas por id. Lo que ya estaba no cambia (tampoco de carpeta, nombre, icono o color); lo nuevo llega en su
    /// carpeta si existe. Los seguidos se unen por
    /// `browseId` (`FollowedArtists.merge`). Igual que `LibraryData.merge`.
    func merging(_ other: LibraryFile) -> LibraryFile {
        var favIDs = Set(favorites.map(\.id))
        var listIDs = Set(playlists.map(\.id))
        let mine = recents ?? []
        var recentIDs = Set(mine.map(\.id))
        let folders = PlaylistFolders.merge(self.folders ?? [], other.folders ?? [])
        let albumFolders = PlaylistFolders.albumTree(PlaylistFolders.merge(self.albumFolders ?? [], other.albumFolders ?? []),
                                                     excluding: folders)
        return LibraryFile(
            favorites: favorites + other.favorites.filter { favIDs.insert($0.id).inserted },
            playlists: PlaylistFolders.clean(playlists + other.playlists.filter { listIDs.insert($0.id).inserted },
                                             folders: folders, albumFolders: albumFolders),
            recents: Array((mine + (other.recents ?? []).filter { recentIDs.insert($0.id).inserted }).prefix(Self.maxRecents)),
            folders: folders,
            followedArtists: FollowedArtists.merge(followedArtists ?? [], other.followedArtists ?? []),
            albumFolders: albumFolders)
    }
}

// MARK: - library.json en disco, sin perder nunca lo que había

/// Cómo se leyó library.json al arrancar.
enum LibraryRead {
    /// No hay archivo (o está vacío): primera vez.
    case missing
    /// Leído. `skipped`: canciones y playlists que había en el archivo y no se han podido leer.
    case ok(LibraryFile, skipped: Int)
    /// Hay archivo pero no se entiende (cortado, dañado, no es JSON).
    case unreadable
}

/// Lee y guarda library.json. Regla: **nunca se escribe encima de algo que no se ha leído entero**. Si el archivo no
/// se puede leer, se guarda una copia tal cual (`library-copia-<huella>.json`), `unreadableCopy` deja de ser nil
/// (la app avisa) y `save` no escribe hasta `startOver()`. Si se leyó saltándose algo, la copia se guarda igual y se
/// sigue. Sólo Foundation; igual que `LibraryDisk` y `Library` en Android.
final class LibraryDisk {
    let file: URL
    /// El nombre de la copia del archivo que no se pudo leer. Mientras no sea nil, no se guarda nada.
    private(set) var unreadableCopy: String?

    init(file: URL) { self.file = file }

    /// Lo que hay guardado, o nil si no hay nada o no se pudo leer (mira `unreadableCopy`).
    func load() -> LibraryFile? {
        switch Self.read(file) {
        case .missing:
            return nil
        case .ok(let lib, let skipped):
            // Se va a escribir sin lo que se saltó: antes, el archivo como estaba. Sin copia, no se escribe.
            if skipped > 0, Self.keepCopy(of: file) == nil { unreadableCopy = "" }
            return lib
        case .unreadable:
            unreadableCopy = Self.keepCopy(of: file) ?? ""
            return nil
        }
    }

    /// Guarda la biblioteca. No hace nada si el archivo que había no se pudo leer. true si se escribió.
    @discardableResult
    func save(_ library: LibraryFile) -> Bool {
        guard unreadableCopy == nil, let data = try? JSONEncoder().encode(library) else { return false }
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    /// «Empezar de cero»: la copia se queda y se vuelve a guardar con normalidad.
    func startOver() { unreadableCopy = nil }

    static func read(_ file: URL) -> LibraryRead {
        guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
        guard let data = try? Data(contentsOf: file) else { return .unreadable }
        if data.isEmpty { return .missing }
        guard let lib = try? LibraryFile.decode(data) else { return .unreadable }
        return .ok(lib, skipped: max(0, rawItemCount(data) - lib.itemCount))
    }

    /// Canciones y playlists que dice tener el archivo, sin mirar si se pueden leer.
    static func rawItemCount(_ data: Data) -> Int {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return 0 }
        func count(_ v: Any?) -> Int { (v as? [Any])?.count ?? 0 }
        let lists = o["playlists"] as? [Any] ?? []
        return count(o["favorites"]) + count(o["recents"]) + lists.count
            + lists.reduce(0) { $0 + count(($1 as? [String: Any])?["songs"]) }
    }

    /// Copia el archivo tal cual a su lado, con la huella del contenido en el nombre: abrir la app varias veces
    /// con el mismo archivo roto no amontona copias. Devuelve el nombre, o nil si no se pudo copiar.
    static func keepCopy(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let name = "library-copia-\(fingerprint(data)).json"
        let copy = file.deletingLastPathComponent().appendingPathComponent(name)
        if let there = try? Data(contentsOf: copy), there == data { return name }
        return (try? data.write(to: copy, options: .atomic)) != nil ? name : nil
    }

    /// FNV-1a de 64 bits en hexadecimal (16 letras). No es seguridad: sólo da el mismo nombre al mismo contenido.
    static func fingerprint(_ data: Data) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in data { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

// MARK: - Modo «Ordenar» (paso B de menús y gestos; DECISIONS 40)

/// Mover una portada en el modo «Ordenar», sin arrastrar («Antes» / «Después») o arrastrándola por su asa.
/// Sólo Foundation; igual que `GridOrder` en Android.
enum GridOrder {
    /// `id` un puesto antes (-1) o después (+1), si su vecina se puede apartar (`canSwap`: las carpetas se ordenan
    /// entre ellas y las playlists entre ellas). Si no, el orden queda igual.
    static func step<ID: Equatable>(_ id: ID, by delta: Int, in ids: [ID], canSwap: (ID, ID) -> Bool = { _, _ in true }) -> [ID] {
        guard let i = ids.firstIndex(of: id), delta == 1 || delta == -1, ids.indices.contains(i + delta),
              canSwap(id, ids[i + delta]) else { return ids }
        var out = ids
        out.swapAt(i, i + delta)
        return out
    }

    static func canStep<ID: Equatable>(_ id: ID, by delta: Int, in ids: [ID], canSwap: (ID, ID) -> Bool = { _, _ in true }) -> Bool {
        step(id, by: delta, in: ids, canSwap: canSwap) != ids
    }

    /// `id` pasa al puesto `index` y las de en medio se corren un sitio.
    static func moved<ID: Equatable>(_ id: ID, to index: Int, in ids: [ID]) -> [ID] {
        guard let from = ids.firstIndex(of: id), ids.indices.contains(index), from != index else { return ids }
        var out = ids
        out.insert(out.remove(at: from), at: index)
        return out
    }
}

/// El arrastre del modo «Ordenar»: una portada cogida por su asa que sigue al dedo. Los huecos (`slots`) son los
/// marcos de las celdas al empezar, por puesto: como todas miden lo mismo, no cambian aunque cambie el orden, y así
/// no hace falta esperar a que la pantalla se recoloque para saber qué hay bajo el dedo. Vale para la cuadrícula de
/// Playlists y para el carrusel de Fijados. Sólo Foundation; igual que `OrderDrag` en Android.
struct OrderDrag<ID: Hashable> {
    let id: ID
    /// Marco de cada puesto al empezar a arrastrar (sólo los que se ven).
    let slots: [Int: CGRect]
    /// Puesto en el que estaba al cogerla.
    let start: Int
    /// Lo que se ha movido el dedo desde que la cogió.
    var translation: CGSize = .zero
    /// Carpeta marcada para soltarla dentro: el dedo lleva `intoDwell` en el centro de su portada.
    var into: ID?
    /// La carpeta en cuyo centro está el dedo, aún sin el tiempo, y desde cuándo (`now` de `move`).
    private(set) var pendingInto: ID?
    private var pendingSince: TimeInterval = 0
    /// Ha cambiado de puesto alguna vez (aunque vuelva al suyo).
    var changed = false

    /// Para meterla en una carpeta (prompt 2-0, lo pidió Toxbox: que no la meta si sólo se quiere mover al lado): el
    /// dedo tiene que estar en el centro de la portada de la carpeta (sin este margen a cada lado, en fracción de su
    /// ancho) y quedarse ahí este tiempo. Pasar por encima o por el borde no la marca.
    static var intoInset: CGFloat { 0.2 }
    static var intoDwell: TimeInterval { 0.3 }

    /// ¿Está `p` en el centro de la portada de `slot`? La portada es el cuadrado de arriba de la celda.
    static func inCore(_ p: CGPoint, of slot: CGRect) -> Bool {
        let side = min(slot.width, slot.height), m = side * intoInset
        return CGRect(x: slot.minX + m, y: slot.minY + m, width: slot.width - 2 * m, height: side - 2 * m).contains(p)
    }

    /// El dedo se mueve a `location` (en el momento `now`, en segundos). Devuelve el orden nuevo (el mismo si no
    /// cambia nada) y apunta `into`.
    mutating func move(to location: CGPoint, translation: CGSize, order: [ID], now: TimeInterval = 0,
                       canDropInto: (ID, ID) -> Bool = { _, _ in false },
                       canSwap: (ID, ID) -> Bool = { _, _ in true }) -> [ID] {
        self.translation = translation
        guard let index = slots.first(where: { $0.value.contains(location) })?.key, order.indices.contains(index),
              order[index] != id else { into = nil; pendingInto = nil; return order }
        let target = order[index]
        if canDropInto(id, target) {
            guard let slot = slots[index], Self.inCore(location, of: slot) else { into = nil; pendingInto = nil; return order }
            if pendingInto != target { pendingInto = target; pendingSince = now }
            into = now - pendingSince >= Self.intoDwell ? target : nil
            return order
        }
        into = nil
        pendingInto = nil
        guard canSwap(id, target) else { return order }
        changed = true
        return GridOrder.moved(id, to: index, in: order)
    }

    /// Cuánto hay que desplazar la celda para que siga bajo el dedo: lo que se movió el dedo menos lo que ya se
    /// ha corrido ella al cambiar de puesto.
    func offset(in order: [ID]) -> CGSize {
        guard let now = order.firstIndex(of: id), let a = slots[start], let b = slots[now] else { return translation }
        return CGSize(width: translation.width - (b.minX - a.minX), height: translation.height - (b.minY - a.minY))
    }
}

/// El registro del modo «Ordenar» que leen los tests de interfaz (`OrderDebugLabel`, sólo con `-screenshotScenario`).
/// Está aquí, con los modelos, porque no es texto de la interfaz: no se traduce.
enum OrderLog {
    /// El arrastre: gestos pedidos y arrancados, por qué no, celdas medidas y portadas en el orden.
    static func lift(asked: Int, started: Int, fail: String, cells: Int, order: Int) -> String {
        "pedidos=\(asked) arrancados=\(started) fallo=\(fail) celdas=\(cells) orden=\(order) "
    }

    /// El temblor (prompt 2-0): cuántas portadas tiemblan y cuántas llevan el borde de «Reducir movimiento».
    static func wiggle(moving: Int, reduced: Bool) -> String {
        reduced ? "tiemblan=0 bordes=\(moving)" : "tiemblan=\(moving) bordes=0"
    }
}
