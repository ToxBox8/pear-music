import SwiftUI
import CryptoKit
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
        /// «minima_recomendada» (0.5 de x.1.1): por debajo, el aviso de versión antigua no se quita más de 24 h.
        var minimum: String?
    }

    @Published var pending: Release?
    private let defaults = UserDefaults.standard

    // MARK: Firma de publicación (fase de seguridad S4, x.1.1)
    /// Clave pública Ed25519 de publicación (32 bytes en base64). La privada vive fuera de línea (USB de Toxbox,
    /// `tools/publicar/firmar.mjs`). Creada el 21-10-2026; vacía, no se comprobaría nada.
    nonisolated static let publishKey = "8mBhBBxlDG8xNXRUxUuOEqFd4nSnCQtj7UFB8z6bbEk="

    enum Signature: Equatable { case good, missing, bad, noKey }

    /// `version.json.sig`, o nil si no está.
    private static func fetchSignature() async -> String? {
        let sigURL = URL(string: url.absoluteString + ".sig")!
        guard let (d, r) = try? await URLSession.shared.data(from: sigURL), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// x.1.1 «verificar y avisar»: sin firma se sigue (y se apunta); con firma que no cuadra **no se ofrece**
    /// descargar. En la versión siguiente, sin firma tampoco. Igual que Android.
    nonisolated static func signature(_ body: Data, sig: String?, publicKey: String = publishKey) -> Signature {
        guard !publicKey.isEmpty else { return .noKey }
        guard let sig = sig?.trimmingCharacters(in: .whitespacesAndNewlines), !sig.isEmpty else { return .missing }
        guard let keyData = Data(base64Encoded: publicKey), let sigData = Data(base64Encoded: sig),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(sigData, for: body) else { return .bad }
        return .good
    }

    // MARK: Versión simulada (2.2 de x.1.1, sólo Pear Dev): la app se cree otra versión para ver el aviso sin instalar.
    @Published private(set) var simulated: String? = Channel.adminTools ? UserDefaults.standard.string(forKey: "updates.fakeVersion") : nil

    /// Pone (o quita, con nil) la versión simulada y olvida la última comprobación para que se vea al volver.
    func simulate(_ version: String?) {
        guard Channel.adminTools else { return }
        defaults.set(version, forKey: "updates.fakeVersion")
        for k in ["updates.checked", "updates.snoozeVersion", "updates.staleUntil"] { defaults.removeObject(forKey: k) }
        simulated = version
    }

    private var installed: String { simulated ?? AboutView.version }

    // MARK: Versión antigua (0.5 de x.1.1)
    nonisolated static let staleDays = 21
    nonisolated static let staleMinors = 2

    /// Cuántas versiones menores va por detrás; otra mayor cuenta como muchas.
    nonisolated static func minorsBehind(_ installed: String, _ latest: String) -> Int {
        func core(_ v: String) -> [Int] {
            let c = (v.hasPrefix("v") ? String(v.dropFirst()) : v).split(separator: "-")[0].split(separator: ".").map { Int($0) ?? 0 }
            return c + [0, 0]
        }
        let i = core(installed), l = core(latest)
        if l[0] != i[0] { return l[0] > i[0] ? 99 : 0 }
        return max(0, l[1] - i[1])
    }

    /// ¿Es antigua? Por debajo de la mínima recomendada, 2 menores por detrás o 21 días sin actualizar.
    nonisolated static func isStale(installed: String, latest: String?, minimum: String?, pendingSince: Date?, now: Date) -> Bool {
        guard let latest, compare(latest, installed) > 0 else { return false }
        return (minimum.map { compare(installed, $0) < 0 } ?? false) || minorsBehind(installed, latest) >= staleMinors ||
            (pendingSince.map { now.timeIntervalSince($0) >= Double(staleDays) * 86_400 } ?? false)
    }

    /// Aviso de versión antigua en Inicio: nil = no; `true` = por debajo de la mínima (no se quita más de 24 h).
    @Published private(set) var stale: Bool?

    private func refreshStale(now: Date) {
        let latest = defaults.string(forKey: "updates.latest"), minimum = defaults.string(forKey: "updates.minimum")
        let old = Self.isStale(installed: installed, latest: latest, minimum: minimum,
                               pendingSince: defaults.object(forKey: "updates.pendingSince") as? Date, now: now)
        let until = defaults.object(forKey: "updates.staleUntil") as? Date ?? .distantPast
        stale = old && now >= until ? (minimum.map { Self.compare(installed, $0) < 0 } ?? false) : nil
    }

    /// «Ahora no»: 24 h si está por debajo de la mínima, 3 días si no.
    func dismissStale(now: Date = Date()) {
        defaults.set(now.addingTimeInterval(stale == true ? Self.snoozeSeconds : 3 * Self.snoozeSeconds), forKey: "updates.staleUntil")
        stale = nil
    }

    /// «Actualizar» desde el aviso de versión antigua: se vuelve a mirar ya y sale el aviso de siempre.
    func checkNow() async {
        for k in ["updates.checked", "updates.snoozeVersion", "updates.snoozeUntil"] { defaults.removeObject(forKey: k) }
        await check()
    }

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
                       fix: ios["fix"] as? Bool ?? false,
                       minimum: ios["minima_recomendada"] as? String)
    }

    func check(now: Date = Date()) async {
        // Pear Dev sólo comprueba con una versión simulada (2.2 de x.1.1): así se ve el aviso sin instalar nada.
        guard Channel.current == "usr" || simulated != nil else { return }
        refreshStale(now: now)
        let last = defaults.object(forKey: "updates.checked") as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= Self.checkEvery || defaults.string(forKey: "updates.pending") != nil else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: Self.url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        switch Self.signature(data, sig: await Self.fetchSignature()) {
        case .bad: Logs.w("Updates", "version.json con firma que no cuadra; no se ofrece"); return
        case .missing: Logs.d("Updates", "version.json sin firma (x.1.1 aún lo acepta)")
        default: break
        }
        guard let release = Self.parse(data) else { return }
        let installed = self.installed
        let newer = Self.compare(release.version, installed) > 0
        defaults.set(now, forKey: "updates.checked")
        defaults.set(newer ? release.version : nil, forKey: "updates.pending")
        defaults.set(release.version, forKey: "updates.latest")
        defaults.set(release.minimum, forKey: "updates.minimum")
        // Desde cuándo hay una versión nueva sin instalar (para los 21 días).
        defaults.set(newer ? (defaults.object(forKey: "updates.pendingSince") as? Date ?? now) : nil, forKey: "updates.pendingSince")
        refreshStale(now: now)
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
    /// No sale encima de la bienvenida, el recorrido, las historias ni las novedades: espera a que acaben (1.2 de
    /// x.1.1).
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("termsAcceptedAt") private var termsAcceptedAt = 0.0
    @AppStorage("introStage") private var introStage = ""
    @AppStorage("whatsNewSeen") private var whatsNewSeen = ""
    private var introDone: Bool { onboarded && termsAcceptedAt > 0 && introStage.isEmpty && whatsNewSeen == WhatsNew.current }

    func body(content: Content) -> some View {
        // La versión se captura al dibujar: así los botones la tienen aunque la alerta ya se esté cerrando.
        let release = updates.pending
        return content
            .task { await updates.check() }
            .alert(release.map { L("Pear Music {0}", $0.version) + ($0.title.isEmpty ? "" : ": \($0.title)") } ?? "",
                   isPresented: Binding(get: { updates.pending != nil && introDone }, set: { if !$0 { updates.pending = nil } })) {
                Button(L("Descargar")) { if let release { updates.download(release) } }
                Button(L("Recordarme mañana"), role: .cancel) { if let release { updates.snooze(release) } }
            } message: {
                Text((release?.highlights.map { "• \($0)" }.joined(separator: "\n") ?? "")
                     + L("\n\nSe actualiza encima con AltStore o SideStore: no pierdes tu biblioteca ni tus canciones descargadas."))
            }
    }
}

/// «Esta versión es antigua» en Inicio (0.5 de x.1.1): por debajo de la mínima recomendada, 2 versiones menores por
/// detrás o 21 días sin actualizar. «Actualizar» abre el aviso de siempre; «Ahora no» lo quita 24 h (por debajo de la
/// mínima) o 3 días. Igual que `OldVersionBanner` en Android.
struct OldVersionBanner: View {
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        if updates.stale != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.app.fill").font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Esta versión es antigua")).font(.headline)
                        Text(L("Puede fallar. Actualiza para tener los arreglos.")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    Button { Task { await updates.checkNow() } } label: { Text(L("Actualizar")).frame(maxWidth: .infinity) }
                        .buttonStyle(PillButtonStyle(prominent: true))
                    Button { withAnimation(.uiEaseOut(0.25)) { updates.dismissStale() } } label: { Text(L("Ahora no")).frame(maxWidth: .infinity) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
            .padding(18)
            .background(ThemeSurface(radius: 22))
            .padding(.horizontal)
        }
    }
}

/// Pear Dev con una versión simulada (2.2 de x.1.1): cinta fija arriba para no olvidarlo.
struct SimulatedVersionRibbon: View {
    @ObservedObject private var updates = Updates.shared
    var body: some View {
        if Channel.adminTools, let v = updates.simulated {
            Text(L("VERSIÓN SIMULADA: {0}", v))
                .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 3)
                .background(Color.orange.ignoresSafeArea(edges: .top))
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
    }
}

/// Los servidores de Pear no responden pero YouTube sí (2.5 de x.1.1), casi siempre por los bloqueos de LaLiga durante
/// el fútbol. Se puede quitar; vuelve a salir si en la siguiente apertura sigue igual. Igual que en Android.
struct ServersBlockedBanner: View {
    @ObservedObject private var incident = Incident.shared
    @State private var closed = false

    var body: some View {
        if incident.unreachable && !closed {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "soccerball").font(.title3).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Los servidores de Pear no responden")).font(.headline)
                    Text(L("La música sigue funcionando. Si hay fútbol, puede ser por los bloqueos de LaLiga: los avisos y el soporte vuelven al acabar el partido."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { withAnimation(.uiEaseOut(0.25)) { closed = true } } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).frame(width: 32, height: 32)
                }
                .accessibilityLabel(L("Cerrar el aviso"))
            }
            .padding(.leading, 18).padding(.vertical, 14).padding(.trailing, 8)
            .background(ThemeSurface(radius: 22))
            .padding(.horizontal)
        }
    }
}
