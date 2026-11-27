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
    /// pear-api (desplegado el 19-11-2026). Jiyu Dev / pruebas: `-pearApiBase http://…` para hablar con `wrangler dev`.
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
    /// `unico`: sólo este dispositivo (captura 70b, «Cerrar sesión» siendo el único).
    func estadoDePrueba(unico: Bool = false) {
        deMentira = true
        cuentaId = "1X99P4D412HRCSNX9XJZYP85GR"
        dispositivos = [
            Dispositivo(id: "WR85D13CWP6P3DAEZ6QB9H13HR", nombre: L("iPhone 16"), plataforma: "ios", visto: 1763400000, este: true),
            Dispositivo(id: "1X99P4D412HRCSNX9XJZYP85GR", nombre: L("Pixel de Ana"), plataforma: "android", visto: 1763390000, este: false),
        ]
        if unico { dispositivos.removeLast() }
        meta.dispositivo = "WR85D13CWP6P3DAEZ6QB9H13HR"
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
        // Capturas: la cuenta de mentira sólo en los escenarios que la necesitan. (No en el cierre de `.demoRoute`:
        // SwiftUI construye el destino aunque no sea la ruta del escenario, y la ponía en todos.)
        if let r = Demo.current?.route, [.cuentaComprobar, .cuentaBorrar, .cuentaAnadir, .cuentaAnadirEmojis, .cuentaConectada,
                                          .cuentaSincronizado, .cuentaBloqueado, .cuentaSeguridad, .cuentaCerrarSesion,
                                          .cuentaCerrarSesionUnico, .cuentaTerminos, .cuentaPulsos, .cuentaPulsosVacio].contains(r) {
            estadoDePrueba(unico: r == .cuentaCerrarSesionUnico)
        }
    }

    // MARK: Errores (cuenta.md §7.1 y ADR 0004 §9)

    struct ErrorCuenta: Error, Equatable {
        let codigo: String
        /// El `Retry-After` del servidor (segundos), si lo trae (los 429; B2-6).
        var esperaS: Int? = nil
        /// Lo que se enseña (`CuentaErrores.mensaje`, sólo Foundation: se prueba en Linux).
        var mensaje: String { CuentaErrores.mensaje(codigo) }
    }

    /// El texto de cualquier fallo de la cuenta: un ErrorCuenta da el suyo; lo demás es del propio móvil (`error_local`,
    /// DECISIONS 94), con su tipo en el registro y, en Jiyu Dev, debajo del aviso. Igual que `CuentaPear.mensajeDe` en Android.
    nonisolated static func mensajeDe(_ e: Error) -> String {
        if let c = e as? ErrorCuenta { return c.mensaje }
        return CuentaErrores.local(e, dev: Channel.current == "dev") { Logs.w("Cuenta", $0) }
    }

    // MARK: Crear la cuenta (§3, §7, §7.2)

    /// Lo que nace en el móvil ANTES de hablar con el servidor: R, C y el id de la cuenta. C se enseña una vez.
    struct Borrador { let r: Data; let c: Data; let cuentaId: String; var clave: String { CuentaCripto.base32(c) } }

    /// El borrador de «Crear cuenta», para «Tu clave de recuperación», que la sustituye en la pila (como
    /// `CuentaPear.pendiente` en Android). Sólo en memoria: C no se guarda nunca.
    var pendiente: Borrador?

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
        let r: (Data, HTTPURLResponse)
        do {
            r = try await firmada("POST", "/v1/id/cuentas", cuerpo, cuenta: b.cuentaId, disp: d, dispId: deviceId, rec: deC.semillaRec, conToken: false)
        } catch let e as ErrorCuenta where e.codigo == "limite_diario" {
            throw ErrorCuenta(codigo: "tope_altas") // el tope global de altas del día (orden 9 del 18-11)
        }
        try guardar(r: b.r, d: d, cuenta: b.cuentaId, dispositivo: deviceId, pubRec: deC.pubRec)
        meta.creada = ahora()
        meta.siguienteSugerencia = ahora() + 7 * 86400
        guardarMeta()
        recibirToken(r)
        SyncBiblioteca.shared.alEntrar()
    }

    // MARK: Entrar con la clave de recuperación (§7, §7.3 punto 1)

    func entrarConClave(_ texto: String) async throws {
        try abierta()
        guard let c = CuentaCripto.leerClave(texto) else { throw ErrorCuenta(codigo: "clave_invalida") }
        let deC = try CuentaCripto.derivarDeC(c)
        let enc: [String: Any]
        do { enc = try await json(try await pedir("POST", "/v1/id/recuperacion/buscar", cuerpo: try datos(["l": CuentaCripto.b64u(deC.l)]))) }
        catch let e as ErrorCuenta where e.codigo == "no_encontrado" { throw ErrorCuenta(codigo: "clave_sin_cuenta") }
        guard let cuenta = enc["account_id"] as? String, let env = enc["envoltura_rec"] as? String,
              let pc = enc["pub_cuenta"] as? String else { throw ErrorCuenta(codigo: "error_interno") }
        let r = try CuentaCripto.desenvolver(deC.kekRec, env, cuenta: cuenta)
        // La pública de la cuenta tiene que ser la de la respuesta; si no, se descarta R.
        guard try CuentaCripto.derivarDeR(r).pubCuenta == CuentaCripto.deB64u(pc) else { throw ErrorCuenta(codigo: "no_es_la_cuenta") }
        let d = try ClaveDispositivo.nueva()
        let deviceId = CuentaCripto.idDispositivo(d.publica)
        let cuerpo: [String: Any] = ["account_id": cuenta, "pub_disp": CuentaCripto.b64u(d.publica), "nombre": nombreMovil, "plataforma": "ios"]
        let res: (Data, HTTPURLResponse)
        do { res = try await firmada("POST", "/v1/id/dispositivos", cuerpo, cuenta: cuenta, disp: d, dispId: deviceId, rec: deC.semillaRec, conToken: false) }
        catch let e as ErrorCuenta where e.codigo == "ya_existe" { throw ErrorCuenta(codigo: "cuenta_llena") } // la D es nueva: son los 10
        try guardar(r: r, d: d, cuenta: cuenta, dispositivo: deviceId, pubRec: deC.pubRec)
        recibirToken(res)
        try await cargar()
        meta.vistos = Array(Set(meta.vistos + dispositivos.map(\.id) + altasVistas))
        avisos = []
        guardarMeta()
        SyncBiblioteca.shared.alEntrar()
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
        if id != meta.dispositivo { try await presencia(L("Quitar un dispositivo de tu cuenta")) }
        _ = try await firmada("DELETE", "/v1/id/dispositivos/\(id)", nil, cuentaFirma: true)
        if id == meta.dispositivo { olvidar() } else { try await cargar() }
    }

    /// Cambiar el nombre (`PUT …/{id}/nombre`; órdenes 6 y 9 del 18-11): este móvil, con presencia; otro, con C.
    func renombrar(_ id: String, a nombre: String) async throws {
        guard let n = CuentaCripto.nombreValido(nombre) else { throw ErrorCuenta(codigo: "nombre_invalido") }
        let propio = id == meta.dispositivo
        if propio { try await presencia(L("Cambiar el nombre de este dispositivo")) }
        do {
            _ = try await firmada("PUT", "/v1/id/dispositivos/\(id)/nombre", ["nombre": n], cuentaFirma: !propio)
        } catch let e as ErrorCuenta where e.codigo == "no_encontrado" {
            throw ErrorCuenta(codigo: "movil_no_encontrado")
        }
        try await cargar()
    }

    /// Cerrar sesión (Pulir 2 · notas de la opción A #4): este dispositivo sale de la cuenta con la misma ruta que quitar
    /// uno (`DELETE …/dispositivos/{este}`, sin nada nuevo en el servidor) y se olvidan R, D y la sesión (`olvidar`). La
    /// biblioteca se queda en el dispositivo, sin sincronizar: no se borra nada. Pide presencia (quitar el propio no la
    /// exige el servidor; la pide la app). Si el servidor no contesta, no se olvida nada: seguirías en la lista de los
    /// demás sin poder salir de ella. Igual que `CuentaPear.cerrarSesion` en Android.
    func cerrarSesion() async throws {
        try await presencia(L("Cerrar sesión en este dispositivo"))
        if !deMentira {
            guard let id = meta.dispositivo else { throw ErrorCuenta(codigo: "sin_cuenta") }
            _ = try await firmada("DELETE", "/v1/id/dispositivos/\(id)", nil, cuentaFirma: true)
        }
        olvidar(conservarSoloAqui: true) // B2-8: «No sincronizar esto» se queda (lo decidió Toxbox)
    }

    /// «Quitar todos los demás móviles»: con C y presencia.
    func quitarLosDemas(clave: String) async throws {
        guard let c = CuentaCripto.leerClave(clave) else { throw ErrorCuenta(codigo: "clave_invalida") }
        let deC = try CuentaCripto.derivarDeC(c)
        try await presencia(L("Quitar todos los demás dispositivos"))
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
        do { _ = try await firmada("DELETE", "/v1/id/cuenta/borrado", nil, cuentaFirma: true) }
        catch let e as ErrorCuenta where e.codigo == "no_encontrado" { throw ErrorCuenta(codigo: "sin_borrado") }
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

    // MARK: Móvil nuevo por QR (§4.2; 2-E)

    /// Lo que crea el móvil nuevo (N) al enseñar el QR: D, E_n y s. `s` sólo va en el QR (nunca al servidor ni a un
    /// registro). `inicio`, en el reloj monótono: a los 5 min deja de esperar, diga lo que diga el servidor.
    struct QrNuevo {
        let texto: String
        let idEmp: String
        fileprivate let d: ClaveDispositivo
        fileprivate let ePriv: Data
        fileprivate let eN: Data
        fileprivate let s: Data
        let inicio: TimeInterval
        var quedan: TimeInterval { max(0, 300 - (ProcessInfo.processInfo.systemUptime - inicio)) }
    }
    /// Lo que le llega a N cuando el viejo completa: R ya comprobada (aún sin guardar) y los emojis.
    struct QrRecibido { fileprivate let r: Data; let cuenta: String; let deviceId: String; let emojis: [Int] }

    /// Paso 1: `POST /v1/id/emparejamientos` y el texto del QR.
    func empezarQr() async throws -> QrNuevo {
        try abierta()
        let d = try ClaveDispositivo.nueva()
        let e = CuentaCripto.x25519Nueva(), s = CuentaCripto.aleatorio(16)
        let o: [String: Any]
        do {
            o = try await json(try await pedir("POST", "/v1/id/emparejamientos", cuerpo: try datos([
                "pub_disp_nuevo": CuentaCripto.b64u(d.publica), "e_n": CuentaCripto.b64u(e.pub), "nombre": nombreMovil, "plataforma": "ios",
            ])))
        } catch let err as ErrorCuenta where err.codigo == "ya_existe" { throw ErrorCuenta(codigo: "movil_ya_en_cuenta") }
        guard let id = o["id_emp"] as? String, CuentaCripto.esId(id) else { throw ErrorCuenta(codigo: "error_interno") }
        let q = CuentaCripto.Qr(id: id, eN: e.pub, huella: CuentaCripto.sha256(d.publica), s: s, nombre: nombreMovil)
        return QrNuevo(texto: CuentaCripto.qr(q), idEmp: id, d: d, ePriv: e.priv, eN: e.pub, s: s, inicio: ProcessInfo.processInfo.systemUptime)
    }

    /// Paso 8, una vez (la pantalla lo repite cada 2 s): nil mientras espera; con `completado`, abre el sobre y lo
    /// comprueba (paso 9). Pasados los 5 min, «El código ha caducado».
    func esperarQr(_ q: QrNuevo) async throws -> QrRecibido? {
        guard q.quedan > 0 else { throw ErrorCuenta(codigo: "emparejamiento_caducado") }
        let dispId = CuentaCripto.idDispositivo(q.d.publica)
        let o = try await json(try await firmada("POST", "/v1/id/emparejamientos/estado", ["id_emp": q.idEmp], cuenta: "", disp: q.d,
                                                 dispId: dispId, conToken: false, sinCuenta: true))
        guard (o["estado"] as? String) == "completado" else { return nil }
        do {
            guard let cuenta = o["account_id"] as? String, CuentaCripto.esId(cuenta), (o["device_id"] as? String) == dispId,
                  let ev = o["e_v"] as? String, let sobre = o["sobre"] as? String, let fe = o["firma_ev"] as? String,
                  let pc = o["pub_cuenta"] as? String else { throw ErrorCuenta(codigo: "no_anadido") }
            let eV = try CuentaCripto.deB64u(ev), pubCuenta = try CuentaCripto.deB64u(pc)
            let r = try CuentaCripto.abrirEmparejamiento(ePriv: q.ePriv, eN: q.eN, s: q.s, eV: eV, sobre: sobre, cuenta: cuenta,
                                                         idEmp: q.idEmp, pubCuenta: pubCuenta, firmaEv: try CuentaCripto.deB64u(fe))
            return QrRecibido(r: r, cuenta: cuenta, deviceId: dispId,
                              emojis: CuentaCripto.emojis(cuenta: cuenta, idEmp: q.idEmp, pubCuenta: pubCuenta, eN: q.eN, eV: eV, s: q.s))
        } catch { throw ErrorCuenta(codigo: "no_anadido") } // R se descarta: no se ha guardado nada
    }

    /// Paso 10, «Sí, coinciden»: sólo ahora se guarda R y se pide el primer token (que gasta el emparejamiento).
    func aceptarQr(_ q: QrNuevo, _ rec: QrRecibido) async throws {
        try abierta()
        try Llavero.guardar("R", rec.r)
        try Llavero.guardar("D", q.d.guardable)
        meta.cuenta = rec.cuenta
        meta.dispositivo = rec.deviceId
        meta.vistos = [rec.deviceId]
        cuentaId = rec.cuenta
        guardarMeta()
        tokenExp = 0
        try await renovarSiHaceFalta()
        try await cargar() // trae pub_rec (el QR no la trae; R3) y los móviles
        meta.vistos = Array(Set(meta.vistos + dispositivos.map(\.id) + altasVistas))
        avisos = []
        guardarMeta()
        SyncBiblioteca.shared.alEntrar()
    }

    // MARK: Añadir un móvil desde el viejo (§4.2 pasos 3–7 y 11)

    struct QrLeido { let qr: CuentaCripto.Qr; let plataforma: String; fileprivate let pubDispNuevo: Data }

    /// Paso 3: lee el QR (sólo desde el escáner de «Añadir un móvil»), pide `estado` y comprueba la huella.
    func leerQrDeOtro(_ texto: String) async throws -> QrLeido {
        try abierta()
        guard let q = CuentaCripto.leerQr(texto) else { throw ErrorCuenta(codigo: "qr_invalido") }
        let o = try await json(try await firmada("POST", "/v1/id/emparejamientos/estado", ["id_emp": q.id]))
        guard let pd = o["pub_disp_nuevo"] as? String, let pub = try? CuentaCripto.deB64u(pd), pub.count == 65,
              CuentaCripto.sha256(pub) == q.huella else { throw ErrorCuenta(codigo: "qr_invalido") }
        return QrLeido(qr: q, plataforma: o["plataforma"] as? String ?? "", pubDispNuevo: pub)
    }

    /// Pasos 5–7: tras «Añadir», presencia, sobre y firmas, `completar`; devuelve los emojis para comparar.
    /// 410 emparejamiento_usado: otro se adelantó con el mismo QR (paso 11), sin emojis.
    func completarQr(_ l: QrLeido) async throws -> [Int] {
        try abierta()
        try await presencia(L("Añadir un dispositivo a tu cuenta"))
        guard let cuenta = meta.cuenta, let r = Llavero.leer("R") else { throw ErrorCuenta(codigo: "sin_cuenta") }
        let deR = try CuentaCripto.derivarDeR(r)
        let e = CuentaCripto.x25519Nueva()
        let k = try CuentaCripto.clavePar(e.priv, l.qr.eN, s: l.qr.s, eN: l.qr.eN, eV: e.pub)
        let cuerpo: [String: Any] = [
            "id_emp": l.qr.id, "e_v": CuentaCripto.b64u(e.pub),
            "sobre": try CuentaCripto.sellarSobre(k, r, cuenta: cuenta, idEmp: l.qr.id, pubCuenta: deR.pubCuenta),
            "firma_alta": CuentaCripto.b64u(try CuentaCripto.edFirmar(deR.semillaCuenta, CuentaCripto.utf8(CuentaCripto.cadenaAltaPorQr(cuenta, l.qr.id, l.pubDispNuevo)))),
            "firma_ev": CuentaCripto.b64u(try CuentaCripto.edFirmar(deR.semillaCuenta, CuentaCripto.utf8(CuentaCripto.cadenaFirmaEv(cuenta, l.qr.id, e.pub)))),
        ]
        do {
            _ = try await firmada("POST", "/v1/id/emparejamientos/completar", cuerpo, cuentaFirma: true)
        } catch let err as ErrorCuenta where err.codigo == "emparejamiento_usado" {
            throw ErrorCuenta(codigo: "qr_adelantado")
        } catch let err as ErrorCuenta where err.codigo == "ya_existe" {
            throw ErrorCuenta(codigo: "cuenta_llena")
        }
        meta.vistos.append(CuentaCripto.idDispositivo(l.pubDispNuevo)) // el aviso de alta no salta para el que acabas de añadir
        guardarMeta()
        try? await cargar()
        return CuentaCripto.emojis(cuenta: cuenta, idEmp: l.qr.id, pubCuenta: deR.pubCuenta, eN: l.qr.eN, eV: e.pub, s: l.qr.s)
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
    func olvidar(conservarSoloAqui: Bool = false) {
        for k in ["R", "D", "meta"] { Llavero.borrar(k) }
        SyncBiblioteca.shared.olvidar(conservarSoloAqui: conservarSoloAqui)
        PulsosEstado.shared.olvidar()
        let desfase = meta.desfase
        meta = Meta()
        meta.desfase = desfase
        cuentaId = nil; token = nil; tokenExp = 0; dispositivos = []; avisos = []; borrarEn = nil
        deMentira = false
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

    private func conToken(_ metodo: String, _ ruta: String, cabeceras: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        try await renovarSiHaceFalta()
        do { return try await pedir(metodo, ruta, token: token, cabeceras: cabeceras) } catch let e as ErrorCuenta where e.codigo == "token_caducado" || e.codigo == "token_invalido" {
            tokenExp = 0
            try await renovarSiHaceFalta()
            return try await pedir(metodo, ruta, token: token, cabeceras: cabeceras)
        }
    }

    // MARK: Sync (sync.md §3): sólo el transporte de los bloques; lo de dentro lo hace SyncBiblioteca

    enum Bajada { case igual, bloque(Data, etag: String), noHay }
    /// Los 8 primeros caracteres del device_id (la `d` de las marcas, sync.md §5.1).
    var dispositivoCorto: String? { deMentira ? nil : meta.dispositivo.map { String($0.prefix(8)) } }
    var kMusic: Data? { deMentira ? nil : Llavero.leer("R").flatMap { try? CuentaCripto.derivarDeR($0).kMusic } }
    /// Milisegundos del reloj de la app (para las marcas).
    func ahoraMs() -> Double { (Date().timeIntervalSince1970 + Double(meta.desfase)) * 1000 }

    func bajarBloque(_ clave: String, etag: String?) async throws -> Bajada {
        try abierta()
        guard !deMentira, meta.cuenta != nil else { throw ErrorCuenta(codigo: "sin_cuenta") }
        do {
            let r = try await conToken("GET", "/v1/sync/music/\(clave)", cabeceras: etag.map { ["If-None-Match": $0] } ?? [:]) // i18n: no
            if r.1.statusCode == 304 { return .igual }
            return .bloque(r.0, etag: r.1.value(forHTTPHeaderField: "ETag") ?? "") // i18n: no
        } catch let e as ErrorCuenta where e.codigo == "no_encontrado" { return .noHay }
    }

    /// Sube con If-Match (o If-None-Match: * si es la primera vez). 409 → ErrorCuenta("version_cambiada"). Da el ETag nuevo.
    func subirBloque(_ clave: String, _ bloque: Data, etag: String?) async throws -> String {
        guard !deMentira else { throw ErrorCuenta(codigo: "sin_cuenta") }
        let r = try await firmada("PUT", "/v1/sync/music/\(clave)", nil, crudo: bloque, extra: etag.map { ["If-Match": $0] } ?? ["If-None-Match": "*"]) // i18n: no
        if let e = r.1.value(forHTTPHeaderField: "ETag") { return e } // i18n: no
        return (try await json(r))["etag"] as? String ?? ""
    }

    // MARK: Pulsos (puntos.md §3 y §4): sólo el transporte; leer y lo que se ve, en PulsosModel y PulsosViews

    /// `GET /v1/puntos` (o `/v1/puntos/antes/{cursor}`) con el token; da los bytes tal cual para que
    /// `PulsosModel.leer` los compruebe enteros. Un token caducado se renueva y se repite una vez. Igual que Android.
    func pedirPulsos(_ cursor: String?) async throws -> Data {
        try abierta()
        guard !deMentira, meta.cuenta != nil else { throw ErrorCuenta(codigo: "sin_cuenta") }
        return try await conToken("GET", cursor.map { "/v1/puntos/antes/\($0)" } ?? "/v1/puntos").0 // i18n: no
    }

    /// Gasta `cantidad` pulsos en `concepto` con un `idOperacion` de `PulsosModel.nuevoIdOperacion` (el mismo si se
    /// repite tras un corte: no cobra dos veces). Firmado con D. En la 3.0 no lo usa ninguna pantalla (la tienda es la 3.1).
    func gastarPulsos(_ idOperacion: String, _ cantidad: Int64, _ concepto: String) async throws -> [String: Any] {
        guard !deMentira else { throw ErrorCuenta(codigo: "sin_cuenta") }
        guard let cuerpo = PulsosModel.cuerpoGasto(idOperacion, cantidad, concepto) else { throw ErrorCuenta(codigo: "peticion_invalida") }
        return try await json(try await firmada("POST", PulsosModel.rutaGastos, nil, crudo: Data(cuerpo.utf8), tipoCrudo: "application/json"))
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
    /// `crudo`: un cuerpo binario (los bloques de la sync), en vez de `cuerpo` en JSON. `extra`: más cabeceras.
    private func firmada(_ metodo: String, _ ruta: String, _ cuerpo: [String: Any]?, cuenta: String? = nil, disp: ClaveDispositivo? = nil,
                         dispId: String? = nil, cuentaFirma: Bool = false, rec: Data? = nil, conToken: Bool = true,
                         crudo: Data? = nil, extra: [String: String] = [:], sinCuenta: Bool = false,
                         tipoCrudo: String = "application/octet-stream") async throws -> (Data, HTTPURLResponse) {
        try abierta()
        if conToken { try await renovarSiHaceFalta() }
        guard let cuentaId = cuenta ?? meta.cuenta, let dispId = dispId ?? meta.dispositivo, let d = disp ?? ClaveDispositivo.guardada() else {
            throw ErrorCuenta(codigo: "sin_cuenta")
        }
        let bytes = try crudo ?? cuerpo.map(datos) ?? Data()
        var repetida = false
        while true {
            let ts = ahora(), nonce = CuentaCripto.b64u(CuentaCripto.aleatorio(16))
            let cadena = CuentaCripto.utf8(CuentaCripto.cadenaPeticion(metodo, ruta, cuentaId, dispId, ts, nonce, bytes))
            // `sinCuenta`: el sondeo del QR del móvil nuevo, sin X-Pear-Cuenta y con la cuenta vacía en la cadena (§5.2).
            var h = ["X-Pear-Disp": dispId, "X-Pear-Ts": String(ts), "X-Pear-Nonce": nonce,
                     "X-Pear-Firma-Disp": CuentaCripto.b64u(try d.firmar(cadena))]
            if !sinCuenta { h["X-Pear-Cuenta"] = cuentaId }
            if cuentaFirma, let r = Llavero.leer("R") {
                h["X-Pear-Firma-Cuenta"] = CuentaCripto.b64u(try CuentaCripto.edFirmar(try CuentaCripto.derivarDeR(r).semillaCuenta, cadena))
            }
            if let rec { h["X-Pear-Firma-Rec"] = CuentaCripto.b64u(try CuentaCripto.edFirmar(rec, cadena)) }
            h.merge(extra) { _, b in b }
            do {
                return try await pedir(metodo, ruta, cuerpo: cuerpo == nil && crudo == nil ? nil : bytes, token: conToken ? token : nil, cabeceras: h,
                                       tipo: crudo == nil ? "application/json" : tipoCrudo)
            } catch let e as ErrorCuenta where e.codigo == "reloj_desfasado" && !repetida {
                repetida = true // el desfase ya se ha corregido con la Date de esa respuesta: una vez más
            } catch let e as ErrorCuenta where e.codigo == "terminos_pendientes" {
                terminosPendientes = true
                throw e
            }
        }
    }

    private func pedir(_ metodo: String, _ ruta: String, cuerpo: Data? = nil, token: String? = nil, cabeceras: [String: String] = [:],
                       tipo: String = "application/json") async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: Self.base.appendingPathComponent(String(ruta.dropFirst())), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = metodo
        if let cuerpo { req.httpBody = cuerpo; req.setValue(tipo, forHTTPHeaderField: "Content-Type") } // i18n: no
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
            if let codigo { trasError(codigo) }
            // Sin el JSON de error (lo de delante de Cloudflare, un Worker caído): por el código HTTP.
            throw ErrorCuenta(codigo: codigo ?? (http.statusCode == 429 ? "demasiadas_peticiones"
                                                 : (500...599).contains(http.statusCode) ? "servidor_caido" : "http_\(http.statusCode)"),
                              esperaS: http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }) // i18n: no
        }
        return (data, http)
    }

    /// Lo que pasa con un error del servidor, en cualquier petición (revisión del bloque 2, B2-2): «dispositivo_revocado»
    /// (el Worker sólo lo dice con la firma o el token buenos) saca a este dispositivo de la cuenta al momento, no sólo al
    /// renovar la sesión. Igual que `trasError` en Android.
    func trasError(_ codigo: String) { if codigo == "dispositivo_revocado" && tieneCuenta { olvidar() } }

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
        // Los dos atajos, sólo en el simulador (B2-1): nunca en un iPhone, ni en Jiyu Dev. `deMentira` sólo lo pone
        // `Demo.current`, que fuera del simulador es nil; el `#if` es la segunda llave.
        #if targetEnvironment(simulator)
        if UserDefaults.standard.bool(forKey: "pearSinPresencia") && Channel.adminTools { return } // tests de interfaz (Jiyu Dev)
        if deMentira { return } // la cuenta de mentira de las capturas y los CuentaUITests: sin claves ni servidor
        #endif
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
