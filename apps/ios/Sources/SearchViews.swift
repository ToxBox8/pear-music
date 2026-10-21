import SwiftUI

// MARK: - Resultados de búsqueda (los usan Inicio y la pestaña Buscar)

/// Busca mientras se escribe (con una pausa corta para no lanzar una búsqueda por letra) y enseña
/// artistas, álbumes y canciones en secciones separadas. YouTube Music ya ignora mayúsculas y
/// acentos («beyonce» encuentra a Beyoncé).
struct SearchResultsView: View {
    let query: String
    @State private var results = SearchResults()
    @State private var loading = false
    @State private var failed = false
    @State private var shownQuery = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 26) {
            if trimmed.isEmpty {
                note(L("Busca canciones, álbumes o artistas"))
            } else if loading && results.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 48)
            } else if failed {
                note(L("No se pudo buscar. Revisa tu conexión."))
            } else if results.isEmpty && !loading && shownQuery == trimmed {
                note(L("No hay resultados para «{0}»", trimmed))
            } else {
                if !results.artists.isEmpty {
                    resultSection(L("Artistas")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(results.artists) { a in
                                    NavigationLink(value: a) { ArtistCard(artist: a) }
                                        .buttonStyle(TactileButtonStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                if !results.albums.isEmpty {
                    resultSection(L("Álbumes")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(results.albums) { c in
                                    NavigationLink(value: c) { AlbumCard(collection: c) }
                                        .buttonStyle(TactileButtonStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                if !results.songs.isEmpty {
                    resultSection(L("Canciones")) {
                        LazyVStack(spacing: 0) {
                            ForEach(results.songs) { song in
                                SongRowV11(song: song, context: results.songs, more: true)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .opacity(loading && !results.isEmpty ? 0.6 : 1)
        .animation(.uiEaseOut(0.2), value: loading)
        .task(id: trimmed) { await run(trimmed) }
    }

    private func run(_ q: String) async {
        guard !q.isEmpty else { results = SearchResults(); failed = false; shownQuery = ""; return }
        // Espera a que se deje de escribir; si cambia el texto, esta tarea se cancela.
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        loading = true; failed = false
        do {
            let r = try await YTClient.searchAll(q)
            guard !Task.isCancelled else { return }
            results = r
        } catch {
            guard !Task.isCancelled else { return }
            results = SearchResults(); failed = true
        }
        shownQuery = q
        loading = false
    }

    private func note(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.top, 48).padding(.horizontal, 32)
    }

    @ViewBuilder
    private func resultSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal)
            content()
        }
    }
}

/// «Álbum • Beyoncé • 2024» → «Beyoncé · 2024»; los singles y EP conservan el tipo.
func albumLine(_ subtitle: String) -> String {
    subtitle.components(separatedBy: " • ").filter { $0 != "Álbum" && $0 != "Album" && $0 != "Àlbum" && $0 != "Albuma" && !$0.isEmpty }.joined(separator: " · ")
}

/// Tarjeta redonda de artista (resultados de búsqueda y «Puede que también te guste»).
struct ArtistCard: View {
    let artist: RemoteArtist
    var body: some View {
        VStack(spacing: 8) {
            CoverImage(url: artist.thumbnail)
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            Text(artist.name).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .frame(width: 112)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Artista {0}", artist.name))
    }
}

/// Tarjeta de álbum con portada, título y «artista · año».
struct AlbumCard: View {
    let collection: RemoteCollection
    var size: CGFloat = 150
    var showArtist = true
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: collection.thumb(400))
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(collection.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(showArtist ? albumLine(collection.subtitle) : albumYear(collection.subtitle))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: size, alignment: .leading)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }

    /// En la página del artista no hace falta repetir su nombre: «Single · 2024».
    private func albumYear(_ subtitle: String) -> String {
        let parts = subtitle.components(separatedBy: " • ")
        guard parts.count >= 3 else { return albumLine(subtitle) }
        return [parts[0], parts[parts.count - 1]].filter { $0 != "Álbum" }.joined(separator: " · ")
    }
}

// MARK: - Página de artista

struct ArtistView: View {
    let artist: RemoteArtist
    @EnvironmentObject var library: Library
    @State private var page: ArtistPage?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(spacing: 12) {
                    CoverImage(url: page?.thumbnail ?? artist.thumbnail)
                        .frame(width: 180, height: 180)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                    Text(page?.name ?? artist.name).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    if !artist.subtitle.isEmpty {
                        Text(artist.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let songs = page?.songs, !songs.isEmpty {
                        PlayShuffleBar(songs: songs).padding(.horizontal).padding(.top, 4)
                    }
                    // Lo que tienes guardado de este artista (lo que antes se abría desde «Tu música › Artistas»).
                    let name = page?.name ?? artist.name
                    let mine = library.allSongs().filter { primaryArtist($0.artist).caseInsensitiveCompare(name) == .orderedSame }
                    if !mine.isEmpty {
                        NavigationLink { SongListV11View(title: name, songs: mine) } label: {
                            Text(L("En tu biblioteca: {0}", songCount(mine.count))).font(.subheadline.weight(.semibold))
                        }
                        .padding(8)
                    }
                }
                .frame(maxWidth: .infinity)

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                } else if let page {
                    if !page.songs.isEmpty {
                        section(L("Canciones más escuchadas")) {
                            LazyVStack(spacing: 0) {
                                ForEach(page.songs) { song in
                                    SongRowV11(song: song, context: page.songs)
                                        .padding(.horizontal, 16).padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    if !page.albums.isEmpty { albumRow(L("Álbumes"), page.albums, kind: .album, page: page) }
                    if !page.singles.isEmpty { albumRow(L("Singles y EP"), page.singles, kind: .single, page: page) }
                    if page.songs.isEmpty && page.albums.isEmpty && page.singles.isEmpty {
                        Text(L("Este artista no tiene canciones ni álbumes disponibles."))
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                } else {
                    Text(L("No se pudo cargar el artista. Revisa tu conexión."))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
        }
        .themed()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: DiscographyRoute.self) { DiscographyView(page: $0.page, kind: $0.kind) }
        .task {
            if page == nil { page = try? await YTClient.artist(artist) }
            loading = false
        }
        .miniPlayer()
    }

    private func albumRow(_ title: String, _ items: [RemoteCollection], kind: Discography.Kind, page: ArtistPage) -> some View {
        section(title, trailing: {
            // «Ver todo»: la discografía completa (YouTube Music + MusicBrainz), siempre: el carrusel nunca la trae entera.
            // Por valor, como los álbumes: mezclar un enlace con vista de destino y enlaces por valor hacía que, al
            // abrir un álbum desde aquí, la pila se rehiciera y «Ver todo» se volviera a abrir (1.10 de x.1.1).
            NavigationLink(value: DiscographyRoute(page: page, kind: kind)) { Text(L("Ver todo")) }
                .accessibilityLabel(L("Ver todos: {0}", title))
        }) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { c in
                        NavigationLink(value: c) { AlbumCard(collection: c, showArtist: false) }
                            .buttonStyle(TactileButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        section(title, trailing: { EmptyView() }, content: content)
    }

    @ViewBuilder
    private func section<T: View, C: View>(_ title: String, @ViewBuilder trailing: () -> T, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                trailing()
            }
            .padding(.horizontal)
            content()
        }
    }
}

/// «Ver todo» de un artista, para empujarlo por valor en la pila.
struct DiscographyRoute: Hashable {
    let page: ArtistPage
    let kind: Discography.Kind
    static func == (a: Self, b: Self) -> Bool { a.page.name == b.page.name && a.kind == b.kind }
    func hash(into h: inout Hasher) { h.combine(page.name); h.combine(kind) }
}

// MARK: - Discografía completa (Fase 3.1), como DiscographyScreen en Android
/// Todos los álbumes o todos los singles y EP: lo de YouTube Music («Ver todo», se puede escuchar) y, detrás, lo que
/// MusicBrainz conoce y YouTube Music no tiene, atenuado como «No disponible para escuchar».
struct DiscographyView: View {
    let page: ArtistPage
    @State var kind: Discography.Kind
    @State private var albums: [Discography.Item]?
    @State private var singles: [Discography.Item]?

    init(page: ArtistPage, kind: Discography.Kind) {
        self.page = page
        _kind = State(initialValue: kind)
    }

    var body: some View {
        let list = kind == .album ? albums : singles
        ScrollView {
            VStack(spacing: 18) {
                Picker(L("Tipo"), selection: $kind) {
                    Text(L("Álbumes")).tag(Discography.Kind.album)
                    Text(L("Singles y EP")).tag(Discography.Kind.single)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                if let list {
                    if list.isEmpty {
                        Text(kind == .album ? L("No hay álbumes.") : L("No hay singles ni EP.")).foregroundStyle(.secondary).padding(.top, 32)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                            ForEach(Array(list.enumerated()), id: \.offset) { _, item in
                                switch item {
                                case .playable(let c):
                                    NavigationLink(value: c) { AlbumCard(collection: c, showArtist: false) }.buttonStyle(TactileButtonStyle())
                                case .missing(let r):
                                    MissingAlbumCard(release: r)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    ProgressView().padding(.top, 32)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle(page.name)
        .navigationBarTitleDisplayMode(.inline)
        .themed()
        .task {
            var ytAlbums = page.albums
            var ytSingles = page.singles
            if let ref = page.albumsMore, let all = try? await YTClient.discography(ref, artist: page.name) { ytAlbums = all }
            if let ref = page.singlesMore, let all = try? await YTClient.discography(ref, artist: page.name) { ytSingles = all }
            // Primero lo de YouTube Music (rápido); luego se completa con MusicBrainz (1 petición por segundo).
            albums = ytAlbums.map(Discography.Item.playable)
            singles = ytSingles.map(Discography.Item.playable)
            let mb = await Discography.musicBrainz(page.name) ?? []
            albums = Discography.merge(ytAlbums, mb, kind: .album)
            singles = Discography.merge(ytSingles, mb, kind: .single)
        }
        .miniPlayer()
    }
}

/// Un disco que existe (MusicBrainz) pero no está en YouTube Music: atenuado y sin acción.
private struct MissingAlbumCard: View {
    let release: Discography.MbRelease
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary)
                .frame(width: 150, height: 150)
                .overlay { Image(systemName: "opticaldisc").font(.system(size: 40)).foregroundStyle(.tertiary) }
            Text(release.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text([release.year, L("No disponible para escuchar")].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
