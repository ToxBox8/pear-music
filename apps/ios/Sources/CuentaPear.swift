import CryptoKit
import Foundation
import LocalAuthentication
import Security
import UIKit

/// Cuenta Jiyu Pulse 3.0 (ADR 0004, docs/spec/cuenta.md), sin contraseña ni correo. Sustituye a `Account` (ADR 0001,
/// nunca desplegada para usuarios). R vive en el Llavero (ThisDeviceOnly); la clave del dispositivo D, en el Secure
/// Enclave (no exportable). La criptografía y los formatos, byte a byte, en `CuentaCripto` (probado con los vectores).
/// La app funciona igual sin cuenta; en el nivel 2 del estado firmado la cuenta se apaga (`Incident`).
@MainActor
final class CuentaPear: ObservableObject {
    static let shared = CuentaPear()
    /// pear-api (sin desplegar todavía). Jiyu Dev / pruebas: `-pearApiBase http://…` para hablar con `wrangler dev`.
    static var base: URL {
        if let s = UserDefaults.standard.string(forKey: "pearApiBase"), let u = URL(string: s) { return u }
        return URL(string: "https://pear-api.8toxbox8-69a.workers.dev")!
    }
    /// La de docs/legal/README.md (cuenta.md §7.2). Si el Worker tiene otra, `409 terminos_nuevos` y se vuelven a pedir.
    static let terminosVersion = "2026-11-17"

    struct Dispositivo: Identifiable, Equatable { let id: String; let nombre: String; let plataforma: String; let visto: Int?; let este: Bool }

    @Published private(set) var cuentaId: String?
    @Published private(set) var dispositivos: [Dispositivo] = []
    struct AvisoAlta: Identifiable { let id: String; let aviso: CuentaCripto.Aviso; let nombre: String }
    @Published private(set) var avisos: [AvisoAlta] = []
    @Published private(set) var borrarEn: Int?
    @Published private(set) var terminosPendientes = false
    @Published private(set) var disponible: Bool?
    var tieneCuenta: Bool { cuentaId != nil }
    var soloEsteMovil: Bool { dispositivos.count == 1 }

    private var token: String?
    private var tokenExp = 0
    private var deMentira = false

    /// Sólo capturas (`-screenshotScenario`): una cuenta de mentira, sin red ni claves (como `estadoDePrueba` de Android).
    func estadoDePrueba() {
        deMentira = true
        cuentaId = "1X99P4D412HRCSNX9XJZYP85GR"
        dispositivos = [
            Dispositivo(id: "WR85D13CWP6P3DAEZ6QB9H13HR", nombre: "iPhone 16", plataforma: "ios", visto: 1763400000, este: true),
            Dispositivo(id: "1X99P4D412HRCSNX9XJZYP85GR", nombre: "Pixel de Ana", plataforma: "android", visto: 1763390000, este: false),
        ]
        // La pub_rec de shared/spec/vectores/hkdf.json: su clave es TN2T-D4WT-QT75-ZFCX-H5W9-QQTJ-2W (CuentaUITests).
        meta.pubRec = "dIKLJHcIXwRQ7QUYY9Ec7so6OaW2UtKdC3gPfYwcW7o"
    }
    private var meta = Meta()

    struct Meta: Codable {
        var cuenta: String?
        var dispositivo: String?
        var pubRec: String?            // b64u (pública: «Comprobar mi clave» sin red)
        var creada: Int?
        var vistos: [String] = []       // aviso de alta (§7.3 punto 8)
        var desfase = 0                 // reloj de la app (§5.2, H6)
        var siguienteSugerencia: Int?   // «Comprobar mi clave»: a los 7, 30 y cada 90 días
    }

    private init() {
        if let d = Llavero.leer("meta"), let m = try? JSONDecoder().decode(Meta.self, from: d) { meta = m }
        cuentaId = meta.cuenta
    }

    // MARK: Errores (cuenta.md §7.1 y ADR 0004 §9)

    struct ErrorCuenta: Error, Equatable {
        let codigo: String
        /// Lo que se enseña (L()); discreto, nunca corta la música.
        var mensaje: String {
            switch codigo {
            case "sin_conexion": return L("Sin conexión")
            case "bloqueado": return L("Conexión bloqueada temporalmente. La música sigue funcionando")
            case "mantenimiento": return L("En mantenimiento")
            case "servicio_no_disponible", "limite_diario", "incidente":
                return L("La cuenta no está disponible ahora; puedes seguir escuchando")
            case "reloj_desfasado": return L("Revisa la hora del móvil")
            case "demasiadas_peticiones": return L("Demasiados intentos. Prueba dentro de un rato")
            case "dispositivo_revocado": return L("Este móvil ya no está en tu cuenta")
            case "no_encontrado": return L("No hay ninguna cuenta con esa clave")
            case "clave_invalida": return L("Esa clave no es válida")
            case "terminos_pendientes", "terminos_nuevos": return L("Hay términos nuevos que aceptar")
            case "ya_existe": return L("Ya hay 10 móviles en tu cuenta. Quita uno antes")
            case "no_es_la_cuenta": return L("No se ha podido abrir tu cuenta con esa clave")
            case "presencia": return L("Hace falta Face ID, huella o el código del móvil")
            default: return L("Algo ha fallado. Prueba otra vez")
            }
        }
    }

    // MARK: Crear la cuenta (§3, §7, §7.2)

    /// Lo que nace en el móvil ANTES de hablar con el servidor: R, C y el id de la cuenta. C se enseña una vez.
    struct Borrador { let r: Data; let c: Data; let cuentaId: String; var clave: String { CuentaCripto.base32(c) } }

    func borrador() -> Borrador {
        Borrador(r: CuentaCripto.aleatorio(32), c: CuentaCripto.aleatorio(16), cuentaId: CuentaCripto.base32(CuentaCripto.aleatorio(16)))
    }

    func crear(_ b: Borrador) async throws {
        try abierta()
        let deR = try CuentaCripto.derivarDeR(b.r), deC = try CuentaCripto.derivarDeC(b.c)
        let d = try ClaveDispositivo.nueva()
        let deviceId = CuentaCripto.idDispositivo(d.publica)
        let cuerpo: [String: Any] = [
            "account_id": b.cuentaId, "pub_cuenta": CuentaCripto.b64u(deR.pubCuenta), "pub_rec": CuentaCripto.b64u(deC.pubRec),
            "pub_disp": CuentaCripto.b64u(d.publica), "hash_l": CuentaCripto.b64u(deC.hashL),
            "envoltura_rec": try CuentaCripto.envolver(deC.kekRec, b.r, cuenta: b.cuentaId),
            "nombre": nombreMovil, "plataforma": "ios",
            "firma_alta": CuentaCripto.b64u(try CuentaCripto.edFirmar(deR.semillaCuenta, CuentaCripto.utf8(CuentaCripto.cadenaAlta(b.cuentaId, d.publica)))),
            "terminos_version": Self.terminosVersion, "mayor_14": true, "turnstile": "",
        ]
        let r = try await firmada("POST", "/v1/id/cuentas", cuerpo, cuenta: b.cuentaId, disp: d, dispId: deviceId, rec: deC.semillaRec, conToken: false)
        try guardar(r: b.r, d: d, cuenta: b.cuentaId, dispositivo: deviceId, pubRec: deC.pubRec)
        meta.creada = ahora()
        meta.siguienteSugerencia = ahora() + 7 * 86400
        guardarMeta()
        recibirToken(r)
    }

    // MARK: Entrar con la clave de recuperación (§7, §7.3 punto 1)

    func entrarConClave(_ texto: String) async throws {
        try abierta()
        guard let c = CuentaCripto.leerClave(texto) else { throw ErrorCuenta(codigo: "clave_invalida") }
        let deC = try CuentaCripto.derivarDeC(c)
        let enc = try await json(try await pedir("POST", "/v1/id/recuperacion/buscar", cuerpo: try datos(["l": CuentaCripto.b64u(deC.l)])))
        guard let cuenta = enc["account_id"] as? String, let env = enc["envoltura_rec"] as? String,
              let pc = enc["pub_cuenta"] as? String else { throw ErrorCuenta(codigo: "error_interno") }
        let r = try CuentaCripto.desenvolver(deC.kekRec, env, cuenta: cuenta)
        // La pública de la cuenta tiene que ser la de la respuesta; si no, se descarta R.
        guard try CuentaCripto.derivarDeR(r).pubCuenta == CuentaCripto.deB64u(pc) else { throw ErrorCuenta(codigo: "no_es_la_cuenta") }
        let d = try ClaveDispositivo.nueva()
        let deviceId = CuentaCripto.idDispositivo(d.publica)
        let cuerpo: [String: Any] = ["account_id": cuenta, "pub_disp": CuentaCripto.b64u(d.publica), "nombre": nombreMovil, "plataforma": "ios"]
        let res = try await firmada("POST", "/v1/id/dispositivos", cuerpo, cuenta: cuenta, disp: d, dispId: deviceId, rec: deC.semillaRec, conToken: false)
        try guardar(r: r, d: d, cuenta: cuenta, dispositivo: deviceId, pubRec: deC.pubRec)
        recibirToken(res)
        try await cargar()
        meta.vistos = Array(Set(meta.vistos + dispositivos.map(\.id) + altasVistas))
        avisos = []
        guardarMeta()
    }

    // MARK: Al abrir y en Ajustes › Cuenta

    private var altasVistas: [String] = []

    /// La cuenta (pub_rec, borrar_en) y los dispositivos con sus altas (avisos).
    func cargar() async throws {
        try abierta()
        guard tieneCuenta, !deMentira else { return }
        let c = try await json(try await conToken("GET", "/v1/id/cuenta"))
        if let pr = c["pub_rec"] as? String { meta.pubRec = pr }
        borrarEn = c["borrar_en"] as? Int
        let l = try await json(try await conToken("GET", "/v1/id/dispositivos"))
        dispositivos = (l["dispositivos"] as? [[String: Any]] ?? []).map {
            Dispositivo(id: $0["device_id"] as? String ?? "", nombre: $0["nombre"] as? String ?? "", plataforma: $0["plataforma"] as? String ?? "",
                        visto: $0["visto"] as? Int, este: $0["este"] as? Bool ?? false)
        }
        let altas = (l["altas"] as? [[String: Any]] ?? []).map {
            CuentaCripto.Alta(deviceId: $0["device_id"] as? String ?? "", nombre: $0["nombre"] as? String ?? "", creado: $0["creado"] as? Int ?? 0, quitado: $0["quitado"] as? Int)
        }
        altasVistas = altas.map(\.deviceId)
        let nombres = Dictionary(altas.map { ($0.deviceId, $0.nombre) }, uniquingKeysWith: { a, _ in a })
        avisos = CuentaCripto.avisosDeAlta(altas, vistos: Set(meta.vistos), este: meta.dispositivo ?? "").map { aviso in
            switch aviso { case .nuevo(let id), .quitado(let id): return AvisoAlta(id: id, aviso: aviso, nombre: nombres[id] ?? "") }
        }
        guardarMeta()
    }

    /// «He sido yo» o ya avisado: no se vuelve a avisar.
    func avisoVisto(_ deviceId: String) {
        meta.vistos.append(deviceId)
        avisos.removeAll { $0.id == deviceId }
        guardarMeta()
    }

    // MARK: Dispositivos (§7.3 puntos 3 y 9)

    func quitar(_ id: String) async throws {
        if id != meta.dispositivo { try await presencia(L("Quitar un móvil de tu cuenta")) }
        _ = try await firmada("DELETE", "/v1/id/dispositivos/\(id)", nil, cuentaFirma: true)
        if id == meta.dispositivo { olvidar() } else { try await cargar() }
    }

    /// «Quitar todos los demás móviles»: con C y presencia.
    func quitarLosDemas(clave: String) async throws {
        guard let c = CuentaCripto.leerClave(clave) else { throw ErrorCuenta(codigo: "clave_invalida") }
        let deC = try CuentaCripto.derivarDeC(c)
        try await presencia(L("Quitar todos los demás móviles"))
        _ = try await firmada("DELETE", "/v1/id/dispositivos", nil, cuentaFirma: true, rec: deC.semillaRec)
        meta.pubRec = CuentaCripto.b64u(deC.pubRec)
        try await cargar()
    }

    // MARK: Borrar (§7.3 punto 6)

    /// Con la clave: al momento. Sin ella: presencia y 14 días.
    func borrar(clave: String?) async throws {
        if let clave, !clave.isEmpty {
            guard let c = CuentaCripto.leerClave(clave) else { throw ErrorCuenta(codigo: "clave_invalida") }
            _ = try await firmada("DELETE", "/v1/id/cuenta", nil, cuentaFirma: true, rec: try CuentaCripto.derivarDeC(c).semillaRec)
            olvidar()
        } else {
            try await presencia(L("Borrar tu cuenta"))
            let r = try await json(try await firmada("DELETE", "/v1/id/cuenta", nil, cuentaFirma: true))
            borrarEn = r["borrar_en"] as? Int
        }
    }

    func cancelarBorrado() async throws {
        _ = try await firmada("DELETE", "/v1/id/cuenta/borrado", nil, cuentaFirma: true)
        borrarEn = nil
    }

    // MARK: Términos (§7.2)

    func aceptarTerminos() async throws {
        _ = try await firmada("PUT", "/v1/id/terminos", ["terminos_version": Self.terminosVersion, "mayor_14": true])
        terminosPendientes = false
    }

    // MARK: «Comprobar mi clave» (§7.3 punto 7), sin red

    func esMiClave(_ texto: String) -> Bool {
        guard let pr = meta.pubRec, let pub = try? CuentaCripto.deB64u(pr) else { return false }
        return CuentaCripto.esMiClave(texto, pubRec: pub)
    }

    /// La sugerencia discreta: a los 7 días de crear la cuenta, a los 30 y después cada 90.
    var tocaSugerirClave: Bool { tieneCuenta && (meta.siguienteSugerencia.map { ahora() >= $0 } ?? false) }
    func posponerSugerencia() {
        let creada = meta.creada ?? ahora()
        let pasos = [7, 30].map { creada + $0 * 86400 }
        meta.siguienteSugerencia = pasos.first { $0 > ahora() } ?? ahora() + 90 * 86400
        guardarMeta()
    }

    // MARK: Guardado local

    private func guardar(r: Data, d: ClaveDispositivo, cuenta: String, dispositivo: String, pubRec: Data) throws {
        try Llavero.guardar("R", r)
        try Llavero.guardar("D", d.guardable)
        meta.cuenta = cuenta
        meta.dispositivo = dispositivo
        meta.pubRec = CuentaCripto.b64u(pubRec)
        meta.vistos = [dispositivo]
        cuentaId = cuenta
        guardarMeta()
    }
    private func guardarMeta() { if let d = try? JSONEncoder().encode(meta) { try? Llavero.guardar("meta", d) } }

    /// Este móvil sale de la cuenta (lo han quitado o lo ha quitado él): fuera R, D y la sesión.
    func olvidar() {
        for k in ["R", "D", "meta"] { Llavero.borrar(k) }
        let desfase = meta.desfase
        meta = Meta()
        meta.desfase = desfase
        cuentaId = nil; token = nil; tokenExp = 0; dispositivos = []; avisos = []; borrarEn = nil
    }

    private var nombreMovil: String { CuentaCripto.nombreValido(UIDevice.current.name) ?? "iPhone" }

    // MARK: Red: reloj de la app, token y peticiones firmadas (§5, §6)

    /// Segundos del reloj de la app: el del móvil + el desfase medido con la cabecera `Date` del Worker.
    func ahora() -> Int { Int(Date().timeIntervalSince1970) + meta.desfase }

    private func abierta() throws {
        // Nivel 2 del estado firmado: la cuenta se apaga (no se llama a ninguna ruta).
        if Incident.shared.state.level == 2 { throw ErrorCuenta(codigo: "incidente") }
    }

    /// ¿Está pear-api? (`GET /v1/salud`; mide también el desfase la primera vez).
    func comprobarSalud() async {
        do {
            let o = try await json(try await pedir("GET", "/v1/salud"))
            disponible = (o["servicios"] as? [String: String])?["id"] == "up" && (o["estado"] as? String) == "ok"
        } catch { disponible = false }
    }

    private func conToken(_ metodo: String, _ ruta: String) async throws -> (Data, HTTPURLResponse) {
        try await renovarSiHaceFalta()
        do { return try await pedir(metodo, ruta, token: token) } catch let e as ErrorCuenta where e.codigo == "token_caducado" || e.codigo == "token_invalido" {
            tokenExp = 0
            try await renovarSiHaceFalta()
            return try await pedir(metodo, ruta, token: token)
        }
    }

    /// 5 min antes de `exp`, o si no hay: POST /v1/id/sesion, sin enseñar nada (lo decidió Toxbox).
    private func renovarSiHaceFalta() async throws {
        guard tokenExp - 300 <= ahora() else { return }
        guard let cuenta = meta.cuenta, let disp = meta.dispositivo, let d = ClaveDispositivo.guardada() else { throw ErrorCuenta(codigo: "sin_cuenta") }
        let ts = ahora(), nonce = CuentaCripto.b64u(CuentaCripto.aleatorio(16))
        let firma = try d.firmar(CuentaCripto.utf8(CuentaCripto.cadenaSesion(cuenta, disp, ts, nonce)))
        do {
            let r = try await pedir("POST", "/v1/id/sesion", cuerpo: try datos(["account_id": cuenta, "device_id": disp, "ts": ts, "nonce": nonce, "firma": CuentaCripto.b64u(firma)]))
            let o = try await json(r)
            recibirToken(o)
            terminosPendientes = (o["terminos_vigentes"] as? String) != (o["terminos_aceptados"] as? String)
            borrarEn = o["borrar_en"] as? Int
        } catch let e as ErrorCuenta where e.codigo == "dispositivo_revocado" {
            olvidar()
            throw e
        }
    }

    private func recibirToken(_ r: (Data, HTTPURLResponse)) { if let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any] { recibirToken(o) } }
    private func recibirToken(_ o: [String: Any]) {
        token = o["token"] as? String
        tokenExp = token.flatMap(CuentaCripto.expDelToken) ?? 0
    }

    /// Petición firmada con D (§5.2); `cuentaFirma` añade la de la cuenta (de R) y `rec`, la de recuperación (de C).
    private func firmada(_ metodo: String, _ ruta: String, _ cuerpo: [String: Any]?, cuenta: String? = nil, disp: ClaveDispositivo? = nil,
                         dispId: String? = nil, cuentaFirma: Bool = false, rec: Data? = nil, conToken: Bool = true) async throws -> (Data, HTTPURLResponse) {
        try abierta()
        if conToken { try await renovarSiHaceFalta() }
        guard let cuentaId = cuenta ?? meta.cuenta, let dispId = dispId ?? meta.dispositivo, let d = disp ?? ClaveDispositivo.guardada() else {
            throw ErrorCuenta(codigo: "sin_cuenta")
        }
        let bytes = try cuerpo.map(datos) ?? Data()
        var repetida = false
        while true {
            let ts = ahora(), nonce = CuentaCripto.b64u(CuentaCripto.aleatorio(16))
            let cadena = CuentaCripto.utf8(CuentaCripto.cadenaPeticion(metodo, ruta, cuentaId, dispId, ts, nonce, bytes))
            var h = ["X-Pear-Cuenta": cuentaId, "X-Pear-Disp": dispId, "X-Pear-Ts": String(ts), "X-Pear-Nonce": nonce,
                     "X-Pear-Firma-Disp": CuentaCripto.b64u(try d.firmar(cadena))]
            if cuentaFirma, let r = Llavero.leer("R") {
                h["X-Pear-Firma-Cuenta"] = CuentaCripto.b64u(try CuentaCripto.edFirmar(try CuentaCripto.derivarDeR(r).semillaCuenta, cadena))
            }
            if let rec { h["X-Pear-Firma-Rec"] = CuentaCripto.b64u(try CuentaCripto.edFirmar(rec, cadena)) }
            do {
                return try await pedir(metodo, ruta, cuerpo: cuerpo == nil ? nil : bytes, token: conToken ? token : nil, cabeceras: h)
            } catch let e as ErrorCuenta where e.codigo == "reloj_desfasado" && !repetida {
                repetida = true // el desfase ya se ha corregido con la Date de esa respuesta: una vez más
            } catch let e as ErrorCuenta where e.codigo == "terminos_pendientes" {
                terminosPendientes = true
                throw e
            }
        }
    }

    private func pedir(_ metodo: String, _ ruta: String, cuerpo: Data? = nil, token: String? = nil, cabeceras: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: Self.base.appendingPathComponent(String(ruta.dropFirst())), timeoutInterval: 20)
        req.httpMethod = metodo
        if let cuerpo { req.httpBody = cuerpo; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") } // i18n: no
        for (k, v) in cabeceras { req.setValue(v, forHTTPHeaderField: k) }
        let data: Data, res: URLResponse
        do { (data, res) = try await URLSession.shared.data(for: req) } catch { throw await errorDeRed() }
        guard let http = res as? HTTPURLResponse else { throw ErrorCuenta(codigo: "error_interno") }
        // Reloj de la app: desfase = Date del Worker − hora del móvil al recibirla (§5.2).
        if let fecha = http.value(forHTTPHeaderField: "Date").flatMap(Self.fechaHTTP) { // i18n: no
            meta.desfase = Int(fecha.timeIntervalSince1970) - Int(Date().timeIntervalSince1970)
        }
        if http.statusCode >= 400 {
            let codigo = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any])?["codigo"] as? String
            Logs.w("Cuenta", "\(metodo) \(http.statusCode) \(codigo ?? "?")") // sin ruta ni ids (§9)
            throw ErrorCuenta(codigo: codigo ?? "error_interno")
        }
        return (data, http)
    }

    /// Sin Internet o Cloudflare bloqueado (ADR 0004 §9): se prueba un dominio que no es de Cloudflare.
    private func errorDeRed() async -> ErrorCuenta {
        var r = URLRequest(url: URL(string: "https://www.google.com/generate_204")!, timeoutInterval: 6)
        r.httpMethod = "HEAD"
        let hayInternet = (try? await URLSession.shared.data(for: r)) != nil
        return ErrorCuenta(codigo: hayInternet ? "bloqueado" : "sin_conexion")
    }

    private func json(_ r: (Data, HTTPURLResponse)) async throws -> [String: Any] {
        guard let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any] else { throw ErrorCuenta(codigo: "error_interno") }
        return o
    }
    private func datos(_ o: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) }

    private static let formatoHTTP: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
    private static func fechaHTTP(_ s: String) -> Date? { formatoHTTP.date(from: s) }

    // MARK: Presencia (§7.3 punto 3): Face ID / huella o el código del sistema

    private func presencia(_ motivo: String) async throws {
        if UserDefaults.standard.bool(forKey: "pearSinPresencia") && Channel.adminTools { return } // tests de interfaz (Jiyu Dev)
        let ctx = LAContext()
        do {
            guard try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: motivo) else { throw ErrorCuenta(codigo: "presencia") }
        } catch is ErrorCuenta { throw ErrorCuenta(codigo: "presencia") } catch { throw ErrorCuenta(codigo: "presencia") }
    }
}

// MARK: - La clave del dispositivo D (P-256): Secure Enclave; en el simulador o con -screenshotScenario, una normal

private enum ClaveDispositivo {
    case enclave(SecureEnclave.P256.Signing.PrivateKey)
    case software(P256.Signing.PrivateKey)

    static func nueva() throws -> ClaveDispositivo {
        #if targetEnvironment(simulator)
        return .software(P256.Signing.PrivateKey())
        #else
        if SecureEnclave.isAvailable { return .enclave(try SecureEnclave.P256.Signing.PrivateKey()) }
        throw CuentaPear.ErrorCuenta(codigo: "sin_enclave")
        #endif
    }
    static func guardada() -> ClaveDispositivo? {
        guard let d = Llavero.leer("D") else { return nil }
        #if targetEnvironment(simulator)
        return (try? P256.Signing.PrivateKey(rawRepresentation: d)).map(ClaveDispositivo.software)
        #else
        return (try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: d)).map(ClaveDispositivo.enclave)
        #endif
    }
    /// 65 bytes SEC1 (`x963Representation`).
    var publica: Data {
        switch self { case .enclave(let k): return k.publicKey.x963Representation; case .software(let k): return k.publicKey.x963Representation }
    }
    /// Lo que se guarda en el Llavero: del Secure Enclave, su `dataRepresentation` (un identificador cifrado por el
    /// propio chip, no la clave); en el simulador, la clave normal.
    var guardable: Data {
        switch self { case .enclave(let k): return k.dataRepresentation; case .software(let k): return k.rawRepresentation }
    }
    /// r‖s de 64 bytes (`rawRepresentation`).
    func firmar(_ d: Data) throws -> Data {
        switch self {
        case .enclave(let k): return try k.signature(for: d).rawRepresentation
        case .software(let k): return try k.signature(for: d).rawRepresentation
        }
    }
}

// MARK: - Llavero: servicio «pear-id», ThisDeviceOnly (cuenta.md §2)

enum Llavero {
    private static let servicio = "pear-id"
    private static func consulta(_ cuenta: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicio, kSecAttrAccount as String: cuenta]
    }
    static func guardar(_ cuenta: String, _ datos: Data) throws {
        SecItemDelete(consulta(cuenta) as CFDictionary)
        var q = consulta(cuenta)
        q[kSecValueData as String] = datos
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let s = SecItemAdd(q as CFDictionary, nil)
        guard s == errSecSuccess else { Logs.e("Cuenta", "Llavero \(s)"); throw CuentaPear.ErrorCuenta(codigo: "llavero") }
    }
    static func leer(_ cuenta: String) -> Data? {
        var q = consulta(cuenta)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    static func borrar(_ cuenta: String) { SecItemDelete(consulta(cuenta) as CFDictionary) }
}
