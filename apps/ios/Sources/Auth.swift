import Foundation
import Security
import CryptoKit
import WebKit

// MARK: - Llavero
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "LibreMusic",
         kSecAttrAccount as String: key]
    }
    static func set(_ value: String, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        var add = query(key)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}

// MARK: - Cabeceras autenticadas (cookies + SAPISIDHASH)
enum Auth {
    static let key = "yt_cookie_header"
    static let webUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static var cookieHeader: String? { Keychain.get(key) }

    private static func parse(_ header: String) -> [String: String] {
        var d: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let p = pair.trimmingCharacters(in: .whitespaces)
            guard let eq = p.firstIndex(of: "=") else { continue }
            d[String(p[..<eq])] = String(p[p.index(after: eq)...])
        }
        return d
    }

    static func hasValidCookie(_ header: String) -> Bool {
        let d = parse(header)
        return d["SAPISID"] != nil || d["__Secure-3PAPISID"] != nil
    }

    static func headers() -> [String: String]? {
        guard let cookie = cookieHeader else { return nil }
        let d = parse(cookie)
        guard let sapisid = d["SAPISID"] ?? d["__Secure-3PAPISID"] else { return nil }
        let origin = "https://music.youtube.com"
        let ts = Int(Date().timeIntervalSince1970)
        let digest = Insecure.SHA1.hash(data: Data("\(ts) \(sapisid) \(origin)".utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return ["Cookie": cookie,
                "Authorization": "SAPISIDHASH \(ts)_\(hash)",
                "X-Origin": origin,
                "Origin": origin,
                "X-Goog-AuthUser": "0",
                "User-Agent": webUA]
    }
}

// MARK: - Estado de la sesión de YouTube Music (no es la cuenta de Pear Music, que está en Account.swift)
@MainActor
final class YTAccount: ObservableObject {
    @Published private(set) var isLoggedIn = false

    init() {
        if let c = Auth.cookieHeader, Auth.hasValidCookie(c) { isLoggedIn = true }
    }

    func signIn(cookies: [HTTPCookie]) {
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        save(header)
    }

    /// Alternativa manual: pegar la cabecera "Cookie" copiada del navegador.
    @discardableResult
    func signIn(rawCookie: String) -> Bool {
        var h = rawCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.lowercased().hasPrefix("cookie:") { h = String(h.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        guard Auth.hasValidCookie(h) else { return false }
        save(h)
        return true
    }

    private func save(_ header: String) {
        guard Auth.hasValidCookie(header) else { return }
        Keychain.set(header, for: Auth.key)
        isLoggedIn = true
    }

    func signOut() {
        Keychain.delete(Auth.key)
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: .distantPast) {}
        isLoggedIn = false
    }
}
