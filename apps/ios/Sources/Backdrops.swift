import SwiftUI
import UIKit

// MARK: - Fondos animados de los temas
// Todos usan la paleta de la carátula (ThemeEngine) y van más rápido mientras suena
// música. Se pausan si la pantalla no está visible o con «Reducir movimiento».

private func fract(_ x: Double) -> Double { x - floor(x) }
/// Pseudoaleatorio estable (el mismo número para la misma semilla en iOS y Android).
private func hash(_ n: Double) -> Double { fract(sin(n * 12.9898) * 43758.5453) }

/// Fase acumulada: cambiar de velocidad (play/pausa) no provoca saltos en la animación.
final class PhaseClock {
    private var last: Date?
    private(set) var phase: Double = 0
    func tick(_ now: Date, speed: Double) -> Double {
        if let last { phase += min(now.timeIntervalSince(last), 0.1) * speed }
        last = now
        return phase
    }
}

struct ThemeBackdrop: View {
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @EnvironmentObject var engine: ThemeEngine
    @EnvironmentObject var player: Player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        BackdropContent(theme: AppTheme(rawValue: themeID) ?? .glass, palette: engine.palette,
                        playing: player.isPlaying, paused: !visible || reduceMotion, song: player.current)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { visible = true }
            .onDisappear { visible = false }
    }
}

/// Fotograma fijo de un tema para la galería de Ajustes.
struct BackdropPreview: View {
    let theme: AppTheme
    @EnvironmentObject var engine: ThemeEngine
    var body: some View {
        BackdropContent(theme: theme, palette: engine.palette, playing: false, paused: true, song: nil)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct BackdropContent: View {
    let theme: AppTheme
    let palette: [Color]
    let playing: Bool
    let paused: Bool
    let song: Song?

    var body: some View {
        switch theme {
        case .air: AirBackdrop(palette: palette)
        case .glass: GlassBackdrop(palette: palette, art: song?.thumb(300))
        case .neon: NeonBackdrop(palette: palette, playing: playing, paused: paused)
        case .plain: Color(.systemGroupedBackground)
        }
    }
}

// MARK: Cristal
struct GlassBackdrop: View {
    let palette: [Color]
    let art: URL?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        Color(.systemBackground)
            .overlay {
                ZStack {
                    Circle().fill(palette[0].opacity(0.6)).frame(width: 340, height: 340)
                        .offset(x: drift ? -130 : -60, y: drift ? -260 : -190)
                    Circle().fill(palette[1].opacity(0.5)).frame(width: 300, height: 300)
                        .offset(x: drift ? 150 : 90, y: drift ? 30 : 130)
                    Circle().fill(palette[2].opacity(0.42)).frame(width: 260, height: 260)
                        .offset(x: drift ? -90 : 50, y: drift ? 330 : 250)
                    if let art {
                        CoverImage(url: art, placeholder: false).opacity(0.5)
                            .frame(width: 320, height: 320)
                            .offset(x: drift ? 40 : -20, y: drift ? -40 : 20)
                    }
                }
                .blur(radius: 70)
            }
            .overlay(Color(.systemBackground).opacity(scheme == .dark ? 0.3 : 0.2))
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
            }
    }
}

// MARK: Aire
/// Papel de Air OS (gris claro con cintas blancas). Monocromo: el color sólo lo pone la música.
struct AirBackdrop: View {
    let palette: [Color]
    var body: some View { AirPaper() }
}

// MARK: Neón (rejilla synthwave)
private struct NeonBackdrop: View {
    let palette: [Color]
    let playing: Bool
    let paused: Bool
    @State private var clock = PhaseClock()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { tl in
            let t = clock.tick(tl.date, speed: playing ? 1 : 0.2)
            Canvas { ctx, size in
                let w = size.width, h = size.height, horizon = h * 0.44
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x05030C)))
                // halo del horizonte
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(Gradient(colors: [palette[0].opacity(playing ? 0.45 : 0.3), .clear]),
                                               center: CGPoint(x: w / 2, y: horizon), startRadius: 0, endRadius: w * 0.8))
                // estrellas
                var stars = Path()
                for i in 0..<60 {
                    let n = Double(i)
                    let x = hash(n) * w, y = hash(n + 9) * horizon * 0.95
                    let r = 0.5 + hash(n + 4) * (0.8 + 0.5 * sin(t * 2 + n))
                    stars.addEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
                ctx.fill(stars, with: .color(.white.opacity(0.7)))
                // rejilla en perspectiva
                var horizontal = Path(), vertical = Path()
                for k in 0..<16 {
                    let z = fract((Double(k) + t * 0.8) / 16)
                    let y = horizon + (h - horizon) * pow(z, 2.3)
                    horizontal.move(to: CGPoint(x: 0, y: y)); horizontal.addLine(to: CGPoint(x: w, y: y))
                }
                for i in -14...14 {
                    let x0 = w / 2 + Double(i) * w * 0.018, x1 = w / 2 + Double(i) * w * 0.32
                    vertical.move(to: CGPoint(x: x0, y: horizon)); vertical.addLine(to: CGPoint(x: x1, y: h))
                }
                for (path, color) in [(horizontal, palette[1]), (vertical, palette[0])] {
                    ctx.stroke(path, with: .color(color.opacity(0.22)), lineWidth: 5)   // resplandor
                    ctx.stroke(path, with: .color(color.opacity(0.95)), lineWidth: 1.2)
                }
                ctx.fill(Path(CGRect(x: 0, y: horizon - 1, width: w, height: 2)), with: .color(palette[0]))
            }
        }
    }
}

// MARK: - Carátula como fondo
/// La carátula enorme y desenfocada con un velo del color de fondo, como en Descubrir: fondo del
/// reproductor con «Colores de la carátula». Gira muy despacio mientras suena.
struct ArtworkBackdrop: View {
    let url: URL?
    let playing: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !playing || reduceMotion)) { ctx in
            GeometryReader { g in
                let side = max(g.size.width, g.size.height) * 1.6
                CoverImage(url: url, placeholder: false)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees((ctx.date.timeIntervalSinceReferenceDate * 4).truncatingRemainder(dividingBy: 360)))
                    .blur(radius: 70)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
            }
        }
        // Velo: el texto del reproductor se sigue leyendo en claro y en oscuro.
        .overlay((scheme == .dark ? Color.black : Color.white).opacity(scheme == .dark ? 0.42 : 0.5))
        .background(Color(uiColor: .systemBackground))
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
