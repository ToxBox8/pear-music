import Foundation
import Network

// MARK: - Jam v2: protocolo abierto compatible con Android
// Especificación: docs/JAM_PROTOCOL.md. Bonjour `_lm-jam2._tcp` (TXT: v, code, host) + TCP con
// un mensaje JSON por línea. Convive con el Jam v1 (MultipeerConnectivity) de JamService:
// el anfitrión anuncia los dos y el invitado busca en los dos a la vez.

/// Un mensaje v2 tal y como viaja por la red (los campos que no aplican se omiten).
struct JamWire: Codable {
    var v = 2
    var type: String
    var name: String? = nil
    var code: String? = nil
    var state: JamState? = nil
    var entry: JamEntry? = nil
    var songID: String? = nil
    var reason: String? = nil
}

enum JamV2 {
    static let serviceType = "_lm-jam2._tcp"
    static let maxPeople = 16
    /// Topes contra abusos desde la red local (mismos que `JamRules` en Android).
    static let maxConnections = 24
    static let maxLineBytes = 256 * 1024
    static let maxEntries = 500
    static let maxText = 300

    /// Una canción con datos razonables (un invitado malicioso podría mandar textos enormes).
    static func acceptable(_ e: JamEntry) -> Bool {
        !e.song.id.isEmpty && e.song.id.count <= 64 && e.song.title.count <= maxText && e.song.artist.count <= maxText
            && e.by.count <= maxText
    }
}

/// Una conexión TCP con entramado por líneas (`\n`). Todo ocurre en la cola que se le pasa.
final class JamLine {
    let id = UUID()
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onMessage: ((JamWire) -> Void)?
    var onClose: (() -> Void)?
    private var buffer = Data()
    private var closed = false

    init(_ connection: NWConnection) { self.connection = connection }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onReady?()
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain()
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.receive()
        }
    }

    private func drain() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            // Las líneas desconocidas o de versiones futuras se ignoran.
            if let msg = try? JSONDecoder().decode(JamWire.self, from: line) { onMessage?(msg) }
        }
        // Una línea sin fin (alguien de la red mandando basura) llenaría la memoria: se corta la conexión.
        if buffer.count > JamV2.maxLineBytes { close() }
    }

    func send(_ msg: JamWire) {
        guard !closed, var data = try? JSONEncoder().encode(msg) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?()
    }
}

/// Anfitrión v2: anuncia el Jam por Bonjour y acepta invitados por TCP.
final class JamHostV2 {
    private let queue = DispatchQueue(label: "app.libremusic.jam.v2.host")
    private var listener: NWListener?
    private var peers: [UUID: JamLine] = [:]
    var onMessage: ((UUID, JamWire) -> Void)?
    var onClose: ((UUID) -> Void)?

    init?(name: String, code: String, host: String) {
        guard let listener = try? NWListener(using: .tcp) else { return nil }
        let txt = NWTXTRecord(["v": "2", "code": code, "host": String(host.prefix(40))])
        listener.service = NWListener.Service(name: String(name.prefix(60)), type: JamV2.serviceType, domain: nil, txtRecord: txt)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        // Tope de conexiones abiertas: más gente que el máximo del Jam sólo puede ser alguien abusando de la red.
        guard peers.count < JamV2.maxConnections else { connection.cancel(); return }
        let line = JamLine(connection)
        let id = line.id
        peers[id] = line
        line.onMessage = { [weak self] msg in self?.onMessage?(id, msg) }
        line.onClose = { [weak self] in
            self?.peers[id] = nil
            self?.onClose?(id)
        }
        line.start(queue: queue)
        // Quien no se presenta con el código en 15 s, fuera.
        queue.asyncAfter(deadline: .now() + 15) { [weak self] in
            if self?.peers[id] != nil, self?.greeted.contains(id) == false { self?.drop(id) }
        }
    }

    /// Conexiones que ya se han presentado con el código bueno (sólo se toca en `queue`).
    private var greeted = Set<UUID>()
    func markGreeted(_ id: UUID) { queue.async { self.greeted.insert(id) } }

    func send(_ msg: JamWire, to id: UUID) {
        queue.async { self.peers[id]?.send(msg) }
    }

    func broadcast(_ msg: JamWire, to ids: Set<UUID>) {
        queue.async {
            for (id, peer) in self.peers where ids.contains(id) { peer.send(msg) }
        }
    }

    func drop(_ id: UUID) {
        queue.async { self.peers[id]?.close() }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            let all = Array(self.peers.values)
            self.peers = [:]
            all.forEach { $0.onClose = nil; $0.close() }
        }
    }
}

/// Invitado v2: busca el Jam con el código en el TXT y se conecta al anfitrión.
final class JamGuestV2 {
    private let queue = DispatchQueue(label: "app.libremusic.jam.v2.guest")
    private var browser: NWBrowser?
    private var line: JamLine?
    var onMessage: ((JamWire) -> Void)?
    var onClose: (() -> Void)?

    init(code: String, name: String) {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: JamV2.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.line == nil else { return }
            for result in results {
                if case .bonjour(let txt) = result.metadata, txt["code"] == code {
                    self.connect(to: result.endpoint, code: code, name: name)
                    break
                }
            }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    private func connect(to endpoint: NWEndpoint, code: String, name: String) {
        browser?.cancel()
        browser = nil
        let line = JamLine(NWConnection(to: endpoint, using: .tcp))
        self.line = line
        line.onReady = { [weak line] in line?.send(JamWire(type: "hello", name: name, code: code)) }
        line.onMessage = { [weak self] msg in self?.onMessage?(msg) }
        line.onClose = { [weak self] in self?.onClose?() }
        line.start(queue: queue)
    }

    func send(_ msg: JamWire) {
        queue.async { self.line?.send(msg) }
    }

    func stop() {
        queue.async {
            self.browser?.cancel()
            self.browser = nil
            let line = self.line
            self.line = nil
            line?.onClose = nil
            line?.close()
        }
    }
}
