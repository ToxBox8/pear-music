import SwiftUI

// MARK: - Modo de demostración para las capturas
// `-screenshotScenario <nombre>` (argumento de lanzamiento, llega por UserDefaults) abre la app
// en uno de los estados de `ScreenshotTest` de Android con los mismos datos de ejemplo y sin red:
// 6 canciones, 3 playlists y «Blinding Lights» en pausa en 1:14 de 3:20. La CI (ios.yml) lanza
// cada escenario en el simulador del iPhone 16 y guarda la captura con el mismo nombre.
enum Demo {
    enum Tab: String { case home, reels, library, settings }
    enum Route { case favorites, themePicker }

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
    }

    /// Estado del reproductor y hojas abiertas.
    @MainActor static func apply(player: Player, jam: JamService) {
        guard let s = current else { return }
        if s.playing { player.preview(queue: songs, index: 0, progress: 74, duration: 200) }
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
