import CryptoKit
import Foundation

/// Alfabeto Crockford de la clave de recuperación (sin I, L, O ni U), igual que en Android.
private let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

/// Cuenta opcional (Fase 2.1, ADR 0001), igual que `Account` en Android: código al correo y biblioteca guardada en la
/// nube **cifrada en el iPhone** con la clave de recuperación (128 bits aleatorios, 26 caracteres) que sólo tiene el
/// usuario. Sesión y clave, cifradas con `SecureBox` en `Application Support/account`.
@MainActor
final class Account: ObservableObject {
    static let shared = Account()
    static let base = URL(string: "https://pear-music-api.8toxbox8-69a.workers.dev/v1/cuenta")!

    struct State: Equatable {
        var email: String?
        var hasKey = false
        var lastSync: Date?
        var version = 0
        var cloudHasLibrary = false
    }

    @Published private(set) var state = State()
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("account")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private init() { state = load() }

    // MARK: Guardado local cifrado
    private func read(_ name: String) -> String? {
        guard let raw = try? Data(contentsOf: dir.appendingPathComponent(name)), let plain = try? SecureBox.open(raw) else { return nil }
        return String(decoding: plain, as: UTF8.self)
    }
    private func write(_ name: String, _ value: String?) {
        let url = dir.appendingPathComponent(name)
        guard let value else { try? FileManager.default.removeItem(at: url); return }
        // Sin llavero no se guarda (nunca en claro): la sesión dura hasta cerrar la app, como en Android.
        if let sealed = try? SecureBox.seal(Data(value.utf8)) { try? sealed.write(to: url, options: [.atomic, .completeFileProtection]) }
        else { Logs.w("Account", "No se pudo guardar cifrado") }
    }
    private func load() -> State {
        let meta = read("meta").flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
        let last = (meta["lastSync"] as? Double).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return State(email: meta["email"] as? String, hasKey: read("key") != nil, lastSync: last,
                     version: meta["version"] as? Int ?? 0, cloudHasLibrary: meta["cloud"] as? Bool ?? false)
    }
    private func saveMeta(_ s: State) {
        let meta: [String: Any] = ["email": s.email ?? "", "lastSync": s.lastSync?.timeIntervalSince1970 ?? 0, "version": s.version, "cloud": s.cloudHasLibrary]
        if let data = try? JSONSerialization.data(withJSONObject: meta) { write("meta", String(decoding: data, as: UTF8.self)) }
        var copy = s
        copy.hasKey = read("key") != nil
        state = copy
    }
    private var token: String? { read("token") }

    // MARK: Clave de recuperación y cifrado

    nonisolated static func newRecoveryKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        var bits = 0, value = 0, out = ""
        for b in bytes {
            value = (value << 8) | Int(b); bits += 8
            while bits >= 5 { out.append(alphabet[(value >> (bits - 5)) & 31]); bits -= 5 }
            value &= (1 << bits) - 1
        }
        if bits > 0 { out.append(alphabet[(value << (5 - bits)) & 31]) }
        return stride(from: 0, to: out.count, by: 4).map { i in
            String(out[out.index(out.startIndex, offsetBy: i)..<out.index(out.startIndex, offsetBy: min(i + 4, out.count))])
        }.joined(separator: "-")
    }

    nonisolated static func normalizeKey(_ raw: String) -> String? {
        let k = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
            .replacingOccurrences(of: "O", with: "0").replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "L", with: "1")
        guard k.count == 26, k.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return stride(from: 0, to: 26, by: 4).map { i in
            String(k[k.index(k.startIndex, offsetBy: i)..<k.index(k.startIndex, offsetBy: min(i + 4, 26))])
        }.joined(separator: "-")
    }

    private nonisolated static func aesKey(_ recovery: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data("pear-music-library-v1:\(recovery.replacingOccurrences(of: "-", with: ""))".utf8)))
    }

    /// Mismo formato que Android: base64 de `[1][nonce 12][cifrado][etiqueta 16]`.
    nonisolated static func encrypt(_ plain: Data, recovery: String) throws -> String {
        guard let combined = try AES.GCM.seal(plain, using: aesKey(recovery)).combined else { throw CocoaError(.coderInvalidValue) }
        return (Data([1]) + combined).base64EncodedString()
    }

    nonisolated static func decrypt(_ blob: String, recovery: String) throws -> Data {
        guard let bytes = Data(base64Encoded: blob), bytes.count > 29, bytes.first == 1 else { throw CocoaError(.coderReadCorrupt) }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: bytes.dropFirst()), using: aesKey(recovery))
    }

    // MARK: Servidor
    struct APIError: LocalizedError { let message: String; var errorDescription: String? { message } }

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil, auth: Bool = false) async throws -> (Int, [String: Any]) {
        if Incident.restricted { throw APIError(message: L("La cuenta está en pausa mientras resolvemos un incidente.")) }
        var r = URLRequest(url: path.isEmpty ? Self.base : Self.base.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth {
            guard let token else { throw APIError(message: L("Vuelve a entrar en tu cuenta.")) }
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { r.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        do {
            let (data, response) = try await URLSession.shared.data(for: r)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
        } catch {
            throw APIError(message: L("Sin conexión. Inténtalo cuando tengas internet."))
        }
    }

    private func ok(_ r: (Int, [String: Any])) throws -> [String: Any] {
        guard (200..<300).contains(r.0) else { throw APIError(message: r.1["error"] as? String ?? L("El servidor no responde ({0}). Prueba más tarde.", r.0)) }
        return r.1
    }

    func available() async -> Bool {
        guard let r = try? await call("GET", "disponible") else { return false }
        return (try? ok(r))?["available"] as? Bool ?? false
    }

    func requestCode(_ email: String) async throws {
        _ = try ok(await call("POST", "codigo", body: ["email": email.trimmingCharacters(in: .whitespaces)]))
    }

    @discardableResult
    func signIn(_ email: String, code: String) async throws -> Bool {
        let r = try ok(await call("POST", "entrar", body: ["email": email.trimmingCharacters(in: .whitespaces), "code": code]))
        guard let t = r["token"] as? String else { throw APIError(message: L("Respuesta inesperada del servidor.")) }
        write("token", t)
        let had = r["hasLibrary"] as? Bool ?? false
        saveMeta(State(email: email.trimmingCharacters(in: .whitespaces).lowercased(), cloudHasLibrary: had))
        return had
    }

    func setRecoveryKey(_ key: String?) {
        write("key", key)
        state.hasKey = key != nil
    }
    var recoveryKey: String? { read("key") }

    /// Sube la biblioteca cifrada; con `overwrite` («empezar de cero») sustituye la copia que ya no se puede abrir.
    func upload(_ library: Library, overwrite: Bool = false) async throws {
        guard let key = recoveryKey else { throw APIError(message: L("Falta la clave de recuperación.")) }
        // Con portadas si caben en el límite de la nube (2 MB tras cifrar); si no, sin ellas. Igual que Android.
        let full = library.exportData()
        let blob = try Self.encrypt(full.count < 1_400_000 ? full : library.exportData(covers: false), recovery: key)
        var r = try await call("PUT", "biblioteca", body: ["blob": blob, "baseVersion": state.version], auth: true)
        if r.0 == 409 {
            if overwrite {
                r = try await call("PUT", "biblioteca", body: ["blob": blob, "baseVersion": r.1["version"] as? Int ?? 0], auth: true)
            } else {
                _ = try await download(library)
                let again = library.exportData()
                let merged = try Self.encrypt(again.count < 1_400_000 ? again : library.exportData(covers: false), recovery: key)
                r = try await call("PUT", "biblioteca", body: ["blob": merged, "baseVersion": state.version], auth: true)
            }
        }
        let v = try ok(r)["version"] as? Int ?? 0
        var s = state; s.version = v; s.lastSync = Date(); s.cloudHasLibrary = true
        saveMeta(s)
    }

    /// Trae la copia de la nube y la une con la del iPhone (no borra nada).
    func download(_ library: Library) async throws -> (favorites: Int, playlists: Int) {
        guard let key = recoveryKey else { throw APIError(message: L("Falta la clave de recuperación.")) }
        let r = try await call("GET", "biblioteca", auth: true)
        if r.0 == 404 { return (0, 0) }
        let j = try ok(r)
        guard let blob = j["blob"] as? String, let plain = try? Self.decrypt(blob, recovery: key) else {
            throw APIError(message: L("La clave de recuperación no es la de esta cuenta."))
        }
        let added = try library.importData(plain)
        var s = state; s.version = j["version"] as? Int ?? s.version; s.lastSync = Date()
        saveMeta(s)
        return added
    }

    func signOut() async {
        _ = try? await call("POST", "salir", auth: true)
        clearLocal()
    }

    func delete() async throws {
        _ = try ok(await call("DELETE", "", auth: true))
        clearLocal()
    }

    private func clearLocal() {
        ["token", "key", "meta"].forEach { write($0, nil) }
        state = State()
    }
}
