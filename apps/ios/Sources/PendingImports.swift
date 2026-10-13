import Foundation
import SwiftUI

/// Canciones de una importación que no se añadieron («para revisar» sin elegir o no encontradas), por playlist, para
/// volver a buscarlas desde la propia playlist. Sólo en este móvil (`Documents/import_pending.json`). Mismo formato que
/// `PendingImports` en Android: `{"<playlistId>":[{"title","artist","album","duration","isrc","explicit"},…]}`.
@MainActor
final class PendingImports: ObservableObject {
    static let shared = PendingImports()
    @Published private(set) var all: [String: [AMTrack]] = [:]
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("import_pending.json")

    private init() {
        if let data = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([String: [AMTrack]].self, from: data) { all = m }
    }

    func set(_ playlistID: String, _ tracks: [AMTrack]) {
        all[playlistID] = tracks.isEmpty ? nil : tracks
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: url, options: .atomic) }
    }

    func remove(_ playlistID: String, _ track: AMTrack) {
        set(playlistID, (all[playlistID] ?? []).filter { $0 != track })
    }
}

/// «Sin añadir: N canciones» encima de las canciones de una playlist importada.
struct PendingImportRow: View {
    let playlistID: UUID
    @ObservedObject private var pending = PendingImports.shared

    var body: some View {
        if let l = pending.all[playlistID.uuidString], !l.isEmpty {
            NavigationLink { PendingImportView(playlistID: playlistID) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.magnifyingglass").font(.title3).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sin añadir: \(songCount(l.count))").font(.body.weight(.medium))
                        Text("De la importación. Toca para buscarlas otra vez.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// «Sin añadir»: se vuelven a buscar y se elige la versión, que se añade a la playlist. Igual que en Android.
struct PendingImportView: View {
    let playlistID: UUID
    @EnvironmentObject var library: Library
    @ObservedObject private var pending = PendingImports.shared
    @State private var results: [AMTrack: TrackMatch] = [:]
    @State private var searching = false
    @State private var done = 0
    @State private var open: AMTrack?

    private var tracks: [AMTrack] { pending.all[playlistID.uuidString] ?? [] }

    var body: some View {
        Form {
            if tracks.isEmpty {
                Text("No queda ninguna canción por añadir").foregroundStyle(.secondary)
            } else {
                Section {
                    Button { Task { await search() } } label: {
                        Label(searching ? "Buscando…" : "Buscar otra vez", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searching)
                } footer: {
                    Text(searching ? "Buscando en YouTube Music… \(done) de \(tracks.count)"
                         : "Se buscan otra vez en YouTube Music (a veces aparecen versiones nuevas). Elige la buena y se añade a la playlist.")
                }
                Section(songCount(tracks.count)) {
                    ForEach(tracks, id: \.self) { t in
                        let m = results[t]
                        HStack {
                            Button { if m?.candidates.isEmpty == false { open = open == t ? nil : t } } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title)
                                    Text(line(t, m)).font(.footnote).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Button { pending.remove(playlistID.uuidString, t) } label: {
                                Image(systemName: "xmark").foregroundStyle(.secondary).frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Descartar \(t.title)")
                        }
                        if open == t, let m {
                            ForEach(Array(m.candidates.enumerated()), id: \.offset) { j, c in
                                Button {
                                    if let p = library.playlists.first(where: { $0.id == playlistID }) { library.add(c.song, to: p) }
                                    pending.remove(playlistID.uuidString, t)
                                    open = nil
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.song.title)
                                        Text(c.song.artist + (j == 0 ? " · más probable" : "")).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sin añadir")
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }

    private func line(_ t: AMTrack, _ m: TrackMatch?) -> String {
        let d = Int(t.duration)
        var parts = [t.artist].filter { !$0.isEmpty }
        if d > 0 { parts.append(String(format: "%d:%02d", d / 60, d % 60)) }
        var s = parts.joined(separator: " · ")
        if let m { s += "\n" + (m.candidates.isEmpty ? "Sin resultados" : "\(m.candidates.count) posibles") }
        return s
    }

    private func search() async {
        searching = true; done = 0
        let list = tracks
        var out: [AMTrack: TrackMatch] = [:]
        // De 3 en 3, como al importar.
        for chunk in stride(from: 0, to: list.count, by: 3).map({ Array(list[$0..<min($0 + 3, list.count)]) }) {
            await withTaskGroup(of: (AMTrack, TrackMatch).self) { g in
                for t in chunk { g.addTask { (t, await ImportMatcher.matchOne(t)) } }
                for await (t, m) in g { out[t] = m; done += 1 }
            }
        }
        results = out
        searching = false
    }
}
