import Foundation
import SwiftUI

/// Estadísticas de escucha, sólo en este móvil (`Documents/stats.json`, fuera de `library.json`). Cuenta una escucha
/// cuando la canción suena 30 s (o la mitad, si dura menos de un minuto). Mismo formato y reglas que `PlayStats` en
/// Android: `{"version":1,"songs":{"<videoId>":{"title","artist","thumbnail"}},"plays":[["<videoId>",<segundos epoch>],…]}`.
@MainActor
final class PlayStats: ObservableObject {
    static let shared = PlayStats()

    enum Period: String, CaseIterable, Identifiable {
        case month, year, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .month: return "Este mes"
            case .year: return "Este año"
            case .all: return "Siempre"
            }
        }
    }

    struct Play: Equatable { let id: String; let at: Int64 }
    struct Summary {
        let plays: Int, songs: Int, artists: Int
        let topSongs: [(Song, Int)]
        let topArtists: [(String, Int)]
    }

    static let maxPlays = 50_000
    static let countAfter: Double = 30

    @Published private(set) var songs: [String: Song] = [:]
    @Published private(set) var plays: [Play] = []
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("stats.json")

    private init() { load() }

    /// ¿Cuenta ya como escuchada? `duration` ≤ 0 si aún no se sabe.
    nonisolated static func shouldCount(position: Double, duration: Double) -> Bool {
        position >= countAfter || (duration > 0 && duration < 60 && position >= duration / 2)
    }

    func record(_ song: Song, at: Int64 = Int64(Date().timeIntervalSince1970)) {
        songs[song.id] = song
        plays.append(Play(id: song.id, at: at))
        if plays.count > Self.maxPlays { plays.removeFirst(plays.count - Self.maxPlays) }
        save()
    }

    func clear() { songs = [:]; plays = []; save() }

    /// Inicio del periodo en segundos epoch (hora local), o 0 para «Siempre».
    static func since(_ p: Period, now: Date = Date()) -> Int64 {
        let cal = Calendar.current
        switch p {
        case .all: return 0
        case .month: return Int64(cal.date(from: cal.dateComponents([.year, .month], from: now))!.timeIntervalSince1970)
        case .year: return Int64(cal.date(from: cal.dateComponents([.year], from: now))!.timeIntervalSince1970)
        }
    }

    func summary(since: Int64, top: Int = 10) -> Summary {
        let ps = plays.filter { $0.at >= since }
        var bySong: [String: Int] = [:]
        ps.forEach { bySong[$0.id, default: 0] += 1 }
        let ranked = bySong.compactMap { id, n in songs[id].map { ($0, n) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title.lowercased() < $1.0.title.lowercased() }
        var byArtist: [String: Int] = [:]
        ranked.forEach { byArtist[primaryArtist($0.0.artist), default: 0] += $0.1 }
        let artists = byArtist.map { ($0.key, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lowercased() < $1.0.lowercased() }
        return Summary(plays: ps.count, songs: bySong.count, artists: byArtist.count,
                       topSongs: Array(ranked.prefix(top)), topArtists: Array(artists.prefix(5)))
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (id, v) in (o["songs"] as? [String: [String: Any]]) ?? [:] {
            songs[id] = Song(id: id, title: v["title"] as? String ?? "", artist: v["artist"] as? String ?? "", thumbnail: (v["thumbnail"] as? String).flatMap(URL.init(string:)))
        }
        plays = ((o["plays"] as? [[Any]]) ?? []).compactMap { p in
            guard p.count == 2, let id = p[0] as? String, let at = (p[1] as? NSNumber)?.int64Value else { return nil }
            return Play(id: id, at: at)
        }
    }

    private func save() {
        let o: [String: Any] = [
            "version": 1,
            "songs": songs.mapValues { s -> [String: Any] in ["title": s.title, "artist": s.artist, "thumbnail": s.thumbnail.map { $0.absoluteString as Any } ?? NSNull()] },
            "plays": plays.map { [$0.id, $0.at] as [Any] },
        ]
        let url = self.url
        guard let data = try? JSONSerialization.data(withJSONObject: o) else { return }
        DispatchQueue.global(qos: .utility).async { try? data.write(to: url, options: .atomic) }
    }
}

/// «Estadísticas» en Tu música: lo que más escuchas este mes, este año o siempre. Igual que `StatsScreen` en Android.
struct StatsView: View {
    @ObservedObject private var stats = PlayStats.shared
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: Library
    @EnvironmentObject var downloads: DownloadStore
    @State private var period: PlayStats.Period = .month

    var body: some View {
        let s = stats.summary(since: PlayStats.since(period))
        List {
            Section {
                Picker("Periodo", selection: $period) {
                    ForEach(PlayStats.Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            if s.plays == 0 {
                Text("Aún no hay escuchas en este periodo. Cuenta cada canción que suena al menos 30 segundos.")
                    .font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.top, 40)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(Array(s.topSongs.enumerated()), id: \.element.0.id) { i, item in
                        Button { player.play(item.0, in: s.topSongs.map(\.0)) } label: {
                            HStack(spacing: 10) {
                                rank(i)
                                CoverImage(url: item.0.thumb(160)).frame(width: 46, height: 46)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.0.title).font(.body.weight(.medium)).lineLimit(1)
                                    Text(item.0.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(times(item.1, "vez", "veces")).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .glassRow()
                } header: {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(times(s.plays, "escucha", "escuchas")) de \(songCount(s.songs)) y \(times(s.artists, "artista", "artistas"))")
                            .font(.subheadline).foregroundStyle(.secondary).textCase(nil)
                        Text("Lo que más escuchas").font(.title3.bold()).foregroundStyle(.primary).textCase(nil)
                    }
                }
                Section {
                    ForEach(Array(s.topArtists.enumerated()), id: \.element.0) { i, item in
                        NavigationLink {
                            SongListV11View(title: item.0, songs: library.allSongs(including: downloads.songs).filter { primaryArtist($0.artist) == item.0 })
                        } label: {
                            HStack(spacing: 10) {
                                rank(i)
                                CoverImage(url: (s.topSongs.first { primaryArtist($0.0.artist) == item.0 }?.0
                                                 ?? stats.songs.values.first { primaryArtist($0.artist) == item.0 })?.thumb(160))
                                    .frame(width: 46, height: 46).clipShape(Circle())
                                Text(item.0).font(.body.weight(.medium)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(times(item.1, "escucha", "escuchas")).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .glassRow()
                } header: {
                    Text("Tus artistas").font(.title3.bold()).foregroundStyle(.primary).textCase(nil)
                }
            }
            if !stats.plays.isEmpty {
                Section {
                    HoldToConfirmButton(title: "Mantén para borrar las estadísticas") { stats.clear() }
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Se guardan sólo en este móvil y no salen en la copia de la biblioteca.")
                }
            }
        }
        .navigationTitle("Estadísticas")
        .themed()
    }

    private func rank(_ i: Int) -> some View {
        Text("\(i + 1)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            .frame(minWidth: 22, alignment: .trailing)
    }

    private func times(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
}
