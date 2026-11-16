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
/// Biblioteca), van aquí con su portada.
/// Menús y gestos (paso B; DECISIONS 40): mantener pulsada una portada abre su menú y nada más; el orden se cambia en
/// el modo «Ordenar» (del ⋯ o del menú de una portada), arrastrando la portada entera (paso C; DECISIONS 42 y 43), y
/// pasa a «A mano». El + crea una playlist (y la abre) o una carpeta.
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    /// Modo «Ordenar» (sólo se arrastra; DECISIONS 42 y 43).
    @State private var ordering = Demo.current?.playlistsOrdering == true
    @State private var moving: MoveItem?
    @State private var deleting: PlaylistFolder?
    @State private var deletingPlaylist: Playlist?
    @State private var editingPlaylist: Playlist?
    @State private var opened: Entry?
    /// La playlist recién creada: se abre para que se vea que existe y añadirle canciones.
    @State private var created: UUID?
    /// La carpeta recién creada: la cuadrícula se desplaza hasta ella.
    @State private var reveal: String?
    /// Si se entra en «Ordenar» desde el menú de una portada, ésa se queda a la vista.
    @State private var keepVisible: String?

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

    private static var sorts: [(String, String)] { [
        ("recent", L("Añadidas recientemente")), ("name", L("Nombre (A-Z)")), ("nameDesc", L("Nombre (Z-A)")),
        ("count", L("Nº de canciones")), ("custom", L("A mano")),
    ] }

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
        // En el modo «Ordenar» se ve el nivel entero: ordenar sólo lo encontrado no tendría sentido.
        let shown = query.isEmpty || ordering ? all : searchEntries()
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // El buscador es la primera fila de la lista, como en Android, y no se dibuja mientras se ordena
                    // (DECISIONS 42 y 47): la lista no se vuelve a crear y se queda donde estaba.
                    if !ordering && !all.isEmpty {
                        ListSearchField(text: $query, prompt: folder.map { L("Buscar en {0}", $0.name) } ?? L("Buscar en playlists"))
                    }
                    if let folder, !ordering { FolderHeader(folder: folder) }
                    if !shown.isEmpty {
                        if ordering { OrderHint() }
                        ReorderGrid(items: shown, ordering: ordering, onMoved: saveOrder,
                                    canDropInto: canDropInto, canSwap: canSwap, onDropInto: dropInto,
                                    menu: { AnyView(menu($0)) },
                                    destination: { e in
                                        if let p = e.playlist { PlaylistV11View(playlistID: p.id) }
                                        else if let f = e.folder { PlaylistsListView(folderID: f.id) }
                                        else if let k = e.smart { SmartListV11View(kind: k) }
                                    }) { e in cell(e) }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: reveal) { key in
                guard let key else { return }
                withAnimation(reduceMotion ? nil : .uiEaseOut(0.3)) { proxy.scrollTo(key, anchor: .center) }
                reveal = nil
            }
            // Sin ancla: lo mínimo para que se vea entera (si ya se ve, no se mueve).
            .onChange(of: keepVisible) { key in
                guard let key else { return }
                proxy.scrollTo(key)
                keepVisible = nil
            }
        }
        .overlay {
            if all.isEmpty && query.isEmpty {
                EmptyCreate(folder: folderID != nil) { newPlaylist(in: folderID) }
            } else if shown.isEmpty { NoMatchesView(query: query) }
        }
        .themed()
        .navigationTitle(ordering ? L("Ordenar") : folder?.name ?? L("Playlists"))
        .navigationBarBackButtonHidden(ordering)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if ordering {
                    Button(L("Hecho")) { setOrdering(false) }.fontWeight(.semibold)
                } else {
                    Menu { addMenu } label: { Image(systemName: "plus") }
                        .accessibilityLabel(L("Nueva playlist o carpeta"))
                    Menu { toolbarMenu } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel(L("Más opciones"))
                }
            }
        }
        .sheet(item: $moving) { MoveToFolderSheet(item: $0) }
        .sheet(item: $editingPlaylist) { PlaylistEditor(playlistID: $0.id) }
        .navigationDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let p = opened?.playlist { PlaylistV11View(playlistID: p.id) }
            else if let f = opened?.folder { PlaylistsListView(folderID: f.id) }
            else if let k = opened?.smart { SmartListV11View(kind: k) }
        }
        .navigationDestination(isPresented: Binding(get: { created != nil }, set: { if !$0 { created = nil } })) {
            if let created { PlaylistV11View(playlistID: created) }
        }
        .deletePlaylistAlert($deletingPlaylist, library: library)
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
        // Escribir en el buscador sale del modo «Ordenar».
        .onChange(of: query) { q in if !q.isEmpty && ordering { setOrdering(false) } }
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

    /// El menú de mantener pulsado (lo decidió Toxbox: mantener pulsado es sólo menú).
    @ViewBuilder private func menu(_ e: Entry) -> some View {
        Button { opened = e } label: { Label(L("Abrir"), systemImage: "arrow.up.right.square") }
        if let p = e.playlist {
            Button { moving = .playlist(p.id) } label: { Label(L("Mover a…"), systemImage: "folder") }
            if let current = p.folder, let f = library.folders.first(where: { $0.id == current }) {
                Button { library.movePlaylist(p.id, to: f.parent) } label: {
                    Label(L("Sacar de «{0}»", f.name), systemImage: "arrow.up.forward.square")
                }
            }
            Button { startOrdering(e.key) } label: { Label(L("Ordenar"), systemImage: "arrow.up.arrow.down") }
            Button { library.update(p.id) { $0.pinned = $0.pinned == true ? nil : true } } label: {
                p.pinned == true ? Label(L("Soltar de arriba"), systemImage: "pin.slash") : Label(L("Fijar arriba"), systemImage: "pin")
            }
            Divider()
            Button { editingPlaylist = p } label: { Label(L("Editar"), systemImage: "pencil") }
            Button(role: .destructive) { deletingPlaylist = p } label: { Label(L("Eliminar…"), systemImage: "trash") }
        } else if let f = e.folder {
            Button { rename(f) } label: { Label(L("Renombrar"), systemImage: "pencil") }
            Button { moving = .folder(f.id) } label: { Label(L("Mover carpeta a…"), systemImage: "folder") }
            Button { startOrdering(e.key) } label: { Label(L("Ordenar"), systemImage: "arrow.up.arrow.down") }
            Divider()
            Button(role: .destructive) { deleting = f } label: { Label(L("Eliminar carpeta…"), systemImage: "trash") }
        } else {
            Button { startOrdering(e.key) } label: { Label(L("Ordenar"), systemImage: "arrow.up.arrow.down") }
        }
    }

    /// El + de la barra: crear aquí.
    @ViewBuilder private var addMenu: some View {
        Button { newPlaylist(in: folderID) } label: {
            Label(folderID == nil ? L("Nueva playlist") : L("Nueva playlist aquí"), systemImage: "plus.rectangle.on.rectangle")
        }
        if PlaylistFolders.canCreate(in: folderID, folders: library.folders) {
            Button { newFolder(in: folderID) } label: {
                Label(folderID == nil ? L("Nueva carpeta") : L("Nueva carpeta aquí"), systemImage: "folder.badge.plus")
            }
        }
    }

    @ViewBuilder private var toolbarMenu: some View {
        Button { startOrdering() } label: { Label(L("Ordenar"), systemImage: "arrow.up.arrow.down") }
        // El criterio (antes en la pantalla «Editar orden»).
        Picker(L("Ordenar por"), selection: $sort) {
            ForEach(Self.sorts, id: \.0) { item in Text(item.1).tag(item.0) }
        }
        .pickerStyle(.inline)
        if let folder {
            Divider()
            Button { rename(folder) } label: { Label(L("Renombrar"), systemImage: "pencil") }
            Button { moving = .folder(folder.id) } label: { Label(L("Mover carpeta a…"), systemImage: "folder") }
            Button(role: .destructive) { deleting = folder } label: { Label(L("Eliminar carpeta…"), systemImage: "trash") }
        }
    }

    // MARK: Modo «Ordenar»

    /// Entra o sale de «Ordenar»; `keep`, la portada que tiene que quedar a la vista. La lista es la misma y se queda
    /// donde estaba. Sin animación: la cuadrícula cambia de una perezosa a una que no lo es (un fundido enseñaría dos).
    private func setOrdering(_ on: Bool, keep: String? = nil) {
        ordering = on
        if let keep { keepVisible = keep }
    }

    /// Entra en el modo «Ordenar» (del ⋯ o, con `key`, del menú de esa portada): se borra lo buscado y se ve el nivel
    /// entero.
    private func startOrdering(_ key: String? = nil) {
        query = ""
        setOrdering(true, keep: key)
    }

    /// Guarda el orden de este nivel; al mover algo, Playlists pasa a ordenarse «A mano».
    private func saveOrder(_ moved: [String]) {
        guard moved != keys else { return }
        orderRaw = LibraryOrder.reorder(level: moved, playlists: library.userPlaylists, folders: library.folders,
                                        sort: sort, order: LibraryOrder.decode(orderRaw)).joined(separator: "\n")
        sort = "custom"
    }

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
        withAnimation(reduceMotion ? nil : .uiEaseOut(0.25)) { library.movePlaylist(id, to: folder) }
    }

    // MARK: Nombres

    private func newPlaylist(in folder: String?) {
        NamePrompt.ask(L("Nueva playlist")) { name in created = library.createPlaylist(name, in: folder) }
    }

    private func newFolder(in parent: String?) {
        NamePrompt.ask(L("Nueva carpeta")) { name in
            if let id = library.createFolder(name, in: parent) { reveal = LibraryOrder.key(folder: id) }
        }
    }

    private func rename(_ f: PlaylistFolder) {
        NamePrompt.ask(L("Renombrar carpeta"), initial: f.name, confirm: L("Guardar")) { library.renameFolder(f.id, to: $0) }
    }

    private func destinationName(_ f: PlaylistFolder?) -> String {
        f?.parent.flatMap { p in library.folders.first { $0.id == p }?.name } ?? L("Playlists")
    }
}

/// Sin nada todavía (Playlists o una carpeta): qué es y un botón para empezar.
private struct EmptyCreate: View {
    let folder: Bool
    let create: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: folder ? "folder" : "music.note.list").font(.system(size: 40, weight: .regular)).foregroundStyle(.secondary)
            Text(folder ? L("Carpeta vacía") : L("Todavía no hay playlists")).font(.headline)
            if folder {
                Text(L("Crea una playlist aquí o trae una con «Mover a…» de su menú."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button(action: create) { Text(L("Crear playlist")) }
                .buttonStyle(PillButtonStyle(prominent: true))
                .frame(maxWidth: 220)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }
}

/// «Tus álbumes»: los álbumes guardados o descargados desde su página, en cuadrícula y con buscador. Mantener pulsado
/// abre el menú; «Ordenar» entra en el mismo modo que Playlists, sin «Mover a…» (paso B; DECISIONS 40).
struct AlbumsListView: View {
    @EnvironmentObject var library: Library
    @AppStorage("albumSort") private var albumSort = "recent"
    @AppStorage("albumOrder") private var albumOrder = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var ordering = false
    /// Como en Playlists: la portada del menú se queda a la vista al entrar en «Ordenar».
    @State private var keepVisible: UUID?
    @State private var deleting: Playlist?
    @State private var opened: Playlist?

    var body: some View {
        let albums = LibraryOrder.albums(library.albums, sort: albumSort, order: LibraryOrder.decode(albumOrder))
        let shown = ordering ? albums : LocalSearch.filter(albums, query) { "\($0.name) \($0.album?.artist ?? "")" }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // El buscador, primera fila de la lista; no se dibuja mientras se ordena (DECISIONS 42 y 47).
                    if !ordering && !albums.isEmpty { ListSearchField(text: $query, prompt: L("Buscar en tus álbumes")) }
                    if !shown.isEmpty {
                        if ordering { OrderHint() }
                        ReorderGrid(items: shown, ordering: ordering, onMoved: save,
                                    menu: { AnyView(menu($0)) },
                                    destination: { p in PlaylistV11View(playlistID: p.id) }) { p in
                            GridCover(playlist: p, subtitle: p.album?.line ?? songCount(p.songs.count))
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: keepVisible) { id in
                guard let id else { return }
                proxy.scrollTo(id)
                keepVisible = nil
            }
        }
        .overlay {
            if albums.isEmpty { AlbumsEmptyView() }
            else if shown.isEmpty { NoMatchesView(query: query) }
        }
        .themed()
        .navigationTitle(ordering ? L("Ordenar") : L("Tus álbumes"))
        .navigationBarBackButtonHidden(ordering)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if ordering {
                    Button(L("Hecho")) { setOrdering(false) }.fontWeight(.semibold)
                } else if albums.count > 1 {
                    Button(L("Ordenar")) { start() }
                }
            }
        }
        .navigationDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened { PlaylistV11View(playlistID: opened.id) }
        }
        .deletePlaylistAlert($deleting, library: library)
        .onChange(of: query) { q in if !q.isEmpty && ordering { setOrdering(false) } }
        .miniPlayer()
    }

    @ViewBuilder private func menu(_ p: Playlist) -> some View {
        Button { opened = p } label: { Label(L("Abrir"), systemImage: "arrow.up.right.square") }
        Button { start(p.id) } label: { Label(L("Ordenar"), systemImage: "arrow.up.arrow.down") }
        Button { library.update(p.id) { $0.pinned = $0.pinned == true ? nil : true } } label: {
            p.pinned == true ? Label(L("Soltar de arriba"), systemImage: "pin.slash") : Label(L("Fijar arriba"), systemImage: "pin")
        }
        Divider()
        Button(role: .destructive) { deleting = p } label: { Label(L("Eliminar…"), systemImage: "trash") }
    }

    private func setOrdering(_ on: Bool, keep: UUID? = nil) {
        ordering = on
        if let keep { keepVisible = keep }
    }

    private func start(_ keep: UUID? = nil) {
        query = ""
        setOrdering(true, keep: keep)
    }

    private func save(_ moved: [UUID]) {
        // Las claves `folder:` de las carpetas de álbumes (T15) se quedan, aunque aún no se pinten.
        albumOrder = LibraryOrder.savingAlbums(moved.map(\.uuidString), into: LibraryOrder.decode(albumOrder)).joined(separator: "\n")
        albumSort = "custom"
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

/// El buscador de Playlists, de una carpeta y de Tus álbumes: la primera fila de la lista (DECISIONS 47), con el mismo
/// aspecto que `SearchField` en Android (36 de alto, relleno del sistema atenuado, lupa y botón de borrar). No es
/// `.searchable`: iOS 16 no deja esconder ése sin volver a crear la lista, que acababa arriba al entrar y salir de
/// «Ordenar». Sin shu: el cursor va del color del texto.
struct ListSearchField: View {
    @Binding var text: String
    let prompt: String
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .font(.body)
                .tint(Color.primary)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { focused = false }
                .accessibilityAddTraits(.isSearchField)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        // El dibujo mide como en Android; la zona táctil, los 44 pt de siempre.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -13)
                .accessibilityLabel(L("Borrar"))
            }
        }
        .padding(.horizontal, 8)
        // 36 como en Android; crece con el tamaño de letra del sistema.
        .frame(minHeight: 36)
        // El mismo relleno que Android: `fill` de tokens.json (el relleno del sistema) al 45 % en claro y al 60 % en oscuro.
        .background(Color(uiColor: .systemFill).opacity(scheme == .dark ? 0.6 : 0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
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

/// Cuadrícula de dos columnas de Playlists, de una carpeta y de Tus álbumes. Fuera de «Ordenar», tocar abre y
/// mantener pulsado abre el menú (`menu`). En «Ordenar» (`ordering`) sólo se arrastra: el dedo quieto 0,2 s levanta la
/// portada entera (deslizar antes desplaza la lista), la copia levantada sigue al dedo sin animación y deja su hueco
/// marcado, las demás se apartan, soltar sobre una carpeta (`canDropInto`) la mete dentro y cerca del borde de arriba o
/// de abajo la lista se desplaza sola (`OrderLift`). Tocar no hace nada. Igual que `ReorderGrid` en Android.
struct ReorderGrid<Item: Identifiable, Destination: View, Cell: View>: View {
    let items: [Item]
    let ordering: Bool
    let onMoved: ([Item.ID]) -> Void
    /// ¿Se puede soltar `arrastrado` dentro de `celda`? (carpetas; por defecto, nada es contenedor).
    var canDropInto: (Item.ID, Item.ID) -> Bool = { _, _ in false }
    /// ¿Se aparta `celda` al pasar `arrastrado` por encima? (las carpetas van siempre delante de las playlists).
    var canSwap: (Item.ID, Item.ID) -> Bool = { _, _ in true }
    var onDropInto: (Item.ID, Item.ID) -> Void = { _, _ in }
    /// Menú al mantener pulsado (si no se da, nada).
    var menu: ((Item) -> AnyView)? = nil
    @ViewBuilder let destination: (Item) -> Destination
    @ViewBuilder let cell: (Item) -> Cell
    @StateObject private var lift = OrderLift<Item.ID>()
    @GestureState private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)]
    private let space = "order-grid"

    var body: some View {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let shown = lift.order.compactMap { byID[$0] }
        let list = shown.count == items.count ? shown : items
        Group {
            if ordering {
                // Sin pereza mientras se ordena: la portada cogida no puede desaparecer a mitad del gesto.
                OrderGridLayout { ForEach(list) { p in orderCell(p).id(p.id) } }
            } else {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(list) { p in
                        NavigationLink { destination(p) } label: { cell(p) }
                            .buttonStyle(TactileButtonStyle())
                            .contextMenu { if let menu { menu(p) } }
                            .id(p.id)
                    }
                }
            }
        }
        .coordinateSpace(name: space)
        .background(OrderAnchorView(anchor: lift.anchor))
        .onPreferenceChange(OrderFrameKey<Item.ID>.self) { lift.frames = $0 }
        .overlay(alignment: .topLeading) { liftedCopy(byID) }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, ordering ? 12 : 0)
        .onAppear { lift.order = items.map(\.id) }
        .onChange(of: items.map(\.id)) { ids in if lift.drag == nil { lift.order = ids } }
        .onChange(of: pressing) { on in if !on { finish() } }
        // Salir de «Ordenar» (o irse la pantalla) con una portada cogida la suelta donde está y guarda el orden.
        .onChange(of: ordering) { on in if !on { finish() } }
        .onDisappear { finish() }
    }

    /// Una celda en el modo «Ordenar»: no se toca; se coge con el dedo quieto y, mientras está levantada, en su sitio
    /// queda el hueco.
    private func orderCell(_ p: Item) -> some View {
        let lifted = lift.drag?.id == p.id
        return ZStack(alignment: .top) {
            cell(p).opacity(lifted ? 0 : 1)
            if lifted { OrderHole() }
        }
        .environment(\.dropInto, lift.drag?.into == p.id)
        .contentShape(Rectangle())
        .gesture(OrderGesture.lift(pressing: $pressing,
                                   onLift: { lift.lift(p.id, axis: .vertical, reduceMotion: reduceMotion, canDropInto: canDropInto, canSwap: canSwap) },
                                   // Sólo manda el dedo que la cogió (un segundo dedo en otra portada no la mueve).
                                   onMove: { if lift.drag?.id == p.id { lift.move(start: $0, now: $1) } },
                                   onEnd: finish))
        .background(GeometryReader { g in
            Color.clear.preference(key: OrderFrameKey<Item.ID>.self, value: [p.id: g.frame(in: .named(space))])
        })
    }

    /// La portada levantada, encima de la cuadrícula y en el sitio del dedo, sin animación.
    @ViewBuilder private func liftedCopy(_ byID: [Item.ID: Item]) -> some View {
        if let d = lift.drag, let item = byID[d.id], let r = d.slots[d.start] {
            cell(item)
                .frame(width: r.width, height: r.height, alignment: .top)
                .orderLifted(reduceMotion: reduceMotion)
                .opacity(d.into != nil ? 0.85 : 1)
                .offset(x: r.minX + lift.shift.width, y: r.minY + lift.shift.height)
                .accessibilityHidden(true)
        }
    }

    private func finish() {
        guard let d = lift.end() else { return }
        if let into = d.into { onDropInto(d.id, into) }
        else if d.changed { onMoved(lift.order) }
    }
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
