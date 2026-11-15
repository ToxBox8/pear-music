import SwiftUI

// MARK: - Carpetas de playlists (3.0, bloque 1; DECISIONS 35)
// Piezas de la interfaz de las carpetas: portada, cabecera, «Mover a…» y textos. La cuadrícula está en
// PlaylistsListView (LibraryViews.swift) y las reglas en PlaylistFolders (LibraryModel.swift). Igual que
// ui/PlaylistFolders.kt en Android.

/// Textos de las carpetas.
enum FolderText {
    /// «3 playlists · 1 carpeta»; «Vacía» si no tiene nada.
    static func contents(playlists: Int, folders: Int) -> String {
        var parts: [String] = []
        if playlists > 0 { parts.append(playlists == 1 ? L("1 playlist") : L("{0} playlists", playlists)) }
        if folders > 0 { parts.append(folders == 1 ? L("1 carpeta") : L("{0} carpetas", folders)) }
        return parts.isEmpty ? L("Vacía") : parts.joined(separator: " · ")
    }
}

/// Qué se mueve con «Mover a…».
enum MoveItem: Identifiable {
    case playlist(UUID)
    case folder(String)
    var id: String {
        switch self {
        case .playlist(let id): return "p-" + id.uuidString
        case .folder(let id): return "f-" + id
        }
    }
}

/// El aviso con un nombre: crear una carpeta o una playlist, o renombrar una carpeta.
enum FolderNaming {
    case newFolder(String?)
    /// En esa carpeta, o arriba del todo (nil).
    case newPlaylist(String?)
    case rename(PlaylistFolder)

    var title: String {
        switch self {
        case .newFolder: return L("Nueva carpeta")
        case .newPlaylist: return L("Nueva playlist")
        case .rename: return L("Renombrar carpeta")
        }
    }
    var confirm: String {
        if case .rename = self { return L("Guardar") }
        return L("Crear")
    }
}

/// Silueta de la carpeta de atrás: rectángulo con la pestaña arriba a la izquierda.
private struct FolderBackShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let c = min(14, w * 0.08)
        let tabEnd = w * 0.36, tabH = h * 0.11
        var p = Path()
        p.move(to: CGPoint(x: 0, y: c))
        p.addQuadCurve(to: CGPoint(x: c, y: 0), control: .zero)
        p.addLine(to: CGPoint(x: tabEnd - 10, y: 0))
        p.addCurve(to: CGPoint(x: tabEnd + 8, y: tabH), control1: CGPoint(x: tabEnd, y: 0), control2: CGPoint(x: tabEnd, y: tabH))
        p.addLine(to: CGPoint(x: w - c, y: tabH))
        p.addQuadCurve(to: CGPoint(x: w, y: tabH + c), control: CGPoint(x: w, y: tabH))
        p.addLine(to: CGPoint(x: w, y: h - c))
        p.addQuadCurve(to: CGPoint(x: w - c, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: c, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - c), control: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}

/// Portada de una carpeta: papel washi con la pestaña en kincha y un mosaico con las 4 primeras portadas de lo que
/// guarda (también de sus subcarpetas). Sin insignia: lo eligió Claude entre «sin insignia» y «en sumi» a tamaño real
/// (DECISIONS 35). Mientras se arrastra una playlist encima, se marca para soltarla dentro.
struct FolderCover: View {
    let folder: PlaylistFolder
    @EnvironmentObject var library: Library
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dropInto) private var dropTarget
    @Environment(\.accentFill) private var accentFill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        let tab = dark ? Tokens.FolderDark.tab : Tokens.FolderLight.tab
        let paper = dark ? Tokens.FolderDark.paper : Tokens.FolderLight.paper
        let edge = dark ? Tokens.FolderDark.edge : Tokens.FolderLight.edge
        let well = dark ? Tokens.FolderDark.well : Tokens.FolderLight.well
        let inside = Array(library.playlists(inFolder: folder.id).prefix(4))
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { g in
                    let side = g.size.width
                    let top = side * 0.15
                    let pad = side * 0.055, gap = side * 0.035
                    let cell = min((side - pad * 2 - gap) / 2, (side - top - pad * 2 - gap) / 2)
                    ZStack(alignment: .bottom) {
                        FolderBackShape().fill(tab)
                        RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                            .fill(paper)
                            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous).strokeBorder(edge, lineWidth: 1))
                            .overlay {
                                VStack(spacing: gap) {
                                    ForEach(0..<2, id: \.self) { row in
                                        HStack(spacing: gap) {
                                            ForEach(0..<2, id: \.self) { col in
                                                let i = row * 2 + col
                                                if i < inside.count {
                                                    PlaylistCover(playlist: inside[i], size: cell, radius: 7)
                                                } else {
                                                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(well).frame(width: cell, height: cell)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: side - top)
                    }
                }
            }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
            .overlay {
                if dropTarget {
                    RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .strokeBorder(accentFill, lineWidth: 3)
                        .padding(-4)
                }
            }
            .overlay(alignment: .top) {
                if dropTarget {
                    Text(L("Soltar en {0}", folder.name))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(Tokens.Brand.washi)
                        .background(Capsule().fill(Tokens.Brand.sumi))
                        .offset(y: -14)
                        .transition(.opacity)
                }
            }
            .scaleEffect(dropTarget && !reduceMotion ? 1.04 : 1)
            .animation(.uiEaseOut(0.22), value: dropTarget)
    }
}

/// Cabecera de una carpeta: qué tiene y Reproducir / Aleatorio con todo lo de dentro (sin repetir canciones).
struct FolderHeader: View {
    let folder: PlaylistFolder
    @EnvironmentObject var library: Library

    var body: some View {
        let lists = library.playlists(inFolder: folder.id)
        var seen = Set<String>()
        let songs = lists.flatMap(\.songs).filter { seen.insert($0.id).inserted }
        let contents = FolderText.contents(playlists: library.userPlaylists.filter { $0.folder == folder.id }.count,
                                           folders: library.folders.filter { $0.parent == folder.id }.count)
        VStack(alignment: .leading, spacing: 14) {
            Text(songs.isEmpty ? contents : "\(contents) · \(songCount(songs.count))")
                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            if !songs.isEmpty { PlayShuffleBar(songs: songs) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

/// Carpeta sin nada dentro: qué hacer.
struct FolderEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder").font(.system(size: 40, weight: .regular)).foregroundStyle(.secondary)
            Text(L("Carpeta vacía")).font(.headline)
            Text(L("Arrastra una playlist encima de la carpeta o usa «Mover a…» en su menú."))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }
}

/// «Mover a…»: las carpetas en árbol, con la actual marcada. Al mover una carpeta, donde no cabe sale apagado y
/// dice por qué. «Nueva carpeta» la crea arriba del todo y mete ahí lo que se mueve. Igual que `MoveToFolderSheet`
/// en Android.
struct MoveToFolderSheet: View {
    let item: MoveItem
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var naming = false
    @State private var newName = ""

    private var current: String? {
        switch item {
        case .playlist(let id): return library.playlists.first { $0.id == id }?.folder
        case .folder(let id): return library.folders.first { $0.id == id }?.parent
        }
    }

    private var itemName: String {
        switch item {
        case .playlist(let id): return library.playlists.first { $0.id == id }?.name ?? ""
        case .folder(let id): return library.folders.first { $0.id == id }?.name ?? ""
        }
    }

    /// Las carpetas de arriba abajo, cada una con su nivel (0 = arriba del todo), por nombre.
    private var tree: [(PlaylistFolder, Int)] {
        var out: [(PlaylistFolder, Int)] = []
        func walk(_ parent: String?, _ level: Int) {
            let children = library.folders.filter { $0.parent == parent }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for f in children where level < PlaylistFolders.maxDepth {
                out.append((f, level))
                walk(f.id, level + 1)
            }
        }
        walk(nil, 0)
        return out
    }

    private var canUseNewFolder: Bool {
        guard case .folder(let id) = item else { return true }
        return PlaylistFolders.canMoveIntoNew(id, folders: library.folders)
    }

    /// Por qué no se puede mover aquí (nil = se puede).
    private func blocked(_ target: String?) -> String? {
        guard case .folder(let id) = item else { return nil }
        if target == id { return L("Es la que mueves") }
        if let target, PlaylistFolders.subtree(id, in: library.folders).contains(target) { return L("Está dentro de la que mueves") }
        if !PlaylistFolders.canMove(id, to: target, folders: library.folders) { return L("No cabe: pasaría de 3 niveles") }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(nil, title: L("Playlists"), subtitle: L("Fuera de las carpetas"), level: 0, symbol: "music.note.list")
                    ForEach(tree, id: \.0.id) { f, level in
                        row(f.id, title: f.name, subtitle: nil, level: level, symbol: "folder.fill")
                    }
                } header: {
                    if let place = current.flatMap({ c in library.folders.first { $0.id == c }?.name }) {
                        Text(L("«{0}» está en {1}.", itemName, place)).textCase(nil)
                    }
                } footer: {
                    Text(L("Caben hasta 3 niveles de carpetas."))
                }
                // Una carpeta que ya ocupa 3 niveles no cabe en ninguna otra: sin «Nueva carpeta» (antes la creaba
                // vacía y no movía nada).
                if canUseNewFolder {
                    Section {
                        Button { newName = ""; naming = true } label: { Label(L("Nueva carpeta"), systemImage: "folder.badge.plus") }
                    }
                }
            }
            // Formulario del sistema, como el editor de playlist y la misma hoja en Android.
            .navigationTitle(L("Mover a…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Cancelar")) { dismiss() } } }
            .alert(L("Nueva carpeta"), isPresented: $naming) {
                TextField(L("Nombre"), text: $newName)
                Button(L("Crear")) { if let id = library.createFolder(newName) { move(to: id) } }
                Button(L("Cancelar"), role: .cancel) {}
            }
        }
    }

    private func row(_ target: String?, title: String, subtitle: String?, level: Int, symbol: String) -> some View {
        let reason = blocked(target)
        let here = target == current
        return Button { move(to: target) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(ThemeSurface(radius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary).lineLimit(1)
                    if let line = reason ?? subtitle { Text(line).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if here { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
            }
            .padding(.leading, CGFloat(level) * 24)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        // Filas de 52 pt, como las de Android y los formularios de iOS 26 de la app.
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        // Sin el tinte de los botones de una lista: el único color es la marca de dónde está ahora.
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .opacity(reason != nil ? 0.45 : 1)
        .accessibilityAddTraits(here ? .isSelected : [])
    }

    private func move(to target: String?) {
        switch item {
        case .playlist(let id): library.movePlaylist(id, to: target)
        case .folder(let id): library.moveFolder(id, to: target)
        }
        dismiss()
    }
}

extension String {
    /// nil si está vacío (para elegir un texto por defecto).
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
