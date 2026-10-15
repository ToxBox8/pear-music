import SwiftUI

// MARK: - Biblioteca «Nueva 1.1»
// Las playlists son lo primero que se ve: un carrusel de portadas grandes con las listas
// inteligentes (Descargadas, Favoritos) por delante. Debajo, el resto de la música en filas
// sobrias. Dentro de una playlist cada canción lleva sus propios botones de favorito y
// descarga, y un anillo de puntos muestra cuánta de la lista está disponible sin conexión.

// MARK: Helpers de plataforma
/// `contentMargins` y el ajuste al soltar el carrusel son de iOS 17; en iOS 16 se usa padding clásico.
private var carouselUsesMargins: Bool {
    if #available(iOS 17.0, *) { return true }
    return false
}

private extension View {
    @ViewBuilder func carouselScroll(inset: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.contentMargins(.horizontal, inset, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
        } else {
            self
        }
    }

    @ViewBuilder func carouselLayout() -> some View {
        if #available(iOS 17.0, *) { self.scrollTargetLayout() } else { self }
    }

    /// Las tarjetas lejos del centro se atenúan y encogen un poco al desplazar (iOS 17+).
    @ViewBuilder func carouselFade() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTransition(axis: .horizontal) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.55)
                    .scaleEffect(phase.isIdentity ? 1 : 0.93)
            }
        } else {
            self
        }
    }
}

// MARK: - Listas inteligentes
enum SmartList: String, Identifiable {
    case downloads, favorites
    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: return L("Descargadas")
        case .favorites: return L("Favoritos")
        }
    }
    var symbol: String {
        switch self {
        case .downloads: return "arrow.down"
        case .favorites: return "heart.fill"
        }
    }
    /// Índice en `PlaylistStyle.palettes`.
    var palette: Int {
        switch self {
        case .downloads: return 2
        case .favorites: return 0
        }
    }
}

/// Portada de una lista inteligente: degradado de color con el glifo grande.
private struct SmartCover: View {
    let kind: SmartList
    var size: CGFloat?

    var body: some View {
        Rectangle()
            .fill(PlaylistStyle.gradient(kind.palette))
            .overlay(
                Image(systemName: kind.symbol)
                    .font(.system(size: (size ?? 180) * 0.34, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            )
            .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Anillo de puntos
/// Un punto por cada 1/`dots` de la lista: los iluminados son la parte descargada.
struct DotRing: View {
    var lit: Double
    var dots = 72
    var diameter: CGFloat
    var tint: Color

    var body: some View {
        ZStack {
            ForEach(0..<dots, id: \.self) { i in
                let on = Double(i) / Double(dots) < lit
                Circle()
                    .fill(on ? tint : Color.primary.opacity(0.2))
                    .frame(width: on ? 5 : 3.5, height: on ? 5 : 3.5)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(Double(i) / Double(dots) * 360))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Pantalla principal
struct LibraryV11View: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var downloads: DownloadStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var jam: JamService
    @AppStorage("playlistSort") private var sort = "recent"
    @State private var showNew = false
    @State private var newName = ""
    @State private var showImport = false
    @State private var editing: Playlist?

    private let inset: CGFloat = 20

    private static func artists(_ songs: [Song]) -> [ArtistGroup] {
        Dictionary(grouping: songs) { primaryArtist($0.artist) }
            .map { ArtistGroup(name: $0.key, songs: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @AppStorage("playlistOrder") private var orderRaw = ""
    @AppStorage("smartPlacement") private var placement = "playlists"
    @AppStorage("musicOrder") private var musicRaw = ""
    @State private var editingMusic = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showReorder = false

    /// Claves del carrusel en orden (playlists y, si van ahí, Descargadas y Favoritos).
    private var orderedKeys: [String] {
        LibraryOrder.keys(library.userPlaylists, sort: sort, order: LibraryOrder.decode(orderRaw), smartInPlaylists: placement != "music")
    }

    var body: some View {
        // Una sola pasada por redibujado: la lista completa se reutiliza en cabecera y filas.
        let songs = library.allSongs(including: downloads.songs)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    header(songs)
                    PinnedRow()
                    playlistsSection
                    musicSection(songs)
                }
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .themed()
            .toolbar(.hidden, for: .navigationBar)
            .alert(L("Nueva playlist"), isPresented: $showNew) {
                TextField(L("Nombre"), text: $newName)
                Button(L("Crear")) { library.createPlaylist(newName); newName = "" }
                Button(L("Cancelar"), role: .cancel) { newName = "" }
            }
            .sheet(isPresented: $showImport) { ImportView() }
            .sheet(item: $editing) { PlaylistEditor(playlistID: $0.id) }
            .demoRoute(.favorites) { SmartListV11View(kind: .favorites) }
            .miniPlayer()
        }
    }

    // MARK: Cabecera
    private func header(_ songs: [Song]) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Biblioteca")).displayTitle(40)
                Text(summary(songs)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Menu {
                Button { showNew = true } label: { Label("Nueva playlist", systemImage: "plus.rectangle.on.rectangle") }
                Button { showImport = true } label: { Label("Importar de Apple Music", systemImage: "square.and.arrow.down") }
                Divider()
                Button { jam.showSheet = true } label: { Label("Jam con amigos", systemImage: "person.3") }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(ThemeSurface(radius: 22))
                    .clipShape(Circle())
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel(L("Añadir playlist"))
        }
        .padding(.horizontal, inset)
    }

    private func summary(_ songs: [Song]) -> String {
        let n = songs.count
        let off = downloads.songs.count
        if n == 0 { return L("Aún no has guardado nada") }
        let base = songCount(n)
        return off > 0 ? L("{0} · {1} sin conexión", base, off) : base
    }

    // MARK: Playlists
    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Playlists")).displayTitle(24)
                Spacer()
                if library.userPlaylists.count > 1 {
                    Menu {
                        Picker(L("Ordenar por"), selection: $sort) {
                            Label("Añadidas recientemente", systemImage: "clock").tag("recent")
                            Label("Nombre (A-Z)", systemImage: "textformat").tag("name")
                            Label("Nombre (Z-A)", systemImage: "textformat").tag("nameDesc")
                            Label("Nº de canciones", systemImage: "number").tag("count")
                        }
                        Divider()
                        Button { showReorder = true } label: {
                            Label(L("A mano…"), systemImage: sort == "custom" ? "checkmark" : "line.3.horizontal")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("Ordenar playlists"))
                }
                NavigationLink { PlaylistsListView() } label: {
                    Text(L("Ver todas")).font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, inset)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    if let state = jam.jam { jamTile(state) }
                    let byID = Dictionary(library.playlists.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
                    ForEach(orderedKeys, id: \.self) { key in
                        switch key {
                        case LibraryOrder.downloads: smartTile(.downloads, count: downloads.songs.count)
                        case LibraryOrder.favorites: smartTile(.favorites, count: library.favorites.count)
                        default: if let p = byID[key] { playlistCard(p) }
                        }
                    }

                    newTile
                }
                .carouselLayout()
                .padding(.horizontal, carouselUsesMargins ? 0 : inset)
            }
            .carouselScroll(inset: inset)

            if library.userPlaylists.isEmpty {
                Text(L("Crea una playlist con + o tráete las tuyas desde Apple Music."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal, inset)
            }
        }
        .sheet(isPresented: $showReorder) { ReorderPlaylistsView() }
    }

    private func playlistCard(_ p: Playlist) -> some View {
                        NavigationLink { PlaylistV11View(playlistID: p.id) } label: {
                            PlaylistCardV11(playlist: p)
                        }
                        .buttonStyle(TactileButtonStyle())
                        .carouselFade()
                        .contextMenu {
                            Button { if let f = p.songs.first { player.play(f, in: p.songs) } } label: {
                                Label("Reproducir", systemImage: "play.fill")
                            }
                            Button { let s = p.songs.shuffled(); if let f = s.first { player.play(f, in: s) } } label: {
                                Label("Aleatorio", systemImage: "shuffle")
                            }
                            Button { editing = p } label: { Label("Editar", systemImage: "pencil") }
                        }
    }

    private func smartTile(_ kind: SmartList, count: Int) -> some View {
        NavigationLink { SmartListV11View(kind: kind) } label: {
            VStack(alignment: .leading, spacing: 10) {
                SmartCover(kind: kind, size: PlaylistCardV11.side)
                    .frame(width: PlaylistCardV11.side, height: PlaylistCardV11.side)
                    .clipShape(RoundedRectangle(cornerRadius: PlaylistCardV11.corner, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 16, y: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.callout.bold()).lineLimit(1)
                    Text(songCount(count))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: PlaylistCardV11.side, alignment: .leading)
            .foregroundStyle(.primary)
        }
        .buttonStyle(TactileButtonStyle())
        .carouselFade()
    }

    /// El Jam en curso, primero del carrusel mientras dure.
    private func jamTile(_ state: JamState) -> some View {
        Button { jam.showSheet = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: PlaylistCardV11.corner, style: .continuous)
                    .fill(PlaylistStyle.gradient(1))
                    .frame(width: PlaylistCardV11.side, height: PlaylistCardV11.side)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.fill").font(.system(size: 48, weight: .bold))
                            Text(state.code).font(.system(size: 20, weight: .bold, design: .monospaced)).tracking(3)
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 16, y: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.name).font(.callout.bold()).lineLimit(1)
                    Text(jam.isActive ? L("Jam en directo · {0}", state.members.count) : L("Jam sin conexión"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: PlaylistCardV11.side, alignment: .leading)
            .foregroundStyle(.primary)
        }
        .buttonStyle(TactileButtonStyle())
        .carouselFade()
        .accessibilityLabel(L("Jam {0}, código {1}", state.name, state.code))
    }

    private var newTile: some View {
        Button { showNew = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: PlaylistCardV11.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [5, 6]))
                    .frame(width: PlaylistCardV11.side, height: PlaylistCardV11.side)
                    .overlay(Image(systemName: "plus").font(.system(size: 30, weight: .medium)).foregroundStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Nueva playlist")).font(.callout.bold())
                    Text(L("Vacía o importada")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: PlaylistCardV11.side, alignment: .leading)
            .foregroundStyle(.primary)
        }
        .buttonStyle(TactileButtonStyle())
        .carouselFade()
        .contextMenu {
            Button { showNew = true } label: { Label("Nueva playlist", systemImage: "plus.rectangle.on.rectangle") }
            Button { showImport = true } label: { Label("Importar de Apple Music", systemImage: "square.and.arrow.down") }
            Button { jam.showSheet = true } label: { Label("Jam con amigos", systemImage: "person.3") }
        }
    }

    // MARK: El resto de la música
    /// «Tu música» en el orden de `musicOrder`. Mantener pulsada una carpeta entra en el modo edición (como la
    /// pantalla de inicio): las filas tiemblan y se arrastran; «Hecho» sale. Lo pidió Toxbox. Igual en Android.
    private func musicSection(_ songs: [Song]) -> some View {
        let order = MusicOrder.decode(musicRaw).filter { placement == "music" || ($0 != "downloads" && $0 != "favorites") }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline) {
                Text(L("Tu música")).displayTitle(24)
                Spacer()
                if editingMusic { Button(L("Hecho")) { withAnimation(.uiEaseOut(0.25)) { editingMusic = false } }.font(.body.weight(.semibold)) }
            }
            .padding(.horizontal, inset)
            .padding(.bottom, editingMusic ? 0 : 8)
            if editingMusic {
                Text(L("Arrastra las carpetas para cambiar el orden.")).font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, inset).padding(.bottom, 8)
            }
            VStack(spacing: 0) {
                ForEach(Array(order.enumerated()), id: \.element) { i, key in
                    musicRow(key, songs, last: i == order.count - 1)
                        .rotationEffect(.degrees(editingMusic && !reduceMotion ? (i % 2 == 0 ? 0.45 : -0.45) : 0))
                        .animation(editingMusic && !reduceMotion ? .easeInOut(duration: 0.32).repeatForever(autoreverses: true) : .default, value: editingMusic)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            withAnimation(.uiEaseOut(0.25)) { editingMusic = true }
                        })
                        .draggable(key) { Text(key).hidden() }
                        .dropDestination(for: String.self) { items, _ in
                            guard editingMusic, let from = items.first, from != key else { return false }
                            var all = MusicOrder.decode(musicRaw)
                            all.removeAll { $0 == from }
                            all.insert(from, at: all.firstIndex(of: key) ?? all.endIndex)
                            withAnimation(.uiEaseOut(0.25)) { musicRaw = all.joined(separator: ",") }
                            return true
                        }
                }
            }
            .padding(.horizontal, inset)
        }
    }

    @ViewBuilder private func musicRow(_ key: String, _ songs: [Song], last: Bool) -> some View {
        switch key {
        case "downloads":
            LibraryLinkRow(title: SmartList.downloads.title, count: downloads.songs.count, symbol: "arrow.down.circle", last: last, editing: editingMusic) {
                SmartListV11View(kind: .downloads)
            }
        case "favorites":
            LibraryLinkRow(title: SmartList.favorites.title, count: library.favorites.count, symbol: "heart", last: last, editing: editingMusic) {
                SmartListV11View(kind: .favorites)
            }
        case "albums":
            LibraryLinkRow(title: L("Tus álbumes"), count: library.albums.count, symbol: "square.stack", last: last, editing: editingMusic) { AlbumsListView() }
        case "songs":
            LibraryLinkRow(title: L("Canciones"), count: songs.count, symbol: "music.note", last: last, editing: editingMusic) {
                SongListV11View(title: L("Canciones"), songs: songs.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                })
            }
        case "artists":
            LibraryLinkRow(title: L("Artistas"), count: Set(songs.map { primaryArtist($0.artist) }).count, symbol: "music.mic", last: last, editing: editingMusic) {
                ArtistsView(artists: Self.artists(songs))
            }
        case "recents":
            LibraryLinkRow(title: L("Recientes"), count: library.recents.count, symbol: "clock", last: last, editing: editingMusic) {
                SongListV11View(title: L("Recientes"), songs: library.recents)
            }
        default:
            LibraryLinkRow(title: L("Estadísticas"), count: PlayStats.shared.plays.filter { $0.at >= PlayStats.since(.month) }.count, symbol: "chart.bar", last: last, editing: editingMusic) {
                StatsView()
            }
        }
    }
}

/// Fila grande de navegación: título, recuento y chevron, separadas por líneas finas.
private struct LibraryLinkRow<Destination: View>: View {
    let title: String
    let count: Int
    let symbol: String
    var last = false
    /// Modo edición de «Tu música»: sin navegar, con el asa en vez del chevron.
    var editing = false
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        if editing {
            content.accessibilityHint(L("Arrastra para cambiar el orden"))
        } else {
            NavigationLink { LazyDestination(build: destination) } label: { content }
                .buttonStyle(RowHighlightStyle())
        }
    }

    private var content: some View {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(ThemeSurface(radius: 18))
                        .clipShape(Circle())
                    Text(title).font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: editing ? "line.3.horizontal" : "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
                if !last { Divider() }
            }
            .foregroundStyle(.primary)
    }
}

/// Construye el destino sólo cuando se abre: `NavigationLink` crea su destino al dibujar la fila.
private struct LazyDestination<V: View>: View {
    let build: () -> V
    var body: some View { build() }
}

/// Tarjeta de una playlist del usuario.
struct PlaylistCardV11: View {
    static let side: CGFloat = 176
    static let corner: CGFloat = Tokens.Radius.playlistCard
    let playlist: Playlist
    @EnvironmentObject var downloads: DownloadStore

    var body: some View {
        let offline = playlist.songs.filter { downloads.isDownloaded($0) }.count
        VStack(alignment: .leading, spacing: 10) {
            PlaylistCover(playlist: playlist, size: Self.side, radius: Self.corner)
                .shadow(color: .black.opacity(0.14), radius: 16, y: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).font(.callout.bold()).lineLimit(1)
                HStack(spacing: 4) {
                    Text(songCount(playlist.songs.count))
                    if offline > 0 && offline == playlist.songs.count {
                        Image(systemName: "arrow.down.circle.fill").imageScale(.small)
                            .accessibilityLabel(L("Descargada"))
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: Self.side, alignment: .leading)
        .foregroundStyle(.primary)
    }
}

// MARK: - Botones por canción
/// Estado de descarga de una canción como botón circular: flecha → anillo de progreso → check.
struct DownloadGlyphButton: View {
    let song: Song
    @EnvironmentObject var downloads: DownloadStore
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    var body: some View {
        let accent = (AppTheme(rawValue: themeID) ?? .glass).accent
        let done = downloads.isDownloaded(song)
        let busy = downloads.inProgress.contains(song.id)
        let failed = downloads.failed.contains(song.id)
        let pct = downloads.progress[song.id] ?? 0

        Button {
            if !done && !busy { Task { await downloads.download(song) } }
        } label: {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                } else if busy {
                    Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(0.04, pct))
                        .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold)).foregroundStyle(accent)
                } else if failed {
                    Image(systemName: "arrow.clockwise.circle").foregroundStyle(.red)
                } else {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 24, weight: .regular))
            .frame(width: 24, height: 24)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .animation(.uiEaseOut(0.2), value: done)
        }
        .buttonStyle(TactileButtonStyle())
        .disabled(done || busy)
        .accessibilityLabel(done ? L("Descargada") : busy ? L("Descargando") : failed ? L("Reintentar descarga") : L("Descargar"))
    }
}

struct FavoriteGlyphButton: View {
    let song: Song
    @EnvironmentObject var library: Library
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    var body: some View {
        let accent = (AppTheme(rawValue: themeID) ?? .glass).accent
        let fav = library.isFavorite(song)
        Button { library.toggleFavorite(song) } label: {
            Image(systemName: fav ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(fav ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                .scaleEffect(fav ? 1.08 : 1)
                .animation(.uiEaseOut(0.2), value: fav)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel(fav ? L("Quitar de favoritos") : L("Añadir a favoritos"))
    }
}

/// Fila de canción de la biblioteca 1.1: tocar reproduce; a la derecha, favorito y descarga.
struct SongRowV11: View {
    let song: Song
    let context: [Song]
    /// Resultados de búsqueda: «⋯» (menú al primer toque) en vez del botón de descarga, que está en el menú.
    var more = false
    @EnvironmentObject var player: Player

    var body: some View {
        let isCurrent = player.current?.id == song.id
        HStack(spacing: 4) {
            Button { player.play(song, in: context) } label: {
                HStack(spacing: 12) {
                    CoverImage(url: song.thumb(256))
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.artworkSmall, style: .continuous))
                        .overlay {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: Tokens.Radius.artworkSmall, style: .continuous).fill(.black.opacity(0.38))
                                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                    .foregroundStyle(.white)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.callout.weight(isCurrent ? .bold : .semibold)).lineLimit(1)
                        Text(song.artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TactileButtonStyle())

            FavoriteGlyphButton(song: song)
            if more {
                Menu { SongMenuItems(song: song) } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(L("Más opciones de {0}", song.title))
            } else {
                DownloadGlyphButton(song: song)
            }
        }
        .contextMenu { SongMenuItems(song: song) }
    }
}

// MARK: - Cabecera de colección
/// Portada circular con el anillo de puntos, título grande y datos.
private struct CollectionHeader<Cover: View>: View {
    let title: String
    let songs: [Song]
    var ringLit: Double
    @ViewBuilder let cover: (CGFloat) -> Cover
    @EnvironmentObject var downloads: DownloadStore
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    var body: some View {
        let accent = (AppTheme(rawValue: themeID) ?? .glass).accent
        let ring: CGFloat = 268
        let artwork = ring - 40
        let offline = songs.filter { downloads.isDownloaded($0) }.count

        VStack(spacing: 18) {
            ZStack {
                DotRing(lit: ringLit, diameter: ring - 6, tint: accent)
                cover(artwork)
                    .frame(width: artwork, height: artwork)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 22, y: 12)
            }
            .frame(width: ring, height: ring)
            .padding(.top, 6)

            VStack(spacing: 6) {
                Text(title).displayTitle(30).multilineTextAlignment(.center).lineLimit(2)
                Text(subtitle(offline: offline))
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func subtitle(offline: Int) -> String {
        let n = songs.count
        let base = songCount(n)
        return offline > 0 ? L("{0} · {1} sin conexión", base, offline) : base
    }
}

// MARK: - Filtros
private enum SongFilter: String, CaseIterable, Identifiable {
    case all, downloaded, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L("Todas")
        case .downloaded: return L("Descargadas")
        case .favorites: return L("Favoritas")
        }
    }
}

private struct FilterChips: View {
    @Binding var selection: SongFilter
    let counts: [SongFilter: Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SongFilter.allCases) { f in
                let on = selection == f
                Button {
                    withAnimation(.uiEaseOut(0.22)) { selection = f }
                } label: {
                    HStack(spacing: 5) {
                        Text(f.title)
                        if f != .all { Text("\(counts[f] ?? 0)").monospacedDigit().opacity(0.7) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
                    .background(
                        Capsule().fill(on ? Color.primary : Color.clear)
                            .background(ThemeSurface(radius: 18).opacity(on ? 0 : 1))
                            .clipShape(Capsule())
                    )
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Detalle común (playlists y listas inteligentes)
private struct CollectionDetailV11<Cover: View>: View {
    let title: String
    let songs: [Song]
    var filters = true
    /// «Descargar todo» (id de la playlist o "favorites"): sólo en playlists y Favoritos, nil en el resto.
    var bulkOwner: String? = nil
    var emptyText = L("Todavía no hay nada aquí")
    var onRemove: ((Song) -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    /// Fijar arriba en Biblioteca e Inicio (nil = sin el botón).
    var pinned: Bool? = nil
    var onPin: (() -> Void)? = nil
    /// Playlist importada con canciones sin añadir: fila «Sin añadir» encima de las canciones.
    var pendingFor: UUID? = nil
    @ViewBuilder let cover: (CGFloat) -> Cover

    @EnvironmentObject var downloads: DownloadStore
    @EnvironmentObject var library: Library
    @State private var filter: SongFilter = .all

    private var visible: [Song] {
        switch filter {
        case .all: return songs
        case .downloaded: return songs.filter { downloads.isDownloaded($0) }
        case .favorites: return songs.filter { library.isFavorite($0) }
        }
    }

    private var offlineCount: Int { songs.filter { downloads.isDownloaded($0) }.count }

    var body: some View {
        let lit = songs.isEmpty ? 0 : Double(offlineCount) / Double(songs.count)
        List {
            Section {
                VStack(spacing: 20) {
                    CollectionHeader(title: title, songs: songs, ringLit: lit, cover: cover)
                    PlayShuffleBar(songs: visible.isEmpty ? songs : visible)
                    if let bulkOwner { DownloadAllButton(owner: bulkOwner, songs: songs) }
                    if filters && !songs.isEmpty {
                        FilterChips(selection: $filter, counts: [
                            .downloaded: offlineCount,
                            .favorites: songs.filter { library.isFavorite($0) }.count
                        ])
                    }
                }
                .padding(.horizontal, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            }

            if let pendingFor {
                Section { PendingImportRow(playlistID: pendingFor) }
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(visible) { song in
                    SongRowV11(song: song, context: visible)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.primary.opacity(0.08))
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if let onRemove {
                                Button(role: .destructive) { onRemove(song) } label: {
                                    Label("Quitar", systemImage: "minus.circle")
                                }
                            }
                        }
                }
            } footer: {
                if visible.isEmpty { emptyMessage.padding(.top, 8) }
            }
        }
        .listStyle(.plain)
        .themed()
        .navigationBarTitleDisplayMode(.inline)
        // Las filas se deslizan para quitar: deslizar a la izquierda no cambia de pestaña aquí.
        .onAppear { if onRemove != nil { TabSwipe.rowSwipeScreens += 1 } }
        .onDisappear { if onRemove != nil { TabSwipe.rowSwipeScreens -= 1 } }
        .toolbar {
            if let onPin, let pinned {
                Button(action: onPin) { Image(systemName: pinned ? "pin.fill" : "pin") }
                    .accessibilityLabel(pinned ? L("Soltar de arriba") : L("Fijar arriba"))
            }
            if let onEdit {
                Button(action: onEdit) { Image(systemName: "pencil.circle") }
                    .accessibilityLabel(L("Editar playlist"))
            }
        }
        .miniPlayer()
    }

    @ViewBuilder private var emptyMessage: some View {
        let text: String = {
            if songs.isEmpty { return emptyText }
            switch filter {
            case .downloaded: return L("Ninguna canción de esta lista está descargada.")
            case .favorites: return L("Aún no has marcado favoritas aquí.")
            case .all: return emptyText
            }
        }()
        Text(text).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }
}

/// «Descargar todo» de una lista (playlist, Favoritos o álbum): pendiente → progreso (Pausar / Cancelar) →
/// en pausa (Reanudar / Cancelar) → completa (tocar ofrece quitar lo descargado, con confirmación).
/// Cancelar no borra nada: lo ya descargado se queda.
struct DownloadAllButton: View {
    /// Lista dueña de la descarga (id de la playlist, "favorites" o el browseId del álbum).
    let owner: String
    let songs: [Song]
    var title: String? = nil
    /// Al empezar a descargar (el álbum se guarda en «Tus álbumes»).
    var onStart: (() -> Void)? = nil
    @EnvironmentObject var downloads: DownloadStore
    @State private var confirmRemove = false

    var body: some View {
        let total = songs.count
        let done = songs.filter { downloads.isDownloaded($0) }.count
        // Sólo «Descargando» en la lista que lo pidió, aunque otras compartan canciones.
        let running = downloads.bulk[owner] != nil
        let complete = total > 0 && done == total
        let paused = !complete && downloads.paused.contains(owner)

        HStack(spacing: 6) {
            mainButton(total: total, done: done, running: running, paused: paused, complete: complete)
            if running || paused {
                Button(L("Cancelar")) { downloads.cancelBulk(owner) }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
                    .accessibilityHint(L("Deja de descargar; lo ya descargado se queda"))
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.uiEaseOut(0.2), value: running)
        .animation(.uiEaseOut(0.2), value: paused)
        .confirmationDialog(title.map { L("¿Quitar las descargas de «{0}»?", $0) } ?? L("¿Quitar las descargas?"), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(L("Quitar {0}", songCount(done)), role: .destructive) {
                songs.forEach { downloads.remove($0) }
            }
            Button(L("Cancelar"), role: .cancel) {}
        } message: {
            Text(L("Dejarán de estar disponibles sin conexión, también en otras listas que las tengan."))
        }
    }

    private func mainButton(total: Int, done: Int, running: Bool, paused: Bool, complete: Bool) -> some View {
        Button {
            if running { downloads.pauseBulk(owner) }
            else if complete { confirmRemove = true }
            else { downloads.startBulk(songs, owner: owner); onStart?() }
        } label: {
            HStack(spacing: 8) {
                if running {
                    ProgressView().controlSize(.small)
                    Text(L("{0} de {1} · Pausar", done, total)).monospacedDigit()
                } else if paused {
                    Image(systemName: "play.circle")
                    Text(L("Reanudar · {0} de {1}", done, total)).monospacedDigit()
                } else if complete {
                    Image(systemName: "checkmark.circle.fill")
                    Text(L("Disponible sin conexión"))
                } else {
                    Image(systemName: "arrow.down.circle")
                    Text(done > 0 ? L("Descargar las {0} que faltan", total - done) : L("Descargar todo"))
                }
            }
        }
        .buttonStyle(PillButtonStyle(prominent: false))
        .disabled(total == 0)
        .accessibilityHint(running ? L("Pausa la descarga de la lista") : paused ? L("Sigue con las que faltan") : complete ? L("Ofrece quitar las descargas") : "")
    }
}

// MARK: - Pantallas de destino
/// Playlist del usuario con filtros, botones por canción y descarga completa.
struct PlaylistV11View: View {
    let playlistID: UUID
    @EnvironmentObject var library: Library
    @State private var editing = false

    var body: some View {
        if let p = library.playlists.first(where: { $0.id == playlistID }) {
            CollectionDetailV11(
                title: p.name,
                songs: p.songs,
                bulkOwner: p.id.uuidString,
                emptyText: L("Mantén pulsada una canción en Buscar o Inicio para añadirla."),
                onRemove: { library.remove(songID: $0.id, from: p.id) },
                onEdit: { editing = true },
                pinned: p.pinned ?? false,
                onPin: {
                    if let i = library.playlists.firstIndex(where: { $0.id == p.id }) {
                        library.playlists[i].pinned = (p.pinned ?? false) ? nil : true
                    }
                },
                pendingFor: p.id,
                cover: { side in PlaylistCover(playlist: p, size: side, radius: 0) }
            )
            .sheet(isPresented: $editing) { PlaylistEditor(playlistID: p.id) }
        }
    }
}

/// Descargadas o Favoritos como si fueran playlists.
struct SmartListV11View: View {
    let kind: SmartList
    @EnvironmentObject var library: Library
    @EnvironmentObject var downloads: DownloadStore

    var body: some View {
        switch kind {
        case .downloads:
            CollectionDetailV11(
                title: kind.title,
                songs: downloads.songs,
                filters: false,
                emptyText: L("Descarga canciones con la flecha de cada fila o con «Descargar todo» en una playlist."),
                onRemove: { downloads.remove($0) },
                cover: { side in SmartCover(kind: kind, size: side) }
            )
        case .favorites:
            CollectionDetailV11(
                title: kind.title,
                songs: library.favorites,
                filters: false,
                bulkOwner: "favorites",
                emptyText: L("Toca el corazón de una canción para guardarla aquí."),
                onRemove: { library.toggleFavorite($0) },
                cover: { side in SmartCover(kind: kind, size: side) }
            )
        }
    }
}

/// Lista plana (Canciones, Recientes) con los mismos botones por canción.
struct SongListV11View: View {
    let title: String
    let songs: [Song]

    var body: some View {
        CollectionDetailV11(
            title: title,
            songs: songs,
            emptyText: L("Todavía no hay nada aquí"),
            cover: { side in
                CoverImage(url: songs.first?.thumb(Int(side * 3)))
            }
        )
    }
}

// MARK: - Ordenar playlists a mano
/// Orden propio del carrusel: se arrastran las filas (también Descargadas y Favoritos si están en
/// Playlists). Al mover algo, el orden pasa a ser «A mano». Igual que ReorderPlaylistsScreen en Android.
struct ReorderPlaylistsView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var downloads: DownloadStore
    @AppStorage("playlistSort") private var sort = "recent"
    @AppStorage("playlistOrder") private var orderRaw = ""
    @AppStorage("smartPlacement") private var placement = "playlists"
    @Environment(\.dismiss) private var dismiss
    @State private var keys: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section(L("Ordenar por")) {
                    ForEach([("recent", L("Añadidas recientemente")), ("name", L("Nombre (A-Z)")), ("nameDesc", L("Nombre (Z-A)")), ("count", L("Nº de canciones")), ("custom", L("A mano"))], id: \.0) { item in
                        Button {
                            sort = item.0
                            keys = LibraryOrder.keys(library.userPlaylists, sort: sort, order: LibraryOrder.decode(orderRaw), smartInPlaylists: placement != "music")
                        } label: {
                            HStack {
                                Text(item.1).foregroundStyle(.primary)
                                Spacer()
                                if sort == item.0 { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
                .glassRow()
                Section {
                    ForEach(keys, id: \.self) { key in row(key) }
                        .onMove { from, to in
                            keys.move(fromOffsets: from, toOffset: to)
                            orderRaw = keys.joined(separator: "\n")
                            sort = "custom"
                        }
                } footer: {
                    Text(L("Arrastra para cambiar el orden del carrusel. Al mover algo, Playlists se ordena «A mano»."))
                }
                .glassRow()
            }
            .environment(\.editMode, .constant(.active))
            .themed()
            .navigationTitle(L("Editar playlists"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Hecho")) { dismiss() } } }
            .onAppear {
                keys = LibraryOrder.keys(library.userPlaylists, sort: sort, order: LibraryOrder.decode(orderRaw), smartInPlaylists: placement != "music")
            }
        }
    }

    @ViewBuilder private func row(_ key: String) -> some View {
        HStack(spacing: 12) {
            switch key {
            case LibraryOrder.downloads, LibraryOrder.favorites:
                let kind: SmartList = key == LibraryOrder.downloads ? .downloads : .favorites
                SmartCover(kind: kind, size: 44)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.body.weight(.medium))
                    Text(songCount(kind == .downloads ? downloads.songs.count : library.favorites.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
            default:
                if let p = library.playlists.first(where: { $0.id.uuidString == key }) {
                    PlaylistCover(playlist: p, size: 44, radius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.body.weight(.medium)).lineLimit(1)
                        Text(songCount(p.songs.count)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Fijados (Fase 3.3)
/// Los álbumes y playlists con la chincheta, arriba en Biblioteca e Inicio; mantener pulsado suelta. Igual que
/// `PinnedRow` en Android.
struct PinnedRow: View {
    @EnvironmentObject var library: Library

    var body: some View {
        let pinned = library.playlists.filter { $0.pinned == true }
        if !pinned.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Fijados")).font(.title2.bold()).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(pinned) { p in
                            NavigationLink(value: p.id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    PlaylistCover(playlist: p, size: 132)
                                    Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(p.album.map { [$0.artist, $0.year].compactMap { $0 }.joined(separator: " · ") } ?? songCount(p.songs.count))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 132, alignment: .leading)
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(TactileButtonStyle())
                            .contextMenu {
                                Button { library.playlists.firstIndex(where: { $0.id == p.id }).map { library.playlists[$0].pinned = nil } } label: {
                                    Label("Soltar de arriba", systemImage: "pin.slash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}
