import Combine
import SwiftUI
import UserNotifications
import UIKit

@main
struct LibreMusicApp: App {
    @StateObject private var player = Player()
    @StateObject private var library = Library()
    @StateObject private var downloads = DownloadStore.shared
    @StateObject private var engine = ThemeEngine()
    @StateObject private var jam = JamService()

    /// Idioma elegido (Cierre 1.0): al cambiarlo se vuelve a dibujar todo con los textos nuevos.
    @AppStorage("language") private var language = ""

    init() {
        I18n.load()
        Demo.prepare()
        // Avisos: tarea en segundo plano (hay que registrarla al arrancar), notificaciones y copia guardada.
        AvisosStore.registrarFondo()
        UNUserNotificationCenter.current().delegate = AvisosNotificationDelegate.shared
        AvisosStore.shared.cargarCopia()
        if AvisosStore.shared.notificar { AvisosStore.programarFondo() }
        let d = UserDefaults.standard
        // Instalación nueva: Cristal, que respeta el modo claro/oscuro del móvil. Los temas
        // retirados en la 1.3 (Partículas, ASCII, Malla…) y el antiguo interruptor «cristal
        // sí/no» pasan a Cristal o Sistema.
        let stored = d.string(forKey: "theme")
        // Guía inicial sólo en instalaciones nuevas (aún no hay tema guardado), como en Android.
        if d.object(forKey: "onboarded") == nil { d.set(stored != nil, forKey: "onboarded") }
        // «Primeros pasos» sólo en instalaciones nuevas (quien ya usaba la app ya sabe).
        if d.object(forKey: "firstSteps") == nil { d.set(stored != nil ? "hidden" : "", forKey: "firstSteps") }
        if stored == nil {
            let old = d.object(forKey: "glass") as? Bool
            d.set(old == false ? AppTheme.plain.rawValue : Tokens.defaultTheme, forKey: "theme")
        } else if AppTheme(rawValue: stored!) == nil {
            d.set(Tokens.defaultTheme, forKey: "theme")
        }
        d.removeObject(forKey: "glass")
        d.removeObject(forKey: "libraryStyle")   // sólo queda la biblioteca 1.1
        if d.string(forKey: "deck") == nil {
            let fallback = AppTheme.current == .air ? DeckStyle.air : DeckStyle.normal
            d.set(d.bool(forKey: "cassette") ? DeckStyle.cassette.rawValue : fallback.rawValue, forKey: "deck")
        }
        // Una vez: con el tema Aire, el reproductor pasa a ser el de Air OS.
        if !d.bool(forKey: "airDeckOffered") {
            d.set(true, forKey: "airDeckOffered")
            if AppTheme.current == .air { d.set(DeckStyle.air.rawValue, forKey: "deck") }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(language)
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(downloads)
                .environmentObject(engine)
                .environmentObject(jam)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: Library
    @EnvironmentObject var downloads: DownloadStore
    @ObservedObject private var shortcuts = ShortcutRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var engine: ThemeEngine
    @EnvironmentObject var jam: JamService
    @AppStorage("searchPlacement") private var searchPlacement = "home"
    @AppStorage("deck") private var deckID = DeckStyle.normal.rawValue
    @Environment(\.verticalSizeClass) private var verticalSize
    @AppStorage("tabOrder") private var tabOrderRaw = ""
    /// Barra inferior: «classic» o «simpmusic» (Ajustes › Aspecto › Barra inferior; mismo ajuste que Android).
    @AppStorage("barStyle") private var barStyle = "classic"
    /// Ajustes arriba en Inicio (junto al Jam) o en la barra, aparte para cada barra (Ajustes › Aspecto › Ajustes):
    /// por defecto en la barra con la clásica y arriba con la estilo SimpMusic. Mismo ajuste que Android.
    @AppStorage("settingsTop.classic") private var settingsTopClassic = false
    @AppStorage("settingsTop.simpmusic") private var settingsTopSimp = true
    @AppStorage("lastTab") private var lastTab = ""
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("termsAcceptedAt") private var termsAcceptedAt = 0.0
    @AppStorage("showDiscover") private var showDiscover = true
    @AppStorage("introStage") private var introStage = ""
    @AppStorage("openAccountAfterIntro") private var openAccountAfterIntro = false
    /// Última versión («2.1») cuyas novedades se han visto (1.1).
    @AppStorage("whatsNewSeen") private var whatsNewSeen = ""
    @ObservedObject private var guide = Guide.shared
    @State private var showAccount = false
    @State private var tab = RootView.startTab()
    @State private var demoImport = Demo.current?.showImport ?? false

    /// La app vuelve a abrirse en la última pestaña usada (la primera vez, Inicio).
    private static func startTab() -> String {
        if let demo = Demo.current { return demo.tab.rawValue }
        let d = UserDefaults.standard
        let visible = TabOrder.visible(TabOrder.decode(d.string(forKey: "tabOrder") ?? ""), searchTab: d.string(forKey: "searchPlacement") == "tab",
                                       discover: d.object(forKey: "showDiscover") as? Bool ?? true)
        return TabOrder.tag(TabOrder.start(last: d.string(forKey: "lastTab") ?? "", visible: visible))
    }

    /// iPhone en horizontal con casete o vinilo elegido: el objeto ocupa toda la pantalla.
    private var immersive: Bool {
        verticalSize == .compact && player.current != nil && (DeckStyle(rawValue: deckID) ?? .normal).isObject
    }

    /// Orden de las pestañas (Ajustes › Aspecto › Pestañas), también para deslizar a la anterior o la siguiente.
    private var tabOrder: [String] {
        simpBar ? barTabs : TabOrder.visible(TabOrder.decode(tabOrderRaw), searchTab: searchPlacement == "tab", discover: showDiscover)
            .filter { !(settingsTop && $0 == TabOrder.settings) }.map(TabOrder.tag)
    }

    /// Barra estilo SimpMusic: en la barra van tus pestañas y Buscar va aparte. Ajustes, en la barra o arriba en Inicio.
    private var simpBar: Bool { barStyle == "simpmusic" }
    private var settingsTop: Bool { simpBar ? settingsTopSimp : settingsTopClassic }
    private var barTabs: [String] {
        TabOrder.visible(TabOrder.decode(tabOrderRaw), searchTab: false, discover: showDiscover)
            .filter { !(settingsTop && $0 == TabOrder.settings) }.map(TabOrder.tag)
    }

    @ViewBuilder private var tabView: some View {
        #if compiler(>=6.2)
        if simpBar, #available(iOS 26.0, *) {
            SimpTabView(tab: $tab, tabs: barTabs) { tabContent($0) }
        } else {
            classicTabView
        }
        #else
        classicTabView
        #endif
    }

    private var classicTabView: some View {
        // Con la barra estilo SimpMusic antes de iOS 26, Buscar va al final de la barra.
        let shown = simpBar ? barTabs + [TabOrder.tag(TabOrder.search)] : tabOrder
        return TabView(selection: $tab) {
            ForEach(shown, id: \.self) { t in
                tabContent(t)
                    .tabItem { Label(TabOrder.title(TabOrder.key(t)), systemImage: TabOrder.symbol(TabOrder.key(t))) }
                    .tag(t)
            }
        }
    }

    var body: some View {
        tabView
        .onChange(of: tab) { lastTab = TabOrder.key($0) }
        .onChange(of: barStyle) { _ in if settingsTop && TabOrder.key(tab) == TabOrder.settings { tab = TabOrder.tag(TabOrder.home) } }
        .onChange(of: settingsTop) { top in if top && TabOrder.key(tab) == TabOrder.settings { tab = TabOrder.tag(TabOrder.home) } }
        .onChange(of: searchPlacement) { if !simpBar && $0 != "tab" && tab == TabOrder.search { tab = TabOrder.home } }
        // Bienvenida (también desde Ajustes › Ayuda y soporte). Quien ya usaba la app antes de la 2.0 sólo ve la
        // pantalla de privacidad, una vez. Después: recorrido sobre la app → historias → (cuenta, si la pidió).
        .fullScreenCover(isPresented: Binding(get: { (!onboarded || termsAcceptedAt == 0) && Demo.current == nil },
                                              set: { if !$0 { onboarded = true } }),
                         onDismiss: { if introStage.isEmpty, openAccountAfterIntro { openAccountAfterIntro = false; showAccount = true } }) {
            OnboardingView(privacyOnly: onboarded)
        }
        .overlay {
            if onboarded && termsAcceptedAt > 0 && introStage == "tour" && Demo.current == nil {
                TourOverlay(select: { tab = TabOrder.tag($0) }, onDone: { withAnimation(.uiEaseOut(0.3)) { introStage = "stories" } })
            }
        }
        .overlay {
            if onboarded && termsAcceptedAt > 0 && introStage == "stories" && Demo.current == nil {
                StoriesView(onDone: {
                    withAnimation(.uiEaseOut(0.3)) { introStage = "" }
                    if openAccountAfterIntro { openAccountAfterIntro = false; showAccount = true }
                })
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showAccount) { NavigationStack { AccountView() }.environmentObject(library) }
        // Novedades tras actualizar (1.1): una vez por versión; no se cierra deslizando, hay que elegir.
        .background(EmptyView().fullScreenCover(isPresented: Binding(
            get: { onboarded && termsAcceptedAt > 0 && introStage.isEmpty && whatsNewSeen != WhatsNew.current && guide.active == nil && Demo.current == nil },
            set: { _ in }
        )) {
            WhatsNewView(onTour: { whatsNewSeen = WhatsNew.current; guide.active = "whatsnew" },
                         onClose: { whatsNewSeen = WhatsNew.current })
        })
        // Instalación nueva: ya está la bienvenida, así que estas novedades no salen.
        .onAppear { if !onboarded && whatsNewSeen.isEmpty { whatsNewSeen = WhatsNew.current } }
        // La guía y el recorrido de novedades empiezan en Ajustes: en su pestaña o, si está arriba, en Inicio.
        .onChange(of: guide.active) { g in
            guard g != nil else { return }
            tab = TabOrder.tag(settingsTop ? TabOrder.home : TabOrder.settings)
        }
        // Primeros pasos: se marcan solos (Intro.swift).
        .onChange(of: tab) { if $0 == TabOrder.tag("discover") { FirstSteps.mark("discover") } }
        // Descubrir apagado mientras se estaba en ella: a Inicio.
        .onChange(of: showDiscover) { if !$0 && tab == TabOrder.tag("discover") { tab = TabOrder.tag(TabOrder.home) } }
        .onChange(of: jam.showSheet) { if $0 { FirstSteps.mark("jam") } }
        .onChange(of: library.favorites.count) { if $0 > 0 { FirstSteps.mark("favorite") } }
        .onChange(of: downloads.downloadedIDs.count) { if $0 > 0 { FirstSteps.mark("download") } }
        .onChange(of: library.playlists.contains { $0.pinned == true }) { if $0 { FirstSteps.mark("pin") } }
        // Deslizar a los lados cambia de pestaña (como Instagram y como en Android).
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global).onEnded { v in
                guard let next = TabSwipe.target(from: tab, order: tabOrder, drag: v) else { return }
                tab = next
            }
        )
        .sheet(isPresented: $jam.showSheet) { JamSheet() }
        .sheet(isPresented: $demoImport) { ImportView() }
        .task {
            Demo.apply(player: player, jam: jam)
            // Hasta 1.4.1 se podía elegir el icono violeta («logo antiguo»). Ya no viene en la app: quien lo
            // tuviera vuelve al de encendido (iOS enseña su aviso de cambio de icono una vez).
            if UIApplication.shared.alternateIconName != nil { try? await UIApplication.shared.setAlternateIconName(nil) }
        }
        // libremusic://jam/CÓDIGO: el QR del Jam escaneado con la cámara del iPhone.
        .onOpenURL { jam.handle(url: $0) }
        .modifier(UpdateAlert())
        .overlay { IncidentOverlay() }
        .modifier(NowPlayingAccessory())
        .sheet(isPresented: $player.showFullPlayer) {
            PlayerView()
                .overlay { if immersive { ImmersiveDeck(style: DeckStyle(rawValue: deckID) ?? .normal) } }
        }
        .overlay { if immersive && !player.showFullPlayer { ImmersiveDeck(style: DeckStyle(rawValue: deckID) ?? .normal) } }
        .animation(.easeInOut(duration: 0.35), value: immersive)
        .modifier(ThemeAppearance(forceDark: tab == Demo.Tab.reels.rawValue && !player.showFullPlayer && !jam.showSheet))
        // Atajos de Siri / Atajos (los mismos que los del icono en Android).
        .onReceive(shortcuts.$pending.compactMap { $0 }) { kind in
            shortcuts.pending = nil
            switch kind {
            case .favorites:
                let l = library.favorites.shuffled()
                if let first = l.first { player.play(first, in: l) }
            case .downloads:
                let l = downloads.songs.shuffled()
                if let first = l.first { player.play(first, in: l) }
            case .discover: tab = TabOrder.tag("discover")
            case .search: tab = TabOrder.tag(simpBar || searchPlacement == "tab" ? "search" : "home")
            }
        }
        // Notificación de aviso pulsada: a Inicio, que abre Avisos.
        .onReceive(AvisosStore.shared.$abrir.filter { $0 }) { _ in tab = TabOrder.tag("home") }
        // Copia automática de la biblioteca (una al día) al abrir y al salir de la app.
        .onChange(of: scenePhase) { phase in
            if phase != .inactive { AutoBackup.shared.backup(library: library) }
            // Avisos al día cada vez que se vuelve a la app, sin esperar al trabajo de fondo.
            if phase == .active { Task { await AvisosStore.shared.refrescarAlAbrir() } }
            // Estado de incidencias firmado (Fase 4): al abrir; sin red, se queda el último válido.
            if phase == .active { Task { await Incident.shared.refresh() } }
            // Instalaciones activas: un contador por versión, una vez al día y sin identificadores.
            if phase == .active { Task { await Ficha.pingActive(); await Ficha.reportDecision() } }
            // Telemetría, sólo con consentimiento: mide mientras la app está a la vista y manda un resumen a la semana (Fase 4b).
            if phase == .active { Telemetry.shared.foreground() }
            if phase == .background { Telemetry.shared.background() }
        }
        .onChange(of: player.current?.id) { _ in
            if let s = player.current { library.markPlayed(s); FirstSteps.mark("play") }
            Task { await engine.update(for: player.current) }
        }
    }
}

#if compiler(>=6.2)
/// Barra estilo SimpMusic en iOS 26: la del sistema ya hace lo mismo (Buscar en un círculo aparte con `role: .search`,
/// se pliega al bajar y el mini reproductor, que es el accesorio, se pone a su lado).
@available(iOS 26.0, *)
private struct SimpTabView<Content: View>: View {
    @Binding var tab: String
    let tabs: [String]
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        TabView(selection: $tab) {
            ForEach(tabs, id: \.self) { t in
                Tab(TabOrder.title(TabOrder.key(t)), systemImage: TabOrder.symbol(TabOrder.key(t)), value: t) { content(t) }
            }
            Tab(value: TabOrder.tag(TabOrder.search), role: .search) { content(TabOrder.tag(TabOrder.search)) }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
#endif

extension RootView {
    @ViewBuilder func tabContent(_ tag: String) -> some View {
        switch TabOrder.key(tag) {
        case TabOrder.discover: ReelsView()
        case TabOrder.search: SearchView()
        case TabOrder.library: LibraryView()
        case TabOrder.settings: SettingsView()
        default: HomeView()
        }
    }
}

/// Deslizar entre pestañas. Lo que se arrastra en horizontal dentro de la pantalla tiene
/// prioridad: carruseles, filas con «Quitar» y, dentro de una pila, deslizar a la derecha
/// (que es «atrás»).
@MainActor
enum TabSwipe {
    /// Pantallas abiertas con filas que se deslizan para quitar (las cuenta CollectionDetailV11).
    static var rowSwipeScreens = 0

    static func target(from tab: String, order: [String], drag v: DragGesture.Value) -> String? {
        let dx = v.translation.width, dy = v.translation.height
        let predicted = v.predictedEndTranslation.width
        guard abs(dx) > abs(dy) * 1.6, abs(dx) > 70 || abs(predicted) > 220,
              let i = order.firstIndex(of: tab) else { return nil }
        let leftward = dx < 0
        if blocked(at: v.startLocation, leftward: leftward) { return nil }
        // Dentro de una pila, hacia la derecha es «atrás» (lo hace el sistema).
        if !leftward && navigationDepth() > 1 { return nil }
        let j = leftward ? i + 1 : i - 1
        return order.indices.contains(j) ? order[j] : nil
    }

    private static var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow }
    }

    /// ¿Empezó el arrastre sobre algo que se desplaza en horizontal o una fila deslizable?
    private static func blocked(at point: CGPoint, leftward: Bool) -> Bool {
        guard let window, let hit = window.hitTest(point, with: nil) else { return false }
        var view: UIView? = hit
        while let v = view {
            if let s = v as? UIScrollView, s.isScrollEnabled, s.contentSize.width > s.bounds.width + 1 { return true }
            if leftward && rowSwipeScreens > 0 && v is UICollectionViewCell { return true }
            view = v.superview
        }
        return false
    }

    /// Pantallas apiladas en la pestaña visible (1 = en la raíz).
    private static func navigationDepth() -> Int {
        func find(_ vc: UIViewController?) -> UINavigationController? {
            guard let vc else { return nil }
            if let nav = vc as? UINavigationController { return nav }
            if let tabs = vc as? UITabBarController { return find(tabs.selectedViewController) }
            for child in vc.children { if let n = find(child) { return n } }
            return nil
        }
        return find(window?.rootViewController)?.viewControllers.count ?? 1
    }
}

/// «1 canción», «12 canciones».
func songCount(_ n: Int) -> String { n == 1 ? L("1 canción") : "\(n) canciones" }

func timeString(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
}

// MARK: - Buscar
struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView { SearchResultsView(query: query) }
                .scrollDismissesKeyboard(.interactively)
                .themed()
                .navigationTitle(L("Buscar"))
                .searchable(text: $query, prompt: L("Canciones, álbumes, artistas…"))
                .navigationDestination(for: RemoteCollection.self) { CollectionView(collection: $0) }
                .navigationDestination(for: RemoteArtist.self) { ArtistView(artist: $0) }
                .miniPlayer()
        }
    }
}

/// Acciones de una canción (menú contextual de filas y tarjetas).
struct SongMenuItems: View {
    let song: Song
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: Library
    @EnvironmentObject var downloads: DownloadStore
    @EnvironmentObject var jam: JamService

    var body: some View {
        if jam.isActive {
            Button { jam.add(song) } label: {
                Label(jam.contains(song) ? "Ya está en el Jam" : "Añadir al Jam", systemImage: "person.3")
            }
            .disabled(jam.contains(song))
        }
        Button { player.playNext(song) } label: { Label("Reproducir a continuación", systemImage: "text.insert") }
        Button { player.enqueue(song) } label: { Label("Añadir a la cola", systemImage: "text.append") }
        Button { library.toggleFavorite(song) } label: {
            Label(library.isFavorite(song) ? L("Quitar de favoritos") : L("Añadir a favoritos"),
                  systemImage: library.isFavorite(song) ? "heart.slash" : "heart")
        }
        if !library.userPlaylists.isEmpty {
            Menu {
                // Con la portada de cada playlist, para reconocerlas de un vistazo (como en Android).
                ForEach(library.userPlaylists) { p in
                    Button { library.add(song, to: p) } label: {
                        Label { Text(p.name) } icon: { Image(uiImage: PlaylistMenuIcon.image(for: p)) }
                    }
                }
            } label: { Label("Añadir a playlist", systemImage: "plus.rectangle.on.rectangle") }
        }
        if downloads.isDownloaded(song) {
            Button(role: .destructive) { downloads.remove(song) } label: { Label("Eliminar descarga", systemImage: "trash") }
        } else {
            Button { Task { await downloads.download(song) } } label: { Label("Descargar", systemImage: "arrow.down.circle") }
        }
    }
}

// MARK: - Mini reproductor
/// En iOS 26 el mini reproductor va en el hueco nativo sobre la barra de pestañas
/// (como Apple Music): el sistema lo coloca y lo compacta cuando la barra se minimiza.
/// En versiones anteriores se dibuja encima del contenido de cada pantalla.
var usesSystemAccessory: Bool {
    #if compiler(>=6.2)
    if #available(iOS 26.1, *) { return true }
    #endif
    return false
}

extension View {
    @ViewBuilder func miniPlayer() -> some View {
        if usesSystemAccessory { self } else { safeAreaInset(edge: .bottom) { MiniPlayer() } }
    }
}

struct NowPlayingAccessory: ViewModifier {
    @EnvironmentObject var player: Player

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: player.current != nil) { AccessoryPlayer() }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
private struct AccessoryPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        MiniPlayerBar(compact: placement == .inline).padding(.horizontal, 14)
    }
}
#endif

/// Contenido del mini reproductor. Tocarlo abre el reproductor; mantenerlo pulsado deja elegir
/// el tipo de reproductor (antes la carátula lo cambiaba con un toque y era fácil hacerlo sin querer).
struct MiniPlayerBar: View {
    var compact = false
    @EnvironmentObject var player: Player
    @AppStorage("deck") private var deckID = DeckStyle.normal.rawValue

    var body: some View {
        let deck = DeckStyle(rawValue: deckID) ?? .normal
        if let song = player.current {
            HStack(spacing: 10) {
                Button { player.showFullPlayer = true } label: {
                    ZStack {
                        switch deck {
                        case .normal: CoverImage(url: song.thumb(120))
                        case .cassette: MiniCassette(isPlaying: player.isPlaying)
                        case .vinyl: MiniVinyl(isPlaying: player.isPlaying, art: song.thumb(120))
                        case .air: MiniAirDisc(art: song.thumb(120), isPlaying: player.isPlaying)
                        }
                    }
                    .frame(width: compact ? 28 : 38, height: compact ? 28 : 38)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous))
                }
                .accessibilityLabel(L("Abrir reproductor"))

                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if !compact {
                        Text(player.error ?? song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { player.showFullPlayer = true }

                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(compact ? .body : .title3)
                        .frame(width: 34, height: 34).contentShape(Rectangle())
                }
                .accessibilityLabel(player.isPlaying ? L("Pausar") : L("Reproducir"))
                if !compact {
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.body)
                            .frame(width: 30, height: 34).contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("Siguiente"))
                }
            }
            .foregroundStyle(.primary)
            .buttonStyle(TactileButtonStyle())
            .contextMenu {
                Picker(L("Reproductor"), selection: $deckID) {
                    ForEach(DeckStyle.allCases) { d in Label(d.name, systemImage: d.symbol).tag(d.rawValue) }
                }
                Button { player.showFullPlayer = true } label: {
                    Label("Abrir reproductor", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
        }
    }
}

/// Mini reproductor flotante para iOS < 26.1.
struct MiniPlayer: View {
    @EnvironmentObject var player: Player
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    private var glass: Bool { (AppTheme(rawValue: themeID) ?? .glass).styled }

    var body: some View {
        if player.current != nil {
            VStack(spacing: 0) {
                MiniProgress(clock: player.clock)
                    .padding(.horizontal, glass ? 18 : 0)
                    .padding(.top, glass ? 6 : 0)
                HStack(spacing: 8) {
                    MiniPlayerBar()
                    RoutePicker().frame(width: 30, height: 30)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: glass ? Tokens.Radius.miniPlayer : 0, style: .continuous))
            .glassCard(radius: Tokens.Radius.miniPlayer)
            .padding(.horizontal, glass ? 12 : 0)
            .padding(.bottom, glass ? 4 : 0)
        }
    }
}

// MARK: - Reproductor completo (progreso, cola, AirPlay)
struct PlayerView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: Library
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @AppStorage("deck") private var deckID = DeckStyle.normal.rawValue
    @AppStorage("artworkColorsPlayer") private var artworkPlayer = false
    @AppStorage("artworkIntensity") private var artworkIntensity = ArtworkLevel.balanced.intensity
    @AppStorage("artworkOpacity") private var artworkOpacity = ArtworkLevel.balanced.opacity
    @EnvironmentObject var engine: ThemeEngine
    @Environment(\.colorScheme) private var scheme
    @State private var showQueue = false
    /// Cola o letra en el sitio de la carátula (se recuerda la última).
    @State private var panel: PlayerPanel = .queue
    @State private var editingQueue = false

    private var glass: Bool { (AppTheme(rawValue: themeID) ?? .glass).styled }

    private var deck: DeckStyle { DeckStyle(rawValue: deckID) ?? .normal }
    private var artworkLevel: ArtworkLevel { ArtworkLevel(intensity: artworkIntensity, opacity: artworkOpacity) }
    /// «Colores de la portada» en el reproductor, con el nivel elegido (las dos barras a 0 = apagado).
    private var artworkOn: Bool { artworkPlayer && artworkLevel.enabled }

    var body: some View {
        if deck == .air, !showQueue, let song = player.current {
            AirPlayerView(song: song, showQueue: $showQueue, onLyrics: { panel = .lyrics; withAnimation(.uiEaseOut(0.25)) { showQueue = true } })
                .background { AirPaper() }
                .transition(.opacity)
        } else {
            classic
        }
    }

    private var classic: some View {
        VStack(spacing: 14) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 8)

            if showQueue {
                Picker(L("Panel"), selection: $panel) {
                    Text(L("Cola")).tag(PlayerPanel.queue)
                    Text(L("Letra")).tag(PlayerPanel.lyrics)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                if panel == .lyrics, let song = player.current { LyricsView(song: song) } else { queueView }
            } else if let song = player.current {
                switch deck {
                case .normal, .air:
                    artwork(song)
                        .padding(.top, 8)
                    titleBlock(song)
                    Spacer(minLength: 0)
                case .cassette, .vinyl:
                    // El objeto manda: cabecera compacta y el casete/vinilo lo más grande posible.
                    compactHeader(song)
                    Spacer(minLength: 0)
                    Group {
                        if deck == .cassette {
                            CassetteView(song: song, clock: player.clock)
                        } else {
                            VinylView(song: song, clock: player.clock)
                        }
                    }
                    .padding(.horizontal, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Spacer(minLength: 0)
                }
            }

            if deck.isObject && player.current != nil {
                secondaryControls.padding(.bottom, 10)
            } else {
                controls.transition(.opacity)
            }
        }
        .animation(.uiEaseOut(0.3), value: deckID)
        .background {
            if deck == .air { AirPaper() }
            // «Colores de la carátula» en el reproductor (Air conserva su papel plateado).
            else if artworkOn, let song = player.current { ArtworkBackdrop(url: song.thumb(400), playing: player.isPlaying) }
            else if glass { ThemeBackdrop() }
        }
        .tint(artworkOn && player.current != nil ? engine.palette[0].artworkAccent(dark: scheme == .dark, level: artworkLevel, base: (AppTheme(rawValue: themeID) ?? .glass).accent) : nil)
    }

    private func titleBlock(_ song: Song) -> some View {
        // Temporizador a la izquierda y «⋯» a la derecha, del mismo ancho: el título sigue centrado.
        HStack(spacing: 4) {
            SleepTimerButton()
            VStack(spacing: 4) {
                ScrambleText(text: song.title).font(.title3).bold().multilineTextAlignment(.center).lineLimit(2)
                Text(song.artist).foregroundStyle(.secondary)
                SleepTimerLabel()
                if let e = player.error { Text(e).font(.caption).foregroundStyle(.red) }
            }
            .frame(maxWidth: .infinity)
            songMoreButton(song)
        }
        .padding(.horizontal, 8)
    }

    /// «⋯» del reproductor: el mismo menú de canción que en el resto de la app.
    private func songMoreButton(_ song: Song) -> some View {
        Menu {
            Button { panel = .lyrics; withAnimation(.uiEaseOut(0.25)) { showQueue = true } } label: {
                Label("Ver letra", systemImage: "quote.bubble")
            }
            Divider()
            SongMenuItems(song: song)
        } label: {
            Image(systemName: "ellipsis").font(.title3).foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(L("Más opciones de {0}", song.title))
    }

    private func compactHeader(_ song: Song) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: song.thumb(240))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                ScrambleText(text: song.title).font(.headline).lineLimit(1)
                Text(player.error ?? song.artist).font(.subheadline)
                    .foregroundStyle(player.error == nil ? Color.secondary : Color.red).lineLimit(2)
                SleepTimerLabel()
            }
            Spacer(minLength: 0)
            SleepTimerButton()
            songMoreButton(song)
            Menu {
                Picker(L("Reproductor"), selection: $deckID) {
                    ForEach(DeckStyle.allCases) { d in Label(d.name, systemImage: d.symbol).tag(d.rawValue) }
                }
            } label: {
                Image(systemName: deck.symbol).font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("Cambiar reproductor"))
        }
        .padding(.horizontal, 16)
    }

    private func artwork(_ song: Song) -> some View {
        CoverImage(url: song.thumb(1000))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 340, maxHeight: 340)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.artworkPlayer, style: .continuous))
            .overlay {
                if glass {
                    RoundedRectangle(cornerRadius: Tokens.Radius.artworkPlayer, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
            // Se encoge un poco en pausa, como un objeto que "descansa".
            .scaleEffect(player.isPlaying ? 1 : 0.9)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: player.isPlaying)
            .accessibilityLabel(L("Carátula de {0}", song.title))
    }

    private var controls: some View {
        VStack(spacing: 18) {
            ScrubberView(clock: player.clock)

            HStack(spacing: 28) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.title).frame(width: 56, height: 56).contentShape(Rectangle())
                }
                .accessibilityLabel(L("Anterior"))
                Button { player.toggle() } label: {
                    if glass {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .frame(width: 76, height: 76)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                    }
                }
                .buttonStyle(TactileButtonStyle(lip: glass))
                .accessibilityLabel(player.isPlaying ? L("Pausar") : L("Reproducir"))
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title).frame(width: 56, height: 56).contentShape(Rectangle())
                }
                .accessibilityLabel(L("Siguiente"))
            }

            secondaryControls
        }
        .buttonStyle(TactileButtonStyle())
        .padding(glass ? 16 : 0)
        .glassCard(radius: 28, onlyWhenGlass: true)
        .padding(.horizontal, glass ? 12 : 16)
        .padding(.bottom, 8)
    }

    /// Favorito, descarga, AirPlay, bucle y cola: comunes a los controles normales y al casete.
    private var secondaryControls: some View {
        HStack(spacing: 16) {
            if let song = player.current {
                let fav = library.isFavorite(song)
                Button { library.toggleFavorite(song) } label: {
                    Image(systemName: fav ? "heart.fill" : "heart")
                        .foregroundStyle(fav ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .scaleEffect(fav ? 1.1 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: fav)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(fav ? L("Quitar de favoritos") : L("Añadir a favoritos"))
                DownloadButton(song: song)
            }
            RoutePicker().frame(width: 44, height: 44)
            RepeatButton()
            Button { withAnimation(.uiEaseOut(0.25)) { showQueue.toggle() } } label: {
                Image(systemName: showQueue ? "music.note" : "list.bullet").frame(width: 44, height: 44)
            }
            .accessibilityLabel(showQueue ? L("Ver carátula") : L("Ver cola"))
        }
        .font(.title3)
        .buttonStyle(TactileButtonStyle())
    }

    private var queueView: some View {
        let upcoming = max(player.queue.count - player.index - 1, 0)
        return VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("A continuación")).font(.headline)
                    Text(songCount(upcoming)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if upcoming > 0 {
                    Button(editingQueue ? L("Listo") : L("Editar")) {
                        withAnimation(.uiEaseOut(0.2)) { editingQueue.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 20)

            queueList.edgeFade()

            if upcoming > 0 {
                HoldToConfirmButton(title: "Mantén para vaciar la cola", systemImage: "text.badge.xmark") {
                    player.clearUpcoming()
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var queueList: some View {
        List {
            ForEach(Array(player.queue.enumerated()), id: \.offset) { i, song in
                Button { player.jump(to: i) } label: {
                    HStack {
                        if i == player.index { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint) }
                        VStack(alignment: .leading) {
                            Text(song.title).lineLimit(1)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                // Mantener pulsada una fila de la cola abre el mismo menú de canción que en el resto de la app.
                .contextMenu { SongMenuItems(song: song) }
                .listRowBackground(Color.clear)
            }
            .onDelete { player.remove(at: $0) }
            .onMove { player.move(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Las asas de mover y borrar sólo aparecen con «Editar»; deslizar borra siempre.
        .environment(\.editMode, .constant(editingQueue ? .active : .inactive))
    }
}

// MARK: - Vistas que sí siguen el tiempo de reproducción
struct MiniProgress: View {
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        ProgressView(value: min(clock.progress, max(clock.duration, 1)), total: max(clock.duration, 1))
            .progressViewStyle(.linear)
    }
}

struct ScrubberView: View {
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject var player: Player
    @State private var pos = 0.0
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $pos, in: 0...max(clock.duration, 1)) { editing in
                dragging = editing
                if !editing { player.seek(to: pos) }
            }
            HStack {
                Text(timeString(dragging ? pos : clock.progress))
                Spacer()
                Text(timeString(clock.duration))
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .onAppear { pos = clock.progress }
        .onReceive(clock.$progress) { if !dragging { pos = $0 } }
    }
}

/// Bucle de tres estados (como en Música): del color de los demás botones desactivado, con el color del
/// tema y fondo suave al repetir la lista, y con el «1» al repetir la canción. Toma la fuente de la fila.
struct RepeatButton: View {
    @EnvironmentObject private var player: Player

    var body: some View {
        let on = player.repeatMode != .off
        Button { withAnimation(.uiEaseOut(0.2)) { player.cycleRepeat() } } label: {
            Image(systemName: player.repeatMode.symbol)
                .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: 38, height: 34)
                .background(on ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel(player.repeatMode.label)
        .accessibilityHint(L("Cambia entre no repetir, repetir lista y repetir canción"))
    }
}
