import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Biblioteca
/// Un solo diseño (la biblioteca 1.1), igual en iOS y Android.
struct LibraryView: View {
    var body: some View { LibraryV11View() }
}

struct ArtistGroup: Identifiable {
    var id: String { name }
    let name: String
    let songs: [Song]
}

extension Library {
    /// Canciones únicas guardadas en favoritos y playlists (+ descargas).
    func allSongs(including extra: [Song] = []) -> [Song] {
        var seen = Set<String>()
        return (favorites + playlists.flatMap(\.songs) + extra).filter { seen.insert($0.id).inserted }
    }
}

/// Artista principal: «Clarent y Quevedo» → «Clarent» (también limpia el formato antiguo «Artista · Álbum»).
func primaryArtist(_ s: String) -> String {
    let name = s.replacingOccurrences(of: #"\s*(,| y | & | x | feat\.? | ft\.? | · ).*$"#, with: "",
                                      options: [.regularExpression, .caseInsensitive])
    return name.isEmpty ? L("Desconocido") : name
}

struct RowHighlightStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            .animation(.uiEaseOut(0.15), value: configuration.isPressed)
    }
}

// MARK: - Buscador local (Playlists, Artistas, Álbumes y demás «Ver todas»)

/// Filtro de listas de la biblioteca: ignora mayúsculas y acentos («beyonce» encuentra «Beyoncé»).
/// Mismas reglas que `LocalSearch` en Android.
enum LocalSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
    /// Los elementos cuyo texto contiene todas las palabras de la búsqueda, en cualquier orden.
    static func filter<T>(_ items: [T], _ query: String, text: (T) -> String) -> [T] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let t = fold(text(item))
            return words.allSatisfy { t.contains($0) }
        }
    }
}

/// «Sin resultados» del buscador local, con el texto buscado.
struct NoMatchesView: View {
    let query: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
            Text(L("Nada coincide con «{0}»", query.trimmingCharacters(in: .whitespaces))).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center).padding(.horizontal, 32)
    }
}

/// Playlists (2.9 de x.1.1): la carpeta de «Tu música», en cuadrícula como «Tus álbumes». Es el único sitio de las
/// playlists: el carrusel de Biblioteca lo ocupa ahora Fijados. Con Descargadas y Favoritos «en Playlists» (Ajustes ›
/// Biblioteca), van aquí con su portada. Manteniendo pulsada una portada sale su menú y, si se arrastra, se cambia el
/// orden (pasa a «A mano») o se mete en una carpeta.
/// Carpetas (3.0, bloque 1; DECISIONS 35): con `folderID` es la pantalla de una carpeta, con Reproducir y Aleatorio
/// de todo lo de dentro. En cada nivel van primero las carpetas y después las playlists. Igual que `PlaylistsScreen`
/// en Android.
struct PlaylistsListView: View {
    var folderID: String? = nil
    @EnvironmentObject var library: Library
    @EnvironmentObject var downloads: DownloadStore
    @AppStorage("playlistSort") private var sort = "recent"
    @AppStorage("playlistOrder") private var orderRaw = ""
    @AppStorage("smartPlacement") private var placement = "playlists"
    @AppStorage("playlistDragHintDone") private var hintDone = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var editing = false
    @State private var naming: FolderNaming?
    @State private var nameText = ""
    @State private var moving: MoveItem?
    @State private var deleting: PlaylistFolder?
    @State private var opened: Entry?

    /// Una casilla de la cuadrícula: una playlist, una lista inteligente o una carpeta. `key` es su clave en
    /// `playlistOrder` (el id de la playlist o de la carpeta, o "downloads" / "favorites").
    struct Entry: Identifiable {
        let key: String
        var id: String { key }
        let title: String
        let subtitle: String
        var playlist: Playlist? = nil
        var smart: SmartList? = nil
        var folder: PlaylistFolder? = nil
    }

    private var folder: PlaylistFolder? { folderID.flatMap { id in library.folders.first { $0.id == id } } }
    private var smartHere: Bool { folderID == nil && placement != "music" }

    private var keys: [String] {
        LibraryOrder.level(folderID, playlists: library.userPlaylists, folders: library.folders, sort: sort,
                           order: LibraryOrder.decode(orderRaw), smartInPlaylists: smartHere)
    }

    private func entry(_ key: String, path: Bool) -> Entry? {
        switch key {
        case LibraryOrder.downloads:
            return Entry(key: key, title: SmartList.downloads.title, subtitle: songCount(downloads.songs.count), smart: .downloads)
        case LibraryOrder.favorites:
            return Entry(key: key, title: SmartList.favorites.title, subtitle: songCount(library.favorites.count), smart: .favorites)
        default:
            if let id = LibraryOrder.folderID(key) {
                guard let f = library.folders.first(where: { $0.id == id }) else { return nil }
                return Entry(key: key, title: f.name, subtitle: path ? place(f.parent) ?? folderContents(f) : folderContents(f), folder: f)
            }
            guard let p = library.userPlaylists.first(where: { $0.id.uuidString == key }) else { return nil }
            return Entry(key: key, title: p.name, subtitle: path ? place(p.folder) ?? songCount(p.songs.count) : songCount(p.songs.count), playlist: p)
        }
    }

    /// «En Gimnasio › Pierna» (buscando: dónde está cada cosa). nil si está arriba del todo.
    private func place(_ parent: String?) -> String? {
        let names = PlaylistFolders.path(parent, in: library.folders).map(\.name)
        return names.isEmpty ? nil : L("En {0}", names.joined(separator: " › "))
    }

    /// «3 playlists · 1 carpeta»: lo que hay justo dentro.
    private func folderContents(_ f: PlaylistFolder) -> String {
        FolderText.contents(playlists: library.userPlaylists.filter { $0.folder == f.id }.count,
                            folders: library.folders.filter { $0.parent == f.id }.count)
    }

    /// Buscando: todo lo que hay en este nivel y por debajo, con su ruta.
    private func searchEntries() -> [Entry] {
        let inside: Set<String>? = folderID.map { PlaylistFolders.subtree($0, in: library.folders) }
        let folders = library.folders.filter { f in f.id != folderID && (inside.map { s in f.parent.map(s.contains) ?? false } ?? true) }
        let lists = library.userPlaylists.filter { p in inside.map { s in p.folder.map(s.contains) ?? false } ?? true }
        let smart = smartHere ? [LibraryOrder.downloads, LibraryOrder.favorites] : []
        let all = (smart + folders.map { LibraryOrder.key(folder: $0.id) } + lists.map(\.id.uuidString)).compactMap { entry($0, path: true) }
        return LocalSearch.filter(all, query) { $0.title }
    }

    var body: some View {
        let all = keys.compactMap { entry($0, path: false) }
        let shown = query.isEmpty ? all : searchEntries()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let folder { FolderHeader(folder: folder) }
                if !shown.isEmpty {
                    if !hintDone || !query.isEmpty { ReorderHint(enabled: query.isEmpty, folders: !library.folders.isEmpty) }
                    ReorderGrid(items: shown, enabled: query.isEmpty, onMoved: { moved in
                        orderRaw = LibraryOrder.reorder(level: moved, playlists: library.userPlaylists, folders: library.folders,
                                                        sort: sort, order: LibraryOrder.decode(orderRaw)).joined(separator: "\n")
                        sort = "custom"
                    }, canDropInto: canDropInto, canSwap: canSwap, onDropInto: dropInto, onDragEnd: { hintDone = true },
                    menu: { AnyView(menu($0)) },
                    destination: { e in
                        if let p = e.playlist { PlaylistV11View(playlistID: p.id) }
                        else if let f = e.folder { PlaylistsListView(folderID: f.id) }
                        else if let k = e.smart { SmartListV11View(kind: k) }
                    }) { e in cell(e) }
                }
            }
        }
        .overlay {
            if all.isEmpty && query.isEmpty {
                if folderID == nil { Text(L("Todavía no hay playlists")).foregroundStyle(.secondary) }
                else { FolderEmptyView() }
            } else if shown.isEmpty { NoMatchesView(query: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: folder.map { L("Buscar en {0}", $0.name) } ?? L("Buscar en playlists"))
        .scrollDismissesKeyboard(.interactively)
        .themed()
        .navigationTitle(folder?.name ?? L("Playlists"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu { toolbarMenu } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel(L("Más opciones"))
            }
        }
        .sheet(isPresented: $editing) { ReorderPlaylistsView(folderID: folderID) }
        .sheet(item: $moving) { MoveToFolderSheet(item: $0) }
        .navigationDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let p = opened?.playlist { PlaylistV11View(playlistID: p.id) }
            else if let f = opened?.folder { PlaylistsListView(folderID: f.id) }
        }
        .alert(naming?.title ?? "", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField(L("Nombre"), text: $nameText)
            Button(naming?.confirm ?? L("Crear")) { applyName() }
            Button(L("Cancelar"), role: .cancel) { naming = nil }
        }
        .alert(L("¿Eliminar la carpeta «{0}»?", deleting?.name ?? ""), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L("Eliminar carpeta"), role: .destructive) {
                if let f = deleting {
                    library.deleteFolder(f.id)
                    if f.id == folderID { dismiss() }
                }
                deleting = nil
            }
            Button(L("Cancelar"), role: .cancel) { deleting = nil }
        } message: {
            Text(L("Lo que tiene dentro pasa a «{0}». No se borra ninguna playlist ni canción.", destinationName(deleting)))
        }
        // La carpeta abierta ya no existe (borrada desde otro sitio o al importar): se vuelve atrás.
        .onChange(of: library.folders.map(\.id)) { ids in if let folderID, !ids.contains(folderID) { dismiss() } }
        .task { if Demo.current?.showMove == true, folderID != nil, let p = library.userPlaylists.first(where: { $0.folder == folderID }) { moving = .playlist(p.id) } }
        .miniPlayer()
    }

    // MARK: Celdas y menús

    @ViewBuilder private func cell(_ e: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let f = e.folder { FolderCover(folder: f) }
                else if let p = e.playlist { PlaylistCover(playlist: p, size: nil).shadow(color: .black.opacity(0.14), radius: 12, y: 6) }
                else if let k = e.smart {
                    SmartCover(kind: k, size: nil)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                }
            }
            Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(e.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(e.folder != nil ? L("Carpeta {0}", e.title) : e.title)
        .accessibilityValue(e.subtitle)
    }

    /// Soltar sin mover abre el menú (como en Fijados; lo decidió Toxbox).
    @ViewBuilder private func menu(_ e: Entry) -> some View {
        if let p = e.playlist {
            Button { opened = e } label: { Label(L("Abrir"), systemImage: "arrow.up.right.square") }
            Button { moving = .playlist(p.id) } label: { Label(L("Mover a…"), systemImage: "folder") }
            if let current = p.folder, let f = library.folders.first(where: { $0.id == current }) {
                Button { library.movePlaylist(p.id, to: f.parent) } label: {
                    Label(L("Sacar de «{0}»", f.name), systemImage: "arrow.up.forward.square")
                }
            }
            Divider()
            Button { library.update(p.id) { $0.pinned = $0.pinned == true ? nil : true } } label: {
                p.pinned == true ? Label(L("Soltar de arriba"), systemImage: "pin.slash") : Label(L("Fijar arriba"), systemImage: "pin")
            }
        } else if let f = e.folder {
            Button { opened = e } label: { Label(L("Abrir"), systemImage: "arrow.up.right.square") }
            Button { nameText = f.name; naming = .rename(f) } label: { Label(L("Renombrar"), systemImage: "pencil") }
            Button { moving = .folder(f.id) } label: { Label(L("Mover carpeta a…"), systemImage: "folder") }
            Divider()
            Button(role: .destructive) { deleting = f } label: { Label(L("Eliminar carpeta"), systemImage: "trash") }
        }
    }

    @ViewBuilder private var toolbarMenu: some View {
        if let folder {
            Button { nameText = ""; naming = .newPlaylist(folder.id) } label: { Label(L("Nueva playlist aquí"), systemImage: "plus") }
            if PlaylistFolders.canCreate(in: folder.id, folders: library.folders) {
                Button { nameText = ""; naming = .newFolder(folder.id) } label: { Label(L("Nueva carpeta aquí"), systemImage: "folder.badge.plus") }
            }
            Divider()
            Button { nameText = folder.name; naming = .rename(folder) } label: { Label(L("Renombrar"), systemImage: "pencil") }
            Button { moving = .folder(folder.id) } label: { Label(L("Mover carpeta a…"), systemImage: "folder") }
            Button { editing = true } label: { Label(L("Editar orden"), systemImage: "arrow.up.arrow.down") }
            Divider()
            Button(role: .destructive) { deleting = folder } label: { Label(L("Eliminar carpeta"), systemImage: "trash") }
        } else {
            Button { nameText = ""; naming = .newFolder(nil) } label: { Label(L("Nueva carpeta"), systemImage: "folder.badge.plus") }
            Button { editing = true } label: { Label(L("Editar orden"), systemImage: "arrow.up.arrow.down") }
        }
    }

    // MARK: Arrastrar dentro de una carpeta

    private func isFolder(_ key: String) -> Bool { LibraryOrder.folderID(key) != nil }

    private func canDropInto(_ dragged: String, _ target: String) -> Bool {
        guard isFolder(target) else { return false }
        if isFolder(dragged) { return false } // las carpetas se meten con «Mover carpeta a…»; arrastrando se ordenan
        return library.userPlaylists.contains { $0.id.uuidString == dragged }
    }

    /// Las carpetas se ordenan entre ellas y las playlists entre ellas (las carpetas van siempre delante).
    private func canSwap(_ dragged: String, _ target: String) -> Bool { isFolder(dragged) == isFolder(target) }

    private func dropInto(_ dragged: String, _ target: String) {
        guard let id = UUID(uuidString: dragged), let folder = LibraryOrder.folderID(target) else { return }
        withAnimation(.uiEaseOut(0.25)) { library.movePlaylist(id, to: folder) }
    }

    // MARK: Nombres

    private func applyName() {
        let n = nameText
        switch naming {
        case .newFolder(let parent): library.createFolder(n, in: parent)
        case .newPlaylist(let folder): library.createPlaylist(n, in: folder)
        case .rename(let f): library.renameFolder(f.id, to: n)
        case nil: break
        }
        naming = nil
    }

    private func destinationName(_ f: PlaylistFolder?) -> String {
        f?.parent.flatMap { p in library.folders.first { $0.id == p }?.name } ?? L("Playlists")
    }
}

/// «Tus álbumes»: los álbumes guardados o descargados desde su página, en cuadrícula y con buscador. Se reordenan
/// arrastrando, como Playlists (2.9 de x.1.1).
struct AlbumsListView: View {
    @EnvironmentObject var library: Library
    @AppStorage("albumSort") private var albumSort = "recent"
    @AppStorage("albumOrder") private var albumOrder = ""
    @State private var query = ""

    var body: some View {
        let albums = LibraryOrder.albums(library.albums, sort: albumSort, order: LibraryOrder.decode(albumOrder))
        let shown = LocalSearch.filter(albums, query) { "\($0.name) \($0.album?.artist ?? "")" }
        ScrollView {
            if !shown.isEmpty {
                ReorderHint(enabled: query.isEmpty)
                ReorderGrid(items: shown, enabled: query.isEmpty, onMoved: { moved in
                    albumOrder = moved.map(\.uuidString).joined(separator: "\n")
                    albumSort = "custom"
                }, destination: { p in PlaylistV11View(playlistID: p.id) }) { p in
                    GridCover(playlist: p, subtitle: p.album?.line ?? songCount(p.songs.count))
                }
            }
        }
        .overlay {
            if albums.isEmpty { AlbumsEmptyView() }
            else if shown.isEmpty { NoMatchesView(query: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Buscar en tus álbumes"))
        .scrollDismissesKeyboard(.interactively)
        .themed()
        .navigationTitle(L("Tus álbumes"))
        .miniPlayer()
    }
}

/// Portada grande con nombre y una línea, para las cuadrículas de Playlists y Tus álbumes.
private struct GridCover: View {
    let playlist: Playlist
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaylistCover(playlist: playlist, size: nil)
                .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
            Text(playlist.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}

/// Cómo se reordena la cuadrícula; buscando no se puede (se ordenaría sólo lo encontrado). En Playlists sale sólo
/// hasta el primer arrastre (`playlistDragHintDone`, lo pidió Toxbox); en Tus álbumes, siempre.
struct ReorderHint: View {
    let enabled: Bool
    /// Con carpetas, también dice que se puede meter una portada en una.
    var folders = false
    var body: some View {
        Text(!enabled ? L("Borra la búsqueda para cambiar el orden.")
             : folders ? L("Mantén pulsada una portada y arrástrala para cambiar el orden o meterla en una carpeta.")
             : L("Mantén pulsada una portada y arrástrala para cambiar el orden."))
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 4)
    }
}

/// La celda sobre la que se está soltando algo para meterlo dentro (una carpeta). La lee `FolderCover`.
private struct DropIntoKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var dropInto: Bool {
        get { self[DropIntoKey.self] }
        set { self[DropIntoKey.self] = newValue }
    }
}

/// Cuadrícula de dos columnas que se reordena manteniendo pulsado y arrastrando (2.9 de x.1.1). El sistema levanta
/// la portada; al pasar por encima de otra, se apartan, y al soltar llega el orden nuevo a `onMoved`. Con
/// `enabled = false` (buscando) sólo se tocan. Las celdas que son contenedores (carpetas, 3.0) no se apartan: si lo
/// que se arrastra cabe dentro, se marcan y al soltar llega a `onDropInto`. Igual que `ReorderGrid` en Android.
struct ReorderGrid<Item: Identifiable, Destination: View, Cell: View>: View {
    let items: [Item]
    let enabled: Bool
    let onMoved: ([Item.ID]) -> Void
    /// ¿Se puede soltar `arrastrado` dentro de `celda`? (carpetas; por defecto, nada es contenedor).
    var canDropInto: (Item.ID, Item.ID) -> Bool = { _, _ in false }
    /// ¿Se aparta `celda` al pasar `arrastrado` por encima? (las carpetas van siempre delante de las playlists).
    var canSwap: (Item.ID, Item.ID) -> Bool = { _, _ in true }
    var onDropInto: (Item.ID, Item.ID) -> Void = { _, _ in }
    /// Al acabar un arrastre, se haya movido o metido algo.
    var onDragEnd: () -> Void = {}
    /// Menú al mantener pulsado sin mover (si no se da, nada). Va en la misma vista que el arrastre, como en Fijados:
    /// así el sistema enseña el menú al soltar sin mover y arrastra si se mueve.
    var menu: ((Item) -> AnyView)? = nil
    @ViewBuilder let destination: (Item) -> Destination
    @ViewBuilder let cell: (Item) -> Cell
    @State private var order: [Item.ID] = []
    @State private var dragging: Item.ID?
    @State private var into: Item.ID?
    private let columns = [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)]

    var body: some View {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let shown = order.compactMap { byID[$0] }
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(shown.count == items.count ? shown : items) { p in
                NavigationLink { destination(p) } label: { cell(p) }
                    .buttonStyle(TactileButtonStyle())
                    .environment(\.dropInto, into == p.id)
                    .opacity(dragging == p.id ? 0.35 : 1)
                    .contextMenu { if let menu { menu(p) } }
                    .modifier(Lift(enabled: enabled, id: p.id, dragging: $dragging))
                    .onDrop(of: [.text], delegate: CellDrop(target: p.id, order: $order, dragging: $dragging, into: $into,
                                                            canDropInto: canDropInto, canSwap: canSwap,
                                                            dropInto: { d, t in onDropInto(d, t); onDragEnd() }, finish: finish))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Soltar entre celdas también termina el arrastre.
        .onDrop(of: [.text], delegate: GridDrop(dragging: $dragging, finish: finish))
        .onAppear { order = items.map(\.id) }
        .onChange(of: items.map(\.id)) { ids in if dragging == nil { order = ids } }
    }

    private func finish() {
        guard dragging != nil else { return }
        dragging = nil
        into = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onMoved(order)
        onDragEnd()
    }
}

/// Mantener pulsado levanta la celda (sólo si se puede reordenar; buscando, no).
struct Lift<ID: Hashable>: ViewModifier {
    let enabled: Bool
    let id: ID
    @Binding var dragging: ID?
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                dragging = id
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                return NSItemProvider(object: "\(id)" as NSString)
            }
        } else {
            content
        }
    }
}

struct CellDrop<ID: Hashable>: DropDelegate {
    let target: ID
    @Binding var order: [ID]
    @Binding var dragging: ID?
    /// Celda marcada para soltar dentro (carpetas). Sin carpetas, siempre nil.
    var into: Binding<ID?> = .constant(nil)
    var canDropInto: (ID, ID) -> Bool = { _, _ in false }
    var canSwap: (ID, ID) -> Bool = { _, _ in true }
    var dropInto: (ID, ID) -> Void = { _, _ in }
    let finish: () -> Void

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target else { return }
        if canDropInto(d, target) {
            into.wrappedValue = target
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        guard canSwap(d, target), let from = order.firstIndex(of: d), let to = order.firstIndex(of: target) else { return }
        withAnimation(.uiEaseOut(0.22)) { order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
    }
    func dropExited(info: DropInfo) { if into.wrappedValue == target { into.wrappedValue = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        if let d = dragging, into.wrappedValue == target {
            dragging = nil
            into.wrappedValue = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dropInto(d, target)
        } else {
            finish()
        }
        return true
    }
}

struct GridDrop<ID: Hashable>: DropDelegate {
    @Binding var dragging: ID?
    let finish: () -> Void
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { finish(); return true }
}

/// Sin álbumes todavía: qué es esto y cómo se llena.
private struct AlbumsEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack").font(.system(size: 40, weight: .regular)).foregroundStyle(.secondary)
            Text(L("Todavía no tienes álbumes")).font(.headline)
            Text(L("Busca un álbum o entra en un artista y pulsa «Añadir a Tus álbumes» o «Descargar todo»."))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }
}

struct ArtistsView: View {
    let artists: [ArtistGroup]
    @EnvironmentObject var library: Library
    @State private var query = ""
    /// «Todos» o «Siguiendo» (3.0, bloque 1). Sin canciones guardadas pero con seguidos, empieza en «Siguiendo».
    @State private var following: Bool? = Demo.current?.artistsFollowing == true ? true : nil
    /// Orden A-Z / Z-A con el botón de arriba a la derecha (Fase 3.1); mismo ajuste que Android.
    @AppStorage("artistsSort") private var sort = "az"

    private var showFollowing: Bool { following ?? (artists.isEmpty && !library.followedArtists.isEmpty) }

    var body: some View {
        let followed = library.followedArtists
        let ordered = artists.sorted { LocalSearch.fold($0.name) < LocalSearch.fold($1.name) }
        let shown = LocalSearch.filter(sort == "za" ? ordered.reversed() : ordered, query) { $0.name }
        let orderedFollowed = followed.sorted { LocalSearch.fold($0.name) < LocalSearch.fold($1.name) }
        let shownFollowed = LocalSearch.filter(sort == "za" ? orderedFollowed.reversed() : orderedFollowed, query) { $0.name }
        List {
            if !followed.isEmpty {
                HStack(spacing: 8) {
                    ChoiceChip(title: L("Todos"), on: !showFollowing) { withAnimation(.uiEaseOut(0.22)) { following = false } }
                    ChoiceChip(title: L("Siguiendo"), count: followed.count, on: showFollowing) {
                        withAnimation(.uiEaseOut(0.22)) { following = true }
                    }
                    Spacer(minLength: 0)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }
            if showFollowing {
                ForEach(shownFollowed) { a in
                    // Se abre su página directamente por su browseId, sin buscarlo por nombre.
                    NavigationLink {
                        ArtistView(artist: RemoteArtist(id: a.browseId, name: a.name, subtitle: "", thumbnail: a.thumbnail))
                    } label: {
                        artistRow(name: a.name, thumbnail: a.thumbnail, detail: followedSince(a))
                    }
                    .glassRow()
                }
            } else {
                ForEach(shown) { a in
                    // Al tocar se abre su perfil de YouTube Music (discografía completa); sin red o sin encontrarlo, sus canciones.
                    NavigationLink {
                        ArtistProfileLoader(name: a.name, songs: a.songs)
                    } label: {
                        artistRow(name: a.name, thumbnail: a.songs.first?.thumb(160), detail: songCount(a.songs.count))
                    }
                    .glassRow()
                }
            }
        }
        .overlay {
            if showFollowing {
                if shownFollowed.isEmpty && !followed.isEmpty { NoMatchesView(query: query) }
            } else if artists.isEmpty {
                Text(L("Guarda canciones para ver sus artistas")).foregroundStyle(.secondary)
            } else if shown.isEmpty { NoMatchesView(query: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Buscar artistas"))
        .scrollDismissesKeyboard(.interactively)
        .themed()
        .navigationTitle(L("Artistas"))
        .toolbar {
            if !artists.isEmpty || !followed.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { sort = sort == "za" ? "az" : "za" } label: {
                        Label(sort == "za" ? "Z-A" : "A-Z", systemImage: "textformat").labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel(sort == "za" ? L("Ordenar de la A a la Z") : L("Ordenar de la Z a la A"))
                }
            }
        }
        .miniPlayer()
    }

    private func artistRow(name: String, thumbnail: URL?, detail: String) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: thumbnail)
                .frame(width: 46, height: 46)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    /// «Desde el 14 nov 2026» (o, si la copia no lo traía, «Siguiendo»).
    private func followedSince(_ a: FollowedArtist) -> String {
        guard a.since > 0 else { return L("Siguiendo") }
        let date = Date(timeIntervalSince1970: TimeInterval(a.since) / 1000)
        return L("Desde el {0}", date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: I18n.current == "va" ? "ca" : I18n.current))))
    }
}

/// Perfil (YouTube Music) del artista con ese nombre; si no se encuentra o no hay red, sus canciones guardadas.
/// Desde «Tu música › Artistas» y desde la cabecera de un álbum (Fase 3.1), como `openArtistProfile` en Android.
struct ArtistProfileLoader: View {
    let name: String
    let songs: [Song]
    @State private var artist: RemoteArtist?
    @State private var done = false

    var body: some View {
        Group {
            if let artist { ArtistView(artist: artist) }
            else if done { SongListV11View(title: name, songs: songs) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).themed() }
        }
        .task {
            if !done { artist = await YTClient.findArtist(name); done = true }
        }
    }
}

// MARK: - Editor: nombre, foto, icono y color
struct PlaylistEditor: View {
    let playlistID: UUID
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var moving = false

    private var playlist: Playlist? { library.playlists.first { $0.id == playlistID } }

    var body: some View {
        NavigationStack {
            if let p = playlist {
                Form {
                    Section {
                        HStack { Spacer(); PlaylistCover(playlist: p, size: 150); Spacer() }
                            .listRowBackground(Color.clear)
                    }
                    Section(L("Nombre")) {
                        TextField(L("Nombre"), text: $name)
                    }
                    // Carpeta (3.0, bloque 1): dónde está y «Mover a…». Los álbumes no van en carpetas.
                    if p.album == nil {
                        Section(L("Carpeta")) {
                            Button { moving = true } label: {
                                HStack {
                                    Text(PlaylistFolders.path(p.folder, in: library.folders).map(\.name).joined(separator: " › ").nilIfEmpty ?? L("Ninguna"))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                            }
                            .accessibilityHint(L("Mover a otra carpeta"))
                        }
                    }
                    Section {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label(PlaylistArt.exists(p.id) ? "Cambiar foto" : "Elegir foto", systemImage: "photo.on.rectangle")
                        }
                        if PlaylistArt.exists(p.id) {
                            Button(role: .destructive) { library.setCover(nil, for: p.id) } label: {
                                Label(L("Quitar foto"), systemImage: "trash")
                            }
                        }
                    } header: { Text(L("Foto")) } footer: {
                        Text(L("Si hay foto se muestra en lugar del icono."))
                    }
                    Section(L("Icono")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                            Button { library.update(p.id) { $0.icon = nil } } label: {
                                Image(systemName: "square.grid.2x2")
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(.tint).opacity(p.icon == nil ? 0.25 : 0))
                            }
                            .accessibilityLabel(L("Sin icono"))
                            .accessibilityAddTraits(p.icon == nil ? .isSelected : [])
                            ForEach(PlaylistStyle.icons, id: \.self) { icon in
                                Button { library.update(p.id) { $0.icon = icon } } label: {
                                    Image(systemName: icon)
                                        .frame(width: 42, height: 42)
                                        .background(Circle().fill(.tint).opacity(p.icon == icon ? 0.25 : 0))
                                }
                                .accessibilityAddTraits(p.icon == icon ? .isSelected : [])
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.title3)
                    }
                    Section(L("Color")) {
                        HStack(spacing: 10) {
                            ForEach(PlaylistStyle.palettes.indices, id: \.self) { i in
                                Button { library.update(p.id) { $0.tint = i } } label: {
                                    Circle().fill(PlaylistStyle.gradient(i))
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().strokeBorder(.primary, lineWidth: (p.tint ?? 1) == i ? 2.5 : 0))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .sheet(isPresented: $moving) { MoveToFolderSheet(item: .playlist(p.id)) }
                .navigationTitle(L("Editar playlist"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button(L("Listo")) {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { library.update(p.id) { $0.name = n } }
                        dismiss()
                    }
                }
                .onAppear { name = p.name }
                .onChange(of: photo) { item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            library.setCover(data, for: playlistID)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Importar desde Apple Music
/// Copia de la biblioteca como archivo (library.json) para el selector de archivos del sistema.
struct LibraryBackup: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ImportView: View {
    @Environment(\.accentFill) private var accentFill
    @Environment(\.onAccent) private var onAccent
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var localLists: [AMPlaylist]?
    @State private var status: Status = .idle
    @State private var errorText: String?
    @State private var notice: String?
    @State private var importingBackup = false
    @State private var exportingBackup = false
    @State private var backup = LibraryBackup(data: Data())
    /// Qué archivo se está eligiendo (un solo selector por vista: con varios, SwiftUI sólo presenta uno).
    @State private var fileMode: FileMode = .library
    @State private var job: ImportJob?
    @State private var pending = ImportJob.pending()
    @State private var simpLists: [SimpPlaylist] = []

    enum FileMode { case library, csv, simpMusic }

    enum Status: Equatable {
        case idle
        case reading
        case matching(name: String, done: Int, total: Int)
        /// Resumen de una importación con emparejado: lo bueno, lo dudoso y lo que no se encontró.
        case review
        /// Playlists de una copia de SimpMusic para elegir cuáles traer.
        case simpPick
        case finished(title: String, detail: String)
    }

    private var busy: Bool {
        switch status {
        case .reading, .matching: return true
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch status {
                case .review:
                    if let job {
                        ImportReviewSections(job: job, onCancel: { job.discard(); self.job = nil; status = .idle }) { songs, left in
                            Task { await create(job.playlist, songs: songs, left: left) }
                        }
                    }
                case .simpPick:
                    SimpMusicPickSections(lists: simpLists, onCancel: { status = .idle }) { chosen in
                        Task { await importSimp(chosen) }
                    }
                case .matching(let name, let done, let total):
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Importando «{0}»", name)).font(.headline)
                            ProgressView(value: Double(done), total: Double(max(total, 1)))
                            Text(L("Buscando en YouTube Music… {0} de {1}", done, total))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    } footer: { Text(L("Puedes cerrar la app: al volver, la importación sigue donde se quedó.")) }
                case .finished(let title, let detail):
                    Section {
                        Label(title, systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                        Text(detail).font(.subheadline)
                        Button(L("Listo")) { dismiss() }
                    }
                case .reading:
                    Section { HStack { ProgressView(); Text(L("Leyendo la playlist…")).padding(.leading, 8) } }
                case .idle:
                    EmptyView()
                }

                if status != .review && status != .simpPick {
                if let p = pending, status == .idle {
                    Section {
                        LabeledContent("«\(p.playlist.name)»", value: "\(p.results.count) de \(p.playlist.tracks.count)")
                        Button(L("Continuar")) { match(p) }
                        Button(L("Descartar"), role: .destructive) { p.discard(); pending = nil }
                    } header: { Text(L("Sin terminar")) } footer: { Text(L("Se cortó a medias; sigue donde se quedó.")) }
                }

                Section {
                    // String y no LocalizedStringKey: como Markdown, la URL salía en azul como un enlace.
                    TextField(String(L("Enlace de Spotify o Apple Music")), text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button { link = UIPasteboard.general.string ?? link } label: { Label(L("Pegar"), systemImage: "doc.on.clipboard") }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button { Task { await importLink() } } label: { Label(L("Importar"), systemImage: "square.and.arrow.down") }
                            .buttonStyle(.borderedProminent).tint(accentFill).foregroundStyle(onAccent)
                            .disabled(link.isEmpty)
                    }
                } header: { Text(L("Desde un enlace")) } footer: {
                    Text(L("Apple Music o Spotify: abre la playlist → Compartir → Copiar enlace. Tiene que ser pública. De Spotify llegan hasta unas 100 canciones; para listas más largas, usa el CSV de Exportify."))
                }
                .disabled(busy)

                Section {
                    Button { fileMode = .csv; importingBackup = true } label: { Label(L("CSV de Exportify (Spotify)"), systemImage: "doc.text") }
                    Button { fileMode = .simpMusic; importingBackup = true } label: { Label(L("Copia de SimpMusic (.backup)"), systemImage: "clock.arrow.circlepath") }
                } header: { Text(L("Desde un archivo")) } footer: {
                    Text(L("Spotify: exporta la playlist en exportify.app (gratis, entra con tu cuenta de Spotify) y elige el .csv; trae todas las canciones y su ISRC, que empareja mejor. SimpMusic: Ajustes › Copia de seguridad, y elige el archivo .backup; sus canciones ya son de YouTube Music, así que llegan exactas."))
                }
                .disabled(busy)

                Section {
                    if let lists = localLists {
                        if lists.isEmpty {
                            Text(L("No hay playlists en la biblioteca de este iPhone.")).foregroundStyle(.secondary)
                        }
                        ForEach(lists) { pl in
                            Button { Task { await importPlaylist(pl) } } label: {
                                HStack(spacing: 12) {
                                    GradientIcon(systemName: "music.note.list", palette: 0, size: 38)
                                    VStack(alignment: .leading) {
                                        Text(pl.name).foregroundStyle(.primary)
                                        Text(songCount(pl.tracks.count)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Button { Task { await loadLocal() } } label: { Label(L("Ver mis playlists"), systemImage: "music.note.house") }
                    }
                } header: { Text(L("Desde la app Música de este iPhone")) } footer: {
                    Text(L("Lee las playlists de tu biblioteca (necesita «Sincronizar biblioteca» activado en Ajustes → Música)."))
                }
                .disabled(busy)

                // Lo mismo que Android: la biblioteca entera en un archivo, para pasarla de un móvil a otro.
                Section {
                    Button { fileMode = .library; importingBackup = true } label: { Label(L("Importar copia"), systemImage: "square.and.arrow.down") }
                    Button {
                        backup = LibraryBackup(data: library.exportData())
                        exportingBackup = true
                    } label: { Label(L("Exportar copia"), systemImage: "square.and.arrow.up") }
                } header: { Text(L("Copia de la biblioteca")) } footer: {
                    Text(L("Archivo library.json de Jiyu Pulse (también el de Android). Se añade lo que no tengas, sin borrar nada."))
                }
                .disabled(busy)

                if let notice {
                    Section { Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                if let errorText {
                    Section { Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
                }
            }
            .fileImporter(isPresented: $importingBackup, allowedContentTypes: fileMode == .library ? [.json] : fileMode == .csv ? [.commaSeparatedText, .plainText] : [.zip, .data]) { result in
                switch fileMode {
                case .library: importBackup(result)
                case .csv: importCSV(result)
                case .simpMusic: importSimpFile(result)
                }
            }
            .background {
                // Un selector por vista: con los dos en la misma, SwiftUI sólo presenta uno.
                Color.clear.fileExporter(isPresented: $exportingBackup, document: backup, contentType: .json,
                                         defaultFilename: "pear-music-library.json") { result in
                    errorText = nil; notice = nil
                    switch result {
                    case .success: notice = L("Biblioteca exportada.")
                    case .failure(let e) where (e as NSError).code == NSUserCancelledError: break
                    case .failure: errorText = L("No se pudo exportar la biblioteca.")
                    }
                }
            }
            .navigationTitle(L("Importar playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(L("Cerrar")) { dismiss() }.disabled(busy) }
            .interactiveDismissDisabled(busy)
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        errorText = nil; notice = nil
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let added = try? library.importData(data) else {
            errorText = L("No se pudo leer ese archivo de biblioteca.")
            return
        }
        notice = L("Importado: {0} favoritas y {1} playlists nuevas.", added.favorites, added.playlists)
    }

    private func importLink() async {
        errorText = nil
        status = .reading
        do {
            let pl = SpotifyImporter.isSpotify(link) ? try await SpotifyImporter.fetchPublic(link) : try await AppleMusicImporter.fetchPublic(link)
            match(ImportJob(playlist: pl))
        } catch {
            status = .idle
            errorText = error.localizedDescription
        }
    }

    /// Empareja (o sigue emparejando) y enseña el resumen para revisar.
    private func match(_ j: ImportJob) {
        job = j
        pending = nil
        errorText = nil
        let pl = j.playlist
        status = .matching(name: pl.name, done: j.results.count, total: pl.tracks.count)
        Task {
            await ImportMatcher.matchAll(j) { done in status = .matching(name: pl.name, done: done, total: pl.tracks.count) }
            status = .review
        }
    }

    private func create(_ pl: AMPlaylist, songs: [Song], left: [AMTrack] = []) async {
        var cover: Data?
        if let url = pl.artwork { cover = try? await URLSession.shared.data(from: url).0 }
        let id = library.importPlaylist(name: pl.name, songs: songs, cover: cover)
        // Las que no se añaden quedan en la playlist para volver a buscarlas («Sin añadir»).
        PendingImports.shared.set(id.uuidString, left)
        job?.discard()
        job = nil
        status = .finished(title: L("«{0}» importada", pl.name),
                           detail: L("{0} de {1} canciones. Ya está en tu Biblioteca; no se ha descargado nada (usa «Descargar todo» si la quieres sin conexión).", songs.count, pl.tracks.count)
                               + (left.isEmpty ? "" : L(" Las {0} que faltan quedan en la playlist, en «Sin añadir», para buscarlas otra vez.", left.count)))
    }

    private func importCSV(_ result: Result<URL, Error>) {
        errorText = nil; notice = nil
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            match(ImportJob(playlist: try ExportifyCSV.parse(fileName: url.lastPathComponent, text: text)))
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func importSimpFile(_ result: Result<URL, Error>) {
        errorText = nil; notice = nil
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let lists = try SimpMusicBackup.read(url)
            guard !lists.isEmpty else { errorText = L("La copia no tiene playlists."); return }
            simpLists = lists
            status = .simpPick
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func importSimp(_ chosen: [SimpPlaylist]) async {
        for l in chosen {
            var cover: Data?
            if let url = l.cover { cover = try? await URLSession.shared.data(from: url).0 }
            library.importPlaylist(name: l.name, songs: l.songs, cover: cover)
        }
        status = .finished(title: chosen.count == 1 ? L("Playlist importada") : L("{0} playlists importadas", chosen.count),
                           detail: L("{0} canciones, iguales que en SimpMusic. No se ha descargado nada.", chosen.reduce(0) { $0 + $1.songs.count }))
    }

    private func loadLocal() async {
        errorText = nil
        guard await AppleMusicImporter.requestLibraryAccess() else {
            errorText = AppleMusicImporter.Failure.denied.localizedDescription
            return
        }
        localLists = AppleMusicImporter.libraryPlaylists()
    }

    private func importPlaylist(_ pl: AMPlaylist) async {
        match(ImportJob(playlist: pl))
    }

}

// MARK: - Revisar una importación
/// Cuántas encajan, cuántas hay que revisar y cuántas no se encontraron. Lo dudoso no se elige solo: se toca y
/// se escoge entre los candidatos (o «Ninguna»). Igual que `ImportReview` en Android.
struct ImportReviewSections: View {
    @ObservedObject var job: ImportJob
    let onCancel: () -> Void
    let onCreate: ([Song], [AMTrack]) -> Void
    @State private var picks: [Int: Song?] = [:]
    @State private var open: Int?

    private var matches: [TrackMatch] {
        job.playlist.tracks.indices.map { job.results[$0] ?? TrackMatch(track: job.playlist.tracks[$0], choice: nil, confidence: .none, candidates: []) }
    }

    private func chosen(_ i: Int) -> Song? { picks.keys.contains(i) ? picks[i]! : matches[i].choice }

    var body: some View {
        let all = matches
        let good = all.filter { $0.confidence == .good }.count
        let review = all.indices.filter { all[$0].confidence == .review }
        let none = all.indices.filter { all[$0].confidence == .none }
        var seen = Set<String>()
        let songs = all.indices.compactMap(chosen).filter { seen.insert($0.id).inserted }

        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("{0} bien · {1} para revisar · {2} no encontradas", good, review.count, none.count)).font(.headline)
                Text(review.isEmpty && none.isEmpty ? L("Todas encajan con su versión en YouTube Music.")
                     : L("Toca las dudosas para elegir la versión correcta. Las que dejes sin elegir no se añaden."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: { Text("«\(job.playlist.name)»") }

        rows(L("Para revisar"), review, all)
        rows(L("No encontradas"), none, all)

        Section {
            Button { onCreate(songs, all.indices.filter { chosen($0) == nil }.map { all[$0].track }) } label: { Text(L("Crear playlist con {0}", songCount(songs.count))).frame(maxWidth: .infinity) }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(songs.isEmpty)
            Button(role: .cancel, action: onCancel) { Text(L("Cancelar")).frame(maxWidth: .infinity) }
                .buttonStyle(PillButtonStyle(prominent: false))
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder private func rows(_ title: String, _ indices: [Int], _ all: [TrackMatch]) -> some View {
        if !indices.isEmpty {
            Section(title) {
                ForEach(indices, id: \.self) { i in
                    let m = all[i]
                    let pick = chosen(i)
                    Button {
                        if !m.candidates.isEmpty { withAnimation(.uiEaseOut(0.2)) { open = open == i ? nil : i } }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.track.title).foregroundStyle(.primary)
                            Text(Self.line(m.track)).font(.footnote).foregroundStyle(.secondary)
                            Text(pick.map { "→ \($0.title) · \($0.artist)" } ?? (m.candidates.isEmpty ? L("Sin resultados") : L("Sin elegir")))
                                .font(.footnote).foregroundStyle(pick == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                        }
                    }
                    if open == i {
                        ForEach(Array(m.candidates.enumerated()), id: \.offset) { j, c in
                            Button { picks[i] = c.song; open = nil } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.song.title).foregroundStyle(.primary)
                                        Text(c.song.artist + (j == 0 ? L(" · más probable") : "")).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if pick?.id == c.song.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                            .padding(.leading, 12)
                        }
                        Button { picks[i] = .some(nil); open = nil } label: {
                            HStack {
                                Text(L("Ninguna (no añadir)")).foregroundStyle(.secondary)
                                Spacer()
                                if pick == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .padding(.leading, 12)
                    }
                }
            }
        }
    }

    static func line(_ t: AMTrack) -> String {
        let d = Int(t.duration)
        return [t.artist.isEmpty ? nil : t.artist, d > 0 ? String(format: "%d:%02d", d / 60, d % 60) : nil].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Elegir qué playlists de SimpMusic traer (todas marcadas al principio).
struct SimpMusicPickSections: View {
    let lists: [SimpPlaylist]
    let onCancel: () -> Void
    let onImport: ([SimpPlaylist]) -> Void
    @State private var selected: Set<UUID> = []
    @State private var ready = false

    var body: some View {
        Section {
            ForEach(lists) { l in
                Button {
                    if selected.contains(l.id) { selected.remove(l.id) } else { selected.insert(l.id) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.name).foregroundStyle(.primary)
                            Text(songCount(l.songs.count)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected.contains(l.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .disabled(l.songs.isEmpty)
            }
        } header: { Text(L("Copia de SimpMusic")) } footer: {
            Text(L("Las canciones ya son de YouTube Music: llegan exactas, sin buscar. No se descarga nada."))
        }
        .onAppear {
            guard !ready else { return }
            ready = true
            selected = Set(lists.filter { !$0.songs.isEmpty }.map(\.id))
        }

        Section {
            Button { onImport(lists.filter { selected.contains($0.id) }) } label: {
                Text(selected.count == 1 ? L("Importar 1 playlist") : L("Importar {0} playlists", selected.count)).frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .disabled(selected.isEmpty)
            Button(role: .cancel, action: onCancel) { Text(L("Cancelar")).frame(maxWidth: .infinity) }
                .buttonStyle(PillButtonStyle(prominent: false))
        }
        .listRowBackground(Color.clear)
    }
}
