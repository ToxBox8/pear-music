import SwiftUI
import PhotosUI

// MARK: - Informar de un error (Fase 4C)
/// Mismos límites que el Worker (`services/soporte/src/limits.js`) y que `SupportLimits` en Android.
enum SupportLimits {
    static let maxPhotos = 4
    static let maxPhotoBytes = 1_500_000
    static let minText = 10
    static let maxText = 4000
    /// Lado mayor de las fotos al reescalarlas: se leen bien y pesan poco.
    static let photoSide: CGFloat = 1600

    static func validEmail(_ email: String) -> Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.count <= 254 && e.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil
    }

    static func validText(_ text: String) -> Bool {
        (minText...maxText).contains(text.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }
}

/// Un reporte a medias o que no se pudo enviar. Las fotos ya están comprimidas en `Documents/support/<id>/`.
struct SupportDraft: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var email = ""
    var text = ""
    var photos: [String] = []   // nombres de archivo dentro de su carpeta
    var updated = Date()
    /// «error» (Informar de un error) o «sugerencia» (Buzón de sugerencias).
    var kind: String? = nil

    var isEmpty: Bool { email.trimmingCharacters(in: .whitespaces).isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty && photos.isEmpty }
}

/// Borradores guardados en el iPhone (`Documents/support/drafts.json`, cifrado), el más reciente primero.
@MainActor
final class SupportStore: ObservableObject {
    static let shared = SupportStore()
    @Published private(set) var drafts: [SupportDraft] = []
    private let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("support")
    private var file: URL { dir.appendingPathComponent("drafts.json") }

    private init() {
        guard let raw = try? Data(contentsOf: file) else { return }
        // Hasta la 1.4.1 se guardaba en claro (empieza por «[»): se lee y se vuelve a guardar cifrado.
        let legacy = raw.first == UInt8(ascii: "[")
        if let data = legacy ? raw : try? SecureBox.open(raw),
           let list = try? JSONDecoder().decode([SupportDraft].self, from: data) {
            drafts = list.sorted { $0.updated > $1.updated }
            if legacy { persist(drafts) }
        }
    }

    private func persist(_ list: [SupportDraft]) {
        drafts = list.sorted { $0.updated > $1.updated }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // El correo y el texto van cifrados con SecureBox (ver docs/SEGURIDAD.md).
        // Si el llavero falla, el borrador se queda sólo en memoria (nunca en claro en el disco), como en Android.
        if let data = try? JSONEncoder().encode(drafts), let sealed = try? SecureBox.seal(data) {
            try? sealed.write(to: file, options: [.atomic, .completeFileProtection])
        } else {
            Logs.w("Support", "No se pudo guardar el borrador cifrado")
        }
    }

    /// Guarda (o quita, si está vacío) el borrador.
    func save(_ d: SupportDraft) {
        var rest = drafts.filter { $0.id != d.id }
        if !d.isEmpty { var copy = d; copy.updated = Date(); rest.append(copy) }
        persist(rest)
    }

    /// Borra el borrador y sus fotos (al enviarlo bien o al eliminarlo).
    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(id))
        persist(drafts.filter { $0.id != id })
    }

    func photoURL(_ draft: String, _ name: String) -> URL { dir.appendingPathComponent(draft).appendingPathComponent(name) }

    /// Guarda una foto en el borrador: reescalada y como JPEG nuevo, así no viaja ningún metadato (ni la
    /// ubicación). Baja la calidad hasta que pese menos de `maxPhotoBytes`.
    func importPhoto(_ data: Data, into draft: String) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let side = max(image.size.width, image.size.height)
        let scale = min(1, SupportLimits.photoSide / max(side, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // Dibujar la imagen aplica su orientación y deja fuera el EXIF.
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        var quality: CGFloat = 0.85
        var jpeg = resized.jpegData(compressionQuality: quality)
        while let j = jpeg, j.count > SupportLimits.maxPhotoBytes, quality > 0.3 {
            quality -= 0.1
            jpeg = resized.jpegData(compressionQuality: quality)
        }
        guard let jpeg, jpeg.count <= SupportLimits.maxPhotoBytes else { return nil }
        let name = UUID().uuidString + ".jpg"
        let folder = dir.appendingPathComponent(draft)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do { try jpeg.write(to: folder.appendingPathComponent(name)) } catch { return nil }
        return name
    }
}

enum SupportClient {
    /// El Worker de `services/soporte`. La URL del webhook de Discord nunca está en la app.
    static let endpoint = URL(string: "https://libremusic-soporte.8toxbox8-69a.workers.dev/report")!

    /// Resultado de enviar: `error` nil si ha llegado; si el servidor lo rechazó por el contenido, `denialID`
    /// permite apelar (`appeal`). Igual que `SupportClient.Result` en Android.
    struct Result { var error: String?; var denialID: String? = nil; var ticket: Int? = nil }

    /// El id anónimo con el que se piden las respuestas del soporte, sólo si ya se envió algo desde aquí.
    static var sentDeviceID: String? {
        UserDefaults.standard.bool(forKey: "supportSent") ? UserDefaults.standard.string(forKey: "supportDeviceId") : nil
    }

    private static var deviceID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "supportDeviceId") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "supportDeviceId")
        return id
    }

    /// Envía el reporte.
    static func send(_ d: SupportDraft, photos: [URL]) async -> Result {
        if Incident.restricted { return Result(error: L("El soporte está en pausa mientras resolvemos un incidente. Tu reporte se queda en Borradores.")) }
        var model = utsname()
        uname(&model)
        let modelName = withUnsafeBytes(of: &model.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let fields: [(String, String)] = [
            ("email", d.email.trimmingCharacters(in: .whitespaces)),
            ("text", d.text.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("platform", "ios"),
            ("appVersion", AboutView.version),
            ("os", "iOS \(UIDevice.current.systemVersion)"),
            ("model", modelName),
            ("deviceId", deviceID),
            ("kind", d.kind ?? "error"),
        ]
        let boundary = "LibreMusic-\(UUID().uuidString)"
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        for (k, v) in fields {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        for (i, url) in photos.enumerated() {
            guard let data = try? Data(contentsOf: url) else { continue }
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\(i)\"; filename=\"foto-\(i + 1).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
            body.append(data)
            add("\r\n")
        }
        add("--\(boundary)--\r\n")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if (200..<300).contains(status) {
                // Desde ahora la campana pregunta por las respuestas a sus tickets.
                UserDefaults.standard.set(true, forKey: "supportSent")
                return Result(error: nil, ticket: json?["ticket"] as? Int)
            }
            return Result(error: json?["error"] as? String ?? L("El servidor de soporte no responde ({0}). Prueba más tarde.", status),
                          denialID: json?["denialId"] as? String)
        } catch {
            return Result(error: L("Sin conexión. Inténtalo cuando tengas internet."))
        }
    }

    /// Apela un rechazo (sólo desde el iPhone que lo envió). Devuelve nil si ha llegado, o el motivo.
    static func appeal(denialID: String, email: String, text: String) async -> String? {
        var request = URLRequest(url: endpoint.deletingLastPathComponent().appendingPathComponent("appeal"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "denialId": denialID, "deviceId": deviceID,
            "email": email.trimmingCharacters(in: .whitespaces), "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return nil }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return json?["error"] as? String ?? L("El servidor de soporte no responde ({0}). Prueba más tarde.", status)
        } catch {
            return L("Sin conexión. Inténtalo cuando tengas internet.")
        }
    }
}

/// Correo, descripción y hasta 4 capturas. Se guarda solo como borrador al salir; enviar pide confirmación de
/// privacidad, evita el doble envío y, si falla, lo deja en Borradores. Mismo aspecto y textos que Android.
struct SupportView: View {
    var draftID: String? = nil
    /// Buzón de sugerencias (Cierre 1.0): el mismo formulario, como sugerencia.
    var suggestion = false
    @ObservedObject private var store = SupportStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SupportDraft()
    @State private var loaded = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var emailTouched = false
    @State private var sending = false
    @State private var sent = false
    @State private var confirm = false
    @State private var failure: String?
    @State private var showSent = false
    @State private var localProblem: String?
    @State private var denial: (id: String, message: String)?
    @State private var appealing = false
    @State private var appealText = ""
    @State private var appealResult: String?
    @State private var ticket: Int?

    private var emailOK: Bool { SupportLimits.validEmail(draft.email) }
    private var canSend: Bool { emailOK && SupportLimits.validText(draft.text) && !sending }

    var body: some View {
        Form {
            let others = store.drafts.filter { $0.id != draft.id }.count
            if others > 0 {
                Section {
                    NavigationLink { SupportDraftsView() } label: { LabeledContent(L("Borradores"), value: "\(others)") }
                }
                .glassRow()
            }

            Section {
                TextField("nombre@correo.com", text: $draft.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: draft.email) { _ in emailTouched = true }
            } header: { Text(L("Tu correo")) } footer: {
                Text(emailTouched && !draft.email.isEmpty && !emailOK
                     ? L("Revisa el correo: falta algo (por ejemplo, la @ o el dominio).")
                     : L("Para poder contestarte. No se usa para nada más. La respuesta también te llega a Avisos, sólo a ti."))
            }
            .glassRow()

            Section {
                TextField(suggestion ? L("Por ejemplo: poder ordenar mis playlists por artista.") : L("Por ejemplo: al pulsar «Descargar todo» en un álbum, la app se cierra."), text: $draft.text, axis: .vertical)
                    .lineLimit(5...12)
                    .onChange(of: draft.text) { if $0.count > SupportLimits.maxText { draft.text = String($0.prefix(SupportLimits.maxText)) } }
            } header: { Text(suggestion ? L("Tu idea") : L("Qué ha pasado")) } footer: {
                Text(suggestion ? L("Qué te gustaría que hiciera Pear Music y para qué te serviría (mínimo {0} caracteres).", SupportLimits.minText)
                     : L("Cuenta qué hacías y qué esperabas que pasara. Cuanto más concreto, mejor (mínimo {0} caracteres).", SupportLimits.minText))
            }
            .glassRow()

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(draft.photos, id: \.self) { name in
                            ZStack(alignment: .topTrailing) {
                                if let img = UIImage(contentsOfFile: store.photoURL(draft.id, name).path) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                        .frame(width: 84, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                Button {
                                    draft.photos.removeAll { $0 == name }
                                    try? FileManager.default.removeItem(at: store.photoURL(draft.id, name))
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title3)
                                        .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                                        .frame(width: 44, height: 44, alignment: .topTrailing)
                                }
                                .accessibilityLabel(L("Quitar foto"))
                            }
                        }
                        if draft.photos.count < SupportLimits.maxPhotos {
                            PhotosPicker(selection: $picked, maxSelectionCount: SupportLimits.maxPhotos - draft.photos.count, matching: .images) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.15))
                                    .frame(width: 84, height: 84)
                                    .overlay(Image(systemName: "photo.badge.plus").font(.title2).foregroundStyle(.tint))
                            }
                            .accessibilityLabel(L("Añadir capturas"))
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: { Text(L("Capturas")) } footer: {
                Text(L("Hasta {0}. Se reducen y se les quitan la ubicación y los demás datos de la foto antes de enviarlas.", SupportLimits.maxPhotos))
            }
            .glassRow()

            Section {
                Button { confirm = true } label: {
                    HStack(spacing: 8) {
                        if sending { ProgressView().tint(.white) }
                        Text(sending ? "Enviando…" : L("Enviar"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(!canSend)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        }
        .navigationTitle(suggestion ? L("Buzón de sugerencias") : L("Informar de un error"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let id = draftID, let d = store.drafts.first(where: { $0.id == id }) { draft = d } else if suggestion { draft.kind = "sugerencia" }
        }
        // Al salir de la pantalla, lo escrito queda como borrador (salvo si se ha enviado).
        .onDisappear { if !sent { store.save(draft) } }
        .onChange(of: picked) { items in
            guard !items.isEmpty else { return }
            Task {
                var failed = false
                for item in items {
                    if draft.photos.count >= SupportLimits.maxPhotos { break }
                    if let data = try? await item.loadTransferable(type: Data.self), let name = store.importPhoto(data, into: draft.id) {
                        draft.photos.append(name)
                    } else { failed = true }
                }
                picked = []
                if failed { failure = L("Alguna foto no se pudo añadir.") }
            }
        }
        .confirmationDialog(suggestion ? L("¿Enviar la sugerencia?") : L("¿Enviar el reporte?"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L("Enviar")) { send() }
            Button(L("Cancelar"), role: .cancel) {}
        } message: {
            Text(draft.photos.isEmpty ? L("Se enviarán tu correo, el texto y datos del iPhone (modelo, versión de iOS y de la app) al canal privado de soporte de Pear Music.")
                 : L("Se enviarán tu correo, el texto, {0} foto(s) y datos del iPhone (modelo, versión de iOS y de la app) al canal privado de soporte de Pear Music.", draft.photos.count))
        }
        .alert(L("No se pudo enviar"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(L("Vale"), role: .cancel) {}
        } message: { Text(failure ?? "") }
        .alert(L("Revisa el mensaje"), isPresented: Binding(get: { localProblem != nil }, set: { if !$0 { localProblem = nil } })) {
            Button(L("Reformular"), role: .cancel) {}
        } message: { Text(localProblem ?? "") }
        .alert(L("No se pudo enviar"), isPresented: Binding(get: { denial != nil && !appealing }, set: { if !$0 && !appealing { denial = nil } })) {
            Button(L("Reformular"), role: .cancel) { denial = nil }
            Button(L("Apelar")) { appealText = ""; appealing = true }
        } message: { Text(L("{0}\n\nPuedes reformularlo o, si crees que es un error, apelar.", denial?.message ?? "")) }
        .alert(L("Apelar"), isPresented: $appealing) {
            TextField(L("Por qué es un reporte de verdad"), text: $appealText)
            Button(L("Enviar apelación")) {
                guard let id = denial?.id else { return }
                denial = nil
                Task { appealResult = await SupportClient.appeal(denialID: id, email: draft.email, text: appealText) ?? L("Apelación enviada. Te contestaremos al correo.") }
            }
            Button(L("Cancelar"), role: .cancel) { denial = nil }
        } message: { Text(L("Explica por qué es un reporte de verdad. Lo leerá una persona y te contestará al correo.")) }
        .alert(L("Apelación"), isPresented: Binding(get: { appealResult != nil }, set: { if !$0 { appealResult = nil } })) {
            Button(L("Vale"), role: .cancel) {}
        } message: { Text(appealResult ?? "") }
        .alert(suggestion ? L("Sugerencia enviada") : L("Reporte enviado"), isPresented: $showSent) {
            Button(L("Vale")) { dismiss() }
        } message: { Text(ticket.map { L("¡Gracias! Es el ticket #{0}. Te contestaremos en Avisos (sólo a ti) y al correo que has puesto.", $0) }
                 ?? L("¡Gracias! Te contestaremos en Avisos (sólo a ti) y al correo que has puesto.")) }
    }

    private func send() {
        guard !sending else { return }
        // Primera capa: las mismas reglas que el servidor, sin gastar el envío.
        if let problem = SupportFilter.problem(draft.text) { localProblem = problem; return }
        sending = true
        let snapshot = draft
        let urls = snapshot.photos.map { store.photoURL(snapshot.id, $0) }
        Task {
            let result = await SupportClient.send(snapshot, photos: urls)
            sending = false
            if let error = result.error, let id = result.denialID {
                // Rechazado por el contenido: se puede reformular (sigue en el formulario) o apelar.
                store.save(snapshot)
                denial = (id, error)
            } else if let error = result.error {
                store.save(snapshot)
                failure = L("{0}\n\nLo hemos guardado en Borradores para que lo envíes más tarde.", error)
            } else {
                sent = true
                store.delete(snapshot.id)
                ticket = result.ticket
                showSent = true
            }
        }
    }
}

/// Reportes guardados: abrir para seguir o enviar, o eliminarlos.
struct SupportDraftsView: View {
    @ObservedObject private var store = SupportStore.shared
    @State private var deleting: SupportDraft?

    var body: some View {
        List {
            ForEach(store.drafts) { d in
                NavigationLink { SupportView(draftID: d.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.text.split(separator: "\n").first.map { String($0.prefix(60)) } ?? L("Sin descripción")).lineLimit(1)
                        Text([d.updated.formatted(date: .abbreviated, time: .shortened),
                              d.photos.isEmpty ? nil : "\(d.photos.count) \(d.photos.count == 1 ? "foto" : "fotos")"]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { deleting = d } label: { Label("Eliminar", systemImage: "trash") }
                }
            }
            .glassRow()
        }
        .overlay { if store.drafts.isEmpty { Text(L("No hay borradores")).foregroundStyle(.secondary) } }
        .confirmationDialog(L("¿Eliminar el borrador?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(L("Eliminar"), role: .destructive) { if let d = deleting { store.delete(d.id) } }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(L("Se borran el texto y sus fotos. No se puede deshacer.")) }
        .navigationTitle(L("Borradores"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}
