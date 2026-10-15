import SwiftUI
import UIKit

/// Avisos de versión nueva (Fase 2.2), igual que `Updates` en Android: `version.json` de la web como mucho cada
/// 6 h, «Recordarme mañana» lo aplaza 24 h. iOS no deja que una app se instale sola, así que «Descargar» abre la
/// fuente de AltStore o SideStore, que **actualiza encima** (mismo bundle id: se conservan la biblioteca, los
/// ajustes y las canciones descargadas); si no hay ninguna, la guía de la web. Sólo en la variante usr. En modo
/// seguro (kill switch nivel 2 o más) sólo se ofrecen las versiones marcadas como arreglo (`"fix": true`).
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()
    static let url = URL(string: "https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev/version.json")!
    static let snoozeSeconds: TimeInterval = 24 * 3600
    private static let checkEvery: TimeInterval = 6 * 3600

    struct Release: Equatable {
        let version, title: String
        let highlights: [String]
        let altstore, sidestore, guide: URL?
        var fix = false
    }

    @Published var pending: Release?
    private let defaults = UserDefaults.standard

    /// -1, 0 o 1. Semver con pre-releases (2.0.0-pre1 < 2.0.0). Mismo algoritmo que Android.
    nonisolated static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ v: String) -> ([Int], String?) {
            var clean = v.trimmingCharacters(in: .whitespaces)
            if clean.hasPrefix("v") { clean.removeFirst() }
            let pieces = clean.split(separator: "-", maxSplits: 1).map(String.init)
            var core = pieces[0].split(separator: ".").map { Int($0) ?? 0 }
            while core.count < 3 { core.append(0) }
            return (core, pieces.count > 1 ? pieces[1] : nil)
        }
        let (ca, pa) = parts(a), (cb, pb) = parts(b)
        for i in 0..<3 where ca[i] != cb[i] { return ca[i] < cb[i] ? -1 : 1 }
        switch (pa, pb) {
        case (nil, nil): return 0
        case (nil, _): return 1
        case (_, nil): return -1
        case let (x?, y?):
            let nx = Int(x.filter(\.isNumber)), ny = Int(y.filter(\.isNumber))
            if let nx, let ny, x.filter({ !$0.isNumber }) == y.filter({ !$0.isNumber }) { return nx == ny ? 0 : (nx < ny ? -1 : 1) }
            return x == y ? 0 : (x < y ? -1 : 1)
        }
    }

    nonisolated static func shouldShow(_ r: Release, installed: String, snoozedVersion: String?, snoozedUntil: Date, now: Date) -> Bool {
        compare(r.version, installed) > 0 && !(snoozedVersion == r.version && now < snoozedUntil)
    }

    nonisolated static func parse(_ data: Data) -> Release? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ios = root["ios"] as? [String: Any], let version = ios["version"] as? String else { return nil }
        return Release(version: version, title: ios["title"] as? String ?? "", highlights: ios["highlights"] as? [String] ?? [],
                       altstore: (ios["altstore"] as? String).flatMap(URL.init(string:)),
                       sidestore: (ios["sidestore"] as? String).flatMap(URL.init(string:)),
                       guide: (ios["guide"] as? String).flatMap(URL.init(string:)),
                       fix: ios["fix"] as? Bool ?? false)
    }

    func check(now: Date = Date()) async {
        guard Channel.current == "usr" else { return }
        let last = defaults.object(forKey: "updates.checked") as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= Self.checkEvery || defaults.string(forKey: "updates.pending") != nil else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: Self.url),
              (response as? HTTPURLResponse)?.statusCode == 200, let release = Self.parse(data) else { return }
        let installed = AboutView.version
        defaults.set(now, forKey: "updates.checked")
        defaults.set(Self.compare(release.version, installed) > 0 ? release.version : nil, forKey: "updates.pending")
        if Self.allowed(release, restricted: Incident.restricted), Self.shouldShow(release, installed: installed, snoozedVersion: defaults.string(forKey: "updates.snoozeVersion"),
                           snoozedUntil: defaults.object(forKey: "updates.snoozeUntil") as? Date ?? .distantPast, now: now) {
            pending = release
        }
    }

    /// En modo seguro sólo se ofrece una versión de arreglo: frena la mala sin bloquear la que la corrige.
    nonisolated static func allowed(_ r: Release, restricted: Bool) -> Bool { !restricted || r.fix }

    func snooze(_ r: Release, now: Date = Date()) {
        defaults.set(r.version, forKey: "updates.snoozeVersion")
        defaults.set(now.addingTimeInterval(Self.snoozeSeconds), forKey: "updates.snoozeUntil")
        pending = nil
    }

    /// AltStore, si no SideStore, si no la guía de la web.
    func download(_ r: Release) {
        pending = nil
        let app = UIApplication.shared
        if let u = r.altstore, app.canOpenURL(u) { app.open(u) }
        else if let u = r.sidestore, app.canOpenURL(u) { app.open(u) }
        else if let u = r.guide { app.open(u) }
    }
}

/// El aviso: novedades, «Descargar» y «Recordarme mañana». Se cuelga de la vista raíz.
struct UpdateAlert: ViewModifier {
    @ObservedObject var updates = Updates.shared

    func body(content: Content) -> some View {
        // La versión se captura al dibujar: así los botones la tienen aunque la alerta ya se esté cerrando.
        let release = updates.pending
        return content
            .task { await updates.check() }
            .alert(release.map { L("Pear Music {0}", $0.version) + ($0.title.isEmpty ? "" : ": \($0.title)") } ?? "",
                   isPresented: Binding(get: { updates.pending != nil }, set: { if !$0 { updates.pending = nil } })) {
                Button(L("Descargar")) { if let release { updates.download(release) } }
                Button(L("Recordarme mañana"), role: .cancel) { if let release { updates.snooze(release) } }
            } message: {
                Text((release?.highlights.map { "• \($0)" }.joined(separator: "\n") ?? "")
                     + L("\n\nSe actualiza encima con AltStore o SideStore: no pierdes tu biblioteca ni tus canciones descargadas."))
            }
    }
}
