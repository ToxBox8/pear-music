import Foundation
import UIKit
import AVFoundation

private let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}
private func writeJSON<T: Encodable>(_ value: T, to url: URL) {
    if let data = try? JSONEncoder().encode(value) { try? data.write(to: url, options: .atomic) }
}

// `Playlist`, `AlbumInfo` y las carpetas (`PlaylistFolder`, `PlaylistFolders`) están en LibraryModel.swift.

// MARK: - Fotos de portada de las playlists (Documents/covers/<id>.jpg)
enum PlaylistArt {
    private static let dir: URL = {
        let d = docsDir.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static func url(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).jpg") }
    static func exists(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }
    static func image(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: url(id).path) }

    /// Guarda la foto reducida a 700 px (JPEG) para no llenar el almacenamiento.
    static func save(_ data: Data, for id: UUID) {
        guard let img = UIImage(data: data) else { return }
        let side: CGFloat = 700
        let scale = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        try? resized.jpegData(compressionQuality: 0.85)?.write(to: url(id), options: .atomic)
    }
    static func remove(_ id: UUID) { try? FileManager.default.removeItem(at: url(id)) }
}

// MARK: - Biblioteca
@MainActor
final class Library: ObservableObject {
    /// Lee y guarda library.json sin pisar nunca un archivo que no se pudo leer (`LibraryDisk`, en LibraryModel.swift).
    private let disk = LibraryDisk(file: docsDir.appendingPathComponent("library.json"))
    /// Si library.json no se pudo leer: el nombre de la copia que se ha guardado («» si ni eso). Mientras no sea
    /// nil, la app avisa y nada de lo que cambies se guarda (`startOver`).
    @Published private(set) var unreadableCopy: String?

    @Published var favorites: [Song] = [] { didSet { save() } }
    @Published var playlists: [Playlist] = [] { didSet { save() } }
    /// Carpetas de playlists (3.0, bloque 1). Siempre normalizadas: sin huérfanas, ciclos ni más de 3 niveles.
    @Published private(set) var folders: [PlaylistFolder] = [] { didSet { save() } }
    /// Carpetas de álbumes (3.0, T15). Sin pantalla todavía: se leen, se conservan y se exportan.
    @Published private(set) var albumFolders: [PlaylistFolder] = [] { didSet { save() } }
    /// Últimas canciones reproducidas (la más reciente primero).
    @Published private(set) var recents: [Song] = [] { didSet { save() } }
    /// Artistas seguidos (3.0, bloque 1), el último que sigues primero. Como mucho 500.
    @Published private(set) var followedArtists: [FollowedArtist] = [] { didSet { save() } }

    init() {
        // Capturas: datos de ejemplo en memoria, sin leer ni escribir library.json.
        if DemoCatalog.isActive { DemoCatalog.seed(self); return }
        if Demo.isActive { Demo.seed(self); return }
        if let s = disk.load() {
            favorites = s.favorites
            folders = s.folders ?? []
            albumFolders = s.albumFolders ?? []
            playlists = s.playlists
            recents = s.recents ?? []
            followedArtists = s.followedArtists ?? []
        }
        unreadableCopy = disk.unreadableCopy
        if unreadableCopy != nil { Logs.e("library", "library.json no se puede leer; copia guardada y escritura parada") }
    }
    private func save() {
        guard !Demo.isActive, !DemoCatalog.isActive else { return }
        disk.save(snapshot)
    }
    /// «Empezar de cero» del aviso: la copia del archivo ilegible se queda y lo que hay ahora en pantalla se guarda.
    func startOver() {
        disk.startOver()
        unreadableCopy = nil
        save()
    }

    private var snapshot: LibraryFile {
        LibraryFile(favorites: favorites, playlists: playlists, recents: recents, folders: folders,
                    followedArtists: followedArtists, albumFolders: albumFolders)
    }

    func markPlayed(_ s: Song) {
        var r = recents.filter { $0.id != s.id }
        r.insert(s, at: 0)
        recents = Array(r.prefix(40))
    }

    func isFavorite(_ s: Song) -> Bool { favorites.contains { $0.id == s.id } }
    func toggleFavorite(_ s: Song) {
        if let i = favorites.firstIndex(where: { $0.id == s.id }) { favorites.remove(at: i) }
        else { favorites.insert(s, at: 0) }
    }
    /// Crea una playlist vacía, dentro de `folder` si se da (3.0). nil si el nombre está vacío.
    @discardableResult
    func createPlaylist(_ name: String, in folder: String? = nil) -> UUID? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        var p = Playlist(name: n)
        if let folder, folders.contains(where: { $0.id == folder }) { p.folder = folder }
        playlists.append(p)
        return p.id
    }
    func deletePlaylists(at offsets: IndexSet) { playlists.remove(atOffsets: offsets) }
    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        PlaylistArt.remove(id)
    }
    func update(_ id: UUID, _ change: (inout Playlist) -> Void) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[i])
    }
    func setCover(_ data: Data?, for id: UUID) {
        if let data { PlaylistArt.save(data, for: id) } else { PlaylistArt.remove(id) }
        objectWillChange.send()
    }
    /// Las playlists del usuario, sin los álbumes guardados (ésos van en «Tus álbumes»).
    var userPlaylists: [Playlist] { playlists.filter { $0.album == nil } }
    /// «Tus álbumes»: los álbumes guardados o descargados desde su página, el último primero.
    var albums: [Playlist] { playlists.filter { $0.album != nil }.reversed() }
    func album(_ browseId: String) -> Playlist? { playlists.first { $0.album?.browseId == browseId } }

    /// Crea una playlist ya rellena (importación). Devuelve su id.
    @discardableResult
    func importPlaylist(name: String, songs: [Song], cover: Data? = nil, album: AlbumInfo? = nil) -> UUID {
        var p = Playlist(name: name, songs: songs)
        p.album = album
        p.tint = Int.random(in: 0..<PlaylistStyle.palettes.count)
        if let cover { PlaylistArt.save(cover, for: p.id) }
        playlists.append(p)
        return p.id
    }
    /// Una playlist compartida por QR (0.6 de x.1.1): con su icono y color, y un nombre que no choque con otra
    /// («Atardecer (2)»). Igual que `importShared` en Android.
    func importShared(name: String, songs: [Song], icon: String?, tint: Int?) -> UUID {
        let taken = Set(userPlaylists.map(\.name))
        let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Playlist" : name.trimmingCharacters(in: .whitespaces)
        var unique = base, i = 2
        while taken.contains(unique) { unique = "\(base) (\(i))"; i += 1 }
        var p = Playlist(name: unique, songs: songs, icon: icon)
        p.tint = tint ?? Int.random(in: 0..<PlaylistStyle.palettes.count)
        playlists.append(p)
        return p.id
    }

    // MARK: Copia de la biblioteca (library.json, docs/LIBRARY_FORMAT.md)
    /// La biblioteca en el formato común con Android.
    /// Desde 2.0 lleva también las **portadas propias** (`covers`, JPEG en base64) y el **orden manual** de las
    /// playlists (`playlistOrder`, `playlistSort`), que antes se perdían. `covers: false` para la nube si no caben.
    func exportData(covers: Bool = true) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let base = (try? encoder.encode(snapshot)) ?? Data()
        guard var dict = (try? JSONSerialization.jsonObject(with: base)) as? [String: Any] else { return base }
        if covers {
            var map: [String: String] = [:]
            for p in playlists where PlaylistArt.exists(p.id) {
                if let data = try? Data(contentsOf: PlaylistArt.url(p.id)) { map[p.id.uuidString] = data.base64EncodedString() }
            }
            if !map.isEmpty { dict["covers"] = map }
        }
        let d = UserDefaults.standard
        let order = LibraryOrder.decode(d.string(forKey: "playlistOrder") ?? "")
        if !order.isEmpty { dict["playlistOrder"] = order }
        dict["playlistSort"] = d.string(forKey: "playlistSort") ?? "recent"
        // Orden de «Tus álbumes» (2.9 de x.1.1), como el de las playlists.
        let albumOrder = LibraryOrder.decode(d.string(forKey: "albumOrder") ?? "")
        if !albumOrder.isEmpty { dict["albumOrder"] = albumOrder }
        dict["albumSort"] = d.string(forKey: "albumSort") ?? "recent"
        // Orden de «Fijados» (x.1.1).
        let pinnedOrder = LibraryOrder.decode(d.string(forKey: "pinnedOrder") ?? "")
        if !pinnedOrder.isEmpty { dict["pinnedOrder"] = pinnedOrder }
        // Orden de las carpetas de «Tu música» (Cierre 1.0), sólo si no es el de fábrica.
        let music = MusicOrder.decode(d.string(forKey: "musicOrder"))
        if music != MusicOrder.defaults { dict["musicOrder"] = music }
        return (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])) ?? base
    }

    /// Une una copia sin borrar nada: favoritas y recientes por id de canción, playlists por id.
    /// Devuelve cuántas favoritas y playlists se han añadido.
    @discardableResult
    func importData(_ data: Data) throws -> (favorites: Int, playlists: Int) {
        let merged = snapshot.merging(try LibraryFile.decode(data))
        let added = (merged.favorites.count - favorites.count, merged.playlists.count - playlists.count)
        favorites = merged.favorites
        // Carpetas antes que playlists: así ninguna playlist apunta a una carpeta que aún no está.
        folders = merged.folders ?? []
        albumFolders = merged.albumFolders ?? []
        playlists = merged.playlists
        recents = merged.recents ?? []
        followedArtists = merged.followedArtists ?? []
        // Portadas donde no haya una propia, y el orden unido: el tuyo se respeta y lo nuevo va detrás; si este
        // iPhone no tenía orden propio, se adopta el de la copia. Igual que Library.importJson en Android.
        if let extra = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let covers = extra["covers"] as? [String: String] {
                for p in playlists where !PlaylistArt.exists(p.id) {
                    if let b64 = covers[p.id.uuidString], let jpeg = Data(base64Encoded: b64) {
                        try? FileManager.default.createDirectory(at: PlaylistArt.url(p.id).deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? jpeg.write(to: PlaylistArt.url(p.id), options: .atomic)
                    }
                }
                objectWillChange.send()
            }
            if let incoming = extra["playlistOrder"] as? [String] {
                let d = UserDefaults.standard
                let local = LibraryOrder.decode(d.string(forKey: "playlistOrder") ?? "")
                let merged = local.isEmpty ? incoming : local + incoming.filter { !local.contains($0) }
                d.set(merged.joined(separator: "\n"), forKey: "playlistOrder")
                if local.isEmpty, let sort = extra["playlistSort"] as? String { d.set(sort, forKey: "playlistSort") }
            }
            if let incoming = extra["albumOrder"] as? [String] {
                let d = UserDefaults.standard
                let local = LibraryOrder.decode(d.string(forKey: "albumOrder") ?? "")
                let merged = local.isEmpty ? incoming : local + incoming.filter { !local.contains($0) }
                d.set(merged.joined(separator: "\n"), forKey: "albumOrder")
                if local.isEmpty, let sort = extra["albumSort"] as? String { d.set(sort, forKey: "albumSort") }
            }
            if let incoming = extra["pinnedOrder"] as? [String] {
                let d = UserDefaults.standard
                let local = LibraryOrder.decode(d.string(forKey: "pinnedOrder") ?? "")
                d.set((local + incoming.filter { !local.contains($0) }).joined(separator: "\n"), forKey: "pinnedOrder")
            }
            if let music = extra["musicOrder"] as? [String] {
                let d = UserDefaults.standard
                if MusicOrder.decode(d.string(forKey: "musicOrder")) == MusicOrder.defaults {
                    d.set(MusicOrder.decode(music.joined(separator: ",")).joined(separator: ","), forKey: "musicOrder")
                }
            }
        }
        return added
    }

    // MARK: Artistas seguidos (3.0, bloque 1; reglas en FollowedArtists)
    func isFollowing(_ browseId: String) -> Bool { followedArtists.contains { $0.browseId == browseId } }

    /// Sigue a un artista (va el primero). false si ya sigues a 500.
    @discardableResult
    func follow(browseId: String, name: String, thumbnail: URL?, since: Int64? = nil) -> Bool {
        let a = FollowedArtist(browseId: browseId, name: name, thumbnail: thumbnail,
                               since: since ?? Int64(Date().timeIntervalSince1970 * 1000))
        guard let next = FollowedArtists.follow(a, in: followedArtists) else { return false }
        if next != followedArtists { followedArtists = next }
        return true
    }

    func unfollow(_ browseId: String) { followedArtists = FollowedArtists.unfollow(browseId, in: followedArtists) }

    // MARK: Carpetas de playlists (3.0, bloque 1; reglas en PlaylistFolders)
    /// Crea una carpeta dentro de `parent` (nil = arriba del todo). nil si el nombre está vacío o no cabe (3 niveles).
    @discardableResult
    func createFolder(_ name: String, in parent: String? = nil) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, parent == nil || folders.contains(where: { $0.id == parent }),
              PlaylistFolders.canCreate(in: parent, folders: folders) else { return nil }
        let f = PlaylistFolder(name: n, parent: parent)
        folders.append(f)
        return f.id
    }
    func renameFolder(_ id: String, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = n
    }
    /// Icono y color de una carpeta (prompt 2-0; reglas en docs/LIBRARY_FORMAT.md › «Icono y color de carpeta»). Sin
    /// icono vuelve el mosaico; el color se guarda igual, aunque sin icono no se pinte.
    func setFolderLook(_ id: String, icon: String?, tint: Int?) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].icon = icon.flatMap { PlaylistIcons.names.contains($0) ? $0 : nil }
        folders[i].tint = tint.flatMap { PlaylistIcons.paletteRange.contains($0) ? $0 : nil }
    }
    /// Mueve una carpeta (con todo lo suyo) dentro de `target` (nil = arriba del todo). false si no cabe.
    @discardableResult
    func moveFolder(_ id: String, to target: String?) -> Bool {
        guard let i = folders.firstIndex(where: { $0.id == id }),
              target == nil || folders.contains(where: { $0.id == target }),
              PlaylistFolders.canMove(id, to: target, folders: folders) else { return false }
        folders[i].parent = target
        return true
    }
    /// Mete una playlist en una carpeta (nil = la saca de todas). Los álbumes no van en carpetas.
    func movePlaylist(_ id: UUID, to folder: String?) {
        guard folder == nil || folders.contains(where: { $0.id == folder }) else { return }
        update(id) { if $0.album == nil { $0.folder = folder } }
    }
    /// Borra la carpeta; lo que tenía dentro sube un nivel. Nunca borra playlists.
    func deleteFolder(_ id: String) {
        let (nextFolders, nextPlaylists) = PlaylistFolders.delete(id, folders: folders, members: playlists)
        playlists = nextPlaylists
        folders = nextFolders
    }
    /// Las playlists de una carpeta y de sus subcarpetas («Reproducir» y «Aleatorio» de la carpeta).
    func playlists(inFolder id: String) -> [Playlist] {
        PlaylistFolders.members(of: id, folders: folders, in: userPlaylists)
    }

    func add(_ s: Song, to playlist: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }),
              !playlists[i].songs.contains(where: { $0.id == s.id }) else { return }
        playlists[i].songs.append(s)
    }
    func remove(at offsets: IndexSet, from playlist: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].songs.remove(atOffsets: offsets)
    }
    /// Quita una canción concreta (las listas filtradas no tienen los mismos índices que la playlist).
    func remove(songID: String, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].songs.removeAll { $0.id == songID }
    }
}

// MARK: - Descargas
@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    @Published private(set) var songs: [Song] = []
    /// Ids de las canciones descargadas: consulta instantánea en las listas (sin tocar el disco por fila).
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var inProgress: Set<String> = []
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var failed: Set<String> = []
    @Published var lastError: String?

    private let dir = docsDir.appendingPathComponent("Downloads", isDirectory: true)
    private var indexFile: URL { dir.appendingPathComponent("index.json") }

    private init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Entradas del índice cuyo archivo ya no está se descartan para no marcarlas como descargadas.
        // Modo demo (DemoCatalog): las canciones del patrocinador salen como descargadas, sin archivos ni tocar el índice.
        if DemoCatalog.isActive {
            songs = DemoCatalog.songs
            downloadedIDs = Set(songs.map(\.id))
            return
        }
        let indexed = readJSON([Song].self, from: indexFile) ?? []
        songs = indexed.filter { localURL(for: $0.id) != nil }
        downloadedIDs = Set(songs.map(\.id))
        if songs.count != indexed.count { writeJSON(songs, to: indexFile) }
    }

    private func path(_ id: String, ext: String = "m4a") -> URL { dir.appendingPathComponent("\(id).\(ext)") }

    /// .m4a normalmente; .aac si no se pudo convertir.
    func localURL(for id: String) -> URL? {
        ["m4a", "aac"].map { path(id, ext: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    func isDownloaded(_ s: Song) -> Bool { downloadedIDs.contains(s.id) }

    func download(_ song: Song) async {
        guard !inProgress.contains(song.id) else { return }
        // Archivo en disco que no llegó al índice (p. ej. la app se cerró al terminar): se registra sin bajarlo otra vez.
        if localURL(for: song.id) != nil {
            if !downloadedIDs.contains(song.id) { register(song) }
            return
        }
        inProgress.insert(song.id)
        failed.remove(song.id)
        progress[song.id] = 0
        defer { inProgress.remove(song.id); progress[song.id] = nil }
        do {
            let tmp = try await YTClient.downloadAudio(song: song) { [weak self] p in self?.progress[song.id] = p }
            defer { try? FileManager.default.removeItem(at: tmp) }
            let m4a = path(song.id)
            try? FileManager.default.removeItem(at: m4a)
            if tmp.pathExtension == "m4a" {
                try FileManager.default.copyItem(at: tmp, to: m4a)
            } else if await Self.remux(tmp, to: m4a) == false {
                // Si AVFoundation no lo empaqueta en .m4a, el .aac también se reproduce.
                try? FileManager.default.removeItem(at: path(song.id, ext: "aac"))
                try FileManager.default.copyItem(at: tmp, to: path(song.id, ext: "aac"))
            }
            register(song)
        } catch {
            // Cancelada desde «Detener»: no es un fallo y no se marca para reintentar.
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            failed.insert(song.id)
            lastError = L("No se pudo descargar «{0}»: {1}", song.title, error.localizedDescription)
        }
    }

    private func register(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        songs.insert(song, at: 0)
        downloadedIDs.insert(song.id)
        writeJSON(songs, to: indexFile)
    }

    /// «Descargar todo» en curso, por lista (id de la playlist o "favorites"). Antes era uno solo
    /// para toda la app: una playlist que compartía canciones con la que se descargaba también
    /// decía «Descargando… · Detener», y «Detener» paraba la otra.
    private var bulkTasks: [String: Task<Void, Never>] = [:]
    private var bulkLists: [String: [Song]] = [:]
    @Published private(set) var bulk: [String: Set<String>] = [:]
    /// Listas con «Descargar todo» en pausa: lo bajado se queda y «Reanudar» sigue con lo que falta.
    @Published private(set) var paused: Set<String> = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var activeObserver: NSObjectProtocol?

    /// Lanza «Descargar todo» para la lista `owner` (sólo sus canciones); se detiene con `cancelBulk(owner)`.
    func startBulk(_ list: [Song], owner: String) {
        paused.remove(owner)
        bulkTasks[owner]?.cancel()
        bulkLists[owner] = list
        bulk[owner] = Set(list.map(\.id))
        keepRunningInBackground()
        bulkTasks[owner] = Task { [weak self] in
            await self?.downloadAll(list)
            guard let self, !Task.isCancelled else { return }
            // Si iOS suspendió la app a medias, quedan pendientes y se reanudan al volver (`resumeBulk`).
            if list.allSatisfy({ self.isDownloaded($0) || self.failed.contains($0.id) }) { self.finishBulk(owner) }
        }
    }

    /// Para sin olvidar la lista: la pantalla ofrece «Reanudar».
    func pauseBulk(_ owner: String) {
        cancelBulk(owner)
        paused.insert(owner)
    }

    /// Para y olvida: lo ya descargado se queda.
    func cancelBulk(_ owner: String) {
        bulkTasks[owner]?.cancel()
        paused.remove(owner)
        finishBulk(owner)
    }

    private func finishBulk(_ owner: String) {
        bulkTasks[owner] = nil
        bulkLists[owner] = nil
        bulk[owner] = nil
        if bulk.isEmpty, backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    /// Pide a iOS unos minutos más al salir de la app, y reanuda lo pendiente al volver.
    private func keepRunningInBackground() {
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Descargas") { [weak self] in
                guard let self else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resumeBulk() }
            }
        }
    }

    private func resumeBulk() {
        for (owner, list) in bulkLists where list.contains(where: { !isDownloaded($0) && !inProgress.contains($0.id) }) {
            failed.subtract(list.map(\.id))
            startBulk(list, owner: owner)
        }
    }

    /// Descarga las que falten de una lista, de dos en dos para no saturar la conexión.
    func downloadAll(_ list: [Song]) async {
        let pending = list.filter { !isDownloaded($0) && !inProgress.contains($0.id) }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            while next < min(2, pending.count) {
                let s = pending[next]
                next += 1
                group.addTask { await self.download(s) }
            }
            while await group.next() != nil {
                if !Task.isCancelled && next < pending.count {
                    let s = pending[next]
                    next += 1
                    group.addTask { await self.download(s) }
                }
            }
        }
    }

    /// AAC suelto (ADTS) → contenedor .m4a sin recodificar: duración exacta y búsqueda precisa.
    private static func remux(_ src: URL, to dest: URL) async -> Bool {
        let asset = AVURLAsset(url: src)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return false }
        export.outputURL = dest
        export.outputFileType = .m4a
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        return export.status == .completed
    }

    /// Tamaño total de las canciones descargadas.
    func totalBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func removeAll() {
        for s in songs { for ext in ["m4a", "aac"] { try? FileManager.default.removeItem(at: path(s.id, ext: ext)) } }
        songs = []
        downloadedIDs = []
        failed = []
        writeJSON(songs, to: indexFile)
    }

    func remove(_ song: Song) {
        for ext in ["m4a", "aac"] { try? FileManager.default.removeItem(at: path(song.id, ext: ext)) }
        songs.removeAll { $0.id == song.id }
        downloadedIDs.remove(song.id)
        failed.remove(song.id)
        writeJSON(songs, to: indexFile)
    }
}

// `MusicOrder` (orden de los apartados de «Tu música») está en LibraryModel.swift.
