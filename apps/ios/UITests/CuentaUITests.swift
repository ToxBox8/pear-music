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
    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: Self.out.appendingPathComponent("\(self.name.filter { $0.isLetter || $0.isNumber })-\(name).png"))
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
        app.buttons["botonClave"].tap()
        let grupo = id("campoGrupo")
        XCTAssertTrue(grupo.waitForExistence(timeout: 5))
        grupo.tap()
        grupo.typeText("UUUU") // la U no está en el alfabeto: nunca es un grupo
        app.buttons["botonClave"].tap()
        XCTAssertTrue(any("No es ese grupo").waitForExistence(timeout: 5))
        shot("grupo-equivocado")
    }

    /// 2-E (§4.2 paso 10, §4.3): el móvil nuevo enseña los 6 emojis con su nombre para VoiceOver, y «No coinciden»
    /// descarta lo recibido sin guardar nada.
    func testQrEmojisYNoCoinciden() {
        launch("64_cuenta_qr_emojis", ready: "¿Ves lo mismo en tu otro móvil?")
        let emojis = id("emojisQr")
        XCTAssertTrue(emojis.waitForExistence(timeout: 5))
        // Los índices de los vectores (59, 29, 27, 61, 23, 38) con la tabla PROVISIONAL.
        XCTAssertEqual(emojis.label, "Emojis: coche, zanahoria, piña, dado, manzana, trompeta")
        shot("emojis")
        app.buttons["noCoinciden"].tap()
        XCTAssertTrue(any("No uses este código").waitForExistence(timeout: 5), "«No coinciden» tiene que decir qué hacer")
        shot("no-coinciden")
    }

    /// 2-E: el QR del móvil nuevo sale con su cuenta atrás, y el viejo pregunta «¿Añadir…?» con el nombre del QR.
    func testQrNuevoYAnadir() {
        launch("63_cuenta_qr", ready: "Entrar desde otro móvil")
        XCTAssertTrue(id("imagenQr").waitForExistence(timeout: 5), "Falta el código QR")
        XCTAssertTrue(any("Caduca en 4:32").exists, "Falta la cuenta atrás")
        shot("qr")
        app.terminate()
        launch("65_cuenta_anadir", ready: "¿Añadir \"Pixel de Ana\" a tu cuenta?")
        XCTAssertTrue(app.buttons["anadirMovil"].exists)
        shot("anadir")
    }
}
