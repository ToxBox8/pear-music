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
    // v2.1 «cada uno en su móvil» (2.6 de x.1.1): `play` (song, positionMs, atMs, playing), `ping` (t0), `pong` (t0, th).
    var song: Song? = nil
    var positionMs: Int64? = nil
    var atMs: Int64? = nil
    var playing: Bool? = nil
    var t0: Int64? = nil
    var th: Int64? = nil
}

/// «Cada uno en su móvil» (v2.1, 2.6 de x.1.1): reloj y correcciones, sin red para poder probarlo. Igual que
/// `JamSync` en Android.
enum JamSync {
    static let speaker = "altavoz"
    static let everyone = "todos"
    /// Más de esto, salto; entre `nudgeMs` y esto, se ajusta la velocidad unos segundos (sin saltos audibles).
    static let seekMs: Int64 = 250
    static let nudgeMs: Int64 = 60
    static let faster: Float = 1.03
    static let slower: Float = 0.97
    static let firstPings = 4
    static let pingEvery: TimeInterval = 30

    struct Sample: Equatable { let rtt: Int64; let offset: Int64 }

    static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    static func sample(t0: Int64, th: Int64, t1: Int64) -> Sample { Sample(rtt: t1 - t0, offset: th - (t0 + t1) / 2) }

    /// Diferencia de reloj (hora del anfitrión − la nuestra): la media de las dos medidas más rápidas.
    static func offset(_ samples: [Sample]) -> Int64? {
        let best = samples.sorted { $0.rtt < $1.rtt }.prefix(2)
        return best.isEmpty ? nil : best.map(\.offset).reduce(0, +) / Int64(best.count)
    }

    /// Dónde debería ir la canción ahora en este móvil.
    static func expected(positionMs: Int64, atMs: Int64, playing: Bool, localNow: Int64, offset: Int64) -> Int64 {
        playing ? positionMs + (localNow + offset - atMs) : positionMs
    }

    enum Correction: Equatable { case none, seek(Int64), speed(Float) }

    static func correct(expected: Int64, actual: Int64) -> Correction {
        let drift = expected - actual
        if abs(drift) > seekMs { return .seek(expected) }
        if abs(drift) >= nudgeMs { return .speed(drift > 0 ? faster : slower) }
        return .none
    }
}

enum JamV2 {
    static let serviceType = "_lm-jam2._tcp"

    /// La IPv4 privada del iPhone en la Wi-Fi (en0), o nil.
    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var fallback: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            let name = String(cString: ifa.ifa_name)
            guard ip.hasPrefix("10.") || ip.hasPrefix("192.168.") || isPrivate172(ip) else { continue }
            if name == "en0" { return ip }
            fallback = fallback ?? ip
        }
        return fallback
    }

    private static func isPrivate172(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        return p.count == 4 && p[0] == 172 && (16...31).contains(p[1])
    }
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

    /// Dirección del anfitrión en la Wi-Fi («IP:puerto») para el QR, cuando el puerto está listo (Fase 3.2).
    var onDirect: ((String) -> Void)?

    init?(name: String, code: String, host: String) {
        guard let listener = try? NWListener(using: .tcp) else { return nil }
        let txt = NWTXTRecord(["v": "2", "code": code, "host": String(host.prefix(40))])
        // El código en el nombre: los invitados Android resuelven primero el que coincide (Fase 3.2).
        listener.service = NWListener.Service(name: "\(name.prefix(48)) · \(code)", type: JamV2.serviceType, domain: nil, txtRecord: txt)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard case .ready = state, let port = listener?.port?.rawValue, let ip = JamV2.localIPv4() else { return }
            self?.onDirect?("\(ip):\(port)")
        }
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

    private var started = Date()
    private var direct: JamLine?
    /// Conexiones de la búsqueda aún sin decidir (retenidas hasta que una gana).
    private var pending: [JamLine] = []

    /// `direct` («IP», puerto) del QR: se prueba a la vez que la búsqueda Bonjour y gana el primero (Fase 3.2).
    init(code: String, name: String, direct: (String, UInt16)? = nil) {
        if let (ip, port) = direct, let p = NWEndpoint.Port(rawValue: port) {
            let quick = JamLine(NWConnection(host: NWEndpoint.Host(ip), port: p, using: .tcp))
            self.direct = quick
            quick.onReady = { [weak self, weak quick] in
                guard let self, let quick, self.line == nil else { quick?.close(); return }
                self.adopt(quick, code: code, name: name, via: "directo")
            }
            quick.start(queue: queue)
            // Si en 2 s no ha conectado, se abandona: la búsqueda sigue por su lado.
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                if let self, self.line == nil { self.direct?.close(); self.direct = nil }
            }
        }
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
        let found = JamLine(NWConnection(to: endpoint, using: .tcp))
        pending.append(found)
        found.onReady = { [weak self, weak found] in
            guard let self, let found, self.line == nil else { found?.close(); return }
            self.adopt(found, code: code, name: name, via: "wifi")
        }
        found.start(queue: queue)
    }

    /// El primer camino que conecta se queda la conexión; se paran la búsqueda y el otro intento.
    private func adopt(_ winner: JamLine, code: String, name: String, via: String) {
        line = winner
        browser?.cancel()
        browser = nil
        if direct !== winner { direct?.close() }
        direct = nil
        pending.filter { $0 !== winner }.forEach { $0.close() }
        pending = []
        Logs.d("LMJam", "join_ms=\(Int(Date().timeIntervalSince(started) * 1000)) via=\(via)")
        winner.onMessage = { [weak self] msg in self?.onMessage?(msg) }
        winner.onClose = { [weak self] in self?.onClose?() }
        winner.send(JamWire(type: "hello", name: name, code: code))
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
