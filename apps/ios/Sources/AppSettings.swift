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
    static func visible(_ order: [String], searchTab: Bool) -> [String] {
        searchTab ? order.flatMap { $0 == home ? [home, search] : [$0] } : order
    }

    /// Pestaña al abrir: la última usada, si sigue visible. La primera vez, Inicio: abrir en Descubrir
    /// pondría música sola nada más instalar.
    static func start(last: String, visible: [String]) -> String { visible.contains(last) ? last : home }

    /// Etiqueta de la pestaña en el `TabView` (Descubrir se llamaba «reels» por dentro).
    static func tag(_ key: String) -> String { key == discover ? Demo.Tab.reels.rawValue : key }
    static func key(_ tag: String) -> String { tag == Demo.Tab.reels.rawValue ? discover : tag }

    static func title(_ key: String) -> String {
        switch key {
        case discover: return "Descubrir"
        case home: return "Inicio"
        case search: return "Buscar"
        case library: return "Biblioteca"
        default: return "Ajustes"
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
        .confirmationDialog("¿Restablecer \(section)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Restablecer", role: .destructive) { withAnimation(.uiEaseOut(0.25)) { reset() } }
            Button("Cancelar", role: .cancel) {}
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
    case theme, player, artwork, tabs, bar, icon, playback, downloads, library, manage, about, help, support, advanced
}

private struct SettingEntry: Identifiable {
    let title: String
    let section: String
    let keywords: String
    let destination: SettingsDestination
    var id: String { section + title }
}

private let settingsIndex: [SettingEntry] = [
    SettingEntry(title: "Tema", section: "Aspecto", keywords: "color fondo cristal neón aire sistema apariencia", destination: .theme),
    SettingEntry(title: "Claro u oscuro", section: "Aspecto", keywords: "modo noche oscuro claro automático", destination: .theme),
    SettingEntry(title: "Reproductor", section: "Aspecto", keywords: "casete vinilo air normal", destination: .player),
    SettingEntry(title: "Efecto en los títulos", section: "Aspecto", keywords: "símbolos animación scramble", destination: .player),
    SettingEntry(title: "Colores de la portada", section: "Aspecto", keywords: "carátula color tinte sutil equilibrado intenso", destination: .artwork),
    SettingEntry(title: "Pestañas", section: "Aspecto", keywords: "orden barra descubrir inicio biblioteca", destination: .tabs),
    SettingEntry(title: "Barra inferior", section: "Aspecto", keywords: "barra simpmusic plegar buscar", destination: .bar),
    SettingEntry(title: "Icono de la app", section: "Aspecto", keywords: "logo encendido violeta pantalla de inicio", destination: .icon),
    SettingEntry(title: "Calidad al escuchar", section: "Reproducción", keywords: "streaming datos ahorro máxima kbps", destination: .playback),
    SettingEntry(title: "Seguir con canciones parecidas", section: "Reproducción", keywords: "radio infinita autoplay automático cola acabar", destination: .playback),
    SettingEntry(title: "Fundido entre canciones", section: "Reproducción", keywords: "crossfade transición suave volumen cortes", destination: .playback),
    SettingEntry(title: "Copia automática", section: "Biblioteca", keywords: "copia seguridad backup icloud drive guardar exportar", destination: .library),
    SettingEntry(title: "AirPlay", section: "Reproducción", keywords: "salida audio altavoz homepod apple tv bluetooth", destination: .playback),
    SettingEntry(title: "Canciones descargadas", section: "Descargas", keywords: "espacio offline sin conexión borrar", destination: .downloads),
    SettingEntry(title: "Ordenar playlists", section: "Biblioteca", keywords: "orden a-z recientes a mano", destination: .library),
    SettingEntry(title: "Descargadas y Favoritos", section: "Biblioteca", keywords: "carrusel tu música", destination: .library),
    SettingEntry(title: "Dónde está Buscar", section: "Biblioteca", keywords: "buscar pestaña inicio barra", destination: .library),
    SettingEntry(title: "Eliminar playlists", section: "Biblioteca", keywords: "borrar quitar", destination: .manage),
    SettingEntry(title: "Informar de un error", section: "Ayuda y soporte", keywords: "bug fallo problema soporte reporte escarabajo contacto", destination: .support),
    SettingEntry(title: "Guía inicial", section: "Ayuda y soporte", keywords: "tutorial bienvenida empezar", destination: .help),
    SettingEntry(title: "Acerca de", section: "Ayuda y soporte", keywords: "versión créditos licencia", destination: .about),
    SettingEntry(title: "Vaciar caché de carátulas", section: "Avanzado", keywords: "memoria imágenes portadas", destination: .advanced),
    SettingEntry(title: "Tolerancia de duración", section: "Avanzado", keywords: "emparejar importar spotify segundos coincidencia", destination: .advanced),
]

struct SettingsView: View {
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
        NavigationStack {
            Form {
                if query.trimmingCharacters(in: .whitespaces).isEmpty { sections } else { results }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar en Ajustes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { SupportView() } label: { Image(systemName: "ladybug") }
                        .accessibilityLabel("Informar de un error")
                }
            }
            .navigationTitle("Ajustes")
            .themed()
            .demoRoute(.themePicker) { AppearanceSettings() }
            .miniPlayer()
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            NavigationLink { AspectSettings() } label: {
                SettingsRow(icon: "paintpalette.fill", palette: 1, title: "Aspecto", value: nil,
                            subtitle: "\(theme.name) · \((DeckStyle(rawValue: deckID) ?? .normal).name)"
                                + ((artworkPlayer || artworkApp) && level.enabled ? " · Colores \(level.title.lowercased())" : ""))
            }
            NavigationLink { AudioSettings() } label: {
                SettingsRow(icon: "waveform", palette: 3, title: "Reproducción", value: nil,
                            subtitle: quality == "low" ? "Ahorro de datos" : "Calidad máxima")
            }
            NavigationLink { DownloadsSettings() } label: {
                SettingsRow(icon: "arrow.down.circle.fill", palette: 2, title: "Descargas", value: nil,
                            subtitle: downloads.songs.isEmpty ? "Ninguna canción descargada"
                                : "\(songCount(downloads.songs.count)) · \(ByteCountFormatter.string(fromByteCount: downloads.totalBytes(), countStyle: .file))")
            }
            NavigationLink { LibrarySettings() } label: {
                SettingsRow(icon: "books.vertical.fill", palette: 0, title: "Biblioteca", value: nil,
                            subtitle: "Playlists: \(Self.sortTitle(playlistSort).lowercased()) · Buscar \(searchPlacement == "tab" ? "en su pestaña" : "en Inicio")")
            }
            NavigationLink { HelpSettings() } label: {
                SettingsRow(icon: "info.circle.fill", palette: 6, title: "Ayuda y soporte", value: nil,
                            subtitle: "Informar de un error · Guía inicial · Versión \(AboutView.version)")
            }
        }
        .glassRow()

        // Lo técnico, plegado: sólo quien lo busca lo ve.
        Section {
            DisclosureGroup(isExpanded: $advanced.animation(.uiEaseOut(0.25))) {
                LabeledContent("Calidad de descarga", value: "Máxima")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tolerancia de duración")
                    Text("Al importar de Spotify o Apple Music, cuánto puede durar distinta una canción para darla por buena")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("Tolerancia", selection: $tolerance) {
                        ForEach([2, 4, 6, 10], id: \.self) { Text("±\($0) s").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
                Button(cacheCleared ? "Caché vaciada" : "Vaciar caché de carátulas") {
                    imageMemory.removeAllObjects()
                    URLCache.shared.removeAllCachedResponses()
                    cacheCleared = true
                }
                .disabled(cacheCleared)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avanzado")
                    if !advanced { Text("Calidad de descarga, tolerancia al importar y caché").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        } footer: {
            if advanced { Text("Las descargas se guardan siempre a la máxima calidad (AAC 128 kbps), así suenan igual sin conexión.") }
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
        case .icon: AppIconSettings()
        case .playback: AudioSettings()
        case .downloads: DownloadsSettings()
        case .library: LibrarySettings()
        case .manage: ManagePlaylistsView()
        case .about: AboutView()
        case .support: SupportView()
        case .help, .advanced: HelpSettings()
        }
    }

    static func sortTitle(_ sort: String) -> String {
        ["name": "A-Z", "nameDesc": "Z-A", "count": "Por tamaño", "custom": "A mano"][sort] ?? "Recientes"
    }
}

// MARK: Aspecto
struct AspectSettings: View {
    @AppStorage("barStyle") private var barStyle = "classic"
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
            return ["light": "claro", "dark": "oscuro"][appearance] ?? "claro u oscuro según el iPhone"
        }()
        Form {
            Section {
                NavigationLink { AppearanceSettings() } label: {
                    SettingsRow(icon: "paintpalette.fill", palette: 1, title: "Tema", value: nil, subtitle: "\(theme.name) · \(mode)")
                }
                NavigationLink { PlayerSettings() } label: {
                    SettingsRow(icon: "play.circle.fill", palette: 0, title: "Reproductor", value: nil,
                                subtitle: (DeckStyle(rawValue: deckID) ?? .normal).name + (scramble ? " · títulos con efecto" : ""))
                }
                NavigationLink { ArtworkColorsSettings() } label: {
                    SettingsRow(icon: "sparkles", palette: 5, title: "Colores de la portada", value: nil,
                                subtitle: !(artworkPlayer || artworkApp) || !level.enabled ? "Desactivado"
                                    : level.title + " · " + [artworkPlayer ? "reproductor" : nil, artworkApp ? "resto de la app" : nil].compactMap { $0 }.joined(separator: " y "))
                }
                NavigationLink { TabOrderSettings() } label: {
                    SettingsRow(icon: "arrow.left.arrow.right", palette: 7, title: "Pestañas", value: nil,
                                subtitle: TabOrder.decode(tabOrderRaw).map(TabOrder.title).joined(separator: ", "))
                }
                NavigationLink { AppIconSettings() } label: {
                    SettingsRow(icon: "app.badge", palette: 3, title: "Icono de la app", value: nil, subtitle: AppIcon.current.title)
                }
            }
            .glassRow()

            Section {
                Picker("Barra inferior", selection: $barStyle) {
                    Text("Clásica").tag("classic")
                    Text("Estilo SimpMusic").tag("simpmusic")
                }
                .pickerStyle(.segmented)
            } header: { Text("Barra inferior") } footer: {
                Text(barStyle == "simpmusic"
                     ? "Tus pestañas en la barra y Buscar aparte, como SimpMusic. Ajustes y el Jam están arriba en Inicio. En iOS 26 la barra se pliega al bajar por una lista."
                     : "Las pestañas de siempre.")
            }
            .glassRow()

            ResetSection(section: "Aspecto", what: "Vuelven el tema Cristal, el reproductor Normal, los colores de la portada apagados y el orden de pestañas de fábrica.") {
                SettingsReset.appearance()
            }
        }
        .navigationTitle("Aspecto")
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
                Toggle(isOn: $artworkPlayer) { titled("En el reproductor", "Fondo con la carátula desenfocada y controles de su color") }
                Toggle(isOn: $artworkApp) { titled("En el resto de la app", "Botones del color de la canción y fondos y menús con un toque") }
            } header: { Text("Dónde") } footer: {
                Text("Al sonar una canción, la app y los menús toman colores parecidos a los de su portada, como Descubrir.")
            }
            .glassRow()

            Section {
                Picker("Nivel", selection: presetBinding) {
                    Text("No").tag("off")
                    ForEach(ArtworkLevel.presets, id: \.name) { Text($0.name).tag($0.name) }
                }
                .pickerStyle(.segmented)
                DisclosureGroup(isExpanded: $fine.animation(.uiEaseOut(0.25))) {
                    slider("Exageración del color", "Cuánto se parecen los botones al color de la portada", $intensity)
                    slider("Opacidad", "Cuánto se tiñen los fondos y los menús", $opacity)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ajuste fino")
                        if level.title == "Personalizado" { Text("Personalizado").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            } header: { Text("Cuánto") } footer: {
                Text("El texto y los iconos mantienen siempre un contraste legible, aunque la portada sea muy clara o muy viva.")
            }
            .glassRow()
        }
        .navigationTitle("Colores de la portada")
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
                Text("\(Int((value.wrappedValue * 100).rounded())) %").foregroundStyle(.secondary).monospacedDigit()
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
                    Text("Canción que suena").font(.callout.weight(.semibold))
                    Text("Artista").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "heart.fill").foregroundStyle(accent)
            }
            HStack(spacing: 8) {
                Text("Reproducir").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 36).background(accent, in: Capsule())
                Text("Menú").font(.subheadline.weight(.semibold))
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
        .accessibilityLabel("Vista previa de los colores de la portada")
    }
}

// MARK: Pestañas (Fase 3)
/// Se arrastran para cambiar el orden; Ajustes se puede mover pero no quitar.
struct TabOrderSettings: View {
    @AppStorage("tabOrder") private var tabOrderRaw = ""

    var body: some View {
        let order = TabOrder.decode(tabOrderRaw)
        Form {
            Section {
                ForEach(order, id: \.self) { key in
                    Label(TabOrder.title(key), systemImage: TabOrder.symbol(key))
                }
                .onMove { from, to in
                    var o = order
                    o.move(fromOffsets: from, toOffset: to)
                    tabOrderRaw = TabOrder.encode(o)
                }
            } header: { Text("Orden de la barra") } footer: {
                Text("Arrastra ≡ para cambiar el orden; deslizar a los lados sigue el mismo orden. La app se abre en la última pestaña que usaste. Ajustes siempre está en la barra.")
            }
            .glassRow()

            Section {
                Button {
                    withAnimation(.uiEaseOut(0.25)) { tabOrderRaw = TabOrder.encode(TabOrder.defaultOrder) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Orden de fábrica")
                        Text("Descubrir, Inicio, Biblioteca, Ajustes").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .disabled(order == TabOrder.defaultOrder)
            }
            .glassRow()
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Pestañas")
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

// MARK: Icono de la app (Fase 5)
/// El original de encendido (por defecto) o el violeta. Mismas claves que `AppIcon` en Android.
enum AppIcon: String, CaseIterable, Identifiable {
    case power, violet
    var id: String { rawValue }
    var title: String { self == .power ? "Encendido" : "Violeta" }
    /// Nombre del icono alternativo en el catálogo (nil = el principal).
    var alternateName: String? { self == .power ? nil : "AppIcon-Violeta" }
    /// Vista previa (no se puede pintar un AppIcon desde el código).
    var preview: String { self == .power ? "Logo" : "IconPreviewViolet" }

    static var current: AppIcon { UIApplication.shared.alternateIconName == nil ? .power : .violet }
}

/// iOS avisa con una alerta del sistema cada vez que se cambia el icono; no se puede evitar.
struct AppIconSettings: View {
    @State private var current = AppIcon.current
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ForEach(AppIcon.allCases) { icon in
                        Button {
                            guard icon != current, UIApplication.shared.supportsAlternateIcons else { return }
                            UIApplication.shared.setAlternateIconName(icon.alternateName) { error in
                                Task { @MainActor in
                                    if error == nil { current = icon } else { failed = true }
                                }
                            }
                        } label: {
                            VStack(spacing: 10) {
                                Image(icon.preview).resizable().scaledToFit()
                                    .frame(width: 112, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                                        .strokeBorder(icon == current ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.12)), lineWidth: icon == current ? 3 : 1))
                                Text(icon.title + (icon == .power ? " (original)" : ""))
                                    .font(.subheadline.weight(icon == current ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).opacity(icon == current ? 1 : 0)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TactileButtonStyle())
                        .accessibilityLabel("Icono \(icon.title)")
                        .accessibilityAddTraits(icon == current ? .isSelected : [])
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            } footer: {
                Text("iOS enseña un aviso cada vez que cambias el icono. El de la pantalla de inicio cambia al momento.")
            }
        }
        .alert("No se pudo cambiar el icono", isPresented: $failed) { Button("Vale", role: .cancel) {} }
        .navigationTitle("Icono de la app")
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
                Picker("Calidad", selection: $quality) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Máxima")
                        Text("Mejor sonido; gasta más datos").font(.footnote).foregroundStyle(.secondary)
                    }.tag("max")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ahorro de datos")
                        Text("Para escuchar con datos móviles").font(.footnote).foregroundStyle(.secondary)
                    }.tag("low")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text("Calidad al escuchar") } footer: {
                Text("«Máxima» usa AAC a 128 kbps; «Ahorro de datos», 48 kbps. Se aplica desde la siguiente canción.")
            }
            .glassRow()

            Section {
                Toggle("Seguir con canciones parecidas", isOn: $autoplay)
            } footer: {
                Text("Cuando se acaba lo que estás escuchando y el bucle está apagado, se añaden canciones parecidas a la última.")
            }
            .glassRow()

            Section {
                Picker("Fundido", selection: $crossfade) {
                    ForEach(Fade.options, id: \.self) { s in Text(s == 0 ? "No" : "\(s) s").tag(s) }
                }
                .pickerStyle(.segmented)
            } header: { Text("Fundido entre canciones") } footer: {
                Text(crossfade == 0 ? "Cada canción empieza y acaba a su volumen." : "La canción baja de volumen en sus últimos \(crossfade) s y la siguiente entra suavemente. Útil para listas variadas; en álbumes que van seguidos, mejor «No».")
            }
            .glassRow()

            Section {
                HStack {
                    SettingsRow(icon: "airplayaudio", palette: 7, title: "AirPlay", value: nil, subtitle: "Altavoces, HomePod y Apple TV")
                    RoutePicker().frame(width: 44, height: 44)
                }
            } footer: {
                Text("El bucle (no repetir, repetir lista o canción) se cambia en el reproductor.")
            }
            .glassRow()

            ResetSection(section: "Reproducción", what: "La calidad al escuchar vuelve a «Máxima» se quita el fundido y se vuelve a seguir con canciones parecidas.") { SettingsReset.playback() }
        }
        .navigationTitle("Reproducción")
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
                LabeledContent("Canciones", value: "\(downloads.songs.count)")
                LabeledContent("Espacio usado", value: ByteCountFormatter.string(fromByteCount: downloads.totalBytes(), countStyle: .file))
            } footer: {
                Text("Las descargas se guardan en este iPhone a la máxima calidad y se ven en Biblioteca › Descargadas. Para bajar una lista o un álbum entero, usa «Descargar todo» en su página.")
            }
            .glassRow()

            if !downloads.songs.isEmpty {
                Section {
                    HoldToConfirmButton(title: "Mantén para borrar las descargas") { downloads.removeAll() }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    Text("Dejarán de estar disponibles sin conexión. Las playlists y los favoritos no se tocan.")
                }
                .glassRow()
            }
        }
        .navigationTitle("Descargas")
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
                NavigationLink { SupportView() } label: {
                    SettingsRow(icon: "ladybug.fill", palette: 0, title: "Informar de un error", value: nil,
                                subtitle: "Cuéntanos qué ha fallado; puedes añadir capturas")
                }
                Button { onboarded = false } label: {
                    SettingsRow(icon: "graduationcap.fill", palette: 2, title: "Guía inicial", value: nil,
                                subtitle: "Vuelve a ver los tres pasos del principio: tema, colores y descargas")
                }
                .foregroundStyle(.primary)
                NavigationLink { AboutView() } label: {
                    SettingsRow(icon: "info.circle.fill", palette: 6, title: "Acerca de", value: nil, subtitle: "Versión \(AboutView.version) y créditos")
                }
            }
            .glassRow()
        }
        .navigationTitle("Ayuda y soporte")
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

// MARK: - Guía inicial (Fase 4)
/// Tres pantallas la primera vez —tema, colores de la portada y descargas— que dejan la app configurada sin
/// entrar a Ajustes. Mismos pasos y textos que `OnboardingScreen` en Android.
struct OnboardingView: View {
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("artworkColorsPlayer") private var artworkPlayer = false
    @AppStorage("artworkColorsApp") private var artworkApp = false
    @AppStorage("artworkIntensity") private var intensity = ArtworkLevel.balanced.intensity
    @AppStorage("artworkOpacity") private var opacity = ArtworkLevel.balanced.opacity
    @AppStorage("quality") private var quality = "max"
    @EnvironmentObject var engine: ThemeEngine
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page > 0 { Button("Atrás") { withAnimation(.uiEaseOut(0.3)) { page -= 1 } } }
                Spacer()
                Button("Saltar") { onboarded = true }
            }
            .frame(height: 52)
            .padding(.horizontal, 20)

            TabView(selection: $page) {
                step(0) { themeStep }
                step(1) { colorsStep }
                step(2) { downloadsStep }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Capsule().fill(i == page ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            .animation(.uiEaseOut(0.25), value: page)
            .padding(.vertical, 14)

            Button {
                if page < 2 { withAnimation(.uiEaseOut(0.3)) { page += 1 } } else { onboarded = true }
            } label: {
                Text(page < 2 ? "Siguiente" : "Empezar").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .themed()
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
        header("Elige tu tema", "Cambia el fondo, las tarjetas, el color y la letra de toda la app. Puedes cambiarlo cuando quieras en Ajustes › Aspecto.")
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
        Picker("Modo", selection: $appearance) {
            Text("Automático").tag("system")
            Text("Claro").tag("light")
            Text("Oscuro").tag("dark")
        }
        .pickerStyle(.segmented)
        .disabled(theme.scheme != nil)
        .padding(.top, 18)
    }

    @ViewBuilder private var colorsStep: some View {
        header("Colores de la portada", "Mientras suena una canción, la app toma colores parecidos a los de su portada. Elige cuánto; el texto siempre se lee bien.")
        let on = artworkApp || artworkPlayer
        let level = ArtworkLevel(intensity: intensity, opacity: opacity)
        ArtworkPreview(art: engine.palette[0], level: on ? level : .off)
        Picker("Nivel", selection: Binding(
            get: { on && level.enabled ? (ArtworkLevel.presets.first { $0.name == level.title }?.name ?? "") : "off" },
            set: { name in
                let enable = name != "off"
                artworkApp = enable
                artworkPlayer = enable
                if let l = ArtworkLevel.presets.first(where: { $0.name == name })?.level { intensity = l.intensity; opacity = l.opacity }
            }
        )) {
            Text("No").tag("off")
            ForEach(ArtworkLevel.presets, id: \.name) { Text($0.name).tag($0.name) }
        }
        .pickerStyle(.segmented)
        .padding(.top, 18)
    }

    @ViewBuilder private var downloadsStep: some View {
        header("Descargas", "Descarga una canción con su flecha, o una playlist o un álbum entero con «Descargar todo». Se guardan en este iPhone a la máxima calidad y las tienes en Biblioteca › Descargadas, también sin conexión.")
        Text("Calidad al escuchar sin descargar").font(.headline)
        Picker("Calidad", selection: $quality) {
            Text("Máxima").tag("max")
            Text("Ahorro de datos").tag("low")
        }
        .pickerStyle(.segmented)
        .padding(.top, 10)
        Text(quality == "low" ? "Gasta menos datos móviles (48 kbps)." : "Mejor sonido (AAC 128 kbps).")
            .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
    }
}
