import Foundation
import UIKit

/// Telemetría de rendimiento (Fase 2.1, ADR 0001), igual que `Telemetry` en Android. **Apagada por defecto**:
/// sin el consentimiento (separado de la cuenta; se retira en Ajustes › Ayuda y soporte › Tus datos) no se mide
/// ni se envía nada. Campos exactos en docs/TELEMETRIA.md; el servidor rechaza cualquier otro.
///
/// **Fase 4b: un informe por semana.** Cada sesión se apunta en el móvil y, al empezar una semana ISO nueva, se
/// envía el resumen de la anterior (medianas y número de sesiones). **Pear Dev es sólo manual** (lo decidió Toxbox
/// el 15-10-2026): mide siempre en el móvil, nunca envía sola, y «Enviar ahora» manda la semana en curso con los
/// campos elegidos.
@MainActor
final class Telemetry: NSObject {
    static let shared = Telemetry()
    static let endpoint = URL(string: "https://pear-music-api.8toxbox8-69a.workers.dev/v1/telemetria")!
    private let defaults = UserDefaults.standard

    private var link: CADisplayLink?
    private var frames: [CFTimeInterval] = []
    private var last: CFTimeInterval = 0
    private var sessionStart = Date()
    private var startupMs: Int?
    private var firstSession = true

    var enabled: Bool { Channel.adminTools || defaults.bool(forKey: "telemetry.consent") }
    var asked: Bool { defaults.object(forKey: "telemetry.consent") != nil }

    /// El identificador de la telemetría, sólo si está activada (para unirla a la ficha del soporte).
    var installIfEnabled: String? { enabled ? install : nil }

    /// Versión del texto de consentimiento que se enseña. La 2 añadirá «y a veces antes, si el responsable lo pide»
    /// (2.12 de x.1.1): **hasta que Toxbox apruebe ese texto, sigue en 1** y nadie recibe el resumen «forzado».
    static let consentText = 1
    /// Desde qué texto aceptado se atiende «forzar».
    private static let forcedFromText = 2

    func setConsent(_ on: Bool) {
        let was = enabled
        defaults.set(on, forKey: "telemetry.consent")
        defaults.set(Date(), forKey: "telemetry.consentAt")
        defaults.set(on ? Self.consentText : 0, forKey: "telemetry.consentText")
        if was && !on, let old = defaults.string(forKey: "telemetry.install") {
            for k in ["telemetry.install", "telemetry.week", "telemetry.pending"] { defaults.removeObject(forKey: k) }
            Task.detached { await Self.deleteRemote(old) }
        }
    }

    private var install: String {
        if let id = defaults.string(forKey: "telemetry.install") { return id }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let id = bytes.map { String(format: "%02x", $0) }.joined()
        defaults.set(id, forKey: "telemetry.install")
        return id
    }

    func foreground() {
        guard enabled, link == nil else { return }
        sessionStart = Date()
        frames.removeAll(keepingCapacity: true)
        last = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        if last > 0, frames.count < 20_000 { frames.append(l.timestamp - last) }
        if firstSession, startupMs == nil, let start = Self.processStart { startupMs = Int(Date().timeIntervalSince(start) * 1000) }
        last = l.timestamp
    }

    func background() {
        guard let l = link else { return }
        l.invalidate()
        link = nil
        guard enabled else { return }
        record(session())
        firstSession = false
        startupMs = nil
        Task { await flushIfDue() }
    }

    /// Lo medido en esta sesión.
    private func session() -> [String: Double] {
        let sorted = frames.sorted()
        var out: [String: Double] = ["session_minutes": Double(min(1439, max(0, Int(Date().timeIntervalSince(sessionStart) / 60))))]
        if let s = startupMs, (0..<120_000).contains(s) { out["startup_ms"] = Double(s) }
        if !sorted.isEmpty {
            let median = sorted[sorted.count / 2]
            if median > 0 { out["fps_median"] = min(240, 1 / median) }
            let budget = 1.0 / Double(max(60, UIScreen.main.maximumFramesPerSecond))
            out["jank_percent"] = Double(sorted.filter { $0 > budget * 1.5 }.count) * 100 / Double(sorted.count)
        }
        if let mb = Self.memoryMB { out["memory_mb"] = Double(mb) }
        return out
    }

    /// Semana ISO, «2026-W42».
    nonisolated static func isoWeek(_ date: Date = Date()) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    private struct Bucket: Codable { var week: String; var sessions: [[String: Double]] }

    private func load(_ key: String) -> Bucket? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Bucket.self, from: $0) }
    }
    private func save(_ b: Bucket?, _ key: String) {
        if let b, let d = try? JSONEncoder().encode(b) { defaults.set(d, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private func record(_ s: [String: Double]) {
        let week = Self.isoWeek()
        var b = load("telemetry.week") ?? Bucket(week: week, sessions: [])
        if b.week != week {
            if !b.sessions.isEmpty { save(b, "telemetry.pending") }
            b = Bucket(week: week, sessions: [])
        }
        if b.sessions.count < 200 { b.sessions.append(s) }
        save(b, "telemetry.week")
    }

    /// Campos que se pueden elegir en «Enviar ahora» de Pear Dev (igual que Android).
    static var choosable: [(String, String)] { [
        ("os_version", L("Versión del sistema")), ("device_model", "Modelo"), ("sessions", "Sesiones"), ("startup_ms", "Arranque"),
        ("fps_median", "FPS"), ("jank_percent", "Tirones"), ("memory_mb", "Memoria"), ("session_minutes", L("Minutos por sesión")),
    ] }

    /// Resumen de una semana: medianas de cada medida y número de sesiones.
    private func summarize(_ b: Bucket, kind: String, only: Set<String>? = nil) -> [String: Any] {
        func median(_ k: String) -> Double? {
            let v = b.sessions.compactMap { $0[k] }.sorted()
            return v.isEmpty ? nil : v[v.count / 2]
        }
        var all: [String: Any] = [
            "os_version": String(UIDevice.current.systemVersion.prefix(32)), "device_model": String(Self.model.prefix(64)),
            "sessions": b.sessions.count,
        ]
        if let v = median("startup_ms") { all["startup_ms"] = Int(v) }
        if let v = median("fps_median") { all["fps_median"] = (v * 10).rounded() / 10 }
        if let v = median("jank_percent") { all["jank_percent"] = (v * 10).rounded() / 10 }
        if let v = median("memory_mb") { all["memory_mb"] = Int(v) }
        if let v = median("session_minutes") { all["session_minutes"] = Int(v) }
        var out: [String: Any] = [
            "install": install, "platform": "ios", "channel": Channel.current, "app_version": AboutView.version,
            "week": b.week, "kind": kind,
        ]
        for (k, v) in all where only == nil || only!.contains(k) { out[k] = v }
        return out
    }

    private static func post(_ body: [String: Any]) async -> Bool {
        var r = URLRequest(url: endpoint)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Envía la semana que ya acabó (al salir de la app y en el refresco de fondo de los avisos).
    func flushIfDue() async {
        guard enabled, !Incident.restricted, !Channel.adminTools else { return } // Pear Dev: sólo «Enviar ahora»
        let now = Self.isoWeek()
        if let b = load("telemetry.week"), b.week != now, !b.sessions.isEmpty {
            save(b, "telemetry.pending")
            save(Bucket(week: now, sessions: []), "telemetry.week")
        }
        guard let pending = load("telemetry.pending") else { return }
        if await Self.post(summarize(pending, kind: "semanal")) { save(nil, "telemetry.pending") }
    }

    /// «Forzar extracción» del panel (2.12 de x.1.1): la orden llega en el latido diario (`/v1/activo`). Sólo la atiende
    /// quien aceptó un texto que lo dice, en la variante pública; Pear Dev y pref no tienen envío automático. Manda la
    /// semana en curso una vez por orden. Igual que Android.
    func sendForced(_ orden: String) async {
        guard Channel.current == "usr", defaults.bool(forKey: "telemetry.consent"), !Incident.restricted,
              defaults.integer(forKey: "telemetry.consentText") >= Self.forcedFromText,
              defaults.string(forKey: "telemetry.lastOrden") != orden else { return }
        let body = summarize(load("telemetry.week") ?? Bucket(week: Self.isoWeek(), sessions: []), kind: "forzado")
        if await Self.post(body) { defaults.set(orden, forKey: "telemetry.lastOrden") }
    }

    /// Pear Dev: manda ya la semana en curso con los campos elegidos. Devuelve cuántos campos se enviaron, o nil.
    func sendNow(only: Set<String>) async -> Int? {
        guard Channel.adminTools else { return nil }
        let body = summarize(load("telemetry.week") ?? Bucket(week: Self.isoWeek(), sessions: []), kind: "manual", only: only)
        return await Self.post(body) ? body.count : nil
    }

    /// Para «Borrar todos mis datos»: borra en el servidor lo enviado desde esta instalación.
    func deleteRemoteNow() async {
        guard let id = defaults.string(forKey: "telemetry.install") else { return }
        await Self.deleteRemote(id)
    }

    nonisolated static func deleteRemote(_ install: String) async {
        var r = URLRequest(url: endpoint, timeoutInterval: 3)
        r.httpMethod = "DELETE"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["install": install])
        _ = try? await URLSession.shared.data(for: r)
    }

    private static var model: String {
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// Cuándo arrancó el proceso (sysctl), para medir el arranque hasta el primer fotograma.
    private static var processStart: Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let t = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000)
    }

    private static var memoryMB: Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : nil
    }
}
