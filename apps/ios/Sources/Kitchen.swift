import SwiftUI
import UIKit

// Componentes inspirados en "The Kitchen" de dqnamo (dqnamo.com/kitchen),
// adaptados a SwiftUI y al estilo cristal de la app.

/// Curva "ui ease out" que usa dqnamo en todos sus componentes: cubic-bezier(0.23, 1, 0.32, 1).
extension Animation {
    static func uiEaseOut(_ duration: Double = 0.18) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }
}

private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - Tactile Button
/// Se hunde al pulsar (escala 0.97). Con `lip` dibuja una cara de cristal circular
/// con un "labio" inferior que desaparece al presionar, como un botón físico.
struct TactileButtonStyle: ButtonStyle {
    var lip = false

    func makeBody(configuration: Configuration) -> some View {
        TactileBody(configuration: configuration, lip: lip)
    }
}

private struct TactileBody: View {
    let configuration: ButtonStyleConfiguration
    let lip: Bool

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .background {
                if lip {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.28)).offset(y: pressed ? 1 : 4)
                        Circle().fill(.ultraThinMaterial)
                        Circle().strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.05)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    }
                }
            }
            .offset(y: lip && pressed ? 3 : 0)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.uiEaseOut(0.15), value: pressed)
            .onChange(of: pressed) { if $0 { haptic() } }
    }
}

// MARK: - Scramble Text
/// Revela el texto de izquierda a derecha sobre símbolos aleatorios (32 ms por paso, máx. ~1.5 s).
struct ScrambleText: View {
    let text: String
    var interval = 0.032
    @State private var shown: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("scramble") private var enabled = true

    private static let symbols = Array("-_~`!@#$%^&*()+=[]{}|;:,.<>?")
    /// Títulos ya revelados: si la vista se recrea (p. ej. el mini reproductor de iOS 26)
    /// el título se muestra directamente en lugar de repetir la animación.
    private static var revealed = Set<String>()

    var body: some View {
        Text(shown ?? (Self.revealed.contains(text) || !enabled ? text : String(repeating: " ", count: text.count)))
            .accessibilityLabel(text)
            .task(id: text) { await reveal() }
    }

    private func reveal() async {
        let target = Array(text)
        guard enabled, !reduceMotion, !target.isEmpty, !Self.revealed.contains(text) else { shown = text; return }
        Self.revealed.insert(text)
        let step = max(1, Int((Double(target.count) / 48).rounded(.up)))
        var revealed = 0
        while revealed < target.count {
            shown = String(target.enumerated().map { i, c in
                i < revealed || c.isWhitespace ? c : Self.symbols.randomElement()!
            })
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { return }
            revealed += step
        }
        shown = text
    }
}

// MARK: - Dynamic Button (descarga)
/// Cambia de "Descargar" → "Descargando 40 %" → "Descargado" (o "Reintentar" si falla);
/// el ancho se ajusta con un muelle sin rebote y la etiqueta entra/sale deslizándose 8 pt.
struct DownloadButton: View {
    let song: Song
    @EnvironmentObject var downloads: DownloadStore
    /// Con letra grande sólo el icono: si no, la fila del reproductor no cabe y la cola se sale (igual que Android).
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Phase { case idle, busy, done, failed }

    private var phase: Phase {
        if downloads.isDownloaded(song) { return .done }
        if downloads.inProgress.contains(song.id) { return .busy }
        if downloads.failed.contains(song.id) { return .failed }
        return .idle
    }

    var body: some View {
        let p = phase
        let pct = Int(((downloads.progress[song.id] ?? 0) * 100).rounded())
        Button { Task { await downloads.download(song) } } label: {
            ZStack {
                HStack(spacing: 6) {
                    Group {
                        switch p {
                        case .idle: Image(systemName: "arrow.down")
                        case .busy: ProgressView().controlSize(.small)
                        case .done: Image(systemName: "checkmark")
                        case .failed: Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 15, height: 15)
                    if typeSize < .xxLarge {
                        switch p {
                        case .idle: Text(L("Descargar"))
                        case .busy: Text(L("Descargando {0} %", pct)).monospacedDigit()
                        case .done: Text(L("Descargado"))
                        case .failed: Text(L("Reintentar"))
                        }
                    }
                }
                .id(p)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                        removal: .opacity.combined(with: .offset(y: -8))))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(p == .failed ? Color.red : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(ThemeSurface(radius: 17))
            .overlay(Capsule().strokeBorder(Color.red.opacity(p == .failed ? 0.6 : 0), lineWidth: 1))
        }
        .buttonStyle(TactileButtonStyle())
        .disabled(p == .busy || p == .done)
        .animation(.uiEaseOut(0.26), value: p)
        .accessibilityLabel(p == .idle ? L("Descargar") : p == .busy ? L("Descargando") : p == .done ? L("Descargado") : L("Reintentar descarga"))
        .accessibilityHint(p == .failed ? (downloads.lastError ?? "") : "")
    }
}

// MARK: - Hold to Confirm
/// Acción destructiva que se rellena mientras se mantiene pulsada (1.6 s por defecto).
/// Soltar antes la rebobina en 0.18 s.
struct HoldToConfirmButton: View {
    let title: String
    var systemImage = "trash"
    var duration = 1.6
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var confirmed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            content.foregroundStyle(.red)
            content
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.red)
                .mask(alignment: .leading) { Rectangle().scaleEffect(x: progress, anchor: .leading) }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.14), in: shape)
        .overlay(shape.strokeBorder(Color.red.opacity(0.7), lineWidth: 1))
        .clipShape(shape)
        .scaleEffect(progress > 0 && !confirmed ? 0.98 : 1)
        .animation(.uiEaseOut(0.15), value: progress > 0)
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 8) {
            complete()
        } onPressingChanged: { pressing in
            guard !confirmed else { return }
            if pressing {
                haptic()
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.18)) { progress = 0 }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("Mantén pulsado para confirmar"))
        .accessibilityAction { complete() }
    }

    private var content: some View {
        Label(confirmed ? L("Hecho") : title, systemImage: confirmed ? "checkmark" : systemImage)
            .font(.subheadline.weight(.semibold))
    }

    private func complete() {
        guard !confirmed else { return }
        confirmed = true
        progress = 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            confirmed = false
            withAnimation(.easeOut(duration: 0.18)) { progress = 0 }
        }
    }
}

// MARK: - Scroll Fade
extension View {
    /// Difumina los bordes superior e inferior de una lista que desborda.
    func edgeFade(_ size: CGFloat = 32) -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: size)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: size)
            }
        }
    }
}

// MARK: - Cassette Player
// Réplica en SwiftUI del «Cassette Audio Player» de dqnamo (dqnamo.com/kitchen):
// carcasa negra con tornillos, etiqueta con tres rayas, ventana con bobinas de 6
// dientes y la cinta pasando de un carrete a otro, progreso con tiempos y una
// botonera trapezoidal. «Volver al inicio» rebobina la cinta con una animación.
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

private enum Tape {
    static let shell = LinearGradient(colors: [Color(hex: 0x373735), Color(hex: 0x20201F), Color(hex: 0x0E0E0D)],
                                      startPoint: UnitPoint(x: 0.37, y: 0), endPoint: UnitPoint(x: 0.63, y: 1))
    static let window = Color(hex: 0x1B1A18)
    static let rotationPerSecond = 300.0   // grados por segundo de audio, como el original

    static func label(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xDC2626) : Color(hex: 0xFCFCFC) }
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white : Color(hex: 0x1C1C1A) }
    static func stripes(_ scheme: ColorScheme) -> [Color] {
        scheme == .dark ? [.white, .white, .white] : [Color(hex: 0x22C55E), Color(hex: 0x14B8A6), Color(hex: 0x3B82F6)]
    }
}

struct CassetteView: View {
    let song: Song
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject var player: Player
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rewind = 0.0          // 0…1 mientras se rebobina
    @State private var scrub: Double?        // fracción mientras se arrastra el progreso
    @State private var wind: Double?         // segundos mientras se bobina la cinta a mano
    @State private var windAngle = 0.0       // giro de las bobinas puesto por el dedo
    @State private var windWasPlaying = false
    @State private var windTick = 0.0

    private var fraction: Double {
        clock.duration > 0 ? min(max(clock.progress / clock.duration, 0), 1) : 0
    }
    /// Posición visible: la del dedo (barra o bobinas) o la real.
    private var current: Double {
        if let scrub { return scrub }
        if let wind { return clock.duration > 0 ? min(max(wind / clock.duration, 0), 1) : 0 }
        return fraction
    }
    private var shown: Double { current * (1 - rewind) }
    /// Número de catálogo estable por canción (como el «200769» del original).
    private var catalogue: String {
        String(format: "%06d", song.id.unicodeScalars.reduce(7) { ($0 * 31 + Int($1.value)) % 1_000_000 })
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let screw = w * 0.033
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.034, style: .continuous)
                    .fill(Tape.shell)
                    .overlay(RoundedRectangle(cornerRadius: w * 0.034, style: .continuous)
                        .strokeBorder(Color(hex: 0x050505), lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.025, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1).padding(6))
                    .overlay(alignment: .top) {   // brillo superior
                        RoundedRectangle(cornerRadius: w * 0.034, style: .continuous)
                            .stroke(LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .center), lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 24, y: 18)

                ForEach(0..<4) { i in
                    Screw(size: screw)
                        .position(x: i % 2 == 0 ? w * 0.0253 + screw / 2 : w - w * 0.0253 - screw / 2,
                                  y: i < 2 ? h * 0.04 + screw / 2 : h - h * 0.04 - screw / 2)
                }

                label(width: w * 0.83, height: h * 0.665)
                    .position(x: w / 2, y: h * 0.095 + h * 0.665 / 2)

                controls(width: w * 0.46, height: h * 0.16)
                    .position(x: w / 2, y: h - h * 0.035 - h * 0.08)
            }
        }
        .aspectRatio(1.58, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Casete: \(song.title)")
    }

    // MARK: Etiqueta
    private func label(width lw: CGFloat, height lh: CGFloat) -> some View {
        let bg = Tape.label(scheme), ink = Tape.ink(scheme)
        let small = Font.system(size: max(8, lw * 0.024), weight: .bold, design: .monospaced)
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(bg)
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: lh * 0.04) {
                        Text(song.artist.uppercased()).font(small).tracking(1.3).opacity(0.85).lineLimit(1)
                        Text(song.title).font(.system(size: max(13, lw * 0.052), weight: .semibold)).tracking(-0.6).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: lh * 0.04) {
                        Text("LADO A").font(small).tracking(0.9)
                            .foregroundStyle(bg)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(ink, in: Capsule())
                        Text(catalogue).font(.system(size: max(7, lw * 0.021), weight: .bold, design: .monospaced))
                            .tracking(0.9).opacity(0.7)
                    }
                }
                .foregroundStyle(ink)
                .padding(.horizontal, lw * 0.045).padding(.top, lw * 0.04)

                ZStack {
                    VStack(spacing: 3) {
                        ForEach(0..<3) { i in Rectangle().fill(Tape.stripes(scheme)[i]) }
                    }
                    .frame(height: lh * 0.34 * 0.58)
                    TimelineView(.animation(paused: !player.isPlaying || reduceMotion)) { tl in
                        let spin = (tl.date.timeIntervalSinceReferenceDate * Tape.rotationPerSecond).truncatingRemainder(dividingBy: 360)
                        let back = min(clock.progress * Tape.rotationPerSecond, 2160) * rewind
                        TapeWindow(fraction: shown, angle: .degrees((reduceMotion ? 0 : spin - back) + windAngle),
                                   ring: bg.opacity(0.5), onWind: windBy, onWindEnd: windEnd)
                    }
                    .padding(.horizontal, lw * 0.175)
                }
                .frame(height: lh * 0.34)
                .padding(.top, lh * 0.06)

                Spacer(minLength: 0)
                progressBar(ink: ink, bg: bg)
                    .padding(.horizontal, lw * 0.045).padding(.bottom, lw * 0.035)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(scheme == .dark ? Color.white.opacity(0.15) : bg.opacity(0.5), lineWidth: 4))
        .frame(width: lw, height: lh)
    }

    private func progressBar(ink: Color, bg: Color) -> some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let x = g.size.width * shown
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.28)).frame(height: 3)
                    Capsule().fill(ink).frame(width: max(0, x), height: 3)
                    Circle().fill(.white)
                        .overlay(Circle().strokeBorder(bg, lineWidth: 2))
                        .shadow(color: Color(hex: 0x25211D, opacity: 0.38), radius: 2, y: 1)
                        .frame(width: 13, height: 13)
                        .offset(x: min(max(x - 6.5, 0), g.size.width - 13))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { scrub = min(max($0.location.x / g.size.width, 0), 1) }
                    .onEnded { _ in
                        if let s = scrub { player.seek(to: s * clock.duration) }
                        scrub = nil
                    })
            }
            .frame(height: 22)
            HStack {
                Text(timeString(current * clock.duration))
                Spacer()
                Text(timeString(clock.duration))
            }
            .font(.system(size: 12)).monospacedDigit()
            .foregroundStyle(ink)
        }
        .accessibilityElement()
        .accessibilityLabel(L("Progreso"))
        .accessibilityValue("\(timeString(clock.progress)) de \(timeString(clock.duration))")
    }

    // MARK: Botonera
    private func controls(width: CGFloat, height: CGFloat) -> some View {
        let small = min(max(width * 0.14, 26), 50), big = min(max(width * 0.18, 32), 64)
        return ZStack {
            Trapezoid().fill(Color(hex: 0x63635E, opacity: 0.2))
            Trapezoid().fill(LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
            HStack(spacing: width * 0.05) {
                Button { restart() } label: { CassetteKey(icon: "arrow.counterclockwise", size: small, big: false) }
                    .disabled(clock.progress <= 0)
                    .accessibilityLabel(L("Volver al inicio"))
                Button { player.toggle() } label: {
                    CassetteKey(icon: player.isPlaying ? "pause.fill" : "play.fill", size: big, big: true)
                }
                .accessibilityLabel(player.isPlaying ? L("Pausa") : L("Reproducir"))
                Button { player.next() } label: { CassetteKey(icon: "forward.fill", size: small, big: false) }
                    .accessibilityLabel(L("Siguiente"))
            }
            .buttonStyle(TactileButtonStyle())
        }
        .frame(width: width, height: height)
    }

    /// Bobinar a mano: girar una bobina (o arrastrar la cinta) mueve la canción
    /// 6 s por vuelta, con un «clic» háptico cada ~35°. Al soltar, salta ahí.
    private func windBy(_ radians: Double) {
        if wind == nil {
            windWasPlaying = player.isPlaying
            if windWasPlaying { player.pause() }
            wind = clock.progress
        }
        windAngle += radians * 180 / .pi
        wind = min(max((wind ?? 0) + radians / (2 * .pi) * 6, 0), max(clock.duration, 0))
        windTick += abs(radians)
        if windTick > 0.6 { UISelectionFeedbackGenerator().selectionChanged(); windTick = 0 }
    }

    private func windEnd() {
        if let w = wind { player.seek(to: w) }
        wind = nil
        if windWasPlaying { player.resume() }
    }

    /// Rebobina con easeInOutCubic (0,22–1 s según lo avanzada que esté la cinta) y vuelve a sonar.
    private func restart() {
        let wasPlaying = player.isPlaying
        guard !reduceMotion, clock.progress > 0 else { player.seek(to: 0); return }
        if wasPlaying { player.pause() }
        let duration = 0.22 + 0.78 * fraction
        withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: duration)) { rewind = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            player.seek(to: 0)
            rewind = 0
            if wasPlaying { player.resume() }
        }
    }
}

private struct CassetteKey: View {
    let icon: String
    let size: CGFloat
    let big: Bool

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(Color(hex: 0xFDFDFC))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: big ? 0x8D8D86 : 0x63635E)))
            .overlay(Circle().strokeBorder(big ? Color(hex: 0xBCBBB5, opacity: 0.5) : Color(hex: 0x82827C), lineWidth: 1))
            .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: .black.opacity(big ? 0.32 : 0.28), radius: big ? 4 : 2.5, y: big ? 3 : 2)
            .frame(width: max(44, size), height: max(44, size))
            .contentShape(Rectangle())
    }
}

private struct Trapezoid: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.13, y: 0))
        p.addLine(to: CGPoint(x: r.width * 0.87, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.addLine(to: CGPoint(x: 0, y: r.height))
        p.closeSubpath()
        return p
    }
}

private struct Screw: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(EllipticalGradient(colors: [Color(hex: 0x5F5F5C), Color(hex: 0x30302E), Color(hex: 0x171716)],
                                             center: UnitPoint(x: 0.36, y: 0.3), startRadiusFraction: 0, endRadiusFraction: 0.8))
            Circle().strokeBorder(Color(hex: 0x060606), lineWidth: 0.8)
            ForEach([45.0, -45.0], id: \.self) { a in
                Capsule().fill(Color(hex: 0x1D1D1B)).frame(width: size * 0.64, height: max(1, size * 0.14)).rotationEffect(.degrees(a))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.38), radius: 0.5, y: 1)
    }
}

/// Ventana con forma de cápsula: bobinas en los extremos y, en el centro, la cinta
/// enrollada (el carrete izquierdo se vacía y el derecho se llena con el progreso).
private struct TapeWindow: View {
    let fraction: Double
    let angle: Angle
    let ring: Color
    var onWind: (Double) -> Void = { _ in }
    var onWindEnd: () -> Void = {}
    @State private var lastAngle: Double?
    @State private var lastX: CGFloat?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let rectW = w * 0.44, rectH = h * 0.76
            ZStack {
                Capsule().fill(Tape.window)
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.13), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))

                ZStack {
                    Color(hex: 0x393631)
                    spool(diameter: rectH * 3.6 * (1 - 0.4 * fraction)).position(x: h / 2, y: h / 2)
                    spool(diameter: rectH * 3.6 * (0.6 + 0.4 * fraction)).position(x: w - h / 2, y: h / 2)
                    HStack(spacing: 0) {
                        ForEach(0..<5) { _ in
                            Spacer()
                            Rectangle().fill(Color(red: 224 / 255, green: 215 / 255, blue: 195 / 255, opacity: 0.28))
                                .frame(width: 2, height: rectH * 0.42)
                        }
                        Spacer()
                    }
                    .frame(width: rectW)
                }
                .frame(width: w, height: h)
                .mask { RoundedRectangle(cornerRadius: 3).frame(width: rectW, height: rectH) }
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x11100F), lineWidth: 2).frame(width: rectW, height: rectH))

                KitchenReel().frame(width: h * 0.78, height: h * 0.78).rotationEffect(angle).position(x: h / 2, y: h / 2)
                KitchenReel().frame(width: h * 0.78, height: h * 0.78).rotationEffect(angle).position(x: w - h / 2, y: h / 2)
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(ring, lineWidth: 3).padding(-3))
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { v in
                    // Empezando sobre una bobina: se gira como con un lápiz. Si no, se arrastra la cinta.
                    let reels = [CGPoint(x: h / 2, y: h / 2), CGPoint(x: w - h / 2, y: h / 2)]
                    if let c = reels.first(where: { hypot(v.startLocation.x - $0.x, v.startLocation.y - $0.y) < h * 0.55 }) {
                        let a = atan2(v.location.y - c.y, v.location.x - c.x)
                        if let last = lastAngle { onWind(angleDelta(a, last)) }
                        lastAngle = a
                    } else {
                        if let last = lastX { onWind(Double((v.location.x - last) / (h * 0.39))) }
                        lastX = v.location.x
                    }
                }
                .onEnded { _ in
                    lastAngle = nil
                    lastX = nil
                    onWindEnd()
                })
            .accessibilityElement()
            .accessibilityLabel(L("Cinta"))
            .accessibilityHint(L("Gira una bobina o arrastra la cinta para avanzar o rebobinar"))
        }
    }

    private func spool(diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(hex: 0x050505))
            ForEach(1..<9) { i in
                Circle().stroke(Color(hex: 0x171717), lineWidth: 1.5)
                    .frame(width: diameter * CGFloat(i) / 9, height: diameter * CGFloat(i) / 9)
            }
            Circle().strokeBorder(Color(hex: 0x0D0A08), lineWidth: 1)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Bobina del original: disco claro con 6 dientes oscuros en el borde.
struct KitchenReel: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                Circle().fill(Color(hex: 0xFCFCFC))
                ForEach(0..<6) { i in
                    RoundedRectangle(cornerRadius: s * 0.02)
                        .fill(Color(hex: 0x1B1A18))
                        .overlay(RoundedRectangle(cornerRadius: s * 0.02).stroke(Color(hex: 0x11100F), lineWidth: max(0.5, s * 0.0125)))
                        .frame(width: s * 0.08, height: s * 0.11)
                        .offset(y: -s * 0.415)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
                Circle().strokeBorder(Tape.window, lineWidth: max(1, s * 0.03))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Casete en miniatura para el mini reproductor: mismo diseño simplificado.
struct MiniCassette: View {
    let isPlaying: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { tl in
                let angle = Angle.degrees((tl.date.timeIntervalSinceReferenceDate * Tape.rotationPerSecond).truncatingRemainder(dividingBy: 360))
                ZStack {
                    Tape.shell
                    RoundedRectangle(cornerRadius: s * 0.08, style: .continuous)
                        .fill(Tape.label(scheme))
                        .frame(width: s * 0.84, height: s * 0.58)
                        .offset(y: -s * 0.06)
                    VStack(spacing: max(0.5, s * 0.02)) {
                        ForEach(0..<3) { i in Rectangle().fill(Tape.stripes(scheme)[i]) }
                    }
                    .frame(width: s * 0.84, height: s * 0.13)
                    .offset(y: -s * 0.04)
                    Capsule().fill(Tape.window)
                        .frame(width: s * 0.66, height: s * 0.28)
                        .offset(y: -s * 0.04)
                    HStack(spacing: s * 0.66 - 2 * s * 0.28) {
                        KitchenReel().frame(width: s * 0.22).rotationEffect(angle)
                        KitchenReel().frame(width: s * 0.22).rotationEffect(angle)
                    }
                    .offset(y: -s * 0.04)
                    Trapezoid().fill(Color(hex: 0x63635E, opacity: 0.45))
                        .frame(width: s * 0.5, height: s * 0.11)
                        .offset(y: s * 0.38)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Fila de lista como tarjeta del tema (con Sistema, la fila normal de iOS).
private struct GlassRow: ViewModifier {
    let inset: Bool
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    func body(content: Content) -> some View {
        let enabled = (AppTheme(rawValue: themeID) ?? .glass).styled
        let card = ThemeSurface(radius: Tokens.Radius.row)
            .padding(.vertical, inset ? 3 : 0)
            .padding(.horizontal, inset ? 10 : 0)
        content
            .listRowBackground(enabled ? AnyView(card) : nil)
            .listRowSeparator(enabled && inset ? .hidden : .automatic)
    }
}

extension View {
    func glassRow(inset: Bool = false) -> some View { modifier(GlassRow(inset: inset)) }
}
