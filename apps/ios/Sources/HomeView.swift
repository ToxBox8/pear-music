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
    @State private var showSettings = false
    @State private var query = ""

    /// Buscar vive en Inicio (barra arriba) salvo que en Ajustes se elija la pestaña aparte.
    private var searchInHome: Bool { searchPlacement != "tab" }
    private var showingSearch: Bool { searchInHome && !query.isEmpty }
    @State private var shelves: [HomeShelf] = []
    @State private var forYou: [Song] = []
    /// «Novedades de tus artistas» (lanzamientos de este año).
    @State private var releases: [RemoteCollection] = []
    @State private var seed: Song?
    @State private var loading = false
    @State private var failed = false

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 6..<13: return "Buenos días"
        case 13..<21: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if showingSearch { searchResults } else {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if !library.recents.isEmpty {
                        section("Escuchado recientemente") { SongCardsRow(songs: Array(library.recents.prefix(15))) }
                    }
                    if !forYou.isEmpty {
                        section("Para ti", subtitle: seed.map { "Porque escuchaste «\($0.title)»" }) { QuickPicks(songs: forYou) }
                    }
                    if !releases.isEmpty {
                        section("Novedades de tus artistas", subtitle: "Lo que han sacado este año") {
                            ShelfContent(items: releases.map { .collection($0) })
                        }
                    }
                    if !library.userPlaylists.isEmpty {
                        section("Tus playlists") {
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
                            Text("No se pudieron cargar las recomendaciones.").foregroundStyle(.secondary)
                            Button { Task { await load() } } label: { Label("Reintentar", systemImage: "arrow.clockwise") }
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
            .searchBar(searchInHome, text: $query) {}
            .navigationDestination(for: RemoteCollection.self) { CollectionView(collection: $0) }
            .navigationDestination(for: RemoteArtist.self) { ArtistView(artist: $0) }
            .navigationDestination(for: UUID.self) { PlaylistV11View(playlistID: $0) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { jam.showSheet = true } label: {
                        Image(systemName: jam.isActive ? "person.2.wave.2.fill" : "person.2.wave.2")
                    }
                    .accessibilityLabel(jam.isActive ? "Abrir el Jam" : "Jam con amigos")
                }
                // Con la barra estilo SimpMusic, Ajustes sale de la barra y vive aquí, junto al Jam.
                if barStyle == "simpmusic" {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Ajustes")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .refreshable { await load() }
            .task {
                // Capturas: sin red, como en ScreenshotTest de Android.
                if Demo.isActive { failed = true; return }
                if shelves.isEmpty { await load() }
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
                    Text(collection.subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    PlayShuffleBar(songs: songs)
                        .padding(.top, 4)
                    if isAlbum {
                        Button { if saved { confirmRemove = true } else { Task { await save() } } } label: {
                            Label(saved ? "En Tus álbumes" : "Añadir a Tus álbumes",
                                  systemImage: saved ? "checkmark" : "plus")
                        }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(songs.isEmpty)
                        .confirmationDialog("¿Quitar «\(collection.title)» de Tus álbumes?", isPresented: $confirmRemove, titleVisibility: .visible) {
                            Button("Quitar de Tus álbumes", role: .destructive) { removeAlbum() }
                        } message: {
                            Text("Las canciones descargadas se quedan en Descargadas.")
                        }
                    } else {
                        Button { Task { await save() } } label: {
                            Label(saved ? "Guardada en tu biblioteca" : "Guardar en biblioteca",
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
            else if songs.isEmpty { Text("No se pudieron cargar las canciones").foregroundStyle(.secondary) }
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
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Canciones, artistas…")
                .onSubmit(of: .search, submit)
        } else {
            self
        }
    }
}
