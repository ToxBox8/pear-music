import SwiftUI
import UIKit
import AVKit

// MARK: - Selector de AirPlay (altavoces, HomePod, Apple TV…)
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        v.tintColor = .label
        v.activeTintColor = UIColor(Tokens.Brand.violet)
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Tarjeta según el tema
// Con el tema Cristal en iOS 26 usa el cristal nativo del sistema; el resto de temas
// (y Cristal en versiones anteriores) dibujan su propia superficie.
struct GlassCard: ViewModifier {
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    let radius: CGFloat
    let onlyWhenGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let theme = AppTheme(rawValue: themeID) ?? .glass
        if theme == .glass {
            native(content)
        } else if theme.styled {
            content.background(ThemeSurface(radius: radius)).shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        } else if onlyWhenGlass {
            content
        } else {
            content.background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func native(_ c: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            c.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            c.background(ThemeSurface(radius: radius)).shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
        #else
        c.background(ThemeSurface(radius: radius)).shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        #endif
    }
}

/// Fondo animado del tema, listas transparentes y barras translúcidas.
struct Themed: ViewModifier {
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @AppStorage("artworkColorsApp") private var artworkApp = false
    @AppStorage("artworkIntensity") private var intensity = ArtworkLevel.balanced.intensity
    @AppStorage("artworkOpacity") private var opacity = ArtworkLevel.balanced.opacity
    @EnvironmentObject var engine: ThemeEngine
    @EnvironmentObject var player: Player
    func body(content: Content) -> some View {
        let styled = (AppTheme(rawValue: themeID) ?? .glass).styled
        let level = ArtworkLevel(intensity: intensity, opacity: opacity)
        // «Colores de la portada» en la app: un toque del color de la canción en el fondo.
        let tint = artworkApp && level.enabled && player.current != nil
        content
            .scrollContentBackground(styled || tint ? .hidden : .automatic)
            .background {
                if styled { ThemeBackdrop() } else if tint { Color(uiColor: .systemGroupedBackground).ignoresSafeArea() }
                if tint { engine.palette[0].opacity(level.backgroundTint).ignoresSafeArea().allowsHitTesting(false) }
            }
            .toolbarBackground(styled ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.bar), for: .navigationBar, .tabBar)
    }
}

extension View {
    func glassCard(radius: CGFloat = 20, onlyWhenGlass: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, onlyWhenGlass: onlyWhenGlass))
    }
    func themed() -> some View { modifier(Themed()) }
}

// MARK: - Ajustes
/// Fila de ajustes al estilo de la app Ajustes: icono con fondo de color, título y valor actual.
struct SettingsRow: View {
    let icon: String
    let palette: Int
    let title: String
    let value: String?
    /// Debajo del nombre: el valor actual o una frase que explica la opción.
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(systemName: icon, palette: palette, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
        }
    }
}

// MARK: Buscar
struct SearchSettings: View {
    @AppStorage("searchPlacement") private var searchPlacement = "home"

    var body: some View {
        Form {
            Section {
                Picker(L("Buscar"), selection: $searchPlacement) {
                    Label("Barra arriba en Inicio", systemImage: "house").tag("home")
                    Label("Pestaña aparte", systemImage: "magnifyingglass").tag("tab")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text(L("Dónde buscar")) } footer: {
                Text(searchPlacement == "tab"
                     ? L("Buscar tiene su propia pestaña en la barra de abajo.")
                     : L("La barra de búsqueda está siempre arriba en Inicio y la pestaña Buscar desaparece."))
            }
            .glassRow()
        }
        .navigationTitle(L("Buscar"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

// MARK: Tema
struct AppearanceSettings: View {
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @AppStorage("appearance") private var appearance = "system"

    private var theme: AppTheme { AppTheme(rawValue: themeID) ?? .glass }

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(AppTheme.ordered) { t in
                        Button {
                            withAnimation(.uiEaseOut(0.3)) { themeID = t.rawValue }
                        } label: { ThemeCard(theme: t, selected: t == theme) }
                        .buttonStyle(TactileButtonStyle())
                        .accessibilityLabel(t.name)
                        .accessibilityAddTraits(t == theme ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } header: { Text(L("Tema")) } footer: {
                Text(L("El tema cambia el fondo, las tarjetas, el color y la letra. Los fondos toman los colores de la carátula y se animan más mientras suena música."))
            }

            Section {
                Picker(L("Modo"), selection: $appearance) {
                    Text(L("Automático")).tag("system")
                    Text(L("Claro")).tag("light")
                    Text(L("Oscuro")).tag("dark")
                }
                .pickerStyle(.segmented)
                .disabled(theme.scheme != nil)
            } header: { Text(L("Claro u oscuro")) } footer: {
                if let forced = theme.scheme {
                    Text(forced == .dark ? L("«{0}» usa siempre el modo oscuro.", theme.name) : L("«{0}» usa siempre el modo claro.", theme.name))
                }
            }
            .glassRow()
        }
        .navigationTitle(L("Tema"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

/// Muestra de un tema: su fondo (fotograma fijo), una tarjeta con su letra y su acento.
struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                BackdropPreview(theme: theme)
                HStack(spacing: 6) {
                    Circle().fill(theme.accent).frame(width: 8, height: 8)
                    Text(L("Aa")).font(.system(.subheadline, design: theme.fontDesign).weight(.semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(ThemeSurface(radius: 10, theme: theme))
                .padding(8)
            }
            .frame(height: 118)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? theme.accent : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, theme.accent)
                        .padding(8)
                }
            }
            .environment(\.colorScheme, theme.scheme ?? scheme)

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name).font(.subheadline.weight(.semibold))
                Text(theme.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: Reproductor
struct PlayerSettings: View {
    @AppStorage("scramble") private var scramble = true

    var body: some View {
        Form {
            Section {
                DeckPicker()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } header: { Text(L("Reproductor multimedia")) } footer: {
                Text(L("Casete: gira una bobina o arrastra la cinta para avanzar o rebobinar. Vinilo: gira el disco con el dedo o mueve el brazo. Con el iPhone en horizontal, el casete o el vinilo ocupan toda la pantalla. También puedes cambiarlo manteniendo pulsado el mini reproductor."))
            }

            Section {
                Toggle(isOn: $scramble) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Efecto en los títulos"))
                        Text(L("Al cambiar de canción, el título aparece entre símbolos que se ordenan"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .glassRow()
        }
        .navigationTitle(L("Reproductor"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

// MARK: Biblioteca
struct LibrarySettings: View {
    @AppStorage("playlistSort") private var sort = "recent"
    @AppStorage("smartPlacement") private var placement = "playlists"
    @AppStorage("searchPlacement") private var searchPlacement = "home"
    @State private var showReorder = false

    var body: some View {
        Form {
            Section(L("Ordenar playlists por")) {
                Picker(L("Ordenar"), selection: $sort) {
                    Text(L("Añadidas recientemente")).tag("recent")
                    Text(L("Nombre (A-Z)")).tag("name")
                    Text(L("Nombre (Z-A)")).tag("nameDesc")
                    Text(L("Nº de canciones")).tag("count")
                    Text(L("A mano")).tag("custom")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .glassRow()

            Section {
                Button { showReorder = true } label: { Label("Ordenar a mano", systemImage: "line.3.horizontal") }
            } footer: {
                Text(L("Arrastra las playlists, Descargadas y Favoritos para colocarlas donde quieras."))
            }
            .glassRow()

            Section {
                Picker(L("Descargadas y Favoritos"), selection: $placement) {
                    Text(L("En Playlists (portada grande)")).tag("playlists")
                    Text(L("En «Tu música» (fila)")).tag("music")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text(L("Descargadas y Favoritos")) } footer: {
                Text(placement == "music" ? L("Aparecen como filas en «Tu música», encima de Canciones.") : L("Aparecen con su portada grande en el carrusel de Playlists."))
            }
            .glassRow()

            Section {
                Picker(L("Buscar"), selection: $searchPlacement) {
                    Text(L("Barra arriba en Inicio")).tag("home")
                    Text(L("Pestaña aparte")).tag("tab")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text(L("Dónde está Buscar")) } footer: {
                Text(searchPlacement == "tab"
                     ? L("Buscar tiene su propia pestaña en la barra de abajo, justo después de Inicio.")
                     : L("La barra de búsqueda está siempre arriba en Inicio."))
            }
            .glassRow()

            BackupSection()

            // Al final y en otra pantalla, para no borrar nada sin querer.
            Section {
                NavigationLink { ManagePlaylistsView() } label: {
                    Label("Eliminar playlists", systemImage: "trash").foregroundStyle(.red)
                }
            } footer: {
                Text(L("Antes de borrar se pide confirmación."))
            }
            .glassRow()

            ResetSection(section: L("Biblioteca"), what: L("Las playlists vuelven a ordenarse por recientes, Descargadas y Favoritos al carrusel y Buscar a Inicio. No se borra ninguna playlist.")) {
                SettingsReset.library()
            }
        }
        .navigationTitle(L("Biblioteca"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
        .sheet(isPresented: $showReorder) { ReorderPlaylistsView() }
    }
}

// MARK: Acerca de
struct AboutView: View {

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image("Logo")
                        .resizable().scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                    Text(L("Pear Music")).font(.title2.bold())
                    Text(L("Versión {0}", Self.version)).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Text(L("Cliente no oficial de YouTube Music. Usa una API no oficial de YouTube, así que puede dejar de funcionar si YouTube la cambia. Las descargas se guardan en este iPhone."))
                    .font(.subheadline)
            }
            .glassRow()

            Section(L("Créditos")) {
                Link(destination: URL(string: "https://www.dqnamo.com/kitchen")!) {
                    Label(L("Componentes inspirados en The Kitchen de dqnamo"), systemImage: "fork.knife")
                }
                // SimpMusic (GPL-3.0): la barra estilo SimpMusic sale de su diseño. Lo pidió Toxbox.
                Link(destination: URL(string: "https://github.com/maxrave-dev/SimpMusic")!) {
                    Label(L("Barra inferior inspirada en SimpMusic, de maxrave-dev (GPL-3.0)"), systemImage: "music.note.house")
                }
            }
            .glassRow()
        }
        .navigationTitle(L("Acerca de"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}
