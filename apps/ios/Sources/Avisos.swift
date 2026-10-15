import SwiftUI
import BackgroundTasks
import UserNotifications

// MARK: - Avisos (canal privado de Discord → web → app)
//
// Lo que se escribe en el canal privado de avisos sale en la web (`/api/avisos`) y aquí: campana con los no leídos en
// Inicio, pantalla Avisos y notificación del móvil. Igual que `avisos/Avisos.kt` en Android. Sólo se hace un GET sin
// datos del usuario ni identificadores.

struct Aviso: Identifiable, Equatable {
    let id: String
    let importante: Bool
    let titulo: String
    let texto: String
    let enlace: URL?
    let fecha: Date
    /// Respuesta del soporte SÓLO para este iPhone (tickets, Cierre 1.0): «abierto», «mensaje», «fiesta» o
    /// «en-ello». nil = aviso para todos. Igual que Android.
    var personal: String? = nil
    var ticket: Int? = nil
}

enum EstadoAvisos: Equatable {
    /// Primera carga sin copia guardada.
    case cargando
    /// `sinConexion`: la última descarga falló y se ve la copia guardada.
    case listo([Aviso], sinConexion: Bool)
    /// Falló la descarga y no hay copia guardada.
    case error
}

@MainActor
final class AvisosStore: ObservableObject {
    static let shared = AvisosStore()
    static let url = URL(string: "https://libremusic-landing.8toxbox8-69a.workers.dev/api/avisos")!
    /// Sólo se notifica en el móvil lo publicado en las últimas 48 h (como SimpMusic con su blog).
    static let ventanaNotificar: TimeInterval = 48 * 3600
    static let tareaFondo = "com.example.libremusic.avisos"

    @Published private(set) var estado: EstadoAvisos = .cargando
    @Published private(set) var sinLeer = 0
    /// true al pulsar una notificación de aviso: Inicio abre la pantalla y lo vuelve a poner a false.
    @Published var abrir = false

    private let d = UserDefaults.standard
    private enum Clave {
        static let json = "avisos.ultimaRespuesta"
        static let vistos = "avisos.vistos"
        static let notificados = "avisos.notificados"
        static let notificar = "avisos.notificar"
        static let personales = "avisos.personales"
    }

    var notificar: Bool {
        get { d.object(forKey: Clave.notificar) as? Bool ?? true }
        set {
            d.set(newValue, forKey: Clave.notificar)
            if newValue { Self.programarFondo() } else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.tareaFondo) }
        }
    }

    /// Pinta la copia guardada al instante; luego hay que llamar a `refrescar()`.
    func cargarCopia() {
        guard let data = d.data(forKey: Clave.json), let generales = try? Self.parsear(data) else { return }
        let avisos = Self.juntar(generales, d.data(forKey: Clave.personales).flatMap { try? Self.parsearPersonales($0) } ?? [])
        estado = .listo(avisos, sinConexion: false)
        recalcularSinLeer(avisos)
    }

    /// Descarga los avisos. Devuelve la lista nueva, o nil si no se pudo.
    @discardableResult
    func refrescar() async -> [Aviso]? {
        var req = URLRequest(url: Self.url, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200, data.count <= 256 * 1024,
              let generales = try? Self.parsear(data) else {
            if case .listo(let l, _) = estado { estado = .listo(l, sinConexion: true) } else { estado = .error }
            return nil
        }
        let avisos = Self.juntar(generales, await personales())
        d.set(data, forKey: Clave.json)
        estado = .listo(avisos, sinConexion: false)
        recalcularSinLeer(avisos)
        return avisos
    }

    /// Al pasar la app a primer plano. Lo recibido así ya se ve en la campana: queda como notificado y el trabajo
    /// de fondo no lo vuelve a sacar como notificación.
    func refrescarAlAbrir() async {
        guard let avisos = await refrescar() else { return }
        _ = pendientesDeNotificar(avisos)
    }

    /// Al abrir Avisos: todo lo que hay pasa a visto y la campana se apaga.
    func marcarVistos() {
        guard case .listo(let avisos, _) = estado else { return }
        // Sólo se guardan ids que siguen existiendo, para que la lista no crezca para siempre.
        d.set(avisos.map(\.id), forKey: Clave.vistos)
        sinLeer = 0
    }

    /// Avisos aún no notificados y de las últimas 48 h. Todos los recibidos quedan apuntados como notificados:
    /// un aviso viejo nunca salta y uno nuevo salta una sola vez.
    func pendientesDeNotificar(_ avisos: [Aviso], ahora: Date = Date()) -> [Aviso] {
        let ya = Set(d.stringArray(forKey: Clave.notificados) ?? [])
        let nuevos = avisos.filter { !ya.contains($0.id) && ahora.timeIntervalSince($0.fecha) <= Self.ventanaNotificar }
        d.set(avisos.map(\.id), forKey: Clave.notificados)
        return nuevos
    }

    private func recalcularSinLeer(_ avisos: [Aviso]) {
        let vistos = Set(d.stringArray(forKey: Clave.vistos) ?? [])
        sinLeer = avisos.filter { !vistos.contains($0.id) }.count
    }

    // MARK: Contrato del JSON (versión 1)

    enum Fallo: Error { case formato, version, estado }

    /// Falla si no es la versión 1 o el estado no es «ok» ni «sin_configurar» (que es una lista vacía).
    nonisolated static func juntar(_ generales: [Aviso], _ personales: [Aviso]) -> [Aviso] {
        (generales + personales).sorted { $0.fecha > $1.fecha }
    }

    /// Las respuestas del soporte a los tickets de este iPhone; sólo si ya se envió algo desde aquí.
    private func personales() async -> [Aviso] {
        let guardado = d.data(forKey: Clave.personales).flatMap { try? Self.parsearPersonales($0) } ?? []
        guard let device = SupportClient.sentDeviceID,
              var url = URLComponents(string: "https://libremusic-soporte.8toxbox8-69a.workers.dev/mensajes") else { return guardado }
        url.queryItems = [URLQueryItem(name: "device", value: device)]
        guard let u = url.url, let (data, resp) = try? await URLSession.shared.data(from: u),
              (resp as? HTTPURLResponse)?.statusCode == 200, let lista = try? Self.parsearPersonales(data) else { return guardado }
        d.set(data, forKey: Clave.personales)
        return lista
    }

    nonisolated static func parsearPersonales(_ data: Data) throws -> [Aviso] {
        guard let raiz = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lista = raiz["mensajes"] as? [[String: Any]] else { throw Fallo.formato }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tipos: Set<String> = ["abierto", "mensaje", "fiesta", "en-ello"]
        return lista.compactMap { m in
            guard let id = m["id"] as? String, let at = m["at"] as? String, let fecha = iso.date(from: at) ?? ISO8601DateFormatter().date(from: at) else { return nil }
            let tipo = m["tipo"] as? String ?? "mensaje"
            return Aviso(id: "ticket-" + id, importante: false, titulo: m["title"] as? String ?? L("Respuesta de Pear Music"),
                         texto: m["text"] as? String ?? "", enlace: nil, fecha: fecha,
                         personal: tipos.contains(tipo) ? tipo : "mensaje", ticket: m["ticket"] as? Int)
        }
    }

    nonisolated static func parsear(_ data: Data) throws -> [Aviso] {
        guard let raiz = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Fallo.formato }
        guard raiz["version"] as? Int == 1 else { throw Fallo.version }
        guard let estado = raiz["estado"] as? String, estado == "ok" || estado == "sin_configurar" else { throw Fallo.estado }
        guard let lista = raiz["avisos"] as? [[String: Any]] else { throw Fallo.formato }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoSimple = ISO8601DateFormatter()
        return try lista.map { a in
            guard let id = a["id"] as? String, let titulo = a["titulo"] as? String, let f = a["fecha"] as? String,
                  let fecha = iso.date(from: f) ?? isoSimple.date(from: f) else { throw Fallo.formato }
            // Sólo http(s): se abre con un toque y otro esquema no debe llegar ahí.
            let enlace = (a["enlace"] as? String).flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
            return Aviso(id: id, importante: a["tipo"] as? String == "importante", titulo: titulo,
                         texto: a["texto"] as? String ?? "", enlace: enlace, fecha: fecha)
        }
    }

    // MARK: Segundo plano y notificaciones (como el RssFeedNotifyWork de SimpMusic)

    /// Se llama en el `init` de la app: iOS exige registrar la tarea antes de acabar de arrancar.
    nonisolated static func registrarFondo() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: tareaFondo, using: nil) { tarea in
            programarFondo()
            let trabajo = Task { @MainActor in
                // Estado de incidencias (Fase 4) y resumen semanal de telemetría (Fase 4b), igual que el AvisosWorker de Android.
                await Incident.shared.refresh()
                await Telemetry.shared.flushIfDue()
                let store = AvisosStore.shared
                if let avisos = await store.refrescar(), store.notificar {
                    for aviso in store.pendientesDeNotificar(avisos) { await notificar(aviso) }
                }
                tarea.setTaskCompleted(success: true)
            }
            tarea.expirationHandler = { trabajo.cancel() }
        }
    }

    /// Pide a iOS una comprobación dentro de 15 min como pronto (iOS decide cuándo, según el uso de la app).
    nonisolated static func programarFondo() {
        let req = BGAppRefreshTaskRequest(identifier: tareaFondo)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// Permiso de notificaciones la primera vez que se abre Avisos; si se deniega, el interruptor se apaga.
    func pedirPermiso() async {
        let centro = UNUserNotificationCenter.current()
        let ajustes = await centro.notificationSettings()
        guard ajustes.authorizationStatus == .notDetermined else {
            if ajustes.authorizationStatus == .denied { notificar = false }
            return
        }
        let concedido = (try? await centro.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if !concedido { notificar = false }
    }

    nonisolated static func notificar(_ aviso: Aviso) async {
        let c = UNMutableNotificationContent()
        c.title = aviso.titulo
        c.body = aviso.texto
        c.sound = .default
        c.threadIdentifier = "avisos"
        c.userInfo = ["abrirAvisos": true]
        c.interruptionLevel = aviso.importante ? .timeSensitive : .active
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "aviso-\(aviso.id)", content: c, trigger: nil))
    }
}

/// Pulsar una notificación de aviso abre Avisos (también con la app abierta) y deja verlas con la app delante.
final class AvisosNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AvisosNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["abrirAvisos"] as? Bool == true {
            await MainActor.run { AvisosStore.shared.abrir = true }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// Igual que la web y Android: «ahora mismo», «hace 5 min», «hace 3 h», «ayer», «hace 3 días» o la fecha.
func haceCuanto(_ fecha: Date, ahora: Date = Date()) -> String {
    let seg = max(0, ahora.timeIntervalSince(fecha))
    if seg < 60 { return L("ahora mismo") }
    let min = (seg / 60).rounded()
    if min < 60 { return L("hace {0} min", Int(min)) }
    let h = (min / 60).rounded()
    if h < 24 { return L("hace {0} h", Int(h)) }
    let d = (h / 24).rounded()
    if d < 7 { return d == 1 ? "ayer" : L("hace {0} días", Int(d)) }
    let f = DateFormatter()
    f.locale = Locale(identifier: "es_ES")
    f.dateFormat = "d MMM yyyy"
    return f.string(from: fecha)
}

// MARK: - Interfaz

/// Campana de la barra de Inicio, junto al Jam, con los no leídos («9+» si pasan de nueve).
struct AvisosBell: View {
    @ObservedObject private var store = AvisosStore.shared
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: store.sinLeer > 0 ? "bell.fill" : "bell")
                .overlay(alignment: .topTrailing) {
                    if store.sinLeer > 0 {
                        Text(store.sinLeer > 9 ? "9+" : "\(store.sinLeer)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: 9, y: -8)
                    }
                }
        }
        .accessibilityLabel(store.sinLeer > 0 ? L("Avisos, {0} sin leer", store.sinLeer) : L("Avisos"))
    }
}

struct AvisosView: View {
    @ObservedObject private var store = AvisosStore.shared
    @State private var notificar = AvisosStore.shared.notificar

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $notificar) {
                    SettingsRow(icon: "bell.badge.fill", palette: 4, title: L("Notificar en el móvil"), value: nil)
                }
                .onChange(of: notificar) { nuevo in
                    store.notificar = nuevo
                    if nuevo { Task { await store.pedirPermiso(); notificar = store.notificar } }
                }
            } footer: {
                Text(L("Comprueba de vez en cuando si hay avisos nuevos. Sólo se pide la lista de avisos, sin enviar nada tuyo."))
            }
            .glassRow()
            switch store.estado {
            case .cargando:
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            case .error:
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "icloud.slash").font(.largeTitle).foregroundStyle(.tertiary)
                        Text(L("No se han podido cargar")).font(.headline)
                        Text(L("Comprueba la conexión y vuelve a intentarlo.")).font(.subheadline).foregroundStyle(.secondary)
                        Button(L("Reintentar")) { Task { await store.refrescar() } }.buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24).multilineTextAlignment(.center)
                }
            case .listo(let avisos, let sinConexion):
                if avisos.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "bell.slash").font(.largeTitle).foregroundStyle(.tertiary)
                            Text(L("No hay avisos")).font(.headline)
                            Text(L("Cuando haya algo importante saldrá aquí.")).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24).multilineTextAlignment(.center)
                    }
                } else {
                    Section {
                        ForEach(avisos) { AvisoRow(aviso: $0) }
                    } header: {
                        if sinConexion { Text(L("Sin conexión")) }
                    } footer: {
                        if sinConexion { Text(L("Estos son los últimos avisos guardados.")) }
                    }
                    .glassRow()
                }
            }
        }
        .navigationTitle(L("Avisos"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refrescar() }
        .task {
            await store.refrescar()
            if store.notificar { await store.pedirPermiso(); notificar = store.notificar }
        }
        // Lo que se ve pasa a leído y la campana se apaga (también lo que llegue mientras está abierta).
        .onChange(of: store.estado) { _ in store.marcarVistos() }
        .onAppear { store.marcarVistos() }
        .themed()
    }
}

private struct AvisoRow: View {
    let aviso: Aviso
    @Environment(\.openURL) private var openURL

    // Respuestas del soporte sólo para ti: check (abierta), bocadillo, confeti (solucionado) y línea de comandos.
    private var symbol: String {
        switch aviso.personal {
        case "abierto": return "checkmark.circle.fill"
        case "mensaje": return "bubble.left.fill"
        case "fiesta": return "party.popper.fill"
        case "en-ello": return "apple.terminal.fill"
        default: return aviso.importante ? "exclamationmark.bubble.fill" : "megaphone.fill"
        }
    }
    private var highlighted: Bool { aviso.importante || aviso.personal != nil }
    private var tint: Color { aviso.personal == "fiesta" ? .green : highlighted ? .accentColor : .secondary }
    private var label: String {
        if aviso.personal != nil { return L("Sólo para ti") + (aviso.ticket.map { L(" · ticket #{0}", $0) } ?? "") }
        return aviso.importante ? L("Importante") : L("Aviso")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tint.opacity(highlighted ? 0.16 : 0.12)))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    Text(haceCuanto(aviso.fecha)).font(.footnote).foregroundStyle(.secondary)
                }
                Text(aviso.titulo).font(.headline)
                if !aviso.texto.isEmpty {
                    Text(aviso.texto).font(.subheadline).foregroundStyle(.secondary)
                }
                if let enlace = aviso.enlace {
                    Button { openURL(enlace) } label: {
                        Label("Abrir enlace", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 5)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
