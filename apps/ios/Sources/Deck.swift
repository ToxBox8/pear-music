import SwiftUI
import UIKit

// MARK: - Tipo de reproductor: controles normales, casete o vinilo
enum DeckStyle: String, CaseIterable, Identifiable {
    case normal, cassette, vinyl, air

    var id: String { rawValue }
    var name: String {
        switch self {
        case .normal: return L("Normal")
        case .cassette: return L("Casete")
        case .vinyl: return L("Vinilo")
        case .air: return L("Air")
        }
    }
    var symbol: String {
        switch self {
        case .normal: return "slider.horizontal.3"
        case .cassette: return "recordingtape"
        case .vinyl: return "opticaldisc.fill"
        case .air: return "circle.dotted"
        }
    }
    /// Objeto físico que llena la pantalla en horizontal.
    var isObject: Bool { self == .cassette || self == .vinyl }
}

private func selectionTick() { UISelectionFeedbackGenerator().selectionChanged() }

/// Diferencia entre dos ángulos en (-π, π].
func angleDelta(_ a: Double, _ b: Double) -> Double {
    var d = a - b
    while d > .pi { d -= 2 * .pi }
    while d <= -.pi { d += 2 * .pi }
    return d
}

// MARK: - Botones de cabecera (Reproducir / Aleatorio)
/// Botón de 48 pt, ancho completo: relleno de acento o superficie del tema.
struct PillButtonStyle: ButtonStyle {
    var prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent)
    }
}

private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    var body: some View {
        let theme = AppTheme(rawValue: themeID) ?? .glass
        let radius = min(14, theme.maxRadius)
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(prominent ? AnyShapeStyle(theme.onAccent) : AnyShapeStyle(.tint))
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.tint)
                } else {
                    ThemeSurface(radius: radius)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.uiEaseOut(0.15), value: configuration.isPressed)
    }
}

struct PlayShuffleBar: View {
    let songs: [Song]
    @EnvironmentObject var player: Player

    var body: some View {
        HStack(spacing: 12) {
            Button { if let f = songs.first { player.play(f, in: songs) } } label: {
                Label(L("Reproducir"), systemImage: "play.fill")
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            Button { let s = songs.shuffled(); if let f = s.first { player.play(f, in: s) } } label: {
                Label(L("Aleatorio"), systemImage: "shuffle")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
        }
        .disabled(songs.isEmpty)
    }
}

// MARK: - Vinilo
// Tocadiscos: el disco gira a 33⅓ rpm con la carátula como galleta; el brazo sigue el
// progreso. Gira el disco con el dedo para avanzar o retroceder (como un DJ) o arrastra
// el brazo a otro surco. START·STOP reproduce o pausa.
struct VinylView: View {
    let song: Song
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject var player: Player
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeID) ?? .glass }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scratch: Double?        // segundos mientras se gira el disco a mano
    @State private var extraAngle = 0.0        // giro añadido por el dedo
    @State private var lastTouch: Double?
    @State private var armFraction: Double?    // posición mientras se arrastra el brazo
    @State private var wasPlaying = false
    @State private var tick = 0.0

    private static let secondsPerTurn = 4.0
    private static let rpmDegrees = 200.0      // 33⅓ rpm

    private var fraction: Double {
        if let armFraction { return armFraction }
        let t = scratch ?? clock.progress
        return clock.duration > 0 ? min(max(t / clock.duration, 0), 1) : 0
    }

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let center = CGPoint(x: s * 0.44, y: s * 0.52)
            let pivot = CGPoint(x: s * 0.86, y: s * 0.15)
            let armLength = s * 0.6
            let rOuter = s * 0.37, rInner = s * 0.17
            let theta = armAngle(center: center, pivot: pivot, length: armLength,
                                 radius: player.current == nil ? nil : rOuter - (rOuter - rInner) * fraction)
            ZStack(alignment: .topLeading) {
                // Plinto
                RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2E2D31), Color(hex: 0x1A191C), Color(hex: 0x111012)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.6)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 16)
                    .frame(width: s, height: s)

                // Plato
                Circle().fill(Color(hex: 0x0C0C0E))
                    .overlay(Circle().strokeBorder(Color(hex: 0x3A393E), lineWidth: s * 0.008))
                    .frame(width: s * 0.86, height: s * 0.86)
                    .position(center)

                // Disco
                TimelineView(.animation(paused: !player.isPlaying || reduceMotion || scratch != nil)) { tl in
                    let spin = reduceMotion ? 0 : (tl.date.timeIntervalSinceReferenceDate * Self.rpmDegrees).truncatingRemainder(dividingBy: 360)
                    Record(art: song.thumb(600))
                        .frame(width: s * 0.8, height: s * 0.8)
                        .rotationEffect(.degrees(spin + extraAngle))
                }
                .position(center)
                // Brillo fijo: la luz no gira con el disco.
                Circle()
                    .fill(AngularGradient(colors: [.clear, .white.opacity(0.13), .clear, .clear, .white.opacity(0.09), .clear, .clear],
                                          center: .center, angle: .degrees(-30)))
                    .mask(Circle().strokeBorder(.black, lineWidth: s * 0.22))
                    .frame(width: s * 0.8, height: s * 0.8)
                    .position(center)
                    .allowsHitTesting(false)
                Circle().fill(.clear)
                    .frame(width: s * 0.8, height: s * 0.8)
                    .contentShape(Circle())
                    .position(center)
                    .gesture(scratchGesture(center: center))
                    .accessibilityLabel(L("Disco"))
                    .accessibilityHint(L("Gíralo para avanzar o retroceder"))

                // Velocidad (se ilumina al sonar)
                VStack(spacing: 2) {
                    Circle().fill(player.isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(hex: 0x3A393E)))
                        .frame(width: s * 0.022, height: s * 0.022)
                        .shadow(color: player.isPlaying ? theme.accent : .clear, radius: 4)
                    Text("33").font(.system(size: max(9, s * 0.03), weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x8A8990))
                }
                .position(x: s * 0.07, y: s * 0.08)

                // Brazo
                Tonearm(size: s, lifted: !player.isPlaying || scratch != nil)
                    .frame(width: s * 0.1, height: armLength + s * 0.12)
                    .rotationEffect(.degrees(theta), anchor: UnitPoint(x: 0.5, y: (s * 0.12) / (armLength + s * 0.12)))
                    .position(x: pivot.x, y: pivot.y + (armLength + s * 0.12) / 2 - s * 0.12)
                    .animation(armFraction == nil ? .easeInOut(duration: 0.6) : nil, value: theta)
                    .gesture(armGesture(center: center, pivot: pivot, length: armLength, rOuter: rOuter, rInner: rInner))
                    .accessibilityLabel(L("Brazo"))
                    .accessibilityHint(L("Arrástralo a otro surco para cambiar la posición"))

                // Controles del plinto
                HStack(spacing: s * 0.03) {
                    Button { player.previous() } label: { DeckKey(icon: "backward.fill", size: s * 0.1) }
                        .accessibilityLabel(L("Anterior"))
                    Button { player.next() } label: { DeckKey(icon: "forward.fill", size: s * 0.1) }
                        .accessibilityLabel(L("Siguiente"))
                }
                .buttonStyle(TactileButtonStyle())
                .position(x: s * 0.84, y: s * 0.9)

                Button { player.toggle() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: max(13, s * 0.04), weight: .bold))
                        Text("START·STOP").font(.system(size: max(7, s * 0.02), weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color(hex: 0xE8E6E1))
                    .frame(width: max(56, s * 0.17), height: max(44, s * 0.1))
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x3B3A3F)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel(player.isPlaying ? L("Pausa") : L("Reproducir"))
                .position(x: s * 0.13, y: s * 0.9)
            }
            .frame(width: s, height: s)
            .coordinateSpace(name: "vinyl")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Ángulo del brazo (0° = reposo, apuntando abajo) para que la aguja caiga a `radius`
    /// del centro del disco. Búsqueda binaria entre el reposo y el punto más cercano.
    private func armAngle(center: CGPoint, pivot: CGPoint, length: CGFloat, radius: CGFloat?) -> Double {
        guard let radius else { return 0 }
        func needleDistance(_ deg: Double) -> Double {
            let a = deg * .pi / 180
            let nx = pivot.x - length * sin(a), ny = pivot.y + length * cos(a)
            return hypot(nx - center.x, ny - center.y)
        }
        let closest = atan2(pivot.x - center.x, center.y - pivot.y) * 180 / .pi
        var lo = 0.0, hi = closest
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if needleDistance(mid) > radius { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    private func scratchGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("vinyl"))
            .onChanged { v in
                let a = atan2(v.location.y - center.y, v.location.x - center.x)
                if scratch == nil {
                    wasPlaying = player.isPlaying
                    if wasPlaying { player.pause() }
                    scratch = clock.progress
                }
                if let last = lastTouch {
                    let d = angleDelta(a, last)
                    extraAngle += d * 180 / .pi
                    scratch = min(max((scratch ?? 0) + d / (2 * .pi) * Self.secondsPerTurn, 0), max(clock.duration, 0))
                    tick += abs(d)
                    if tick > .pi / 6 { selectionTick(); tick = 0 }
                }
                lastTouch = a
            }
            .onEnded { _ in
                if let s = scratch { player.seek(to: s) }
                scratch = nil
                lastTouch = nil
                if wasPlaying { player.resume() }
            }
    }

    private func armGesture(center: CGPoint, pivot: CGPoint, length: CGFloat, rOuter: CGFloat, rInner: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("vinyl"))
            .onChanged { v in
                // La aguja sigue al dedo a lo largo de su arco: se usa el ángulo desde el pivote.
                let a = atan2(pivot.x - v.location.x, v.location.y - pivot.y)
                let nx = pivot.x - length * sin(a), ny = pivot.y + length * cos(a)
                let r = hypot(nx - center.x, ny - center.y)
                let f = min(max((rOuter - r) / (rOuter - rInner), 0), 1)
                if armFraction == nil { selectionTick() }
                armFraction = f
            }
            .onEnded { _ in
                if let f = armFraction { player.seek(to: f * clock.duration) }
                armFraction = nil
                selectionTick()
            }
    }
}

/// Disco: surcos, pistas y la carátula como galleta central.
private struct Record: View {
    let art: URL?
    var body: some View {
        GeometryReader { g in
            let d = g.size.width
            ZStack {
                Circle().fill(Color(hex: 0x0A0A0B))
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    var grooves = Path(), gaps = Path()
                    var r = size.width * 0.21
                    var i = 0
                    while r < size.width * 0.49 {
                        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                        if i % 37 == 36 { gaps.addEllipse(in: rect) } else { grooves.addEllipse(in: rect) }
                        r += 1.4
                        i += 1
                    }
                    ctx.stroke(grooves, with: .color(.white.opacity(0.045)), lineWidth: 0.6)
                    ctx.stroke(gaps, with: .color(.black), lineWidth: 1.6)
                }
                CoverImage(url: art)
                    .frame(width: d * 0.36, height: d * 0.36)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                Circle().fill(Color(hex: 0xD5D3CE)).frame(width: d * 0.028, height: d * 0.028)
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Brazo: contrapeso arriba del pivote, tubo y cápsula con aguja.
private struct Tonearm: View {
    let size: CGFloat
    let lifted: Bool
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, top = size * 0.12
            ZStack(alignment: .top) {
                // contrapeso
                RoundedRectangle(cornerRadius: w * 0.15)
                    .fill(LinearGradient(colors: [Color(hex: 0x6E6D72), Color(hex: 0x2C2B2F)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 0.62, height: top * 0.55)
                    .offset(y: top * 0.05)
                // tubo
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xE4E3DF), Color(hex: 0x8F8E93)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, w * 0.16), height: h - top * 0.5)
                    .offset(y: top * 0.4)
                // pivote
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x8D8C91), Color(hex: 0x2A292D)], center: .topLeading, startRadius: 0, endRadius: w * 0.5))
                    .frame(width: w * 0.8, height: w * 0.8)
                    .offset(y: top - w * 0.4)
                // cápsula
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0x1E1D21))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
                    .frame(width: w * 0.42, height: size * 0.07)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -w * 0.08, y: h - size * 0.07)
            }
            .frame(width: w, height: h)
        }
        .scaleEffect(lifted ? 1.03 : 1)
        .shadow(color: .black.opacity(lifted ? 0.5 : 0.35), radius: lifted ? 10 : 4, x: lifted ? 6 : 2, y: lifted ? 10 : 4)
        .animation(.easeOut(duration: 0.3), value: lifted)
    }
}

private struct DeckKey: View {
    let icon: String
    let size: CGFloat
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: max(11, size * 0.32), weight: .bold))
            .foregroundStyle(Color(hex: 0xE8E6E1))
            .frame(width: max(36, size), height: max(36, size))
            .background(Circle().fill(Color(hex: 0x3B3A3F)))
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// Vinilo en miniatura para el mini reproductor.
struct MiniVinyl: View {
    let isPlaying: Bool
    let art: URL?
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { tl in
            ZStack {
                Color(hex: 0x16151A)
                Record(art: art)
                    .padding(2)
                    .rotationEffect(.degrees((tl.date.timeIntervalSinceReferenceDate * 200).truncatingRemainder(dividingBy: 360)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Horizontal: el casete o el vinilo a pantalla completa
/// Sólo el objeto, sin barra de acciones encima: la gracia es manejar las teclas del casete o el brazo del vinilo
/// (lo pidió Toxbox, x.1.1). Las acciones básicas siguen en VoiceOver como acciones del objeto. Se sale girando el
/// móvil.
struct ImmersiveDeck: View {
    let style: DeckStyle
    @EnvironmentObject var player: Player

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ThemeBackdrop().opacity(0.55)
            if let song = player.current {
                // La isla dinámica y las esquinas: márgenes de la ventana (en horizontal, a los dos lados) y un poco
                // más, para que las bobinas y el brazo no rocen el borde.
                let inset = Self.windowInsets
                Group {
                    switch style {
                    case .vinyl:
                        HStack(spacing: 28) {
                            VinylView(song: song, clock: player.clock)
                            DeckInfo(song: song, clock: player.clock).frame(maxWidth: 300, alignment: .leading)
                        }
                    case .cassette, .normal, .air:
                        CassetteView(song: song, clock: player.clock)
                    }
                }
                .padding(.leading, inset.left + 12)
                .padding(.trailing, inset.right + 12)
                .padding(.vertical, max(inset.top, inset.bottom, 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .accessibilityAction(named: player.isPlaying ? L("Pausa") : L("Reproducir")) { player.toggle() }
                .accessibilityAction(named: L("Siguiente")) { player.next() }
                .accessibilityAction(named: L("Anterior")) { player.previous() }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .transition(.opacity)
    }

    private static var windowInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.safeAreaInsets ?? .zero
    }
}

/// Título, artista y tiempo junto al tocadiscos en horizontal.
private struct DeckInfo: View {
    let song: Song
    @ObservedObject var clock: PlaybackClock
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrambleText(text: song.title).font(.title.bold()).lineLimit(3)
            Text(song.artist).font(.title3).foregroundStyle(.secondary).lineLimit(2)
            Text("\(timeString(clock.progress)) / \(timeString(clock.duration))")
                .font(.headline).monospacedDigit().foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Ajustes: elegir reproductor
struct DeckPicker: View {
    @AppStorage("deck") private var deck = DeckStyle.normal.rawValue
    @EnvironmentObject var player: Player

    var body: some View {
        HStack(spacing: 12) {
            ForEach(DeckStyle.allCases) { d in
                Button { withAnimation(.uiEaseOut(0.25)) { deck = d.rawValue } } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            switch d {
                            case .normal:
                                Image(systemName: "play.fill").font(.title2).foregroundStyle(.tint)
                            case .cassette:
                                MiniCassette(isPlaying: false).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            case .vinyl:
                                MiniVinyl(isPlaying: false, art: player.current?.thumb(240)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            case .air:
                                MiniAirDisc(art: player.current?.thumb(240)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .frame(width: 76, height: 76)
                        .background(ThemeSurface(radius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(deck == d.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear), lineWidth: 2.5))
                        Text(d.name).font(.subheadline.weight(deck == d.rawValue ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.primary)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel(d.name)
                .accessibilityAddTraits(deck == d.rawValue ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Ajustes: eliminar playlists (fuera del camino para evitar sustos)
struct ManagePlaylistsView: View {
    @EnvironmentObject var library: Library
    @State private var pending: Playlist?

    var body: some View {
        List {
            Section {
                ForEach(library.userPlaylists) { p in
                    HStack(spacing: 12) {
                        PlaylistCover(playlist: p, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).lineLimit(1)
                            Text(songCount(p.songs.count)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { pending = p } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityLabel(L("Eliminar {0}", p.name))
                    }
                }
            } footer: {
                Text(L("Eliminar una playlist no borra sus canciones de Favoritos ni de Descargas."))
            }
            .glassRow()
        }
        .overlay { if library.userPlaylists.isEmpty { Text(L("No hay playlists")).foregroundStyle(.secondary) } }
        .themed()
        .navigationTitle(L("Eliminar playlists"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("¿Eliminar «{0}»?", pending?.name ?? ""), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(L("Eliminar playlist"), role: .destructive) {
                if let p = pending { library.deletePlaylist(p.id) }
                pending = nil
            }
            Button(L("Cancelar"), role: .cancel) { pending = nil }
        } message: {
            Text(L("Se borrará la playlist y su portada. No se puede deshacer."))
        }
    }
}
