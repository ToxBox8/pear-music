// Cuenta Jiyu Pulse 3.0: la criptografía y los formatos de docs/spec/cuenta.md, byte a byte (2-C paso 3).
// Sólo Foundation y CryptoKit, sin nada de la interfaz ni del Llavero: así lo prueban en Linux, con swift-crypto
// (la misma API), los vectores de shared/spec/vectores (tools/spec/swift, objetivo CuentaApp). El Secure Enclave y el
// Llavero están en CuentaPear.swift.
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

enum CuentaCripto {
    struct Fallo: Error, Equatable { let codigo: String }

    // MARK: base64url sin relleno y estricto (cuenta.md §1)

    static func b64u(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    private static let alfabetoB64 = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".unicodeScalars)
    static func deB64u(_ s: String) throws -> Data {
        guard s.unicodeScalars.allSatisfy({ alfabetoB64.contains($0) }), s.count % 4 != 1 else { throw Fallo(codigo: "base64url") }
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        guard let d = Data(base64Encoded: t), b64u(d) == s else { throw Fallo(codigo: "base64url") }
        return d
    }
    static func utf8(_ s: String) -> Data { Data(s.utf8) }
    static func sha256(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }
    static func aleatorio(_ n: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<n).map { _ in UInt8.random(in: 0...255, using: &g) })
    }

    // MARK: Crockford base32: ids y clave de recuperación C (cuenta.md §1 y §3)

    static let alfabeto = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func base32(_ d: Data) -> String {
        var bits = 0, valor = 0, out = ""
        for b in d {
            valor = (valor << 8) | Int(b); bits += 8
            while bits >= 5 { out.append(alfabeto[(valor >> (bits - 5)) & 31]); bits -= 5 }
            valor &= (1 << bits) - 1
        }
        if bits > 0 { out.append(alfabeto[(valor << (5 - bits)) & 31]) }
        return out
    }

    /// XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XX.
    static func mostrarClave(_ c26: String) -> String {
        stride(from: 0, to: c26.count, by: 4).map { i in
            String(c26[c26.index(c26.startIndex, offsetBy: i)..<c26.index(c26.startIndex, offsetBy: min(i + 4, c26.count))])
        }.joined(separator: "-")
    }

    /// Los seis grupos de 4 que se pueden pedir para confirmar (§3): 1…6, sin el último de 2.
    static func grupo(_ c26: String, _ n: Int) -> String {
        let i = c26.index(c26.startIndex, offsetBy: (n - 1) * 4)
        return String(c26[i..<c26.index(i, offsetBy: 4)])
    }

    /// Un grupo de 4 escrito para confirmar (§3), normalizado igual que la clave entera.
    static func normalizarGrupo(_ texto: String) -> String {
        var limpio = String.UnicodeScalarView()
        for u in texto.unicodeScalars where !quitarClave.contains(u.value) {
            limpio.append((0x61...0x7a).contains(u.value) ? Unicode.Scalar(u.value - 32)! : u)
        }
        return String(limpio).replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "L", with: "1")
    }

    /// Lo que se quita al leer (§3): lista explícita, `isWhitespace` de Swift no es lo mismo que en JS o Kotlin.
    static let quitarClave: Set<UInt32> = [
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0x85, 0xa0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
        0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0x200b, 0xfeff,
        0x2d, 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212,
    ]

    /// Lo que escribe el usuario → los 26 caracteres normalizados, o nil («Esa clave no es válida», sin red).
    static func normalizarClave(_ texto: String) -> String? {
        var limpio = String.UnicodeScalarView()
        for u in texto.unicodeScalars where !quitarClave.contains(u.value) {
            limpio.append((0x61...0x7a).contains(u.value) ? Unicode.Scalar(u.value - 32)! : u)
        }
        let k = String(limpio).replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "L", with: "1")
        return leerClave(k) == nil ? nil : k
    }

    /// Lo que escribe el usuario → 16 bytes, o nil.
    static func leerClave(_ texto: String) -> Data? {
        var limpio = String.UnicodeScalarView()
        for u in texto.unicodeScalars where !quitarClave.contains(u.value) {
            limpio.append((0x61...0x7a).contains(u.value) ? Unicode.Scalar(u.value - 32)! : u)
        }
        let k = String(limpio).replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "L", with: "1")
        guard k.unicodeScalars.count == 26, k.allSatisfy({ alfabeto.contains($0) }) else { return nil }
        var bits = 0, valor = 0, out = Data()
        for c in k {
            valor = (valor << 5) | alfabeto.firstIndex(of: c)!; bits += 5
            if bits >= 8 { out.append(UInt8((valor >> (bits - 8)) & 255)); bits -= 8; valor &= (1 << bits) - 1 }
        }
        return bits == 2 && valor == 0 ? out : nil
    }

    /// Un id de la spec: 26 caracteres del alfabeto y los 2 bits de relleno del último a cero.
    static func esId(_ s: String) -> Bool {
        s.unicodeScalars.count == 26 && s.allSatisfy({ alfabeto.contains($0) }) && (alfabeto.firstIndex(of: s.last!)! & 3) == 0
    }

    // MARK: Claves (cuenta.md §2)

    static let salt = utf8("pear-id/v1")
    static func hkdf(_ ikm: Data, info: String, salt: Data = CuentaCripto.salt, largo: Int = 32) -> Data {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: utf8(info), outputByteCount: largo)
            .withUnsafeBytes { Data($0) }
    }

    struct DeR { let kMusic: Data; let semillaCuenta: Data; let pubCuenta: Data }
    struct DeC { let kekRec: Data; let l: Data; let hashL: Data; let semillaRec: Data; let pubRec: Data }

    static func derivarDeR(_ r: Data) throws -> DeR {
        guard r.count == 32 else { throw Fallo(codigo: "R") }
        let semilla = hkdf(r, info: "pear/account/sign/v1")
        return DeR(kMusic: hkdf(r, info: "pear/app/music/data/v1"), semillaCuenta: semilla, pubCuenta: try edPub(semilla))
    }
    static func derivarDeC(_ c: Data) throws -> DeC {
        guard c.count == 16 else { throw Fallo(codigo: "C") }
        let l = hkdf(c, info: "pear/recovery/lookup/v1")
        let semilla = hkdf(c, info: "pear/recovery/sign/v1")
        return DeC(kekRec: hkdf(c, info: "pear/recovery/wrap/v1"), l: l, hashL: sha256(l), semillaRec: semilla, pubRec: try edPub(semilla))
    }

    /// device_id = base32(SHA-256(pub_disp)[0..16]) (§1).
    static func idDispositivo(_ pubDisp: Data) -> String { base32(sha256(pubDisp).prefix(16)) }

    // MARK: Ed25519 y P-256

    static func edPub(_ semilla: Data) throws -> Data { try Curve25519.Signing.PrivateKey(rawRepresentation: semilla).publicKey.rawRepresentation }
    static func edFirmar(_ semilla: Data, _ m: Data) throws -> Data { try Curve25519.Signing.PrivateKey(rawRepresentation: semilla).signature(for: m) }
    static func edVerificar(_ pub: Data, _ m: Data, _ firma: Data) -> Bool {
        guard pub.count == 32, firma.count == 64, let k = try? Curve25519.Signing.PublicKey(rawRepresentation: pub) else { return false }
        return k.isValidSignature(firma, for: m)
    }
    /// pub = 0x04‖X‖Y (x963Representation); firma = r‖s (rawRepresentation, la que da el Secure Enclave).
    static func p256Verificar(_ pub: Data, _ m: Data, _ firma: Data) -> Bool {
        guard pub.count == 65, pub.first == 4, firma.count == 64,
              let k = try? P256.Signing.PublicKey(x963Representation: pub),
              let f = try? P256.Signing.ECDSASignature(rawRepresentation: firma) else { return false }
        return k.isValidSignature(f, for: m)
    }

    // MARK: AES-256-GCM y la envoltura de recuperación (§4.1)

    static func sellar(_ clave: Data, _ nonce: Data, _ datos: Data, _ aad: Data) throws -> Data {
        let s = try AES.GCM.seal(datos, using: SymmetricKey(data: clave), nonce: AES.GCM.Nonce(data: nonce), authenticating: aad)
        return s.ciphertext + s.tag
    }
    static func abrir(_ clave: Data, _ nonce: Data, _ ct: Data, _ aad: Data) throws -> Data {
        guard ct.count >= 16 else { throw Fallo(codigo: "corto") }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ct.dropLast(16), tag: ct.suffix(16))
        return try AES.GCM.open(box, using: SymmetricKey(data: clave), authenticating: aad)
    }

    static func envolver(_ kek: Data, _ r: Data, cuenta: String, nonce: Data = aleatorio(12)) throws -> String {
        let ct = try sellar(kek, nonce, r, utf8("pear-wrap/v1|\(cuenta)|recovery"))
        return "{\"v\":1,\"tipo\":\"recovery\",\"nonce\":\"\(b64u(nonce))\",\"ct\":\"\(b64u(ct))\"}"
    }
    /// Abre la envoltura sólo si es el texto canónico exacto (§4.1): claves repetidas, espacios, `1.0` o `true` no pasan.
    static func desenvolver(_ kek: Data, _ texto: String, cuenta: String) throws -> Data {
        guard let o = try? JSONSerialization.jsonObject(with: utf8(texto)) as? [String: Any], o.count == 4,
              let n = o["nonce"] as? String, let c = o["ct"] as? String,
              texto == "{\"v\":1,\"tipo\":\"recovery\",\"nonce\":\"\(n)\",\"ct\":\"\(c)\"}" else { throw Fallo(codigo: "envoltura") }
        let nonce = try deB64u(n), ct = try deB64u(c)
        guard nonce.count == 12, ct.count == 48 else { throw Fallo(codigo: "envoltura") }
        return try abrir(kek, nonce, ct, utf8("pear-wrap/v1|\(cuenta)|recovery"))
    }

    // MARK: Cadenas que se firman (§5)

    static func cadenaSesion(_ cuenta: String, _ disp: String, _ ts: Int, _ nonce: String) -> String {
        "pear-session/v1|\(cuenta)|\(disp)|\(ts)|\(nonce)"
    }
    static func cadenaAlta(_ cuenta: String, _ pubDisp: Data) -> String { "pear-add-device/v1|\(cuenta)|\(b64u(pubDisp))" }
    static func cadenaPeticion(_ metodo: String, _ ruta: String, _ cuenta: String, _ disp: String, _ ts: Int, _ nonce: String, _ cuerpo: Data) -> String {
        "pear-req/v1|\(metodo)|\(ruta)|\(cuenta)|\(disp)|\(ts)|\(nonce)|\(b64u(sha256(cuerpo)))"
    }

    /// El móvil trata el token como opaco: sólo lee `exp` para pedir otro 5 min antes (§6).
    static func expDelToken(_ token: String) -> Int? {
        let p = token.split(separator: ".", omittingEmptySubsequences: false)
        guard p.count == 3, p[0] == "v1", let d = try? deB64u(String(p[1])),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o["exp"] as? Int
    }

    // MARK: Emparejamiento por QR, v2 (cuenta.md §4.2 y §4.3; 2-E)

    /// Par X25519 efímero (E_n o E_v): privada y pública de 32 bytes. Se olvida al acabar.
    static func x25519Nueva() -> (priv: Data, pub: Data) {
        let k = Curve25519.KeyAgreement.PrivateKey()
        return (k.rawRepresentation, k.publicKey.rawRepresentation)
    }
    static func x25519Pub(_ priv: Data) throws -> Data {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: priv).publicKey.rawRepresentation
    }
    /// Secreto compartido de 32 bytes; falla si sale todo ceros (pública de orden bajo, paso 5).
    static func x25519(_ priv: Data, _ pubOtro: Data) throws -> Data {
        guard pubOtro.count == 32 else { throw Fallo(codigo: "x25519") }
        let k = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: priv)
        let s = try k.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubOtro))
            .withUnsafeBytes { Data($0) }
        guard s.count == 32, s.contains(where: { $0 != 0 }) else { throw Fallo(codigo: "x25519") }
        return s
    }
    /// k = HKDF(X25519, salt = s, info = "pear/pair/v2|" + b64u(E_n) + "|" + b64u(E_v)): la única HKDF con otra salt.
    static func clavePar(_ privPropia: Data, _ pubOtro: Data, s: Data, eN: Data, eV: Data) throws -> Data {
        guard s.count == 16 else { throw Fallo(codigo: "s") }
        return hkdf(try x25519(privPropia, pubOtro), info: "pear/pair/v2|\(b64u(eN))|\(b64u(eV))", salt: s)
    }
    static func aadSobre(_ cuenta: String, _ idEmp: String, _ pubCuenta: Data) -> Data {
        utf8("pear-pair/v2|\(cuenta)|\(idEmp)|\(b64u(pubCuenta))")
    }
    static func sellarSobre(_ k: Data, _ r: Data, cuenta: String, idEmp: String, pubCuenta: Data, nonce: Data = aleatorio(12)) throws -> String {
        let ct = try sellar(k, nonce, r, aadSobre(cuenta, idEmp, pubCuenta))
        return "{\"v\":2,\"nonce\":\"\(b64u(nonce))\",\"ct\":\"\(b64u(ct))\"}"
    }
    /// Abre el sobre sólo si es el texto canónico exacto (como la envoltura, §4.1).
    static func abrirSobre(_ k: Data, _ texto: String, cuenta: String, idEmp: String, pubCuenta: Data) throws -> Data {
        guard let o = try? JSONSerialization.jsonObject(with: utf8(texto)) as? [String: Any], o.count == 3,
              let n = o["nonce"] as? String, let c = o["ct"] as? String,
              texto == "{\"v\":2,\"nonce\":\"\(n)\",\"ct\":\"\(c)\"}" else { throw Fallo(codigo: "sobre") }
        let nonce = try deB64u(n), ct = try deB64u(c)
        guard nonce.count == 12, ct.count == 48 else { throw Fallo(codigo: "sobre") }
        return try abrir(k, nonce, ct, aadSobre(cuenta, idEmp, pubCuenta))
    }
    static func cadenaAltaPorQr(_ cuenta: String, _ idEmp: String, _ pubDisp: Data) -> String {
        "pear-pair-add/v1|\(cuenta)|\(idEmp)|\(b64u(pubDisp))"
    }
    static func cadenaFirmaEv(_ cuenta: String, _ idEmp: String, _ eV: Data) -> String {
        "pear-pair-ev/v1|\(cuenta)|\(idEmp)|\(b64u(eV))"
    }

    /// Lo que hace el móvil nuevo con la respuesta `completado` (paso 9), por este orden: abrir el sobre con el aad de
    /// la respuesta, que la clave de cuenta de R sea `pub_cuenta` y que `firma_ev` valga con ella. Devuelve R.
    static func abrirEmparejamiento(ePriv: Data, eN: Data, s: Data, eV: Data, sobre: String, cuenta: String, idEmp: String,
                                    pubCuenta: Data, firmaEv: Data) throws -> Data {
        let k = try clavePar(ePriv, eV, s: s, eN: eN, eV: eV)
        let r = try abrirSobre(k, sobre, cuenta: cuenta, idEmp: idEmp, pubCuenta: pubCuenta)
        guard try derivarDeR(r).pubCuenta == pubCuenta else { throw Fallo(codigo: "pub_cuenta") }
        guard edVerificar(pubCuenta, utf8(cadenaFirmaEv(cuenta, idEmp, eV)), firmaEv) else { throw Fallo(codigo: "firma_ev") }
        return r
    }

    /// Emojis de comprobación (§4.3): 6 índices de 0 a 63 con los 36 primeros bits de SHA-256 de todo el intercambio.
    static func emojis(cuenta: String, idEmp: String, pubCuenta: Data, eN: Data, eV: Data, s: Data) -> [Int] {
        let d = [UInt8](sha256(utf8("pear-pair-sas/v2|\(cuenta)|\(idEmp)|\(b64u(pubCuenta))|\(b64u(eN))|\(b64u(eV))|\(b64u(s))")))
        return (0..<6).map { i in
            (0..<6).reduce(0) { v, b in let bit = 6 * i + b; return (v << 1) | Int((d[bit >> 3] >> (7 - (bit & 7))) & 1) }
        }
    }

    /// La tabla fija de 64 emojis (§4.3), igual que en Android y que `shared/spec/emojis-qr.json` (PROVISIONAL, 2-E).
    /// Sus nombres para VoiceOver, en `EmparejarViews.swift` (`EmojisQr.nombre`).
    static let tablaEmojis: [String] = [
        "🐘", "🦒", "🐢", "🐙", "🦋", "🐝", "🐧", "🦀", "🐌", "🐳", "🦉", "🐍", "🦄", "🌵", "🌻", "🍄", "🍀", "🌈", "⛄", "⚡", "🔥", "🌍", "⭐", "🍎", "🍌", "🍇", "🍉", "🍍", "🍒", "🥕", "🌽", "🍕", "🍩", "🧀", "🍦", "☕", "🎃", "🎸", "🎺", "🥁", "🔦", "🎁", "🔑", "🔔", "💡", "⏰", "📷", "☔", "⚓", "🔨", "📚", "🎩", "👓", "👑", "💎", "🧦", "🚲", "🚀", "⛵", "🚗", "🏠", "🎲", "⚽", "🎯",
    ]

    /// Por porcentajes según RFC 3986: todo salvo A-Z a-z 0-9 - . _ ~, en UTF-8 y con mayúsculas.
    static func porcentaje(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            let c = Character(Unicode.Scalar(b))
            if (b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a) || (b >= 0x30 && b <= 0x39) || "-._~".contains(c) { out.append(c) }
            else { out += String(format: "%%%02X", b) }
        }
        return out
    }

    struct Qr: Equatable { let id: String; let eN: Data; let huella: Data; let s: Data; let nombre: String }

    static func qr(_ q: Qr) -> String {
        "libremusic://emparejar?v=2&id=\(q.id)&e=\(b64u(q.eN))&h=\(b64u(q.huella))&s=\(b64u(q.s))&n=\(porcentaje(q.nombre))"
    }

    /// Lee el QR (§4.2 paso 2): exactamente v, id, e, h, s y n, una vez cada uno y en cualquier orden; v = 2; id de la
    /// spec; e y h de 32 bytes y s de 16 en base64url estricto; n con la regla del nombre. Si no, nil («Este código no
    /// es válido»). Sólo lo llama el escáner de «Añadir un móvil».
    static func leerQr(_ texto: String) -> Qr? {
        let prefijo = "libremusic://emparejar?"
        guard texto.hasPrefix(prefijo) else { return nil }
        var p: [String: String] = [:]
        for parte in texto.dropFirst(prefijo.count).split(separator: "&", omittingEmptySubsequences: false) {
            guard let i = parte.firstIndex(of: "=") else { return nil }
            let k = String(parte[..<i]), v = String(parte[parte.index(after: i)...])
            guard ["v", "id", "e", "h", "s", "n"].contains(k), p[k] == nil else { return nil }
            p[k] = v
        }
        guard p.count == 6, p["v"] == "2", let id = p["id"], esId(id),
              let e = try? deB64u(p["e"]!), e.count == 32, let h = try? deB64u(p["h"]!), h.count == 32,
              let s = try? deB64u(p["s"]!), s.count == 16,
              let n = leerPorcentaje(p["n"]!), let nombre = nombreValido(n) else { return nil }
        return Qr(id: id, eN: e, huella: h, s: s, nombre: nombre)
    }

    /// Cualquier codificación por porcentajes válida, en UTF-8 (un % suelto o bytes que no son UTF-8 → nil).
    static func leerPorcentaje(_ s: String) -> String? {
        var bytes = [UInt8](), u = Array(s.utf8), i = 0
        while i < u.count {
            if u[i] == 0x25 {
                let hex: (UInt8) -> Bool = { (0x30...0x39).contains($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0) }
                guard i + 2 < u.count, hex(u[i + 1]), hex(u[i + 2]),
                      let b = UInt8(String(decoding: u[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) else { return nil }
                bytes.append(b); i += 3
            } else { bytes.append(u[i]); i += 1 }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    // MARK: «Comprobar mi clave» y avisos de alta (§7.3 puntos 7 y 8)

    /// La clave entera, sin red: deriva la clave de recuperación y compara su pública con `pub_rec`.
    static func esMiClave(_ texto: String, pubRec: Data) -> Bool {
        guard let c = leerClave(texto), let d = try? derivarDeC(c) else { return false }
        return d.pubRec == pubRec
    }

    struct Alta: Equatable { let deviceId: String; let nombre: String; let creado: Int; let quitado: Int? }
    enum Aviso: Equatable { case nuevo(String), quitado(String) }

    /// Las altas de `GET /v1/id/dispositivos` que no son este móvil ni están en `vistos`, por `creado` y `device_id`.
    static func avisosDeAlta(_ altas: [Alta], vistos: Set<String>, este: String) -> [Aviso] {
        altas.filter { $0.deviceId != este && !vistos.contains($0.deviceId) }
            .sorted { $0.creado != $1.creado ? $0.creado < $1.creado : $0.deviceId < $1.deviceId }
            .map { $0.quitado == nil ? .nuevo($0.deviceId) : .quitado($0.deviceId) }
    }

    /// `nombre` del dispositivo (§7): 1–40 puntos de código tras quitar los espacios de los lados, sin Cc.
    static func nombreValido(_ s: String) -> String? {
        let n = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = n.unicodeScalars
        guard (1...40).contains(u.count), !u.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        return n
    }
}
