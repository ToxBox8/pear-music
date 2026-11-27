import XCTest

/// Tests de interfaz de Ajustes › Cuenta 3.0 (2-C paso 3), en el simulador y sin red (`-screenshotScenario`).
/// Mismo patrón que BibliotecaUITests: capturas en /tmp/jiyu-uitests.
final class CuentaUITests: XCTestCase {
    private var app: XCUIApplication!
    private static let out = URL(fileURLWithPath: "/tmp/jiyu-uitests", isDirectory: true)

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
        app = XCUIApplication()
    }

    private func launch(_ scenario: String, ready: String) {
        app.launchArguments = ["-screenshotScenario", scenario, "-language", "es", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        XCTAssertTrue(any(ready).waitForExistence(timeout: 20), "La pantalla del escenario \(scenario) no llegó a salir")
    }
    private func any(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    private func id(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    /// Baja hasta que salga (el `Form` no crea las filas que no se ven: «Tu clave» es más alta desde la orden 11).
    private func bajarHasta(_ e: XCUIElement) {
        for _ in 0..<6 where !e.exists || !e.isHittable { app.swipeUp() }
    }
    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: Self.out.appendingPathComponent("\(self.name.filter { $0.isLetter || $0.isNumber })-\(name).png"))
    }

    /// Captura con el mismo nombre que la de Android (60_cuenta_menu_dispositivo…), para la hoja de paridad.
    private func captura(_ nombre: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: Self.out.appendingPathComponent("paridad-\(nombre).png"))
    }
    private func titulo(_ t: String) -> XCUIElement { app.navigationBars[t] }
    private func atras() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    /// El gesto atrás del sistema: arrastrar desde el borde izquierdo.
    private func gestoAtras() {
        let borde = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        borde.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
    }
    /// El menú de una fila sale pegado a ella y sin tapar la barra de pestañas (Pulir 2 · menús anclados).
    private func anclado(_ opcion: XCUIElement, a fila: XCUIElement) {
        let o = opcion.frame, f = fila.frame
        XCTAssertLessThan(min(abs(o.minY - f.maxY), abs(f.minY - o.maxY), abs(o.midY - f.midY)), 320,
                          "El menú (\(o)) tiene que salir junto a la fila (\(f))")
        let barra = app.tabBars.firstMatch
        if barra.exists { XCTAssertLessThanOrEqual(o.maxY, barra.frame.minY + 1, "El menú no tapa la barra de abajo") }
    }

    /// §7.2: sin las dos casillas no se crea la cuenta; la de telemetría no hace falta.
    func testCrearCuentaPideLasDosCasillas() {
        launch("57_cuenta_crear", ready: "Tu cuenta, sin contraseña")
        let crear = app.buttons["botonCrear"]
        XCTAssertTrue(crear.waitForExistence(timeout: 5))
        XCTAssertFalse(crear.isEnabled, "Sin casillas, «Crear cuenta» no se puede pulsar")
        id("casillaTerminos").tap()
        XCTAssertFalse(crear.isEnabled, "Sólo con los términos, tampoco")
        id("casillaEdad").tap()
        shot("dos-casillas")
        XCTAssertTrue(crear.isEnabled, "Con las dos (y sin la de telemetría), sí")
    }

    /// §7.3 punto 7: la clave entera se comprueba en el móvil, sin red.
    func testComprobarMiClaveSinRed() {
        launch("61_cuenta_comprobar", ready: "Comprobar mi clave")
        let campo = id("campoClave")
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.tap()
        campo.typeText("0000-0000-0000-0000-0000-0000-00")
        app.buttons["botonComprobar"].tap()
        XCTAssertTrue(any("Esa no es tu clave").waitForExistence(timeout: 5), "Otra clave tiene que decir «Esa no es tu clave»")
        shot("otra")
        campo.tap()
        campo.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        campo.typeText("tn2t d4wt qt75 zfcx h5w9 qqtj 2w") // la buena, en minúsculas y con espacios (§3)
        app.buttons["botonComprobar"].tap()
        XCTAssertTrue(any("Está bien").waitForExistence(timeout: 5), "La buena tiene que decir «Está bien»")
        shot("buena")
    }

    /// §3: se confirma un grupo de 4; si se equivoca, otro grupo al azar (sin llamar al servidor).
    func testConfirmarUnGrupoEquivocado() {
        launch("58_cuenta_tu_clave", ready: "Tu clave de recuperación")
        bajarHasta(app.buttons["botonClave"])
        app.buttons["botonClave"].tap()
        let grupo = id("campoGrupo")
        XCTAssertTrue(grupo.waitForExistence(timeout: 5))
        grupo.tap()
        grupo.typeText("UUUU") // la U no está en el alfabeto: nunca es un grupo
        bajarHasta(app.buttons["botonClave"])
        app.buttons["botonClave"].tap()
        XCTAssertTrue(any("No es ese grupo").waitForExistence(timeout: 5))
        shot("grupo-equivocado")
    }

    /// 2-E (§4.2 paso 10, §4.3): el dispositivo nuevo enseña los 6 emojis con su nombre para VoiceOver, y «No
    /// coinciden» descarta lo recibido sin guardar nada.
    func testQrEmojisYNoCoinciden() {
        launch("64_cuenta_qr_emojis", ready: "¿Ves lo mismo en tu otro dispositivo?")
        let emojis = id("emojisQr")
        XCTAssertTrue(emojis.waitForExistence(timeout: 5))
        // Los índices de los vectores (59, 29, 27, 61, 23, 38) con la tabla PROVISIONAL.
        XCTAssertEqual(emojis.label, "Emojis: coche, zanahoria, piña, dado, manzana, trompeta")
        shot("emojis")
        app.buttons["noCoinciden"].tap()
        XCTAssertTrue(any("No uses este código").waitForExistence(timeout: 5), "«No coinciden» tiene que decir qué hacer")
        shot("no-coinciden")
    }

    /// 2-E: el QR del dispositivo nuevo sale con su cuenta atrás, y el viejo pregunta «¿Añadir…?» con el nombre del QR.
    func testQrNuevoYAnadir() {
        launch("63_cuenta_qr", ready: "Entrar con otro dispositivo")
        XCTAssertTrue(id("imagenQr").waitForExistence(timeout: 5), "Falta el código QR")
        XCTAssertTrue(any("Caduca en 4:32").exists, "Falta la cuenta atrás")
        shot("qr")
        app.terminate()
        launch("65_cuenta_anadir", ready: "¿Añadir \"Pixel de Ana\" a tu cuenta?")
        XCTAssertTrue(app.buttons["anadirMovil"].exists)
        shot("anadir")
    }

    /// Opción A (DECISIONS 100): sin cuenta, «Crear cuenta» se ve sin bajar y va antes que las dos formas de entrar;
    /// «Qué ganas con la cuenta» está plegado y se abre en el sitio. Como `CuentaUiTest` de Android.
    func testSinCuentaCrearCuentaALaVista() {
        launch("56_cuenta_sin_crear", ready: "Tu música en todos tus dispositivos")
        let crear = id("crearCuenta"), entrar = id("entrarDesdeOtro")
        XCTAssertTrue(crear.waitForExistence(timeout: 5))
        XCTAssertTrue(crear.isHittable, "«Crear cuenta» se ve sin bajar")
        XCTAssertTrue(entrar.exists && id("entrarConClave").exists, "Las dos formas de entrar")
        XCTAssertLessThan(crear.frame.minY, entrar.frame.minY, "«Crear cuenta» va antes que «Entrar con otro dispositivo»")
        XCTAssertFalse(any("Tu biblioteca, cifrada en la nube").exists, "«Qué ganas con la cuenta» empieza plegado")
        id("queGanas").tap()
        XCTAssertTrue(any("Tu biblioteca, cifrada en la nube").waitForExistence(timeout: 5), "Al tocarlo se abre en el sitio")
        shot("sin-cuenta-abierto")
    }

    /// Opción A: con cuenta, arriba la sync con «Comprobar ahora», «Tus dispositivos» y «Añadir un dispositivo» sin
    /// bajar, «Lo que se sincroniza» y, plegado, «Seguridad y cuenta». Como `CuentaUiTest` de Android.
    func testConCuentaOrdenDeLaOpcionA() {
        launch("67_cuenta_conectada", ready: "Tus dispositivos")
        let anadir = id("anadirDispositivo")
        XCTAssertTrue(anadir.waitForExistence(timeout: 5))
        XCTAssertTrue(anadir.isHittable, "«Añadir un dispositivo» se ve sin bajar")
        XCTAssertTrue(any("Sincronizado hace 2 min").exists, "PULIR #4: la fila del estado de la sincronización")
        XCTAssertTrue(any("Tu música está igual en tus 2 dispositivos").exists, "Con la sync al día y dos dispositivos")
        XCTAssertTrue(id("comprobarAhora").isHittable, "Pulir 2 #3: «Comprobar ahora» se ve y se puede tocar")
        XCTAssertLessThan(id("estadoSync").frame.minY, anadir.frame.minY, "La sync va arriba")
        XCTAssertFalse(id("nombreCuenta").exists, "«Seguridad y cuenta» empieza plegado")
        shot("con-cuenta")
        bajarHasta(id("seguridadYCuenta")) // con la fila «Pulsos» (3-A) queda bajo el borde y el Form no la crea hasta bajar
        id("seguridadYCuenta").tap()
        bajarHasta(id("borrarCuenta"))
        for fila in ["comprobarMiClave", "nombreCuenta", "quitarLosDemas", "cerrarSesion", "borrarCuenta"] {
            XCTAssertTrue(id(fila).waitForExistence(timeout: 5), "En «Seguridad y cuenta» falta \(fila)")
        }
        XCTAssertLessThan(id("cerrarSesion").frame.minY, id("borrarCuenta").frame.minY, "«Cerrar sesión» va encima de «Borrar cuenta»")
        shot("seguridad-abierto")
    }

    /// Notas de la opción A #3: tocar un dispositivo abre su menú (el de una playlist), pegado a la fila; «Quitar de la
    /// cuenta» pide la confirmación de eliminar y «Cambiar nombre» el aviso con campo. Este dispositivo no se quita
    /// desde aquí (sale con «Cerrar sesión»). Capturas 60, 60b y 60c, en claro y oscuro.
    func testMenuDeUnDispositivo() { menuDeUnDispositivo("67_cuenta_conectada", sufijo: "") }
    func testMenuDeUnDispositivoOscuro() { menuDeUnDispositivo("67_cuenta_conectada_oscuro", sufijo: "_oscuro") }
    private func menuDeUnDispositivo(_ escenario: String, sufijo: String) {
        launch(escenario, ready: "Tus dispositivos")
        let otro = id("disp-1X99P4D412HRCSNX9XJZYP85GR"), este = id("disp-WR85D13CWP6P3DAEZ6QB9H13HR")
        XCTAssertTrue(otro.waitForExistence(timeout: 5))
        otro.tap()
        let quitar = app.buttons["Quitar de la cuenta"]
        XCTAssertTrue(quitar.waitForExistence(timeout: 5), "El menú del otro dispositivo tiene «Quitar de la cuenta»")
        XCTAssertTrue(app.buttons["Cambiar nombre"].exists, "y «Cambiar nombre»")
        anclado(app.buttons["Cambiar nombre"], a: otro)
        captura("60_cuenta_menu_dispositivo\(sufijo)")
        quitar.tap()
        let aviso = app.alerts["¿Quitar «Pixel de Ana»?"]
        XCTAssertTrue(aviso.waitForExistence(timeout: 5), "Quitar pide la confirmación de eliminar")
        XCTAssertTrue(aviso.buttons["Quitar"].exists && aviso.buttons["Cancelar"].exists)
        captura("60b_cuenta_quitar_dispositivo\(sufijo)")
        aviso.buttons["Cancelar"].tap()
        este.tap()
        XCTAssertTrue(app.buttons["Cambiar nombre"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Quitar de la cuenta"].exists, "Este dispositivo no se quita desde su menú")
        app.buttons["Cambiar nombre"].tap()
        let nombre = app.alerts["Cambiar nombre"]
        XCTAssertTrue(nombre.waitForExistence(timeout: 5), "Cambiar nombre abre el aviso con campo")
        XCTAssertEqual(nombre.textFields.firstMatch.value as? String, "iPhone 16", "con el nombre de ahora escrito")
        if sufijo.isEmpty { captura("60c_cuenta_cambiar_nombre") }
        nombre.buttons["Cancelar"].tap()
    }

    /// Notas de la opción A #1: la flecha y el gesto atrás vuelven a Cuenta, no a Ajustes. Como `NavegacionCuentaTest`.
    func testAtrasVuelveACuenta() {
        launch("67_cuenta_conectada", ready: "Tus dispositivos")
        id("anadirDispositivo").tap()
        XCTAssertTrue(titulo("Añadir un dispositivo").waitForExistence(timeout: 5), "Tiene que abrir «Añadir un dispositivo»")
        atras()
        XCTAssertTrue(titulo("Cuenta").waitForExistence(timeout: 5), "La flecha vuelve a Cuenta")
        id("loQueSeSincroniza").tap()
        XCTAssertTrue(titulo("Lo que se sincroniza").waitForExistence(timeout: 5))
        gestoAtras()
        XCTAssertTrue(titulo("Cuenta").waitForExistence(timeout: 5), "El gesto atrás vuelve a Cuenta")
        bajarHasta(id("seguridadYCuenta")) // con la fila «Pulsos» (3-A) queda bajo el borde y el Form no la crea hasta bajar
        id("seguridadYCuenta").tap()
        bajarHasta(id("cerrarSesion"))
        id("cerrarSesion").tap()
        XCTAssertTrue(titulo("Cerrar sesión").waitForExistence(timeout: 5), "El título es la fila que la abre")
        atras()
        XCTAssertTrue(titulo("Cuenta").waitForExistence(timeout: 5))
    }

    /// Pulsos (3-A): con cuenta, la fila de Cuenta dice el saldo, la pantalla lo enseña (y a VoiceOver) y el gesto
    /// atrás vuelve a Cuenta. Como `NavegacionCuentaTest` de Android.
    func testPulsosConCuenta() {
        launch("67_cuenta_conectada", ready: "Tus dispositivos")
        let fila = id("filaPulsos")
        bajarHasta(fila)
        XCTAssertTrue(fila.waitForExistence(timeout: 5), "Cuenta tiene la fila «Pulsos»")
        XCTAssertTrue(any("1.250").exists, "La fila dice el saldo")
        fila.tap()
        XCTAssertTrue(titulo("Pulsos").waitForExistence(timeout: 5), "Abre «Pulsos» con su título")
        let saldo = id("saldoPulsos")
        XCTAssertTrue(saldo.waitForExistence(timeout: 5))
        XCTAssertEqual(saldo.label, "1.250 pulsos", "El saldo, para VoiceOver")
        XCTAssertTrue(any("Aún no tienes pulsos").exists, "Sin movimientos, lo dice")
        shot("pulsos-desde-cuenta")
        gestoAtras()
        XCTAssertTrue(titulo("Cuenta").waitForExistence(timeout: 5), "El gesto atrás vuelve a Cuenta")
    }

    /// Pulsos (3-A): el historial con su texto por motivo, el signo de cada cantidad y «Qué son los pulsos».
    func testPulsosHistorial() {
        launch("72_pulsos", ready: "Movimientos")
        for t in ["Código de fundador", "Encuesta respondida", "Gastados en la tienda", "+500", "\u{2212}300"] {
            XCTAssertTrue(any(t).exists, "En el historial falta «\(t)»")
        }
        bajarHasta(any("Son tuyos"))
        XCTAssertTrue(any("Se ganan, nunca se compran").exists && any("Son tuyos").exists, "«Qué son los pulsos», entero")
        shot("pulsos-historial")
    }

    /// Pulsos (3-A): sin cuenta, explica qué son y «Crear cuenta» la sustituye (atrás vuelve a Cuenta, no a Pulsos).
    func testPulsosSinCuentaOfreceCrearla() {
        launch("56_cuenta_sin_crear", ready: "Tu música en todos tus dispositivos")
        let fila = id("filaPulsos")
        bajarHasta(fila)
        fila.tap()
        XCTAssertTrue(titulo("Pulsos").waitForExistence(timeout: 5), "Abre «Pulsos»")
        XCTAssertTrue(any("Los pulsos van con tu cuenta").exists, "Explica que van con la cuenta")
        id("crearCuentaPulsos").tap()
        XCTAssertTrue(titulo("Crear cuenta").waitForExistence(timeout: 5), "«Crear cuenta» sustituye a Pulsos")
        atras()
        XCTAssertTrue(titulo("Cuenta").waitForExistence(timeout: 5), "Atrás vuelve a Cuenta")
        XCTAssertFalse(titulo("Pulsos").exists)
    }

    /// Notas de la opción A #2: «Tu clave de recuperación» sustituye a «Crear cuenta»: atrás vuelve a Cuenta.
    func testTuClaveSustituyeACrearCuenta() {
        launch("56_cuenta_sin_crear", ready: "Tu música en todos tus dispositivos")
        id("crearCuenta").tap()
        XCTAssertTrue(titulo("Crear cuenta").waitForExistence(timeout: 5))
        id("casillaTerminos").tap(); id("casillaEdad").tap()
        app.buttons["botonCrear"].tap()
        XCTAssertTrue(titulo("Tu clave de recuperación").waitForExistence(timeout: 5), "Tiene que abrir «Tu clave de recuperación»")
        atras()
        XCTAssertTrue(titulo("Cuenta").waitForExistence(timeout: 5), "Atrás vuelve a Cuenta, no a «Crear cuenta»")
        XCTAssertFalse(titulo("Crear cuenta").exists)
    }

    /// Notas de la opción A #4: «Cerrar sesión» pide confirmación, saca este dispositivo de la cuenta y vuelve a Cuenta
    /// sin cuenta, con el aviso de que la biblioteca sigue aquí. Siendo el único, el aviso grande (70b).
    func testCerrarSesion() {
        launch("67b_cuenta_seguridad", ready: "Seguridad y cuenta")
        bajarHasta(id("cerrarSesion"))
        id("cerrarSesion").tap()
        XCTAssertTrue(titulo("Cerrar sesión").waitForExistence(timeout: 5))
        XCTAssertFalse(id("avisoUnico").exists, "Con otro dispositivo en la cuenta no sale el aviso grande")
        app.buttons["botonCerrarSesion"].tap()
        let aviso = app.alerts["¿Cerrar sesión en este dispositivo?"]
        XCTAssertTrue(aviso.waitForExistence(timeout: 5), "Pide confirmación")
        aviso.buttons["Cerrar sesión"].tap()
        XCTAssertTrue(any("Tu música en todos tus dispositivos").waitForExistence(timeout: 10), "Vuelve a Cuenta, ya sin cuenta")
        XCTAssertTrue(titulo("Cuenta").exists)
        XCTAssertTrue(any("Has cerrado sesión").exists, "Dice que la biblioteca sigue aquí")
        shot("sesion-cerrada")
        app.terminate()
        launch("70b_cuenta_cerrar_sesion_unico", ready: "Cerrar sesión en este dispositivo")
        XCTAssertTrue(id("avisoUnico").waitForExistence(timeout: 5), "Siendo el único, el aviso grande")
        XCTAssertTrue(any("Es tu único dispositivo").exists)
    }

    /// Orden 11: la clave en 7 grupos numerados; al confirmar se dice qué es un grupo y cuál se pide (como Android).
    func testLaClaveExplicaQueEsUnGrupo() {
        launch("58_cuenta_tu_clave", ready: "Tu clave de recuperación")
        XCTAssertTrue(any("Lo redondo es siempre un cero").waitForExistence(timeout: 5))
        XCTAssertTrue(any("Grupo 1:").exists, "Cada grupo con su número para VoiceOver")
        bajarHasta(app.buttons["botonClave"])
        app.buttons["botonClave"].tap()
        XCTAssertTrue(any("Un grupo son los 4 caracteres").waitForExistence(timeout: 5))
        shot("grupo-marcado")
    }

    /// PULIR #5 y notas de la opción A #3: el menú de una fila (pegado a ella) con «No sincronizar esto», que la deja
    /// sólo aquí, y «Quitar de todos mis dispositivos», que pide la confirmación de eliminar. Capturas 68b y 68c.
    func testLoQueSeSincronizaDosOpciones() { loQueSeSincroniza("68_cuenta_sincronizado", sufijo: "") }
    func testLoQueSeSincronizaDosOpcionesOscuro() { loQueSeSincroniza("68_cuenta_sincronizado_oscuro", sufijo: "_oscuro") }
    private func loQueSeSincroniza(_ escenario: String, sufijo: String) {
        launch(escenario, ready: "Lo que se sincroniza")
        let fila = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sinc-playlist:'")).firstMatch
        XCTAssertTrue(fila.waitForExistence(timeout: 5), "Tiene que haber alguna playlist")
        fila.tap()
        // Con su explicación de subtítulo, la etiqueta del botón empieza por el título.
        let no = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "No sincronizar esto")).firstMatch
        XCTAssertTrue(no.waitForExistence(timeout: 5))
        anclado(no, a: fila)
        captura("68b_cuenta_sincronizado_menu\(sufijo)")
        no.tap()
        XCTAssertTrue(any("Sólo en este dispositivo").waitForExistence(timeout: 5), "Tiene que decir «Sólo en este dispositivo»")
        shot("solo-aqui")
        fila.tap()
        app.buttons["Quitar de todos mis dispositivos"].tap()
        XCTAssertTrue(any("de todos tus dispositivos?").waitForExistence(timeout: 5), "Tiene que pedir confirmación")
        captura("68c_cuenta_quitar_de_todos\(sufijo)")
        app.alerts.firstMatch.buttons["Cancelar"].tap()
    }
}
