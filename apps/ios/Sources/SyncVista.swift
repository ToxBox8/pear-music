import Foundation

/// Lo que se ve de la sincronización (PULIR #3 y #4): en qué está ahora y cómo quedó la última. Sólo Foundation: los
/// textos se prueban en Linux (`scripts/tests/EstadoSyncTests.swift`). Igual que `SyncBiblioteca.Vista` y `estadoSync`
/// en Android.
enum FaseSync { case quieta, bajando, uniendo, subiendo
    var texto: String {
        switch self {
        case .bajando: return L("Bajando tu biblioteca…")
        case .uniendo: return L("Juntando lo de tus móviles…")
        case .subiendo: return L("Subiendo tu biblioteca…")
        case .quieta: return L("Biblioteca al día")
        }
    }
}

struct VistaSync: Equatable {
    var fase: FaseSync = .quieta
    /// ms de la última vez que la nube y el móvil quedaron iguales; 0 = nunca.
    var ultimaOk: Double = 0
    var pendiente = false
    /// La última vez no había red (o Cloudflare bloqueado): «se subirá luego».
    var sinRed = false
    /// Al acabar, se han puesto cambios de otro móvil: la cápsula dice «Biblioteca al día» un momento (ms).
    var traido: Double = 0

    /// El icono (SF Symbol) y el texto de la fila de Ajustes › Cuenta.
    func estado(ahora: Double = Date().timeIntervalSince1970 * 1000) -> (icono: String, texto: String) {
        if fase != .quieta { return ("arrow.triangle.2.circlepath", fase.texto) }
        if sinRed { return ("icloud.slash", L("Sin conexión: se subirá luego")) }
        if pendiente { return ("icloud.and.arrow.up", L("Pendiente de subir")) }
        if ultimaOk > 0 { return ("checkmark.icloud", L("Sincronizado {0}", VistaSync.haceCuanto(ultimaOk, ahora))) }
        return ("icloud", L("Aún no se ha sincronizado"))
    }

    /// «ahora mismo», «hace 5 min», «hace 3 h» o «el 18 nov 2026», en el idioma de la app (no en el del sistema).
    static func haceCuanto(_ ms: Double, _ ahora: Double) -> String {
        let min = Int((ahora - ms) / 60_000)
        if min < 1 { return L("ahora mismo") }
        if min < 60 { return L("hace {0} min", String(min)) }
        if min < 24 * 60 { return L("hace {0} h", String(min / 60)) }
        let f = DateFormatter()
        f.locale = Locale(identifier: I18n.current == "va" ? "ca" : I18n.current)
        f.dateStyle = .medium; f.timeStyle = .none
        return L("el {0}", f.string(from: Date(timeIntervalSince1970: ms / 1000)))
    }
}
