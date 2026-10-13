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
                note("Busca canciones, álbumes o artistas")
            } else if loading && results.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 48)
            } else if failed {
                note("No se pudo buscar. Revisa tu conexión.")
            } else if results.isEmpty && !loading && shownQuery == trimmed {
                note("No hay resultados para «\(trimmed)»")
            } else {
                if !results.artists.isEmpty {
                    resultSection("Artistas") {
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
                    resultSection("Álbumes") {
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
                    resultSection("Canciones") {
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
    subtitle.components(separatedBy: " • ").filter { $0 != "Álbum" && $0 != "Album" && !$0.isEmpty }.joined(separator: " · ")
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
        .accessibilityLabel("Artista \(artist.name)")
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
                }
                .frame(maxWidth: .infinity)

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                } else if let page {
                    if !page.songs.isEmpty {
                        section("Canciones más escuchadas") {
                            LazyVStack(spacing: 0) {
                                ForEach(page.songs) { song in
                                    SongRowV11(song: song, context: page.songs)
                                        .padding(.horizontal, 16).padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    if !page.albums.isEmpty { albumRow("Álbumes", page.albums) }
                    if !page.singles.isEmpty { albumRow("Singles y EP", page.singles) }
                    if page.songs.isEmpty && page.albums.isEmpty && page.singles.isEmpty {
                        Text("Este artista no tiene canciones ni álbumes disponibles.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                } else {
                    Text("No se pudo cargar el artista. Revisa tu conexión.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
        }
        .themed()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if page == nil { page = try? await YTClient.artist(artist) }
            loading = false
        }
        .miniPlayer()
    }

    private func albumRow(_ title: String, _ items: [RemoteCollection]) -> some View {
        section(title) {
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal)
            content()
        }
    }
}
