import CryptoKit
import SwiftUI

/// Estado de incidencias firmado (Fase 4, kill switch), igual que `Incident` en Android. La app lleva sólo la clave
/// pública Ed25519; el estado lo firma el PC de Toxbox y lo sirve el Worker `pear-music-estado`. Falla en abierto y
/// nunca acepta un contador menor que el último visto. Runbook: docs/RUNBOOK-INCIDENTES.md.
@MainActor
final class Incident: ObservableObject {
    static let shared = Incident()
    static let url = URL(string: "https://pear-music-estado.8toxbox8-69a.workers.dev/estado")!
    static let publicKey = "XBII1upMDF2PUHjTFrJwYEyHbbiUM3TT2O+9kHuTlgI="

    struct State: Equatable { var level = 0; var message = ""; var counter: Int64 = 0 }
    @Published private(set) var state = State()

    /// Modo seguro o bloqueo: se apagan actualizaciones, búsqueda remota, soporte, telemetría y cuenta.
    nonisolated static var restricted: Bool { UserDefaults.standard.integer(forKey: "incident.level") >= 2 }

    private let d = UserDefaults.standard
    private init() { load() }

    nonisolated static func verify(payload: String, sig: String, publicKey: String = publicKey) -> [String: Any]? {
        guard let keyData = Data(base64Encoded: publicKey), let sigData = Data(base64Encoded: sig),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(sigData, for: Data(payload.utf8)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
    }

    nonisolated static func effective(_ p: [String: Any], firstSeen: Date, now: Date) -> State {
        let expired = Double(p["expiresAt"] as? Int64 ?? Int64(p["expiresAt"] as? Int ?? 0)) < now.timeIntervalSince1970
        let ttl = (p["ttlHours"] as? Int).map { Double($0) * 3600 }
        let aged = ttl.map { now.timeIntervalSince(firstSeen) > $0 } ?? false
        let level = expired || aged ? 0 : min(3, max(0, p["level"] as? Int ?? 0))
        return State(level: level, message: level == 0 ? "" : p["message"] as? String ?? "", counter: Int64(p["counter"] as? Int ?? 0))
    }

    func load(now: Date = Date()) {
        guard let payload = d.string(forKey: "incident.payload"),
              let p = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else { return }
        apply(Self.effective(p, firstSeen: d.object(forKey: "incident.firstSeen") as? Date ?? now, now: now))
    }

    func refresh(now: Date = Date()) async {
        guard let (data, response) = try? await URLSession.shared.data(from: Self.url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        _ = accept(data, now: now)
    }

    @discardableResult
    func accept(_ envelope: Data, now: Date = Date(), publicKey: String = publicKey) -> Bool {
        guard let e = (try? JSONSerialization.jsonObject(with: envelope)) as? [String: Any],
              let payload = e["payload"] as? String, let sig = e["sig"] as? String,
              let p = Self.verify(payload: payload, sig: sig, publicKey: publicKey) else { return false }
        let counter = Int64(p["counter"] as? Int ?? 0)
        let last = Int64(d.integer(forKey: "incident.counter"))
        guard counter >= last else { return false } // anti-rollback
        let firstSeen = counter == last ? (d.object(forKey: "incident.firstSeen") as? Date ?? now) : now
        d.set(payload, forKey: "incident.payload")
        d.set(Int(counter), forKey: "incident.counter")
        d.set(firstSeen, forKey: "incident.firstSeen")
        apply(Self.effective(p, firstSeen: firstSeen, now: now))
        return true
    }

    private func apply(_ s: State) {
        state = s
        d.set(s.level, forKey: "incident.level")
    }
}

/// Aviso o modo seguro arriba; bloqueo total a pantalla completa (con «Escuchar mis descargas"). Igual que Android.
struct IncidentOverlay: View {
    @ObservedObject private var incident = Incident.shared
    @EnvironmentObject var downloads: DownloadStore
    @EnvironmentObject var player: Player
    @State private var dismissed: Int64 = -1

    var body: some View {
        let st = incident.state
        ZStack(alignment: .top) {
            if (1...2).contains(st.level) && dismissed != st.counter {
                let safe = st.level == 2
                HStack(spacing: 10) {
                    Image(systemName: safe ? "shield.lefthalf.filled" : "info.circle.fill").font(.title3)
                        .foregroundStyle(safe ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(safe ? L("Modo seguro") : "Aviso").font(.subheadline.weight(.semibold))
                        Text(st.message).font(.footnote).opacity(0.9).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(safe ? .white : .primary)
                    Spacer(minLength: 0)
                    if !safe {
                        Button { dismissed = st.counter } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel(L("Cerrar el aviso")).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 14).padding(.vertical, 10).padding(.trailing, 4)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(safe ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color(uiColor: .systemBackground))))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .padding(.horizontal, 12).padding(.top, 6)
                .transition(.opacity)
            }
            if st.level == 3 {
                VStack(spacing: 10) {
                    GradientIcon(systemName: "wrench.and.screwdriver.fill", palette: 3, size: 72).padding(.bottom, 14)
                    Text(L("En mantenimiento")).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text(st.message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text(L("Mientras tanto no se puede buscar, actualizar ni enviar nada. Tu música descargada sigue aquí."))
                        .font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    if !downloads.songs.isEmpty {
                        Button { let l = downloads.songs.shuffled(); player.play(l[0], in: l) } label: {
                            Text(L("Escuchar mis descargas")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle(prominent: true)).padding(.top, 18)
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
                .transition(.opacity)
            }
        }
        .animation(.uiEaseOut(0.3), value: st)
    }
}

/// Botón de pánico remoto de Pear Dev (Fase 4): publica un estado prefirmado en el PC con contraseña + TOTP.
enum Panic {
    static let base = URL(string: "https://pear-music-estado.8toxbox8-69a.workers.dev/panico")!

    static func call(_ path: String, _ body: [String: Any]) async -> (Int, [String: Any]) {
        var r = URLRequest(url: path.isEmpty ? base : base.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: r) else { return (0, ["error": L("Sin conexión con el servidor de estado.")]) }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:])
    }
}
