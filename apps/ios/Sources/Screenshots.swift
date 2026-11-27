import SwiftUI

// MARK: - Modo de demostración para las capturas
// `-screenshotScenario <nombre>` (argumento de lanzamiento, llega por UserDefaults) abre la app
// en uno de los estados de `ScreenshotTest` de Android con los mismos datos de ejemplo y sin red:
// 6 canciones, 3 playlists y «Blinding Lights» en pausa en 1:14 de 3:20. La CI (ios.yml) lanza
// cada escenario en el simulador del iPhone 16 y guarda la captura con el mismo nombre.
enum Demo {
    enum Tab: String { case home, reels, library, settings }
    enum Route { case favorites, themePicker, artist, downloads, playlists, folder, artists, manage, badges,
                 cuenta, cuentaCrear, cuentaClave, cuentaEntrar, cuentaComprobar, cuentaBorrar,
                 cuentaSinCrearAbierto, cuentaSeguridad, cuentaCerrarSesion, cuentaCerrarSesionUnico, cuentaTerminos,
                 cuentaQr, cuentaQrEmojis, cuentaAnadir, cuentaAnadirEmojis, cuentaConectada, cuentaSincronizado, cuentaBloqueado,
                 cuentaPulsos, cuentaPulsosVacio, cuentaPulsosSinCuenta,
                 cuentaCodigo, cuentaCodigoMal, cuentaCodigoCanjeado }

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
        /// Biblioteca con «Tu música» en el modo de ordenar (flechas y asa).
        var musicEditing = false
        /// Playlists en el modo «Ordenar» (sólo arrastrando; paso C).
        var playlistsOrdering = false
        /// Sólo los tests de interfaz: 24 playlists más, para que la cuadrícula pase de la pantalla (desplazamiento al
        /// borde en el modo «Ordenar»). No es una captura.
        var manyPlaylists = false
        /// «Reducir movimiento» para el temblor del modo «Ordenar» (prompt 2-0): las portadas llevan el borde en vez de
        /// temblar. Lo llevan las capturas de «Ordenar», como en Android (`ScreenshotTest` lo fuerza en todas), para
        /// que la pantalla se quede quieta y salga recta.
        var reduceMotion = false
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
        // Insignia «NUEVO» sobre una portada clara (washi) y otra casi negra (sumi), en claro y en oscuro.
        "52_insignia_nuevo_claro": Scenario(playing: false, route: .badges),
        "52_insignia_nuevo_oscuro": Scenario(appearance: "dark", playing: false, route: .badges),
        // «Tu música» ordenando: «Hecho», flechas y asa (revisión del bloque 1).
        "53_tu_musica_ordenar": Scenario(playing: false, tab: .library, musicEditing: true),
        // Modo «Ordenar» de Playlists (paso C de menús y gestos): sin barra, asas ni buscador.
        "54_playlists_ordenar": Scenario(playing: false, tab: .library, route: .playlists, folders: true, playlistsOrdering: true, reduceMotion: true),
        "55_playlists_ordenar_oscuro": Scenario(appearance: "dark", playing: false, tab: .library, route: .playlists, folders: true, playlistsOrdering: true, reduceMotion: true),
        // Cuenta 3.0 (bloque 2, 2-C paso 3): Ajustes › Cuenta, como ScreenshotTest.cuenta_* de Android.
        "56_cuenta_sin_crear": Scenario(tab: .settings, route: .cuenta),
        "56_cuenta_sin_crear_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuenta),
        // Pulir 2 · opción A: sin cuenta, con «Qué ganas con la cuenta» abierto.
        "56b_cuenta_sin_crear_abierto": Scenario(tab: .settings, route: .cuentaSinCrearAbierto),
        "57_cuenta_crear": Scenario(tab: .settings, route: .cuentaCrear),
        "57_cuenta_crear_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaCrear),
        "58_cuenta_tu_clave": Scenario(tab: .settings, route: .cuentaClave),
        "58_cuenta_tu_clave_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaClave),
        "59_cuenta_entrar": Scenario(tab: .settings, route: .cuentaEntrar),
        "59_cuenta_entrar_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaEntrar),
        // La 60 («Dispositivos») ya no existe (DECISIONS 101): el menú de un dispositivo (60, 60b, 60c) lo capturan
        // los CuentaUITests, porque hay que tocarlo.
        "61_cuenta_comprobar": Scenario(tab: .settings, route: .cuentaComprobar),
        "61_cuenta_comprobar_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaComprobar),
        "62_cuenta_borrar": Scenario(tab: .settings, route: .cuentaBorrar),
        "62_cuenta_borrar_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaBorrar),
        // Móvil nuevo por QR (2-E): el QR del nuevo, sus emojis, «¿Añadir…?» del viejo y sus emojis.
        "63_cuenta_qr": Scenario(tab: .settings, route: .cuentaQr),
        "64_cuenta_qr_emojis": Scenario(tab: .settings, route: .cuentaQrEmojis),
        "65_cuenta_anadir": Scenario(tab: .settings, route: .cuentaAnadir),
        "66_cuenta_anadir_emojis": Scenario(tab: .settings, route: .cuentaAnadirEmojis),
        // Pulir el bloque 2: Ajustes › Cuenta con la cuenta puesta («Añadir un móvil», el estado de la sincronización).
        "67_cuenta_conectada": Scenario(tab: .settings, route: .cuentaConectada),
        "67_cuenta_conectada_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaConectada),
        // Pulir 2 · opción A: con «Seguridad y cuenta» abierto.
        "67b_cuenta_seguridad": Scenario(tab: .settings, route: .cuentaSeguridad),
        "67b_cuenta_seguridad_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaSeguridad),
        // PULIR #5: «Lo que se sincroniza» con la biblioteca de ejemplo.
        // Pulir 2 #1: con carpetas y seguidos, cada fila con su imagen, en claro y en oscuro.
        "68_cuenta_sincronizado": Scenario(tab: .settings, route: .cuentaSincronizado, folders: true, followed: true),
        "68_cuenta_sincronizado_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaSincronizado, folders: true, followed: true),
        // Pulir 2 #2, modo fútbol: la cápsula y la fila dicen por qué no se llega al servidor.
        "69_cuenta_bloqueado": Scenario(tab: .settings, route: .cuentaBloqueado),
        // Pulir 2 · notas de la opción A #4: cerrar sesión (70b, siendo el único dispositivo) y los términos nuevos (71).
        "70_cuenta_cerrar_sesion": Scenario(tab: .settings, route: .cuentaCerrarSesion),
        "70_cuenta_cerrar_sesion_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaCerrarSesion),
        "70b_cuenta_cerrar_sesion_unico": Scenario(tab: .settings, route: .cuentaCerrarSesionUnico),
        "70b_cuenta_cerrar_sesion_unico_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaCerrarSesionUnico),
        "71_cuenta_terminos_nuevos": Scenario(tab: .settings, route: .cuentaTerminos),
        "71_cuenta_terminos_nuevos_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaTerminos),
        // Pulsos (bloque 3, 3-A): con saldo e historial, sin movimientos y sin cuenta, en claro y en oscuro (como Android).
        "72_pulsos": Scenario(tab: .settings, route: .cuentaPulsos),
        "72_pulsos_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaPulsos),
        "72b_pulsos_vacio": Scenario(tab: .settings, route: .cuentaPulsosVacio),
        "72b_pulsos_vacio_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaPulsosVacio),
        "72c_pulsos_sin_cuenta": Scenario(tab: .settings, route: .cuentaPulsosSinCuenta),
        "72c_pulsos_sin_cuenta_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaPulsosSinCuenta),
        // «Tengo un código» (3-B): vacío, mal escrito y ya canjeado, en claro y en oscuro (como Android).
        "72d_codigo": Scenario(tab: .settings, route: .cuentaCodigo),
        "72d_codigo_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaCodigo),
        "72e_codigo_mal": Scenario(tab: .settings, route: .cuentaCodigoMal),
        "72e_codigo_mal_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaCodigoMal),
        "72f_codigo_canjeado": Scenario(tab: .settings, route: .cuentaCodigoCanjeado),
        "72f_codigo_canjeado_oscuro": Scenario(appearance: "dark", tab: .settings, route: .cuentaCodigoCanjeado),
        // Sólo tests de interfaz (BibliotecaUITests): Playlists con 24 playlists más, para el desplazamiento al borde.
        "ui_muchas_playlists": Scenario(playing: false, tab: .library, route: .playlists, manyPlaylists: true),
        // Sólo tests de interfaz: la Biblioteca con «Reducir movimiento», para ver que en «Ordenar» nada tiembla.
        "ui_reducir_movimiento": Scenario(playing: false, tab: .library, reduceMotion: true),
        // Sólo tests de interfaz (prompt 2-0b): Playlists con carpetas y «Reducir movimiento», para sacar de una carpeta.
        "ui_carpetas_reducir_movimiento": Scenario(playing: false, tab: .library, route: .playlists, folders: true, reduceMotion: true),
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

    /// Sólo en el simulador (revisión del bloque 2, B2-1): en un iPhone de verdad no hay modo de capturas. Con la app
    /// firmada para desarrollo (AltStore, iloader), `devicectl` puede lanzarla con argumentos, y la cuenta de mentira de
    /// los escenarios de la cuenta se salta Face ID (`CuentaPear.presencia`). Las capturas y los CuentaUITests van en
    /// el simulador (ios.yml), así que no pierden nada.
    static let current: Scenario? = {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.string(forKey: "screenshotScenario").flatMap { scenarios[$0] }
        #else
        return nil
        #endif
    }()
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
        // Los órdenes guardados por un escenario anterior (los tests de interfaz ordenan de verdad) no pasan al siguiente.
        ["musicOrder", "playlistOrder", "pinnedOrder", "albumOrder"].forEach { d.removeObject(forKey: $0) }
        d.set("recent", forKey: "albumSort")
        d.set("playlists", forKey: "smartPlacement")
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
        if current?.manyPlaylists == true {
            for i in 1...24 { library.playlists.append(Playlist(name: String(format: "Lista %02d", i), songs: Array(songs.prefix(1 + i % 4)), tint: i % 8)) }
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

/// Capturas 52: la insignia «NUEVO» sobre una portada clara y otra casi negra (sólo tokens), con el fondo del tema.
/// Igual que `ScreenshotTest.insignia_nuevo_*` en Android.
struct NewBadgePreview: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach([Tokens.Brand.washi, Tokens.Brand.sumi], id: \.self) { cover in
                RoundedRectangle(cornerRadius: Tokens.Radius.artworkCard, style: .continuous)
                    .fill(cover)
                    .frame(width: 150, height: 150)
                    .overlay(alignment: .topLeading) { NewBadge().padding(8) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themed()
    }
}
