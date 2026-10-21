import Foundation
import MultipeerConnectivity
import AVFoundation
import CoreImage.CIFilterBuiltins
import UIKit
import SwiftUI

// MARK: - Jam: playlist hecha entre amigos que están cerca
// Sin servidor: los móviles se encuentran por WiFi/Bluetooth (MultipeerConnectivity, v1) y,
// para jugar con Android, también por Bonjour + TCP (protocolo abierto v2, JamNet.swift).
// Quien crea el Jam es el anfitrión y guarda la versión buena de la lista; los demás
// le mandan lo que añaden o quitan y él reparte la lista actualizada a todos.
// Para unirse hace falta su código de 6 caracteres (o escanear el QR, que lleva
// libremusic://jam/CÓDIGO y también abre la app desde la cámara del iPhone).

struct JamEntry: Codable, Identifiable, Hashable {
    let song: Song
    let by: String
    var id: String { song.id }
}

struct JamState: Codable, Equatable {
    var name: String
    var code: String
    var host: String
    var members: [String]
    var entries: [JamEntry]
    /// v2.1 (x.1.1): «altavoz» (suena sólo en el anfitrión) o «todos» (cada uno en su móvil). nil = altavoz (antiguo).
    var mode: String? = nil
    var everyone: Bool { mode == JamSync.everyone }
}

private enum JamMessage: Codable {
    case hello(name: String)
    case state(JamState)
    case add(JamEntry)
    case remove(songID: String)
    case ended
}

@MainActor
final class JamService: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case hosting
        case searching
        case joined
        /// Sin conexión con el anfitrión: la lista se conserva para poder guardarla.
        case lost(String)
    }

    nonisolated static let serviceType = "lm-jam"
    nonisolated static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    /// MultipeerConnectivity admite hasta 8 personas por sesión, anfitrión incluido.
    static let maxPeople = 8

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var jam: JamState?
    @Published private(set) var searchStalled = false
    @Published private(set) var joiningCode: String?
    /// Anfitrión: su dirección en la Wi-Fi para el QR (Fase 3.2).
    @Published fileprivate(set) var direct: String?
    /// Direcciones directas vistas en enlaces o QR, por código (desde cualquier hilo: el escáner no va en el principal).
    final class DirectHints: @unchecked Sendable {
        static let shared = DirectHints()
        private let lock = NSLock()
        private var map: [String: (String, UInt16)] = [:]
        func remember(_ text: String) {
            guard let c = JamService.code(from: text), let d = JamService.direct(from: text) else { return }
            lock.lock(); map[c] = d; lock.unlock()
        }
        func take(_ code: String) -> (String, UInt16)? { lock.lock(); defer { lock.unlock() }; return map[code] }
    }
    @Published var showSheet = false
    /// Código que llegó por enlace o QR y espera a que la hoja del Jam lo use.
    @Published var pendingCode: String?

    var isActive: Bool { phase == .hosting || phase == .joined }
    var isHost: Bool { phase == .hosting }
    private(set) var myName = ""

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var names: [MCPeerID: String] = [:]
    private var stallTask: Task<Void, Never>?
    // Jam v2 (JamNet.swift): protocolo abierto para Android, en paralelo a MultipeerConnectivity.
    private var host2: JamHostV2?
    private var guest2: JamGuestV2?
    private var names2: [UUID: String] = [:]
    private var joinedViaV2 = false

    // «Cada uno en su móvil» (v2.1, 2.6 de x.1.1)
    /// Invitado: lo último que suena en el anfitrión; `JamPlaybackSync` lo sigue con el reproductor.
    @Published private(set) var remotePlay: JamWire?
    /// Invitado en modo «todos»: si suena también en este iPhone (se puede quitar si está al lado del altavoz).
    @Published var listenHere = true
    private var clockSamples: [JamSync.Sample] = []
    private var pinger: Task<Void, Never>?
    /// Anfitrión: lo último que mandó, para quien entra a mitad de canción.
    private var lastPlay: JamWire?
    /// Diferencia de reloj con el anfitrión, o nil si aún no se ha medido.
    var clockOffset: Int64? { JamSync.offset(clockSamples) }

    // MARK: Códigos
    static func makeCode() -> String { String((0..<6).map { _ in alphabet.randomElement()! }) }

    /// Mayúsculas, sin espacios ni caracteres fuera del alfabeto (O→0 no existe: se descartan).
    nonisolated static func normalize(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) }.prefix(6))
    }

    /// Acepta «libremusic://jam/ABC123» o el código suelto.
    nonisolated static func code(from text: String) -> String? {
        if let url = URL(string: text), url.scheme == "libremusic", url.host == "jam" {
            let c = normalize(url.lastPathComponent)
            return c.count == 6 ? c : nil
        }
        let c = normalize(text)
        return c.count == 6 && text.trimmingCharacters(in: .whitespacesAndNewlines).count == 6 ? c : nil
    }

    /// Con `direct` («IP:puerto» del anfitrión) quien escanea el QR entra al momento (Fase 3.2). Las versiones viejas
    /// sólo leen la ruta, así que ignoran `?h=`. Igual que `JamLink` en Android.
    static func link(_ code: String, direct: String? = nil) -> String {
        "libremusic://jam/\(code)" + (direct.map { "?h=\($0)" } ?? "")
    }

    /// La dirección directa de un enlace (sólo IPv4 privadas y puertos 1024–65535), o nil.
    nonisolated static func direct(from text: String) -> (String, UInt16)? {
        guard let comps = URLComponents(string: text), let h = comps.queryItems?.first(where: { $0.name == "h" })?.value else { return nil }
        let parts = h.split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]), port >= 1024 else { return nil }
        let o = parts[0].split(separator: ".").compactMap { Int($0) }
        guard o.count == 4, o.allSatisfy({ (0...255).contains($0) }) else { return nil }
        let isPrivate = o[0] == 10 || (o[0] == 172 && (16...31).contains(o[1])) || (o[0] == 192 && o[1] == 168)
        return isPrivate ? (String(parts[0]), port) : nil
    }

    func handle(url: URL) {
        guard let c = Self.code(from: url.absoluteString) else { return }
        DirectHints.shared.remember(url.absoluteString)
        pendingCode = c
        showSheet = true
    }

    // MARK: Crear / unirse / salir
    func host(title: String, as name: String) {
        leave(notify: false)
        myName = Self.cleanName(name)
        let me = MCPeerID(displayName: myName)
        let code = Self.makeCode()
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        jam = JamState(name: trimmed.isEmpty ? "Jam de \(myName)" : trimmed, code: code, host: myName, members: [myName], entries: [])
        session = makeSession(me)
        let adv = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: ["code": code], serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        let h = JamHostV2(name: jam?.name ?? "Jam", code: code, host: myName)
        h?.onDirect = { [weak self] addr in Task { @MainActor in self?.direct = addr } }
        h?.onMessage = { [weak self] id, msg in Task { @MainActor in self?.received2(msg, from: id) } }
        h?.onClose = { [weak self] id in Task { @MainActor in self?.closed2(id) } }
        host2 = h
        phase = .hosting
    }

    func join(code raw: String, as name: String) {
        let code = Self.normalize(raw)
        guard code.count == 6 else { return }
        leave(notify: false)
        myName = Self.cleanName(name)
        let me = MCPeerID(displayName: myName)
        session = makeSession(me)
        joiningCode = code
        let b = MCNearbyServiceBrowser(peer: me, serviceType: Self.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
        let g = JamGuestV2(code: code, name: myName, direct: DirectHints.shared.take(code))
        g.onMessage = { [weak self] msg in Task { @MainActor in self?.receivedFromHost2(msg) } }
        g.onClose = { [weak self] in Task { @MainActor in self?.hostClosed2() } }
        guest2 = g
        searchStalled = false
        phase = .searching
        stallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .searching else { return }
            self.searchStalled = true
        }
    }

    /// Sale del Jam. Si eres el anfitrión, se termina para todos.
    func leave(notify: Bool = true) {
        if notify && isHost {
            send(.ended, to: session?.connectedPeers ?? [])
            host2?.broadcast(JamWire(type: "ended"), to: Set(names2.keys))
        }
        disconnect()
        jam = nil
        phase = .idle
        joiningCode = nil
        searchStalled = false
    }

    private func disconnect() {
        stallTask?.cancel()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        names = [:]
        host2?.stop()
        host2 = nil
        guest2?.stop()
        guest2 = nil
        names2 = [:]
        joinedViaV2 = false
        pinger?.cancel()
        pinger = nil
        clockSamples = []
        remotePlay = nil
        lastPlay = nil
        listenHere = true
    }

    /// Anfitrión: un altavoz o cada uno en su móvil (2.6 de x.1.1). Sólo lo siguen los invitados del Jam v2.
    func setMode(_ mode: String) {
        guard isHost else { return }
        jam?.mode = mode == JamSync.everyone ? JamSync.everyone : JamSync.speaker
        broadcast()
    }

    /// Anfitrión en modo «todos»: lo que suena aquí, para que los demás lo sigan.
    func hostPlayback(song: Song?, positionMs: Int64, playing: Bool) {
        guard isHost, jam?.everyone == true else { return }
        let msg = JamWire(type: "play", song: song, positionMs: positionMs, atMs: JamSync.now(), playing: playing)
        lastPlay = msg
        host2?.broadcast(msg, to: Set(names2.keys))
    }

    /// Invitado: unas medidas de reloj seguidas al entrar y luego una cada 30 s (sólo cuentan las más rápidas).
    private func startPinger() {
        pinger?.cancel()
        clockSamples = []
        pinger = Task { [weak self] in
            for _ in 0..<JamSync.firstPings {
                self?.guest2?.send(JamWire(type: "ping", t0: JamSync.now()))
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(JamSync.pingEvery * 1_000_000_000))
                self?.guest2?.send(JamWire(type: "ping", t0: JamSync.now()))
            }
        }
    }

    // MARK: Canciones
    func contains(_ song: Song) -> Bool { jam?.entries.contains { $0.song.id == song.id } ?? false }

    func add(_ song: Song) {
        guard isActive, !contains(song) else { return }
        let entry = JamEntry(song: song, by: myName)
        jam?.entries.append(entry)          // se ve al instante; el anfitrión confirma después
        if isHost {
            broadcast()
        } else if joinedViaV2 {
            guest2?.send(JamWire(type: "add", entry: entry))
        } else {
            send(.add(entry), to: session?.connectedPeers ?? [])
        }
    }

    func canRemove(_ e: JamEntry) -> Bool { isHost || e.by == myName }

    func remove(_ e: JamEntry) {
        guard isActive, canRemove(e) else { return }
        jam?.entries.removeAll { $0.id == e.id }
        if isHost {
            broadcast()
        } else if joinedViaV2 {
            guest2?.send(JamWire(type: "remove", songID: e.id))
        } else {
            send(.remove(songID: e.id), to: session?.connectedPeers ?? [])
        }
    }

    // MARK: Red
    private func makeSession(_ me: MCPeerID) -> MCSession {
        let s = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }

    private func send(_ msg: JamMessage, to peers: [MCPeerID]) {
        guard let session, !peers.isEmpty, let data = try? JSONEncoder().encode(msg) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    private func broadcast() {
        guard isHost, let jam else { return }
        send(.state(jam), to: session?.connectedPeers ?? [])
        host2?.broadcast(JamWire(type: "state", state: jam), to: Set(names2.keys))
    }

    // MARK: Jam v2 (anfitrión)
    private func received2(_ msg: JamWire, from id: UUID) {
        guard isHost, var current = jam else { return }
        switch msg.type {
        case "hello":
            guard msg.code == current.code else {
                host2?.send(JamWire(type: "error", reason: "bad_code"), to: id)
                host2?.drop(id)
                return
            }
            guard current.members.count < JamV2.maxPeople else {
                host2?.send(JamWire(type: "error", reason: "full"), to: id)
                host2?.drop(id)
                return
            }
            let name = Self.cleanName(msg.name ?? "")
            host2?.markGreeted(id)
            names2[id] = name
            current.members.append(name)
            jam = current
            broadcast()
            if current.everyone, let lastPlay { host2?.send(lastPlay, to: id) }
        case "ping":
            guard names2[id] != nil, let t0 = msg.t0 else { return }
            host2?.send(JamWire(type: "pong", t0: t0, th: JamSync.now()), to: id)
        case "add":
            guard names2[id] != nil, let e = msg.entry, JamV2.acceptable(e), current.entries.count < JamV2.maxEntries else { return }
            if !current.entries.contains(where: { $0.id == e.id }) {
                current.entries.append(e)
                jam = current
            }
            broadcast()
        case "remove":
            guard let who = names2[id], let songID = msg.songID else { return }
            current.entries.removeAll { $0.id == songID && $0.by == who }
            jam = current
            broadcast()
        default:
            break
        }
    }

    private func closed2(_ id: UUID) {
        guard isHost, let name = names2.removeValue(forKey: id),
              let i = jam?.members.lastIndex(of: name), i > 0 else { return }
        jam?.members.remove(at: i)
        broadcast()
    }

    // MARK: Jam v2 (invitado)
    private func receivedFromHost2(_ msg: JamWire) {
        guard !isHost, phase == .searching || phase == .joined else { return }
        switch msg.type {
        case "state":
            guard let s = msg.state else { return }
            if phase == .searching {
                stallTask?.cancel()
                browser?.stopBrowsingForPeers()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            if !joinedViaV2 { startPinger() }
            joinedViaV2 = true
            jam = s
            phase = .joined
        case "play":
            remotePlay = msg
        case "pong":
            guard let t0 = msg.t0, let th = msg.th else { return }
            clockSamples.append(JamSync.sample(t0: t0, th: th, t1: JamSync.now()))
            if clockSamples.count > 12 { clockSamples.removeFirst() }
        case "ended":
            let host = jam?.host ?? L("El anfitrión")
            disconnect()
            phase = .lost(L("{0} ha terminado el Jam.", host))
        case "error":
            disconnect()
            phase = .lost(msg.reason == "full" ? L("El Jam está lleno.") : L("El código no es válido."))
        default:
            break
        }
    }

    private func hostClosed2() {
        guard joinedViaV2, phase == .joined else { return }
        let host = jam?.host ?? L("el anfitrión")
        disconnect()
        phase = .lost(L("Se perdió la conexión con {0}.", host))
    }

    private static func cleanName(_ raw: String) -> String {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // MCPeerID admite como mucho 63 bytes y nunca un nombre vacío.
        var out = n.isEmpty ? "Invitado" : String(n.prefix(24))
        while out.utf8.count > 60 { out.removeLast() }
        return out
    }

    fileprivate func received(_ msg: JamMessage, from peer: MCPeerID) {
        if isHost {
            switch msg {
            case .hello(let name):
                names[peer] = name
                jam?.members.append(name)
                broadcast()
            case .add(let e):
                if jam?.entries.contains(where: { $0.id == e.id }) == false { jam?.entries.append(e) }
                broadcast()
            case .remove(let id):
                let who = names[peer]
                jam?.entries.removeAll { $0.id == id && $0.by == who }
                broadcast()
            case .state, .ended:
                break
            }
        } else {
            switch msg {
            case .state(let s):
                guard !joinedViaV2 else { break }
                jam = s
                if phase == .searching {
                    stallTask?.cancel()
                    browser?.stopBrowsingForPeers()
                    guest2?.stop()
                    guest2 = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                phase = .joined
            case .ended:
                let host = jam?.host ?? L("El anfitrión")
                disconnect()
                phase = .lost(L("{0} ha terminado el Jam.", host))
            case .hello, .add, .remove:
                break
            }
        }
    }

    fileprivate func peer(_ peer: MCPeerID, changed state: MCSessionState) {
        switch state {
        case .connected:
            if !isHost { send(.hello(name: myName), to: [peer]) }
        case .notConnected:
            if isHost {
                // Se quita una sola aparición: dos personas pueden llamarse igual.
                if let name = names.removeValue(forKey: peer), let i = jam?.members.lastIndex(of: name), i > 0 {
                    jam?.members.remove(at: i)
                    broadcast()
                }
            } else if phase == .joined {
                let host = jam?.host ?? L("el anfitrión")
                disconnect()
                phase = .lost(L("Se perdió la conexión con {0}.", host))
            } else if phase == .searching {
                // La invitación falló (p. ej. se rechazó por timeout): se vuelve a buscar.
                browser?.stopBrowsingForPeers()
                browser?.startBrowsingForPeers()
            }
        default:
            break
        }
    }

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        guard phase == .searching, let code = joiningCode, info?["code"] == code,
              let session, session.connectedPeers.isEmpty else { return }
        browser?.invitePeer(peer, to: session, withContext: Data(code.utf8), timeout: 20)
    }

    fileprivate func shouldAccept(context: Data?) -> MCSession? {
        guard isHost, let jam, let context, String(decoding: context, as: UTF8.self) == jam.code,
              let session, session.connectedPeers.count < Self.maxPeople - 1 else { return nil }
        return session
    }
}

// MARK: Delegados (llegan en hilos de fondo: todo se pasa al hilo principal)
extension JamService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            guard session === self.session else { return }
            self.peer(peerID, changed: state)
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? JSONDecoder().decode(JamMessage.self, from: data) else { return }
        Task { @MainActor in
            guard session === self.session else { return }
            self.received(msg, from: peerID)
        }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}

extension JamService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            let session = self.shouldAccept(context: context)
            invitationHandler(session != nil, session)
        }
    }
}

extension JamService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in self.found(peerID, info: info) }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

// MARK: - Código QR
enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Escáner de QR
struct QRScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.onCode = onCode
        return c
    }
    func updateUIViewController(_ c: ScannerController, context: Context) { c.onCode = onCode }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let capture = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              capture.canAddInput(input) else { return }
        capture.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard capture.canAddOutput(output) else { return }
        capture.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: capture)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let s = capture
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let s = capture
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
              let code = JamService.code(from: text) else { return }
        JamService.DirectHints.shared.remember(text)
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(code)
    }
}

/// «Cada uno en su móvil» (v2.1, 2.6 de x.1.1). El anfitrión cuenta lo que suena (al cambiar de canción o de pausa y
/// cada 5 s, así un salto llega enseguida); cada invitado lo sigue con **su propio audio** y cada 2 s compara dónde va
/// con dónde debería ir: más de 250 ms, salta; entre 60 y 250 ms, acelera o frena un 3 % hasta alcanzarlo. Nunca se
/// transmite sonido. Igual que `JamPlaybackSync` en Android.
struct JamPlaybackSync: ViewModifier {
    @EnvironmentObject var jam: JamService
    @EnvironmentObject var player: Player

    private var hosting: Bool { jam.isHost && jam.jam?.everyone == true }
    private var following: Bool { jam.phase == .joined && !jam.isHost && jam.jam?.everyone == true && jam.listenHere }

    func body(content: Content) -> some View {
        content
            .task(id: "\(hosting)-\(player.current?.id ?? "")-\(player.isPlaying)") {
                guard hosting else { return }
                while !Task.isCancelled {
                    jam.hostPlayback(song: player.current, positionMs: Self.ms(player.livePosition) ?? Int64(player.progress * 1000), playing: player.isPlaying)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
            .task(id: "\(following)-\(jam.remotePlay?.song?.id ?? "")-\(jam.remotePlay?.atMs ?? 0)-\(jam.remotePlay?.playing ?? false)") {
                guard following, let r = jam.remotePlay else { player.nudge(1); return }
                guard let song = r.song else { player.pause(); return }
                if player.current?.id != song.id { player.play(song, in: [song]) }
                let position = r.positionMs ?? 0, at = r.atMs ?? JamSync.now()
                guard r.playing == true else {
                    player.pause()
                    player.seek(to: Double(position) / 1000)
                    return
                }
                while !Task.isCancelled {
                    if !player.isPlaying { player.resume() }
                    // Mientras carga, la posición no es un número: corregir ahí haría saltar una y otra vez.
                    if let actual = Self.ms(player.livePosition) {
                        let expected = JamSync.expected(positionMs: position, atMs: at, playing: true, localNow: JamSync.now(), offset: jam.clockOffset ?? 0)
                        switch JamSync.correct(expected: expected, actual: actual) {
                        case .seek(let to): player.nudge(1); player.seek(to: Double(to) / 1000)
                        case .speed(let f): player.nudge(f)
                        case .none: player.nudge(1)
                        }
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
    }

    private static func ms(_ seconds: Double) -> Int64? { seconds.isFinite ? Int64(seconds * 1000) : nil }
}
