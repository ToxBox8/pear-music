import SwiftUI

// MARK: - Orden de pestañas (Fase 3)
/// Orden de las pestañas (Ajustes › Aspecto › Pestañas). Mismas claves y reglas que `TabOrder` en Android:
/// las cuatro pestañas fijas, cada una una vez; Ajustes se puede mover pero nunca ocultar. Buscar, si va
/// como pestaña aparte, se coloca justo después de Inicio.
enum TabOrder {
    static let discover = "discover", home = "home", search = "search", library = "library", settings = "settings"
    /// Por defecto Descubrir va a la izquierda del todo.
    static let defaultOrder = [discover, home, library, settings]

    /// Lo guardado («discover,home,…»); si falta alguna o sobra algo, el orden por defecto.
    static func decode(_ raw: String) -> [String] {
        var seen = Set<String>()
        let keys = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { defaultOrder.contains($0) && seen.insert($0).inserted }
        return keys.count == defaultOrder.count ? keys : defaultOrder
    }

    static func encode(_ order: [String]) -> String { order.joined(separator: ",") }

    /// Las pestañas que se ven, con Buscar detrás de Inicio si va aparte.
    /// `discover: false` la quita (Ajustes › Aspecto › Pestañas › Descubrir, Fase 3.3), como en Android.
    static func visible(_ order: [String], searchTab: Bool, discover: Bool = true) -> [String] {
        (searchTab ? order.flatMap { $0 == home ? [home, search] : [$0] } : order).filter { discover || $0 != "discover" }
    }

    /// Pestaña al abrir: la última usada, si sigue visible. La primera vez, Inicio: abrir en Descubrir
    /// pondría música sola nada más instalar.
    static func start(last: String, visible: [String]) -> String { visible.contains(last) ? last : home }

    /// Etiqueta de la pestaña en el `TabView` (Descubrir se llamaba «reels» por dentro).
    static func tag(_ key: String) -> String { key == discover ? Demo.Tab.reels.rawValue : key }
    static func key(_ tag: String) -> String { tag == Demo.Tab.reels.rawValue ? discover : tag }

    static func title(_ key: String) -> String {
        switch key {
        case discover: return L("Descubrir")
        case home: return L("Inicio")
        case search: return L("Buscar")
        case library: return L("Biblioteca")
        default: return L("Ajustes")
        }
    }

    static func symbol(_ key: String) -> String {
        switch key {
        case discover: return "play.square.stack.fill"
        case home: return "house.fill"
        case search: return "magnifyingglass"
        case library: return "square.stack.fill"
        default: return "gearshape"
        }
    }
}

// MARK: - Restablecer
/// «Restablecer» de cada sección de Ajustes: vuelve a los valores de una instalación nueva. Mismos valores
/// que `Prefs.reset…` en Android.
enum SettingsReset {
    private static var d: UserDefaults { .standard }

    static func appearance() {
        d.set(AppTheme.glass.rawValue, forKey: "theme")
        d.set("system", forKey: "appearance")
        d.set(DeckStyle.normal.rawValue, forKey: "deck")
        d.set(true, forKey: "scramble")
        d.set(false, forKey: "artworkColorsPlayer")
        d.set(false, forKey: "artworkColorsApp")
        d.set(ArtworkLevel.balanced.intensity, forKey: "artworkIntensity")
        d.set(ArtworkLevel.balanced.opacity, forKey: "artworkOpacity")
        d.set(TabOrder.encode(TabOrder.defaultOrder), forKey: "tabOrder")
    }

    static func playback() { d.set("max", forKey: "quality"); d.set(0, forKey: "crossfade"); d.set(true, forKey: "autoplay") }

    static func library() {
        d.set("recent", forKey: "playlistSort")
        d.set("", forKey: "playlistOrder")
        d.set("playlists", forKey: "smartPlacement")
        d.set("home", forKey: "searchPlacement")
    }
}

/// «Restablecer …» al final de una sección, con confirmación.
struct ResetSection: View {
    let section: String
    let what: String
    let reset: () -> Void
    @State private var confirm = false

    var body: some View {
        Section {
            Button(role: .destructive) { confirm = true } label: {
                Label("Restablecer \(section)", systemImage: "arrow.counterclockwise")
            }
        } footer: { Text(what) }
        .glassRow()
        .confirmationDialog(L("¿Restablecer {0}?", section), isPresented: $confirm, titleVisibility: .visible) {
            Button(L("Restablecer"), role: .destructive) { withAnimation(.uiEaseOut(0.25)) { reset() } }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(what) }
    }
}

/// Hueco para las previsualizaciones animadas de cada opción (Fase 4). Hoy enseña una imagen fija o nada;
/// cuando se hagan las animaciones, se cambian aquí y valen para todos los ajustes.
struct SettingPreview<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}

// MARK: - Ajustes (Fase 4)
/// Dónde está cada opción, para el buscador de Ajustes.
private enum SettingsDestination: Hashable {
    case theme, player, artwork, tabs, bar, playback, downloads, library, manage, about, help, support, advanced, avisos, myData, account, language
}

private struct SettingEntry: Identifiable {
    let title: String
    let section: String
    let keywords: String
    let destination: SettingsDestination
    var id: String { section + title }
}

private var settingsIndex: [SettingEntry] { [
    SettingEntry(title: L("Tema"), section: L("Aspecto"), keywords: L("color fondo cristal neón aire sistema apariencia"), destination: .theme),
    SettingEntry(title: L("Claro u oscuro"), section: L("Aspecto"), keywords: L("modo noche oscuro claro automático"), destination: .theme),
    SettingEntry(title: L("Reproductor"), section: L("Aspecto"), keywords: L("casete vinilo air normal"), destination: .player),
    SettingEntry(title: L("Efecto en los títulos"), section: L("Aspecto"), keywords: L("símbolos animación scramble"), destination: .player),
    SettingEntry(title: L("Colores de la portada"), section: L("Aspecto"), keywords: L("carátula color tinte sutil equilibrado intenso"), destination: .artwork),
    SettingEntry(title: L("Pestañas"), section: L("Aspecto"), keywords: L("orden barra descubrir inicio biblioteca"), destination: .tabs),
    SettingEntry(title: L("Descubrir"), section: L("Aspecto"), keywords: L("ocultar quitar desactivar descubrir feed fragmentos reels"), destination: .tabs),
    SettingEntry(title: L("Barra inferior"), section: L("Aspecto"), keywords: L("barra simpmusic plegar buscar"), destination: .bar),
    SettingEntry(title: L("Calidad al escuchar"), section: L("Reproducción"), keywords: L("streaming datos ahorro máxima kbps"), destination: .playback),
    SettingEntry(title: L("Seguir con canciones parecidas"), section: L("Reproducción"), keywords: L("radio infinita autoplay automático cola acabar"), destination: .playback),
    SettingEntry(title: L("Fundido entre canciones"), section: L("Reproducción"), keywords: L("crossfade transición suave volumen cortes"), destination: .playback),
    SettingEntry(title: L("Copia automática"), section: L("Biblioteca"), keywords: L("copia seguridad backup icloud drive guardar exportar"), destination: .library),
    SettingEntry(title: "AirPlay", section: L("Reproducción"), keywords: L("salida audio altavoz homepod apple tv bluetooth"), destination: .playback),
    SettingEntry(title: L("Canciones descargadas"), section: L("Descargas"), keywords: L("espacio offline sin conexión borrar"), destination: .downloads),
    SettingEntry(title: L("Ordenar playlists"), section: L("Biblioteca"), keywords: L("orden a-z recientes a mano"), destination: .library),
    SettingEntry(title: L("Descargadas y Favoritos"), section: L("Biblioteca"), keywords: L("carrusel tu música"), destination: .library),
    SettingEntry(title: L("Dónde está Buscar"), section: L("Biblioteca"), keywords: L("buscar pestaña inicio barra"), destination: .library),
    SettingEntry(title: L("Eliminar playlists"), section: L("Biblioteca"), keywords: L("borrar quitar"), destination: .manage),
    SettingEntry(title: L("Avisos"), section: L("Ayuda y soporte"), keywords: L("notificaciones campana caídas novedades discord"), destination: .avisos),
    SettingEntry(title: L("Cuenta"), section: L("Ajustes"), keywords: L("cuenta correo nube sincronizar copia cifrada clave recuperación iniciar sesión"), destination: .account),
    SettingEntry(title: L("Telemetría"), section: L("Ayuda y soporte"), keywords: L("telemetría rendimiento datos consentimiento privacidad fps"), destination: .myData),
    SettingEntry(title: L("Tus datos"), section: L("Ayuda y soporte"), keywords: L("privacidad rgpd exportar borrar datos eliminar zip"), destination: .myData),
    SettingEntry(title: L("Idioma"), section: L("Ajustes"), keywords: L("idioma lengua language català valencià galego euskara english esperanto"), destination: .language),
    SettingEntry(title: L("Informar de un error"), section: L("Ayuda y soporte"), keywords: L("bug fallo problema soporte reporte escarabajo contacto"), destination: .support),
    SettingEntry(title: L("Guía inicial"), section: L("Ayuda y soporte"), keywords: L("tutorial bienvenida empezar"), destination: .help),
    SettingEntry(title: L("Acerca de"), section: L("Ayuda y soporte"), keywords: L("versión créditos licencia"), destination: .about),
    SettingEntry(title: L("Vaciar caché de carátulas"), section: L("Avanzado"), keywords: L("memoria imágenes portadas"), destination: .advanced),
    SettingEntry(title: L("Tolerancia de duración"), section: L("Avanzado"), keywords: L("emparejar importar spotify segundos coincidencia"), destination: .advanced),
] }

struct SettingsView: View {
    @ObservedObject private var account = Account.shared
    /// Guía de Ajustes y recorrido de novedades (1.1): abren las pantallas por su ruta.
    @ObservedObject private var guide = Guide.shared
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @AppStorage("deck") private var deckID = DeckStyle.normal.rawValue
    @AppStorage("quality") private var quality = "max"
    @AppStorage("artworkColorsPlayer") private var artworkPlayer = false
    @AppStorage("artworkColorsApp") private var artworkApp = false
    @AppStorage("artworkIntensity") private var intensity = ArtworkLevel.balanced.intensity
    @AppStorage("artworkOpacity") private var opacity = ArtworkLevel.balanced.opacity
    @AppStorage("playlistSort") private var playlistSort = "recent"
    @AppStorage("searchPlacement") private var searchPlacement = "home"
    @EnvironmentObject var downloads: DownloadStore
    @State private var query = ""
    @State private var advanced = false
    @State private var cacheCleared = false
    @AppStorage("matchTolerance") private var tolerance = 4

    private var theme: AppTheme { AppTheme(rawValue: themeID) ?? .glass }
    private var level: ArtworkLevel { ArtworkLevel(intensity: intensity, opacity: opacity) }

    var body: some View {
        NavigationStack(path: $guide.path) {
            Form {
                if query.trimmingCharacters(in: .whitespaces).isEmpty { sections } else { results }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Buscar en Ajustes"))
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Guía de Ajustes (1.1): recorre todas las opciones explicándolas.
                    Button { guide.active = "settings" } label: { Image(systemName: "graduationcap").tourTarget("settings:guide") }
                        .accessibilityLabel(L("Guía de Ajustes"))
                    // Carta junto al escarabajo: el buzón de sugerencias (lo pidió Toxbox).
                    NavigationLink { SupportView(suggestion: true) } label: { Image(systemName: "envelope").tourTarget("settings:mail") }
                        .accessibilityLabel(L("Buzón de sugerencias"))
                    NavigationLink { SupportView() } label: { Image(systemName: "ladybug") }
                        .accessibilityLabel(L("Informar de un error"))
                }
            }
            .navigationTitle(L("Ajustes"))
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .aspect: AspectSettings()
                case .audio: AudioSettings()
                case .library: LibrarySettings()
                case .help: HelpSettings()
                }
            }
            .themed()
            .demoRoute(.themePicker) { AppearanceSettings() }
            .miniPlayer()
        }
        .overlay {
            if let g = guide.active {
                GuideOverlay(steps: g == "settings" ? GuideSteps.settings : GuideSteps.whatsNew) {
                    guide.active = nil
                    guide.path = []
                }
                .id(g)
            }
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            NavigationLink { AccountView() } label: {
                SettingsRow(icon: "person.crop.circle.fill", palette: 4, title: L("Cuenta"), value: nil,
                            subtitle: account.state.email ?? L("Opcional · guarda tu biblioteca cifrada en la nube"))
            }
        }
        .glassRow()
        Section {
            NavigationLink(value: SettingsRoute.aspect) {
                SettingsRow(icon: "paintpalette.fill", palette: 1, title: L("Aspecto"), value: nil,
                            subtitle: L("{0} · {1}", theme.name, (DeckStyle(rawValue: deckID) ?? .normal).name)
                                + ((artworkPlayer || artworkApp) && level.enabled ? L(" · Colores {0}", level.title.lowercased()) : ""))
            }
            // Idioma (Cierre 1.0).
            NavigationLink { LanguageSettings() } label: {
                SettingsRow(icon: "globe", palette: 3, title: L("Idioma"), value: nil,
                            subtitle: I18n.langs.first { $0.id == I18n.current }?.name ?? L("Castellano"))
            }
            NavigationLink(value: SettingsRoute.audio) {
                SettingsRow(icon: "waveform", palette: 3, title: L("Reproducción"), value: nil,
                            subtitle: quality == "low" ? L("Ahorro de datos") : L("Calidad máxima"))
            }
            NavigationLink { DownloadsSettings() } label: {
                SettingsRow(icon: "arrow.down.circle.fill", palette: 2, title: L("Descargas"), value: nil,
                            subtitle: downloads.songs.isEmpty ? L("Ninguna canción descargada")
                                : L("{0} · {1}", songCount(downloads.songs.count), ByteCountFormatter.string(fromByteCount: downloads.totalBytes(), countStyle: .file)))
            }
            NavigationLink(value: SettingsRoute.library) {
                SettingsRow(icon: "books.vertical.fill", palette: 0, title: L("Biblioteca"), value: nil,
                            subtitle: L("Playlists: ") + Self.sortTitle(playlistSort).lowercased() + L(" · Buscar ") + (searchPlacement == "tab" ? L("en su pestaña") : L("en Inicio")))
            }
            NavigationLink(value: SettingsRoute.help) {
                SettingsRow(icon: "info.circle.fill", palette: 6, title: L("Ayuda y soporte"), value: nil,
                            subtitle: L("Informar de un error · Guía inicial · Versión {0}", AboutView.version))
            }
        }
        .glassRow()

        // Lo técnico, plegado: sólo quien lo busca lo ve.
        Section {
            DisclosureGroup(isExpanded: $advanced.animation(.uiEaseOut(0.25))) {
                LabeledContent(L("Calidad de descarga"), value: L("Máxima"))
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Tolerancia de duración"))
                    Text(L("Al importar de Spotify o Apple Music, cuánto puede durar distinta una canción para darla por buena"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker(L("Tolerancia"), selection: $tolerance) {
                        ForEach([2, 4, 6, 10], id: \.self) { Text("±\($0) s").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
                Button(cacheCleared ? L("Caché vaciada") : L("Vaciar caché de carátulas")) {
                    imageMemory.removeAllObjects()
                    URLCache.shared.removeAllCachedResponses()
                    cacheCleared = true
                }
                .disabled(cacheCleared)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Avanzado")).tourTarget("row:" + L("Avanzado"))
                    if !advanced { Text(L("Calidad de descarga, tolerancia al importar y caché")).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        } footer: {
            if advanced { Text(L("Las descargas se guardan siempre a la máxima calidad (AAC 128 kbps), así suenan igual sin conexión.")) }
        }
        .glassRow()
    }

    @ViewBuilder private var results: some View {
        let hits = LocalSearch.filter(settingsIndex, query) { "\($0.title) \($0.section) \($0.keywords)" }
        if hits.isEmpty {
            Section { NoMatchesView(query: query).frame(maxWidth: .infinity).listRowBackground(Color.clear) }
        } else {
            Section {
                ForEach(hits) { e in
                    if e.destination == .advanced {
                        Button {
                            query = ""
                            advanced = true
                        } label: { resultLabel(e) }
                    } else {
                        NavigationLink { destination(e.destination) } label: { resultLabel(e) }
                    }
                }
            }
            .glassRow()
        }
    }

    private func resultLabel(_ e: SettingEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(e.title).foregroundStyle(.primary)
            Text(e.section).font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func destination(_ d: SettingsDestination) -> some View {
        switch d {
        case .theme: AppearanceSettings()
        case .player: PlayerSettings()
        case .artwork: ArtworkColorsSettings()
        case .tabs: TabOrderSettings()
        case .bar: AspectSettings()
        case .playback: AudioSettings()
        case .downloads: DownloadsSettings()
        case .library: LibrarySettings()
        case .manage: ManagePlaylistsView()
        case .about: AboutView()
        case .support: SupportView()
        case .language: LanguageSettings()
        case .avisos: AvisosView()
        case .help, .advanced: HelpSettings()
        case .myData: MyDataView()
        case .account: AccountView()
        }
    }

    static func sortTitle(_ sort: String) -> String {
        ["name": "A-Z", "nameDesc": "Z-A", "count": L("Por tamaño"), "custom": L("A mano")][sort] ?? L("Recientes")
    }
}

// MARK: Aspecto
struct AspectSettings: View {
    @AppStorage("barStyle") private var barStyle = "classic"
    @AppStorage("settingsTop.classic") private var settingsTopClassic = false
    @AppStorage("settingsTop.simpmusic") private var settingsTopSimp = true
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("deck") private var deckID = DeckStyle.normal.rawValue
    @AppStorage("scramble") private var scramble = true
    @AppStorage("artworkColorsPlayer") private var artworkPlayer = false
    @AppStorage("artworkColorsApp") private var artworkApp = false
    @AppStorage("artworkIntensity") private var intensity = ArtworkLevel.balanced.intensity
    @AppStorage("artworkOpacity") private var opacity = ArtworkLevel.balanced.opacity
    @AppStorage("tabOrder") private var tabOrderRaw = ""

    var body: some View {
        let theme = AppTheme(rawValue: themeID) ?? .glass
        let level = ArtworkLevel(intensity: intensity, opacity: opacity)
        let mode: String = {
            if let forced = theme.scheme { return forced == .dark ? "oscuro" : "claro" }
            return ["light": "claro", "dark": "oscuro"][appearance] ?? L("claro u oscuro según el iPhone")
        }()
        Form {
            Section {
                NavigationLink { AppearanceSettings() } label: {
                    SettingsRow(icon: "paintpalette.fill", palette: 1, title: L("Tema"), value: nil, subtitle: "\(theme.name) · \(mode)")
                }
                NavigationLink { PlayerSettings() } label: {
                    SettingsRow(icon: "play.circle.fill", palette: 0, title: L("Reproductor"), value: nil,
                                subtitle: (DeckStyle(rawValue: deckID) ?? .normal).name + (scramble ? L(" · títulos con efecto") : ""))
                }
                NavigationLink { ArtworkColorsSettings() } label: {
                    SettingsRow(icon: "sparkles", palette: 5, title: L("Colores de la portada"), value: nil,
                                subtitle: !(artworkPlayer || artworkApp) || !level.enabled ? L("Desactivado")
                                    : level.title + " · " + [artworkPlayer ? "reproductor" : nil, artworkApp ? L("resto de la app") : nil].compactMap { $0 }.joined(separator: " y "))
                }
                NavigationLink { TabOrderSettings() } label: {
                    SettingsRow(icon: "arrow.left.arrow.right", palette: 7, title: L("Pestañas"), value: nil,
                                subtitle: TabOrder.decode(tabOrderRaw).map(TabOrder.title).joined(separator: ", "))
                }
            }
            .glassRow()

            Section {
                Picker(L("Barra inferior"), selection: $barStyle) {
                    Text(L("Clásica")).tag("classic")
                    Text(L("Estilo SimpMusic")).tag("simpmusic")
                }
                .pickerStyle(.segmented)
            } header: { Text(L("Barra inferior")).tourTarget("section:" + L("Barra inferior")) } footer: {
                Text(barStyle == "simpmusic"
                     ? L("Tus pestañas en la barra y Buscar aparte, como SimpMusic. En iOS 26 la barra se pliega al bajar por una lista.")
                     : L("Las pestañas de siempre."))
            }
            .glassRow()

            // Se guarda aparte para cada barra: con la clásica va en la barra y con la estilo SimpMusic arriba.
            let settingsTop = Binding(
                get: { barStyle == "simpmusic" ? settingsTopSimp : settingsTopClassic },
                set: { if barStyle == "simpmusic" { settingsTopSimp = $0 } else { settingsTopClassic = $0 } }
            )
            Section {
                Picker(L("Ajustes"), selection: settingsTop) {
                    Text(L("En la barra")).tag(false)
                    Text(L("Arriba en Inicio")).tag(true)
                }
                .pickerStyle(.segmented)
            } header: { Text(L("Ajustes")).tourTarget("section:" + L("Ajustes")) } footer: {
                Text(settingsTop.wrappedValue
                     ? L("Ajustes está arriba en Inicio, junto al Jam, y no ocupa sitio en la barra.")
                     : L("Ajustes es una pestaña más de la barra; su sitio se elige en Pestañas."))
            }
            .glassRow()

            ResetSection(section: L("Aspecto"), what: L("Vuelven el tema Cristal, el reproductor Normal, los colores de la portada apagados y el orden de pestañas de fábrica.")) {
                SettingsReset.appearance()
            }
        }
        .navigationTitle(L("Aspecto"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

// MARK: Colores de la portada (Fase 4B)
/// Dónde (reproductor y/o resto de la app) y cuánto (presets y, debajo, las dos barras).
struct ArtworkColorsSettings: View {
    @AppStorage("artworkColorsPlayer") private var artworkPlayer = false
    @AppStorage("artworkColorsApp") private var artworkApp = false
    @AppStorage("artworkIntensity") private var intensity = ArtworkLevel.balanced.intensity
    @AppStorage("artworkOpacity") private var opacity = ArtworkLevel.balanced.opacity
    @EnvironmentObject var engine: ThemeEngine
    @State private var fine = false

    private var level: ArtworkLevel { ArtworkLevel(intensity: intensity, opacity: opacity) }

    var body: some View {
        Form {
            Section {
                // Previsualización fija: el tema actual teñido con la portada que suena (o una de ejemplo).
                SettingPreview { ArtworkPreview(art: engine.palette[0], level: level) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                Toggle(isOn: $artworkPlayer) { titled(L("En el reproductor"), L("Fondo con la carátula desenfocada y controles de su color")) }
                Toggle(isOn: $artworkApp) { titled(L("En el resto de la app"), L("Botones del color de la canción y fondos y menús con un toque")) }
            } header: { Text(L("Dónde")).tourTarget("section:" + L("Dónde")) } footer: {
                Text(L("Al sonar una canción, la app y los menús toman colores parecidos a los de su portada, como Descubrir."))
            }
            .glassRow()

            Section {
                Picker(L("Nivel"), selection: presetBinding) {
                    Text(L("No")).tag("off")
                    ForEach(ArtworkLevel.presets, id: \.name) { Text($0.name).tag($0.name) }
                }
                .pickerStyle(.segmented)
                DisclosureGroup(isExpanded: $fine.animation(.uiEaseOut(0.25))) {
                    slider(L("Exageración del color"), L("Cuánto se parecen los botones al color de la portada"), $intensity)
                    slider(L("Opacidad"), L("Cuánto se tiñen los fondos y los menús"), $opacity)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Ajuste fino"))
                        if level.title == "Personalizado" { Text(L("Personalizado")).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            } header: { Text(L("Cuánto")).tourTarget("section:" + L("Cuánto")) } footer: {
                Text(L("El texto y los iconos mantienen siempre un contraste legible, aunque la portada sea muy clara o muy viva."))
            }
            .glassRow()
        }
        .navigationTitle(L("Colores de la portada"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { level.enabled ? (ArtworkLevel.presets.first { $0.name == level.title }?.name ?? "") : "off" },
            set: { name in
                let l = ArtworkLevel.presets.first { $0.name == name }?.level ?? .off
                withAnimation(.uiEaseOut(0.25)) { intensity = l.intensity; opacity = l.opacity }
            }
        )
    }

    private func titled(_ title: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(help).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func slider(_ title: String, _ help: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(L("{0} %", Int((value.wrappedValue * 100).rounded()))).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(help).font(.footnote).foregroundStyle(.secondary)
            Slider(value: value, in: 0...1).accessibilityLabel(title)
        }
        .padding(.vertical, 4)
    }
}

/// Una fila, un botón y un menú del tema actual, teñidos como quedarían con este nivel.
struct ArtworkPreview: View {
    let art: Color
    let level: ArtworkLevel
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = AppTheme(rawValue: themeID) ?? .glass
        let accent = level.enabled ? art.artworkAccent(dark: scheme == .dark, level: level, base: theme.accent) : theme.accent
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(art).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Canción que suena")).font(.callout.weight(.semibold))
                    Text(L("Artista")).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "heart.fill").foregroundStyle(accent)
            }
            HStack(spacing: 8) {
                Text(L("Reproducir")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 36).background(accent, in: Capsule())
                Text(L("Menú")).font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36).background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(uiColor: .systemBackground))
            if level.enabled { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(art.opacity(level.backgroundTint)) }
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .animation(.uiEaseOut(0.25), value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Vista previa de los colores de la portada"))
    }
}

// MARK: Pestañas (Fase 3)
/// Se arrastran para cambiar el orden; Ajustes se puede mover pero no quitar.
struct TabOrderSettings: View {
    @AppStorage("tabOrder") private var tabOrderRaw = ""
    @AppStorage("barStyle") private var barStyle = "classic"
    @AppStorage("settingsTop.classic") private var settingsTopClassic = false
    @AppStorage("settingsTop.simpmusic") private var settingsTopSimp = true
    @AppStorage("showDiscover") private var showDiscover = true
    @State private var swipe: CGFloat = 0

    var body: some View {
        let order = TabOrder.decode(tabOrderRaw)
        // Ajustes arriba en Inicio: se ve apagado y no se mueve, porque no está en la barra.
        let settingsTop = barStyle == "simpmusic" ? settingsTopSimp : settingsTopClassic
        Form {
            Section {
                ForEach(order, id: \.self) { key in
                    let fixed = settingsTop && key == TabOrder.settings
                    // Descubrir se oculta deslizándola a la izquierda (lo pidió Toxbox): queda difuminada.
                    let hidden = key == "discover" && !showDiscover
                    VStack(alignment: .leading, spacing: 2) {
                        Label(TabOrder.title(key), systemImage: TabOrder.symbol(key))
                        if fixed { Text(L("Arriba en Inicio")).font(.footnote).foregroundStyle(.secondary) }
                        if hidden { Text(L("Oculta · desliza a la derecha para ponerla")).font(.footnote).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .offset(x: key == "discover" ? swipe : 0)
                    .opacity(fixed || hidden ? 0.45 : 1)
                    .moveDisabled(fixed)
                    .gesture(DragGesture(minimumDistance: 12)
                        .onChanged { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            swipe = hidden ? min(max(v.translation.width, 0), 120) : max(min(v.translation.width, 0), -120)
                        }
                        .onEnded { _ in
                            if !hidden && swipe < -70 { showDiscover = false }
                            if hidden && swipe > 70 { showDiscover = true }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { swipe = 0 }
                        }, including: key == "discover" ? .all : .subviews)
                    .accessibilityAction(named: hidden ? L("Mostrar Descubrir") : L("Ocultar Descubrir")) {
                        if key == "discover" { showDiscover.toggle() }
                    }
                }
                .onMove { from, to in
                    var o = order
                    o.move(fromOffsets: from, toOffset: to)
                    tabOrderRaw = TabOrder.encode(o)
                }
            } header: { Text(L("Orden de la barra")).tourTarget("section:" + L("Orden de la barra")) } footer: {
                Text(L("Arrastra ≡ para cambiar el orden; deslizar a los lados sigue el mismo orden. Desliza Descubrir a la izquierda para ocultarla (y a la derecha para volver a ponerla). La app se abre en la última pestaña que usaste.")
                     + (settingsTop ? L(" Ajustes está arriba en Inicio y no entra en el orden (se cambia en Aspecto).") : ""))
            }
            .glassRow()

            Section {
                Button {
                    withAnimation(.uiEaseOut(0.25)) { tabOrderRaw = TabOrder.encode(TabOrder.defaultOrder) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Orden de fábrica"))
                        Text(L("Descubrir, Inicio, Biblioteca, Ajustes")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .disabled(order == TabOrder.defaultOrder)
            }
            .glassRow()
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(L("Pestañas"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

// MARK: Reproducción
struct AudioSettings: View {
    @AppStorage("quality") private var quality = "max"
    @AppStorage("crossfade") private var crossfade = 0
    @AppStorage("autoplay") private var autoplay = true

    var body: some View {
        Form {
            Section {
                Picker(L("Calidad"), selection: $quality) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Máxima"))
                        Text(L("Mejor sonido; gasta más datos")).font(.footnote).foregroundStyle(.secondary)
                    }.tag("max")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Ahorro de datos"))
                        Text(L("Para escuchar con datos móviles")).font(.footnote).foregroundStyle(.secondary)
                    }.tag("low")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text(L("Calidad al escuchar")).tourTarget("section:" + L("Calidad al escuchar")) } footer: {
                Text(L("«Máxima» usa AAC a 128 kbps; «Ahorro de datos», 48 kbps. Se aplica desde la siguiente canción."))
            }
            .glassRow()

            Section {
                Toggle(L("Seguir con canciones parecidas"), isOn: $autoplay)
                    .tourTarget("row:" + L("Seguir con canciones parecidas"))
            } footer: {
                Text(L("Cuando se acaba lo que estás escuchando y el bucle está apagado, se añaden canciones parecidas a la última."))
            }
            .glassRow()

            Section {
                Picker(L("Fundido"), selection: $crossfade) {
                    ForEach(Fade.options, id: \.self) { s in Text(s == 0 ? L("No") : "\(s) s").tag(s) }
                }
                .pickerStyle(.segmented)
            } header: { Text(L("Fundido entre canciones")).tourTarget("section:" + L("Fundido entre canciones")) } footer: {
                Text(crossfade == 0 ? L("Cada canción empieza y acaba a su volumen.") : L("La canción baja de volumen en sus últimos {0} s y la siguiente entra suavemente. Útil para listas variadas; en álbumes que van seguidos, mejor «No».", crossfade))
            }
            .glassRow()

            Section {
                HStack {
                    SettingsRow(icon: "airplayaudio", palette: 7, title: "AirPlay", value: nil, subtitle: L("Altavoces, HomePod y Apple TV"))
                    RoutePicker().frame(width: 44, height: 44)
                }
            } footer: {
                Text(L("El bucle (no repetir, repetir lista o canción) se cambia en el reproductor."))
            }
            .glassRow()

            ResetSection(section: L("Reproducción"), what: L("La calidad al escuchar vuelve a «Máxima» se quita el fundido y se vuelve a seguir con canciones parecidas.")) { SettingsReset.playback() }
        }
        .navigationTitle(L("Reproducción"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

// MARK: Descargas
struct DownloadsSettings: View {
    @EnvironmentObject var downloads: DownloadStore

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Canciones"), value: "\(downloads.songs.count)")
                LabeledContent(L("Espacio usado"), value: ByteCountFormatter.string(fromByteCount: downloads.totalBytes(), countStyle: .file))
            } footer: {
                Text(L("Las descargas se guardan en este iPhone a la máxima calidad y se ven en Biblioteca › Descargadas. Para bajar una lista o un álbum entero, usa «Descargar todo» en su página."))
            }
            .glassRow()

            if !downloads.songs.isEmpty {
                Section {
                    HoldToConfirmButton(title: L("Mantén para borrar las descargas")) { downloads.removeAll() }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    Text(L("Dejarán de estar disponibles sin conexión. Las playlists y los favoritos no se tocan."))
                }
                .glassRow()
            }
        }
        .navigationTitle(L("Descargas"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

// MARK: Ayuda y soporte
struct HelpSettings: View {
    @AppStorage("onboarded") private var onboarded = true

    var body: some View {
        Form {
            Section {
                NavigationLink { AvisosView() } label: {
                    SettingsRow(icon: "bell.badge.fill", palette: 4, title: L("Avisos"), value: nil,
                                subtitle: L("Caídas, versiones nuevas y novedades de Pear Music"))
                }
                NavigationLink { SupportView() } label: {
                    SettingsRow(icon: "ladybug.fill", palette: 0, title: L("Informar de un error"), value: nil,
                                subtitle: L("Cuéntanos qué ha fallado; puedes añadir capturas"))
                }
                // Buzón de sugerencias (Cierre 1.0, lo pidió Toxbox): como el soporte, pero para ideas.
                NavigationLink { SupportView(suggestion: true) } label: {
                    SettingsRow(icon: "envelope.open.fill", palette: 5, title: L("Buzón de sugerencias"), value: nil,
                                subtitle: L("Cuéntanos qué te gustaría que hiciera Pear Music"))
                }
                Button { onboarded = false } label: {
                    SettingsRow(icon: "graduationcap.fill", palette: 2, title: L("Guía inicial"), value: nil,
                                subtitle: L("Vuelve a ver la bienvenida, el recorrido y las historias"))
                }
                .foregroundStyle(.primary)
                NavigationLink { MyDataView() } label: {
                    SettingsRow(icon: "lock.fill", palette: 5, title: L("Tus datos"), value: nil,
                                subtitle: L("Exporta o borra todo lo que la app guarda de ti"))
                }
                NavigationLink { AboutView() } label: {
                    SettingsRow(icon: "info.circle.fill", palette: 6, title: L("Acerca de"), value: nil, subtitle: L("Versión {0} y créditos", AboutView.version))
                }
            }
            .glassRow()
            if Channel.adminTools {
                Section(L("Pear Dev")) {
                    NavigationLink { AdminView() } label: {
                        SettingsRow(icon: "lock.shield.fill", palette: 1, title: L("Administración"), value: nil,
                                    subtitle: L("Canal, registro y botón de pánico"))
                    }
                }
                .glassRow()
            }
        }
        .navigationTitle(L("Ayuda y soporte"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

// MARK: - Guía inicial (Fase 4)
/// Tres pantallas la primera vez —tema, colores de la portada y descargas— que dejan la app configurada sin
/// entrar a Ajustes. Mismos pasos y textos que `OnboardingScreen` en Android.
struct OnboardingView: View {
    /// Quien ya usaba la app antes de la 2.0 sólo ve la pantalla de privacidad, una vez.
    var privacyOnly = false
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("termsAcceptedAt") private var termsAcceptedAt = 0.0
    @AppStorage("introStage") private var introStage = ""
    @AppStorage("openAccountAfterIntro") private var openAccountAfterIntro = false
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("artworkColorsPlayer") private var artworkPlayer = false
    @AppStorage("artworkColorsApp") private var artworkApp = false
    @AppStorage("artworkIntensity") private var intensity = ArtworkLevel.balanced.intensity
    @AppStorage("artworkOpacity") private var opacity = ArtworkLevel.balanced.opacity
    @AppStorage("quality") private var quality = "max"
    @EnvironmentObject var engine: ThemeEngine
    @State private var page = 0
    @State private var terms = false
    @State private var telemetry = Telemetry.shared.enabled
    @State private var forward = true

    private enum Page { case language, welcome, privacy, theme, colors, downloads }
    private var pages: [Page] { privacyOnly ? [.privacy] : [.language, .welcome, .privacy, .theme, .colors, .downloads] }
    private var current: Page { pages[page] }
    private var last: Bool { page == pages.count - 1 }

    private func finish() {
        if termsAcceptedAt == 0 { termsAcceptedAt = Date().timeIntervalSince1970 }
        if !privacyOnly { introStage = "tour"; onboarded = true }
    }
    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(.uiEaseOut(0.3)) { page += delta }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page > 0 { Button(L("Atrás")) { go(-1) } }
                Spacer()
                // Las condiciones no se saltan: «Saltar» sólo aparece después de aceptarlas.
                if terms && current != .language && current != .welcome && current != .privacy { Button(L("Saltar")) { finish() } }
            }
            .frame(height: 52)
            .padding(.horizontal, 20)

            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch current {
                        case .language:
                            // Primero el idioma (Cierre 1.0): el subtítulo, también en los otros idiomas.
                            Text(L("Elige tu idioma")).font(.largeTitle.bold()).padding(.top, 8)
                            Text(L("Choose your language · Tria la llengua · Escolle o idioma · Aukeratu hizkuntza · Elektu vian lingvon · Escolha o idioma"))
                                .foregroundStyle(.secondary).padding(.top, 8).padding(.bottom, 12)
                            Form { LanguagePicker() }
                                .scrollDisabled(true)
                                .frame(height: 520)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, -20)
                        case .welcome: welcomeStep
                        case .privacy: privacyStep
                        case .theme: themeStep
                        case .colors: colorsStep
                        case .downloads: downloadsStep
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxHeight: .infinity)

            if pages.count > 1 {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule().fill(i == page ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .frame(width: i == page ? 22 : 8, height: 8)
                    }
                }
                .animation(.uiEaseOut(0.25), value: page)
                .padding(.vertical, 14)
            }

            Button {
                if current == .privacy { termsAcceptedAt = Date().timeIntervalSince1970 }
                if last { finish() } else { go(1) }
            } label: {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .disabled(current == .privacy && !terms)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .onAppear { terms = termsAcceptedAt > 0 }
        .themed()
    }

    private var buttonTitle: String {
        switch current {
        case .language: return L("Siguiente")
        case .welcome: return L("Empezar")
        case .privacy: return !terms ? L("Acepta las condiciones para seguir") : (last ? L("Seguir") : L("Ahora no, seguir"))
        default: return last ? L("Empezar a escuchar") : L("Siguiente")
        }
    }

    @ViewBuilder private var welcomeStep: some View {
        Image("Logo").resizable().scaledToFit().frame(width: 104, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .padding(.top, 36)
        Text(L("Te damos la bienvenida a Pear Music")).font(.largeTitle.bold()).padding(.top, 26)
        Text(L("Toda la música de YouTube Music, gratis y sin anuncios. Con la pantalla apagada, sin conexión y con un Jam para escuchar con tus amigos."))
            .foregroundStyle(.secondary).padding(.top, 10).padding(.bottom, 26)
        welcomePoint("music.note", 1, L("Escucha lo que quieras"), L("Sin anuncios, sin límites y sin cuenta obligatoria."))
        welcomePoint("arrow.down.circle.fill", 2, L("Llévatela sin conexión"), L("Descarga canciones, álbumes y playlists a máxima calidad."))
        welcomePoint("checkmark.shield.fill", 5, L("Tus datos son tuyos"), L("Sin rastreo ni publicidad. Tú decides qué compartes."))
    }

    private func welcomePoint(_ icon: String, _ palette: Int, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            GradientIcon(systemName: icon, palette: palette, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
    }

    /// Condiciones (obligatorias) y telemetría (opcional), por separado y sin marcar; debajo, la cuenta opcional.
    @ViewBuilder private var privacyStep: some View {
        header(L("Antes de empezar"), L("Dos cosas, por separado. Puedes cambiar la segunda cuando quieras en Ajustes › Ayuda y soporte › Tus datos."))
        ConsentBox(checked: $terms, title: L("Acepto las condiciones de uso"),
                   text: L("Pear Music es un proyecto personal y gratuito, sin relación con YouTube ni Google. Es necesario para usar la app."),
                   link: ("Leer las condiciones", URL(string: "https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev/legal")!))
        ConsentBox(checked: Binding(get: { telemetry }, set: { telemetry = $0; Telemetry.shared.setConsent($0) }),
                   title: L("Enviar datos de rendimiento (opcional)"),
                   text: L("Modelo y sistema, versión, cuánto tarda en abrir, fluidez, memoria y minutos de uso, con un identificador aleatorio. Un resumen a la semana; nada de lo que escuchas ni buscas. Sirve sólo para que la app vaya mejor; se borra a los 90 días."),
                   link: ("Qué se envía exactamente", URL(string: "https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev/privacidad")!))
            .padding(.top, 10)
        AccountPitch().padding(.top, 22)
        Button {
            termsAcceptedAt = Date().timeIntervalSince1970
            openAccountAfterIntro = true
            if privacyOnly || last { finish() } else { go(1) }
        } label: { Text(L("Crear mi cuenta")).frame(maxWidth: .infinity) }
        .buttonStyle(PillButtonStyle(prominent: false))
        .disabled(!terms)
        .padding(.vertical, 12)
    }

    private func step<C: View>(_ i: Int, @ViewBuilder content: () -> C) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 0) { content() }.padding(.horizontal, 20) }.tag(i)
    }

    private func header(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold())
            Text(text).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    @ViewBuilder private var themeStep: some View {
        header(L("Elige tu tema"), L("Cambia el fondo, las tarjetas, el color y la letra de toda la app. Puedes cambiarlo cuando quieras en Ajustes › Aspecto."))
        let theme = AppTheme(rawValue: themeID) ?? .glass
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(AppTheme.ordered) { t in
                Button { withAnimation(.uiEaseOut(0.3)) { themeID = t.rawValue } } label: {
                    ThemeCard(theme: t, selected: t == theme)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel(t.name)
                .accessibilityAddTraits(t == theme ? .isSelected : [])
            }
        }
        Picker(L("Modo"), selection: $appearance) {
            Text(L("Automático")).tag("system")
            Text(L("Claro")).tag("light")
            Text(L("Oscuro")).tag("dark")
        }
        .pickerStyle(.segmented)
        .disabled(theme.scheme != nil)
        .padding(.top, 18)
    }

    @ViewBuilder private var colorsStep: some View {
        header(L("Colores de la portada"), L("Mientras suena una canción, la app toma colores parecidos a los de su portada. Elige cuánto; el texto siempre se lee bien."))
        let on = artworkApp || artworkPlayer
        let level = ArtworkLevel(intensity: intensity, opacity: opacity)
        ArtworkPreview(art: engine.palette[0], level: on ? level : .off)
        Picker(L("Nivel"), selection: Binding(
            get: { on && level.enabled ? (ArtworkLevel.presets.first { $0.name == level.title }?.name ?? "") : "off" },
            set: { name in
                let enable = name != "off"
                artworkApp = enable
                artworkPlayer = enable
                if let l = ArtworkLevel.presets.first(where: { $0.name == name })?.level { intensity = l.intensity; opacity = l.opacity }
            }
        )) {
            Text(L("No")).tag("off")
            ForEach(ArtworkLevel.presets, id: \.name) { Text($0.name).tag($0.name) }
        }
        .pickerStyle(.segmented)
        .padding(.top, 18)
    }

    @ViewBuilder private var downloadsStep: some View {
        header(L("Descargas"), L("Descarga una canción con su flecha, o una playlist o un álbum entero con «Descargar todo». Se guardan en este iPhone a la máxima calidad y las tienes en Biblioteca › Descargadas, también sin conexión."))
        Text(L("Calidad al escuchar sin descargar")).font(.headline)
        Picker(L("Calidad"), selection: $quality) {
            Text(L("Máxima")).tag("max")
            Text(L("Ahorro de datos")).tag("low")
        }
        .pickerStyle(.segmented)
        .padding(.top, 10)
        Text(quality == "low" ? L("Gasta menos datos móviles (48 kbps).") : L("Mejor sonido (AAC 128 kbps)."))
            .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
    }
}

/// Casilla de consentimiento de la guía: grande, sin marcar por defecto y con su enlace. Igual que `ConsentBox` en
/// Android.
private struct ConsentBox: View {
    @Binding var checked: Bool
    let title: String
    let text: String
    let link: (String, URL)

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.title2).foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Link(link.0, destination: link.1).font(.subheadline.weight(.semibold)).padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .contentShape(Rectangle())
        .onTapGesture { checked.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(checked ? L("Marcada") : L("Sin marcar"))
    }
}
