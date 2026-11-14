import XCTest

/// Tests de interfaz de la Biblioteca en el simulador (CI: job «uitests» de ios.yml; `scripts/uitests.sh`).
/// Abren la app con los datos de ejemplo de las capturas (`-screenshotScenario`, sin red ni library.json) y hacen
/// lo mismo que una persona: tocar, escribir, mantener pulsado y arrastrar. Cada paso deja una captura y, al
/// final, un `.txt` con lo que se ve, en `/tmp/jiyu-uitests` (la CI lo sube como artefacto).
/// Nacen de la revisión del bloque 1 (docs/revision/v3-bloque-1.md): en el iPhone no se podían crear playlists ni
/// ordenar «Tu música», y ningún test lo veía porque iOS no tenía tests de interfaz.
final class BibliotecaUITests: XCTestCase {
    private var app: XCUIApplication!
    private static let out = URL(fileURLWithPath: "/tmp/jiyu-uitests", isDirectory: true)

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
        app = XCUIApplication()
    }

    /// `ready`: un texto que tiene que verse cuando la pantalla del escenario ya está.
    private func launch(_ scenario: String, ready: String = "Tu música") {
        app.launchArguments = ["-screenshotScenario", scenario, "-language", "es", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        XCTAssertTrue(any(ready).waitForExistence(timeout: 20), "La pantalla del escenario \(scenario) no llegó a salir")
    }

    // MARK: Ayudas

    /// El primer elemento, del tipo que sea, cuyo texto contiene `text`.
    private func any(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func button(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: Self.out.appendingPathComponent("\(self.name.filter { $0.isLetter || $0.isNumber })-\(name).png"))
    }

    private func note(_ name: String, _ text: String) {
        try? text.write(to: Self.out.appendingPathComponent("\(self.name.filter { $0.isLetter || $0.isNumber })-\(name).txt"),
                        atomically: true, encoding: .utf8)
    }

    /// Los textos dados, de arriba abajo según su posición en pantalla.
    private func vertical(_ labels: [String]) -> [String] {
        labels.filter { any($0).exists }.sorted { any($0).frame.minY < any($1).frame.minY }
    }

    /// Las celdas de una cuadrícula en orden de lectura (fila a fila, de izquierda a derecha).
    private func reading(_ labels: [String]) -> [String] {
        labels.filter { any($0).exists }.sorted {
            let a = any($0).frame, b = any($1).frame
            return abs(a.minY - b.minY) > 40 ? a.minY < b.minY : a.minX < b.minX
        }
    }

    private func openPlaylists() {
        let row = button("Playlists")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No está la fila «Playlists» de Tu música")
        row.tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5), "No se abrió Tu música › Playlists")
    }

    // MARK: a) Crear una playlist

    /// Biblioteca › + › Nueva playlist › nombre › Crear. La playlist tiene que salir en Tu música › Playlists.
    func testCrearPlaylistDesdeElMas() {
        launch("01_biblioteca_cristal")
        let plus = app.buttons["Añadir playlist"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "No está el botón +")
        plus.tap()
        shot("1-menu")
        let item = app.buttons["Nueva playlist"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "El menú del + no tiene «Nueva playlist»")
        item.tap()
        let field = app.textFields.firstMatch
        let appeared = field.waitForExistence(timeout: 5)
        shot("2-nombre")
        XCTAssertTrue(appeared, "No salió dónde escribir el nombre de la playlist")
        if appeared {
            field.tap()
            field.typeText("Prueba UI")
            shot("3-escrito")
            let create = app.buttons["Crear"]
            XCTAssertTrue(create.waitForExistence(timeout: 3), "No hay botón «Crear»")
            XCTAssertTrue(create.isEnabled, "«Crear» está apagado con el nombre escrito")
            create.tap()
        }
        sleep(1)
        shot("4-despues")
        openPlaylists()
        let created = any("Prueba UI").waitForExistence(timeout: 5)
        shot("5-playlists")
        note("arbol", app.debugDescription)
        XCTAssertTrue(created, "La playlist «Prueba UI» no sale en Tu música › Playlists")
    }

    /// Lo que hace casi todo el mundo: escribir el nombre y pulsar Intro en el teclado, sin tocar «Crear».
    func testCrearPlaylistConIntro() {
        launch("01_biblioteca_cristal")
        app.buttons["Añadir playlist"].tap()
        let item = app.buttons["Nueva playlist"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "El menú del + no tiene «Nueva playlist»")
        item.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No salió dónde escribir el nombre de la playlist")
        field.tap()
        field.typeText("Con intro\n")
        sleep(2)
        shot("1-despues-de-intro")
        // Si el aviso sigue abierto, Intro no hizo nada: tampoco vale (hay que poder crear sin soltar el teclado).
        XCTAssertFalse(app.buttons["Crear"].exists, "Intro no cierra el aviso de «Nueva playlist»")
        if app.buttons["Cancelar"].exists { app.buttons["Cancelar"].tap() }
        openPlaylists()
        let created = any("Con intro").waitForExistence(timeout: 5)
        shot("2-playlists")
        XCTAssertTrue(created, "Escribir el nombre y pulsar Intro no crea la playlist")
    }

    /// Dentro de una carpeta: ⋯ › Nueva playlist aquí.
    func testCrearPlaylistDentroDeUnaCarpeta() {
        launch("45_carpeta", ready: "Gimnasio")
        XCTAssertTrue(app.navigationBars["Gimnasio"].waitForExistence(timeout: 10), "No se abrió la carpeta Gimnasio")
        let more = app.buttons["Más opciones"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "No está el botón ⋯")
        more.tap()
        let item = app.buttons["Nueva playlist aquí"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "El menú ⋯ no tiene «Nueva playlist aquí»")
        item.tap()
        let field = app.textFields.firstMatch
        let appeared = field.waitForExistence(timeout: 5)
        shot("1-nombre")
        XCTAssertTrue(appeared, "No salió dónde escribir el nombre de la playlist")
        if appeared {
            field.tap()
            field.typeText("Prueba dentro")
            app.buttons["Crear"].tap()
        }
        let created = any("Prueba dentro").waitForExistence(timeout: 5)
        shot("2-despues")
        note("arbol", app.debugDescription)
        XCTAssertTrue(created, "La playlist «Prueba dentro» no sale en la carpeta")
    }

    // MARK: b) Ordenar los apartados de «Tu música»

    private let sections = ["Playlists", "Tus álbumes", "Canciones", "Artistas", "Recientes", "Estadísticas"]

    /// Mantener pulsado un apartado, arrastrarlo dos puestos más abajo y «Hecho»: el orden tiene que cambiar.
    func testOrdenarTuMusicaArrastrando() {
        launch("01_biblioteca_cristal")
        let before = vertical(sections)
        note("1-antes", before.joined(separator: "\n"))
        XCTAssertEqual(before.first, "Playlists")
        any("Playlists").press(forDuration: 1.0)
        let editing = app.buttons["Hecho"].waitForExistence(timeout: 3)
        shot("1-editando")
        XCTAssertTrue(editing, "Mantener pulsado un apartado no entra en el modo de ordenar")
        // Como una persona: mantener pulsado el apartado y llevarlo encima de «Canciones».
        any("Playlists").press(forDuration: 1.2, thenDragTo: any("Canciones"), withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(1)
        shot("2-arrastrado")
        if app.buttons["Hecho"].exists { app.buttons["Hecho"].tap() }
        sleep(1)
        let after = vertical(sections)
        shot("3-despues")
        note("2-despues", after.joined(separator: "\n"))
        note("arbol", app.debugDescription)
        XCTAssertNotEqual(after, before, "Arrastrar «Playlists» encima de «Canciones» no cambia el orden de Tu música")
    }

    /// Lo mismo sin arrastrar (VoiceOver, Control por botón o quien no atina con el gesto): tiene que haber botones.
    func testOrdenarTuMusicaSinArrastrar() {
        launch("01_biblioteca_cristal")
        let before = vertical(sections)
        any("Playlists").press(forDuration: 1.0)
        _ = app.buttons["Hecho"].waitForExistence(timeout: 3)
        let down = app.buttons["Bajar Playlists"]
        let exists = down.waitForExistence(timeout: 3)
        shot("1-editando")
        XCTAssertTrue(exists, "En el modo de ordenar no hay un botón para bajar un apartado sin arrastrar")
        if exists {
            down.tap()
            sleep(1)
            if app.buttons["Hecho"].exists { app.buttons["Hecho"].tap() }
            sleep(1)
            let after = vertical(sections)
            shot("2-despues")
            note("despues", after.joined(separator: "\n"))
            XCTAssertEqual(Array(after.prefix(2)), ["Tus álbumes", "Playlists"], "«Bajar Playlists» no la deja debajo de «Tus álbumes»; antes: \(before)")
        }
    }

    // MARK: Cuadrícula de Playlists: menú y arrastre

    private let lists = ["Descargadas", "Favoritos", "Noche", "Viaje a la playa", "Para correr"]

    /// Mantener pulsada una portada sin moverla abre su menú; al cerrarlo, la portada no puede quedarse apagada
    /// (como «arrastrándose») ni la cuadrícula sin responder.
    func testMenuDeUnaPortadaYCerrarlo() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        shot("1-antes")
        any("Noche").press(forDuration: 1.2)
        let menu = app.buttons["Mover a…"].waitForExistence(timeout: 3)
        shot("2-menu")
        XCTAssertTrue(menu, "Mantener pulsada una portada no abre su menú")
        // Cerrar tocando fuera del menú.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.62)).tap()
        XCTAssertTrue(app.buttons["Mover a…"].waitForNonExistence(timeout: 5), "El menú no se cierra al tocar fuera")
        sleep(2)
        shot("3-cerrado")
        note("arbol", app.debugDescription)
    }

    /// Mantener pulsada una playlist y arrastrarla al sitio de otra cambia el orden.
    func testOrdenarPlaylistsArrastrando() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        let before = reading(lists)
        note("1-antes", before.joined(separator: "\n"))
        any("Noche").press(forDuration: 1.2, thenDragTo: any("Para correr"), withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(2)
        let after = reading(lists)
        shot("1-despues")
        note("2-despues", after.joined(separator: "\n"))
        XCTAssertNotEqual(after, before, "Arrastrar «Noche» al sitio de «Para correr» no cambia el orden")
    }
}
