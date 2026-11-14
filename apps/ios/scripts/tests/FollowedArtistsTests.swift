// Tests de los artistas seguidos (library.json) y de la mezcla de «Novedades de tus artistas» (3.0, bloque 1), sólo
// Foundation: scripts/test-linux.sh. Compila Sources/LibraryModel.swift y Sources/ReleasesModel.swift (el código de
// verdad) con I18n.swift. Los casos de library.json están en shared/library/ (seguidos.json, esperado-seguidos.json);
// los de la mezcla son los mismos, con los mismos números, que FollowedArtistsTest.kt en Android.
import Foundation

var fallos = 0
func igual<T: Equatable>(_ a: T, _ b: T, _ que: String) {
    if a != b { fallos += 1; print("❌ \(que): \(a) ≠ \(b)") }
}
func cierto(_ c: Bool, _ que: String) { if !c { fallos += 1; print("❌ \(que)") } }

// `Song` vive en Client.swift, que no compila en Linux: aquí, el mismo struct (mismas claves).
struct Song: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String
    let thumbnail: URL?
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "../../shared/library")
func datos(_ nombre: String) -> Data { try! Data(contentsOf: dir.appendingPathComponent(nombre)) }
let esperado = try! JSONSerialization.jsonObject(with: datos("esperado-seguidos.json")) as! [String: Any]

// MARK: Cada copia sale como dice esperado-seguidos.json
for nombre in ["antigua-sin-carpetas.json", "carpetas.json", "seguidos.json"] {
    guard let file = try? LibraryFile.decode(datos(nombre)) else { fallos += 1; print("❌ \(nombre): no se lee"); continue }
    let esp = esperado[nombre] as! [[String: Any]]
    let leidos = file.followedArtists ?? []
    igual(leidos.map(\.browseId), esp.map { $0["browseId"] as! String }, "\(nombre): seguidos y su orden")
    for (a, e) in zip(leidos, esp) {
        igual(a.name, e["name"] as! String, "\(nombre): nombre de \(a.browseId)")
        igual(a.thumbnail?.absoluteString, e["thumbnail"] as? String, "\(nombre): foto de \(a.browseId)")
        igual(a.since, (e["since"] as! NSNumber).int64Value, "\(nombre): since de \(a.browseId)")
    }
}
let seguidos = try! LibraryFile.decode(datos("seguidos.json"))
igual(seguidos.playlists.count, 1, "seguidos.json: la playlist sigue")

// MARK: Copia vieja → nueva: al guardar, sin claves nuevas
let antigua = try! LibraryFile.decode(datos("antigua-sin-carpetas.json"))
let reescrita = String(data: try! JSONEncoder().encode(antigua), encoding: .utf8)!
cierto(!reescrita.contains("followedArtists"), "antigua: no escribe followedArtists")

// MARK: Ida y vuelta
let vuelta = try! LibraryFile.decode(JSONEncoder().encode(seguidos))
igual(vuelta.followedArtists ?? [], seguidos.followedArtists ?? [], "ida y vuelta: seguidos")

// MARK: Nueva → anterior (lector congelado de la 2.2 / 3.0.0-beta.1, Store.swift en 3da75cb)
struct AntiguaPlaylist: Codable {
    var id = UUID(); var name: String; var songs: [Song] = []; var icon: String?; var tint: Int?
    var album: AntiguoAlbum?; var pinned: Bool?
}
struct AntiguoAlbum: Codable { var browseId: String; var artist: String?; var year: String? }
struct AntiguaBiblioteca: Codable { var favorites: [Song]; var playlists: [AntiguaPlaylist]; var recents: [Song]? }
for (como, data) in [("copia", datos("seguidos.json")), ("exportada", try! JSONEncoder().encode(seguidos))] {
    if let vieja = try? JSONDecoder().decode(AntiguaBiblioteca.self, from: data) {
        igual(vieja.playlists.map(\.name), ["Para correr"], "versión anterior lee seguidos.json (\(como)) sin perder nada")
    } else {
        fallos += 1; print("❌ versión anterior no puede leer seguidos.json (\(como))")
    }
}

// MARK: Importar = unir por browseId, sin propagar «dejar de seguir»
let mios = [FollowedArtist(browseId: "UCrosalia", name: "Rosalía (mía)", since: 1731000000000),
            FollowedArtist(browseId: "UCotro", name: "Otro", since: 1731700000000)]
let base = LibraryFile(favorites: [], playlists: [], recents: nil, folders: nil, followedArtists: mios)
let unida = base.merging(seguidos).followedArtists ?? []
igual(unida.map(\.browseId), ["UCrosalia", "UCotro", "UCdemo-michael-bennet", "UCsin-nombre", "UCfoto-rara", "UCsalto", "UCmedio"], "unir: los míos primero y lo nuevo detrás")
igual(unida.first?.name, "Rosalía (mía)", "unir: el mío no cambia de nombre")
igual(unida.first?.since, 1731000000000, "unir: se queda el since más antiguo (el mío)")
let sinRosalia = LibraryFile(favorites: [], playlists: [], recents: nil, folders: nil,
                             followedArtists: FollowedArtists.unfollow("UCrosalia", in: mios))
cierto((sinRosalia.merging(seguidos).followedArtists ?? []).contains { $0.browseId == "UCrosalia" },
       "unir: un «dejar de seguir» no viaja (la copia la vuelve a traer)")
let menosAntiguo = FollowedArtists.merge([FollowedArtist(browseId: "UCa", name: "A", since: 200)],
                                         [FollowedArtist(browseId: "UCa", name: "A", since: 100)])
igual(menosAntiguo.first?.since, 100, "unir: since el más antiguo (de la copia)")

// MARK: Seguir, dejar de seguir y el límite de 500
var lista: [FollowedArtist] = []
lista = FollowedArtists.follow(FollowedArtist(browseId: "UC1", name: "Uno", since: 1), in: lista)!
lista = FollowedArtists.follow(FollowedArtist(browseId: "UC2", name: "Dos", since: 2), in: lista)!
igual(lista.map(\.browseId), ["UC2", "UC1"], "seguir: el último va primero")
igual(FollowedArtists.follow(FollowedArtist(browseId: "UC1", name: "Uno otra vez", since: 3), in: lista)!.count, 2, "seguir dos veces no repite")
igual(FollowedArtists.unfollow("UC2", in: lista).map(\.browseId), ["UC1"], "dejar de seguir")
let llena = (0..<500).map { FollowedArtist(browseId: "UC\($0)", name: "A\($0)", since: Int64($0)) }
cierto(FollowedArtists.follow(FollowedArtist(browseId: "UCnuevo", name: "Nuevo", since: 9), in: llena) == nil, "no más de 500")
igual(FollowedArtists.normalize(llena + [FollowedArtist(browseId: "UCx", name: "X", since: 1)]).count, 500, "al leer, como mucho 500")

// MARK: Mezcla de Novedades
let H: Int64 = 3600 * 1000
let ahora: Int64 = 1_800_000_000_000
func rel(_ id: String, _ year: Int, _ kind: String = "Single") -> ReleaseItem {
    ReleaseItem(id: id, title: id, subtitle: "\(kind) • Artista • \(year)", thumbnail: nil)
}
func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
func seg(_ id: String, _ name: String) -> FollowedArtist { FollowedArtist(browseId: id, name: name, since: 1) }

igual(ReleaseMix.minYear(year: 2026, month: 2), 2025, "año mínimo en febrero")
igual(ReleaseMix.minYear(year: 2026, month: 3), 2026, "año mínimo en marzo")

// Quién sale: todos los seguidos y, si son menos de 8, los más escuchados que no sigues.
let top = ["Bad Bunny", "Rosalía", "Quevedo", "Aitana", "Bizarrap", "Karol G", "Mora", "Feid", "Duki"].map { ($0, fold($0)) }
let pocos = ReleaseMix.sources(followed: [seg("UCmb", "Michael Bennet"), seg("UCros", "ROSALÍA")], top: top,
                               resolved: [fold("Quevedo"): "UCmb"], fold: fold)
igual(pocos.map(\.name), ["Michael Bennet", "ROSALÍA", "Bad Bunny", "Aitana", "Bizarrap", "Karol G", "Mora", "Feid"],
      "fuentes: seguidos y luego los más escuchados hasta 8 (sin los que ya sigues, por nombre o por browseId)")
igual(pocos.filter(\.followed).count, 2, "fuentes: dos seguidos")
igual(pocos[2].key, "name:" + fold("Bad Bunny"), "fuentes: el que no se sabe su browseId va por nombre")
let muchos = (0..<9).map { seg("UC\($0)", "Seguido \($0)") }
igual(ReleaseMix.sources(followed: muchos, top: top, resolved: [:], fold: fold).count, 9, "fuentes: con 9 seguidos, todos y ninguno más")

// Qué se vuelve a pedir: nunca pedidos primero, luego los más antiguos; los de menos de 6 h no; como mucho 8.
var cache = ReleasesCache()
for (i, s) in muchos.enumerated() where i < 6 {
    cache = ReleaseMix.record(cache, key: s.browseId, name: s.name, items: [], now: ahora - Int64(i) * 2 * H)
}
let fuentes9 = ReleaseMix.sources(followed: muchos, top: [], resolved: [:], fold: fold)
igual(ReleaseMix.toRefresh(fuentes9, cache: cache, now: ahora).map(\.key), ["UC6", "UC7", "UC8", "UC5", "UC4", "UC3"],
      "pedir: los nunca pedidos y luego del más antiguo al más nuevo; los de menos de 6 h, no")
igual(ReleaseMix.toRefresh((0..<20).map { ReleaseSource(key: "UCx\($0)", browseId: "UCx\($0)", name: "", followed: true) },
                           cache: ReleasesCache(), now: ahora).count, 8, "pedir: como mucho 8 a la vez")

// «Nuevo»: sigo a alguien nuevo y no se marca su discografía.
var c = ReleaseMix.record(ReleasesCache(), key: "UCnuevo", name: "Nuevo", items: [rel("a1", 2026), rel("a2", 2026, "Álbum")], now: ahora)
let fNuevo = [ReleaseSource(key: "UCnuevo", browseId: "UCnuevo", name: "Nuevo", followed: true)]
igual(ReleaseMix.pick(fNuevo, cache: c, now: ahora, minYear: 2026).filter(\.isNew).count, 0,
      "nuevo: sigo a alguien nuevo y no se marca su discografía")
// En la siguiente consulta, lo que aparece sí.
c = ReleaseMix.record(c, key: "UCnuevo", name: "Nuevo", items: [rel("a3", 2026), rel("a1", 2026), rel("a2", 2026, "Álbum")], now: ahora + 7 * H)
let tras = ReleaseMix.pick(fNuevo, cache: c, now: ahora + 7 * H, minYear: 2026)
igual(tras.map(\.item.id), ["a3", "a1", "a2"], "nuevo: lo nuevo primero")
igual(tras.map(\.isNew), [true, false, false], "nuevo: sólo se marca lo que aparece en una consulta posterior")
igual(ReleaseMix.pick(fNuevo, cache: c, now: ahora + 7 * H + 7 * 24 * H, minYear: 2026).filter(\.isNew).count, 0,
      "nuevo: la marca dura 7 días")
// Uno de los más escuchados que pasas a seguir: lo visto se conserva y no se marca otra vez.
var t = ReleaseMix.record(ReleasesCache(), key: "name:" + fold("Bad Bunny"), name: "Bad Bunny", items: [rel("b1", 2026)], now: ahora)
t = ReleaseMix.resolve(t, folded: fold("Bad Bunny"), browseId: "UCbb")
igual(t.artists["UCbb"]?.items.map(\.id), ["b1"], "resolver: la entrada pasa al browseId")
cierto(t.artists["name:" + fold("Bad Bunny")] == nil, "resolver: sin la entrada por nombre")
t = ReleaseMix.record(t, key: "UCbb", name: "Bad Bunny", items: [rel("b1", 2026)], now: ahora + 7 * H)
igual(ReleaseMix.pick([ReleaseSource(key: "UCbb", browseId: "UCbb", name: "Bad Bunny", followed: true)], cache: t,
                      now: ahora + 7 * H, minYear: 2026).filter(\.isNew).count, 0, "seguir a uno de los más escuchados no marca su discografía")

// Orden: lo nuevo, luego los seguidos y luego los más escuchados; uno por artista por turno; como mucho 12; año mínimo.
var m = ReleasesCache()
m = ReleaseMix.record(m, key: "UCf1", name: "F1", items: [rel("f1a", 2026), rel("f1b", 2026), rel("f1c", 2026), rel("f1viejo", 2024)], now: ahora)
m = ReleaseMix.record(m, key: "UCf2", name: "F2", items: [rel("f2a", 2025), rel("f2b", 2026)], now: ahora)
m = ReleaseMix.record(m, key: "UCt1", name: "T1", items: (1...6).map { rel("t1\($0)", 2026) }, now: ahora)
m = ReleaseMix.record(m, key: "UCt2", name: "T2", items: (1...6).map { rel("t2\($0)", 2026) }, now: ahora)
m = ReleaseMix.record(m, key: "UCt1", name: "T1", items: [rel("t1nuevo", 2026)] + (1...6).map { rel("t1\($0)", 2026) }, now: ahora + 7 * H)
let fMezcla = [ReleaseSource(key: "UCf1", browseId: "UCf1", name: "F1", followed: true),
               ReleaseSource(key: "UCf2", browseId: "UCf2", name: "F2", followed: true),
               ReleaseSource(key: "UCt1", browseId: "UCt1", name: "T1", followed: false),
               ReleaseSource(key: "UCt2", browseId: "UCt2", name: "T2", followed: false)]
let mezcla = ReleaseMix.pick(fMezcla, cache: m, now: ahora + 7 * H, minYear: 2025)
igual(mezcla.map(\.item.id), ["t1nuevo", "f1a", "f2b", "f1b", "f2a", "f1c", "t11", "t21", "t12", "t22", "t13", "t23"],
      "mezcla: nuevo, seguidos y más escuchados, uno por artista por turno, 12")
igual(mezcla.filter(\.isNew).map(\.item.id), ["t1nuevo"], "mezcla: sólo t1nuevo es nuevo")
cierto(!mezcla.contains { $0.item.id == "f1viejo" }, "mezcla: lo de antes del año mínimo no sale")

// Sin red: no se guarda nada nuevo y sale lo último.
igual(ReleaseMix.pick(fMezcla, cache: m, now: ahora + 30 * 24 * H, minYear: 2025).count, 12, "sin red: sale lo de la caché aunque tenga días")

// Limpiar: sólo los seguidos y los 8 más escuchados.
var p = m
p = ReleaseMix.resolve(p, folded: "t1", browseId: "UCt1")
p = ReleaseMix.prune(p, followed: [seg("UCf1", "F1")], topFolded: ["t1"])
igual(Set(p.artists.keys), ["UCf1", "UCt1"], "limpiar: fuera los que ya no salen")

print(fallos == 0 ? "Seguidos y Novedades: todo bien." : "Seguidos y Novedades: \(fallos) fallos.")
exit(fallos == 0 ? 0 : 1)
