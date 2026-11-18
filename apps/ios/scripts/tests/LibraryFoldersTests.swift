// Tests de library.json con carpetas (3.0, bloque 1), sólo Foundation: scripts/test-linux.sh.
// Compila Sources/LibraryModel.swift (el código de verdad que usa Library) con I18n.swift. Los casos y lo que tiene
// que salir están en shared/library/, los mismos que lee PlaylistFoldersTest.kt en Android.
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
let esperado = try! JSONSerialization.jsonObject(with: datos("esperado.json")) as! [String: Any]

// MARK: Cada copia sale como dice esperado.json
let todasLasCopias = ["antigua-sin-carpetas.json", "carpetas.json", "carpetas-rotas.json", "carpetas-albumes.json", "carpetas-iconos.json"]
/// Comprueba un árbol de carpetas (`folders` o `albumFolders`) contra su parte de esperado.json.
func arbol(_ leidas: [PlaylistFolder], _ esp: [String: [String: Any]], _ que: String) {
    igual(Set(leidas.map(\.id)), Set(esp.keys), "\(que): carpetas")
    for f in leidas {
        guard let e = esp[f.id] else { continue }
        igual(f.name, e["name"] as! String, "\(que): nombre de \(f.id)")
        igual(f.parent, e["parent"] as? String, "\(que): carpeta de arriba de \(f.id)")
        if e.keys.contains("icon") { igual(f.icon, e["icon"] as? String, "\(que): icono guardado de \(f.name)") }
        if e.keys.contains("tint") { igual(f.tint, e["tint"] as? Int, "\(que): color guardado de \(f.name)") }
        if e.keys.contains("shownIcon") { igual(f.shownIcon, e["shownIcon"] as? String, "\(que): icono pintado de \(f.name)") }
        if e.keys.contains("shownTint") { igual(f.shownTint, e["shownTint"] as? Int, "\(que): color pintado de \(f.name)") }
        cierto(PlaylistFolders.depth(f.id, in: leidas) <= PlaylistFolders.maxDepth, "\(que): \(f.name) pasa de 3 niveles")
    }
}
for nombre in todasLasCopias {
    guard let file = try? LibraryFile.decode(datos(nombre)) else { fallos += 1; print("❌ \(nombre): no se lee"); continue }
    let esp = esperado[nombre] as! [String: Any]
    arbol(file.folders ?? [], esp["folders"] as! [String: [String: Any]], nombre)
    arbol(file.albumFolders ?? [], esp["albumFolders"] as! [String: [String: Any]], "\(nombre) (álbumes)")
    let listas = esp["playlists"] as! [String: Any]
    igual(Set(file.playlists.map(\.id.uuidString)), Set(listas.keys), "\(nombre): playlists")
    for p in file.playlists {
        igual(p.folder, listas[p.id.uuidString] as? String, "\(nombre): carpeta de \(p.name)")
    }
}

// MARK: Carpetas de álbumes (T15): albumOrder con claves folder:, y «Tus álbumes» todos juntos
let albumesCopia = try! LibraryFile.decode(datos("carpetas-albumes.json"))
let albumesCrudo = try! JSONSerialization.jsonObject(with: datos("carpetas-albumes.json")) as! [String: Any]
let albumesEsp = esperado["carpetas-albumes.json"] as! [String: Any]
let ordenAlbumes = albumesCrudo["albumOrder"] as! [String]
igual(LibraryOrder.albumFolderKeys(ordenAlbumes, albumFolders: albumesCopia.albumFolders ?? []),
      albumesEsp["albumFolderKeys"] as! [String], "álbumes: claves folder: que valen")
let enAlbumes = Array(albumesCopia.playlists.filter { $0.album != nil }.reversed()) // como Library.albums
igual(LibraryOrder.albums(enAlbumes, sort: "custom", order: ordenAlbumes).map(\.id.uuidString),
      albumesEsp["albumsShown"] as! [String], "álbumes: «Tus álbumes» los enseña todos, sin las claves folder:")
// Ordenar «Tus álbumes» a mano no borra las claves folder: ni las mueve de sitio.
let p103 = "0000000A-0000-0000-0000-00000000E103", p104 = "0000000A-0000-0000-0000-00000000E104"
let reordenado = LibraryOrder.savingAlbums([p103, p104, "0000000A-0000-0000-0000-00000000E108"], into: ordenAlbumes)
igual(reordenado.filter { LibraryOrder.folderID($0) != nil }, ordenAlbumes.filter { LibraryOrder.folderID($0) != nil },
      "álbumes: al ordenar se conservan las claves folder:, en su orden")
igual(reordenado.filter { LibraryOrder.folderID($0) == nil }, [p103, p104, "0000000A-0000-0000-0000-00000000E108"],
      "álbumes: al ordenar queda el orden nuevo")
igual(reordenado.firstIndex(of: "folder:0000000E-0000-0000-0000-00000000E001"), 0, "álbumes: la clave de la carpeta sigue delante")
// Una clave folder: de un álbum en playlistOrder no pinta nada en Playlists.
let nivelPlaylists = LibraryOrder.level(nil, playlists: albumesCopia.playlists.filter { $0.album == nil },
                                         folders: albumesCopia.folders ?? [], sort: "custom",
                                         order: albumesCrudo["playlistOrder"] as! [String], smartInPlaylists: false)
cierto(!nivelPlaylists.contains("folder:0000000E-0000-0000-0000-00000000E001"), "álbumes: una carpeta de álbumes no sale en Playlists")
// Borrar una carpeta de álbumes sube lo de dentro un nivel y nunca borra álbumes.
let (sinAnos70, albumesTras) = PlaylistFolders.delete("0000000E-0000-0000-0000-00000000E001", folders: albumesCopia.albumFolders!,
                                                      members: albumesCopia.playlists)
igual(sinAnos70.first { $0.id == "0000000E-0000-0000-0000-00000000E002" }?.parent, nil, "álbumes: borrar sube la subcarpeta")
igual(albumesTras.count, albumesCopia.playlists.count, "álbumes: borrar no borra álbumes")
igual(albumesTras.first { $0.id.uuidString == p103 }?.folder, nil, "álbumes: borrar saca el álbum de la carpeta")
// Unir: las carpetas de álbumes propias no cambian (nombre, sitio, icono ni color) y tus álbumes no cambian de carpeta.
let entranteAlbumes = LibraryFile(
    favorites: [],
    playlists: [{ var p = albumesCopia.playlists.first { $0.id.uuidString == p103 }!; p.folder = nil; return p }(),
                Playlist(id: UUID(uuidString: "0000000A-0000-0000-0000-00000000E120")!, name: "Nuevo en Directos",
                         album: AlbumInfo(browseId: "MPREb_new", subtitle: "Álbum • X • 1971"),
                         folder: "0000000E-0000-0000-0000-00000000E002")],
    recents: nil, folders: nil,
    albumFolders: [PlaylistFolder(id: "0000000E-0000-0000-0000-00000000E001", name: "70s", parent: "0000000E-0000-0000-0000-00000000E006",
                                  icon: "star.fill", tint: 1),
                   PlaylistFolder(id: "0000000F-0000-0000-0000-00000000F102", name: "Choca con Pierna"),
                   PlaylistFolder(id: "0000000E-0000-0000-0000-00000000E030", name: "Nueva de álbumes")])
let unidaAlbumes = albumesCopia.merging(entranteAlbumes)
let a70 = unidaAlbumes.albumFolders?.first { $0.id == "0000000E-0000-0000-0000-00000000E001" }
igual(a70?.name, "Años 70", "unir álbumes: la carpeta propia no cambia de nombre")
igual(a70?.parent, nil, "unir álbumes: ni de sitio")
igual(a70?.icon, "guitars.fill", "unir álbumes: ni de icono")
igual(a70?.tint, 6, "unir álbumes: ni de color")
cierto(unidaAlbumes.albumFolders?.contains { $0.id == "0000000E-0000-0000-0000-00000000E030" } == true, "unir álbumes: llega la nueva")
cierto(unidaAlbumes.albumFolders?.contains { $0.id == "0000000F-0000-0000-0000-00000000F102" } == false,
       "unir álbumes: una que repite el id de una de playlists no entra")
igual(unidaAlbumes.playlists.first { $0.id.uuidString == p103 }?.folder, "0000000E-0000-0000-0000-00000000E001",
      "unir álbumes: tu álbum no cambia de carpeta")
igual(unidaAlbumes.playlists.first { $0.name == "Nuevo en Directos" }?.folder, "0000000E-0000-0000-0000-00000000E002",
      "unir álbumes: el nuevo llega en su carpeta")

// MARK: Iconos y colores de carpeta (T16): ida y vuelta, también con los valores que no se conocen
let iconos = try! LibraryFile.decode(datos("carpetas-iconos.json"))
let iconosJSON = String(data: try! JSONEncoder().encode(iconos), encoding: .utf8)!
let iconosVuelta = try! LibraryFile.decode(Data(iconosJSON.utf8))
igual(iconosVuelta.folders ?? [], iconos.folders ?? [], "iconos: ida y vuelta de las carpetas")
igual(iconosVuelta.albumFolders ?? [], iconos.albumFolders ?? [], "iconos: ida y vuelta de las carpetas de álbumes")
let iconosEscritos = (try! JSONSerialization.jsonObject(with: Data(iconosJSON.utf8)) as! [String: Any])["folders"] as! [[String: Any]]
for f in iconosEscritos {
    let id = f["id"] as! String
    if id.hasSuffix("F207") { cierto(f["tint"] == nil, "iconos: un tint en texto no se vuelve a escribir") }
    if id.hasSuffix("F208") || id.hasSuffix("F209") { cierto(f["icon"] == nil, "iconos: un icono numérico o vacío no se vuelve a escribir") }
    if id.hasSuffix("F203") { igual(f["icon"] as? String, "rocket.fill", "iconos: el icono desconocido se escribe tal cual") }
    if id.hasSuffix("F204") { igual(f["tint"] as? Int, 8, "iconos: el color 8 se escribe tal cual") }
}
// Los 24 iconos son los del editor de playlists y hay tantas paletas como en tokens.json.
igual(PlaylistIcons.names.count, 24, "iconos: son 24")
igual(Set(PlaylistIcons.names).count, 24, "iconos: sin repetir")
let tokens = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("../design/tokens.json"))) as! [String: Any]
igual(PlaylistIcons.paletteRange.count, (tokens["playlistPalettes"] as! [Any]).count, "iconos: tantos colores como playlistPalettes")

// MARK: Copia vieja → versión nueva: igual que antes y, al guardar, sin claves nuevas
let antigua = try! LibraryFile.decode(datos("antigua-sin-carpetas.json"))
igual(antigua.playlists.count, 3, "antigua: 3 listas")
igual(antigua.playlists.first { $0.name == "Domingo lento" }?.pinned, true, "antigua: fijada")
igual(antigua.playlists.first { $0.name == "GENESIS" }?.album?.artist, "Michael Bennet", "antigua: álbum")
let reescrita = String(data: try! JSONEncoder().encode(antigua), encoding: .utf8)!
cierto(!reescrita.contains("\"folders\"") && !reescrita.contains("\"folder\"") && !reescrita.contains("\"albumFolders\""),
       "antigua: no escribe folders, folder ni albumFolders")

// MARK: Ida y vuelta con carpetas
let carpetas = try! LibraryFile.decode(datos("carpetas.json"))
let vuelta = try! LibraryFile.decode(JSONEncoder().encode(carpetas))
igual(vuelta.folders ?? [], carpetas.folders ?? [], "ida y vuelta: carpetas")
igual(vuelta.playlists.map(\.folder), carpetas.playlists.map(\.folder), "ida y vuelta: playlists")
let albumesVuelta = try! LibraryFile.decode(JSONEncoder().encode(albumesCopia))
igual(albumesVuelta.albumFolders ?? [], albumesCopia.albumFolders ?? [], "ida y vuelta: carpetas de álbumes")
igual(albumesVuelta.folders ?? [], albumesCopia.folders ?? [], "ida y vuelta: carpetas con álbumes al lado")
igual(albumesVuelta.playlists.map(\.folder), albumesCopia.playlists.map(\.folder), "ida y vuelta: álbumes en sus carpetas")

// MARK: Versión nueva → versión anterior (lector congelado de la 2.2 / 3.0.0-beta.1, Store.swift en 3da75cb)
struct AntiguaPlaylist: Codable {
    var id = UUID(); var name: String; var songs: [Song] = []; var icon: String?; var tint: Int?
    var album: AntiguoAlbum?; var pinned: Bool?
}
struct AntiguoAlbum: Codable { var browseId: String; var artist: String?; var year: String? }
struct AntiguaBiblioteca: Codable { var favorites: [Song]; var playlists: [AntiguaPlaylist]; var recents: [Song]? }

for nombre in ["carpetas.json", "carpetas-rotas.json", "carpetas-albumes.json", "carpetas-iconos.json"] {
    // Tal cual llega en la copia y tal cual la escribe la versión nueva.
    for (como, data) in [("copia", datos(nombre)), ("exportada", try! JSONEncoder().encode(LibraryFile.decode(datos(nombre))))] {
        if let vieja = try? JSONDecoder().decode(AntiguaBiblioteca.self, from: data) {
            let n = (esperado[nombre] as! [String: Any])["playlists"] as! [String: Any]
            igual(Set(vieja.playlists.map(\.id.uuidString)), Set(n.keys), "versión anterior lee \(nombre) (\(como)) sin perder playlists")
        } else {
            fallos += 1; print("❌ versión anterior no puede leer \(nombre) (\(como))")
        }
    }
}

// MARK: Importar = unir
let local = carpetas
let entrante = LibraryFile(
    favorites: [],
    playlists: [
        { var p = carpetas.playlists[0]; p.folder = nil; p.name = "Otro nombre"; return p }(), // ya la tengo: no cambia
        Playlist(id: UUID(uuidString: "0000000A-0000-0000-0000-00000000B010")!, name: "Nueva en Gimnasio", folder: "0000000F-0000-0000-0000-00000000F001"),
        Playlist(id: UUID(uuidString: "0000000A-0000-0000-0000-00000000B011")!, name: "Nueva en la de 4.º nivel", folder: "0000000F-0000-0000-0000-00000000F005"),
    ],
    recents: nil,
    folders: [
        PlaylistFolder(id: "0000000F-0000-0000-0000-00000000F001", name: "Gym"),                    // ya existe: gana la mía
        PlaylistFolder(id: "0000000F-0000-0000-0000-00000000F005", name: "Martes", parent: "0000000F-0000-0000-0000-00000000F003"), // sería el 4.º
    ])
let unida = local.merging(entrante)
let porID = Dictionary(uniqueKeysWithValues: (unida.folders ?? []).map { ($0.id, $0) })
igual(porID["0000000F-0000-0000-0000-00000000F001"]?.name, "Gimnasio", "unir: la carpeta propia no cambia")
igual(porID["0000000F-0000-0000-0000-00000000F005"]?.parent, nil, "unir: la del 4.º nivel queda arriba")
igual(unida.playlists.count, local.playlists.count + 2, "unir: llegan las 2 nuevas")
igual(unida.playlists.first { $0.id.uuidString == "0000000A-0000-0000-0000-00000000B001" }?.folder, "0000000F-0000-0000-0000-00000000F001", "unir: la que ya tenía no se mueve")
igual(unida.playlists.first { $0.id.uuidString == "0000000A-0000-0000-0000-00000000B001" }?.name, "Cardio 160 bpm", "unir: la que ya tenía no cambia de nombre")
igual(unida.playlists.first { $0.name == "Nueva en Gimnasio" }?.folder, "0000000F-0000-0000-0000-00000000F001", "unir: la nueva llega en su carpeta")
igual(unida.playlists.first { $0.name == "Nueva en la de 4.º nivel" }?.folder, "0000000F-0000-0000-0000-00000000F005", "unir: la nueva sigue a su carpeta")

// MARK: Crear, mover, borrar, ruta (mismos casos que PlaylistFoldersTest.kt)
let fs = carpetas.folders!
let gym = "0000000F-0000-0000-0000-00000000F001", pierna = "0000000F-0000-0000-0000-00000000F002"
let lunes = "0000000F-0000-0000-0000-00000000F003", viajes = "0000000F-0000-0000-0000-00000000F004"
cierto(PlaylistFolders.canCreate(in: nil, folders: fs), "crear arriba")
cierto(PlaylistFolders.canCreate(in: pierna, folders: fs), "crear en el 2.º nivel")
cierto(!PlaylistFolders.canCreate(in: lunes, folders: fs), "no crear en el 3.º nivel")
cierto(!PlaylistFolders.canMove(gym, to: viajes, folders: fs), "Gimnasio (3 niveles) no cabe en Viajes")
cierto(PlaylistFolders.canMove(lunes, to: viajes, folders: fs), "Lunes cabe en Viajes")
cierto(!PlaylistFolders.canMove(gym, to: pierna, folders: fs), "no dentro de una suya")
cierto(!PlaylistFolders.canMove(gym, to: gym, folders: fs), "no dentro de sí misma")
cierto(PlaylistFolders.canMove(pierna, to: nil, folders: fs), "subir arriba del todo")
igual(PlaylistFolders.path(lunes, in: fs).map(\.name), ["Gimnasio", "Pierna", "Lunes"], "ruta")
igual(PlaylistFolders.members(of: gym, folders: fs, in: carpetas.playlists).map(\.name), ["Cardio 160 bpm", "Pierna y glúteo", "Lunes duro"], "Reproducir carpeta")
let (sinPierna, listas) = PlaylistFolders.delete(pierna, folders: fs, members: carpetas.playlists)
igual(sinPierna.count, 3, "borrar: una carpeta menos")
igual(sinPierna.first { $0.id == lunes }?.parent, gym, "borrar: la subcarpeta sube un nivel")
igual(listas.count, carpetas.playlists.count, "borrar: no se borra ninguna playlist")
igual(listas.first { $0.name == "Pierna y glúteo" }?.folder, gym, "borrar: la playlist sube un nivel")
let (_, raiz) = PlaylistFolders.delete(gym, folders: fs, members: carpetas.playlists)
igual(raiz.first { $0.name == "Cardio 160 bpm" }?.folder, nil, "borrar la de arriba: a Playlists")

// MARK: Orden de cada nivel (mismos casos que PlaylistFoldersTest.kt)
let propias = carpetas.playlists.filter { $0.album == nil }
let b001 = "0000000A-0000-0000-0000-00000000B001", b004 = "0000000A-0000-0000-0000-00000000B004"
let f002 = "0000000F-0000-0000-0000-00000000F002"
let kGym = LibraryOrder.key(folder: gym), kViajes = LibraryOrder.key(folder: viajes), kF002 = LibraryOrder.key(folder: f002)
igual(kGym, "folder:" + gym, "clave de carpeta con prefijo")
igual(LibraryOrder.folderID(kGym), gym, "clave → id de carpeta")
igual(LibraryOrder.folderID(b004), nil, "una playlist no es carpeta")
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "recent", order: [], smartInPlaylists: true),
      ["downloads", "favorites", kViajes, kGym, b004], "nivel: recientes, carpetas delante")
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "name", order: [], smartInPlaylists: false),
      [kGym, kViajes, b004], "nivel: por nombre, sin listas inteligentes")
igual(LibraryOrder.level(gym, playlists: propias, folders: fs, sort: "name", order: [], smartInPlaylists: true),
      [kF002, b001], "nivel: dentro de Gimnasio, sin listas inteligentes")
let movido = ["downloads", "favorites", kGym, kViajes, b004]
let orden = LibraryOrder.reorder(level: movido, playlists: propias, folders: fs, sort: "recent", order: [])
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "custom", order: orden, smartInPlaylists: true), movido,
      "a mano: el nivel queda como se dejó")
igual(LibraryOrder.level(gym, playlists: propias, folders: fs, sort: "custom", order: orden, smartInPlaylists: true), [kF002, b001],
      "a mano: los otros niveles no saltan")
// Arrastrar dentro de una carpeta (donde Descargadas y Favoritos no se ven) con otro orden puesto: arriba del todo
// siguen delante, no saltan al final (revisión del bloque 1).
let dentro = LibraryOrder.reorder(level: [b001, kF002], playlists: propias, folders: fs, sort: "recent", order: [])
igual(LibraryOrder.level(gym, playlists: propias, folders: fs, sort: "custom", order: dentro, smartInPlaylists: true), [b001, kF002],
      "a mano dentro de una carpeta: carpetas y playlists mezcladas (2-0b)")
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "custom", order: dentro, smartInPlaylists: true),
      ["downloads", "favorites", kViajes, kGym, b004], "a mano dentro de una carpeta: Descargadas y Favoritos no saltan al final")
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "custom", order: dentro, smartInPlaylists: false),
      [kViajes, kGym, b004], "a mano dentro de una carpeta: con Descargadas y Favoritos en Tu música, no salen")

// MARK: Carpetas y playlists mezcladas «A mano» (prompt 2-0b; mismos casos que PlaylistFoldersTest.kt)
let mezclado = ["downloads", kGym, b004, "favorites", kViajes]
let ordenMezclado = LibraryOrder.reorder(level: mezclado, playlists: propias, folders: fs, sort: "recent", order: [])
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "custom", order: ordenMezclado, smartInPlaylists: true),
      mezclado, "mezcladas: el nivel queda como se dejó")
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "custom", order: ordenMezclado, smartInPlaylists: false),
      [kGym, b004, kViajes], "mezcladas, con Descargadas y Favoritos en Tu música")
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "name", order: ordenMezclado, smartInPlaylists: false),
      [kGym, kViajes, b004], "con otro criterio las carpetas siguen delante")
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "custom", order: ["downloads", "favorites", kGym, b004], smartInPlaylists: true),
      ["downloads", "favorites", kGym, kViajes, b004], "una carpeta que no está en el orden: detrás de la última que sí")
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "custom", order: ["favorites", b004, "downloads"], smartInPlaylists: true),
      ["favorites", kGym, kViajes, b004, "downloads"], "ninguna carpeta en el orden: delante de la primera playlist")
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "custom", order: [b004], smartInPlaylists: true),
      [kGym, kViajes, b004, "downloads", "favorites"], "lo que falta del orden va detrás, como siempre")
// Un orden de antes del 2-0b (carpetas seguidas y delante en cada nivel) se ve igual que antes.
let ordenViejo = LibraryOrder.materialize(playlists: propias, folders: fs, sort: "recent", order: [], smartInPlaylists: true)
igual(LibraryOrder.level(nil, playlists: propias, folders: fs, sort: "custom", order: ordenViejo, smartInPlaylists: true),
      ["downloads", "favorites", kViajes, kGym, b004], "orden de antes: igual que antes")
// El lector de la 3.0 anterior (congelado: carpetas delante en el orden de `order`, después las playlists) lee el
// orden mezclado sin perder nada: el formato es el mismo, sólo cambia dónde se pintan las carpetas.
func nivelViejo(_ order: [String]) -> [String] {
    let listas = LibraryOrder.keys(propias.filter { $0.folder == nil }, sort: "custom", order: order, smartInPlaylists: true)
    let mias = fs.filter { $0.parent == nil }.map { LibraryOrder.key(folder: $0.id) }
    let guardadas = order.filter { mias.contains($0) }
    let carpetasViejas = guardadas + mias.filter { !guardadas.contains($0) }
    let at = listas.firstIndex { $0 != "downloads" && $0 != "favorites" } ?? listas.endIndex
    return Array(listas[..<at]) + carpetasViejas + Array(listas[at...])
}
igual(nivelViejo(ordenMezclado), ["downloads", kGym, kViajes, b004, "favorites"], "la 3.0 anterior lo lee: carpetas delante, nada se pierde")
igual(Set(nivelViejo(ordenMezclado)), Set(mezclado), "la 3.0 anterior: las mismas portadas")
// iOS 2.2 / Android 1.2 sólo conocen las playlists: las claves `folder:` se saltan.
igual(LibraryOrder.keys(propias.filter { $0.folder == nil }, sort: "custom", order: ordenMezclado, smartInPlaylists: true),
      ["downloads", b004, "favorites"], "versiones sin carpetas: se saltan las claves folder:")

// MARK: Sacar de una carpeta arrastrando (prompt 2-0b; mismos casos que PlaylistFoldersTest.kt)
igual(PlaylistFolders.ancestor(of: lunes, at: nil, in: fs), gym, "desde Lunes, arriba del todo: Gimnasio")
igual(PlaylistFolders.ancestor(of: lunes, at: gym, in: fs), pierna, "desde Lunes, en Gimnasio: Pierna")
igual(PlaylistFolders.ancestor(of: lunes, at: pierna, in: fs), lunes, "desde Lunes, en Pierna: ella misma")
igual(PlaylistFolders.ancestor(of: lunes, at: viajes, in: fs), nil, "Viajes no tiene a Lunes debajo")
igual(PlaylistFolders.ancestor(of: lunes, at: lunes, in: fs), nil, "en su propio nivel no hay carpeta de la que salga")
igual(LibraryOrder.placing(b004, after: kGym, in: [kViajes, kGym, "downloads", b004]), [kViajes, kGym, b004, "downloads"],
      "sale justo detrás de su carpeta")
igual(LibraryOrder.placing(b004, after: kGym, in: [kViajes]), [kViajes, b004], "si la carpeta no está en el orden, al final")

// MARK: «Nueva carpeta» de «Mover a…»: una carpeta con 3 niveles dentro no cabe en ninguna
cierto(!PlaylistFolders.canMoveIntoNew(gym, folders: fs), "Gimnasio (3 niveles) no cabe en una carpeta nueva")
cierto(PlaylistFolders.canMoveIntoNew(f002, folders: fs), "Pierna (2 niveles) cabe en una carpeta nueva")
cierto(PlaylistFolders.canMoveIntoNew(viajes, folders: fs), "Viajes (1 nivel) cabe en una carpeta nueva")

// MARK: Ordenar «Tu música» con las flechas o el asa (mismos casos que MusicOrderTest.kt)
let todos = MusicOrder.defaults // playlists, downloads, favorites, albums, songs, artists, recents, stats
let vistos = todos.filter { $0 != "downloads" && $0 != "favorites" }
igual(MusicOrder.moved("playlists", by: 1, visible: vistos, all: todos),
      ["albums", "downloads", "favorites", "playlists", "songs", "artists", "recents", "stats"],
      "Tu música: bajar Playlists la deja detrás de Tus álbumes; Descargadas y Favoritos (que no se ven) no se mueven")
igual(MusicOrder.moved("playlists", by: -1, visible: vistos, all: todos), todos, "Tu música: la primera no sube")
igual(MusicOrder.moved("stats", by: 1, visible: vistos, all: todos), todos, "Tu música: la última no baja")
igual(MusicOrder.moved("downloads", by: 1, visible: vistos, all: todos), todos, "Tu música: lo que no se ve no se mueve")
igual(MusicOrder.moved("stats", by: -3, visible: todos, all: todos).suffix(3).map { $0 }, ["artists", "stats", "recents"],
      "Tu música: un paso cada vez, aunque se pida más")
igual(MusicOrder.decode(MusicOrder.moved("songs", by: -1, visible: todos, all: todos).joined(separator: ",")),
      ["playlists", "downloads", "favorites", "songs", "albums", "artists", "recents", "stats"], "Tu música: se guarda y se lee igual")

// MARK: Una carpeta con el mismo id que una playlist o que «downloads» (copia hecha a mano): sin claves repetidas
let mismo = "0000000A-0000-0000-0000-00000000D001"
let choqueCarpetas = PlaylistFolders.normalize([PlaylistFolder(id: mismo, name: "Igual que la lista"),
                                                PlaylistFolder(id: "downloads", name: "Descargas falsa")])
let choqueListas = PlaylistFolders.clean([Playlist(id: UUID(uuidString: mismo)!, name: "Lista"),
                                          Playlist(id: UUID(uuidString: "0000000A-0000-0000-0000-00000000D002")!, name: "Dentro", folder: "downloads")],
                                         folders: choqueCarpetas)
for (criterio, orden) in [("recent", [String]()), ("custom", [mismo, LibraryOrder.key(folder: mismo), "downloads", LibraryOrder.key(folder: "downloads")])] {
    let claves = LibraryOrder.level(nil, playlists: choqueListas, folders: choqueCarpetas, sort: criterio, order: orden, smartInPlaylists: true)
    igual(claves.count, Set(claves).count, "choque (\(criterio)): sin claves repetidas")
    cierto(claves.contains(mismo) && claves.contains(LibraryOrder.key(folder: mismo)), "choque (\(criterio)): la lista y la carpeta salen las dos")
    cierto(claves.contains("downloads") && claves.contains(LibraryOrder.key(folder: "downloads")), "choque (\(criterio)): Descargadas y la carpeta «downloads» salen las dos")
}
igual(LibraryOrder.level("downloads", playlists: choqueListas, folders: choqueCarpetas, sort: "recent", order: [], smartInPlaylists: true),
      ["0000000A-0000-0000-0000-00000000D002"], "choque: dentro de la carpeta «downloads» no salen las listas inteligentes")

print(fallos == 0 ? "Carpetas (library.json): todo bien." : "Carpetas (library.json): \(fallos) fallos.")
exit(fallos == 0 ? 0 : 1)
