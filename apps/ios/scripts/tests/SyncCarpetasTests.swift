import Foundation

// PULIR-BLOQUE-2 #1: «las carpetas no se sincronizan». Dos móviles con lo que hace la app de verdad fuera de la
// interfaz: library.json (`LibraryFile`), los órdenes de los ajustes (`LibraryFile.ponerOrdenes` / `adoptarOrdenes`,
// lo mismo que usan `Library.exportData` y `Library.adoptarSync`) y, en medio, `SyncModel.marcar` y `unir` como
// `SyncBiblioteca.sincronizar`, contra un servidor de mentira. Igual que `SyncCarpetasTest` en Android.

// `Song` vive en Client.swift, que no compila en Linux: aquí, el mismo struct (mismas claves).
struct Song: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String
    let thumbnail: URL?
}

var fallos = 0, total = 0
func comprobar(_ ok: Bool, _ que: String) { total += 1; if !ok { fallos += 1; print("FALLA: \(que)") } }

final class Servidor { var bloque: JV?; var etag = 0 }

final class Movil {
    let d: String
    var lib: LibraryFile
    let ajustes: UserDefaults
    var previo: JV?
    var etag = -1
    var c: Double = 1

    init(_ d: String, _ lib: LibraryFile) {
        self.d = d; self.lib = lib
        ajustes = UserDefaults(suiteName: "sync-carpetas-\(d)")!
        ajustes.removePersistentDomain(forName: "sync-carpetas-\(d)")
    }

    /// `Library.exportData` sin portadas.
    func exportar() -> JV {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        var dict = (try! JSONSerialization.jsonObject(with: try! e.encode(lib))) as! [String: Any]
        LibraryFile.ponerOrdenes(en: &dict, de: ajustes)
        return try! JV.leer(try! JSONSerialization.data(withJSONObject: dict))
    }

    /// `Library.adoptarSync`: playlists y carpetas de la más antigua a la más nueva, y los órdenes a los ajustes.
    func adoptar(_ datos: Data) {
        let f = try! LibraryFile.decode(datos)
        lib = LibraryFile(favorites: f.favorites, playlists: f.playlists.reversed(), recents: lib.recents,
                          folders: (f.folders ?? []).reversed(), followedArtists: f.followedArtists,
                          albumFolders: (f.albumFolders ?? []).reversed())
        LibraryFile.adoptarOrdenes((try! JSONSerialization.jsonObject(with: datos)) as! [String: Any], en: ajustes)
    }

    /// Lo mismo que `SyncBiblioteca.sincronizar` (sin cifrar: eso tiene sus vectores).
    func sincronizar(_ s: Servidor, _ ahora: Double) {
        let actual = exportar()
        let t = Swift.max(ahora.rounded(.down), SyncModel.marcaMayor(previo).t + 1)
        let m = SyncModel.marcar(previo, actual, t: t, c: c, d: d)
        c = m.c
        let nube = s.etag == etag ? previo : s.bloque
        let r = SyncModel.unir(m.lib, nube, ahora: ahora).lib
        if nube == nil || !SyncModel.mismoContenido(r, nube!) { s.bloque = r; s.etag += 1 }
        previo = r; etag = s.etag
        if !SyncModel.mismoContenido(r, m.lib) { adoptar(r.datos()) }
    }

    func carpeta(_ id: String) -> PlaylistFolder? { lib.folders?.first { $0.id == id } }
}

let s = Servidor()
let cardio = Playlist(name: "Cardio", folder: "PIERNA"), suelta = Playlist(name: "Suelta")
let a = Movil("TJJTHK2B", LibraryFile(favorites: [], playlists: [cardio, suelta], recents: [], folders: [
    PlaylistFolder(id: "GYM", name: "Gimnasio", icon: "dumbbell.fill", tint: 3),
    PlaylistFolder(id: "PIERNA", name: "Pierna", parent: "GYM"),
], albumFolders: [PlaylistFolder(id: "SETENTA", name: "Años 70", icon: "guitars.fill", tint: 6)]))
a.ajustes.set("custom", forKey: "playlistSort")
a.ajustes.set([suelta.id.uuidString, "folder:GYM"].joined(separator: "\n"), forKey: "playlistOrder")
// B ya tenía su biblioteca (una playlist suya, sin carpetas) y nunca ha tocado «Ordenar por».
let propia = Playlist(name: "Mía")
let b = Movil("WR85D13C", LibraryFile(favorites: [], playlists: [propia], recents: [], folders: nil))
a.sincronizar(s, 1_000)
b.sincronizar(s, 2_000)

comprobar(Set(b.lib.folders?.map(\.id) ?? []) == ["GYM", "PIERNA"], "B tiene las dos carpetas: \(b.lib.folders?.map(\.id) ?? [])")
comprobar(b.carpeta("PIERNA")?.parent == "GYM", "la de dentro sigue dentro")
comprobar(b.carpeta("GYM")?.icon == "dumbbell.fill" && b.carpeta("GYM")?.tint == 3, "icono y color")
comprobar(b.lib.albumFolders?.first?.id == "SETENTA" && b.lib.albumFolders?.first?.tint == 6, "carpeta de álbumes")
comprobar(b.lib.playlists.first { $0.id == cardio.id }?.folder == "PIERNA", "la playlist sigue en su carpeta")
comprobar(Set(b.lib.playlists.map(\.id)) == [cardio.id, suelta.id, propia.id], "las tres playlists")
comprobar(b.ajustes.string(forKey: "playlistSort") == "custom", "el «A mano» de A no lo pisa el de fábrica de B: \(b.ajustes.string(forKey: "playlistSort") ?? "nil")")
comprobar(LibraryOrder.decode(b.ajustes.string(forKey: "playlistOrder") ?? "").contains("folder:GYM"), "la clave folder: llega")

// B cambia la carpeta (nombre, icono y color) y saca la playlist de la de dentro; A lo recibe.
var fb = b.lib.folders!
fb[fb.firstIndex { $0.id == "GYM" }!].name = "Gym"
fb[fb.firstIndex { $0.id == "GYM" }!].icon = "flame.fill"
fb[fb.firstIndex { $0.id == "GYM" }!].tint = 1
var pb = b.lib.playlists
pb[pb.firstIndex { $0.id == cardio.id }!].folder = "GYM"
b.lib = LibraryFile(favorites: [], playlists: pb, recents: [], folders: fb, albumFolders: b.lib.albumFolders)
b.sincronizar(s, 3_000)
a.sincronizar(s, 4_000)
comprobar(a.carpeta("GYM")?.name == "Gym" && a.carpeta("GYM")?.icon == "flame.fill" && a.carpeta("GYM")?.tint == 1, "A recibe el cambio de la carpeta")
comprobar(a.lib.playlists.first { $0.id == cardio.id }?.folder == "GYM", "A recibe el cambio de carpeta de la playlist")

// Sólo cambia el orden: también viaja.
a.ajustes.set(["folder:GYM", suelta.id.uuidString].joined(separator: "\n"), forKey: "playlistOrder")
a.sincronizar(s, 5_000)
b.sincronizar(s, 6_000)
comprobar(LibraryOrder.decode(b.ajustes.string(forKey: "playlistOrder") ?? "").first == "folder:GYM", "el orden nuevo llega")

// A borra la carpeta de dentro: B también la pierde.
a.lib = LibraryFile(favorites: [], playlists: a.lib.playlists, recents: [], folders: a.lib.folders!.filter { $0.id != "PIERNA" },
                    albumFolders: a.lib.albumFolders)
a.sincronizar(s, 7_000)
b.sincronizar(s, 8_000)
comprobar(b.lib.folders?.map(\.id) == ["GYM"], "B pierde la carpeta borrada: \(b.lib.folders?.map(\.id) ?? [])")

// PULIR #6: el nombre de la cuenta viaja (como un orden más) y gana el último cambio; quitarlo también llega.
a.ajustes.set("Mi música", forKey: "accountName")
a.sincronizar(s, 9_000)
b.sincronizar(s, 10_000)
comprobar(b.ajustes.string(forKey: "accountName") == "Mi música", "el nombre de la cuenta llega")
b.ajustes.set("Casa", forKey: "accountName")
b.sincronizar(s, 11_000)
a.sincronizar(s, 12_000)
comprobar(a.ajustes.string(forKey: "accountName") == "Casa", "gana el último cambio")
a.ajustes.set("", forKey: "accountName")
a.sincronizar(s, 13_000)
b.sincronizar(s, 14_000)
comprobar(b.ajustes.string(forKey: "accountName") == "", "quitarlo también llega")
comprobar(LibraryFile.nombreCuentaValido("  Casa  ") == "Casa" && LibraryFile.nombreCuentaValido(String(repeating: "x", count: 41)) == nil
          && LibraryFile.nombreCuentaValido("   ") == "", "la regla del nombre")

print("Carpetas entre dos móviles: \(total - fallos)/\(total) bien")
exit(fallos == 0 ? 0 : 1)
