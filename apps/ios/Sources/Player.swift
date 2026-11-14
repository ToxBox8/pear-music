import AVFoundation
import MediaPlayer
import Combine
import UIKit

/// Tiempo de reproducción aparte del Player: cambia cada 0,5 s y, si lo publicara el
/// Player, toda la interfaz (incluido el mini reproductor) se redibujaría sin parar.
@MainActor
final class PlaybackClock: ObservableObject {
    /// Llega cada 0,5 s; `stamp` dice cuándo, para calcular el valor entre medias (AirDisc).
    @Published var progress = 0.0 { didSet { stamp = Date() } }
    @Published var duration = 0.0
    private(set) var stamp = Date()

    /// Progreso estimado en `date` mientras suena a velocidad `rate`.
    func progress(at date: Date, playing: Bool, rate: Float) -> Double {
        guard playing else { return progress }
        return min(duration, progress + date.timeIntervalSince(stamp) * Double(rate))
    }
}

@MainActor
final class Player: ObservableObject {
    @Published var queue: [Song] = []
    @Published var index = 0
    @Published var isPlaying = false
    let clock = PlaybackClock()
    var progress: Double {
        get { clock.progress }
        set { if clock.progress != newValue { clock.progress = newValue } }
    }
    var duration: Double {
        get { clock.duration }
        set { if clock.duration != newValue { clock.duration = newValue } }
    }
    @Published var error: String?
    /// Reproductor completo abierto (se presenta desde la raíz para que funcione con el accesorio de iOS 26).
    @Published var showFullPlayer = false
    /// Velocidad de reproducción (botón «x1» del reproductor Air).
    @Published private(set) var rate: Float = 1
    /// Bucle: desactivado, repetir la cola o repetir la canción. Se guarda entre sesiones.
    @Published var repeatMode: RepeatMode = RepeatMode(rawValue: UserDefaults.standard.string(forKey: "repeatMode") ?? "") ?? .off {
        didSet {
            UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
            MPRemoteCommandCenter.shared().changeRepeatModeCommand.currentRepeatType = repeatMode.remote
        }
    }

    var current: Song? { queue.indices.contains(index) ? queue[index] : nil }

    private let player = AVPlayer()
    private var loadTask: Task<Void, Never>?
    private var statusSub: AnyCancellable?
    private var artwork: MPMediaItemArtwork?
    private var timeObserver: Any?
    private var fadeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var loadTimeout: Task<Void, Never>?
    /// Si sonaba al empezar una interrupción: sólo entonces se reanuda al acabar.
    private var resumeAfterInterruption = false

    init() {
        // La sesión se activa al reproducir la primera canción (ver `load`), no al abrir la app,
        // para no cortar el audio de otras apps antes de tiempo.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        Task { @MainActor [weak self] in SleepTimer.shared.player = self }

        player.allowsExternalPlayback = false // el audio sale por la ruta del iPhone (AirPlay/altavoces)
        // Fundido entre canciones: se recalcula 10 veces por segundo (el progreso de la interfaz va cada 0,5 s).
        fadeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                let secs = UserDefaults.standard.integer(forKey: "crossfade")
                let d = self.player.currentItem?.duration.seconds ?? 0
                let hasNext = self.index + 1 < self.queue.count || self.repeatMode != .off
                let f = Fade.factor(position: t.seconds.isFinite ? t.seconds : 0, duration: d.isFinite ? d : 0, hasNext: hasNext, seconds: secs)
                if f != self.fadeVolume { self.fadeVolume = f }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                self.progress = t.seconds.isFinite ? t.seconds : 0
                if let d = self.player.currentItem?.duration.seconds, d.isFinite { self.duration = d }
                // Estadísticas: cada vez que empieza una canción puede contar una escucha.
                if self.isPlaying, !self.playCounted, let song = self.current,
                   PlayStats.shouldCount(position: self.progress, duration: self.duration) {
                    self.playCounted = true
                    PlayStats.shared.record(song)
                }
            }
        }

        // Llamadas, alarmas u otras apps: el sistema pausa el audio y hay que reflejarlo en la interfaz.
        let session = AVAudioSession.sharedInstance()
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0)
            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .began:
                    self.resumeAfterInterruption = self.isPlaying
                    self.isPlaying = false
                    self.updateNowPlaying()
                case .ended:
                    // Si estaba en pausa antes de la llamada, sigue en pausa aunque el sistema diga «reanudar».
                    if options.contains(.shouldResume) && self.resumeAfterInterruption { self.resume() }
                    self.resumeAfterInterruption = false
                @unknown default:
                    break
                }
            }
        }
        // Al desconectar unos auriculares la música se pausa, como en cualquier reproductor.
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.pause() }
        }

        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        rc.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        rc.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        rc.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        // Bucle desde la pantalla de bloqueo, CarPlay o los auriculares.
        rc.changeRepeatModeCommand.isEnabled = true
        rc.changeRepeatModeCommand.currentRepeatType = repeatMode.remote
        rc.changeRepeatModeCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.repeatMode = RepeatMode(remote: e.repeatType) }
            return .success
        }
        rc.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in self?.seek(to: e.positionTime) }
            }
            return .success
        }
    }

    // MARK: Cola
    /// Lo añadido a la cola que aún no ha sonado (ver `UpNext`).
    private var queued = Set<String>()

    /// Reproduce `song` y usa `list` como cola (empezando en esa canción).
    func play(_ song: Song, in list: [Song]) {
        queue = list.isEmpty ? [song] : list
        index = queue.firstIndex(where: { $0.id == song.id }) ?? 0
        lastRadioSeed = nil // cola nueva: aunque sea la misma canción de antes, vuelve a tocar radio
        queued.removeAll()
        load()
    }
    /// Cola de verdad (sugerencia del ticket 7): la canción suena justo después de la actual o, si ya habías añadido
    /// otras, detrás de ellas; antes iba al final de la playlist o de la radio.
    func enqueue(_ song: Song) {
        if queue.isEmpty { queue = [song]; index = 0; load(); return }
        queue.insert(song, at: UpNext.insertAt(queue.map(\.id), current: index, queued: queued))
        queued.insert(song.id)
    }
    /// Justo después de la actual, por delante de lo que ya estaba en la cola (y cuenta como parte de ella).
    func playNext(_ song: Song) {
        if queue.isEmpty { enqueue(song); return }
        queue.insert(song, at: index + 1)
        queued.insert(song.id)
    }
    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        load()
    }
    func move(from: IndexSet, to: Int) {
        let cur = index
        let currentSong = current
        queue.move(fromOffsets: from, toOffset: to)
        if let s = currentSong, let i = queue.firstIndex(where: { $0.id == s.id }) { index = i } else { index = cur }
    }
    /// Quita todo lo que viene después de la canción actual.
    func clearUpcoming() {
        guard index + 1 < queue.count else { return }
        queue.removeSubrange((index + 1)...)
    }
    func remove(at offsets: IndexSet) {
        let removedCurrent = offsets.contains(index)
        index -= offsets.filter { $0 < index }.count
        queue.remove(atOffsets: offsets)
        if queue.isEmpty { stop(); return }
        index = min(max(index, 0), queue.count - 1)
        if removedCurrent { load() }
    }

    /// Capturas (Screenshots.swift): una canción cargada en pausa, sin tocar la red ni el audio.
    func preview(queue: [Song], index: Int, progress: Double, duration: Double) {
        self.queue = queue
        self.index = index
        isPlaying = false
        self.progress = progress
        self.duration = duration
    }

    // MARK: Control
    func next() {
        if index + 1 < queue.count { index += 1; load() }
        else if repeatMode == .all && !queue.isEmpty { index = 0; load() }   // repetir lista: vuelve al principio
        else { pause(); seek(to: 0) }
    }
    func cycleRepeat() { repeatMode = repeatMode.next }
    /// Fin natural de la canción: con «repetir canción» vuelve a empezar; si no, pasa a la siguiente.
    private func itemEnded() {
        // Temporizador «al acabar la canción»: se para aquí, sin pasar a la siguiente.
        if SleepTimer.shared.stopsAtEndOfSong() { pause(); return }
        if repeatMode == .one { playCounted = false; seek(to: 0); resume() } else { next() }
    }
    func previous() {
        if progress > 3 || index == 0 { seek(to: 0) } else { index -= 1; load() }
    }
    func toggle() { isPlaying ? pause() : resume() }
    func setRate(_ r: Float) {
        rate = r
        player.defaultRate = r          // play() arranca a esta velocidad (iOS 16+)
        if isPlaying { player.rate = r }
        updateNowPlaying()
    }
    func resume() { player.play(); isPlaying = true; updateNowPlaying() }
    /// Jam «cada uno en su móvil» (2.6 de x.1.1): acelera o frena un poco para alcanzar al anfitrión, sin tocar la
    /// velocidad elegida (`rate`), y dónde va exactamente la canción.
    func nudge(_ factor: Float) { if isPlaying { player.rate = rate * factor } }
    var livePosition: Double { player.currentTime().seconds }
    /// Volumen propio de la app = temporizador × fundido; no toca el volumen del sistema.
    private var sleepVolume: Float = 1 { didSet { applyVolume() } }
    private var fadeVolume: Float = 1 { didSet { applyVolume() } }
    private func applyVolume() { player.volume = min(1, max(0, sleepVolume * fadeVolume)) }
    /// Lo baja el temporizador para dormir en sus últimos segundos.
    func setVolume(_ v: Float) { sleepVolume = v }
    func pause() { player.pause(); isPlaying = false; resumeAfterInterruption = false; updateNowPlaying() }
    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress = seconds
        updateNowPlaying()
    }
    private func stop() {
        loadTask?.cancel()
        loadTimeout?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false; progress = 0; duration = 0
    }

    // MARK: Carga (local si está descargada, si no streaming)
    /// `preferHLS`: primero la lista HLS de sólo audio; si AVPlayer la rechaza se reintenta con la URL directa.
    /// `renewed`: ya se pidió un identificador de visitante nuevo tras un fallo (sólo se reintenta una vez).
    private func load(preferHLS: Bool = true, renewed: Bool = false) {
        loadTask?.cancel()
        loadTimeout?.cancel()
        guard let song = current else { return }
        // Lo de la cola deja de serlo al sonar.
        queued.remove(song.id)
        try? AVAudioSession.sharedInstance().setActive(true)
        error = nil; progress = 0; duration = 0; artwork = nil
        playCounted = false
        extendWithRadioIfNeeded()
        loadTask = Task {
            do {
                let asset: AVURLAsset
                var usedHLS = false
                if let local = DownloadStore.shared.localURL(for: song.id) {
                    asset = AVURLAsset(url: local)
                } else {
                    let (info, _) = try await YTClient.playableStream(for: song, preferHLS: preferHLS)
                    usedHLS = info.isHLS
                    asset = AVURLAsset(url: info.url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": info.userAgent]])
                }
                if Task.isCancelled { return }
                let item = AVPlayerItem(asset: asset)
                item.audioTimePitchAlgorithm = .spectral   // sin voz de ardilla al acelerar
                let retryDirect = usedHLS
                // Si la URL directa también falla (p. ej. 403 por un identificador de visitante viejo),
                // se pide otro identificador y otra URL una sola vez, como en Android.
                let retryRenewed = !usedHLS && !renewed && DownloadStore.shared.localURL(for: song.id) == nil
                statusSub = item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self] st in
                    guard st == .failed else { return }
                    Task { @MainActor in
                        guard let self, self.current?.id == song.id else { return }
                        if retryDirect { self.load(preferHLS: false, renewed: renewed); return }
                        if retryRenewed { YTClient.resetVisitorData(); self.load(preferHLS: true, renewed: true); return }
                        self.error = L("Fallo al reproducir: {0}", Player.describe(item.error))
                        self.isPlaying = false
                    }
                }
                // Sólo el fin de ESTE item avanza la cola (antes se escuchaba cualquier item).
                if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
                endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.itemEnded() }
                }
                player.replaceCurrentItem(with: item)
                player.play()
                isPlaying = true
                updateNowPlaying()
                loadArtwork(for: song)

                // Si no está listo en un tiempo razonable se trata como un fallo (igual que si AVPlayer lo rechazara).
                loadTimeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard !Task.isCancelled, let self, self.current?.id == song.id,
                          item.status == .unknown else { return }
                    if retryDirect { self.load(preferHLS: false, renewed: renewed); return }
                    self.error = L("Fallo al reproducir: tiempo de espera agotado")
                    self.isPlaying = false
                }
            } catch {
                if !Task.isCancelled {
                    self.error = L("No se pudo obtener el audio: {0}", error.localizedDescription)
                    isPlaying = false
                }
            }
        }
    }

    /// Mensaje con el código real de AVFoundation en vez de "unknown error".
    private static func describe(_ error: Error?) -> String {
        guard let ns = error as NSError? else { return "desconocido" }
        var text = "\(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " ← [\(under.domain) \(under.code)]"
        }
        return text
    }

    private func updateNowPlaying() {
        guard let s = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: s.title,
            MPMediaItemPropertyArtist: s.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Radio infinita (ajuste `autoplay`, activado por defecto): al empezar la última canción de la cola con el bucle
    /// apagado, se añaden canciones parecidas. Mismas reglas que `AutoRadio` en Android.
    private var lastRadioSeed: String?
    /// Si la canción que suena ya se ha apuntado en las estadísticas.
    private var playCounted = false
    static let radioBatch = 20

    /// Las de `radio` que no están ya en la cola ni repetidas, como mucho `radioBatch`.
    static func freshRadio(_ radio: [Song], queued: Set<String>) -> [Song] {
        var seen = queued
        return Array(radio.filter { seen.insert($0.id).inserted }.prefix(radioBatch))
    }

    private func extendWithRadioIfNeeded() {
        let enabled = UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true
        guard enabled, repeatMode == .off, index == queue.count - 1, let seed = current?.id, seed != lastRadioSeed else { return }
        lastRadioSeed = seed
        Task { [weak self] in
            let radio = (try? await YTClient.radio(for: seed)) ?? []
            guard let self, self.current?.id == seed, self.index == self.queue.count - 1 else { return }
            self.queue += Player.freshRadio(radio, queued: Set(self.queue.map(\.id)))
        }
    }

    private func loadArtwork(for song: Song) {
        guard let url = song.thumb(1000) else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = UIImage(data: data), current?.id == song.id else { return }
            artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            updateNowPlaying()
        }
    }
}

/// Estados del bucle, con el mismo nombre de ajuste en Android (`repeatMode`: off / all / one).
enum RepeatMode: String, CaseIterable {
    case off, all, one

    var next: RepeatMode {
        switch self { case .off: return .all; case .all: return .one; case .one: return .off }
    }
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
    var label: String {
        switch self { case .off: return L("Repetir: no"); case .all: return L("Repetir lista"); case .one: return L("Repetir canción") }
    }
    var remote: MPRepeatType {
        switch self { case .off: return .off; case .all: return .all; case .one: return .one }
    }
    init(remote: MPRepeatType) {
        switch remote { case .one: self = .one; case .all: self = .all; default: self = .off }
    }
}

/// Cola de verdad (sugerencia del ticket 7): lo que se añade a la cola suena justo después de la canción actual y, si
/// ya habías añadido otras, detrás de ellas. `queued` son los ids añadidos así que aún no han sonado. Igual que
/// `UpNext` en Android.
enum UpNext {
    /// Dónde meter una canción nueva: tras la actual, saltando las que ya están en la cola.
    static func insertAt(_ ids: [String], current: Int, queued: Set<String>) -> Int {
        var at = min(max(current + 1, 0), ids.count)
        while at < ids.count && queued.contains(ids[at]) { at += 1 }
        return at
    }
}
