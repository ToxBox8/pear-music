import SwiftUI
import AVFoundation
import UIKit

// MARK: - Hoja del Jam
/// Un único sitio para todo el Jam: empezar, buscar al anfitrión y la sala con la lista.
struct JamSheet: View {
    @EnvironmentObject var jam: JamService

    var body: some View {
        NavigationStack {
            Group {
                switch jam.phase {
                case .idle: JamStartView()
                case .searching: JamSearchingView()
                case .hosting, .joined, .lost: JamRoomView()
                }
            }
            .themed()
        }
        .animation(.uiEaseOut(0.3), value: jam.phase)
    }
}

private func themeFor(_ id: String) -> AppTheme { AppTheme(rawValue: id) ?? .glass }

// MARK: Empezar
private struct JamStartView: View {
    @EnvironmentObject var jam: JamService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("jamName") private var name = ""
    @State private var title = ""
    @State private var code = ""
    @State private var scanning = false

    private var hasName: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Jam").displayTitle(46)
                    Text("Una playlist que hacéis entre todos. Funciona con gente que está cerca, en la misma WiFi o con el Bluetooth activado.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                JamTextField(label: "Tu nombre", prompt: "Así te verán los demás", text: $name)
                    .textContentType(.givenName)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Crear uno").font(.title3.bold())
                    JamTextField(label: "Nombre del Jam", prompt: "Opcional, p. ej. Viaje a la playa", text: $title)
                    Button {
                        jam.host(title: title, as: name)
                    } label: {
                        Label("Crear Jam", systemImage: "person.2.wave.2.fill")
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(!hasName)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Unirme a uno").font(.title3.bold())
                    Text("Pide el código a quien lo creó o escanea su QR.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    JamCodeField(code: $code)
                    HStack(spacing: 12) {
                        Button { scanning = true } label: {
                            Label("Escanear QR", systemImage: "qrcode.viewfinder")
                        }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        Button { join() } label: {
                            Label("Unirme", systemImage: "arrow.right")
                        }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(!hasName || code.count < 6)
                    }
                }

                if !hasName {
                    Label("Escribe tu nombre para crear un Jam o unirte.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
        }
        .fullScreenCover(isPresented: $scanning) {
            JamScannerView { scanned in
                code = scanned
                scanning = false
                if hasName { join() }
            }
        }
        .onAppear(perform: usePendingCode)
        .onChange(of: jam.pendingCode) { _ in usePendingCode() }
    }

    private func join() { jam.join(code: code, as: name) }

    /// Llegó un código por enlace o QR del sistema: se rellena y, si ya hay nombre, se entra directamente.
    private func usePendingCode() {
        guard let c = jam.pendingCode else { return }
        jam.pendingCode = nil
        code = c
        if hasName { join() }
    }
}

/// Campo de texto con la superficie del tema y su etiqueta encima.
private struct JamTextField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .font(.body.weight(.medium))
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(ThemeSurface(radius: 14))
                .submitLabel(.done)
                .autocorrectionDisabled()
        }
    }
}

/// Seis casillas para el código; por debajo hay un único campo de texto invisible.
private struct JamCodeField: View {
    @Binding var code: String
    @FocusState private var focused: Bool
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    var body: some View {
        let theme = themeFor(themeID)
        let chars = Array(code)
        ZStack {
            TextField("", text: Binding(get: { code }, set: { code = JamService.normalize($0) }))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Código del Jam, 6 caracteres")
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let caret = focused && i == min(chars.count, 5)
                    let radius = min(14, theme.maxRadius)
                    Text(i < chars.count ? String(chars[i]) : "")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(ThemeSurface(radius: radius))
                        .overlay(
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(theme.accent, lineWidth: caret ? 2 : 0)
                        )
                        .animation(.uiEaseOut(0.15), value: caret)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 58)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

// MARK: Buscando al anfitrión
private struct JamSearchingView: View {
    @EnvironmentObject var jam: JamService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    var body: some View {
        let theme = themeFor(themeID)
        VStack(spacing: 26) {
            Spacer()
            JamRadar(tint: theme.accent, animating: !reduceMotion)
                .frame(width: 180, height: 180)
            VStack(spacing: 10) {
                Text("Buscando el Jam").displayTitle(30)
                if let code = jam.joiningCode { JamCodeText(code: code, size: 24) }
            }
            Text(jam.searchStalled
                 ? "Todavía no aparece. Comprobad que el código es correcto, que estáis en la misma WiFi o con el Bluetooth activado y que quien lo creó tiene Pear Music abierta."
                 : "Mantén Pear Music abierta. Suele tardar unos segundos.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.uiEaseOut(0.3), value: jam.searchStalled)
            Spacer()
            Button { jam.leave() } label: { Text("Cancelar") }
                .buttonStyle(PillButtonStyle(prominent: false))
        }
        .padding(24)
    }
}

/// Ondas que salen del icono, como un radar buscando el móvil del anfitrión.
private struct JamRadar: View {
    let tint: Color
    let animating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = animating ? (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1) : 0.35 + Double(i) * 0.25
                    Circle()
                        .strokeBorder(tint.opacity(0.9 * (1 - p)), lineWidth: 2)
                        .scaleEffect(0.35 + p * 0.65)
                }
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 76, height: 76)
                    .background(ThemeSurface(radius: 38))
                    .clipShape(Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

/// El código con las letras separadas, como se dicta en voz alta.
private struct JamCodeText: View {
    let code: String
    var size: CGFloat = 30

    var body: some View {
        Text(code.map(String.init).joined(separator: " "))
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .accessibilityLabel("Código \(code.map(String.init).joined(separator: ", "))")
    }
}

// MARK: Sala
private struct JamRoomView: View {
    @EnvironmentObject var jam: JamService
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue
    @State private var adding = false
    @State private var showQR = false
    @State private var confirmLeave = false
    @State private var savedName: String?
    /// Playlist creada al guardar: si se vuelve a guardar se actualiza en vez de duplicarla.
    @State private var savedID: UUID?

    var body: some View {
        let theme = themeFor(themeID)
        if let state = jam.jam {
            List {
                Section {
                    header(state, theme: theme)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 16, trailing: 20))
                }
                Section {
                    ForEach(state.entries) { e in
                        JamEntryRow(entry: e, context: state.entries.map(\.song))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.primary.opacity(0.08))
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if jam.isActive && jam.canRemove(e) {
                                    Button(role: .destructive) { jam.remove(e) } label: { Label("Quitar", systemImage: "minus.circle") }
                                }
                            }
                    }
                } footer: {
                    if state.entries.isEmpty {
                        Text(jam.isActive ? "Aún no hay canciones. Añade la primera y aparecerá en el móvil de todos." : "La lista quedó vacía.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }
                }
            }
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { save(state) } label: {
                            Label(savedID == nil ? "Guardar como playlist" : "Actualizar playlist guardada", systemImage: "square.and.arrow.down")
                        }
                            .disabled(state.entries.isEmpty)
                        Divider()
                        Button(role: .destructive) { askLeave(state) } label: {
                            Label(jam.isHost ? "Terminar Jam" : "Salir del Jam", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Opciones del Jam")
                }
            }
            .sheet(isPresented: $adding) { JamAddSongsView() }
            .sheet(isPresented: $showQR) { JamQRView(state: state).presentationDetents([.medium, .large]) }
            .confirmationDialog("¿Guardar la lista antes de salir?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Guardar y salir") { save(state); jam.leave() }
                Button(jam.isHost ? "Terminar sin guardar" : "Salir sin guardar", role: .destructive) { jam.leave() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(jam.isHost ? "El Jam se terminará para todos." : "Podrás volver a entrar con el código mientras siga abierto.")
            }
        }
    }

    @ViewBuilder
    private func header(_ state: JamState, theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                JamLiveBadge(phase: jam.phase, tint: theme.accent)
                Text(state.name).displayTitle(34).lineLimit(2)
                Text(subtitle(state)).font(.subheadline).foregroundStyle(.secondary)
            }

            JamMembers(members: state.members)

            if case .lost(let why) = jam.phase {
                Label(why, systemImage: "wifi.slash")
                    .font(.subheadline.weight(.semibold))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ThemeSurface(radius: 16))
            } else {
                Button { showQR = true } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Código para unirse").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            JamCodeText(code: state.code, size: 26)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "qrcode")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(ThemeSurface(radius: 20))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityHint("Muestra el código QR")
            }

            HStack(spacing: 12) {
                if jam.isActive {
                    Button { adding = true } label: { Label("Añadir", systemImage: "plus") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                } else if savedName == nil {
                    Button { save(state) } label: { Label("Guardar lista", systemImage: "square.and.arrow.down") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(state.entries.isEmpty)
                }
                Button {
                    let songs = state.entries.map(\.song)
                    if let f = songs.first { player.play(f, in: songs) }
                } label: { Label("Reproducir", systemImage: "play.fill") }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(state.entries.isEmpty)
            }

            if let savedName {
                Label("Guardada en Biblioteca como «\(savedName)»", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .transition(.opacity)
            }
        }
    }

    private func subtitle(_ s: JamState) -> String {
        let n = s.entries.count
        let songs = n == 1 ? "1 canción" : "\(n) canciones"
        return jam.isHost ? "Lo has creado tú · \(songs)" : "De \(s.host) · \(songs)"
    }

    private func save(_ s: JamState) {
        guard !s.entries.isEmpty else { return }
        let songs = s.entries.map(\.song)
        if let id = savedID, library.playlists.contains(where: { $0.id == id }) {
            library.update(id) { $0.songs = songs }
        } else {
            savedID = library.importPlaylist(name: s.name, songs: songs)
        }
        withAnimation(.uiEaseOut(0.25)) { savedName = s.name }
    }

    private func askLeave(_ s: JamState) {
        if s.entries.isEmpty || savedName != nil { jam.leave() } else { confirmLeave = true }
    }
}

private struct JamLiveBadge: View {
    let phase: JamService.Phase
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let live = phase == .hosting || phase == .joined
        HStack(spacing: 6) {
            Circle()
                .fill(live ? tint : Color.secondary)
                .frame(width: 8, height: 8)
                .opacity(live && pulse ? 0.35 : 1)
            Text(live ? "En directo" : "Sin conexión")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(live ? tint : .secondary)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Avatares superpuestos y los nombres de quienes están dentro.
private struct JamMembers: View {
    let members: [String]

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                ForEach(Array(members.prefix(6).enumerated()), id: \.offset) { _, m in
                    JamAvatar(name: m, size: 36)
                }
            }
            Text(names).font(.subheadline.weight(.medium)).lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Personas: \(members.joined(separator: ", "))")
    }

    private var names: String {
        switch members.count {
        case 0: return ""
        case 1: return "Sólo \(members[0]) por ahora"
        case 2: return "\(members[0]) y \(members[1])"
        case 3: return "\(members[0]), \(members[1]) y \(members[2])"
        default: return "\(members[0]), \(members[1]) y \(members.count - 2) más"
        }
    }
}

struct JamAvatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let palette = (hash & 0x7fff_ffff) % PlaylistStyle.palettes.count
        Circle()
            .fill(PlaylistStyle.gradient(palette))
            .overlay(
                Text(name.first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct JamEntryRow: View {
    let entry: JamEntry
    let context: [Song]
    @EnvironmentObject var player: Player

    var body: some View {
        let isCurrent = player.current?.id == entry.song.id
        Button { player.play(entry.song, in: context) } label: {
            HStack(spacing: 12) {
                CoverImage(url: entry.song.thumb(200))
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.song.title).font(.system(size: 16, weight: isCurrent ? .bold : .semibold)).lineLimit(1)
                    Text("\(entry.song.artist) · añadida por \(entry.by)")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                JamAvatar(name: entry.by, size: 26)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .contextMenu { SongMenuItems(song: entry.song) }
    }
}

// MARK: QR para compartir
private struct JamQRView: View {
    let state: JamState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text(state.name).displayTitle(26).lineLimit(1).padding(.top, 28)
            if let img = QRCode.image(JamService.link(state.code)) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    .accessibilityLabel("Código QR del Jam")
            }
            JamCodeText(code: state.code, size: 28)
            Text("Escanead con la cámara del iPhone o desde Biblioteca → + → Jam con amigos.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .themed()
    }
}

// MARK: Añadir canciones
private struct JamAddSongsView: View {
    @EnvironmentObject var jam: JamService
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Song] = []
    @State private var searching = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    if !library.favorites.isEmpty {
                        Section("Tus favoritos") { rows(Array(library.favorites.prefix(40))) }
                    }
                    if !library.recents.isEmpty {
                        Section("Escuchado hace poco") { rows(Array(library.recents.prefix(20))) }
                    }
                } else {
                    rows(results)
                }
            }
            .listStyle(.plain)
            .overlay {
                if searching { ProgressView() }
                else if failed { Text("No se pudo buscar. Revisa tu conexión.").foregroundStyle(.secondary) }
                else if query.isEmpty && library.favorites.isEmpty && library.recents.isEmpty {
                    Text("Busca una canción para añadirla").foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Canciones, artistas…")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { if $0.isEmpty { results = []; failed = false } }
            .navigationTitle("Añadir al Jam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .themed()
        }
    }

    private func rows(_ songs: [Song]) -> some View {
        ForEach(songs) { JamPickRow(song: $0).listRowBackground(Color.clear) }
    }

    private func search() async {
        searching = true
        failed = false
        do { results = try await YTClient.search(query) } catch { results = []; failed = true }
        searching = false
    }
}

private struct JamPickRow: View {
    let song: Song
    @EnvironmentObject var jam: JamService
    @AppStorage("theme") private var themeID = AppTheme.glass.rawValue

    var body: some View {
        let added = jam.contains(song)
        Button { jam.add(song) } label: {
            HStack(spacing: 12) {
                CoverImage(url: song.thumb(160))
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.body.weight(.semibold)).lineLimit(1)
                    Text(song.artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(added ? AnyShapeStyle(themeFor(themeID).accent) : AnyShapeStyle(.secondary))
                    .animation(.uiEaseOut(0.2), value: added)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .disabled(added || !jam.isActive)
        .accessibilityLabel(added ? "\(song.title), ya está en el Jam" : "Añadir \(song.title) al Jam")
    }
}

// MARK: Escáner
private struct JamScannerView: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch status {
            case .authorized:
                QRScanner(onCode: onCode).ignoresSafeArea()
                Viewfinder()
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 250, height: 250)
                    .shadow(color: .black.opacity(0.4), radius: 8)
            case .notDetermined:
                ProgressView().tint(.white)
                    .task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        status = AVCaptureDevice.authorizationStatus(for: .video)
                    }
            default:
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 34))
                    Text("Pear Music no tiene permiso para usar la cámara").font(.headline)
                    Text("Actívalo en Ajustes o escribe el código a mano.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { Text("Abrir Ajustes") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .frame(maxWidth: 220)
                        .padding(.top, 6)
                }
                .multilineTextAlignment(.center)
                .padding(32)
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Cerrar")
                }
                Spacer()
                if status == .authorized {
                    Text("Apunta al QR del Jam")
                        .font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(20)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// Esquinas de visor de cámara.
private struct Viewfinder: Shape {
    func path(in r: CGRect) -> Path {
        let l = r.width * 0.18
        let c: CGFloat = 18
        var p = Path()
        // Arriba izquierda
        p.move(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // Arriba derecha
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + c), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // Abajo derecha
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // Abajo izquierda
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}
