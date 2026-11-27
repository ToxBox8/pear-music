import Foundation

/// Los pulsos de la cuenta (docs/spec/puntos.md, bloque 3, 3-A): leer `GET /v1/puntos` y el cuerpo de un gasto. Sólo
/// Foundation (y `CuentaCripto` para el id): pasa los vectores de `shared/spec/vectores/puntos.json` en Linux con
/// `tools/spec/swift/probar.sh` (objetivo `CuentaApp`). La red, en `CuentaPear.pedirPulsos`; lo que se ve, en
/// `PulsosViews.swift`. Igual que `data/Pulsos.kt` en Android.
enum PulsosModel {
    static let rutaGastos = "/v1/puntos/gastos"
    static let motivos = ["fundador", "encuesta", "gasto", "ajuste"]
    private static let maxSeguro: Int64 = 9_007_199_254_740_991 // 2^53 − 1, el entero seguro de JS (el Worker)

    struct Movimiento: Equatable, Identifiable {
        let id: String
        let cantidad: Int64
        let motivo: String
        let ref: String?
        let saldoTras: Int64
        let ts: Int64
    }
    struct Pagina: Equatable {
        let saldo: Int64
        let movimientos: [Movimiento]
        let siguiente: String?
    }

    // MARK: Formato (puntos.md §3 y §4)

    /// id_operacion: 26 caracteres Crockford base32 con los 2 bits de relleno a cero (como los ids de cuenta.md §1).
    static func esIdOperacion(_ s: String) -> Bool {
        let alfabeto = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let c = Array(s)
        guard c.count == 26, c.allSatisfy(alfabeto.contains), let i = alfabeto.firstIndex(of: c[25]) else { return false }
        return i & 3 == 0
    }

    /// 16 bytes de `SecRandomCopyBytes` en base32: uno por gasto, y el mismo si se repite.
    static func nuevoIdOperacion() -> String { CuentaCripto.base32(CuentaCripto.aleatorio(16)) }

    /// El cuerpo exacto de un gasto: estas tres claves, en este orden y sin espacios (lo que se firma). nil si no vale.
    static func cuerpoGasto(_ idOperacion: String, _ cantidad: Int64, _ concepto: String) -> String? {
        guard esIdOperacion(idOperacion), (1...1_000_000).contains(cantidad),
              concepto.range(of: "^[a-z0-9][a-z0-9-]{0,39}$", options: .regularExpression) != nil else { return nil }
        return "{\"id_operacion\":\"\(idOperacion)\",\"cantidad\":\(cantidad),\"concepto\":\"\(concepto)\"}"
    }

    /// Un número entero de JSON (no `true`, no 1.5, no "10") dentro del entero seguro de JS.
    private static func entero(_ v: Any?) -> Int64? {
        guard let n = v as? NSNumber else { return nil }
        #if canImport(Darwin)
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
        #endif
        let d = n.doubleValue
        guard d.rounded() == d, abs(d) <= Double(maxSeguro) else { return nil }
        return n.int64Value
    }

    /// La respuesta de `GET /v1/puntos` (o `/antes/{cursor}`), o nil si algo no cuadra: entonces no se enseña y se
    /// queda el último saldo bueno. Los campos que no conoce se ignoran; un motivo que no conoce se enseña como «ajuste».
    static func leer(_ datos: Data) -> Pagina? {
        guard let o = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any],
              let saldo = entero(o["saldo"]), saldo >= 0, let lista = o["movimientos"] as? [Any] else { return nil }
        var siguiente: String?
        switch o["siguiente"] {
        case nil, is NSNull: siguiente = nil
        case let s as String where s.range(of: "^(0|[1-9][0-9]{0,14})-[0-9A-HJKMNP-TV-Z]{26}$", options: .regularExpression) != nil: siguiente = s
        default: return nil
        }
        var movimientos: [Movimiento] = []
        for x in lista {
            guard let m = x as? [String: Any], let id = m["id"] as? String,
                  let cantidad = entero(m["cantidad"]), cantidad != 0,
                  let tras = entero(m["saldo_tras"]), tras >= 0,
                  let ts = entero(m["ts"]), ts >= 0,
                  let motivo = m["motivo"] as? String else { return nil }
            let ref: String?
            switch m["ref"] {
            case nil, is NSNull: ref = nil
            case let s as String: ref = s
            default: return nil
            }
            movimientos.append(Movimiento(id: id, cantidad: cantidad, motivo: motivos.contains(motivo) ? motivo : "ajuste",
                                          ref: ref, saldoTras: tras, ts: ts))
        }
        return Pagina(saldo: saldo, movimientos: movimientos, siguiente: siguiente)
    }
    static func leer(_ texto: String) -> Pagina? { leer(Data(texto.utf8)) }
}
