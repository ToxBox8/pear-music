import Compression
import Foundation
import UIKit

/// Sincronizar la biblioteca con la cuenta (docs/spec/sync.md §2 y §4; 2-D). Lo que se une y cómo se marca está en
/// `SyncModel` (igual que la referencia y Android); aquí sólo cuándo, el cifrado del bloque y el estado del móvil.
///
/// - Las marcas se ponen en un solo sitio: antes de cada sincronización, `marcar(previo, actual)` compara la biblioteca
///   de ahora con la última que se marcó (`previo`, guardada aquí con sus marcas) y marca lo que ha cambiado.
/// - Bajar al abrir y al volver si hace más de 5 min; subir 30 s después del último cambio y al ir a segundo plano si
///   hay algo pendiente. Sin red o con 5xx: pendiente (una marca, no una cola) y se reintenta. 409: bajar, unir y
///   volver a subir, como mucho 3 vueltas.
/// - Biblioteca que no se pudo leer (`LibraryDisk`): no se sube nada hasta «Empezar de cero».
/// Igual que `SyncBiblioteca` en Android.
@MainActor
final class SyncBiblioteca: ObservableObject {
    static let shared = SyncBiblioteca()
    static let clave = "biblioteca"
    static let maxBloque = 2 * 1024 * 1024
    static let maxInflado = 16 * 1024 * 1024 // sync.md §2

    private weak var library: Library?
    private var espera: Task<Void, Never>?
    private var enCurso = false
    private var estado = Estado()

    /// Lo que guarda el móvil (Application Support/sync-biblioteca.json, protegido como library.json).
    struct Estado: Codable {
        var etag: String?
        var previo: JV?            // la última biblioteca marcada (= la de la nube con ese etag, o lo que se iba a subir)
        var ultimaSync: [Double]?  // t y c de la marca (d aparte): §5.4
        var ultimaSyncD: String?
        var contador: Double = 1   // la c de las marcas de este móvil (§5.1)
        var pendiente = false
        var ultimaBajada: Double = 0
        var avisoGrande = false    // «Tu biblioteca es demasiado grande para la nube», una vez
        // Estadísticas (§6), bloque aparte: sin marcas.
        var etagEst: String?
        var previoEst: JV?
        var pendienteEst = false
        var ultimaSubidaEst: Double = 0
        /// ms de la última vez que la nube y el móvil quedaron iguales (PULIR #4). Opcional: los archivos de antes no
        /// lo tienen y Codable no usa el valor por defecto al leer.
        var ultimaOk: Double?
        /// «No sincronizar esto» (PULIR #5, sync.md §5.6): las claves «k:id» marcadas en este móvil.
        var soloAqui: [String]?
    }

    /// Lo marcado «sólo en este móvil»: ni sube ni lo toca lo que llega; en los demás móviles, como estaba. Igual que
    /// `SyncBiblioteca.soloAqui` en Android.
    @Published private(set) var soloAqui: Set<String> = []
    /// `marcar` = true: «No sincronizar esto»; false: «Volver a sincronizar».
    func soloEnEsteMovil(_ clave: String, _ marcar: Bool) {
        if marcar { soloAqui.insert(clave) } else { soloAqui.remove(clave) }
        estado.soloAqui = soloAqui.sorted()
        guardar()
        alCambiar()
    }

    /// Lo que se ve (PULIR #3 y #4): la cápsula de arriba (`AvisoSync`) y la fila de Ajustes › Cuenta.
    @Published private(set) var vista = VistaSync()
    private func fase(_ f: FaseSync) { vista.fase = f }
    private func alAcabar() { vista.fase = .quieta; vista.pendiente = estado.pendiente; vista.ultimaOk = estado.ultimaOk ?? 0 }
    /// Sólo capturas (`-screenshotScenario`): un estado fijo, como `vistaDePrueba` en Android.
    func vistaDePrueba(_ v: VistaSync) { vista = v }

    /// Lo que se enseña una vez (§5.4, §4): la pantalla de la cuenta lo lee.
    @Published private(set) var aviso: String?

    private static var archivo: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-biblioteca.json")
    }

    private init() {
        if let d = try? Data(contentsOf: Self.archivo), let e = try? JSONDecoder().decode(Estado.self, from: d) { estado = e }
        alAcabar()
        soloAqui = Set(estado.soloAqui ?? [])
        ordenVisto = Self.ordenes()
        // Los órdenes (con las claves `folder:` de las carpetas) viven en UserDefaults, no en library.json: cambiar sólo
        // el orden (arrastrar en «Ordenar», «Ordenar por») no pasaba por `Library.save` y no se subía (PULIR #1).
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in SyncBiblioteca.shared.ordenCambiado() } // `callado` ya habrá puesto `ordenVisto`
        }
    }

    // MARK: Órdenes (playlistOrder, albumOrder, musicOrder y los «Ordenar por»)

    static let clavesOrden = ["playlistOrder", "albumOrder", "musicOrder", "playlistSort", "albumSort", "accountName"]
    private static func ordenes() -> String {
        clavesOrden.map { UserDefaults.standard.string(forKey: $0) ?? "\u{1}" }.joined(separator: "\u{0}")
    }
    private var ordenVisto = ""
    private var silencio = false
    private func ordenCambiado() {
        let o = Self.ordenes()
        guard o != ordenVisto else { return }
        ordenVisto = o
        if !silencio { alCambiar() }
    }
    /// Lo que se hace dentro no cuenta como un cambio de este móvil (poner lo que llega de la nube).
    func callado(_ f: () -> Void) {
        silencio = true
        f()
        ordenVisto = Self.ordenes()
        silencio = false
    }
    private func guardar() {
        guard let d = try? JSONEncoder().encode(estado) else { return }
        try? d.write(to: Self.archivo, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func conectar(_ library: Library) { self.library = library }

    /// Al salir de la cuenta o quitar este móvil: lo de la sync de esa cuenta se olvida.
    func olvidar() {
        espera?.cancel()
        esperaEst?.cancel(); esperaEst = nil
        estado = Estado()
        try? FileManager.default.removeItem(at: Self.archivo)
        vista = VistaSync()
        soloAqui = []
        // El nombre es de esa cuenta (PULIR #6): si se quedara, al entrar en otra se subiría encima del suyo.
        callado { UserDefaults.standard.removeObject(forKey: "accountName") }
    }

    // MARK: Cuándo (§4)

    /// Cada cambio de la biblioteca: se sube 30 s después del último.
    func alCambiar() {
        guard CuentaPear.shared.tieneCuenta else { return }
        estado.pendiente = true
        vista.pendiente = true
        espera?.cancel()
        espera = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.sincronizar()
        }
    }

    /// Recién creada la cuenta o recién entrado en ella (con la clave o el QR): se sincroniza ya, sin esperar a la
    /// siguiente apertura (PULIR #1: el móvil nuevo no traía nada hasta volver a abrir la app).
    func alEntrar() {
        guard CuentaPear.shared.tieneCuenta else { return }
        Task { await sincronizar(); await sincronizarEstadisticas() }
    }

    /// Al abrir y al volver a primer plano: bajar si hace más de 5 min (o si quedó algo pendiente).
    func alAbrir() {
        guard CuentaPear.shared.tieneCuenta else { return }
        if estado.pendiente || estado.pendienteEst || Date().timeIntervalSince1970 - estado.ultimaBajada > 300 {
            Task { await sincronizar(); await sincronizarEstadisticas() }
        }
    }

    /// Cada escucha: las estadísticas se suben como mucho una vez cada 10 min (§6) y al ir a segundo plano.
    func alCambiarEstadisticas() {
        guard CuentaPear.shared.tieneCuenta else { return }
        estado.pendienteEst = true
        guard esperaEst == nil else { return }
        let falta = Swift.max(0, 600 - (Date().timeIntervalSince1970 - estado.ultimaSubidaEst))
        esperaEst = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(falta * 1_000_000_000))
            self?.esperaEst = nil
            guard !Task.isCancelled else { return }
            await self?.sincronizarEstadisticas()
        }
    }
    private var esperaEst: Task<Void, Never>?

    /// Al ir a segundo plano con algo pendiente: se sube ya (con el tiempo que da el sistema; nunca programado).
    func alSegundoPlano() {
        guard CuentaPear.shared.tieneCuenta, estado.pendiente || estado.pendienteEst else { return }
        espera?.cancel()
        esperaEst?.cancel(); esperaEst = nil
        var tarea = UIBackgroundTaskIdentifier.invalid
        tarea = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(tarea) }
        Task {
            if estado.pendiente { await sincronizar() }
            if estado.pendienteEst { await sincronizarEstadisticas() }
            UIApplication.shared.endBackgroundTask(tarea)
        }
    }

    // MARK: Sincronizar

    func sincronizar() async {
        guard !enCurso, let library, library.unreadableCopy == nil, !Demo.isActive, !DemoCatalog.isActive else { return }
        let cuenta = CuentaPear.shared
        guard cuenta.tieneCuenta, let k = cuenta.kMusic, let d = cuenta.dispositivoCorto, let id = cuenta.cuentaId else { return }
        enCurso = true
        defer { enCurso = false; guardar(); alAcabar() }
        do {
            // 1. Marcar lo que ha cambiado desde la última vez (§5.2), con el reloj híbrido (§5.1).
            // Lo marcado «sólo en este móvil» (§5.6) no entra: ni en lo que se marca ni en lo último marcado (así no deja
            // bajas); al final se vuelve a poner como está aquí.
            guard let entera = try? JV.leer(library.exportData(covers: true)) else { return }
            let claves = SyncModel.soloAquiEntero(entera, Array(soloAqui))
            let actual = SyncModel.quitarSoloAqui(entera, claves) ?? entera
            let previo = SyncModel.quitarSoloAqui(estado.previo, claves)
            let ahora = cuenta.ahoraMs()
            let t = Swift.max(ahora.rounded(.down), SyncModel.marcaMayor(previo).t + 1)
            let m = SyncModel.marcar(previo, actual, t: t, c: estado.contador, d: d)
            estado.contador = m.c
            let ultima = estado.ultimaSync.map { Marca(t: $0[0], c: $0[1], d: estado.ultimaSyncD ?? "") }
            for _ in 0..<3 {
                // 2. Bajar (con If-None-Match si ya hay una versión) y unir.
                fase(.bajando)
                let nube: JV?
                var etag = estado.etag
                switch try await cuenta.bajarBloque(Self.clave, etag: estado.previo == nil ? nil : estado.etag) {
                case .igual: nube = estado.previo
                case .bloque(let datos, let e): nube = try abrir(datos, clave: k, cuenta: id); etag = e
                case .noHay: nube = nil; etag = nil
                }
                estado.ultimaBajada = Date().timeIntervalSince1970
                fase(.uniendo)
                let u = SyncModel.unir(m.lib, nube, ahora: ahora, ultimaSync: ultima)
                if u.aviso == .puestaAlDia { guardarCopia(entera) }
                if let a = u.aviso { avisar(a) }
                // 3. Subir si la nube no tiene ya todo (sólo cuenta lo que se sincroniza: no los recientes).
                var resultado = u.lib
                if nube == nil || !SyncModel.mismoContenido(resultado, nube!) {
                    guard let bloque = sellar(&resultado, clave: k, cuenta: id) else { estado.pendiente = false; return }
                    fase(.subiendo)
                    do {
                        etag = try await cuenta.subirBloque(Self.clave, bloque, etag: etag)
                    } catch let e as CuentaPear.ErrorCuenta where e.codigo == "version_cambiada" {
                        continue // otro móvil subió antes: bajar, unir y volver a subir
                    }
                }
                // 4. Lo de la nube y lo del móvil ya son lo mismo: se guarda y se pone en la app.
                let marca = SyncModel.marcaMayor(resultado)
                estado.ultimaSync = [marca.t, marca.c]
                estado.ultimaSyncD = marca.d
                estado.etag = etag
                estado.previo = resultado
                estado.pendiente = false
                estado.ultimaOk = Date().timeIntervalSince1970 * 1000
                vista.sinRed = false
                if !SyncModel.mismoContenido(SyncModel.quitarSoloAqui(resultado, claves) ?? resultado, m.lib) {
                    try? library.adoptarSync(SyncModel.ponerSoloAqui(resultado, entera, claves).datos())
                    vista.traido = Date().timeIntervalSince1970 * 1000
                }
                return
            }
            // Tres choques seguidos: se queda pendiente para la siguiente apertura (§4).
            estado.pendiente = true
        } catch {
            estado.pendiente = true // sin red, 5xx, términos…: se reintenta al volver o al abrir
            let codigo = (error as? CuentaPear.ErrorCuenta)?.codigo
            vista.sinRed = codigo == "sin_conexion" || codigo == "bloqueado"
            Logs.w("Sync", "biblioteca pendiente: \(codigo ?? "error")") // sin datos
        }
    }

    // MARK: Estadísticas (§6): sin marcas; la unión es un conjunto de escuchas

    static let claveEst = "estadisticas"
    private var enCursoEst = false

    func sincronizarEstadisticas() async {
        guard !enCursoEst, !Demo.isActive, !DemoCatalog.isActive else { return }
        let cuenta = CuentaPear.shared
        guard cuenta.tieneCuenta, let k = cuenta.kMusic, let id = cuenta.cuentaId else { return }
        enCursoEst = true
        defer { enCursoEst = false; guardar() }
        do {
            guard let actual = try? JV.leer(PlayStats.shared.exportJSON()) else { return }
            let ahora = cuenta.ahoraMs()
            for _ in 0..<3 {
                let nube: JV?
                var etag = estado.etagEst
                switch try await cuenta.bajarBloque(Self.claveEst, etag: estado.previoEst == nil ? nil : estado.etagEst) {
                case .igual: nube = estado.previoEst
                case .bloque(let datos, let e): nube = try abrir(datos, clave: k, cuenta: id, nombre: Self.claveEst); etag = e
                case .noHay: nube = nil; etag = nil
                }
                var u = SyncModel.unirEstadisticas(actual, nube, ahora: ahora)
                if nube == nil || u.canon != nube!.canon {
                    guard let bloque = sellarEstadisticas(&u, clave: k, cuenta: id) else { return }
                    do { etag = try await cuenta.subirBloque(Self.claveEst, bloque, etag: etag) }
                    catch let e as CuentaPear.ErrorCuenta where e.codigo == "version_cambiada" { continue }
                    estado.ultimaSubidaEst = Date().timeIntervalSince1970
                }
                estado.etagEst = etag
                estado.previoEst = u
                estado.pendienteEst = false
                if u.canon != actual.canon { PlayStats.shared.adoptar(u.datos()) }
                return
            }
        } catch {
            estado.pendienteEst = true
            Logs.w("Sync", "estadísticas pendientes: \((error as? CuentaPear.ErrorCuenta)?.codigo ?? "error")") // sin datos
        }
    }

    /// Si comprimido pasa de 2 MB, fuera las escuchas más antiguas hasta que quepa (§6).
    private func sellarEstadisticas(_ est: inout JV, clave: Data, cuenta: String) -> Data? {
        while true {
            guard let comprimido = Self.deflate(est.datos()) else { return nil }
            let nonce = CuentaCripto.aleatorio(12)
            guard let ct = try? CuentaCripto.sellar(clave, nonce, comprimido, aad(cuenta, Self.claveEst)) else { return nil }
            let bloque = Data([1]) + nonce + ct
            if bloque.count <= Self.maxBloque { return bloque }
            guard let plays = est["plays"]?.lista, plays.count > 10 else { return nil }
            est["plays"] = .arr(Array(plays.dropFirst(plays.count / 10)))
        }
    }

    // MARK: Bloque (§2)

    private func aad(_ cuenta: String, _ bloque: String = clave) -> Data { Data("pear-sync/v1|\(cuenta)|music|\(bloque)".utf8) }

    /// 0x01 ‖ nonce ‖ AES-GCM(deflate(JSON)). Si no cabe en 2 MB, sin portadas; si aún no, nil (y se avisa una vez).
    private func sellar(_ lib: inout JV, clave: Data, cuenta: String) -> Data? {
        for intento in 0..<2 {
            if intento == 1 { lib["covers"] = nil }
            guard let comprimido = Self.deflate(lib.datos()) else { return nil }
            let nonce = CuentaCripto.aleatorio(12)
            guard let ct = try? CuentaCripto.sellar(clave, nonce, comprimido, aad(cuenta)) else { return nil }
            let bloque = Data([1]) + nonce + ct
            if bloque.count <= Self.maxBloque { return bloque }
        }
        if !estado.avisoGrande { estado.avisoGrande = true; aviso = L("Tu biblioteca es demasiado grande para la nube") }
        return nil
    }

    private func abrir(_ bloque: Data, clave: Data, cuenta: String, nombre: String = clave) throws -> JV {
        guard bloque.count >= 29, bloque.first == 1 else { throw CuentaPear.ErrorCuenta(codigo: "version_bloque") }
        let b = [UInt8](bloque)
        let datos = try CuentaCripto.abrir(clave, Data(b[1..<13]), Data(b[13...]), aad(cuenta, nombre))
        guard let json = Self.inflate(datos) else { throw CuentaPear.ErrorCuenta(codigo: "bloque_roto") }
        return try JV.leer(json)
    }

    static func deflate(_ data: Data) -> Data? {
        var out = Data(count: data.count + 4096)
        let n = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, dst.count,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 ? out.prefix(n) : nil
    }

    /// Con tope de 16 MB: un bloque manipulado no se infla sin fin (§2).
    static func inflate(_ data: Data) -> Data? {
        var out = Data(count: maxInflado)
        let n = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, maxInflado,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 && n < maxInflado ? out.prefix(n) : nil
    }

    // MARK: Avisos (§5.4)

    private func avisar(_ a: SyncModel.Aviso) {
        switch a {
        case .puestaAlDia: aviso = L("Hacía mucho que este móvil no se sincronizaba: se ha puesto al día con tu cuenta")
        case .nubeAntigua, .nubeVacia: aviso = L("Tu biblioteca de la nube estaba incompleta: la hemos completado con la de este móvil")
        }
    }
    func avisoVisto() { aviso = nil }

    /// Antes de dar cosas por borradas (§5.4): una copia de library.json, que sale al exportar en Tus datos.
    private func guardarCopia(_ lib: JV) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        try? lib.datos().write(to: docs.appendingPathComponent("library-copia-sync-\(f.string(from: Date())).json"), options: .atomic)
    }
}
