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
        let sort = sortButton
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
        XCTAssertTrue(sortButton.exists, "«Hecho» no sale del modo de ordenar")
    }

    /// Arrastrar el asa (≡) de «Playlists» hasta la fila de «Canciones» la baja dos puestos.
    func testOrdenarTuMusicaArrastrandoElAsa() {
        launch("01_biblioteca_cristal")
        sortButton.tap()
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
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Ordenar", "lapiz-ordenar")).count, 1)
        any("Playlists").press(forDuration: 1.2)
        // Con el menú abierto hay dos «Ordenar»: el de junto al título (tapado) y el del menú, que es el que se puede tocar.
        let inMenu = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Ordenar", "lapiz-ordenar"))
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

    /// El registro del arrastre que deja la app en los tests (`OrderDebugLabel`): si el gesto se pidió, si arrancó,
    /// por qué no y con cuántas celdas medidas.
    private func orderLog(_ id: String = "orden-registro") -> String {
        let e = app.descendants(matching: .any).matching(identifier: id).firstMatch
        return e.exists ? "registro: \(e.label)" : "registro: no hay (\(id))"
    }

    /// Si `name` queda bajo el mini reproductor o la barra de pestañas, sube la lista hasta dejarla por encima, para
    /// que la pulsación caiga en la portada.
    private func liftAboveBars(_ name: String) {
        let bottom = (app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.height - 90) - 90
        let over = any(name).frame.maxY - bottom
        guard over > 0 else { return }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -(over + 40))), withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
    }

    /// «Ordenar» de un menú o de junto al título de «Tu música», no el lápiz (prompt 2-0b), que se llama igual.
    private var sortButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Ordenar", "lapiz-ordenar")).firstMatch
    }

    /// El lápiz junto al ⋯ (o en Fijados): tiene que estar, llamarse «Ordenar» y entrar en el modo.
    private func tapPencil(_ where_: String) {
        let pencil = app.buttons["lapiz-ordenar"].firstMatch
        XCTAssertTrue(pencil.waitForExistence(timeout: 5), "No hay lápiz en \(where_)")
        XCTAssertEqual(pencil.label, "Ordenar", "El lápiz de \(where_) no se llama «Ordenar» para VoiceOver")
        pencil.tap()
        XCTAssertTrue(app.buttons["Hecho"].firstMatch.waitForExistence(timeout: 5), "El lápiz de \(where_) no entra en «Ordenar»")
        XCTAssertFalse(app.buttons["lapiz-ordenar"].firstMatch.exists, "Ordenando, el lápiz de \(where_) tiene que irse")
    }

    /// ⋯ › Ordenar. Tiene que salir «Hecho».
    private func startOrdering() {
        app.buttons["Más opciones"].tap()
        let item = sortButton
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
        let item = sortButton
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
        let log = orderLog()
        note("registro", log)
        app.buttons["Hecho"].tap()
        sleep(1)
        let after = reading(lists)
        shot("3-despues")
        note("2-despues", after.joined(separator: "\n"))
        XCTAssertEqual(after.firstIndex(of: "Noche"), before.firstIndex(of: "Viaje a la playa"),
                       "Arrastrar «Noche» al sitio de «Viaje a la playa» no la deja ahí; antes \(before), después \(after); \(log)")
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
        // «Lista 01» está abajo, fuera de la pantalla (por eso sirve): se espera a la cuadrícula.
        launch("ui_muchas_playlists", ready: "Descargadas")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        startOrdering()
        // La primera portada es siempre «Descargadas». (Antes se buscaba leyendo las 29 portadas, que en la CI tardaba
        // de 2 a 5 minutos con la app parada en «Ordenar» antes del gesto.)
        let first = "Descargadas"
        XCTAssertTrue(any(first).isHittable, "«Descargadas» no está arriba al entrar en «Ordenar»")
        let farName = "Lista 01"
        let wasVisible = any(farName).exists && any(farName).isHittable
        let y0 = any(first).frame.minY
        // El borde de abajo de lo que se ve: encima de la barra de pestañas y del mini reproductor.
        let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.height - 90
        let edge = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.3, dy: bottom - 40))
        shot("1-antes")
        // 1 s quieto (la app pide 0,2 s): con margen para una máquina lenta.
        center(first).press(forDuration: 1.0, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 4)
        sleep(1)
        shot("2-al-borde")
        let log = orderLog()
        note("registro", log)
        note("arbol", app.debugDescription)
        XCTAssertTrue(app.navigationBars["Ordenar"].exists, "Se ha salido del modo de ordenar")
        // Dos fallos distintos: que la portada no se haya cogido (sigue en su sitio) o que, cogida, la lista no baje.
        let stayed = any(first).isHittable && abs(any(first).frame.minY - y0) < 2 && any("Favoritos").isHittable
        XCTAssertFalse(stayed, "«Descargadas» sigue en su sitio (\(y0)): la portada no se ha cogido o la lista no se ha movido nada; \(log)")
        // La lista ha bajado: la primera fila ya no está arriba del todo.
        XCTAssertFalse(any("Descargadas").isHittable && any("Favoritos").isHittable,
                       "Con el dedo cerca del borde de abajo, la lista no se desplaza sola; \(log)")
        XCTAssertFalse(wasVisible, "«\(farName)» ya se veía al empezar: el test no prueba nada")
    }

    private var many: [String] { (1...24).map { String(format: "Lista %02d", $0) } }

    /// La «Lista NN» que se ve más cerca del centro de la pantalla (o la más baja, con `lowest`).
    private func visibleList(lowest: Bool = false) -> String? {
        let mid = app.frame.midY
        let seen = many.filter { any($0).exists && any($0).isHittable }
        return lowest ? seen.max { any($0).frame.minY < any($1).frame.minY }
                      : seen.min { abs(any($0).frame.midY - mid) < abs(any($1).frame.midY - mid) }
    }

    /// Entrar y salir de «Ordenar» con la lista bajada no la lleva arriba: lo que se veía sigue a la vista y casi en
    /// el mismo sitio (cambia sólo lo que ocupan el buscador y la ayuda).
    func testOrdenarNoLlevaLaListaArriba() {
        launch("ui_muchas_playlists", ready: "Descargadas")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        guard let name = visibleList() else { return XCTFail("Tras desplazar no se ve ninguna «Lista NN»") }
        let y0 = any(name).frame.minY
        XCTAssertFalse(any("Descargadas").isHittable, "La lista no ha bajado: el test no prueba nada")
        shot("1-bajada")
        startOrdering()
        sleep(1)
        shot("2-ordenando")
        XCTAssertTrue(any(name).exists && any(name).isHittable, "Al entrar en «Ordenar» «\(name)» ya no se ve: la lista ha vuelto arriba")
        XCTAssertLessThan(abs(any(name).frame.minY - y0), 120, "Al entrar en «Ordenar» la lista salta (\(y0) → \(any(name).frame.minY))")
        XCTAssertFalse(any("Descargadas").isHittable, "Al entrar en «Ordenar» la lista vuelve arriba")
        app.buttons["Hecho"].tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5), "«Hecho» no sale del modo de ordenar")
        sleep(1)
        shot("3-fuera")
        XCTAssertTrue(any(name).exists && any(name).isHittable, "Al salir de «Ordenar» «\(name)» ya no se ve: la lista ha vuelto arriba")
        XCTAssertLessThan(abs(any(name).frame.minY - y0), 120, "Al salir de «Ordenar» la lista salta (\(y0) → \(any(name).frame.minY))")
    }

    /// «Ordenar» desde el menú de una portada de abajo: esa portada sigue a la vista.
    func testOrdenarDesdeElMenuDejaLaPortadaALaVista() {
        launch("ui_muchas_playlists", ready: "Descargadas")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        app.swipeUp()
        sleep(1)
        guard let name = visibleList(lowest: true) else { return XCTFail("Tras desplazar no se ve ninguna «Lista NN»") }
        any(name).press(forDuration: 1.2)
        let item = sortButton
        XCTAssertTrue(item.waitForExistence(timeout: 3), "El menú de «\(name)» no ofrece «Ordenar»")
        item.tap()
        XCTAssertTrue(app.buttons["Hecho"].waitForExistence(timeout: 5), "«Ordenar» del menú no entra en el modo de ordenar")
        sleep(1)
        shot("1-ordenando")
        XCTAssertTrue(any(name).exists && any(name).isHittable, "Al entrar en «Ordenar» desde su menú, «\(name)» no se ve")
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
        let log = orderLog()
        note("registro", log)
        let moved = any("Domingo lento").waitForNonExistence(timeout: 5)
        note("arbol", app.debugDescription)
        XCTAssertTrue(moved, "Soltar «Domingo lento» encima de la carpeta «Viajes» no la mete dentro; \(log)")
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
            // Que la pulsación no caiga en el mini reproductor ni en la barra de pestañas.
            liftAboveBars(name)
            let where_ = any(name).frame
            shot("0-antes-de-\(name.filter { $0.isLetter })")
            any(name).press(forDuration: 1.2)
            let pin = app.buttons["Fijar arriba"]
            let offered = pin.waitForExistence(timeout: 3)
            if !offered {
                shot("0-sin-menu-\(name.filter { $0.isLetter })")
                note("sin-menu", "«\(name)» en \(where_), hittable \(any(name).isHittable)\n\(app.debugDescription)")
            }
            XCTAssertTrue(offered, "El menú de «\(name)» no ofrece «Fijar arriba» (portada en \(where_))")
            guard offered else { return }
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
        let sorts = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Ordenar", "lapiz-ordenar"))
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
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Ordenar", "lapiz-ordenar")).count, 0,
                       "Con Fijados ordenándose, «Ordenar» de «Tu música» sigue ahí (dos shu)")
        // Las dos portadas de Fijados tiemblan (prompt 2-0).
        let wiggle = orderLog("orden-temblor-fijados")
        note("temblor", wiggle)
        XCTAssertTrue(wiggle.contains("tiemblan=2 bordes=0"), "En «Ordenar» de Fijados no tiemblan las dos portadas; \(wiggle)")
        holdAndDrag(before[0], to: center(before[1]))
        let now = pinned.sorted { any($0).frame.minX < any($1).frame.minX }
        shot("4-movido")
        let log = orderLog("orden-registro-fijados")
        note("registro", log)
        XCTAssertEqual(now, Array(before.reversed()), "Arrastrar no cambia el orden de Fijados; \(log)")
        // Arrastrar a los lados no puede cambiar de pestaña (lo hacía: el test acababa en Inicio).
        XCTAssertTrue(any("Tu música").exists, "Arrastrar en Fijados ha cambiado de pestaña")
        done.tap()
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5), "Al terminar no vuelve «Ordenar» de «Tu música»")
    }
    // MARK: Prompt 2-0 del bloque 2: temblor, arrastrar a los cuatro lados y Tus álbumes

    /// En «Ordenar» de Playlists tiemblan todas las portadas (también Descargadas y Favoritos), sin borde. Se lee el
    /// registro `orden-temblor`: comparar capturas no sirve, porque el fondo Cristal se mueve solo (CI 43959102005).
    func testOrdenarLasPortadasTiemblan() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        sleep(1)
        startOrdering()
        sleep(1)
        shot("1-ordenando")
        let log = orderLog("orden-temblor")
        note("temblor", log)
        XCTAssertTrue(log.contains("tiemblan=5 bordes=0"), "En «Ordenar» no tiemblan las cinco portadas; \(log)")
        app.buttons["Hecho"].tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "orden-temblor").firstMatch.exists,
                       "Al salir de «Ordenar» las portadas siguen temblando")
    }

    /// Con «Reducir movimiento» (escenario 54, como la captura) nada tiembla: cada portada lleva un borde.
    func testOrdenarSinTemblorConReducirMovimiento() {
        launch("54_playlists_ordenar", ready: "Viajes")
        XCTAssertTrue(app.buttons["Hecho"].waitForExistence(timeout: 10), "El escenario no abre Playlists en «Ordenar»")
        sleep(1)
        shot("1-ordenando")
        let log = orderLog("orden-temblor")
        note("temblor", log)
        XCTAssertTrue(log.contains("tiemblan=0"), "Con «Reducir movimiento» las portadas tiemblan; \(log)")
        XCTAssertFalse(log.contains("bordes=0"), "Con «Reducir movimiento» las portadas no llevan el borde; \(log)")
    }

    /// Coge la portada que está en `from` (orden de lectura de la cuadrícula de Playlists) y la suelta en el sitio de la
    /// que está en `to`: tiene que quedarse ahí, con todas las demás, y el arrastre tiene que haber arrancado con las
    /// celdas medidas aunque las portadas tiemblen.
    private func dragInGrid(from: Int, to: Int) {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        // La tercera fila, por encima del mini reproductor y de la barra de pestañas.
        liftAboveBars(reading(lists).last ?? "Para correr")
        startOrdering()
        sleep(1)
        let before = reading(lists)
        guard before.count == lists.count else { return XCTFail("No se ven las cinco portadas: \(before)") }
        let (a, b) = (before[from], before[to])
        shot("1-antes")
        holdAndDrag(a, to: center(b))
        shot("2-soltada")
        let log = orderLog()
        note("registro", log)
        app.buttons["Hecho"].tap()
        sleep(1)
        let after = reading(lists)
        note("orden", "antes: \(before)\ndespués: \(after)")
        XCTAssertEqual(after.firstIndex(of: a), to, "Arrastrar «\(a)» al sitio de «\(b)» no la deja ahí; antes \(before), después \(after); \(log)")
        XCTAssertEqual(Set(after), Set(before), "Al ordenar se ha perdido alguna portada")
        XCTAssertTrue(log.contains("arrancados=1") && log.contains("fallo=-") && log.contains("celdas=5"),
                      "El arrastre no arrancó con las cinco celdas medidas; \(log)")
    }

    /// Fila del medio: de la izquierda a la derecha.
    func testOrdenarArrastrandoALaDerecha() { dragInGrid(from: 2, to: 3) }
    /// Fila del medio: de la derecha a la izquierda.
    func testOrdenarArrastrandoALaIzquierda() { dragInGrid(from: 3, to: 2) }
    /// De la tercera fila a la segunda.
    func testOrdenarArrastrandoHaciaArriba() { dragInGrid(from: 4, to: 2) }
    /// De la segunda fila a la tercera.
    func testOrdenarArrastrandoHaciaAbajo() { dragInGrid(from: 2, to: 4) }

    private let albums = ["After Hours", "Un Verano Sin Ti", "Future Nostalgia"]

    private func openAlbums() {
        let row = button("Tus álbumes")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No está la fila «Tus álbumes» de Tu música")
        row.tap()
        XCTAssertTrue(app.navigationBars["Tus álbumes"].waitForExistence(timeout: 5), "No se abrió Tu música › Tus álbumes")
        XCTAssertTrue(any(albums[0]).waitForExistence(timeout: 5))
    }

    /// Mantener pulsado un álbum abre su menú: lo que tiene sentido para un álbum (Abrir, Ordenar, Fijar arriba,
    /// Eliminar…) y no lo de las playlists que no (Editar, Mover a…). «Ordenar» entra en el modo, las portadas
    /// tiemblan y arrastrar un álbum al sitio de otro cambia el orden.
    func testMenuDeUnAlbumYOrdenar() {
        launch("01_biblioteca_cristal")
        openAlbums()
        let before = reading(albums)
        note("1-antes", before.joined(separator: "\n"))
        any(before[0]).press(forDuration: 1.2)
        let menu = app.buttons["Fijar arriba"].waitForExistence(timeout: 3)
        shot("1-menu")
        XCTAssertTrue(menu, "Mantener pulsado un álbum no abre su menú")
        for item in ["Abrir", "Ordenar", "Fijar arriba", "Eliminar…"] {
            XCTAssertTrue(app.buttons[item].exists, "Al menú de un álbum le falta «\(item)»")
        }
        for item in ["Editar", "Mover a…"] {
            XCTAssertFalse(app.buttons[item].exists, "El menú de un álbum ofrece «\(item)»")
        }
        // Con el menú abierto hay dos «Ordenar»: el de la barra (tapado) y el del menú.
        let sorts = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Ordenar", "lapiz-ordenar"))
        let item = (0..<sorts.count).map { sorts.element(boundBy: $0) }.last { $0.isHittable }
        XCTAssertNotNil(item, "El menú de un álbum no ofrece «Ordenar»")
        item?.tap()
        XCTAssertTrue(app.buttons["Hecho"].waitForExistence(timeout: 5), "«Ordenar» del menú de un álbum no entra en el modo")
        XCTAssertTrue(app.navigationBars["Ordenar"].exists, "El título del modo no es «Ordenar»")
        sleep(1)
        shot("2-ordenando")
        let wiggle = orderLog("orden-temblor")
        note("temblor", wiggle)
        XCTAssertTrue(wiggle.contains("tiemblan=3 bordes=0"), "En «Ordenar» de Tus álbumes no tiemblan los tres; \(wiggle)")
        holdAndDrag(before[0], to: center(before[1]))
        let log = orderLog()
        note("registro", log)
        app.buttons["Hecho"].tap()
        sleep(1)
        let after = reading(albums)
        shot("3-despues")
        note("2-despues", after.joined(separator: "\n"))
        XCTAssertEqual(after.firstIndex(of: before[0]), 1, "Arrastrar «\(before[0])» al sitio de «\(before[1])» no la deja ahí; antes \(before), después \(after); \(log)")
        XCTAssertTrue(log.contains("arrancados=1") && log.contains("fallo=-"), "El arrastre de Tus álbumes no arrancó; \(log)")
    }

    /// Tus álbumes con «Reducir movimiento»: en «Ordenar» nada tiembla y cada portada lleva el borde.
    func testAlbumesSinTemblorConReducirMovimiento() {
        launch("ui_reducir_movimiento")
        openAlbums()
        app.buttons["Más opciones"].tap()
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5), "El ⋯ de Tus álbumes no ofrece «Ordenar»")
        sortButton.tap()
        XCTAssertTrue(app.buttons["Hecho"].waitForExistence(timeout: 5), "«Ordenar» de Tus álbumes no entra en el modo")
        sleep(1)
        shot("1-ordenando")
        let log = orderLog("orden-temblor")
        note("temblor", log)
        XCTAssertTrue(log.contains("tiemblan=0 bordes=3"), "Con «Reducir movimiento» los álbumes tiemblan o no llevan el borde; \(log)")
    }
    // MARK: Prompt 2-0 (segunda tanda): el ⋯ de Tus álbumes, el icono de carpeta y soltar junto a una carpeta

    /// Tus álbumes tiene el mismo ⋯ que Playlists: «Ordenar» y «Ordenar por»; «Nombre (A-Z)» los ordena.
    func testAlbumesConElMismoMenuQuePlaylists() {
        launch("01_biblioteca_cristal")
        openAlbums()
        app.buttons["Más opciones"].tap()
        let sort = app.buttons["Nombre (A-Z)"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5), "El ⋯ de Tus álbumes no ofrece «Nombre (A-Z)»")
        for item in ["Ordenar", "Añadidos recientemente", "Nombre (Z-A)", "Nº de canciones", "A mano"] {
            XCTAssertTrue(app.buttons[item].exists, "Al ⋯ de Tus álbumes le falta «\(item)»")
        }
        shot("1-menu")
        sort.tap()
        sleep(1)
        let now = reading(albums)
        shot("2-a-z")
        XCTAssertEqual(now, albums.sorted(), "«Nombre (A-Z)» no ordena los álbumes por nombre")
    }

    /// Menú de una carpeta › Cambiar icono…: elegir un icono y un color los deja elegidos; «Mosaico» vuelve atrás.
    func testCambiarElIconoDeUnaCarpeta() {
        launch("43_carpetas", ready: "Viajes")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        any("Carpeta Viajes").press(forDuration: 1.2)
        let item = app.buttons["Cambiar icono…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "El menú de una carpeta no ofrece «Cambiar icono…»")
        item.tap()
        XCTAssertTrue(app.navigationBars["Icono de la carpeta"].waitForExistence(timeout: 5), "No se abre «Icono de la carpeta»")
        let color = app.buttons["color-2"]
        XCTAssertFalse(color.isEnabled, "Sin icono, el color tiene que estar apagado")
        app.buttons["icono-airplane"].tap()
        XCTAssertTrue(color.isEnabled, "Con icono, el color tiene que poder elegirse")
        color.tap()
        sleep(1)
        shot("1-elegido")
        XCTAssertTrue(app.buttons["icono-airplane"].isSelected, "El icono elegido no queda marcado")
        XCTAssertTrue(color.isSelected, "El color elegido no queda marcado")
        XCTAssertFalse(app.buttons["icono-mosaico"].isSelected, "«Mosaico» sigue marcado con un icono elegido")
        app.buttons["Listo"].tap()
        sleep(1)
        shot("2-cuadricula")
        XCTAssertTrue(app.navigationBars["Playlists"].exists, "«Listo» no vuelve a Playlists")
    }

    /// Soltar una playlist en el borde de una carpeta (no en su centro) no la mete dentro.
    func testSoltarEnElBordeDeUnaCarpetaNoLaMete() {
        launch("43_carpetas", ready: "Viajes")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        XCTAssertTrue(any("Domingo lento").waitForExistence(timeout: 5))
        startOrdering()
        let edge = any("Carpeta Viajes").coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.3))
        holdAndDrag("Domingo lento", to: edge)
        sleep(1)
        shot("1-soltada")
        let log = orderLog()
        note("registro", log)
        XCTAssertTrue(any("Domingo lento").exists, "Soltar «Domingo lento» en el borde de «Viajes» la ha metido dentro; \(log)")
    }

    // MARK: Prompt 2-0b: carpetas y playlists mezcladas, sacar de una carpeta y el lápiz

    /// Carpetas y playlists se ordenan juntas: «Domingo lento» parada en el borde de «Viajes» se cambia el sitio con
    /// ella (antes las carpetas iban siempre delante) y, tras «Hecho», queda delante de la carpeta.
    func testCarpetasYPlaylistsSeMezclan() {
        launch("43_carpetas", ready: "Viajes")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        let cells = ["Descargadas", "Favoritos", "Carpeta Viajes", "Carpeta Gimnasio", "Domingo lento"]
        XCTAssertTrue(any("Domingo lento").waitForExistence(timeout: 5))
        startOrdering()
        let before = reading(cells)
        note("1-antes", before.joined(separator: "\n"))
        let edge = any("Carpeta Viajes").coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.3))
        holdAndDrag("Domingo lento", to: edge)
        shot("1-soltada")
        let log = orderLog()
        note("registro", log)
        app.buttons["Hecho"].tap()
        sleep(1)
        let after = reading(cells)
        note("2-despues", after.joined(separator: "\n"))
        shot("2-despues")
        guard let dl = after.firstIndex(of: "Domingo lento"), let via = after.firstIndex(of: "Carpeta Viajes") else {
            return XCTFail("Falta alguna portada: \(after)")
        }
        XCTAssertLessThan(dl, via, "«Domingo lento» parada en el borde de «Viajes» no se ha cambiado el sitio con ella; antes \(before), después \(after); \(log)")
        XCTAssertEqual(Set(after), Set(before), "Al ordenar se ha perdido alguna portada")
    }

    /// Playlists › Gimnasio (abierta tocándola, para que debajo esté Playlists) y ⋯ › Ordenar.
    private func openGimnasioOrdering(_ scenario: String) {
        launch(scenario, ready: "Gimnasio")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        any("Carpeta Gimnasio").tap()
        XCTAssertTrue(app.navigationBars["Gimnasio"].waitForExistence(timeout: 5), "No se abrió la carpeta Gimnasio")
        XCTAssertTrue(any("Fuerza").waitForExistence(timeout: 5), "En Gimnasio no está «Fuerza»")
        startOrdering()
    }

    /// Coge «Fuerza», la lleva a la barra de arriba (zona «Sacar de «Gimnasio»») y la deja ahí más de 0,5 s: tiene
    /// que subir a Playlists con la portada aún cogida, seguir en «Ordenar» y, al soltar, quedarse en Playlists.
    private func dragOutOfGimnasio() {
        let top = app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center("Fuerza").press(forDuration: 0.5, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 1.4)
        sleep(1)
        shot("1-soltada-arriba")
        let log = orderLog("orden-sacar") + "; " + orderLog()
        note("registro", log)
        XCTAssertTrue(any("Carpeta Gimnasio").waitForExistence(timeout: 5), "No ha subido a Playlists; \(log)")
        XCTAssertTrue(log.contains("sacadas=1"), "La playlist no ha salido de la carpeta; \(log)")
        XCTAssertTrue(app.buttons["Hecho"].exists, "Arriba tiene que seguir en «Ordenar»")
        XCTAssertTrue(any("Fuerza").exists, "«Fuerza» no está en Playlists; \(log)")
        // Arriba la recogió cogida y siguió con el mismo dedo hasta soltarla (no se soltó sola al cambiar de pantalla).
        XCTAssertTrue(log.contains("arrancados=1") && log.contains("soltados=1"), "Arriba no se recogió la portada cogida; \(log)")
        XCTAssertFalse(log.contains("sin-dedo") || log.contains("dedo-cancelado"), "Al cambiar de pantalla se perdió el dedo; \(log)")
        app.buttons["Hecho"].tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5), "«Hecho» no vuelve a Playlists")
        XCTAssertTrue(any("Fuerza").exists, "Tras «Hecho», «Fuerza» no está en Playlists")
        any("Carpeta Gimnasio").tap()
        XCTAssertTrue(app.navigationBars["Gimnasio"].waitForExistence(timeout: 5))
        sleep(1)
        shot("2-gimnasio")
        XCTAssertFalse(any("Fuerza").exists, "«Fuerza» sigue dentro de Gimnasio")
    }

    /// Sacar una playlist de una carpeta llevándola arriba (prompt 2-0b, punto 2a).
    func testSacarDeUnaCarpetaArrastrandoArriba() {
        openGimnasioOrdering("43_carpetas")
        let log = orderLog("orden-sacar")
        XCTAssertTrue(log.contains("animada=si") && log.contains("sacadas=0"), "Sin «Reducir movimiento» la zona se anima; \(log)")
        dragOutOfGimnasio()
    }

    /// Lo mismo con «Reducir movimiento»: funciona igual y la zona no se anima.
    func testSacarDeUnaCarpetaConReducirMovimiento() {
        openGimnasioOrdering("ui_carpetas_reducir_movimiento")
        let log = orderLog("orden-sacar")
        XCTAssertTrue(log.contains("animada=no"), "Con «Reducir movimiento» la zona «Sacar de …» no tiene que animarse; \(log)")
        dragOutOfGimnasio()
    }

    /// El lápiz (punto 3): un toque entra en «Ordenar» en Playlists, dentro de una carpeta y en Tus álbumes.
    func testElLapizEntraEnOrdenar() {
        launch("43_carpetas", ready: "Viajes")
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 10), "No se abrió Playlists")
        tapPencil("Playlists")
        XCTAssertTrue(app.navigationBars["Ordenar"].exists, "El título del modo no es «Ordenar»")
        shot("1-playlists")
        app.buttons["Hecho"].tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5))
        any("Carpeta Gimnasio").tap()
        XCTAssertTrue(app.navigationBars["Gimnasio"].waitForExistence(timeout: 5), "No se abrió Gimnasio")
        tapPencil("una carpeta")
        shot("2-carpeta")
        app.buttons["Hecho"].tap()
    }

    /// El lápiz de Tus álbumes.
    func testElLapizDeTusAlbumes() {
        launch("01_biblioteca_cristal")
        openAlbums()
        tapPencil("Tus álbumes")
        shot("1-albumes")
    }

    /// El lápiz de Fijados: entra en «Ordenar» de Fijados y, mientras tanto, no queda «Ordenar» de «Tu música».
    func testElLapizDeFijados() {
        launch("01_biblioteca_cristal")
        openPlaylists()
        XCTAssertTrue(any("Noche").waitForExistence(timeout: 5))
        liftAboveBars("Noche")
        any("Noche").press(forDuration: 1.2)
        let pin = app.buttons["Fijar arriba"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3), "El menú de «Noche» no ofrece «Fijar arriba»")
        pin.tap()
        sleep(1)
        back()
        XCTAssertTrue(any("Fijados").waitForExistence(timeout: 5))
        tapPencil("Fijados")
        shot("1-fijados")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Ordenar", "lapiz-ordenar")).count, 0,
                       "Con Fijados ordenándose, «Ordenar» de «Tu música» sigue ahí (dos shu)")
        app.buttons["Hecho"].firstMatch.tap()
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5), "Al terminar no vuelve «Ordenar» de «Tu música»")
    }
}
