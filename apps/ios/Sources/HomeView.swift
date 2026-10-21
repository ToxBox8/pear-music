import Combine
import SwiftUI

extension RemoteCollection {
    func thumb(_ px: Int) -> URL? { Song(id: id, title: title, artist: subtitle, thumbnail: thumbnail).thumb(px) }
}

// MARK: - Inicio
struct HomeView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var jam: JamService
    @AppStorage("searchPlacement") private var searchPlacement = "home"
    @AppStorage("barStyle") private var barStyle = "classic"
    /// Al cambiar de idioma se vuelven a pedir las estanterías, que vienen de YouTube en ese idioma (1.8 de x.1.1).
    @AppStorage("language") private var language = ""
    // Capturas de Ajustes (07, 08): Ajustes ya no es una pestaña, así que se abre su hoja desde Inicio.
    @State private var showSettings = Demo.current?.tab == .settings
    @State private var showAvisos = false
    @ObservedObject private var avisos = AvisosStore.shared
    @State private var query = ""

    /// Buscar vive en Inicio (barra arriba) salvo que en Ajustes se elija la pestaña aparte.
    /// Con la barra estilo SimpMusic, Buscar es el círculo de la barra: Inicio no lleva buscador.
    private var searchInHome: Bool { searchPlacement != "tab" && barStyle != "simpmusic" }
    private var showingSearch: Bool { searchInHome && !query.isEmpty }
    @State private var shelves: [HomeShelf] = []
    @State private var forYou: [Song] = []
    /// «Novedades de tus artistas» (lanzamientos de este año).
    @State private var releases: [RemoteCollection] = []
    @State private var seed: Song?
    @State private var loading = false
    @State private var failed = false
    @State private var shelvesLanguage = ""

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 6..<13: return L("Buenos días")
        case 13..<21: return L("Buenas tardes")
        default: return L("Buenas noches")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if showingSearch { searchResults } else {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ServersBlockedBanner()
                    OldVersionBanner()
                    FirstStepsCard()
                    PinnedRow()
                    if !library.recents.isEmpty {
                        section(L("Escuchado recientemente")) { SongCardsRow(songs: Array(library.recents.prefix(15))) }
                    }
                    if !forYou.isEmpty {
                        section(L("Para ti"), subtitle: seed.map { L("Porque escuchaste «{0}»", $0.title) }) { QuickPicks(songs: forYou) }
                    }
                    if !releases.isEmpty {
                        section(L("Novedades de tus artistas"), subtitle: L("Lo que han sacado este año")) {
                            ShelfContent(items: releases.map { .collection($0) })
                        }
                    }
                    if !library.userPlaylists.isEmpty {
                        section(L("Tus playlists")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(library.userPlaylists) { p in
                                        NavigationLink(value: p.id) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                PlaylistCover(playlist: p, size: 150)
                                                Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                                Text(songCount(p.songs.count)).font(.caption).foregroundStyle(.secondary)
                                            }
                                            .frame(width: 150, alignment: .leading)
                                            .foregroundStyle(.primary)
                                        }
                                        .buttonStyle(TactileButtonStyle())
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    ForEach(shelves) { shelf in
                        section(shelf.title) { ShelfContent(items: shelf.items) }
                    }
                    if loading && shelves.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if failed {
                        VStack(spacing: 10) {
                            Text(L("No se pudieron cargar las recomendaciones.")).foregroundStyle(.secondary)
                            Button { Task { await load() } } label: { Label(L("Reintentar"), systemImage: "arrow.clockwise") }
                                .buttonStyle(PillButtonStyle(prominent: false))
                                .frame(maxWidth: 220)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 20)
                    }
                }
                .padding(.vertical, 12)
                }
            }
            .themed()
            .navigationTitle(greeting)
            // Al bajar por los resultados se va el teclado, como en Buscar (1.7 de x.1.1).
            .scrollDismissesKeyboard(.interactively)
            .modifier(HomeScroll())
            .searchBar(searchInHome, text: $query) {}
            .navigationDestination(for: RemoteCollection.self) { CollectionView(collection: $0) }
            .navigationDestination(for: RemoteArtist.self) { ArtistView(artist: $0) }
            .navigationDestination(for: UUID.self) { PlaylistV11View(playlistID: $0) }
            .toolbar {
                // Ajustes vive siempre aquí, arriba a la izquierda; ya no puede ir en la barra (lo decidió Toxbox).
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape").tourTarget("settings") }
                        .accessibilityLabel(L("Ajustes"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { jam.showSheet = true } label: {
                        Image(systemName: jam.isActive ? "person.3.fill" : "person.3")
                            .tourTarget("jam")
                    }
                    .accessibilityLabel(jam.isActive ? L("Abrir el Jam") : L("Jam con amigos"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AvisosBell { showAvisos = true }
                }
            }
            // Ajustes siempre va en hoja (fase 0): el tema y el modo se aplican dentro, que en iOS 16 no se heredan.
            .sheet(isPresented: $showSettings) { SettingsView().modifier(ThemeAppearance()) }
            // Guía de Ajustes o novedades (1.1): se abre la hoja de Ajustes.
            .onReceive(Guide.shared.$active) { if $0 != nil { showSettings = true } }
            .navigationDestination(isPresented: $showAvisos) { AvisosView() }
            .onReceive(avisos.$abrir.filter { $0 }) { _ in
                avisos.abrir = false
                showAvisos = true
            }
            .refreshable { await load() }
            .task(id: language) {
                // Capturas: sin red, como en ScreenshotTest de Android.
                if Demo.isActive { failed = true; return }
                if shelves.isEmpty || shelvesLanguage != I18n.youtubeHl { await load() }
            }
            .miniPlayer()
        }
    }

    /// Resultados mientras se escribe: artistas, álbumes y canciones (SearchViews.swift).
    private var searchResults: some View { SearchResultsView(query: query) }

    @ViewBuilder
    private func section<C: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
            .padding(.horizontal)
            content()
        }
    }

    private func load() async {
        loading = true
        failed = false
        shelvesLanguage = I18n.youtubeHl
        do { shelves = try await YTClient.home() } catch { failed = shelves.isEmpty }
        let homeSong = shelves.flatMap(\.items).compactMap { item -> Song? in
            if case .song(let s) = item { return s }
            return nil
        }.first
        if let s = library.recents.first ?? library.favorites.first ?? homeSong {
            seed = s
            forYou = Array(((try? await YTClient.radio(for: s.id)) ?? []).prefix(20))
        }
        loading = false
        // Novedades después, para no retrasar el resto de Inicio (hasta 16 peticiones la primera vez al día).
        releases = await Releases.load(artists: Releases.topArtists(saved: library.allSongs()))
    }
}

// MARK: - Piezas del inicio
struct CardLabel: View {
    let url: URL?
    let title: String
    let subtitle: String
    var size: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: url)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.artworkCard, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.artworkCard, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: size, alignment: .leading)
        .foregroundStyle(.primary)
    }
}

struct SongCardsRow: View {
    let songs: [Song]
    @EnvironmentObject var player: Player

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(songs) { s in
                    Button { player.play(s, in: songs) } label: {
                        CardLabel(url: s.thumb(400), title: s.title, subtitle: s.artist)
                    }
                    .buttonStyle(TactileButtonStyle())
                    .contextMenu { SongMenuItems(song: s) }
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Rejilla horizontal de 4 filas, como las «Selecciones rápidas» de YouTube Music.
struct QuickPicks: View {
    let songs: [Song]
    @EnvironmentObject var player: Player

    var body: some View {
        let rows = min(4, max(1, songs.count))
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(58), spacing: 8), count: rows), spacing: 12) {
                ForEach(songs) { s in
                    Button { player.play(s, in: songs) } label: {
                        HStack(spacing: 10) {
                            CoverImage(url: s.thumb(120))
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(s.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(4)
                        .frame(width: 280)
                        .background(ThemeSurface(radius: 14))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(TactileButtonStyle())
                    .contextMenu { SongMenuItems(song: s) }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: CGFloat(rows) * 58 + CGFloat(rows - 1) * 8)
    }
}

struct ShelfContent: View {
    let items: [HomeItem]
    @EnvironmentObject var player: Player

    var body: some View {
        let songs = items.compactMap { item -> Song? in
            if case .song(let s) = item { return s }
            return nil
        }
        if songs.count == items.count {
            QuickPicks(songs: songs)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        switch item {
                        case .song(let s):
                            Button { player.play(s, in: songs) } label: {
                                CardLabel(url: s.thumb(400), title: s.title, subtitle: s.artist)
                            }
                            .buttonStyle(TactileButtonStyle())
                            .contextMenu { SongMenuItems(song: s) }
                        case .collection(let c):
                            NavigationLink(value: c) {
                                CardLabel(url: c.thumb(400), title: c.title, subtitle: c.subtitle)
                            }
                            .buttonStyle(TactileButtonStyle())
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Álbum / playlist de YouTube Music
struct CollectionView: View {
    let collection: RemoteCollection
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: Library
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var saved = false
    @State private var confirmRemove = false
    @State private var showArtist = false

    /// Un álbum («MPREb_…») va a «Tus álbumes»; una playlist de YouTube Music, a Playlists.
    private var isAlbum: Bool { collection.id.hasPrefix("MPREb") }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    CoverImage(url: collection.thumb(600))
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                    Text(collection.title).font(.title2.bold()).multilineTextAlignment(.center)
                    // «Álbum • Artista • año»: el artista se toca para ir a su perfil (Fase 3.1).
                    let parts = collection.subtitle.components(separatedBy: " • ")
                    if isAlbum, parts.count >= 2, !parts[1].isEmpty {
                        HStack(spacing: 0) {
                            Text(parts[0] + " · ").foregroundStyle(.secondary)
                            Button(parts[1]) { showArtist = true }
                                .buttonStyle(.borderless).fontWeight(.semibold)
                                .accessibilityLabel(L("Ver el perfil de {0}", parts[1]))
                            if parts.count >= 3 { Text(" · " + (parts.last ?? "")).foregroundStyle(.secondary) }
                        }
                        .font(.subheadline)
                    } else {
                        Text(collection.subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    PlayShuffleBar(songs: songs)
                        .padding(.top, 4)
                    if isAlbum {
                        Button { if saved { confirmRemove = true } else { Task { await save() } } } label: {
                            Label(saved ? L("En Tus álbumes") : L("Añadir a Tus álbumes"),
                                  systemImage: saved ? "checkmark" : "plus")
                        }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(songs.isEmpty)
                        .confirmationDialog(L("¿Quitar «{0}» de Tus álbumes?", collection.title), isPresented: $confirmRemove, titleVisibility: .visible) {
                            Button(L("Quitar de Tus álbumes"), role: .destructive) { removeAlbum() }
                        } message: {
                            Text(L("Las canciones descargadas se quedan en Descargadas."))
                        }
                    } else {
                        Button { Task { await save() } } label: {
                            Label(saved ? L("Guardada en tu biblioteca") : L("Guardar en biblioteca"),
                                  systemImage: saved ? "checkmark" : "plus")
                        }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(songs.isEmpty || saved)
                    }
                    // Descarga sólo las canciones de este álbum o lista (dueño = su browseId).
                    // Descargar un álbum también lo guarda en «Tus álbumes».
                    DownloadAllButton(owner: collection.id, songs: songs, title: collection.title,
                                      onStart: isAlbum && !saved ? { Task { await save() } } : nil)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section {
                ForEach(songs) { song in
                    SongRowV11(song: song, context: songs)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.primary.opacity(0.08))
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8))
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading { ProgressView() }
            else if songs.isEmpty { Text(L("No se pudieron cargar las canciones")).foregroundStyle(.secondary) }
        }
        .navigationDestination(isPresented: $showArtist) {
            let name = collection.subtitle.components(separatedBy: " • ").dropFirst().first ?? ""
            ArtistProfileLoader(name: name, songs: library.allSongs().filter { primaryArtist($0.artist).caseInsensitiveCompare(name) == .orderedSame })
        }
        .themed()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isAlbum { saved = library.album(collection.id) != nil }
            songs = (try? await YTClient.collectionSongs(collection)) ?? []
            loading = false
        }
        .miniPlayer()
    }

    private func save() async {
        guard !saved else { return }
        saved = true
        var cover: Data?
        if let url = collection.thumb(600) { cover = try? await URLSession.shared.data(from: url).0 }
        library.importPlaylist(name: collection.title, songs: songs, cover: cover,
                               album: isAlbum ? AlbumInfo(browseId: collection.id, subtitle: collection.subtitle) : nil)
    }

    private func removeAlbum() {
        if let p = library.album(collection.id) { library.deletePlaylist(p.id) }
        saved = false
    }
}

extension View {
    /// Barra de búsqueda fija bajo el título (sólo si Buscar va en Inicio).
    @ViewBuilder func searchBar(_ enabled: Bool, text: Binding<String>, submit: @escaping () -> Void) -> some View {
        if enabled {
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Canciones, artistas…"))
                .onSubmit(of: .search) {
                    submit()
                    // «Buscar» en el teclado: se quita para ver los resultados enteros (1.7 de x.1.1).
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        } else {
            self
        }
    }
}

/// Avisa de cuándo se mueve Inicio y de cuándo lleva 1,5 s quieto, para «Buscar vuelve al parar» (2.10 de x.1.1).
/// Sólo iOS 18+ (`onScrollPhaseChange`); la barra que se pliega es la de iOS 26, así que antes no hace falta.
struct HomeScroll: ViewModifier {
    static let idle = Notification.Name("HomeScroll.idle")
    static let moving = Notification.Name("HomeScroll.moving")
    @State private var wait: Task<Void, Never>?

    func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                wait?.cancel()
                if phase == .idle {
                    wait = Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if !Task.isCancelled { NotificationCenter.default.post(name: Self.idle, object: nil) }
                    }
                } else {
                    NotificationCenter.default.post(name: Self.moving, object: nil)
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
