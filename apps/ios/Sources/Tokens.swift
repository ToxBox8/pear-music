// Generado por shared/design/gen_tokens.py desde shared/design/tokens.json. No editar a mano.
import SwiftUI

enum Tokens {
    enum Brand {
        static let violet = Color(hex: 0x8B5CF6)
        static let violetDeep = Color(hex: 0x5B21B6)
        static let magenta = Color(hex: 0xEC4899)
        static let amber = Color(hex: 0xF59E0B)
        static let night = Color(hex: 0x07070A)
    }
    static let artworkFallback: [Color] = [Color(hex: 0x8B5CF6), Color(hex: 0xEC4899), Color(hex: 0xF59E0B)]

    struct ThemeSpec {
        let name: String
        let blurb: String
        let accent: Color
        let onAccent: Color
        let scheme: ColorScheme?
        let rounded: Bool
        let maxRadius: CGFloat
    }
    static let themes: [String: ThemeSpec] = [
        "air": ThemeSpec(name: "Aire", blurb: "Plata con Helvetica negra y un anillo de puntos.", accent: Color(hex: 0x111111), onAccent: Color(hex: 0xFFFFFF), scheme: .light, rounded: false, maxRadius: 40),
        "glass": ThemeSpec(name: "Cristal", blurb: "Luz difusa con los colores de la carátula.", accent: Color(hex: 0x8B5CF6), onAccent: Color(hex: 0xFFFFFF), scheme: nil, rounded: false, maxRadius: 40),
        "neon": ThemeSpec(name: "Neón", blurb: "Rejilla synthwave que avanza mientras suena.", accent: Color(hex: 0xFF2BD6), onAccent: Color(hex: 0xFFFFFF), scheme: .dark, rounded: true, maxRadius: 40),
        "plain": ThemeSpec(name: "Sistema", blurb: "Sin efectos ni fondos animados.", accent: Color(hex: 0x8B5CF6), onAccent: Color(hex: 0xFFFFFF), scheme: nil, rounded: false, maxRadius: 40),
    ]
    static let themeOrder = ["glass", "air", "neon", "plain"]
    static let defaultTheme = "glass"

    enum Radius {
        static let row: CGFloat = 14
        static let card: CGFloat = 16
        static let artworkSmall: CGFloat = 12
        static let artworkCard: CGFloat = 16
        static let artworkPlayer: CGFloat = 22
        static let pill: CGFloat = 14
        static let sheet: CGFloat = 28
        static let playlistCard: CGFloat = 28
        static let miniPlayer: CGFloat = 22
        static let formGroup: CGFloat = 26
    }
    enum TypeSize {
        static let largeTitle: CGFloat = 34
        static let title: CGFloat = 28
        static let title2: CGFloat = 22
        static let title3: CGFloat = 20
        static let headline: CGFloat = 17
        static let body: CGFloat = 17
        static let callout: CGFloat = 16
        static let subheadline: CGFloat = 15
        static let footnote: CGFloat = 13
        static let caption: CGFloat = 12
        static let caption2: CGFloat = 11
        static let displayLibrary: CGFloat = 40
        static let displayScreen: CGFloat = 30
        static let displaySection: CGFloat = 24
    }
    static let playlistPalettes: [[Color]] = [
        [Color(hex: 0xFF5C8C), Color(hex: 0xFA994D)],
        [Color(hex: 0x8C59FF), Color(hex: 0xF266D9)],
        [Color(hex: 0x3380FF), Color(hex: 0x59D9FF)],
        [Color(hex: 0x26BF8C), Color(hex: 0x99F273)],
        [Color(hex: 0xFF9E1A), Color(hex: 0xFFD94D)],
        [Color(hex: 0xF2334D), Color(hex: 0x8C1A73)],
        [Color(hex: 0x404066), Color(hex: 0x8080B3)],
        [Color(hex: 0x1AB3BF), Color(hex: 0x4D66F2)],
    ]
    static let holoRainbow: [Color] = [Color(hex: 0xFF3B30), Color(hex: 0xFF9500), Color(hex: 0xFFE600), Color(hex: 0x34C759), Color(hex: 0x00C7FF), Color(hex: 0x3D5BFF), Color(hex: 0xB34DFF)]
    enum AirLight {
        static let paper = Color(hex: 0xE7E9EC)
        static let panel = Color(hex: 0xD6D9DE)
        static let wheel = Color(hex: 0xF8F9FB)
        static let hub = Color(hex: 0xC9CDD3)
        static let ink = Color(hex: 0x111214)
        static let muted = Color(hex: 0x62666D)
        static let dotOff = Color(hex: 0xA9AEB5)
    }
    enum AirDark {
        static let paper = Color(hex: 0x111112)
        static let panel = Color(hex: 0x1E1E20)
        static let wheel = Color(hex: 0x2C2C2F)
        static let hub = Color(hex: 0x19191B)
        static let ink = Color(hex: 0xFFFFFF)
        static let muted = Color(hex: 0x9A9A9E)
        static let dotOff = Color(hex: 0x4A4A4E)
    }
    enum Motion {
        static let easeOut: (Double, Double, Double, Double) = (0.23, 1, 0.32, 1)
        static let fast: Double = 0.15
        static let normal: Double = 0.25
        static let slow: Double = 0.42
    }
}
