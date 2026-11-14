import SwiftUI

// MARK: - Modo de demostración para las capturas
// `-screenshotScenario <nombre>` (argumento de lanzamiento, llega por UserDefaults) abre la app
// en uno de los estados de `ScreenshotTest` de Android con los mismos datos de ejemplo y sin red:
// 6 canciones, 3 playlists y «Blinding Lights» en pausa en 1:14 de 3:20. La CI (ios.yml) lanza
// cada escenario en el simulador del iPhone 16 y guarda la captura con el mismo nombre.
enum Demo {
    enum Tab: String { case home, reels, library, settings }
    enum Route { case favorites, themePicker, artist, downloads, playlists, folder, artists, manage }

    struct Scenario {
        var theme: AppTheme = .glass
        var deck: DeckStyle = .normal
        var appearance = "light"
        var playing = true
        var tab: Tab = .home
        var route: Route?
        var showPlayer = false
        var showJam = false
        var showImport = false
        var barStyle = "classic"
        var discover = true
        /// Texto ya escrito en el buscador de Inicio (tráiler v2).
        var query = ""
        /// Carpetas de playlists (3.0, bloque 1): Gimnasio (con Pierna dentro) y Viajes, como ScreenshotTest.
        var folders = false
        /// Con la carpeta abierta, la hoja «Mover a…» de su primera playlist.
        var showMove = false
        /// Artistas seguidos (3.0, bloque 1): Tu música › Artistas con «Siguiendo» elegido.
        var artistsFollowing = false
        /// Inicio con «Novedades de tus artistas» (dos con la marca «Nuevo»), sin red.
        var releases = false
        /// Con los tres seguidos de `followed` (sin cambiar de pantalla).
        var followed = false
    }

    /// Los mismos nombres que las PNG de Android (shared/design/compare_shots.py los empareja).
    static let scenarios: [String: Scenario] = [
        "01_biblioteca_cristal": Scenario(tab: .library),
        "02_biblioteca_cristal_oscuro": Scenario(appearance: "dark", tab: .library),
        "03_biblioteca_aire": Scenario(theme: .air, tab: .library),
        "04_biblioteca_neon": Scenario(theme: .neon, tab: .library),
        "05_biblioteca_sistema": Scenario(theme: .plain, tab: .library),
        "06_playlist": Scenario(tab: .library, route: .favorites),
        "07_ajustes": Scenario(tab: .settings),
        "08_temas": Scenario(tab: .settings, route: .themePicker),
        "09_reproductor_normal": Scenario(showPlayer: true),
        "10_reproductor_casete": Scenario(deck: .cassette, showPlayer: true),
        "11_reproductor_vinilo": Scenario(deck: .vinyl, showPlayer: true),
        "12_reproductor_air": Scenario(theme: .air, deck: .air, showPlayer: true),
        "13_reproductor_neon": Scenario(theme: .neon, showPlayer: true),
        "14_jam": Scenario(playing: false, showJam: true),
        "15_importar": Scenario(playing: false, showImport: true),
        // x.1.1 (1.5 y 1.3): con Descubrir oculta y Ajustes arriba quedan dos pestañas; tienen que ir centradas.
        "37_barra_dos_pestanas": Scenario(playing: false, discover: false),
        "38_barra_simpmusic_dos": Scenario(playing: false, barStyle: "simpmusic", discover: false),
        // Carpetas de playlists (3.0, bloque 1).
        "43_carpetas": Scenario(tab: .library, route: .playlists, folders: true),
        "44_carpetas_oscuro": Scenario(appearance: "dark", tab: .library, route: .playlists, folders: true),
        "45_carpeta": Scenario(tab: .library, route: .folder, folders: true),
        "46_mover_a": Scenario(tab: .library, route: .folder, folders: true, showMove: true),
        // Seguir artistas (3.0, bloque 1).
        "47_artistas_siguiendo": Scenario(tab: .library, route: .artists, artistsFollowing: true),
        "48_inicio_novedades": Scenario(playing: false, releases: true),
        // Página del artista (sin shu en «Seguir»: el único shu es Reproducir) y Eliminar de la biblioteca.
        "49_artista_seguir": Scenario(playing: false, route: .artist),
        "50_artista_siguiendo": Scenario(playing: false, route: .artist, followed: true),
        "51_eliminar_biblioteca": Scenario(playing: false, tab: .settings, route: .manage),
        // Tráiler v2 (4-11-2026): con `-demoCatalog YES` (DemoCatalog.swift), todo con canciones de Michael Bennet.
        "v2_01_inicio": Scenario(tab: .home),
        "v2_02_busqueda": Scenario(tab: .home, query: "Michael Bennet"),
        "v2_03_artista": Scenario(tab: .home, route: .artist),
        "v2_04_biblioteca": Scenario(tab: .library),
        "v2_05_descargas": Scenario(tab: .library, route: .downloads),
        "v2_06_reproductor": Scenario(showPlayer: true),
        "v2_07_aire": Scenario(theme: .air, tab: .library),
        "v2_08_neon": Scenario(theme: .neon, tab: .library),
        "v2_09_sistema": Scenario(theme: .plain, tab: .library),
        "v2_10_casete": Scenario(deck: .cassette, showPlayer: true),
        "v2_11_vinilo": Scenario(deck: .vinyl, showPlayer: true),
        "v2_12_air": Scenario(theme: .air, deck: .air, showPlayer: true),
        "v2_13_jam": Scenario(showJam: true),
        "v2_14_importar": Scenario(playing: false, showImport: true),
    ]

    static let current: Scenario? = UserDefaults.standard.string(forKey: "screenshotScenario").flatMap { scenarios[$0] }
    static var isActive: Bool { current != nil }

    static let songs = [
        Song(id: "a1", title: "Blinding Lights", artist: "The Weeknd", thumbnail: nil),
        Song(id: "a2", title: "Levitating", artist: "Dua Lipa", thumbnail: nil),
        Song(id: "a3", title: "Quevedo: Bzrp Music Sessions, Vol. 52", artist: "Bizarrap y Quevedo", thumbnail: nil),
        Song(id: "a4", title: "Flowers", artist: "Miley Cyrus", thumbnail: nil),
        Song(id: "a5", title: "As It Was", artist: "Harry Styles", thumbnail: nil),
        Song(id: "a6", title: "Tití Me Preguntó", artist: "Bad Bunny", thumbnail: nil),
    ]

    /// Ajustes del escenario, antes de que se lea ninguna preferencia.
    static func prepare() {
        guard let s = current else { return }
        let d = UserDefaults.standard
        d.set(s.theme.rawValue, forKey: "theme")
        d.set(s.deck.rawValue, forKey: "deck")
        d.set(s.appearance, forKey: "appearance")
        d.set(true, forKey: "airDeckOffered")
        d.set("home", forKey: "searchPlacement")
        d.set("recent", forKey: "playlistSort")
        d.set("", forKey: "jamName")
        d.set(s.barStyle, forKey: "barStyle")
        d.set(s.discover, forKey: "showDiscover")
    }

    /// Los mismos pasos que `seed()` en ScreenshotTest.kt, en el mismo orden.
    @MainActor static func seed(_ library: Library) {
        songs.prefix(4).forEach { library.toggleFavorite($0) }
        songs.forEach { library.markPlayed($0) }
        library.playlists = [
            Playlist(name: "Para correr", songs: Array(songs.prefix(5)), icon: "figure.run", tint: 3),
            Playlist(name: "Viaje a la playa", songs: Array(songs.dropFirst()), icon: "beach.umbrella.fill", tint: 4),
            Playlist(name: "Noche", songs: Array(songs.prefix(2))),
        ]
        // «Tus álbumes»: los mismos tres álbumes guardados que ScreenshotTest de Android (PARIDAD.md, 14-11-2026).
        let albums = [("After Hours", "The Weeknd", "2020"), ("Un Verano Sin Ti", "Bad Bunny", "2022"),
                      ("Future Nostalgia", "Dua Lipa", "2020")]
        for (i, a) in albums.enumerated() {
            library.playlists.append(Playlist(name: a.0, songs: Array(songs.dropFirst(i).prefix(4)),
                                              album: AlbumInfo(browseId: "MPREb_\(i)", subtitle: "\(a.1) • \(a.2)")))
        }
        // Carpetas (3.0, bloque 1): los mismos pasos que seedFolders() en ScreenshotTest.kt.
        if current?.folders == true {
            library.playlists.append(Playlist(name: "Fuerza", songs: Array(songs.prefix(3)), icon: "dumbbell.fill", tint: 5))
            library.playlists.append(Playlist(name: "Domingo lento", songs: Array(songs.suffix(3)), icon: "moon.stars.fill", tint: 6))
            let gym = library.createFolder("Gimnasio")
            let pierna = library.createFolder("Pierna", in: gym)
            let viajes = library.createFolder("Viajes")
            for (name, folder) in [("Para correr", gym), ("Fuerza", gym), ("Noche", pierna), ("Viaje a la playa", viajes)] {
                if let p = library.playlists.first(where: { $0.name == name }) { library.movePlaylist(p.id, to: folder) }
            }
            folderID = gym
        }
        if current?.artistsFollowing == true || current?.releases == true || current?.followed == true {
            for a in followed.reversed() { library.follow(browseId: a.browseId, name: a.name, thumbnail: nil, since: a.since) }
        }
    }

    /// Los mismos seguidos que `seedFollowed()` en ScreenshotTest.kt (sin foto: las capturas no tienen red).
    static let followed = [
        FollowedArtist(browseId: "UCdemo-bad-bunny", name: "Bad Bunny", since: 1_794_657_600_000),
        FollowedArtist(browseId: "UCdemo-dua-lipa", name: "Dua Lipa", since: 1_793_534_400_000),
        FollowedArtist(browseId: "UCdemo-rosalia", name: "Rosalía", since: 1_791_547_200_000),
    ]

    /// «Novedades de tus artistas» del escenario 48: las dos primeras, «Nuevo». Las mismas que `releasePicks` en Android.
    static let releasePicks: [ReleasePick] = [
        ("MPREb_r1", "Verano 26", "Álbum • Bad Bunny • 2026", true),
        ("MPREb_r2", "Neon Nights", "Single • Dua Lipa • 2026", true),
        ("MPREb_r3", "Luz", "Álbum • Rosalía • 2026", false),
        ("MPREb_r4", "After Midnight", "EP • The Weeknd • 2026", false),
    ].map { ReleasePick(item: ReleaseItem(id: $0.0, title: $0.1, subtitle: $0.2, thumbnail: nil), isNew: $0.3) }

    /// La página de artista de los escenarios 49 y 50, sin red. La misma que `ScreenshotTest.artistPage` en Android.
    static let artist = RemoteArtist(id: "UCdemo-bad-bunny", name: "Bad Bunny", subtitle: "Artista", thumbnail: nil)
    static let artistPage = ArtistPage(
        name: "Bad Bunny", thumbnail: nil, songs: [songs[5]],
        albums: [RemoteCollection(id: "MPREb_1", title: "Un Verano Sin Ti", subtitle: "Álbum • Bad Bunny • 2022", thumbnail: nil)],
        singles: [RemoteCollection(id: "MPREb_r1", title: "Verano 26", subtitle: "Single • Bad Bunny • 2026", thumbnail: nil)])

    /// La carpeta que abre el escenario `.folder` (Gimnasio).
    @MainActor static var folderID: String?

    /// Estado del reproductor y hojas abiertas.
    @MainActor static func apply(player: Player, jam: JamService) {
        guard let s = current else { return }
        let queue = DemoCatalog.isActive ? DemoCatalog.songs : songs
        if s.playing { player.preview(queue: queue, index: 0, progress: 74, duration: 200) }
        player.showFullPlayer = s.showPlayer
        jam.showSheet = s.showJam
    }
}

/// Abre la pantalla del escenario dentro de un NavigationStack (sin animación de entrada).
private struct DemoRoute<Destination: View>: ViewModifier {
    let route: Demo.Route
    @ViewBuilder let destination: () -> Destination
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: $pushed, destination: destination)
            .task {
                guard Demo.current?.route == route, !pushed else { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { pushed = true }
            }
    }
}

extension View {
    func demoRoute<D: View>(_ route: Demo.Route, @ViewBuilder destination: @escaping () -> D) -> some View {
        modifier(DemoRoute(route: route, destination: destination))
    }
}
