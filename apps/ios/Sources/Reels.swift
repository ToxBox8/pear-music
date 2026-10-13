import SwiftUI
import AVFoundation
import Combine
import UIKit

// MARK: - Descubrir (reels)
// Feed vertical a pantalla completa, como los reels de Spotify: cada página suena 30 s
// desde la zona del estribillo, en bucle, con la carátula viva. Desliza para la siguiente,
// doble toque para «Me gusta», «Escuchar completa» la pasa al reproductor principal.
// Usa su propio AVPlayer para no tocar la cola ni el «Ahora suena» del reproductor.

@MainActor
final class ReelsFeed: ObservableObject {
    static let clip: Double = 30

    @Published private(set) var items: [Song] = []
    @Published private(set) var index = 0
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var isPlaying = false
    @Published private(set) var buffering = false
    @Published private(set) var clipProgress: Double = 0
    @Published private(set) var brokenIDs: Set<String> = []

    /// Se llama justo antes de que suene un fragmento (para pausar el reproductor principal).
    var onStart: (@MainActor () -> Void)?

    private let player = AVPlayer()
    private var streams: [String: StreamInfo] = [:]
    private var known: Set<String> = []
    private var statusSub: AnyCancellable?
    private var activation: Task<Void, Never>?
    private var activatedID: String?
    private var clipStart: Double = 0
    private var clipEnd: Double = ReelsFeed.clip
    private var looping = false
    private var visible = false
    private var userPaused = false
    private var loadingMore = false

    init() {
        _ = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in self?.tick(t.seconds) }
        }
    }

    var current: Song? { items.indices.contains(index) ? items[index] : nil }

    // MARK: Contenido
    /// Mezcla las radios de tres canciones que te gustan (o del inicio si aún no hay ninguna).
    func load(seeds: [Song], exclude: Set<String>) async {
        guard items.isEmpty, !loading else { return }
        loading = true
        failed = false
        var pool = seeds
        if pool.isEmpty, let shelves = try? await YTClient.home() {
            pool = shelves.flatMap(\.items).compactMap { item -> Song? in
                if case .song(let s) = item { return s }
                return nil
            }
        }
        let picks = Array(pool.shuffled().prefix(3))
        let radios = await withTaskGroup(of: [Song].self, returning: [[Song]].self) { group in
            for s in picks { group.addTask { (try? await YTClient.radio(for: s.id)) ?? [] } }
            var out: [[Song]] = []
            for await r in group { out.append(r) }
            return out
        }
        // Intercaladas para que no salgan diez seguidas del mismo artista.
        var merged: [Song] = []
        for i in 0..<(radios.map(\.count).max() ?? 0) {
            for r in radios where i < r.count { merged.append(r[i]) }
        }
        known = exclude
        items = merged.filter { known.insert($0.id).inserted }
        index = 0
        loading = false
        failed = items.isEmpty
        if visible { activate() }
    }

    func reload(seeds: [Song], exclude: Set<String>) async {
        stopAudio()
        items = []
        brokenIDs = []
        await load(seeds: seeds, exclude: exclude)
    }

    private func loadMoreIfNeeded() {
        guard !loadingMore, index >= items.count - 4, let seed = items.last else { return }
        loadingMore = true
        Task {
            let more = (try? await YTClient.radio(for: seed.id)) ?? []
            items += more.filter { known.insert($0.id).inserted }
            loadingMore = false
        }
    }

    // MARK: Navegación
    func go(to i: Int) {
        guard items.indices.contains(i), i != index else { return }
        index = i
        userPaused = false
        activate()
        loadMoreIfNeeded()
    }

    func setVisible(_ v: Bool) {
        visible = v
        if !v {
            player.pause()
            isPlaying = false
        } else if activatedID != current?.id {
            activate()
        } else if !userPaused && !buffering && player.currentItem != nil {
            startAudio()
        }
    }

    func toggle() {
        if isPlaying {
            player.pause()
            isPlaying = false
            userPaused = true
        } else {
            userPaused = false
            if !buffering && player.currentItem != nil { startAudio() }
        }
    }

    /// El reproductor principal empezó a sonar: el fragmento se calla y espera.
    func yieldToMainPlayer() {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        userPaused = true
    }

    // MARK: Audio
    private func activate(preferHLS: Bool = true) {
        activation?.cancel()
        stopAudio()
        guard let song = current else { return }
        activatedID = song.id
        buffering = true
        activation = Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await self.stream(for: song.id, preferHLS: preferHLS)
                guard !Task.isCancelled, self.current?.id == song.id else { return }
                let asset = AVURLAsset(url: info.url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": info.userAgent]])
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 8
                self.statusSub = item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self] st in
                    Task { @MainActor in self?.status(st, item: item, song: song, wasHLS: info.isHLS) }
                }
                self.player.replaceCurrentItem(with: item)
                self.prefetch(after: self.index)
            } catch {
                if !Task.isCancelled { self.markBroken(song) }
            }
        }
    }

    private func status(_ st: AVPlayerItem.Status, item: AVPlayerItem, song: Song, wasHLS: Bool) {
        guard song.id == current?.id, player.currentItem === item else { return }
        switch st {
        case .readyToPlay:
            guard buffering else { return }
            let d = item.duration.seconds
            // Hacia el 35 % suele estar el estribillo; las canciones cortas empiezan desde el principio.
            clipStart = d.isFinite && d > Self.clip * 2 ? (d * 0.35).rounded() : 0
            clipEnd = d.isFinite ? min(clipStart + Self.clip, d - 0.4) : clipStart + Self.clip
            player.seek(to: CMTime(seconds: clipStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.player.currentItem === item else { return }
                    self.buffering = false
                    if self.visible && !self.userPaused { self.startAudio() }
                }
            }
        case .failed:
            if wasHLS {
                activate(preferHLS: false)
            } else {
                markBroken(song)
            }
        default:
            break
        }
    }

    private func startAudio() {
        onStart?()
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
    }

    private func stopAudio() {
        statusSub = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        activatedID = nil
        isPlaying = false
        buffering = false
        clipProgress = 0
    }

    private func tick(_ t: Double) {
        guard t.isFinite, player.currentItem != nil, !buffering, !looping else { return }
        if t >= clipEnd {
            // Fin del fragmento: vuelve al principio del fragmento, como un bucle.
            looping = true
            player.seek(to: CMTime(seconds: clipStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in self?.looping = false }
            }
            clipProgress = 0
            return
        }
        clipProgress = min(1, max(0, (t - clipStart) / max(1, clipEnd - clipStart)))
    }

    private func markBroken(_ song: Song) {
        brokenIDs.insert(song.id)
        buffering = false
    }

    private func stream(for id: String, preferHLS: Bool = true) async throws -> StreamInfo {
        let key = "\(id)|\(preferHLS)"
        if let s = streams[key] { return s }
        let s = try await YTClient.streamURL(videoId: id, preferHLS: preferHLS)
        streams[key] = s
        return s
    }

    /// Pide por adelantado la URL de las dos siguientes para que el cambio sea inmediato.
    private func prefetch(after i: Int) {
        guard i + 1 < items.count else { return }
        for j in (i + 1)...min(i + 2, items.count - 1) {
            let id = items[j].id
            Task { _ = try? await self.stream(for: id) }
        }
    }
}

// MARK: - Pantalla
struct ReelsView: View {
    @StateObject private var feed = ReelsFeed()
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @Environment(\.scenePhase) private var scenePhase
    @State private var drag: CGFloat = 0
    @State private var onScreen = false

    private var seeds: [Song] { Array(library.favorites.prefix(12)) + Array(library.recents.prefix(12)) }
    private var exclude: Set<String> { Set(library.favorites.map(\.id)) }

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            // Con .ignoresSafeArea el proxy puede dar 0 arriba: se usa el margen real de la ventana
            // para que la cabecera no se meta debajo de la hora y la batería.
            let top = max(g.safeAreaInsets.top, Self.windowTopInset)
            ZStack(alignment: .top) {
                Color.black
                if feed.items.isEmpty {
                    ThemeBackdrop().opacity(0.5)
                    emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(window, id: \.self) { i in
                        ReelPage(song: feed.items[i], isCurrent: i == feed.index, feed: feed, topInset: top)
                            .frame(width: g.size.width, height: h)
                            .offset(y: CGFloat(i - feed.index) * h + drag)
                    }
                }
                // Velo bajo la barra de estado: la hora y la batería se leen sobre cualquier carátula.
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: top + 72)
                    .allowsHitTesting(false)
                header.padding(.top, top + 6)
            }
            .frame(width: g.size.width, height: h)
            .clipped()
            .contentShape(Rectangle())
            .gesture(pageDrag(height: h))
        }
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.colorScheme, .dark)
        // La barra de pestañas también se oscurece para que el feed no quede cortado por una franja clara.
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color.black, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .accessibilityScrollAction { edge in
            if edge == .bottom { step(1) } else if edge == .top { step(-1) }
        }
        .task { await feed.load(seeds: seeds, exclude: exclude) }
        .onAppear {
            onScreen = true
            feed.onStart = { [weak player] in if player?.isPlaying == true { player?.pause() } }
            feed.setVisible(true)
        }
        .onDisappear {
            onScreen = false
            feed.setVisible(false)
        }
        .onChange(of: scenePhase) { phase in feed.setVisible(onScreen && phase == .active) }
        .onChange(of: player.isPlaying) { if $0 { feed.yieldToMainPlayer() } }
    }

    /// Sólo se dibujan la página actual y sus vecinas.
    private var window: [Int] {
        guard !feed.items.isEmpty else { return [] }
        return Array(max(0, feed.index - 1)...min(feed.items.count - 1, feed.index + 1))
    }

    private func pageDrag(height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { v in
                let dy = v.translation.height
                let atEdge = (feed.index == 0 && dy > 0) || (feed.index >= feed.items.count - 1 && dy < 0)
                drag = atEdge ? dy * 0.25 : dy
            }
            .onEnded { v in
                let dy = v.translation.height
                let fling = v.predictedEndTranslation.height
                var target = feed.index
                if (dy < -h * 0.16 || fling < -h * 0.45) && feed.index < feed.items.count - 1 { target += 1 }
                if (dy > h * 0.16 || fling > h * 0.45) && feed.index > 0 { target -= 1 }
                if target != feed.index { UISelectionFeedbackGenerator().selectionChanged() }
                withAnimation(.uiEaseOut(0.42)) {
                    feed.go(to: target)
                    drag = 0
                }
            }
    }

    private func step(_ d: Int) {
        withAnimation(.uiEaseOut(0.42)) { feed.go(to: feed.index + d) }
    }

    /// Margen superior de la ventana (isla dinámica / notch).
    private static var windowTopInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.safeAreaInsets.top ?? 0
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Descubrir").displayTitle(30)
            Spacer()
            Button {
                Task { await feed.reload(seeds: seeds, exclude: exclude) }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityLabel("Mezclar otra vez")
            .disabled(feed.loading)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 14) {
            if feed.loading || !feed.failed {
                ProgressView().controlSize(.large).tint(.white)
                Text("Buscando música para ti…").font(.headline)
            } else {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 34, weight: .semibold))
                Text("No hay fragmentos ahora mismo").font(.headline)
                Text("Revisa la conexión y vuelve a intentarlo.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                Button { Task { await feed.reload(seeds: seeds, exclude: exclude) } } label: {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .frame(maxWidth: 220)
                .padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(32)
    }
}

// MARK: - Página
private extension AppTheme {
    /// Los reels son siempre oscuros: un acento negro (Aire) se cambiaría por blanco.
    var reelAccent: Color { self == .air ? .white : accent }
    var reelOnAccent: Color { self == .air ? .black : onAccent }
}

private struct ReelPage: View {
    let song: Song
    let isCurrent: Bool
    @ObservedObject var feed: ReelsFeed
    var topInset: CGFloat
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @EnvironmentObject var jam: JamService
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false
    @State private var flash: String?

    var body: some View {
        let theme = AppTheme(rawValue: themeID) ?? .glass
        let playing = isCurrent && feed.isPlaying
        let broken = feed.brokenIDs.contains(song.id)

        GeometryReader { g in
            let side = min(g.size.width - 64, g.size.height * 0.46)
            ZStack {
                ReelBackground(url: song.thumb(400), animating: playing && !reduceMotion)

                VStack(spacing: 0) {
                    Spacer(minLength: topInset + 64)
                    ReelArtwork(url: song.thumb(900), side: side, radius: min(30, theme.maxRadius),
                                animating: playing && !reduceMotion)
                        .overlay {
                            if isCurrent && feed.buffering { ProgressView().controlSize(.large).tint(.white) }
                        }
                        .overlay {
                            if let flash {
                                Image(systemName: flash)
                                    .font(.system(size: 54, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.4), radius: 12)
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .overlay {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 120, weight: .bold))
                                .foregroundStyle(theme.reelAccent)
                                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                                .scaleEffect(burst ? 1.08 : 0.4)
                                .opacity(burst ? 1 : 0)
                                .allowsHitTesting(false)
                        }
                    Spacer(minLength: 24)

                    HStack(alignment: .bottom, spacing: 16) {
                        info(theme: theme, broken: broken)
                        actions(theme: theme)
                    }
                    .padding(.horizontal, 20)

                    ClipProgress(feed: feed, active: isCurrent, tint: theme.reelAccent)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 14)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { like() }
            .onTapGesture { togglePlayback() }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Me gusta") { like() }
        .accessibilityAction(named: playing ? "Pausar" : "Reproducir") { togglePlayback() }
    }

    private func info(theme: AppTheme, broken: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(song.title).displayTitle(26).lineLimit(2)
            Text(song.artist).font(.body.weight(.medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            if broken {
                Label("Este fragmento no se pudo cargar", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 4)
            }
            Button {
                feed.yieldToMainPlayer()
                let rest = Array(feed.items.drop(while: { $0.id != song.id }))
                player.play(song, in: rest)
                player.showFullPlayer = true
            } label: {
                Label("Escuchar completa", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .foregroundStyle(theme.reelOnAccent)
                    .background(Capsule().fill(theme.reelAccent))
            }
            .buttonStyle(TactileButtonStyle())
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
    }

    private func actions(theme: AppTheme) -> some View {
        let fav = library.isFavorite(song)
        return VStack(spacing: 18) {
            Button { library.toggleFavorite(song) } label: {
                ReelActionLabel(symbol: fav ? "heart.fill" : "heart", text: "Me gusta", tint: fav ? theme.reelAccent : .white)
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityLabel(fav ? "Quitar de favoritos" : "Añadir a favoritos")

            Menu {
                if jam.isActive {
                    Button { jam.add(song) } label: { Label("Añadir al Jam", systemImage: "person.2.wave.2") }
                        .disabled(jam.contains(song))
                }
                ForEach(library.userPlaylists) { p in
                    Button(p.name) { library.add(song, to: p) }
                }
                if library.userPlaylists.isEmpty && !jam.isActive {
                    Text("Crea una playlist en Biblioteca")
                }
            } label: {
                ReelActionLabel(symbol: "plus.circle", text: "Añadir")
            }
            .accessibilityLabel("Añadir a una playlist")

            if let url = URL(string: "https://music.youtube.com/watch?v=\(song.id)") {
                ShareLink(item: url, subject: Text(song.title), message: Text("\(song.title) — \(song.artist)")) {
                    ReelActionLabel(symbol: "paperplane", text: "Compartir")
                }
            }

            Menu { SongMenuItems(song: song) } label: {
                ReelActionLabel(symbol: "ellipsis", text: "Más")
            }
            .accessibilityLabel("Más opciones")
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
    }

    private func togglePlayback() {
        guard isCurrent, !feed.buffering else { return }
        let symbol = feed.isPlaying ? "pause.fill" : "play.fill"
        feed.toggle()
        withAnimation(.uiEaseOut(0.2)) { flash = symbol }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.uiEaseOut(0.3)) { if flash == symbol { flash = nil } }
        }
    }

    /// Doble toque: siempre marca «Me gusta» (nunca lo quita) y lanza el corazón.
    private func like() {
        if !library.isFavorite(song) { library.toggleFavorite(song) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.uiEaseOut(0.35)) { burst = false }
        }
    }
}

private struct ReelActionLabel: View {
    let symbol: String
    let text: String
    var tint: Color = .white

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 48, height: 40)
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .frame(minWidth: 56)
        .contentShape(Rectangle())
    }
}

/// Barra fina con lo que llevas del fragmento; se redibuja sola sin tocar la página entera.
private struct ClipProgress: View {
    @ObservedObject var feed: ReelsFeed
    let active: Bool
    let tint: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(tint)
                    .frame(width: g.size.width * (active ? feed.clipProgress : 0))
                    .animation(.linear(duration: 0.1), value: feed.clipProgress)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// Carátula que respira y se inclina despacio mientras suena.
private struct ReelArtwork: View {
    let url: URL?
    let side: CGFloat
    let radius: CGFloat
    let animating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let breath = animating ? 1 + 0.022 * sin(t * 2 * .pi / 4.2) : 1
            let tilt = animating ? 5 * sin(t * 2 * .pi / 9) : 0
            CoverImage(url: url)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
                .scaleEffect(breath)
                .rotation3DEffect(.degrees(tilt), axis: (x: 0.25, y: 1, z: 0), perspective: 0.55)
                .shadow(color: .black.opacity(0.45), radius: 34, y: 22)
        }
        .animation(.uiEaseOut(0.6), value: animating)
    }
}

/// La propia carátula, enorme y desenfocada, girando muy despacio detrás de todo.
private struct ReelBackground: View {
    let url: URL?
    let animating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let side = max(g.size.width, g.size.height) * 1.6
                CoverImage(url: url)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees((t * 4).truncatingRemainder(dividingBy: 360)))
                    .blur(radius: 70)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
            }
        }
        .overlay(
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.1), .black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipped()
        .accessibilityHidden(true)
    }
}
