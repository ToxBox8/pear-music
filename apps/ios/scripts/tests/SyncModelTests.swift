import Foundation

// Los casos comunes de la sync (shared/library/sync-unir.json y sync-marcar.json) con SyncModel.swift: los mismos que
// pasan la referencia (tools/spec/vectores.test.mjs) y Android (SyncModelTest).
let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "../../shared/library"
var fallos = 0, total = 0
func comprobar(_ ok: Bool, _ que: String) { total += 1; if !ok { fallos += 1; print("FALLA: \(que)") } }

let unirJ = try JV.leer(try Data(contentsOf: URL(fileURLWithPath: "\(dir)/sync-unir.json")))
let ahora: Double = { if case .num(let n) = unirJ["ahora"]! { return n }; return 0 }()
let topeDef: Int = { if case .num(let n) = unirJ["tope_por_defecto"]! { return Int(n) }; return 5000 }()
for c in unirJ["casos"]!.lista! {
    let nombre = c["nombre"]!.texto!
    var local = c["local"]!
    if let s = c["sellar"], s != .null, case .num(let t) = s["t"]!, case .num(let cc) = s["c"]! {
        local = SyncModel.sellarSinMarca(local, t: t, c: cc, d: s["d"]!.texto!).lib
    }
    let nube: JV? = (c["nube"] == nil || c["nube"] == .null) ? nil : c["nube"]
    let us = Marca(c["ultimaSync"])
    var tope = topeDef
    if case .num(let n)? = c["tope"] { tope = Int(n) }
    let r = SyncModel.unir(local, nube, ahora: ahora, ultimaSync: us, tope: tope)
    comprobar(r.lib == c["esperado"]!, "\(nombre)\n  sale:     \(r.lib.canon)\n  esperado: \(c["esperado"]!.canon)")
    comprobar((r.aviso?.rawValue).map(JV.str) ?? .null == (c["aviso"] ?? .null), "\(nombre): aviso \(String(describing: r.aviso))")
    if c["conmutativo"] == .bool(true), let nube {
        let r2 = SyncModel.unir(nube, local, ahora: ahora, ultimaSync: us, tope: tope)
        comprobar(r2.lib == c["esperado"]!, "\(nombre) (al revés)")
    }
}

let marcarJ = try JV.leer(try Data(contentsOf: URL(fileURLWithPath: "\(dir)/sync-marcar.json")))
for c in marcarJ["casos"]!.lista! {
    let n = c["nueva"]!
    guard case .num(let t) = n["t"]!, case .num(let cc) = n["c"]!, case .num(let esperadoC) = c["c"]! else { fatalError() }
    let previo: JV? = c["previo"] == .null ? nil : c["previo"]
    let r = SyncModel.marcar(previo, c["actual"]!, t: t, c: cc, d: n["d"]!.texto!)
    comprobar(r.lib == c["esperado"]!, "marcar: \(c["nombre"]!.texto!)\n  sale:     \(r.lib.canon)\n  esperado: \(c["esperado"]!.canon)")
    comprobar(r.c == esperadoC, "marcar: \(c["nombre"]!.texto!): contador \(r.c) en vez de \(esperadoC)")
}

let estJ = try JV.leer(try Data(contentsOf: URL(fileURLWithPath: "\(dir)/sync-estadisticas.json")))
let ahoraE: Double = { if case .num(let n) = estJ["ahora"]! { return n }; return 0 }()
for c in estJ["casos"]!.lista! {
    var tope = SyncModel.maxEscuchas
    if case .num(let n)? = c["tope"] { tope = Int(n) }
    let r = SyncModel.unirEstadisticas(c["local"]!, c["nube"], ahora: ahoraE, tope: tope)
    comprobar(r == c["esperado"]!, "estadísticas: \(c["nombre"]!.texto!)\n  sale:     \(r.canon)\n  esperado: \(c["esperado"]!.canon)")
}

// canon igual que JSON.stringify de JS (con claves ordenadas por UTF-16).
comprobar(JV.obj(["b": .num(1), "a": .arr([.str("ñ\"\n"), .bool(true), .null, .num(1.5)])]).canon == #"{"a":["ñ\"\n",true,null,1.5],"b":1}"#, "canon")
comprobar(JV.menorUtf16("\u{FF5E}", "\u{1F600}") == false && JV.menorUtf16("\u{1F600}", "\u{FF5E}"), "orden UTF-16 como JS")
// Ida y vuelta: leer y escribir no cambia nada.
comprobar(try JV.leer(unirJ.datos()) == unirJ, "ida y vuelta del JSON")

// Dos móviles (como SyncBiblioteca, con un servidor de mentira): A y B editan la misma playlist sin verse; B choca
// (409), baja, une y vuelve a subir. Igual que SyncModelTest.dosMovilesEditanLaMismaPlaylistSinPerderNada (Android).
final class Servidor { var bloque: JV?; var etag = 0 }
final class Movil { let d: String; var previo: JV?; var etag = -1; var c: Double = 1; init(_ d: String) { self.d = d } }
func sincronizar(_ m: Movil, _ actual: JV, _ s: Servidor, _ ahora: Double, choqueAntes: (() -> Void)? = nil) -> JV {
    let mk = SyncModel.marcar(m.previo, actual, t: max(ahora, SyncModel.marcaMayor(m.previo).t + 1), c: m.c, d: m.d)
    m.c = mk.c
    var choque = choqueAntes
    for _ in 0..<3 {
        let nube = s.etag == m.etag ? m.previo : s.bloque
        let etag = s.etag
        let u = SyncModel.unir(mk.lib, nube, ahora: ahora).lib
        if nube == nil || !SyncModel.mismoContenido(u, nube!) {
            choque?(); choque = nil
            if s.etag != etag { continue }
            s.bloque = u; s.etag += 1
        }
        m.previo = u; m.etag = s.etag
        return u
    }
    fatalError("tres choques")
}
let base = try JV.leer(Data(#"""
{"favorites":[{"id":"f1","title":"Uno"}],
 "folders":[{"id":"F","name":"Verano","icon":"sun.max.fill","tint":2}],
 "albumFolders":[{"id":"AF","name":"Años 70","icon":"guitars.fill","tint":6}],
 "followedArtists":[{"browseId":"UC1","name":"Artista"}],
 "playlists":[{"id":"P","name":"Viaje","folder":"F","songs":[{"id":"s1"},{"id":"s2"}]},
              {"id":"AL","name":"Currents","album":{"browseId":"MPREb_x"},"folder":"AF","songs":[{"id":"t1"}]}],
 "playlistOrder":["folder:F","P"],"playlistSort":"manual","recents":[{"id":"r1"}]}
"""#.utf8))
func cambiar(_ l: JV, _ f: (inout [JV]) -> Void) -> JV { var l = l; var ps = l["playlists"]!.lista!; f(&ps); l["playlists"] = .arr(ps); return l }
let srv = Servidor(), ma = Movil("TJJTHK2B"), mb = Movil("WR85D13C")
_ = sincronizar(ma, base, srv, 1000)
_ = sincronizar(mb, base, srv, 1001)
let libA = cambiar(base) { ps in var s = ps[0]["songs"]!.lista!; s.append(.obj(["id": .str("sA")])); ps[0]["songs"] = .arr(s) }
var libB = cambiar(base) { ps in ps[0]["name"] = .str("Lisboa"); var s = ps[0]["songs"]!.lista!; s.insert(.obj(["id": .str("sB")]), at: 0); ps[0]["songs"] = .arr(s) }
libB["favorites"] = .arr([])
let finB = sincronizar(mb, libB, srv, 3000) { _ = sincronizar(ma, libA, srv, 2000) }
let finA = sincronizar(ma, libA, srv, 4000)
comprobar(SyncModel.mismoContenido(finA, finB), "dos móviles: acaban igual")
let pFin = finA["playlists"]!.lista!.first { $0["id"]?.texto == "P" }!
comprobar(pFin["name"]?.texto == "Lisboa", "dos móviles: el renombrado de B")
comprobar(Set(pFin["songs"]!.lista!.compactMap { $0["id"]?.texto }) == ["sB", "s1", "s2", "sA"], "dos móviles: las canciones de los dos")
comprobar(finA["favorites"]?.canon == "[]", "dos móviles: la favorita que quitó B")
comprobar(finA["folders"]?.lista?.first?["icon"]?.texto == "sun.max.fill", "dos móviles: icono de la carpeta")
comprobar(finA["albumFolders"]?.lista?.first?["icon"]?.texto == "guitars.fill", "dos móviles: carpeta de álbumes")
comprobar(finA["playlists"]!.lista!.first { $0["id"]?.texto == "AL" }?["folder"]?.texto == "AF", "dos móviles: el álbum en su carpeta")
comprobar(finA["followedArtists"]?.lista?.first?["browseId"]?.texto == "UC1", "dos móviles: el seguido")
func enLaApp(_ l: JV) -> JV { var l = l; l["playlists"] = .arr(l["playlists"]!.lista!.reversed()); return l }
let e = srv.etag
_ = sincronizar(ma, enLaApp(finA), srv, 5000); _ = sincronizar(mb, enLaApp(finB), srv, 5000)
comprobar(srv.etag == e, "dos móviles: después, nada que subir")

// «No sincronizar esto» (sync.md §5.6): shared/library/sync-solo-aqui.json, como la referencia y Android.
let soloJ = try JV.leer(try Data(contentsOf: URL(fileURLWithPath: "\(dir)/sync-solo-aqui.json")))
for c in soloJ["casos"]!.lista! {
    let n = c["nombre"]!.texto!
    let claves = SyncModel.soloAquiEntero(c["lib"], c["marcadas"]!.lista!.map { $0.texto! })
    comprobar(claves == c["claves"]!.lista!.map { $0.texto! }, "solo aquí: \(n): claves \(claves)")
    comprobar(SyncModel.quitarSoloAqui(c["lib"], claves) == c["sinSoloAqui"], "solo aquí: \(n): quitar")
    comprobar(SyncModel.ponerSoloAqui(c["unida"]!, c["lib"], claves) == c["enLaApp"], "solo aquí: \(n): poner")
}

print("SyncModel: \(total - fallos)/\(total) bien")
exit(fallos == 0 ? 0 : 1)
