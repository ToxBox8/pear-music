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

    /// Vuelve a la pantalla anterior: con el botón de la barra si lo hay; si no, deslizando desde el borde.
    private func back() {
        let bar = app.navigationBars.buttons.element(boundBy: 0)
        if bar.exists && bar.isHittable { bar.tap() } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        }
        sleep(1)
    }

    /// Escribe el nombre en el aviso y pulsa «Crear». Comprueba de paso que «Crear» está apagado con el nombre vacío.
    private func typeName(_ name: String, pressCreate: Bool = true) {
        let field = app.textFields.firstMatch
        let appeared = field.waitForExistence(timeout: 5)
        XCTAssertTrue(appeared, "No salió dónde escribir el nombre")
        guard appeared else { return }
        let create = app.buttons["Crear"]
        XCTAssertTrue(create.waitForExistence(timeout: 3), "No hay botón «Crear»")
        XCTAssertFalse(create.isEnabled, "«Crear» tiene que estar apagado con el nombre vacío")
        field.tap()
        field.typeText(name)
        XCTAssertTrue(create.isEnabled, "«Crear» está apagado con el nombre escrito")
        if pressCreate { create.tap() }
    }

    /// La playlist recién creada se abre: se ve su nombre y el texto de «añade canciones».
    private func assertOpened(_ name: String) {
        let empty = any("Mantén pulsada una canción").waitForExistence(timeout: 5)
        shot("abierta")
        XCTAssertTrue(empty && any(name).exists, "Al crear «\(name)» no se abre la playlist")
    }

    // MARK: a) Crear una playlist (pieza 1: se abre al crearla)

    /// Biblioteca › + › Nueva playlist › nombre › Crear. Se abre, y al volver sale en Tu música › Playlists.
    func testCrearPlaylistDesdeElMas() {
        launch("01_biblioteca_cristal")
        let plus = app.buttons["Añadir playlist"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "No está el botón +")
        plus.tap()
        shot("1-menu")
        let item = app.buttons["Nueva playlist"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "El menú del + no tiene «Nueva playlist»")
        item.tap()
        typeName("Prueba UI")
        assertOpened("Prueba UI")
        back()
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
        typeName("Con intro", pressCreate: false)
        app.textFields.firstMatch.typeText("\n")
        sleep(2)
        shot("1-despues-de-intro")
        // Si el aviso sigue abierto, Intro no hizo nada: tampoco vale (hay que poder crear sin soltar el teclado).
        XCTAssertFalse(app.buttons["Crear"].exists, "Intro no cierra el aviso de «Nueva playlist»")
        if app.buttons["Cancelar"].exists { app.buttons["Cancelar"].tap() }
        assertOpened("Con intro")
    }

    /// En Tu música › Playlists: + › Nueva playlist. Se abre, y al volver está en la cuadrícula.
    func testCrearPlaylistDesdePlaylists() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        let plus = app.buttons["Nueva playlist o carpeta"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "Playlists no tiene el botón +")
        plus.tap()
        let item = app.buttons["Nueva playlist"]
        let offered = item.waitForExistence(timeout: 5)
        shot("1-menu")
        XCTAssertTrue(offered, "El + de Playlists no ofrece «Nueva playlist»")
        guard offered else { return }
        item.tap()
        typeName("Desde Playlists")
        assertOpened("Desde Playlists")
        back()
        let created = any("Desde Playlists").waitForExistence(timeout: 5)
        shot("2-despues")
        XCTAssertTrue(created, "La playlist «Desde Playlists» no sale en la cuadrícula")
    }

    /// Dentro de una carpeta: + › Nueva playlist aquí.
    func testCrearPlaylistDentroDeUnaCarpeta() {
        launch("45_carpeta", ready: "Gimnasio")
        XCTAssertTrue(app.navigationBars["Gimnasio"].waitForExistence(timeout: 10), "No se abrió la carpeta Gimnasio")
        let plus = app.buttons["Nueva playlist o carpeta"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "La carpeta no tiene el botón +")
        plus.tap()
        let item = app.buttons["Nueva playlist aquí"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "El + no tiene «Nueva playlist aquí»")
        item.tap()
        typeName("Prueba dentro")
        assertOpened("Prueba dentro")
        back()
        let created = any("Prueba dentro").waitForExistence(timeout: 5)
        shot("2-despues")
        note("arbol", app.debugDescription)
        XCTAssertTrue(created, "La playlist «Prueba dentro» no sale en la carpeta")
    }

    /// Tu música › Playlists: + › Nueva carpeta. La carpeta aparece en la cuadrícula (y no se abre nada).
    func testCrearCarpetaDesdePlaylists() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        app.buttons["Nueva playlist o carpeta"].tap()
        let item = app.buttons["Nueva carpeta"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "El + de Playlists no ofrece «Nueva carpeta»")
        item.tap()
        typeName("Verano")
        let created = any("Carpeta Verano").waitForExistence(timeout: 5)
        shot("1-despues")
        XCTAssertTrue(created, "La carpeta «Verano» no sale en la cuadrícula")
        XCTAssertTrue(app.navigationBars["Playlists"].exists, "Crear una carpeta no tiene que salir de Playlists")
    }

    // MARK: b) Ordenar los apartados de «Tu música»

    private let sections = ["Playlists", "Tus álbumes", "Canciones", "Artistas", "Recientes", "Estadísticas"]

    /// «Ordenar» entra en el modo de ordenar y «Bajar Playlists» la deja debajo de «Tus álbumes», sin arrastrar
    /// (VoiceOver, Control por botón o quien no atina con el gesto).
    func testOrdenarTuMusicaConLasFlechas() {
        launch("01_biblioteca_cristal")
        let before = vertical(sections)
        XCTAssertEqual(before.first, "Playlists")
        let sort = app.buttons["Ordenar"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5), "No hay botón «Ordenar» en Tu música")
        sort.tap()
        let down = app.buttons["Bajar Playlists"]
        let exists = down.waitForExistence(timeout: 3)
        shot("1-ordenando")
        XCTAssertTrue(exists, "En el modo de ordenar no hay un botón para bajar un apartado sin arrastrar")
        XCTAssertFalse(app.buttons["Subir Playlists"].isEnabled, "El primer apartado no puede subir")
        if exists { down.tap() }
        sleep(1)
        XCTAssertTrue(app.buttons["Hecho"].exists, "No hay «Hecho» para salir del modo de ordenar")
        app.buttons["Hecho"].tap()
        sleep(1)
        let after = vertical(sections)
        shot("2-despues")
        note("despues", after.joined(separator: "\n"))
        XCTAssertEqual(Array(after.prefix(2)), ["Tus álbumes", "Playlists"], "«Bajar Playlists» no la deja debajo de «Tus álbumes»; antes: \(before)")
        XCTAssertTrue(app.buttons["Ordenar"].exists, "«Hecho» no sale del modo de ordenar")
    }

    /// Arrastrar el asa (≡) de «Playlists» hasta la fila de «Canciones» la baja dos puestos.
    func testOrdenarTuMusicaArrastrandoElAsa() {
        launch("01_biblioteca_cristal")
        app.buttons["Ordenar"].tap()
        let down = app.buttons["Bajar Playlists"]
        XCTAssertTrue(down.waitForExistence(timeout: 3), "No se entró en el modo de ordenar")
        // El asa va a la derecha de la flecha de bajar (44 pt) y no es un elemento de accesibilidad: por coordenadas.
        let handle = down.coordinate(withNormalizedOffset: CGVector(dx: 1.5, dy: 0.5))
        let target = app.buttons["Bajar Canciones"].coordinate(withNormalizedOffset: CGVector(dx: 1.5, dy: 0.6))
        handle.press(forDuration: 0.2, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        shot("1-arrastrado")
        app.buttons["Hecho"].tap()
        sleep(1)
        let after = vertical(sections)
        note("despues", after.joined(separator: "\n"))
        XCTAssertEqual(Array(after.prefix(3)), ["Tus álbumes", "Canciones", "Playlists"], "Arrastrar el asa de «Playlists» hasta «Canciones» no la deja en su sitio")
    }

    /// Mantener pulsado un apartado abre su menú, con «Ordenar», y no abre el apartado.
    func testOrdenarTuMusicaManteniendoPulsado() {
        launch("01_biblioteca_cristal")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Ordenar")).count, 1)
        any("Playlists").press(forDuration: 1.2)
        // Con el menú abierto hay dos «Ordenar»: el de junto al título (tapado) y el del menú, que es el que se puede tocar.
        let inMenu = app.buttons.matching(NSPredicate(format: "label == %@", "Ordenar"))
        let shown = app.buttons["Hecho"].exists == false && inMenu.element(boundBy: 1).waitForExistence(timeout: 3)
        let menuItem = [inMenu.element(boundBy: 0), inMenu.element(boundBy: 1)].first { $0.exists && $0.isHittable } ?? inMenu.element(boundBy: 0)
        shot("1-menu")
        XCTAssertTrue(shown, "Mantener pulsado un apartado no ofrece «Ordenar»")
        XCTAssertFalse(app.navigationBars["Playlists"].exists, "Mantener pulsado no puede abrir el apartado")
        if shown { menuItem.tap() }
        let editing = app.buttons["Hecho"].waitForExistence(timeout: 3)
        shot("2-ordenando")
        XCTAssertTrue(editing, "«Ordenar» del menú no entra en el modo de ordenar")
    }

    // MARK: Cuadrícula de Playlists: menú (pieza 2) y modo «Ordenar» (pieza 3)

    private let lists = ["Descargadas", "Favoritos", "Noche", "Viaje a la playa", "Para correr"]

    /// El asa (≡) de una portada en el modo «Ordenar»: arriba a la derecha de su celda. No es un elemento de
    /// accesibilidad (con VoiceOver se usan los botones), así que se toca por coordenadas.
    private func grip(_ name: String) -> XCUICoordinate {
        any(name).coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0)).withOffset(CGVector(dx: -22, dy: 22))
    }

    /// Sube la cuadrícula hasta que el asa de `name` quede por encima de la barra «Antes / Después» (que va en el
    /// borde de abajo); si no, el dedo empieza encima de la barra y no coge nada.
    private func bringAboveBar(_ name: String) {
        let barTop = app.buttons["Antes"].exists ? app.buttons["Antes"].frame.minY : app.frame.height - 200
        for _ in 0..<4 {
            let el = any(name)
            guard el.exists, el.frame.minY + 44 > barTop - 24 else { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: barTop - 40))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -160)), withVelocity: .slow, thenHoldForDuration: 0.3)
            sleep(1)
        }
    }

    private func center(_ name: String) -> XCUICoordinate {
        any(name).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
    }

    /// ⋯ › Ordenar. Tiene que salir «Hecho».
    private func startOrdering() {
        app.buttons["Más opciones"].tap()
        let item = app.buttons["Ordenar"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "El menú ⋯ no ofrece «Ordenar»")
        item.tap()
        XCTAssertTrue(app.buttons["Hecho"].waitForExistence(timeout: 5), "«Ordenar» no entra en el modo de ordenar")
    }

    /// Mantener pulsada una portada abre su menú, completo, y nada más: al cerrarlo la portada sigue igual y no
    /// se ha entrado en ningún modo.
    func testMenuDeUnaPortadaYCerrarlo() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        shot("1-antes")
        any("Noche").press(forDuration: 1.2)
        let menu = app.buttons["Mover a…"].waitForExistence(timeout: 3)
        shot("2-menu")
        XCTAssertTrue(menu, "Mantener pulsada una portada no abre su menú")
        for item in ["Abrir", "Ordenar", "Fijar arriba", "Editar", "Eliminar…"] {
            XCTAssertTrue(app.buttons[item].exists, "Al menú de una playlist le falta «\(item)»")
        }
        // Cerrar tocando fuera del menú.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.62)).tap()
        XCTAssertTrue(app.buttons["Mover a…"].waitForNonExistence(timeout: 5), "El menú no se cierra al tocar fuera")
        sleep(2)
        shot("3-cerrado")
        note("arbol", app.debugDescription)
        XCTAssertFalse(app.buttons["Hecho"].exists, "Mantener pulsado sólo abre el menú: no entra en «Ordenar»")
        XCTAssertTrue(app.navigationBars["Playlists"].exists, "Mantener pulsado no puede abrir la playlist")
    }

    /// Menú de una playlist › Eliminar… › la misma confirmación que en Ajustes › Eliminar.
    func testEliminarPlaylistDesdeSuMenu() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        any("Noche").press(forDuration: 1.2)
        let item = app.buttons["Eliminar…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "El menú de una playlist no ofrece «Eliminar…»")
        item.tap()
        let asked = any("¿Eliminar «Noche»?").waitForExistence(timeout: 5)
        shot("1-confirmacion")
        XCTAssertTrue(asked, "«Eliminar…» no pide confirmación")
        XCTAssertTrue(any("No se puede deshacer").exists, "La confirmación no es la de Ajustes")
        // Cancelar no borra nada.
        app.buttons["Cancelar"].tap()
        sleep(1)
        XCTAssertTrue(any("Noche").exists, "Cancelar ha borrado la playlist")
        any("Noche").press(forDuration: 1.2)
        app.buttons["Eliminar…"].tap()
        XCTAssertTrue(any("¿Eliminar «Noche»?").waitForExistence(timeout: 5))
        app.buttons["Eliminar"].tap()
        let gone = any("Noche").waitForNonExistence(timeout: 5)
        shot("2-eliminada")
        XCTAssertTrue(gone, "«Eliminar» no quita la playlist de la cuadrícula")
    }

    /// Menú de una portada › Ordenar: entra en el modo con esa portada ya elegida («Mover a…» encendido).
    func testOrdenarDesdeElMenuDeUnaPortada() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        any("Noche").press(forDuration: 1.2)
        let item = app.buttons["Ordenar"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "El menú de una playlist no ofrece «Ordenar»")
        item.tap()
        let editing = app.buttons["Hecho"].waitForExistence(timeout: 5)
        shot("1-ordenando")
        XCTAssertTrue(editing, "«Ordenar» del menú no entra en el modo de ordenar")
        XCTAssertTrue(app.navigationBars["Ordenar"].exists, "El título del modo no es «Ordenar»")
        XCTAssertTrue(app.buttons["Mover a…"].isEnabled, "La portada del menú no llega elegida")
        XCTAssertTrue(app.buttons["Antes"].exists && app.buttons["Después"].exists, "Faltan «Antes» y «Después»")
        app.buttons["Hecho"].tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5), "«Hecho» no sale del modo de ordenar")
        XCTAssertFalse(app.buttons["Antes"].exists, "La barra de botones sigue fuera del modo de ordenar")
    }

    /// Modo «Ordenar»: coger «Noche» por su asa y llevarla al sitio de «Para correr» cambia el orden. Ya no se
    /// salta: la cuadrícula arrastra con un gesto propio, no con el del sistema.
    func testOrdenarPlaylistsArrastrando() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        let before = reading(lists)
        note("1-antes", before.joined(separator: "\n"))
        startOrdering()
        shot("1-ordenando")
        grip("Noche").press(forDuration: 0.2, thenDragTo: center("Para correr"), withVelocity: .slow, thenHoldForDuration: 0.5)
        sleep(1)
        shot("2-arrastrada")
        app.buttons["Hecho"].tap()
        sleep(1)
        let after = reading(lists)
        shot("3-despues")
        note("2-despues", after.joined(separator: "\n"))
        XCTAssertEqual(after.firstIndex(of: "Noche"), before.firstIndex(of: "Para correr"),
                       "Arrastrar «Noche» por su asa al sitio de «Para correr» no la deja ahí; antes \(before), después \(after)")
        XCTAssertEqual(Set(after), Set(before), "Al ordenar se ha perdido alguna portada")
    }

    /// Modo «Ordenar» sin arrastrar: tocar una portada la elige y «Antes» / «Después» la mueven un puesto.
    func testOrdenarPlaylistsConLosBotones() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        let before = reading(lists)
        startOrdering()
        XCTAssertFalse(app.buttons["Antes"].isEnabled || app.buttons["Después"].isEnabled, "Sin nada elegido, los botones tienen que estar apagados")
        any("Noche").tap()
        sleep(1)
        let forward = app.buttons["Después"].isEnabled
        XCTAssertTrue(forward || app.buttons["Antes"].isEnabled, "Con una portada elegida no se enciende ningún botón")
        shot("1-elegida")
        (forward ? app.buttons["Después"] : app.buttons["Antes"]).tap()
        sleep(1)
        app.buttons["Hecho"].tap()
        sleep(1)
        let after = reading(lists)
        shot("2-despues")
        note("despues", "antes: \(before)\ndespués: \(after)")
        let was = before.firstIndex(of: "Noche") ?? -1
        XCTAssertEqual(after.firstIndex(of: "Noche"), was + (forward ? 1 : -1), "El botón no mueve «Noche» un puesto; antes \(before), después \(after)")
    }

    /// Modo «Ordenar» con carpetas: soltar una playlist encima de una carpeta la mete dentro.
    func testMeterEnUnaCarpetaArrastrando() {
        launch("43_carpetas", ready: "Viajes")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        XCTAssertTrue(any("Domingo lento").waitForExistence(timeout: 5))
        startOrdering()
        bringAboveBar("Domingo lento")
        XCTAssertTrue(any("Carpeta Viajes").isHittable, "Al subir la cuadrícula, la carpeta «Viajes» se sale de la pantalla")
        grip("Domingo lento").press(forDuration: 0.2, thenDragTo: center("Carpeta Viajes"), withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(2)
        shot("1-soltada")
        let moved = any("Domingo lento").waitForNonExistence(timeout: 5)
        note("arbol", app.debugDescription)
        XCTAssertTrue(moved, "Soltar «Domingo lento» encima de la carpeta «Viajes» no la mete dentro")
        XCTAssertTrue(any("Carpeta Viajes").exists, "La carpeta ha desaparecido")
    }

    // MARK: Fijados: menú y modo «Ordenar»

    /// Fijar dos playlists, mantener pulsada una en Fijados › Ordenar, y moverla con el botón.
    func testOrdenarFijados() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        for name in ["Noche", "Para correr"] {
            XCTAssertTrue(any(name).waitForExistence(timeout: 5))
            any(name).press(forDuration: 1.2)
            let pin = app.buttons["Fijar arriba"]
            XCTAssertTrue(pin.waitForExistence(timeout: 3), "El menú de «\(name)» no ofrece «Fijar arriba»")
            pin.tap()
            sleep(1)
        }
        back()
        XCTAssertTrue(any("Fijados").waitForExistence(timeout: 5))
        let pinned = ["Noche", "Para correr"]
        let before = pinned.sorted { any($0).frame.minX < any($1).frame.minX }
        shot("1-fijados")
        any(before[0]).press(forDuration: 1.2)
        // Con el menú abierto puede haber dos «Ordenar»: el de «Tu música» (tapado) y el del menú.
        let sorts = app.buttons.matching(NSPredicate(format: "label == %@", "Ordenar"))
        XCTAssertTrue(app.buttons["Soltar de arriba"].waitForExistence(timeout: 3), "Mantener pulsado un fijado no abre su menú")
        let item = (0..<sorts.count).map { sorts.element(boundBy: $0) }.first { $0.isHittable }
        shot("2-menu")
        XCTAssertNotNil(item, "El menú de un fijado no ofrece «Ordenar»")
        item?.tap()
        let after = app.buttons["Después"]
        let editing = after.waitForExistence(timeout: 5)
        shot("3-ordenando")
        XCTAssertTrue(editing, "«Ordenar» de un fijado no entra en el modo de ordenar")
        guard editing else { return }
        XCTAssertTrue(after.isEnabled, "El primer fijado llega elegido y tiene que poder ir «Después»")
        after.tap()
        sleep(1)
        let now = pinned.sorted { any($0).frame.minX < any($1).frame.minX }
        shot("4-movido")
        XCTAssertEqual(now, Array(before.reversed()), "«Después» no cambia el orden de Fijados")
        app.buttons["Hecho"].firstMatch.tap()
        XCTAssertTrue(after.waitForNonExistence(timeout: 5), "«Hecho» no sale del modo de ordenar de Fijados")
    }
}
