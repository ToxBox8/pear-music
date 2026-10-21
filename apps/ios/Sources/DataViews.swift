import SwiftUI
import UIKit

// MARK: - Tus datos (Ajustes › Ayuda y soporte)
/// Exportar y borrar todo lo que la app guarda (RGPD). Mismos textos que `MyDataScreen` en Android.
struct MyDataView: View {
    @State private var busy = false
    @State private var exported: ExportedFile?
    @State private var failed = false
    @State private var confirmErase = false
    @State private var telemetry = Telemetry.shared.enabled

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { telemetry }, set: { telemetry = $0; Telemetry.shared.setConsent($0) })) {
                    SettingsRow(icon: "speedometer", palette: 3, title: L("Telemetría de rendimiento"), value: nil,
                                subtitle: telemetry ? L("Activada") : L("Desactivada"))
                }
            } footer: {
                Text(L("Si la activas, una vez a la semana se envía un resumen de rendimiento: modelo y sistema, versión, cuánto tarda en abrir, fluidez (FPS y tirones), memoria y minutos de uso, con un identificador aleatorio que no es el de tu cuenta. Nada de lo que escuchas ni buscas. Se borra a los 90 días; al apagarla se borra al momento."))
            }
            .glassRow()

            Section {
                Button {
                    busy = true
                    Task.detached(priority: .userInitiated) {
                        let result = try? UserData.export()
                        await MainActor.run {
                            busy = false
                            if let result { exported = ExportedFile(url: result) } else { failed = true }
                        }
                    }
                } label: {
                    HStack {
                        SettingsRow(icon: "square.and.arrow.up.fill", palette: 2, title: L("Exportar mis datos"), value: nil,
                                    subtitle: L("Un archivo .zip con todo lo que la app guarda de ti"))
                        if busy { ProgressView() }
                    }
                }
                .foregroundStyle(.primary)
                .disabled(busy)
            } footer: {
                Text(L("Pear Music no tiene cuentas ni servidor con tus datos: todo está en este móvil. El archivo lleva tu biblioteca, estadísticas, letras, borradores de soporte y ajustes; no las canciones descargadas."))
            }
            .glassRow()

            Section {
                Button(role: .destructive) { confirmErase = true } label: {
                    Label(L("Borrar todos mis datos"), systemImage: "trash.fill")
                }
            } footer: {
                Text(L("Borra la biblioteca, las descargas, las estadísticas y los ajustes, y cierra la app. No se puede deshacer."))
            }
            .glassRow()
        }
        .navigationTitle(L("Tus datos"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
        .sheet(item: $exported) { file in ActivityView(items: [file.url]) }
        .alert(L("No se pudieron exportar los datos"), isPresented: $failed) { Button(L("Vale"), role: .cancel) {} }
        .alert(L("¿Borrar todos tus datos?"), isPresented: $confirmErase) {
            Button(L("Borrar todo"), role: .destructive) { UserData.eraseAll() }
            Button(L("Cancelar"), role: .cancel) {}
        } message: {
            Text(L("Se borrarán tus playlists, favoritos, descargas, estadísticas y ajustes de este móvil, y la app se cerrará. Si quieres conservar algo, exporta antes tus datos."))
        }
    }
}

// MARK: - Administración (sólo dev)
/// Canal, registro reciente y botón de pánico. Sólo existe con `Channel.adminTools` (variante dev).
struct AdminView: View {
    @State private var lines = Logs.recent

    var body: some View {
        Form {
            Section(L("Esta app")) {
                LabeledContent(L("Canal"), value: Channel.current)
                LabeledContent(L("Versión"), value: "\(AboutView.version) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                LabeledContent(L("Paquete"), value: Bundle.main.bundleIdentifier ?? "?")
            }
            .glassRow()

            Section {
                if lines.isEmpty {
                    Text(L("Sin líneas todavía")).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.suffix(80).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption.monospaced())
                        }
                    }
                    .textSelection(.enabled)
                }
                Button(L("Copiar registro")) { UIPasteboard.general.string = lines.joined(separator: "\n") }
                    .disabled(lines.isEmpty)
                Button(L("Vaciar registro")) { Logs.clear(); lines = Logs.recent }
            } header: {
                Text(L("Registro"))
            } footer: {
                Text(L("Las últimas {0} líneas, sólo en memoria. Nunca llevan datos personales.", lines.count))
            }
            .glassRow()

            AdminTests()
            TelemetryAdmin()
            PanicPanel()
        }
        .navigationTitle(L("Administración"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

/// Pruebas (2.2 de x.1.1): repetir la bienvenida o las novedades y ver el aviso de versión nueva sin instalar nada.
/// Ninguna toca la biblioteca ni las descargas. Igual que `AdminTests` en Android.
private struct AdminTests: View {
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        Section {
            Button(L("Reiniciar la bienvenida")) {
                let d = UserDefaults.standard
                d.set(WhatsNew.current, forKey: "whatsNewSeen")
                d.set("", forKey: "firstSteps")
                d.set("", forKey: "introStage")
                d.set(false, forKey: "onboarded")
            }
            Button(L("Ver las novedades otra vez")) { UserDefaults.standard.set("", forKey: "whatsNewSeen") }
            Toggle(isOn: Binding(get: { updates.simulated != nil }, set: { updates.simulate($0 ? "2.0.0" : nil) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Simular versión antigua"))
                    Text(updates.simulated.map { L("La app se cree la {0}. Sal y vuelve para ver el aviso.", $0) } ?? L("Para ver el aviso de versión nueva"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L("Pruebas"))
        } footer: {
            Text(L("Para repetir la bienvenida o ver los avisos sin reinstalar. No tocan tu biblioteca ni tus descargas."))
        }
        .glassRow()
    }
}

/// Hoja de compartir del sistema (guardar en Archivos, AirDrop…).
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// El .zip exportado, para `.sheet(item:)`.
private struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Botón de pánico remoto (Fase 4, sólo Pear Dev), igual que `PanicPanel` en Android: publica un estado prefirmado en el
/// PC con contraseña + TOTP; el bloqueo total se confirma a los 10 minutos con otro código.
private struct PanicPanel: View {
    @State private var level = 2
    @State private var password = ""
    @State private var code = ""
    @State private var busy = false
    @State private var result: String?
    @State private var confirm = false
    private let names = [0: L("Normal"), 1: L("Aviso"), 2: L("Modo seguro"), 3: L("Bloqueo total")]

    var body: some View {
        Section {
            Picker(L("Nivel"), selection: $level) {
                Text(L("Aviso")).tag(1); Text(L("Seguro")).tag(2); Text(L("Bloqueo")).tag(3); Text(L("Normal")).tag(0)
            }
            .pickerStyle(.segmented)
            SecureField(L("Contraseña"), text: $password)
            TextField(L("Código de 6 cifras"), text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                .onChange(of: code) { v in code = String(v.filter(\.isNumber).prefix(6)) }
            let ready = !busy && password.count >= 8 && code.count == 6
            Button(level == 3 ? L("Pedir bloqueo total") : L("Publicar este nivel"), role: .destructive) { confirm = true }.disabled(!ready)
            Button(L("Confirmar bloqueo pendiente"), role: .destructive) { send("confirmar") }.disabled(!ready)
            Button(L("Cancelar bloqueo pendiente")) { send("cancelar") }.disabled(!ready)
            Button(L("Ver estado y auditoría")) { send("info") }.disabled(!ready)
            if let result { Text(result).font(.footnote).textSelection(.enabled) }
        } header: {
            Text(L("Botón de pánico"))
        } footer: {
            Text(L("Publica uno de los estados firmados en el PC. Aviso: banner que caduca solo. Modo seguro: apaga actualizaciones, búsqueda, soporte, telemetría y cuenta. Bloqueo: pantalla de mantenimiento; se confirma a los 10 min con otro código. Normal: todo vuelve a funcionar."))
        }
        .glassRow()
        .alert("¿Publicar el nivel \(names[level] ?? "")?", isPresented: $confirm) {
            Button(L("Publicar"), role: .destructive) { send("", level: level) }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(L("Afecta a todas las personas que usan Pear Music en cuanto abran la app.")) }
    }

    private func send(_ path: String, level: Int? = nil) {
        busy = true
        var body: [String: Any] = ["password": password, "totp": code]
        if let level { body["level"] = level }
        Task {
            let (status, json) = await Panic.call(path, body)
            if let e = json["error"] as? String { result = "❌ \(e)" }
            else if json["pending"] as? Bool == true { result = "⏳ Bloqueo pedido. Confírmalo a partir de \(json["confirmAfter"] as? String ?? "") con un código nuevo." }
            else if path == "info" {
                let audit = (json["audit"] as? [[String: Any]] ?? []).map { "\(String(($0["at"] as? String ?? "").prefix(16))) · \($0["action"] ?? "") \($0["level"] ?? "") · \($0["via"] ?? "")" }
                result = "Nivel publicado: \(json["level"] ?? 0) · cambios que quedan: \(json["left"] ?? 0)\n\n" + audit.joined(separator: "\n")
            } else if (200..<300).contains(status) { result = "✅ Hecho. Quedan \(json["left"] ?? "?") cambios en el lote." }
            else { result = L("❌ Error {0}", status) }
            code = ""
            busy = false
        }
    }
}

/// Telemetría en Pear Dev (Fase 4b): «Enviar ahora» con los campos elegidos, igual que Android. *Diferencia
/// aceptada:* la llave del panel de la web por USB sólo existe en Android (el móvil de Toxbox).
struct TelemetryAdmin: View {
    @State private var chosen = Set(Telemetry.choosable.map(\.0))
    @State private var busy = false
    @State private var result: String?

    var body: some View {
        Section {
            ForEach(Telemetry.choosable, id: \.0) { item in
                Toggle(item.1, isOn: Binding(get: { chosen.contains(item.0) }, set: { on in if on { chosen.insert(item.0) } else { chosen.remove(item.0) } }))
            }
            Button {
                busy = true
                Task {
                    let n = await Telemetry.shared.sendNow(only: chosen)
                    result = n.map { L("Enviado ({0} campos)", $0) } ?? L("No se pudo enviar")
                    busy = false
                }
            } label: { Label(L("Enviar ahora"), systemImage: "paperplane") }
            .disabled(busy)
            if let result { Text(result).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text(L("Telemetría"))
        } footer: {
            Text(L("Manda ya el resumen de esta semana con los campos marcados (los obligatorios siempre van: identificador, plataforma, variante, versión y semana). El resumen semanal sigue saliendo solo si la telemetría está activada."))
        }
        .glassRow()
    }
}
