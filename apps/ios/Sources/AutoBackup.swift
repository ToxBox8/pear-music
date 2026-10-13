import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Copia automática de la biblioteca: una vez al día (al abrir o salir de la app), `library.json` se copia a una
/// carpeta que elige la persona (iCloud Drive, Google Drive…) como `LibreMusic-copia-AAAA-MM-DD.json`, y se dejan las
/// 7 últimas. Mismo archivo que «Exportar copia» y mismas reglas que `AutoBackup` en Android.
@MainActor
final class AutoBackup: ObservableObject {
    static let shared = AutoBackup()
    static let prefix = "LibreMusic-copia-"
    static let keep = 7

    @Published private(set) var folderName: String?
    @Published private(set) var lastDay: String? = UserDefaults.standard.string(forKey: "backupLast")
    @Published private(set) var error: String?

    private var bookmark: Data? = UserDefaults.standard.data(forKey: "backupBookmark")
    var enabled: Bool { bookmark != nil }

    private init() { folderName = UserDefaults.standard.string(forKey: "backupFolderName") }

    static func fileName(_ day: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "\(prefix)\(f.string(from: day)).json"
    }

    /// Las copias que sobran (las más antiguas) de `names`, dejando `keep`.
    static func toPrune(_ names: [String], keep: Int = keep) -> [String] {
        Array(names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }.sorted(by: >).dropFirst(keep))
    }

    func setFolder(_ url: URL, library: Library) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData() else { error = "No se pudo usar esa carpeta."; return }
        bookmark = data
        folderName = url.lastPathComponent
        UserDefaults.standard.set(data, forKey: "backupBookmark")
        UserDefaults.standard.set(folderName, forKey: "backupFolderName")
        UserDefaults.standard.removeObject(forKey: "backupLast")
        lastDay = nil
        backup(library: library, force: true)
    }

    func disable() {
        bookmark = nil; folderName = nil; lastDay = nil; error = nil
        ["backupBookmark", "backupFolderName", "backupLast"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    /// Hace la copia de hoy si toca (o siempre, con `force`). Devuelve true si se ha escrito.
    @discardableResult
    func backup(library: Library, force: Bool = false) -> Bool {
        guard let bookmark else { return false }
        let name = Self.fileName(Date())
        let today = String(name.dropFirst(Self.prefix.count).dropLast(5))
        if !force && lastDay == today { return false }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else {
            error = "No se pudo guardar la copia. Vuelve a elegir la carpeta."
            return false
        }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        do {
            try library.exportData().write(to: folder.appendingPathComponent(name), options: .atomic)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for old in Self.toPrune(names) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(old)) }
            if stale, let fresh = try? folder.bookmarkData() { self.bookmark = fresh; UserDefaults.standard.set(fresh, forKey: "backupBookmark") }
            lastDay = today
            error = nil
            UserDefaults.standard.set(today, forKey: "backupLast")
            return true
        } catch {
            self.error = "No se pudo guardar la copia. Vuelve a elegir la carpeta."
            return false
        }
    }
}

/// Sección «Copia automática» de Ajustes › Biblioteca.
struct BackupSection: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var backup = AutoBackup.shared
    @State private var picking = false
    @State private var message: String?

    var body: some View {
        Section {
            if backup.enabled {
                Button { picking = true } label: {
                    SettingsRow(icon: "folder", palette: 3, title: "Carpeta", value: backup.folderName ?? "Elegida",
                                subtitle: backup.lastDay.map { "Última copia: \($0)" } ?? "Aún sin copia")
                }
                .buttonStyle(.plain)
                Button { message = backup.backup(library: library, force: true) ? "Copia guardada" : "No se pudo guardar la copia" } label: {
                    Label("Hacer copia ahora", systemImage: "externaldrive.badge.checkmark")
                }
                Button("Desactivar", role: .destructive) { backup.disable() }
            } else {
                Button { picking = true } label: { Label("Elegir carpeta", systemImage: "folder.badge.plus") }
            }
        } header: { Text("Copia automática") } footer: {
            Text(backup.error ?? message ?? (backup.enabled
                ? "Se guarda una al día y se dejan las \(AutoBackup.keep) últimas. Para recuperarla: Biblioteca › Importar › Importar copia."
                : "Una copia al día de tus favoritos, playlists y álbumes en la carpeta que elijas. Elige una que se sincronice (iCloud Drive, Google Drive…) para no perder nada al cambiar de móvil."))
        }
        .glassRow()
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { backup.setFolder(url, library: library) }
        }
    }
}
