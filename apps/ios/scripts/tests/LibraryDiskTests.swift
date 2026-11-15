// Tests de library.json en disco (revisión del bloque 1, T3), sólo Foundation: scripts/test-linux.sh.
// Si el archivo no se puede leer, no se pisa: se guarda una copia, se avisa y no se escribe encima.
// Los mismos casos que LibraryUnreadableTest.kt en Android.
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

let fm = FileManager.default
/// Una carpeta vacía por caso, como el Documents de una instalación.
func carpeta() -> URL {
    let d = fm.temporaryDirectory.appendingPathComponent("lm-disk-\(UUID().uuidString)")
    try! fm.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}
func copias(_ d: URL) -> [String] {
    ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).filter { $0.hasPrefix("library-copia-") }.sorted()
}
func texto(_ u: URL) -> String { (try? String(contentsOf: u, encoding: .utf8)) ?? "<no existe>" }
let cancion = Song(id: "abc12345678", title: "Canción", artist: "Artista", thumbnail: nil)
func biblioteca(_ favoritas: [Song], _ listas: [Playlist] = []) -> LibraryFile {
    LibraryFile(favorites: favoritas, playlists: listas, recents: nil, folders: nil)
}

// MARK: Un archivo ilegible no se pisa
do {
    let d = carpeta(), file = d.appendingPathComponent("library.json")
    // Cortado a medias (el móvil se apagó al guardar, o una copia mal restaurada).
    let roto = #"{"favorites":[{"id":"a","title":"Una","artist":"X"}],"playlists":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"Via"#
    try! roto.write(to: file, atomically: true, encoding: .utf8)

    let disk = LibraryDisk(file: file)
    cierto(disk.load() == nil, "ilegible: arranca sin biblioteca")
    cierto(disk.unreadableCopy != nil, "ilegible: avisa")
    cierto(!disk.save(biblioteca([cancion])), "ilegible: guardar no escribe")
    igual(texto(file), roto, "ilegible: library.json sigue como estaba")
    igual(copias(d).map { texto(d.appendingPathComponent($0)) }, [roto], "ilegible: una copia, igual que el archivo")
    igual(disk.unreadableCopy, copias(d).first, "ilegible: dice cómo se llama la copia")

    // Volver a abrir no amontona copias.
    _ = LibraryDisk(file: file).load(); _ = LibraryDisk(file: file).load()
    igual(copias(d).count, 1, "ilegible: abrir tres veces deja una sola copia")

    // «Empezar de cero»: vuelve a guardar y la copia se queda.
    disk.startOver()
    cierto(disk.unreadableCopy == nil, "empezar de cero: deja de avisar")
    cierto(disk.save(biblioteca([cancion])), "empezar de cero: guarda")
    igual(LibraryDisk(file: file).load()?.favorites.map(\.id), ["abc12345678"], "empezar de cero: se lee lo guardado")
    igual(copias(d).map { texto(d.appendingPathComponent($0)) }, [roto], "empezar de cero: la copia sigue")
}

// MARK: Sin archivo, o vacío, arranca vacía sin avisar
do {
    let d = carpeta(), file = d.appendingPathComponent("library.json")
    let nuevo = LibraryDisk(file: file)
    cierto(nuevo.load() == nil && nuevo.unreadableCopy == nil, "sin archivo: vacía y sin aviso")
    try! Data().write(to: file)
    let vacio = LibraryDisk(file: file)
    cierto(vacio.load() == nil && vacio.unreadableCopy == nil, "archivo vacío: vacía y sin aviso")
    cierto(vacio.save(biblioteca([cancion])), "archivo vacío: guarda")
    igual(copias(d), [], "archivo vacío: sin copias")
}

// MARK: Lo que se salta al leer queda en una copia
do {
    let d = carpeta(), file = d.appendingPathComponent("library.json")
    // Una canción sin id y una playlist que no es un objeto: hasta ahora tumbaban la biblioteca entera en iOS.
    let raro = #"{"favorites":[{"title":"Sin id"},{"id":"b","title":"Bien","artist":"X"}],"playlists":[7,{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"Viaje","songs":[]}],"recents":[]}"#
    try! raro.write(to: file, atomically: true, encoding: .utf8)
    let disk = LibraryDisk(file: file)
    let lib = disk.load()
    cierto(disk.unreadableCopy == nil, "raro: se lee, así que no avisa")
    igual(lib?.favorites.map(\.id), ["b"], "raro: las canciones que se pueden leer")
    igual(lib?.playlists.map(\.name), ["Viaje"], "raro: las playlists que se pueden leer")
    cierto(disk.save(biblioteca([cancion])), "raro: guarda")
    igual(copias(d).map { texto(d.appendingPathComponent($0)) }, [raro], "raro: el archivo de antes queda en una copia")
}

// MARK: Una biblioteca normal no deja copias
do {
    let d = carpeta(), file = d.appendingPathComponent("library.json")
    let a = LibraryDisk(file: file)
    _ = a.load()
    a.save(biblioteca([cancion], [Playlist(name: "Viaje", songs: [cancion])]))
    let b = LibraryDisk(file: file)
    let lib = b.load()
    igual(lib?.playlists.first?.songs.map(\.id), ["abc12345678"], "normal: se lee lo guardado")
    cierto(b.unreadableCopy == nil, "normal: sin aviso")
    igual(copias(d), [], "normal: sin copias")
}

// MARK: Lectura tolerante, como Android
do {
    func leer(_ json: String) -> LibraryFile? { try? LibraryFile.decode(Data(json.utf8)) }
    let id = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    // Sólo el id es obligatorio en una canción; lo demás, vacío.
    igual(leer(#"{"favorites":[{"id":"a"}],"playlists":[]}"#)?.favorites.first?.title, "", "canción sin título: vacío")
    igual(leer(#"{"favorites":[{"id":"a","title":"T","artist":"A","thumbnail":7}],"playlists":[]}"#)?.favorites.count, 1,
          "carátula que no es texto: la canción se queda")
    // Una playlist con campos raros se queda; sin nombre es «Playlist».
    let p = leer(#"{"favorites":[],"playlists":[{"id":"\#(id)","songs":[{"id":"a","title":"T","artist":"A"},"x"],"tint":"rojo","pinned":"sí","album":3,"icon":4}]}"#)?.playlists.first
    igual(p?.name, "Playlist", "playlist sin nombre")
    igual(p?.songs.map(\.id), ["a"], "playlist: se salta la canción rara")
    cierto(p?.tint == nil && p?.pinned == nil && p?.album == nil && p?.icon == nil, "playlist: campos raros, como si no estuvieran")
    // Listas que faltan: vacías. Lo que no es un objeto no es una biblioteca.
    igual(leer("{}")?.favorites.count, 0, "sin listas: vacía")
    cierto(leer("[1,2]") == nil && leer("hola") == nil, "no es un objeto: no se lee")
    // Huella: FNV-1a de 64 bits, la misma que en Android (el mismo archivo, el mismo nombre de copia).
    igual(LibraryDisk.fingerprint(Data("a".utf8)), "af63dc4c8601ec8c", "huella de «a»")
    igual(LibraryDisk.fingerprint(Data()), "cbf29ce484222325", "huella de nada")
}

print(fallos == 0 ? "✅ library.json en disco: todo bien" : "❌ \(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
