import Foundation

// Sincronizar la biblioteca (docs/spec/sync.md §5): unir dos versiones de library.json y poner las marcas a lo que
// ha cambiado. Es la referencia tools/spec/sync.mjs, paso a paso, sobre el JSON (así no se pierde ningún campo que
// la app no conozca). Sólo Foundation: se prueba en Linux con shared/library/sync-unir.json y sync-marcar.json
// (scripts/test-linux.sh). Android: data/SyncModel.kt, igual.

/// Un valor JSON cualquiera.
enum JV: Equatable, Codable {
    case null, bool(Bool), num(Double), str(String), arr([JV]), obj([String: JV])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .num(n) }
        else if let s = try? c.decode(String.self) { self = .str(s) }
        else if let a = try? c.decode([JV].self) { self = .arr(a) }
        else { self = .obj(try c.decode([String: JV].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .num(let n): if n == n.rounded(), abs(n) < 9e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .str(let s): try c.encode(s)
        case .arr(let a): try c.encode(a)
        case .obj(let o): try c.encode(o)
        }
    }
    static func leer(_ data: Data) throws -> JV { try JSONDecoder().decode(JV.self, from: data) }
    func datos() -> Data { (try? JSONEncoder().encode(self)) ?? Data("null".utf8) }

    subscript(_ k: String) -> JV? {
        get { if case .obj(let o) = self { return o[k] }; return nil }
        set { if case .obj(var o) = self { o[k] = newValue; self = .obj(o) } }
    }
    var lista: [JV]? { if case .arr(let a) = self { return a }; return nil }
    var texto: String? { if case .str(let s) = self { return s }; return nil }
    var objeto: [String: JV]? { if case .obj(let o) = self { return o }; return nil }
    var esNulo: Bool { self == .null }

    /// Como `JSON.stringify` de JS con las claves ordenadas (el `canon` de la referencia): sirve para comparar
    /// contenidos igual en las tres implementaciones.
    var canon: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .num(let n): return n == n.rounded() && abs(n) < 9e15 ? String(Int64(n)) : "\(n)"
        case .str(let s): return JV.citar(s)
        case .arr(let a): return "[" + a.map(\.canon).joined(separator: ",") + "]"
        case .obj(let o):
            return "{" + o.keys.sorted(by: JV.menorUtf16).map { JV.citar($0) + ":" + o[$0]!.canon }.joined(separator: ",") + "}"
        }
    }
    static func citar(_ s: String) -> String {
        var r = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\r": r += "\\r"
            case "\t": r += "\\t"
            case "\u{08}": r += "\\b"
            case "\u{0C}": r += "\\f"
            default:
                if u.value < 0x20 { r += String(format: "\\u%04x", u.value) } else { r.unicodeScalars.append(u) }
            }
        }
        return r + "\""
    }
    /// El `<` de las cadenas de JS (por unidades de UTF-16).
    static func menorUtf16(_ a: String, _ b: String) -> Bool { a.utf16.lexicographicallyPrecedes(b.utf16) }
    static func mayorOIgual(_ a: String, _ b: String) -> Bool { !menorUtf16(a, b) }
}

/// Marca de versión `[t, c, d]` (sync.md §5.1).
struct Marca: Comparable {
    var t: Double, c: Double, d: String
    static let cero = Marca(t: 0, c: 0, d: "")
    init(t: Double, c: Double, d: String) { self.t = t; self.c = c; self.d = d }
    init?(_ v: JV?) {
        guard let a = v?.lista, a.count == 3, case .num(let t) = a[0], case .num(let c) = a[1], case .str(let d) = a[2] else { return nil }
        self.init(t: t, c: c, d: d)
    }
    var jv: JV { .arr([.num(t), .num(c), .str(d)]) }
    static func < (x: Marca, y: Marca) -> Bool { SyncModel.cmp(x, y) < 0 }
}

enum SyncModel {
    static let dia: Double = 86_400_000
    static let retencion = 180 * dia
    static let topeBajas = 5000

    static func cmp(_ x: Marca?, _ y: Marca?) -> Int {
        let x = x ?? .cero, y = y ?? .cero
        if x.t != y.t { return x.t < y.t ? -1 : 1 }
        if x.c != y.c { return x.c < y.c ? -1 : 1 }
        return x.d == y.d ? 0 : (menor(x.d, y.d) ? -1 : 1)
    }
    private static func menor(_ a: String, _ b: String) -> Bool { JV.menorUtf16(a, b) }
    static func max(_ x: Marca?, _ y: Marca?) -> Marca { cmp(x, y) >= 0 ? (x ?? .cero) : (y ?? .cero) }
    private static func recortar(_ m: Marca, _ ahora: Double) -> Marca { m.t > ahora + dia ? Marca(t: ahora + dia, c: m.c, d: m.d) : m }

    struct Tipo { let campo: String; let k: String; let idKey: String }
    static let tipos = [
        Tipo(campo: "favorites", k: "favorite", idKey: "id"),
        Tipo(campo: "followedArtists", k: "artist", idKey: "browseId"),
        Tipo(campo: "folders", k: "folder", idKey: "id"),
        Tipo(campo: "albumFolders", k: "albumFolder", idKey: "id"),
        Tipo(campo: "playlists", k: "playlist", idKey: "id"),
    ]
    static let conV: Set<String> = ["folders", "albumFolders", "playlists"]
    static let ordenes = ["playlistOrder", "albumOrder", "musicOrder", "playlistSort", "albumSort", "accountName"]
    static let marcas = ["a", "v", "vCanciones"]
    static let propios: Set<String> = Set(tipos.map(\.campo) + ordenes + ["vOrden", "deleted", "deletedHorizon", "covers"])

    private static func idDe(_ t: Tipo, _ x: JV) -> String { x[t.idKey]?.texto ?? "" }
    private static func sinMarcas(_ x: JV) -> JV {
        guard var o = x.objeto else { return x }
        for k in marcas + ["songs"] { o[k] = nil }
        return .obj(o)
    }
    private static func items(_ l: JV, _ campo: String) -> [JV]? { l[campo]?.lista }
    /// En JS, `lib[campo] ?? []` y «existe» es que la clave esté y no sea null.
    private static func tiene(_ l: JV, _ k: String) -> Bool { if let v = l[k] { return !v.esNulo }; return false }

    private static func clonarRecortado(_ lib: JV?, _ ahora: Double) -> JV {
        guard var l = lib, l.objeto != nil else { return .obj([:]) }
        let r = { (v: JV?) -> JV? in Marca(v).map { recortar($0, ahora).jv } ?? v }
        for t in tipos {
            guard let xs = items(l, t.campo) else { continue }
            l[t.campo] = .arr(xs.map { x in
                var x = x
                for m in marcas where x[m] != nil && !(x[m]!.esNulo) { x[m] = r(x[m]) }
                if let songs = x["songs"]?.lista {
                    x["songs"] = .arr(songs.map { s in var s = s; if s["a"] != nil && !(s["a"]!.esNulo) { s["a"] = r(s["a"]) }; return s })
                }
                return x
            })
        }
        if let bs = l["deleted"]?.lista { l["deleted"] = .arr(bs.map { b in var b = b; b["m"] = r(b["m"]); return b }) }
        if tiene(l, "deletedHorizon") { l["deletedHorizon"] = r(l["deletedHorizon"]) }
        if var vo = l["vOrden"]?.objeto {
            for o in ordenes where vo[o] != nil && !(vo[o]!.esNulo) { vo[o] = r(vo[o]) }
            l["vOrden"] = .obj(vo)
        }
        return l
    }

    /// La marca mayor de toda la biblioteca.
    static func marcaMayor(_ lib: JV?) -> Marca {
        var m = Marca.cero
        guard let lib else { return m }
        for t in tipos {
            for x in items(lib, t.campo) ?? [] {
                for k in marcas { if let v = Marca(x[k]) { m = max(m, v) } }
                for s in x["songs"]?.lista ?? [] { if let a = Marca(s["a"]) { m = max(m, a) } }
            }
        }
        for b in lib["deleted"]?.lista ?? [] { m = max(m, Marca(b["m"])) }
        if let h = Marca(lib["deletedHorizon"]) { m = max(m, h) }
        for o in ordenes { if let v = Marca(lib["vOrden"]?[o]) { m = max(m, v) } }
        return m
    }

    /// H8: marca nueva a lo que no tiene, del final al principio. Devuelve la biblioteca y el siguiente contador.
    static func sellarSinMarca(_ lib: JV, t: Double, c: Double, d: String) -> (lib: JV, c: Double) {
        var l = lib, c = c
        func nueva() -> JV { defer { c += 1 }; return Marca(t: t, c: c, d: d).jv }
        for tp in tipos {
            guard var xs = items(l, tp.campo) else { continue }
            for i in xs.indices.reversed() {
                var x = xs[i]
                if var songs = x["songs"]?.lista {
                    for j in songs.indices.reversed() where !tiene(songs[j], "a") { songs[j]["a"] = nueva() }
                    x["songs"] = .arr(songs)
                }
                if !tiene(x, "a") { x["a"] = nueva() }
                if conV.contains(tp.campo) && !tiene(x, "v") { x["v"] = x["a"] }
                if tp.campo == "playlists" && !tiene(x, "vCanciones") { x["vCanciones"] = x["a"] }
                xs[i] = x
            }
            l[tp.campo] = .arr(xs)
        }
        for o in ordenes where l[o] != nil && !tiene(l["vOrden"] ?? .null, o) {
            var vo = l["vOrden"]?.objeto ?? [:]
            vo[o] = nueva()
            l["vOrden"] = .obj(vo)
        }
        return (l, c)
    }

    /// ¿Tienen lo mismo en lo que se sincroniza? (Colecciones, órdenes, marcas, bajas y portadas; no los recientes ni
    /// lo que es de cada móvil.) Sirve para saber si hay que subir y si hay que poner lo unido en la app.
    static func mismoContenido(_ a: JV, _ b: JV) -> Bool {
        for k in propios where (a[k] ?? .null).canon != (b[k] ?? .null).canon { return false }
        return true
    }

    private static func claveBaja(_ b: JV) -> String {
        "\(b["k"]?.texto ?? "")\u{0}\(b["id"]?.texto ?? "")\u{0}\(b["p"]?.texto ?? "")"
    }

    enum Aviso: String { case puestaAlDia = "puesta_al_dia", nubeAntigua = "nube_antigua", nubeVacia = "nube_vacia" }

    /// Une `local` (el móvil) con `nube` (el bloque bajado; nil si 404). `ahora`: ms del reloj de la app.
    static func unir(_ localIn: JV, _ nubeIn: JV?, ahora: Double, ultimaSync: Marca? = nil, tope: Int = topeBajas) -> (lib: JV, aviso: Aviso?) {
        var local = clonarRecortado(localIn, ahora)
        guard let nubeIn else {
            return (unir(local, .obj([:]), ahora: ahora, ultimaSync: nil, tope: tope).lib, ultimaSync != nil ? .nubeVacia : nil)
        }
        let nube = clonarRecortado(nubeIn, ahora)

        // 1. Bajas.
        var bajas: [String: JV] = [:]
        for b in (local["deleted"]?.lista ?? []) + (nube["deleted"]?.lista ?? []) {
            let k = claveBaja(b)
            if let ya = bajas[k] { if cmp(Marca(b["m"]), Marca(ya["m"])) > 0 { bajas[k] = b } } else { bajas[k] = b }
        }
        var horizonte = max(Marca(local["deletedHorizon"]) ?? .cero, Marca(nube["deletedHorizon"]) ?? .cero)
        let ordenadas = bajas.values.sorted { x, y in
            let c = cmp(Marca(y["m"]), Marca(x["m"]))
            return c != 0 ? c < 0 : menor(claveBaja(x), claveBaja(y))
        }
        var quedan: [JV] = []
        for b in ordenadas {
            let m = Marca(b["m"]) ?? .cero
            if m.t < ahora - retencion || quedan.count >= tope { horizonte = max(horizonte, m) } else { quedan.append(b) }
        }
        let vivas = Set(quedan.map(claveBaja))
        func vivo(_ k: String, _ id: String, _ a: Marca?, _ p: String? = nil) -> Bool {
            let key = "\(k)\u{0}\(id)\u{0}\(p ?? "")"
            guard let b = bajas[key], vivas.contains(key) else { return true }
            return !(cmp(Marca(b["m"]), a ?? .cero) > 0)
        }

        // 2. §5.4.
        var aviso: Aviso? = nil
        if let u = ultimaSync, cmp(marcaMayor(nube), u) < 0 { aviso = .nubeAntigua }
        if let u = ultimaSync, cmp(horizonte, u) > 0, aviso == nil {
            aviso = .puestaAlDia
            for t in tipos {
                guard let xs = items(local, t.campo) else { continue }
                var enNube: [String: JV] = [:]
                for x in items(nube, t.campo) ?? [] { enNube[idDe(t, x)] = x }
                var filtrado = xs.filter { enNube[idDe(t, $0)] != nil || cmp(Marca($0["a"]), u) > 0 }
                if t.campo == "playlists" {
                    filtrado = filtrado.map { p in
                        guard let pn = enNube[idDe(t, p)] else { return p }
                        let ids = Set((pn["songs"]?.lista ?? []).map { $0["id"]?.texto ?? "" })
                        var p = p
                        p["songs"] = .arr((p["songs"]?.lista ?? []).filter { ids.contains($0["id"]?.texto ?? "") || cmp(Marca($0["a"]), u) > 0 })
                        return p
                    }
                }
                local[t.campo] = .arr(filtrado)
            }
        }

        // 3. Colecciones.
        var out: [String: JV] = [:]
        for t in tipos {
            var porId: [String: JV] = [:]
            var orden: [String] = []
            for x in (items(local, t.campo) ?? []) + (items(nube, t.campo) ?? []) {
                let id = idDe(t, x)
                if let ya = porId[id] { porId[id] = fundir(ya, x, t.campo) } else { porId[id] = x; orden.append(id) }
            }
            var xs = orden.compactMap { porId[$0] }.filter { vivo(t.k, idDe(t, $0), Marca($0["a"])) }
            if t.campo == "playlists" {
                xs = xs.map { p in
                    var p = p
                    let pid = idDe(t, p)
                    p["songs"] = .arr((p["songs"]?.lista ?? []).filter { vivo("song", $0["id"]?.texto ?? "", Marca($0["a"]), pid) })
                    return p
                }
            }
            xs.sort { x, y in
                let c = cmp(Marca(y["a"]), Marca(x["a"]))
                return c != 0 ? c < 0 : menor(idDe(t, x), idDe(t, y))
            }
            if !xs.isEmpty || tiene(local, t.campo) || tiene(nube, t.campo) { out[t.campo] = .arr(xs) }
        }

        // 4. Órdenes.
        for o in ordenes {
            if local[o] == nil && nube[o] == nil { continue }
            let vl = Marca(local["vOrden"]?[o]) ?? .cero, vn = Marca(nube["vOrden"]?[o]) ?? .cero
            var c = cmp(vl, vn)
            if c == 0 { c = JV.mayorOIgual((local[o] ?? .null).canon, (nube[o] ?? .null).canon) ? 1 : -1 }
            let (gana, otro) = c > 0 ? (local, nube) : (nube, local)
            let g = tiene(gana, o) ? gana[o] : nil, ot = tiene(otro, o) ? otro[o] : nil
            if (g ?? ot)?.lista != nil {
                var lista = g?.lista ?? []
                for x in ot?.lista ?? [] where !lista.contains(x) { lista.append(x) }
                out[o] = .arr(lista)
            } else if let v = g ?? ot {
                out[o] = v
            }
            var vo = out["vOrden"]?.objeto ?? [:]
            vo[o] = max(vl, vn).jv
            out["vOrden"] = .obj(vo)
        }

        // 5. Portadas.
        if tiene(local, "covers") || tiene(nube, "covers") {
            var covers: [String: JV] = [:]
            func buscar(_ lib: JV, _ id: String) -> JV? { (items(lib, "playlists") ?? []).first { $0["id"]?.texto == id } }
            for p in out["playlists"]?.lista ?? [] {
                let id = p["id"]?.texto ?? ""
                let pl = buscar(local, id), pn = buscar(nube, id)
                var ganaLocal = pn == nil
                if let pl, let pn {
                    var c = cmp(Marca(pl["v"]), Marca(pn["v"]))
                    if c == 0 { c = JV.mayorOIgual(sinMarcas(pl).canon, sinMarcas(pn).canon) ? 1 : -1 }
                    ganaLocal = c > 0
                }
                let (g, o) = ganaLocal ? (local, nube) : (nube, local)
                let gv = g["covers"]?[id], ov = o["covers"]?[id]
                if let cv = (gv != nil && !gv!.esNulo) ? gv : ov { covers[id] = cv }
            }
            out["covers"] = .obj(covers)
        }

        // 6. Lo demás: lo del móvil.
        let claves = Set((local.objeto ?? [:]).keys).union((nube.objeto ?? [:]).keys)
        for k in claves where !propios.contains(k) {
            if let v = localIn[k] { out[k] = v } else { out[k] = nube[k] }
        }

        let finales = quedan.sorted { menor(claveBaja($0), claveBaja($1)) }
        if !finales.isEmpty { out["deleted"] = .arr(finales) }
        if cmp(horizonte, .cero) > 0 { out["deletedHorizon"] = horizonte.jv }
        return (.obj(out), aviso)
    }

    private static func fundir(_ x: JV, _ y: JV, _ campo: String) -> JV {
        var cv = cmp(Marca(x["v"]), Marca(y["v"]))
        if cv == 0 { cv = JV.mayorOIgual(sinMarcas(x).canon, sinMarcas(y).canon) ? 1 : -1 }
        let g = cv > 0 ? x : y
        var r = sinMarcas(g)
        let a = max(Marca(x["a"]), Marca(y["a"]))
        r["a"] = a.jv
        if tiene(x, "v") || tiene(y, "v") { r["v"] = max(Marca(x["v"]), Marca(y["v"])).jv }
        if campo == "playlists" {
            func ids(_ p: JV) -> String { JV.arr((p["songs"]?.lista ?? []).map { $0["id"] ?? .null }).canon }
            var cc = cmp(Marca(x["vCanciones"]), Marca(y["vCanciones"]))
            if cc == 0 { cc = JV.mayorOIgual(ids(x), ids(y)) ? 1 : -1 }
            let (gs, os) = cc > 0 ? (x, y) : (y, x)
            var aDe: [String: Marca] = [:]
            for s in (x["songs"]?.lista ?? []) + (y["songs"]?.lista ?? []) {
                let id = s["id"]?.texto ?? ""
                aDe[id] = max(aDe[id], Marca(s["a"]))
            }
            var songs = gs["songs"]?.lista ?? []
            var vistos = Set(songs.map { $0["id"]?.texto ?? "" })
            for s in os["songs"]?.lista ?? [] where !vistos.contains(s["id"]?.texto ?? "") { songs.append(s); vistos.insert(s["id"]?.texto ?? "") }
            songs = songs.map { s in
                var s = s
                let a = aDe[s["id"]?.texto ?? ""] ?? .cero
                if cmp(a, .cero) > 0 { s["a"] = a.jv } else { s["a"] = nil }
                return s
            }
            r["songs"] = .arr(songs)
            if tiene(x, "vCanciones") || tiene(y, "vCanciones") { r["vCanciones"] = max(Marca(x["vCanciones"]), Marca(y["vCanciones"])).jv }
        }
        if cmp(a, .cero) == 0 { r["a"] = nil }
        return r
    }

    /// Las marcas de lo que ha cambiado entre `previo` (lo último marcado, con marcas; nil la primera vez) y `actual`
    /// (la biblioteca de la app). Cada marca nueva es [t, c++, d]. Devuelve la biblioteca marcada y el contador.
    static func marcar(_ previo: JV?, _ actual: JV, t: Double, c: Double, d: String) -> (lib: JV, c: Double) {
        let p = previo ?? .obj([:])
        var l = actual.objeto != nil ? actual : .obj([:])
        for k in ["deleted", "deletedHorizon", "vOrden"] { l[k] = nil }
        var c = c
        func nueva() -> JV { defer { c += 1 }; return Marca(t: t, c: c, d: d).jv }
        var bajas: [String: JV] = [:]
        for b in p["deleted"]?.lista ?? [] { bajas[claveBaja(b)] = b }
        func baja(_ b: JV) { bajas[claveBaja(b)] = b }
        for tp in tipos {
            var antes: [String: JV] = [:]
            for x in items(p, tp.campo) ?? [] { antes[idDe(tp, x)] = x }
            guard var xs = items(l, tp.campo) else {
                for q in (items(p, tp.campo) ?? []).reversed() { baja(.obj(["k": .str(tp.k), "id": .str(idDe(tp, q)), "m": nueva()])) }
                continue
            }
            let ahora = Set(xs.map { idDe(tp, $0) })
            for i in xs.indices.reversed() {
                var x = xs[i]
                let q = antes[idDe(tp, x)]
                for m in marcas { x[m] = nil }
                if tp.campo == "playlists" {
                    var sq: [String: JV] = [:]
                    for s in q?["songs"]?.lista ?? [] { sq[s["id"]?.texto ?? ""] = s }
                    if var songs = x["songs"]?.lista {
                        for j in songs.indices.reversed() {
                            songs[j]["a"] = nil
                            let a = sq[songs[j]["id"]?.texto ?? ""]?["a"]
                            songs[j]["a"] = (a != nil && !a!.esNulo) ? a! : nueva()
                        }
                        x["songs"] = .arr(songs)
                    }
                    if let q {
                        let ids = Set((x["songs"]?.lista ?? []).map { $0["id"]?.texto ?? "" })
                        for s in (q["songs"]?.lista ?? []).reversed() where !ids.contains(s["id"]?.texto ?? "") {
                            baja(.obj(["k": .str("song"), "id": s["id"] ?? .null, "p": x["id"] ?? .null, "m": nueva()]))
                        }
                    }
                }
                guard let q else {
                    let a = nueva()
                    x["a"] = a
                    if conV.contains(tp.campo) { x["v"] = a }
                    if tp.campo == "playlists" { x["vCanciones"] = a }
                    xs[i] = x
                    continue
                }
                x["a"] = tiene(q, "a") ? q["a"]! : nueva()
                if conV.contains(tp.campo) {
                    x["v"] = sinMarcas(x).canon != sinMarcas(q).canon || !tiene(q, "v") ? nueva() : q["v"]!
                }
                if tp.campo == "playlists" {
                    func ids(_ z: JV) -> String { JV.arr((z["songs"]?.lista ?? []).map { $0["id"] ?? .null }).canon }
                    x["vCanciones"] = ids(x) != ids(q) || !tiene(q, "vCanciones") ? nueva() : q["vCanciones"]!
                }
                xs[i] = x
            }
            l[tp.campo] = .arr(xs)
            for q in (items(p, tp.campo) ?? []).reversed() where !ahora.contains(idDe(tp, q)) {
                baja(.obj(["k": .str(tp.k), "id": .str(idDe(tp, q)), "m": nueva()]))
            }
        }
        for o in ordenes {
            guard let v = l[o] else { continue }
            let antes = p["vOrden"]?[o]
            let igual = v.canon == (p[o] ?? .null).canon && antes != nil && !antes!.esNulo
            var vo = l["vOrden"]?.objeto ?? [:]
            vo[o] = igual ? antes! : nueva()
            l["vOrden"] = .obj(vo)
        }
        if !bajas.isEmpty { l["deleted"] = .arr(bajas.values.sorted { menor(claveBaja($0), claveBaja($1)) }) }
        if tiene(p, "deletedHorizon") { l["deletedHorizon"] = p["deletedHorizon"] }
        return (l, c)
    }

    // MARK: «No sincronizar esto» (PULIR #5; sync.md §5.6): una marca de ESTE móvil, fuera de library.json y del bloque

    /// Las claves «k:id» marcadas más lo que hay dentro de las carpetas marcadas (subcarpetas y sus playlists o álbumes).
    static func soloAquiEntero(_ lib: JV?, _ marcadas: [String]) -> [String] {
        var fuera = Set(marcadas)
        for (campo, k, esAlbum) in [("folders", "folder", false), ("albumFolders", "albumFolder", true)] {
            let carpetas = lib?[campo]?.lista ?? []
            var dentro = Set(carpetas.compactMap { $0["id"]?.texto }.filter { fuera.contains("\(k):\($0)") })
            var cambio = true
            while cambio {
                cambio = false
                for f in carpetas {
                    guard let id = f["id"]?.texto, let padre = f["parent"]?.texto else { continue }
                    if dentro.contains(padre) && !dentro.contains(id) { dentro.insert(id); cambio = true }
                }
            }
            for id in dentro { fuera.insert("\(k):\(id)") }
            for p in lib?["playlists"]?.lista ?? [] {
                let album = p["album"].map { $0 != .null && $0 != .bool(false) } ?? false
                if album == esAlbum, let c = p["folder"]?.texto, dentro.contains(c) { fuera.insert("playlist:\(p["id"]?.texto ?? "")") }
            }
        }
        return fuera.sorted(by: JV.menorUtf16)
    }

    /// La biblioteca sin lo de `claves` (y sin sus portadas): lo que se marca y se sube.
    static func quitarSoloAqui(_ lib: JV?, _ claves: [String]) -> JV? {
        guard var l = lib, let o = l.objeto else { return lib }
        let fuera = Set(claves)
        for t in tipos { if let xs = o[t.campo]?.lista { l[t.campo] = .arr(xs.filter { !fuera.contains("\(t.k):\(idDe(t, $0))") }) } }
        if let c = o["covers"]?.objeto { l["covers"] = .obj(c.filter { !fuera.contains("playlist:\($0.key)") }) }
        return l
    }

    /// Lo que se pone en la app: lo unido, pero lo de `claves` como está en este móvil (o nada, si aquí no está).
    static func ponerSoloAqui(_ unida: JV, _ local: JV?, _ claves: [String]) -> JV {
        guard unida.objeto != nil else { return unida }
        let fuera = Set(claves)
        var out = unida
        for t in tipos {
            let nube = (unida[t.campo]?.lista ?? []).filter { !fuera.contains("\(t.k):\(idDe(t, $0))") }
            let mio = (local?[t.campo]?.lista ?? []).filter { fuera.contains("\(t.k):\(idDe(t, $0))") }
            if !nube.isEmpty || !mio.isEmpty || unida[t.campo] != nil { out[t.campo] = .arr(nube + mio) }
        }
        var covers = (unida["covers"]?.objeto ?? [:]).filter { !fuera.contains("playlist:\($0.key)") }
        for (id, c) in local?["covers"]?.objeto ?? [:] where fuera.contains("playlist:\(id)") { covers[id] = c }
        if unida["covers"] != nil || !covers.isEmpty { out["covers"] = .obj(covers) }
        return out
    }

    // MARK: Estadísticas (sync.md §6)

    static let maxEscuchas = 50_000

    /// Une dos `stats.json`: escuchas sin repetidos, por segundo (empate: videoId), las 50.000 más recientes; `songs`,
    /// unión con la local delante; `clearedAt`, el mayor recortado a ahora + 1 día, y fuera lo de antes. `ahora` en ms.
    static func unirEstadisticas(_ local: JV, _ nube: JV?, ahora: Double, tope: Int = maxEscuchas) -> JV {
        let lim = (ahora / 1000).rounded(.down) + 86_400
        func rec(_ v: JV?) -> Double? { if case .num(let n)? = v { return Swift.min(n, lim) }; return nil }
        let cs = [rec(local["clearedAt"]), rec(nube?["clearedAt"])].compactMap { $0 }
        let cleared = cs.max()
        var vistos = Set<String>()
        var plays: [(String, Double)] = []
        for p in (local["plays"]?.lista ?? []) + (nube?["plays"]?.lista ?? []) {
            guard let a = p.lista, a.count >= 2, let id = a[0].texto, case .num(let t) = a[1] else { continue }
            let k = "\(id)\u{0}\(JV.num(t).canon)"
            if vistos.contains(k) || (cleared.map { t < $0 } ?? false) { continue }
            vistos.insert(k)
            plays.append((id, t))
        }
        plays.sort { x, y in x.1 != y.1 ? x.1 < y.1 : menor(x.0, y.0) }
        if plays.count > tope { plays = Array(plays.suffix(tope)) }
        var songs = nube?["songs"]?.objeto ?? [:]
        for (k, v) in local["songs"]?.objeto ?? [:] { songs[k] = v }
        var out: [String: JV] = ["version": .num(1), "songs": .obj(songs), "plays": .arr(plays.map { .arr([.str($0.0), .num($0.1)]) })]
        if let cleared { out["clearedAt"] = .num(cleared) }
        return .obj(out)
    }
}
