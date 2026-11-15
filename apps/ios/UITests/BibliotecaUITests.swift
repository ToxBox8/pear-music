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

    private func center(_ name: String) -> XCUICoordinate {
        any(name).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
    }

    /// Coge la portada de `name` (dedo quieto más de 0,2 s) y la lleva despacio hasta `to`.
    private func holdAndDrag(_ name: String, to: XCUICoordinate, hold: TimeInterval = 0.5) {
        center(name).press(forDuration: hold, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
        sleep(1)
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

    /// Menú de una portada › Ordenar: entra en el modo, sin barra, sin buscador, y tocar una portada no la abre
    /// (paso C; DECISIONS 42 y 43).
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
        for gone in ["Antes", "Después", "Mover a…"] {
            XCTAssertFalse(app.buttons[gone].exists, "En «Ordenar» sigue «\(gone)»")
        }
        XCTAssertEqual(app.searchFields.count, 0, "El buscador sale mientras se ordena")
        any("Noche").tap()
        sleep(1)
        XCTAssertTrue(app.navigationBars["Ordenar"].exists, "Tocar una portada en «Ordenar» la abre")
        app.buttons["Hecho"].tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5), "«Hecho» no sale del modo de ordenar")
        XCTAssertTrue(app.searchFields.count > 0, "Al salir de «Ordenar» no vuelve el buscador")
    }

    /// Modo «Ordenar»: el dedo quieto un momento sobre «Noche» la coge entera y, llevada al sitio de «Viaje a la
    /// playa» (su vecina, lejos de los bordes), cambia el orden.
    func testOrdenarPlaylistsArrastrando() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        let before = reading(lists)
        note("1-antes", before.joined(separator: "\n"))
        startOrdering()
        shot("1-ordenando")
        holdAndDrag("Noche", to: center("Viaje a la playa"))
        shot("2-arrastrada")
        app.buttons["Hecho"].tap()
        sleep(1)
        let after = reading(lists)
        shot("3-despues")
        note("2-despues", after.joined(separator: "\n"))
        XCTAssertEqual(after.firstIndex(of: "Noche"), before.firstIndex(of: "Viaje a la playa"),
                       "Arrastrar «Noche» al sitio de «Viaje a la playa» no la deja ahí; antes \(before), después \(after)")
        XCTAssertEqual(Set(after), Set(before), "Al ordenar se ha perdido alguna portada")
    }

    /// Modo «Ordenar»: deslizar sin esperar desplaza la lista y no coge ninguna portada.
    func testOrdenarDeslizarNoCogeLaPortada() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        startOrdering()
        let before = reading(lists)
        center("Noche").press(forDuration: 0.02, thenDragTo: center("Favoritos"), withVelocity: .fast, thenHoldForDuration: 0.3)
        sleep(1)
        // Volver arriba, por si la lista se ha desplazado.
        app.swipeDown()
        sleep(1)
        let after = reading(lists)
        note("despues", "antes: \(before)\ndespués: \(after)")
        XCTAssertEqual(after, before, "Deslizar sin esperar ha movido una portada")
    }

    /// Modo «Ordenar» con muchas playlists: coger la primera y dejar el dedo cerca del borde de abajo desplaza la
    /// lista sola, y la portada llega a lo que no se veía.
    func testOrdenarDesplazamientoAlBorde() {
        launch("ui_muchas_playlists", ready: "Lista 01")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        startOrdering()
        let first = reading(lists + (1...24).map { String(format: "Lista %02d", $0) }).first ?? "Descargadas"
        let farName = "Lista 01"
        let wasVisible = any(farName).exists && any(farName).isHittable
        // El borde de abajo de lo que se ve: encima de la barra de pestañas y del mini reproductor.
        let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.height - 90
        let edge = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.3, dy: bottom - 40))
        shot("1-antes")
        center(first).press(forDuration: 0.5, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 4)
        sleep(1)
        shot("2-al-borde")
        note("arbol", app.debugDescription)
        XCTAssertTrue(app.navigationBars["Ordenar"].exists, "Se ha salido del modo de ordenar")
        // La lista ha bajado: la primera fila ya no está arriba del todo.
        XCTAssertFalse(any("Descargadas").isHittable && any("Favoritos").isHittable,
                       "Con el dedo cerca del borde de abajo, la lista no se desplaza sola")
        XCTAssertFalse(wasVisible, "«\(farName)» ya se veía al empezar: el test no prueba nada")
    }

    /// Modo «Ordenar» con carpetas: soltar una playlist encima de una carpeta la mete dentro.
    func testMeterEnUnaCarpetaArrastrando() {
        launch("43_carpetas", ready: "Viajes")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        XCTAssertTrue(any("Domingo lento").waitForExistence(timeout: 5))
        startOrdering()
        XCTAssertTrue(any("Carpeta Viajes").isHittable, "La carpeta «Viajes» no se ve")
        holdAndDrag("Domingo lento", to: center("Carpeta Viajes"))
        sleep(1)
        shot("1-soltada")
        let moved = any("Domingo lento").waitForNonExistence(timeout: 5)
        note("arbol", app.debugDescription)
        XCTAssertTrue(moved, "Soltar «Domingo lento» encima de la carpeta «Viajes» no la mete dentro")
        XCTAssertTrue(any("Carpeta Viajes").exists, "La carpeta ha desaparecido")
    }

    // MARK: Fijados: menú y modo «Ordenar»

    /// Fijar dos playlists, mantener pulsada una en Fijados › Ordenar y arrastrarla al sitio de la otra. Mientras
    /// tanto, «Ordenar» de «Tu música» no se dibuja (un solo shu) y no hay «Antes» ni «Después».
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
        // Con el menú abierto hay dos «Ordenar»: el de «Tu música» (tapado) y el del menú.
        let sorts = app.buttons.matching(NSPredicate(format: "label == %@", "Ordenar"))
        XCTAssertTrue(app.buttons["Soltar de arriba"].waitForExistence(timeout: 3), "Mantener pulsado un fijado no abre su menú")
        let item = (0..<sorts.count).map { sorts.element(boundBy: $0) }.first { $0.isHittable }
        shot("2-menu")
        XCTAssertNotNil(item, "El menú de un fijado no ofrece «Ordenar»")
        item?.tap()
        let done = app.buttons["Hecho"].firstMatch
        let editing = done.waitForExistence(timeout: 5)
        shot("3-ordenando")
        XCTAssertTrue(editing, "«Ordenar» de un fijado no entra en el modo de ordenar")
        guard editing else { return }
        XCTAssertFalse(app.buttons["Antes"].exists || app.buttons["Después"].exists, "Fijados sigue con «Antes» y «Después»")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Ordenar")).count, 0,
                       "Con Fijados ordenándose, «Ordenar» de «Tu música» sigue ahí (dos shu)")
        holdAndDrag(before[0], to: center(before[1]))
        let now = pinned.sorted { any($0).frame.minX < any($1).frame.minX }
        shot("4-movido")
        XCTAssertEqual(now, Array(before.reversed()), "Arrastrar no cambia el orden de Fijados")
        done.tap()
        XCTAssertTrue(app.buttons["Ordenar"].waitForExistence(timeout: 5), "Al terminar no vuelve «Ordenar» de «Tu música»")
    }
}
