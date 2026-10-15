import SwiftUI
import UIKit

// MARK: - Temas
// Cada tema cambia toda la interfaz: fondo animado, superficie de tarjetas y listas,
// color de acento, tipografía y (si su estética lo exige) modo claro/oscuro.
enum AppTheme: String, CaseIterable, Identifiable {
    case glass, air, neon, plain

    var id: String { rawValue }

    /// Tema guardado; los temas retirados (partículas, ASCII…) pasan a Cristal.
    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .glass
    }

    /// Orden de la galería de Ajustes (el mismo que en Android).
    static var ordered: [AppTheme] { Tokens.themeOrder.compactMap(AppTheme.init(rawValue:)) }

    private var spec: Tokens.ThemeSpec { Tokens.themes[rawValue]! }

    var name: String { L(spec.name) }
    var blurb: String { L(spec.blurb) }

    var symbol: String {
        switch self {
        case .air: return "circle.dotted"
        case .glass: return "drop.fill"
        case .neon: return "lightbulb.max.fill"
        case .plain: return "iphone"
        }
    }

    var accent: Color { spec.accent }
    /// Texto sobre un relleno de acento.
    var onAccent: Color { spec.onAccent }
    /// Modo impuesto por la estética del tema (nil = el que elija el usuario).
    var scheme: ColorScheme? { spec.scheme }
    var fontDesign: Font.Design { spec.rounded ? .rounded : .default }
    /// Radio máximo de esquinas.
    var maxRadius: CGFloat { spec.maxRadius }

    /// Con fondo animado y superficies propias (todos menos Sistema).
    var styled: Bool { self != .plain }
}

/// Fondo de tarjetas, filas y barras según el tema.
struct ThemeSurface: View {
    var radius: CGFloat = Tokens.Radius.card
    /// Para mostrar la superficie de otro tema (vista previa); nil = el tema activo.
    var theme: AppTheme? = nil
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    var body: some View {
        let t = theme ?? AppTheme(rawValue: themeID) ?? .glass
        let shape = RoundedRectangle(cornerRadius: min(radius, t.maxRadius), style: .continuous)
        switch t {
        case .air:
            // Como las piezas blancas de Air OS sobre el papel gris: sin borde, sombra mínima.
            shape.fill(LinearGradient(colors: [Color(hex: 0xFBFBFC), Color(hex: 0xECEEF1)], startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .shadow(color: Color(hex: 0x3A4048, opacity: 0.08), radius: 14, y: 6)
        case .glass:
            shape.fill(.ultraThinMaterial)
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.06), .white.opacity(0.22)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        case .neon:
            shape.fill(Color(hex: 0x0B0814, opacity: 0.8))
                .overlay(shape.strokeBorder(t.accent.opacity(0.9), lineWidth: 1.2))
                .shadow(color: t.accent.opacity(0.55), radius: 9)
        case .plain:
            shape.fill(Color(.secondarySystemGroupedBackground))
        }
    }
}

extension AppTheme {
    /// Tipografía de títulos grandes: Aire usa un grotesco negro y apretado, el resto conserva su voz.
    func display(_ size: CGFloat) -> Font {
        self == .air ? .airDisplay(size) : .system(size: size, weight: .bold, design: fontDesign)
    }
    func displayTracking(_ size: CGFloat) -> CGFloat { self == .air ? -size * 0.025 : 0 }
}

/// Título grande según el tema activo.
/// Crece con el tamaño de texto del sistema (Dynamic Type), como el resto de la app.
struct DisplayTitle: ViewModifier {
    @ScaledMetric private var size: CGFloat
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    init(size: CGFloat) { _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle) }
    func body(content: Content) -> some View {
        let t = AppTheme(rawValue: themeID) ?? .glass
        content.font(t.display(size)).tracking(t.displayTracking(size))
    }
}

extension View {
    func displayTitle(_ size: CGFloat) -> some View { modifier(DisplayTitle(size: size)) }
}

/// Aplica acento, tipografía y modo del tema a toda la app.
struct ThemeAppearance: ViewModifier {
    /// Descubrir a la vista: todo oscuro, para que la hora, la batería y la barra de pestañas
    /// se lean sobre el feed negro (como `onBarsDark` en Android).
    var forceDark = false
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("artworkColorsApp") private var artworkApp = false
    @AppStorage("artworkIntensity") private var intensity = ArtworkLevel.balanced.intensity
    @AppStorage("artworkOpacity") private var opacity = ArtworkLevel.balanced.opacity
    @EnvironmentObject var engine: ThemeEngine
    @EnvironmentObject var player: Player
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let t = AppTheme(rawValue: themeID) ?? .glass
        let userScheme: ColorScheme? = appearance == "light" ? .light : appearance == "dark" ? .dark : nil
        let dark = forceDark || (t.scheme ?? userScheme ?? systemScheme) == .dark
        // «Colores de la carátula» en la app: el acento sale de la canción que suena.
        let level = ArtworkLevel(intensity: intensity, opacity: opacity)
        let accent = artworkApp && level.enabled && player.current != nil
            ? engine.palette[0].artworkAccent(dark: dark, level: level, base: t.accent) : t.accent
        let styled = content
            .tint(accent)
            .preferredColorScheme(forceDark ? .dark : (t.scheme ?? userScheme))
        if #available(iOS 16.1, *) {
            styled.fontDesign(t.fontDesign)
        } else {
            styled
        }
    }
}

// MARK: - Paleta de la carátula
/// Colores dominantes de la canción actual; los fondos de todos los temas los usan.
@MainActor
final class ThemeEngine: ObservableObject {
    nonisolated static let fallback = Tokens.artworkFallback
    @Published private(set) var palette: [Color] = ThemeEngine.fallback
    private var songID: String?
    /// Colores ya calculados por carátula: cada portada se analiza una sola vez.
    private var cache: [String: [Color]] = [:]

    func update(for song: Song?) async {
        guard let song, song.id != songID else { return }
        songID = song.id
        if let known = cache[song.id] {
            withAnimation(.easeInOut(duration: 1.2)) { palette = known }
            return
        }
        guard let url = song.thumb(120), let img = await ImageCache.shared.image(for: url),
              song.id == songID else { return }
        let colors = PaletteExtractor.colors(from: img) ?? ThemeEngine.fallback
        if cache.count > 200 { cache.removeAll() }
        cache[song.id] = colors
        withAnimation(.easeInOut(duration: 1.2)) { palette = colors }
    }
}

enum PaletteExtractor {
    /// Reduce la imagen a 16×16, agrupa los píxeles por tono (12 grupos) pesando
    /// saturación y brillo, y devuelve los 3 tonos más presentes, avivados.
    static func colors(from image: UIImage) -> [Color]? {
        guard let cg = image.cgImage else { return nil }
        let w = 16, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        var sums = [(r: Double, g: Double, b: Double, w: Double)](repeating: (0, 0, 0, 0), count: 12)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
            let weight = Double(sat * bri) + 0.01
            let k = min(11, Int(hue * 12))
            sums[k].r += r * weight; sums[k].g += g * weight; sums[k].b += b * weight; sums[k].w += weight
        }
        let top = sums.filter { $0.w > 0.6 }.sorted { $0.w > $1.w }.prefix(3)
        guard !top.isEmpty else { return nil }   // carátula en blanco y negro
        var colors = top.map { s -> Color in
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
            UIColor(red: s.r / s.w, green: s.g / s.w, blue: s.b / s.w, alpha: 1).getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
            return Color(hue: Double(hue), saturation: Double(max(sat, 0.55)), brightness: Double(max(bri, 0.8)))
        }
        while colors.count < 3 { colors.append(ThemeEngine.fallback[colors.count]) }
        return colors
    }
}

// MARK: - Colores de la portada
/// Cuánto se tiñe la app con la portada: exageración del color e opacidad del tinte (0…1). Las dos a 0 =
/// desactivado. Mismos valores, claves (`artworkIntensity`, `artworkOpacity`) y presets que en Android.
struct ArtworkLevel: Hashable {
    var intensity: Double
    var opacity: Double

    static let off = ArtworkLevel(intensity: 0, opacity: 0)
    static let subtle = ArtworkLevel(intensity: 0.25, opacity: 0.2)
    /// Equilibrado = cómo se veía antes de las barras.
    static let balanced = ArtworkLevel(intensity: 0.5, opacity: 0.45)
    static let intense = ArtworkLevel(intensity: 1, opacity: 1)
    struct Preset: Hashable {
        let name: String
        let level: ArtworkLevel
    }
    static var presets: [Preset] { [Preset(name: L("Sutil"), level: subtle), Preset(name: L("Equilibrado"), level: balanced), Preset(name: L("Intenso"), level: intense)] }

    var enabled: Bool { intensity > 0.005 || opacity > 0.005 }

    /// «Sutil», «Equilibrado», «Intenso», «Desactivado» o «Personalizado».
    var title: String {
        guard enabled else { return L("Desactivado") }
        return Self.presets.first { abs($0.level.intensity - intensity) < 0.02 && abs($0.level.opacity - opacity) < 0.02 }?.name ?? L("Personalizado")
    }

    /// Opacidad del tinte de los fondos (0,1 en «Equilibrado», como antes).
    var backgroundTint: Double { opacity * 0.22 }
}

extension Color {
    /// Luminancia relativa (WCAG).
    var luminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double { let c = Double(c); return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func contrast(_ a: Color, _ b: Color) -> Double {
        let (x, y) = (a.luminance, b.luminance)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// El color de una carátula como acento legible, con el nivel elegido: más o menos saturado y más o
    /// menos mezclado con el acento del tema. Siempre a 3:1 como mínimo sobre el fondo (blanco o negro
    /// aproximado), aunque la portada sea muy clara o muy viva. Mismas reglas que `withArtwork` en Android.
    func artworkAccent(dark: Bool, level: ArtworkLevel = .balanced, base: Color? = nil) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        s = max(s, CGFloat(0.9 * level.intensity))
        b = dark ? max(b, 0.82) : min(b, 0.62)
        let bg: Color = dark ? .black : .white
        var accent = Color(hue: h, saturation: s, brightness: b)
        var guardCount = 0
        while Color.contrast(accent, bg) < 3, guardCount < 20 {
            guardCount += 1
            b = dark ? min(b + 0.04, 1) : max(b - 0.04, 0)
            if dark && b >= 1 { s = max(s - 0.06, 0) }
            accent = Color(hue: h, saturation: s, brightness: b)
        }
        guard let base else { return accent }
        return base.mix(with: accent, by: min(level.intensity * 2, 1))
    }

    /// Mezcla lineal en RGB (iOS 16 no tiene `Color.mix`).
    func mix(with other: Color, by t: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(max(0, min(1, t)))
        return Color(red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t), blue: Double(b1 + (b2 - b1) * t))
    }
}
