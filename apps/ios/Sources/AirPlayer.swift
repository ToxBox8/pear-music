import SwiftUI
import AVFoundation
import AVKit
import Combine
import UIKit

// MARK: - Reproductor «Air»
// Copia del concepto Air OS de Geex Arts (dribbble.com/shots/25645360-Music):
// papel gris claro, grotesco negro, un disco esmerilado con la carátula desenfocada
// rodeado de puntos (los negros son lo que ya ha sonado), un selector holográfico que
// marca dónde vas, y abajo un panel con la rueda de iPod, el «x1» y la salida de audio.

struct AirColors {
    let paper: Color
    let panel: Color
    let wheel: Color
    let hub: Color
    let ink: Color
    let muted: Color
    let dotOff: Color
    var dark = false

    static func of(_ scheme: ColorScheme) -> AirColors {
        scheme == .dark
            ? AirColors(paper: Tokens.AirDark.paper, panel: Tokens.AirDark.panel, wheel: Tokens.AirDark.wheel,
                        hub: Tokens.AirDark.hub, ink: Tokens.AirDark.ink, muted: Tokens.AirDark.muted, dotOff: Tokens.AirDark.dotOff, dark: true)
            : AirColors(paper: Tokens.AirLight.paper, panel: Tokens.AirLight.panel, wheel: Tokens.AirLight.wheel,
                        hub: Tokens.AirLight.hub, ink: Tokens.AirLight.ink, muted: Tokens.AirLight.muted, dotOff: Tokens.AirLight.dotOff)
    }

    /// Plata cepillada: más clara arriba, como un metal iluminado desde el techo.
    var paperFill: LinearGradient {
        LinearGradient(colors: dark ? [Color(hex: 0x1A1B1D), Color(hex: 0x0E0E10)]
                                    : [Color(hex: 0xF1F2F4), Color(hex: 0xE2E4E8), Color(hex: 0xD4D7DC)],
                       startPoint: .top, endPoint: .bottom)
    }
    var panelFill: LinearGradient {
        LinearGradient(colors: dark ? [Color(hex: 0x26272A), Color(hex: 0x1B1C1E)]
                                    : [Color(hex: 0xDFE2E6), Color(hex: 0xCDD1D6)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var wheelFill: LinearGradient {
        LinearGradient(colors: dark ? [Color(hex: 0x36373B), Color(hex: 0x26272A)]
                                    : [.white, Color(hex: 0xE9EBEE)],
                       startPoint: .top, endPoint: .bottom)
    }
    var hubFill: LinearGradient {
        LinearGradient(colors: dark ? [Color(hex: 0x141416), Color(hex: 0x202124)]
                                    : [Color(hex: 0xBEC2C9), Color(hex: 0xDADDE1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

extension Font {
    /// El grotesco negro de Air OS. Helvetica Neue viene con iOS; crece con el tamaño de texto del sistema.
    static func airDisplay(_ size: CGFloat) -> Font { .custom("HelveticaNeue-Bold", size: size, relativeTo: .title) }
    static func airText(_ size: CGFloat) -> Font { .custom("HelveticaNeue", size: size, relativeTo: .body) }
}

/// Arcoíris saturado del selector, como el reflejo de un CD.
private let holoRainbow: [Color] = Tokens.holoRainbow

private func airTick() { UISelectionFeedbackGenerator().selectionChanged() }

// MARK: Pantalla
struct AirPlayerView: View {
    let song: Song
    @Binding var showQueue: Bool
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: Library
    @Environment(\.colorScheme) private var scheme
    @State private var scrub: Double?

    init(song: Song, showQueue: Binding<Bool>) {
        self.song = song
        self._showQueue = showQueue
    }

    var body: some View {
        let c = AirColors.of(scheme)
        VStack(spacing: 0) {
            header(c)
            Spacer(minLength: 6)
            AirDisc(song: song, clock: player.clock, playing: player.isPlaying, colors: c, scrub: $scrub, rate: player.rate) {
                player.seek(to: $0)
            }
            .padding(.horizontal, 30)
            AirTitle(song: song, clock: player.clock, scrub: scrub, error: player.error, colors: c)
                .padding(.top, 14)
                .padding(.horizontal, 24)
            Spacer(minLength: 14)
            AirControlPanel(song: song, colors: c, showQueue: $showQueue)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .foregroundStyle(c.ink)
    }

    private func header(_ c: AirColors) -> some View {
        let fav = library.isFavorite(song)
        return HStack(spacing: 4) {
            Text("Música").font(.airDisplay(30)).tracking(-0.8)
            Spacer()
            Button { library.toggleFavorite(song) } label: {
                Image(systemName: fav ? "heart.fill" : "heart")
                    .font(.system(size: 19, weight: .semibold))
                    .scaleEffect(fav ? 1.1 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: fav)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(fav ? "Quitar de favoritos" : "Añadir a favoritos")
            Button { player.showFullPlayer = false } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Cerrar reproductor")
        }
        .buttonStyle(TactileButtonStyle())
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .padding(.top, 14)
    }
}

/// Título y artista; al arrastrar el selector el artista cede el sitio al tiempo.
private struct AirTitle: View {
    let song: Song
    @ObservedObject var clock: PlaybackClock
    let scrub: Double?
    let error: String?
    let colors: AirColors

    var body: some View {
        VStack(spacing: 5) {
            Text(song.title)
                .font(.airDisplay(26)).tracking(-0.5)
                .multilineTextAlignment(.center).lineLimit(2)
                .minimumScaleFactor(0.8)
            Group {
                if let scrub {
                    Text("\(timeString(scrub * clock.duration)) / \(timeString(clock.duration))").monospacedDigit()
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text(song.artist)
                }
            }
            .font(.airText(17))
            .foregroundStyle(colors.muted)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .animation(.uiEaseOut(0.2), value: scrub == nil)
    }
}

// MARK: Disco
private struct AirDisc: View {
    let song: Song
    @ObservedObject var clock: PlaybackClock
    let playing: Bool
    let colors: AirColors
    @Binding var scrub: Double?
    var rate: Float = 1
    var onSeek: (Double) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastDot = -1

    private static let dots = 64

    var body: some View {
        // El progreso llega cada 0,5 s; entre medias se calcula en cada fotograma para que el
        // selector y los puntos avancen sin tirones (antes, una animación lineal por paso).
        TimelineView(.animation(paused: !playing || scrub != nil)) { ctx in
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let disc = side - 46
            let knob = min(104, disc * 0.34)
            let live = clock.progress(at: ctx.date, playing: playing, rate: rate)
            let p = scrub ?? (clock.duration > 0 ? min(1, live / clock.duration) : 0)
            let center = CGPoint(x: side / 2, y: side / 2)

            ZStack {
                AirDots(progress: p, count: Self.dots, radius: side / 2 - 5, colors: colors)

                CoverImage(url: song.thumb(500))
                    .frame(width: disc * 1.15, height: disc * 1.15)
                    .blur(radius: 18)
                    .frame(width: disc, height: disc)
                    .overlay(colors.paper.opacity(0.42))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.07), radius: 30, y: 18)

                HoloKnob(art: song.thumb(300), spinning: playing && !reduceMotion)
                    .frame(width: knob, height: knob)
                    .offset(x: sin(p * 2 * .pi) * (disc / 2 - knob / 2 - 10), y: -cos(p * 2 * .pi) * (disc / 2 - knob / 2 - 10))

                // Zona de arrastre: sólo el borde (puntos + selector), el centro deja cerrar la hoja.
                RingShape(inner: disc / 2 - knob - 20)
                    .fill(Color.clear)
                    .contentShape(RingShape(inner: disc / 2 - knob - 20), eoFill: true)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                guard clock.duration > 0 else { return }
                                var next = Self.progress(at: v.location, center: center)
                                // Sin saltos de 100 % a 0 % al cruzar las 12.
                                if let s = scrub {
                                    if s > 0.75 && next < 0.25 { next = 0.999 }
                                    if s < 0.25 && next > 0.75 { next = 0 }
                                }
                                let dot = Int(next * Double(Self.dots))
                                if dot != lastDot { lastDot = dot; airTick() }
                                scrub = next
                            }
                            .onEnded { _ in
                                if let s = scrub, clock.duration > 0 { onSeek(s * clock.duration) }
                                scrub = nil
                                lastDot = -1
                            }
                    )
            }
            .frame(width: side, height: side)
            .position(center)
        }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Progreso")
        .accessibilityValue("\(timeString(clock.progress)) de \(timeString(clock.duration))")
        .accessibilityAdjustableAction { dir in
            let step = 10.0
            onSeek(max(0, min(clock.duration, clock.progress + (dir == .increment ? step : -step))))
        }
    }

    /// Ángulo desde las 12 en sentido horario → fracción de la canción.
    static func progress(at pt: CGPoint, center c: CGPoint) -> Double {
        var a = atan2(Double(pt.x - c.x), Double(c.y - pt.y))
        if a < 0 { a += 2 * .pi }
        return a / (2 * .pi)
    }
}

/// Corona para recoger el arrastre sin tapar el centro del disco.
private struct RingShape: Shape {
    let inner: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: r)
        let c = CGPoint(x: r.midX, y: r.midY)
        p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
        return p
    }
}

/// Anillo de puntos: los que ya han sonado son negros y algo más grandes.
private struct AirDots: View {
    let progress: Double
    let count: Int
    let radius: CGFloat
    let colors: AirColors

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let on = Double(i) / Double(count) <= progress
                Circle()
                    .fill(on ? colors.ink : colors.dotOff)
                    .frame(width: on ? 5.5 : 3, height: on ? 5.5 : 3)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(i) / Double(count) * 360))
                    .animation(.uiEaseOut(0.3), value: on)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Selector: la carátula, nítida, gira como un CD; encima, el reflejo holográfico de Air OS.
private struct HoloKnob: View {
    let art: URL?
    let spinning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !spinning)) { ctx in
            // 33⅓ rpm ≈ 200°/s; un poco más lento para que la carátula se lea al girar.
            let angle = (ctx.date.timeIntervalSinceReferenceDate * 40).truncatingRemainder(dividingBy: 360)
            GeometryReader { g in
                let s = min(g.size.width, g.size.height)
                ZStack {
                    CoverImage(url: art)
                        .frame(width: s, height: s)
                        .rotationEffect(.degrees(angle))
                    // El reflejo no gira: es la luz, no el disco.
                    Wedge(span: 120)
                        .fill(AngularGradient(colors: holoRainbow, center: .center,
                                              startAngle: .degrees(-60), endAngle: .degrees(60)))
                        .opacity(0.42)
                        .blendMode(.screen)
                        .rotationEffect(.degrees(35))
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    // Agujero central de CD.
                    Circle().fill(Color(hex: 0xE7E9EC)).frame(width: s * 0.16, height: s * 0.16)
                        .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                }
                .frame(width: s, height: s)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(
                    LinearGradient(colors: [.white, Color(hex: 0xBFC3CA)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 3))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Wedge: Shape {
    let span: Double
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        var p = Path()
        p.move(to: c)
        p.addArc(center: c, radius: min(r.width, r.height) / 2,
                 startAngle: .degrees(-90 - span / 2), endAngle: .degrees(-90 + span / 2), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: Panel de controles
private struct AirControlPanel: View {
    let song: Song
    let colors: AirColors
    @Binding var showQueue: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                AirSpeedKnob(colors: colors)
                AirRouteTile(colors: colors)
            }
            AirWheel(colors: colors, showQueue: $showQueue)
                .frame(maxWidth: 210)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(colors.panelFill)
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        )
        .overlay(alignment: .bottomTrailing) {
            AirDownloadDots(song: song, colors: colors).padding(12)
        }
    }
}

/// «x1»: cambia la velocidad; el punto gira alrededor como en un dial.
private struct AirSpeedKnob: View {
    let colors: AirColors
    @EnvironmentObject var player: Player
    private static let rates: [Float] = [1, 1.25, 1.5, 2, 0.75]

    var body: some View {
        let i = Self.rates.firstIndex(of: player.rate) ?? 0
        let angle = 135.0 + Double(i) * 50
        Button {
            player.setRate(Self.rates[(i + 1) % Self.rates.count])
        } label: {
            ZStack {
                Circle().fill(colors.wheel.opacity(0.7))
                Text(label(player.rate)).font(.airText(15)).foregroundStyle(colors.ink)
                Circle().fill(colors.ink).frame(width: 6, height: 6)
                    .offset(y: -23)
                    .rotationEffect(.degrees(angle))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: angle)
            }
            .frame(width: 68, height: 68)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel("Velocidad")
        .accessibilityValue(label(player.rate))
        .accessibilityHint("Toca para cambiarla")
    }

    private func label(_ r: Float) -> String {
        let s = r == r.rounded() ? String(Int(r)) : String(format: "%g", r)
        return "x\(s)"
    }
}

/// Casilla blanca con el dispositivo de salida; tocarla abre el selector de AirPlay.
private struct AirRouteTile: View {
    let colors: AirColors
    @State private var route = AirRoute.current()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(colors.wheelFill)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
            VStack(spacing: 6) {
                Image(systemName: route.symbol)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(colors.muted)
                Text(route.name)
                    .font(.airText(11))
                    .foregroundStyle(colors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
            }
            // El selector real va encima, casi invisible, para que el toque lo abra.
            RoutePicker().opacity(0.02)
        }
        .frame(width: 104, height: 104)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)) { _ in
            withAnimation(.uiEaseOut(0.25)) { route = AirRoute.current() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Salida de audio: \(route.name)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct AirRoute: Equatable {
    let name: String
    let symbol: String

    static func current() -> AirRoute {
        guard let out = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            return AirRoute(name: "iPhone", symbol: "iphone")
        }
        let n = out.portName
        switch out.portType {
        case .builtInSpeaker, .builtInReceiver: return AirRoute(name: "iPhone", symbol: "iphone")
        case .airPlay: return AirRoute(name: n, symbol: "airplayaudio")
        case .carAudio: return AirRoute(name: n, symbol: "car.fill")
        case .headphones: return AirRoute(name: n, symbol: "headphones")
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            if n.localizedCaseInsensitiveContains("AirPods Max") { return AirRoute(name: n, symbol: "airpodsmax") }
            if n.localizedCaseInsensitiveContains("AirPods Pro") { return AirRoute(name: n, symbol: "airpodspro") }
            if n.localizedCaseInsensitiveContains("AirPods") { return AirRoute(name: n, symbol: "airpods") }
            return AirRoute(name: n, symbol: "headphones")
        default: return AirRoute(name: n, symbol: "hifispeaker.fill")
        }
    }
}

/// La rueda del iPod: toca arriba (cola), izquierda, derecha, abajo o el centro;
/// gira el dedo por el borde para avanzar o retroceder (una vuelta = 30 s).
private struct AirWheel: View {
    let colors: AirColors
    @Binding var showQueue: Bool
    @EnvironmentObject var player: Player
    @State private var pressed: Zone?
    @State private var lastAngle: Double?
    @State private var spun = 0.0
    @State private var startTime = 0.0
    @State private var preview: Double?
    @State private var tick = 0

    enum Zone { case menu, back, forward, play, hub }

    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            let hub = d * 0.36
            let c = CGPoint(x: d / 2, y: d / 2)

            ZStack {
                Circle().fill(colors.wheelFill)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 16, y: 8)

                glyph("circle.grid.2x2.fill", size: 11, at: point(.menu, d))
                glyph("backward.fill", size: 13, at: point(.back, d))
                glyph("forward.fill", size: 13, at: point(.forward, d))
                glyph(player.isPlaying ? "pause.fill" : "play.fill", size: 14, at: point(.play, d))

                Circle().fill(colors.hubFill)
                    .frame(width: hub, height: hub)
                    .scaleEffect(pressed == .hub ? 0.94 : 1)
                    .overlay {
                        if let preview {
                            Text(timeString(preview)).font(.airDisplay(15)).monospacedDigit()
                                .foregroundStyle(colors.ink)
                        }
                    }
                    .position(c)

                // Anillo negro sobre lo que se pulsa, como en Air OS.
                if let z = pressed {
                    Circle()
                        .stroke(colors.ink, lineWidth: 5)
                        .frame(width: z == .hub ? hub + 12 : 48, height: z == .hub ? hub + 12 : 48)
                        .position(z == .hub ? c : point(z, d))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: d, height: d)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in changed(v, center: c, hub: hub) }
                    .onEnded { _ in ended() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityRepresentation {
            HStack {
                Button("Anterior") { player.previous() }
                Button(player.isPlaying ? "Pausar" : "Reproducir") { player.toggle() }
                Button("Siguiente") { player.next() }
                Button("Cola") { showQueue = true }
            }
        }
    }

    private func glyph(_ name: String, size: CGFloat, at p: CGPoint) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(colors.muted)
            .position(p)
    }

    private func point(_ z: Zone, _ d: CGFloat) -> CGPoint {
        let inset = d * 0.15
        switch z {
        case .menu: return CGPoint(x: d / 2, y: inset)
        case .back: return CGPoint(x: inset, y: d / 2)
        case .forward: return CGPoint(x: d - inset, y: d / 2)
        case .play: return CGPoint(x: d / 2, y: d - inset)
        case .hub: return CGPoint(x: d / 2, y: d / 2)
        }
    }

    private func angle(_ p: CGPoint, _ c: CGPoint) -> Double { atan2(Double(p.y - c.y), Double(p.x - c.x)) }

    private func zone(at p: CGPoint, center c: CGPoint, hub: CGFloat) -> Zone {
        let dx = p.x - c.x, dy = p.y - c.y
        if hypot(dx, dy) < hub / 2 { return .hub }
        if abs(dx) > abs(dy) { return dx > 0 ? .forward : .back }
        return dy > 0 ? .play : .menu
    }

    private func changed(_ v: DragGesture.Value, center c: CGPoint, hub: CGFloat) {
        let a = angle(v.location, c)
        guard let last = lastAngle else {
            // Primer contacto: se marca la zona.
            lastAngle = a
            spun = 0
            startTime = player.clock.progress
            withAnimation(.uiEaseOut(0.15)) { pressed = zone(at: v.startLocation, center: c, hub: hub) }
            return
        }
        let moved = hypot(v.translation.width, v.translation.height)
        let onRim = hypot(v.startLocation.x - c.x, v.startLocation.y - c.y) >= hub / 2
        guard onRim, moved > 10 || preview != nil else { return }
        // Girando: ya no es un toque, es avanzar/retroceder.
        if pressed != nil { withAnimation(.uiEaseOut(0.15)) { pressed = nil } }
        spun += angleDelta(a, last)
        lastAngle = a
        let t = max(0, min(player.clock.duration, startTime + spun / (2 * .pi) * 30))
        preview = t
        let step = Int(t / 2)
        if step != tick { tick = step; airTick() }
    }

    private func ended() {
        if let preview {
            player.seek(to: preview)
        } else if let z = pressed {
            switch z {
            case .menu: withAnimation(.uiEaseOut(0.25)) { showQueue = true }
            case .back: player.previous()
            case .forward: player.next()
            case .play, .hub: player.toggle()
            }
        }
        preview = nil
        lastAngle = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.uiEaseOut(0.25)) { pressed = nil }
        }
    }
}

/// Esquina del panel: corona de puntos que se rellena al descargar; completa = disponible sin conexión.
private struct AirDownloadDots: View {
    let song: Song
    let colors: AirColors
    @EnvironmentObject var downloads: DownloadStore

    var body: some View {
        let done = downloads.isDownloaded(song)
        let busy = downloads.inProgress.contains(song.id)
        let pct = done ? 1 : (downloads.progress[song.id] ?? 0)
        let n = 12
        Button {
            if !done && !busy { Task { await downloads.download(song) } }
        } label: {
            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    let on = Double(i) / Double(n) < pct
                    Circle()
                        .fill(on ? colors.ink : colors.dotOff)
                        .frame(width: on ? 3.5 : 2.5, height: on ? 3.5 : 2.5)
                        .offset(y: -12)
                        .rotationEffect(.degrees(Double(i) / Double(n) * 360))
                }
                if done {
                    Circle().fill(colors.ink).frame(width: 6, height: 6)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .animation(.uiEaseOut(0.25), value: pct)
        }
        .buttonStyle(TactileButtonStyle())
        .disabled(done || busy)
        .accessibilityLabel(done ? "Descargada" : busy ? "Descargando" : "Descargar")
    }
}

// MARK: - Papel de fondo
/// Gris claro con cintas blancas muy suaves que se desplazan despacio.
struct AirPaper: View {
    var animated = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        let c = AirColors.of(scheme)
        let ribbon = scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.85)
        Rectangle().fill(c.paperFill)
            .overlay {
                GeometryReader { g in
                    let w = g.size.width, h = g.size.height
                    ZStack {
                        Capsule().fill(ribbon)
                            .frame(width: w * 1.6, height: h * 0.22)
                            .rotationEffect(.degrees(-28))
                            .offset(x: drift ? -w * 0.08 : w * 0.06, y: -h * 0.18)
                        Capsule().fill(ribbon)
                            .frame(width: w * 1.4, height: h * 0.16)
                            .rotationEffect(.degrees(24))
                            .offset(x: drift ? w * 0.1 : -w * 0.04, y: h * 0.26)
                        // Brillo metálico: una franja fina que cruza en diagonal.
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(scheme == .dark ? 0.04 : 0.5), .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: w * 0.35, height: h * 1.6)
                            .rotationEffect(.degrees(22))
                            .offset(x: drift ? w * 0.3 : -w * 0.3)
                    }
                    .blur(radius: 40)
                    .frame(width: w, height: h)
                }
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .onAppear {
                guard animated && !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drift = true }
            }
    }
}

// MARK: - Miniatura (mini reproductor y selector de Ajustes)
struct MiniAirDisc: View {
    let art: URL?
    var isPlaying = false

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Color(hex: 0xE7E9EC)
                ForEach(0..<20, id: \.self) { i in
                    Circle().fill(Color(hex: i < 7 ? 0x111214 : 0xA9AEB5))
                        .frame(width: s * 0.05, height: s * 0.05)
                        .offset(y: -s * 0.42)
                        .rotationEffect(.degrees(Double(i) / 20 * 360))
                }
                CoverImage(url: art)
                    .frame(width: s * 0.72, height: s * 0.72)
                    .blur(radius: s * 0.06)
                    .overlay(Color(hex: 0xE7E9EC).opacity(0.35))
                    .clipShape(Circle())
                Circle()
                    .fill(AngularGradient(colors: holoRainbow, center: .center))
                    .frame(width: s * 0.2, height: s * 0.2)
                    .overlay(Circle().strokeBorder(.white, lineWidth: s * 0.03))
                    .offset(x: s * 0.2, y: -s * 0.2)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
