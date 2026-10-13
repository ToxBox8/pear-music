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

    var isEmpty: Bool { email.trimmingCharacters(in: .whitespaces).isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty && photos.isEmpty }
}

/// Borradores guardados en el iPhone (`Documents/support/drafts.json`), el más reciente primero.
@MainActor
final class SupportStore: ObservableObject {
    static let shared = SupportStore()
    @Published private(set) var drafts: [SupportDraft] = []
    private let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("support")
    private var file: URL { dir.appendingPathComponent("drafts.json") }

    private init() {
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([SupportDraft].self, from: data) {
            drafts = list.sorted { $0.updated > $1.updated }
        }
    }

    private func persist(_ list: [SupportDraft]) {
        drafts = list.sorted { $0.updated > $1.updated }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(drafts) { try? data.write(to: file, options: .atomic) }
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

    /// Envía el reporte. Devuelve nil si ha llegado, o el motivo para enseñárselo al usuario.
    static func send(_ d: SupportDraft, photos: [URL]) async -> String? {
        let defaults = UserDefaults.standard
        let deviceID = defaults.string(forKey: "supportDeviceId") ?? {
            let id = UUID().uuidString
            defaults.set(id, forKey: "supportDeviceId")
            return id
        }()
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
            if (200..<300).contains(status) { return nil }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            return message ?? "El servidor de soporte no responde (\(status)). Prueba más tarde."
        } catch {
            return "Sin conexión. Inténtalo cuando tengas internet."
        }
    }
}

/// Correo, descripción y hasta 4 capturas. Se guarda solo como borrador al salir; enviar pide confirmación de
/// privacidad, evita el doble envío y, si falla, lo deja en Borradores. Mismo aspecto y textos que Android.
struct SupportView: View {
    var draftID: String? = nil
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

    private var emailOK: Bool { SupportLimits.validEmail(draft.email) }
    private var canSend: Bool { emailOK && SupportLimits.validText(draft.text) && !sending }

    var body: some View {
        Form {
            let others = store.drafts.filter { $0.id != draft.id }.count
            if others > 0 {
                Section {
                    NavigationLink { SupportDraftsView() } label: { LabeledContent("Borradores", value: "\(others)") }
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
            } header: { Text("Tu correo") } footer: {
                Text(emailTouched && !draft.email.isEmpty && !emailOK
                     ? "Revisa el correo: falta algo (por ejemplo, la @ o el dominio)."
                     : "Para poder contestarte. No se usa para nada más.")
            }
            .glassRow()

            Section {
                TextField("Por ejemplo: al pulsar «Descargar todo» en un álbum, la app se cierra.", text: $draft.text, axis: .vertical)
                    .lineLimit(5...12)
                    .onChange(of: draft.text) { if $0.count > SupportLimits.maxText { draft.text = String($0.prefix(SupportLimits.maxText)) } }
            } header: { Text("Qué ha pasado") } footer: {
                Text("Cuenta qué hacías y qué esperabas que pasara. Cuanto más concreto, mejor (mínimo \(SupportLimits.minText) caracteres).")
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
                                .accessibilityLabel("Quitar foto")
                            }
                        }
                        if draft.photos.count < SupportLimits.maxPhotos {
                            PhotosPicker(selection: $picked, maxSelectionCount: SupportLimits.maxPhotos - draft.photos.count, matching: .images) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.15))
                                    .frame(width: 84, height: 84)
                                    .overlay(Image(systemName: "photo.badge.plus").font(.title2).foregroundStyle(.tint))
                            }
                            .accessibilityLabel("Añadir capturas")
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: { Text("Capturas") } footer: {
                Text("Hasta \(SupportLimits.maxPhotos). Se reducen y se les quitan la ubicación y los demás datos de la foto antes de enviarlas.")
            }
            .glassRow()

            Section {
                Button { confirm = true } label: {
                    HStack(spacing: 8) {
                        if sending { ProgressView().tint(.white) }
                        Text(sending ? "Enviando…" : "Enviar")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(!canSend)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        }
        .navigationTitle("Informar de un error")
        .navigationBarTitleDisplayMode(.inline)
        .themed()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let id = draftID, let d = store.drafts.first(where: { $0.id == id }) { draft = d }
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
                if failed { failure = "Alguna foto no se pudo añadir." }
            }
        }
        .confirmationDialog("¿Enviar el reporte?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Enviar") { send() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se enviarán tu correo, el texto\(draft.photos.isEmpty ? "" : ", \(draft.photos.count) \(draft.photos.count == 1 ? "foto" : "fotos")") y datos del iPhone (modelo, versión de iOS y de la app) al canal privado de soporte de Pear Music.")
        }
        .alert("No se pudo enviar", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Vale", role: .cancel) {}
        } message: { Text(failure ?? "") }
        .alert("Reporte enviado", isPresented: $showSent) {
            Button("Vale") { dismiss() }
        } message: { Text("¡Gracias! Te contestaremos al correo que has puesto.") }
    }

    private func send() {
        guard !sending else { return }
        sending = true
        let snapshot = draft
        let urls = snapshot.photos.map { store.photoURL(snapshot.id, $0) }
        Task {
            let error = await SupportClient.send(snapshot, photos: urls)
            sending = false
            if let error {
                store.save(snapshot)
                failure = "\(error)\n\nLo hemos guardado en Borradores para que lo envíes más tarde."
            } else {
                sent = true
                store.delete(snapshot.id)
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
                        Text(d.text.split(separator: "\n").first.map { String($0.prefix(60)) } ?? "Sin descripción").lineLimit(1)
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
        .overlay { if store.drafts.isEmpty { Text("No hay borradores").foregroundStyle(.secondary) } }
        .confirmationDialog("¿Eliminar el borrador?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { if let d = deleting { store.delete(d.id) } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Se borran el texto y sus fotos. No se puede deshacer.") }
        .navigationTitle("Borradores")
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}
