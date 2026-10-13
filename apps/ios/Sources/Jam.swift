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

    static func link(_ code: String) -> String { "libremusic://jam/\(code)" }

    func handle(url: URL) {
        guard let c = Self.code(from: url.absoluteString) else { return }
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
        let g = JamGuestV2(code: code, name: myName)
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
            joinedViaV2 = true
            jam = s
            phase = .joined
        case "ended":
            let host = jam?.host ?? "El anfitrión"
            disconnect()
            phase = .lost("\(host) ha terminado el Jam.")
        case "error":
            disconnect()
            phase = .lost(msg.reason == "full" ? "El Jam está lleno." : "El código no es válido.")
        default:
            break
        }
    }

    private func hostClosed2() {
        guard joinedViaV2, phase == .joined else { return }
        let host = jam?.host ?? "el anfitrión"
        disconnect()
        phase = .lost("Se perdió la conexión con \(host).")
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
                let host = jam?.host ?? "El anfitrión"
                disconnect()
                phase = .lost("\(host) ha terminado el Jam.")
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
                let host = jam?.host ?? "el anfitrión"
                disconnect()
                phase = .lost("Se perdió la conexión con \(host).")
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
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(code)
    }
}
