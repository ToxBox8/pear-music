import Foundation

// MARK: - Modo demo con el catálogo del patrocinador (tráiler v2, 4-11-2026)
// Llena Inicio, la búsqueda, la página de artista, Biblioteca (Fijados + Tu música) y Descargas sólo con canciones de
// Michael Bennet, sin red, para grabar el tráiler y las capturas. Nunca está en la app pública:
// - sólo existe en Jiyu Dev (`CHANNEL_DEV`) y en las compilaciones Debug (las del simulador de la CI), y
// - hay que encenderlo: `-demoCatalog YES` al lanzar (capturas) o Administración › «Catálogo del patrocinador».
// Las portadas (`demo-*.jpg`) se excluyen de la compilación Release en project.yml. Mismo catálogo que
// `DemoCatalog.kt` en Android. Todas con su portada; la foto del artista es provisional (recorte de la de M.B On This).
enum DemoCatalog {
    #if DEBUG || CHANNEL_DEV
    static let allowed = true
    #else
    static let allowed = false
    #endif

    /// Se lee una vez al abrir: cambiarlo en Administración se aplica al volver a abrir la app.
    static let isActive: Bool = allowed && UserDefaults.standard.bool(forKey: "demoCatalog")

    static let artistName = "Michael Bennet"
    static let artist = RemoteArtist(id: "UCdemo-michael-bennet", name: artistName, subtitle: "Artista", thumbnail: cover("artista"))

    private static func cover(_ name: String) -> URL? { Bundle.main.url(forResource: "demo-" + name, withExtension: "jpg") }

    /// Las ocho canciones con portada (MARCA/patrocinador/portadas/, renombradas por Toxbox el 4-11). DOND va primero:
    /// su portada azul tiñe el fondo Cristal sin acercarse al violeta antiguo. Los ids no son de YouTube: no suenan.
    static let songs = [
        Song(id: "demo-mb-dond", title: "DOND", artist: artistName, thumbnail: cover("dond")),
        Song(id: "demo-mb-rockstar", title: "ROCKSTAR", artist: artistName, thumbnail: cover("rockstar")),
        Song(id: "demo-mb-me-matas", title: "ME MATAS", artist: artistName, thumbnail: cover("me-matas")),
        Song(id: "demo-mb-simulation", title: "SIMULATION", artist: artistName, thumbnail: cover("simulation")),
        Song(id: "demo-mb-flipando", title: "FLIPANDO", artist: artistName, thumbnail: cover("flipando")),
        Song(id: "demo-mb-genesis", title: "GENESIS", artist: artistName, thumbnail: cover("genesis")),
        Song(id: "demo-mb-mb-on-this", title: "M.B On This", artist: artistName, thumbnail: cover("mb-on-this")),
        Song(id: "demo-mb-left-me-2-die", title: "LEFT ME 2 DIE", artist: artistName, thumbnail: cover("left-me-2-die")),
    ]

    /// Cada canción como single (no sabemos de qué álbum es cada una, así que no se inventan álbumes).
    static let singles: [RemoteCollection] = songs.map {
        RemoteCollection(id: "MPREb_" + $0.id, title: $0.title, subtitle: "Single • \($0.artist)", thumbnail: $0.thumbnail)
    }

    static func home() -> [HomeShelf] {
        [
            HomeShelf(title: "Selecciones rápidas", items: songs.map { .song($0) }),
            HomeShelf(title: "Singles y EP", items: singles.map { .collection($0) }),
            HomeShelf(title: "Vuelve a escucharlo", items: songs.reversed().map { .song($0) }),
        ]
    }

    /// Coincide con «Michael Bennet» (desde la primera letra) o con el título de una canción.
    static func search(_ query: String) -> SearchResults {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return SearchResults() }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        if fold(artistName).hasPrefix(q)  {
            return SearchResults(songs: songs, albums: singles, artists: [artist])
        }
        let hits = songs.filter { fold($0.title).contains(q) }
        return SearchResults(songs: hits, albums: singles.filter { s in hits.contains { $0.title == s.title } }, artists: [])
    }

    static func suggestions(_ query: String) -> [String] {
        let q = query.lowercased()
        return ([artistName] + songs.map(\.title)).filter { $0.lowercased().hasPrefix(q) && !q.isEmpty }
    }

    static func artistPage() -> ArtistPage {
        ArtistPage(name: artistName, thumbnail: artist.thumbnail, songs: songs, albums: [], singles: singles)
    }

    static func collectionSongs(_ c: RemoteCollection) -> [Song] {
        songs.filter { "MPREb_" + $0.id == c.id }
    }

    /// «Para ti»: el resto del catálogo, empezando por la siguiente.
    static func radio(for id: String) -> [Song] {
        guard let i = songs.firstIndex(where: { $0.id == id }) else { return songs }
        return Array(songs[(i + 1)...] + songs[...i])
    }

    /// Biblioteca: las canciones en Favoritos y Recientes, dos playlists (una fijada) y dos singles fijados.
    @MainActor static func seed(_ library: Library) {
        songs.prefix(4).forEach { library.toggleFavorite($0) }
        songs.reversed().forEach { library.markPlayed($0) }
        var lists = [
            Playlist(name: "Michael Bennet esencial", songs: songs, icon: "flame.fill", tint: 0, pinned: true),
            Playlist(name: "Para entrenar", songs: [songs[0], songs[3], songs[2]], icon: "figure.run", tint: 4),
            Playlist(name: "De noche", songs: [songs[1], songs[4]], icon: "moon.stars.fill", tint: 2),
        ]
        for (i, s) in singles.prefix(2).enumerated() {
            lists.append(Playlist(name: s.title, songs: [songs[i]], album: AlbumInfo(browseId: s.id, subtitle: s.subtitle), pinned: true))
        }
        library.playlists = lists
    }
}
