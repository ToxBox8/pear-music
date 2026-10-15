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

struct PlaylistsListView: View {
    @EnvironmentObject var library: Library
    @AppStorage("playlistSort") private var sort = "recent"
    @AppStorage("playlistOrder") private var orderRaw = ""
    @State private var query = ""
    @State private var editing = false

    /// En el mismo orden que el carrusel.
    private var ordered: [Playlist] {
        let byID = Dictionary(library.userPlaylists.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        return LibraryOrder.keys(library.userPlaylists, sort: sort, order: LibraryOrder.decode(orderRaw), smartInPlaylists: false).compactMap { byID[$0] }
    }

    var body: some View {
        let shown = LocalSearch.filter(ordered, query) { $0.name }
        List {
            ForEach(shown) { p in
                NavigationLink { PlaylistV11View(playlistID: p.id) } label: {
                    HStack(spacing: 14) {
                        PlaylistCover(playlist: p, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.body.weight(.medium)).lineLimit(1)
                            Text(songCount(p.songs.count)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .glassRow()
        }
        .overlay {
            if library.userPlaylists.isEmpty { Text(L("Todavía no hay playlists")).foregroundStyle(.secondary) }
            else if shown.isEmpty { NoMatchesView(query: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Buscar en playlists"))
        .scrollDismissesKeyboard(.interactively)
        .themed()
        .navigationTitle(L("Playlists"))
        // Lápiz (lo pidió Toxbox): editar el orden aquí mismo, sin ir a Ajustes.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel(L("Editar el orden de las playlists"))
            }
        }
        .sheet(isPresented: $editing) { ReorderPlaylistsView() }
        .miniPlayer()
    }
}

/// «Tus álbumes»: los álbumes guardados o descargados desde su página, en cuadrícula y con buscador.
struct AlbumsListView: View {
    @EnvironmentObject var library: Library
    @State private var query = ""
    private let columns = [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)]

    var body: some View {
        let albums = library.albums
        let shown = LocalSearch.filter(albums, query) { "\($0.name) \($0.album?.artist ?? "")" }
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(shown) { p in
                    NavigationLink { PlaylistV11View(playlistID: p.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            PlaylistCover(playlist: p, size: nil)
                                .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                            Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(p.album?.line ?? songCount(p.songs.count))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(TactileButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
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
    @State private var query = ""
    /// Orden A-Z / Z-A con el botón de arriba a la derecha (Fase 3.1); mismo ajuste que Android.
    @AppStorage("artistsSort") private var sort = "az"

    var body: some View {
        let ordered = artists.sorted { LocalSearch.fold($0.name) < LocalSearch.fold($1.name) }
        let shown = LocalSearch.filter(sort == "za" ? ordered.reversed() : ordered, query) { $0.name }
        List(shown) { a in
            // Al tocar se abre su perfil de YouTube Music (discografía completa); sin red o sin encontrarlo, sus canciones.
            NavigationLink {
                ArtistProfileLoader(name: a.name, songs: a.songs)
            } label: {
                HStack(spacing: 12) {
                    CoverImage(url: a.songs.first?.thumb(160))
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.body.weight(.medium)).lineLimit(1)
                        Text(songCount(a.songs.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .glassRow()
        }
        .overlay {
            if artists.isEmpty { Text(L("Guarda canciones para ver sus artistas")).foregroundStyle(.secondary) }
            else if shown.isEmpty { NoMatchesView(query: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Buscar artistas"))
        .scrollDismissesKeyboard(.interactively)
        .themed()
        .navigationTitle(L("Artistas"))
        .toolbar {
            if !artists.isEmpty {
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
                    Section {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label(PlaylistArt.exists(p.id) ? "Cambiar foto" : "Elegir foto", systemImage: "photo.on.rectangle")
                        }
                        if PlaylistArt.exists(p.id) {
                            Button(role: .destructive) { library.setCover(nil, for: p.id) } label: {
                                Label("Quitar foto", systemImage: "trash")
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
                        Button { link = UIPasteboard.general.string ?? link } label: { Label("Pegar", systemImage: "doc.on.clipboard") }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button { Task { await importLink() } } label: { Label("Importar", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.borderedProminent)
                            .disabled(link.isEmpty)
                    }
                } header: { Text(L("Desde un enlace")) } footer: {
                    Text(L("Apple Music o Spotify: abre la playlist → Compartir → Copiar enlace. Tiene que ser pública. De Spotify llegan hasta unas 100 canciones; para listas más largas, usa el CSV de Exportify."))
                }
                .disabled(busy)

                Section {
                    Button { fileMode = .csv; importingBackup = true } label: { Label("CSV de Exportify (Spotify)", systemImage: "doc.text") }
                    Button { fileMode = .simpMusic; importingBackup = true } label: { Label("Copia de SimpMusic (.backup)", systemImage: "clock.arrow.circlepath") }
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
                        Button { Task { await loadLocal() } } label: { Label("Ver mis playlists", systemImage: "music.note.house") }
                    }
                } header: { Text(L("Desde la app Música de este iPhone")) } footer: {
                    Text(L("Lee las playlists de tu biblioteca (necesita «Sincronizar biblioteca» activado en Ajustes → Música)."))
                }
                .disabled(busy)

                // Lo mismo que Android: la biblioteca entera en un archivo, para pasarla de un móvil a otro.
                Section {
                    Button { fileMode = .library; importingBackup = true } label: { Label("Importar copia", systemImage: "square.and.arrow.down") }
                    Button {
                        backup = LibraryBackup(data: library.exportData())
                        exportingBackup = true
                    } label: { Label("Exportar copia", systemImage: "square.and.arrow.up") }
                } header: { Text(L("Copia de la biblioteca")) } footer: {
                    Text(L("Archivo library.json de Pear Music (también el de Android). Se añade lo que no tengas, sin borrar nada."))
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
