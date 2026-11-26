import Foundation

/// Lo que se ve de la sincronización (PULIR #3 y #4): en qué está ahora y cómo quedó la última. Sólo Foundation: los
/// textos se prueban en Linux (`scripts/tests/EstadoSyncTests.swift`). Igual que `SyncBiblioteca.Vista` y `estadoSync`
/// en Android.
enum FaseSync { case quieta, bajando, uniendo, subiendo
    var texto: String {
        switch self {
        case .bajando: return L("Bajando tu biblioteca…")
        case .uniendo: return L("Juntando lo de tus dispositivos…")
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
    /// Modo fútbol (Pulir 2 #2): hay Internet pero no se llega al servidor (`bloqueado`, ADR 0004 §9; en España, a
    /// veces, durante los partidos). No es un error: se explica y se vuelve a intentar solo en `reintentoEn` (ms).
    var bloqueado = false
    var reintentoEn: Double = 0
    /// El servidor ha dicho `demasiadas_sincronizaciones` (revisión del bloque 2, B2-6: 120 escrituras o 600 lecturas por
    /// hora y dispositivo): lo cambiado sigue pendiente y no se intenta hasta `reintentoEn`, cuando se reintenta sola.
    var limitado = false

    static var textoBloqueado: String { L("No se puede llegar al servidor") }
    static var detalleBloqueado: String { L("En España pasa a veces durante los partidos de fútbol. Se volverá a intentar sola.") }
    /// El mismo texto que `CuentaErrores.mensaje("demasiadas_sincronizaciones")` (aquí, sin depender de él: Linux).
    static var detalleLimitado: String { L("Has sincronizado muchas veces en poco rato. Lo pendiente se subirá solo dentro de un rato") }

    /// Cuánto esperar (ms) tras `demasiadas_sincronizaciones` (B2-6): el `Retry-After` (`esperaS`, segundos), entre 1 min
    /// y 1 h; sin él, 15 min. Igual que `SyncBiblioteca.esperaLimitado` en Android.
    static func esperaLimitado(_ esperaS: Int?) -> Double { Double(Swift.min(3600, Swift.max(60, esperaS ?? 900))) * 1000 }

    /// Cuánto esperar (ms) tras el intento `intento` (0, 1…) que ha dado `bloqueado`: 1, 2, 4, 8, 16 y luego 30 min
    /// como mucho, ±10 % al azar (que no vuelvan todos los móviles a la vez al acabar el partido). Igual en Android.
    static func esperaBloqueado(_ intento: Int, azar: Double = Double.random(in: 0...1)) -> Double {
        let base = Swift.min(30.0 * 60_000, 60_000 * pow(2, Double(Swift.min(intento, 5))))
        return (base * (0.9 + 0.2 * azar)).rounded(.down)
    }

    /// Si se puede intentar ya sin martillear: al abrir o tras un cambio no se intenta antes de `reintentoEn`.
    func puedeIntentar(ahora: Double = Date().timeIntervalSince1970 * 1000) -> Bool { !(bloqueado || limitado) || ahora >= reintentoEn }

    /// El pie de la fila (modo fútbol y límite de la sync).
    var detalle: String? { bloqueado ? VistaSync.detalleBloqueado : limitado ? VistaSync.detalleLimitado : nil }

    /// El icono (SF Symbol) y el texto de la fila de Ajustes › Cuenta.
    func estado(ahora: Double = Date().timeIntervalSince1970 * 1000) -> (icono: String, texto: String) {
        if fase != .quieta { return ("arrow.triangle.2.circlepath", fase.texto) }
        if bloqueado { return ("icloud.slash", VistaSync.textoBloqueado) }
        if limitado { return ("icloud.and.arrow.up", L("Pendiente de subir")) }
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

/// «No sincronizar esto» y su cuenta (revisión del bloque 2, B2-8; lo decidió Toxbox el 26-11): «Cerrar sesión» conserva
/// las marcas con la cuenta de la que eran; al volver a entrar en ella siguen, en otra se olvidan. Sólo Foundation: se
/// prueba en Linux (`EstadoSyncTests`). Igual que `SyncBiblioteca.olvidar` / `cuentaDeSoloAqui` en Android.
enum MarcasSoloAqui {
    /// Lo que se queda al salir de la cuenta: con `conservar` (sólo «Cerrar sesión») y algo marcado, las marcas y su
    /// cuenta; si no, nada.
    static func alSalir(_ marcas: Set<String>, cuenta: String?, conservar: Bool) -> (marcas: [String], cuenta: String)? {
        guard conservar, !marcas.isEmpty, let cuenta else { return nil }
        return (marcas.sorted(), cuenta)
    }
    /// Al sincronizar con la cuenta `id`: si las marcas eran de otra cuenta, fuera.
    static func siguen(en id: String, de: String?) -> Bool { de == nil || de == id }
}

/// El reintento del modo fútbol (Pulir 2 #2): espera y vuelve a intentar. Al empezar, deja de ser «el que espera»; así,
/// si ese intento vuelve a dar `bloqueado` y se programa el siguiente, no se cancela a sí mismo (antes `alFallar` hacía
/// `reintento?.cancel()` sobre su propia `Task` y las estadísticas no se subían nunca al reintentar; DECISIONS 100).
/// Sólo Foundation: se prueba en Linux (`scripts/tests/ReintentoTests.swift`). Igual que `ModoFutbolTest` en Android.
@MainActor
final class ReintentoBloqueado {
    private var tarea: Task<Void, Never>?
    private var turno = 0
    /// Hay un reintento esperando (no uno que ya ha empezado).
    var esperando: Bool { tarea != nil }

    /// Cancela el que espera (si lo hay) y programa [accion] dentro de [espera] ms.
    func programar(espera: Double, _ accion: @escaping @MainActor () async -> Void) {
        tarea?.cancel()
        turno += 1
        let mio = turno
        tarea = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Swift.max(0, espera) * 1_000_000))
            guard !Task.isCancelled else { return }
            if self?.turno == mio { self?.tarea = nil } // ya ha empezado: no es «el que espera»
            await accion()
        }
    }

    /// Cancela el que espera; uno que ya ha empezado sigue hasta el final.
    func cancelar() { tarea?.cancel(); tarea = nil }
}
