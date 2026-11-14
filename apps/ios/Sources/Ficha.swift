import CryptoKit
import Foundation
import UIKit

/// Ficha del dispositivo e instalaciones activas (15-10-2026, lo pidió Toxbox; docs/TELEMETRIA.md), igual que
/// `Ficha` en Android.
///
/// - **Ficha:** al enviar un reporte o una sugerencia (el formulario lo avisa) se manda a `pear-music-api` la ficha
///   de este iPhone con el número de ticket: plataforma, variante, versión, sistema y modelo. Si la telemetría está
///   activada, también su identificador, para que el panel una el ticket con el rendimiento. El id de la ficha es el
///   SHA-256 del id anónimo del soporte (el mismo resumen que guarda `libremusic-soporte`).
/// - **Activos:** una vez al día la app suma uno al contador de su versión. No lleva ningún identificador.
/// - **Decisión sobre la telemetría:** tras contestar la privacidad, «sí» o «no» (y la anterior si cambia, para
///   restarla). Sólo contadores, sin identificador.
enum Ficha {
    private static let base = "https://pear-music-api.8toxbox8-69a.workers.dev/v1"

    static func id(_ supportDeviceID: String) -> String {
        let clean = supportDeviceID.trimmingCharacters(in: .whitespaces).lowercased()
        return SHA256.hash(data: Data(clean.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Tras un reporte con número de ticket. Si no llega, el ticket sigue igual.
    static func send(supportDeviceID: String, ticket: Int, kind: String, model: String) async {
        var body: [String: Any] = [
            "ficha": id(supportDeviceID),
            "platform": "ios",
            "channel": Channel.current,
            "app_version": AboutView.version,
            "os_version": "iOS \(await UIDevice.current.systemVersion)",
            "device_model": String(model.prefix(64)),
            "ticket": ticket,
            "kind": kind == "sugerencia" ? "sugerencia" : "error",
        ]
        if let install = await Telemetry.shared.installIfEnabled { body["install"] = install }
        _ = await post("/ficha", body)
    }

    /// Una vez al día (UTC): suma uno a las instalaciones activas de esta versión.
    static func pingActive(now: Date = Date()) async {
        guard !Incident.restricted else { return }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: now)
        guard UserDefaults.standard.string(forKey: "ficha.activeDay") != today else { return }
        guard let answer = await postForJSON("/activo", ["platform": "ios", "channel": Channel.current, "app_version": AboutView.version]) else { return }
        UserDefaults.standard.set(today, forKey: "ficha.activeDay")
        // «Forzar extracción» del panel (2.12 de x.1.1): Telemetry decide si se atiende (consentimiento y texto).
        if let orden = answer["orden"] as? String, !orden.isEmpty { await Telemetry.shared.sendForced(orden) }
    }

    /// Manda la decisión sobre la telemetría si aún no se ha mandado o ha cambiado.
    static func reportDecision() async {
        let d = UserDefaults.standard
        guard !Incident.restricted, d.double(forKey: "termsAcceptedAt") > 0 else { return }
        let now = d.bool(forKey: "telemetry.consent") ? "si" : "no"
        let sent = d.string(forKey: "ficha.decision")
        guard sent != now else { return }
        var body: [String: Any] = ["platform": "ios", "channel": Channel.current, "app_version": AboutView.version, "decision": now]
        if let sent { body["antes"] = sent }
        if await post("/consentimiento", body) { d.set(now, forKey: "ficha.decision") }
    }

    /// El cuerpo de la respuesta si fue bien (vacío = `[:]`), o nil.
    private static func postForJSON(_ path: String, _ body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: base + path), let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = data
        guard let (out, resp) = try? await URLSession.shared.data(for: r), (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { return nil }
        return (try? JSONSerialization.jsonObject(with: out)) as? [String: Any] ?? [:]
    }

    private static func post(_ path: String, _ body: [String: Any]) async -> Bool {
        guard let url = URL(string: base + path), let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = data
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
