import Foundation
import CryptoKit
import Security
import WebKit

// MARK: - Canal (Fase 1 de la 2.0)
/// Tres apps con el mismo código, como los flavors de Android (ver docs/FLAVORS.md). El canal sale de la
/// configuración de compilación (`Config/*.xcconfig` → `SWIFT_ACTIVE_COMPILATION_CONDITIONS`):
/// - usr: la pública. - pref: la de Toxbox, sin herramientas de administración. - dev: pruebas y administración.
enum Channel {
    #if CHANNEL_DEV
    static let current = "dev"
    static let adminTools = true
    static let verboseLogs = true
    #elseif CHANNEL_PREF
    static let current = "pref"
    static let adminTools = false
    static let verboseLogs = false
    #else
    static let current = "usr"
    static let adminTools = false
    static let verboseLogs = false
    #endif
}

// MARK: - Registro
/// Igual que `Logs` en Android: nunca datos personales; en dev, las últimas líneas en memoria para
/// Ajustes › Ayuda y soporte › Administración. En usr y pref no se guarda nada.
enum Logs {
    private static let capacity = 300
    private static let lock = NSLock()
    private static var lines: [String] = []

    static func d(_ tag: String, _ msg: String) { keep("D", tag, msg) }
    static func w(_ tag: String, _ msg: String) { keep("W", tag, msg) }
    static func e(_ tag: String, _ msg: String) { keep("E", tag, msg) }

    static var recent: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    static func clear() { lock.lock(); lines.removeAll(); lock.unlock() }

    private static func keep(_ level: String, _ tag: String, _ msg: String) {
        guard Channel.verboseLogs else { return }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "\(f.string(from: Date())) \(level)/\(tag): \(msg)"
        lock.lock()
        if lines.count == capacity { lines.removeFirst() }
        lines.append(line)
        lock.unlock()
    }
}

// MARK: - Tus datos (RGPD)
/// Exportar y borrar todo lo que la app guarda. Igual que `UserData` en Android: sin cuentas ni servidor
/// propio, todo vive en el móvil. Cuando haya telemetría, su identificador y su consentimiento entran aquí.
enum UserData {
    /// Lo que no se exporta: el audio descargado (es de YouTube, no un dato tuyo, y pesa gigas).
    private static let skip: Set<String> = ["Downloads"]

    /// Prepara un .zip en una carpeta temporal con la biblioteca, estadísticas, letras, portadas, borradores
    /// de soporte y los ajustes. Devuelve su URL para compartirlo o guardarlo en Archivos.
    static func export() throws -> URL {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let folder = fm.temporaryDirectory.appendingPathComponent("pear-music-datos-\(stamp)")
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder.appendingPathComponent("app"), withIntermediateDirectories: true)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for item in (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? [] where !skip.contains(item.lastPathComponent) {
            try fm.copyItem(at: item, to: folder.appendingPathComponent("app").appendingPathComponent(item.lastPathComponent))
        }
        if let id = Bundle.main.bundleIdentifier, let prefs = UserDefaults.standard.persistentDomain(forName: id) {
            let data = try PropertyListSerialization.data(fromPropertyList: prefs.filter { $0.value is NSSecureCoding }, format: .xml, options: 0)
            try data.write(to: folder.appendingPathComponent("ajustes.plist"))
        }
        try readme.write(to: folder.appendingPathComponent("LEEME.txt"), atomically: true, encoding: .utf8)
        // El sistema comprime una carpeta a .zip al pedirla «para subir»; así no hace falta otra librería.
        var zip: URL?
        var failure: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordError) { tmp in
            let out = fm.temporaryDirectory.appendingPathComponent(folder.lastPathComponent + ".zip")
            try? fm.removeItem(at: out)
            do { try fm.copyItem(at: tmp, to: out); zip = out } catch { failure = error }
        }
        try? fm.removeItem(at: folder)
        if let e = coordError ?? failure { throw e }
        guard let zip else { throw CocoaError(.fileWriteUnknown) }
        return zip
    }

    /// Borra todos los datos de la app (archivos, ajustes, llavero y datos web) y la cierra, como «Borrar
    /// almacenamiento» en Android. iOS no deja borrar una app desde dentro, así que se vacía y se sale.
    static func eraseAll() {
        // Primero lo que hay fuera del móvil (telemetría de esta instalación), con 3 s de límite; luego lo local.
        Task { @MainActor in
            await Telemetry.shared.deleteRemoteNow()
            eraseLocal()
        }
    }

    private static func eraseLocal() {
        let fm = FileManager.default
        for dir in [FileManager.SearchPathDirectory.documentDirectory, .cachesDirectory, .applicationSupportDirectory] {
            guard let root = fm.urls(for: dir, in: .userDomainMask).first else { continue }
            for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: item)
            }
        }
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        Keychain.delete(Auth.key)
        SecureBox.erase()
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            exit(0)
        }
    }

    private static let readme = """
    Datos de Pear Music en este iPhone.

    app/library.json      Biblioteca: playlists, canciones guardadas y álbumes (formato de docs/LIBRARY_FORMAT.md).
    app/stats.json        Estadísticas de escucha (sólo existen en el móvil).
    app/lyrics/, covers/  Letras guardadas y fotos de tus playlists.
    app/support/          Borradores de «Informar de un error» (con tu correo, si lo escribiste).
    ajustes.plist         Ajustes de la app (tema, reproductor, avisos leídos, nombre en el Jam…).

    Pear Music no tiene cuentas ni guarda estos datos en ningún servidor.
    """
}

// MARK: - Caja cifrada
/// AES-256-GCM (CryptoKit) con una clave aleatoria guardada en el llavero sólo para este iPhone
/// (`AfterFirstUnlockThisDeviceOnly`: no viaja a copias de iCloud ni a otro iPhone). Cifra lo sensible que se
/// guarda en disco: borradores de soporte y, desde la 2.0, las credenciales de la cuenta. Mismo formato que
/// `SecureBox` en Android: `[1][nonce 12][cifrado][etiqueta 16]`.
enum SecureBox {
    private static let account = "secure_box_v1"
    private static let version: UInt8 = 1

    private static func key() throws -> SymmetricKey {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "PearMusic.SecureBox",
                                kSecAttrAccount as String: account]
        var read = q
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        if SecItemCopyMatching(read as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
            return SymmetricKey(data: data)
        }
        let fresh = SymmetricKey(size: .bits256)
        var add = q
        add[kSecValueData as String] = fresh.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw CocoaError(.fileWriteNoPermission) }
        return fresh
    }

    static func seal(_ plain: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key()).combined else { throw CocoaError(.coderInvalidValue) }
        return Data([version]) + combined
    }

    static func open(_ sealed: Data) throws -> Data {
        guard sealed.count > 29, sealed.first == version else { throw CocoaError(.coderReadCorrupt) }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed.dropFirst()), using: key())
    }

    /// Para «Borrar todos mis datos».
    static func erase() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: "PearMusic.SecureBox"] as CFDictionary)
    }
}
