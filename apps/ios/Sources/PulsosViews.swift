import SwiftUI

// Ajustes › Cuenta › «Pulsos» (bloque 3, 3-A; docs/spec/puntos.md §7). Igual que `PulsosPantalla` de Android
// (ui/PulsosScreen.kt): mismos textos, mismo orden y el mismo shu. Sin mascota hasta el 3-C. Con cuenta no hay shu
// relleno (aún no hay nada que hacer con los pulsos: la tienda es la 3.1); sin cuenta, «Crear cuenta» (docs/COLOR.md).

/// El símbolo de los pulsos: el del logo (MARCA/logo/simbolo-*.svg), con sus DOS arcos concéntricos y la barra, en el
/// color de `foregroundStyle`. Nunca con un solo arco. Los arcos se dibujan punto a punto con las mismas medidas que el
/// SVG (`M12,13 a11,11 0,1 0,16 0 M16,16.078 a6,6 0,1 0,8 0 M20,9 v12`, trazo 2,5 y extremos redondos), sin depender de
/// hacia dónde gira `addArc`. Igual que `drawable/ic_pulso.xml` en Android.
struct SimboloPulsos: View {
    /// Ancho; el alto sale de la proporción del SVG (24,5 × 25,05 con el trazo).
    let lado: CGFloat
    var body: some View {
        let e = lado / 24.5
        Path { p in
            let centro = CGPoint(x: 20, y: 13 + 57.0.squareRoot()) // el de los dos arcos: (20; 20,55)
            for (radio, desde, hasta) in [(11.0, 223.34, -43.34), (6.0, 228.19, -48.19)] {
                let pasos = 96
                for i in 0...pasos {
                    let a = (desde + (hasta - desde) * Double(i) / Double(pasos)) * .pi / 180
                    let punto = CGPoint(x: (centro.x + radio * cos(a) - 7.75) * e, y: (centro.y + radio * sin(a) - 7.75) * e)
                    if i == 0 { p.move(to: punto) } else { p.addLine(to: punto) }
                }
            }
            p.move(to: CGPoint(x: (20 - 7.75) * e, y: (9 - 7.75) * e))
            p.addLine(to: CGPoint(x: (20 - 7.75) * e, y: (21 - 7.75) * e))
        }
        .stroke(style: StrokeStyle(lineWidth: 2.5 * e, lineCap: .round, lineJoin: .round))
        .frame(width: lado, height: lado * 25.05 / 24.5)
    }
}

/// Lo que enseña la pantalla: el saldo y el historial, sólo en memoria (no hace falta sin red). Igual que `Pulsos` en Android.
@MainActor
final class PulsosEstado: ObservableObject {
    static let shared = PulsosEstado()

    struct Vista: Equatable {
        /// nil = aún no se sabe (nunca se ha cargado).
        var saldo: Int64? = nil
        var movimientos: [PulsosModel.Movimiento] = []
        var siguiente: String? = nil
        var cargando = false
        /// El código de la última carga que falló (los textos, los de la cuenta: `CuentaErrores.mensaje`).
        var error: String? = nil
        /// Lo que tiene la cuenta (3-B): el marco Fundador, si canjeó el código.
        var expansiones: [String] = []
        var fundador: Bool { expansiones.contains(PulsosModel.marcoFundador) }
    }
    @Published private(set) var vista = Vista()
    private var dePrueba = false

    /// Sólo capturas y tests: una vista fija que no se pide a la red. nil lo deja como al abrir la app.
    func vistaDePrueba(_ v: Vista?) { dePrueba = v != nil; vista = v ?? Vista() }
    static let ejemplo = Vista(saldo: 1250, movimientos: [
        .init(id: "M4", cantidad: 250, motivo: "encuesta", ref: "enc-2", saldoTras: 1250, ts: 1795700000),
        .init(id: "M3", cantidad: -300, motivo: "gasto", ref: "marco-neon", saldoTras: 1000, ts: 1795500000),
        .init(id: "M2", cantidad: 800, motivo: "encuesta", ref: "enc-1", saldoTras: 1300, ts: 1795100000),
        .init(id: "M1", cantidad: 500, motivo: "fundador", ref: nil, saldoTras: 500, ts: 1794900000),
    ], expansiones: [PulsosModel.marcoFundador]) // 3-B: con el código canjeado, «Lo que tienes» dice el marco
    static let canjeEjemplo = PulsosModel.Canje(pulsos: 500, expansion: PulsosModel.marcoFundador,
        movimiento: .init(id: "M1", cantidad: 500, motivo: "fundador", ref: "fundador", saldoTras: 500, ts: 1795700000), saldo: 500)

    /// La primera página (al abrir «Pulsos» y con «Probar otra vez»). Si falla, se queda lo último bueno y el error.
    func cargar() async { await pedir(nil) }
    /// «Ver más»: la página siguiente, debajo de lo que ya hay.
    func masAntiguos() async { if let s = vista.siguiente { await pedir(s) } }
    /// Al salir de la cuenta (cerrar sesión, borrarla o quitar este dispositivo).
    func olvidar() { vista = Vista() }

    /// Canjea un código ya leído con `PulsosModel.leerCodigo`. Si va bien, el saldo, el movimiento y el marco entran
    /// en la vista sin volver a pedir nada (el saldo sube al momento). Lanza `CuentaPear.ErrorCuenta`.
    func canjear(_ c20: String) async throws -> PulsosModel.Canje {
        let datos = try await CuentaPear.shared.canjearCodigo(c20)
        guard let canje = PulsosModel.leerCanje(datos) else { throw CuentaPear.ErrorCuenta(codigo: "error_interno") }
        aplicar(canje)
        return canje
    }
    func aplicar(_ canje: PulsosModel.Canje) {
        vista.saldo = canje.saldo
        vista.movimientos = [canje.movimiento] + vista.movimientos.filter { $0.id != canje.movimiento.id }
        if let e = canje.expansion, !vista.expansiones.contains(e) { vista.expansiones = (vista.expansiones + [e]).sorted() }
        vista.error = nil
    }

    private func pedir(_ cursor: String?) async {
        guard !vista.cargando, !dePrueba else { return }
        vista.cargando = true; vista.error = nil
        do {
            let datos = try await CuentaPear.shared.pedirPulsos(cursor)
            guard !dePrueba else { return }
            guard let p = PulsosModel.leer(datos) else { vista.cargando = false; vista.error = "error_interno"; return }
            if cursor == nil {
                vista = Vista(saldo: p.saldo, movimientos: p.movimientos, siguiente: p.siguiente, expansiones: p.expansiones)
            } else {
                var vistos = Set(vista.movimientos.map(\.id))
                vista.movimientos += p.movimientos.filter { vistos.insert($0.id).inserted }
                vista.saldo = p.saldo; vista.siguiente = p.siguiente; vista.cargando = false
            }
        } catch {
            guard !dePrueba else { return }
            vista.cargando = false
            vista.error = (error as? CuentaPear.ErrorCuenta)?.codigo ?? "error_local"
        }
    }

    /// Un entero con los miles agrupados con el separador del idioma de la app («1.250», «1,250»…), también con 4
    /// cifras: `NumberFormatter` en castellano no agrupa «1250» y Android sí, así que se agrupa a mano en las dos.
    nonisolated static func cifra(_ n: Int64) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: I18n.current == "va" ? "ca" : I18n.current)
        return PulsosModel.agrupar(n, separador: f.groupingSeparator ?? ".")
    }
    /// «+500» o «−300» (con el signo menos de verdad, no un guion).
    nonisolated static func cifraConSigno(_ n: Int64) -> String { (n > 0 ? "+" : "\u{2212}") + cifra(abs(n)) }

    /// Qué fue cada movimiento, por su `motivo` (puntos.md §2). Uno que esta versión no conoce llega ya como «ajuste».
    nonisolated static func texto(_ motivo: String) -> String {
        switch motivo {
        case "fundador": return L("Código de fundador")
        case "encuesta": return L("Encuesta respondida")
        case "gasto": return L("Gastados en la tienda")
        default: return L("Ajuste de Jiyu Pulse")
        }
    }
}

struct PulsosView: View {
    @ObservedObject private var cuenta = CuentaPear.shared
    var body: some View {
        Form {
            if cuenta.tieneCuenta { PulsosConCuenta() } else { PulsosSinCuenta() }
            QueSonLosPulsos()
        }
        .navigationTitle(L("Pulsos"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

private struct PulsosConCuenta: View {
    @ObservedObject private var pulsos = PulsosEstado.shared
    @Environment(\.navCuenta) private var nav
    @ScaledMetric(relativeTo: .largeTitle) private var simbolo: CGFloat = 44

    private var v: PulsosEstado.Vista { pulsos.vista }
    private var etiqueta: String {
        switch v.saldo {
        case nil: return L("Cargando tu saldo")
        case 1: return L("1 pulso")
        case let s?: return L("{0} pulsos", PulsosEstado.cifra(s))
        }
    }

    var body: some View {
        // El saldo: el símbolo y la cifra, grandes, en una línea; debajo, «pulsos». Sin tarjeta: es lo que es la pantalla.
        Section {
            VStack(spacing: 2) {
                HStack(spacing: 14) {
                    SimboloPulsos(lado: simbolo).foregroundStyle(.tint)
                    if v.saldo == nil && v.cargando {
                        ProgressView().controlSize(.large)
                    } else {
                        Text(v.saldo.map(PulsosEstado.cifra) ?? "\u{2013}")
                            .displayTitle(Tokens.TypeSize.displayBalance).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                Text(v.saldo == 1 ? L("pulso") : L("pulsos")).font(.headline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(etiqueta)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("saldoPulsos")
        }
        if let codigo = v.error {
            Section {
                Estado(ok: false, texto: CuentaErrores.mensaje(codigo))
                Button { Task { await pulsos.cargar() } } label: { Label(L("Probar otra vez"), systemImage: "arrow.clockwise") }
            }
        }
        // Lo que tienes (3-B): el marco Fundador, si canjeaste el código; si no, la fila para canjearlo. El dibujo del
        // marco y lucirlo en el perfil llegan en la 3.1. Sin shu: son filas de texto.
        if v.fundador {
            Section {
                Fila(titulo: L("Marco Fundador"), subtitulo: L("Lo lucirás en tu perfil cuando llegue."), icono: "rosette")
            } header: { Text(L("Lo que tienes")) }
        } else if v.saldo != nil {
            Section {
                Button { nav.ir(.codigo) } label: {
                    Fila(titulo: L("Tengo un código"), subtitulo: L("Canjea tu código de fundador"), icono: "gift", flecha: true)
                }
                .accessibilityIdentifier("filaTengoCodigo")
            }
        }
        // El historial: qué fue, cuándo y cuánto.
        Section {
            if v.movimientos.isEmpty {
                if v.saldo != nil {
                    Fila(titulo: L("Aún no tienes pulsos"), subtitulo: L("Cuando canjees un código o respondas una encuesta, lo verás aquí."))
                } else {
                    Fila(titulo: v.cargando ? L("Cargando…") : L("No se ha podido cargar"))
                }
            } else {
                ForEach(v.movimientos) { m in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PulsosEstado.texto(m.motivo))
                            Text(fecha(m.ts)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(PulsosEstado.cifraConSigno(m.cantidad)).monospacedDigit()
                            .foregroundStyle(m.cantidad > 0 ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel))
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
                if v.siguiente != nil {
                    Button(v.cargando ? L("Cargando…") : L("Ver más")) { Task { await pulsos.masAntiguos() } }
                        .disabled(v.cargando)
                }
            }
        } header: { Text(L("Movimientos")) }
        .task { await pulsos.cargar() }
    }

    /// Fecha en el idioma de la app, como «Visto 17 nov 2025» de los dispositivos.
    private func fecha(_ ts: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: I18n.current == "va" ? "ca" : I18n.current)))
    }
}

private struct PulsosSinCuenta: View {
    @Environment(\.navCuenta) private var nav
    var body: some View {
        Section {
            VStack(spacing: 8) {
                SimboloPulsos(lado: 52).foregroundStyle(.tint).padding(.bottom, 4).accessibilityHidden(true)
                Text(L("Los pulsos van con tu cuenta")).font(.title3.bold()).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(L("Créala gratis, sin contraseña, y empieza a ganarlos.")).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .listRowSeparator(.hidden)
            // Sin cuenta, «Crear cuenta» sustituye a Pulsos: atrás vuelve a Cuenta (dos niveles como mucho).
            Button(L("Crear cuenta")) { nav.cambiar(.crear) }
                .buttonStyle(PillButtonStyle(prominent: true))
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 14, trailing: 16))
                .accessibilityIdentifier("crearCuentaPulsos")
        }
    }
}

/// Qué son los pulsos, con la voz del brandbook (pág. 19): se ganan, nunca se compran, y no gastar no pasa nada.
private struct QueSonLosPulsos: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                punto("checklist", 5, L("Se ganan, nunca se compran"),
                      L("Respondiendo encuestas, una vez cada una, y con códigos como el de fundador. No se pueden comprar ni cambiar por dinero."))
                punto("paintpalette.fill", 2, L("Para personalizar Jiyu Pulse"),
                      L("Marcos, temas y más, en una tienda que llega pronto. Gastarlos es darle de comer a la mascota: le encantan."))
                punto("heart.fill", 0, L("Sin prisa"),
                      L("Si no los gastas, no pasa nada: te esperan. La mascota nunca tiene hambre por tu culpa."))
                punto("lock.fill", 4, L("Son tuyos"), L("Van con tu cuenta y no se pueden pasar a otra."))
            }
            .padding(.bottom, 8)
        } header: { Text(L("Qué son los pulsos")) }
    }

    private func punto(_ icon: String, _ palette: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GradientIcon(systemName: icon, palette: palette, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Ajustes › Cuenta › Pulsos › «Tengo un código» (3-B; puntos.md §6.3 y §7). Una casilla que acepta el código con o
/// sin guiones y en minúsculas; «Canjear» (el único shu) sólo se enciende cuando el código cuadra con su control, y si
/// hay 20 caracteres que no cuadran lo dice sin preguntar a nadie. Al canjear, la pantalla pasa a «+500 pulsos» y el
/// marco, con «Hecho» (el shu de ese estado). Sin mascota hasta el 3-C. Igual que `CodigoPantalla` de Android.
struct CodigoView: View {
    /// Sólo capturas: lo escrito al abrir y la pantalla ya canjeada.
    var textoInicial = ""
    var canjeInicial: PulsosModel.Canje? = nil
    @State private var texto = ""
    @State private var error: String?
    @State private var canjeando = false
    @State private var hecho: PulsosModel.Canje?
    @State private var listo = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let canje = hecho { CodigoCanjeado(canje: canje) { dismiss() } } else { pedir }
        }
        .navigationTitle(L("Tengo un código")).navigationBarTitleDisplayMode(.inline)
        .themed()
        .onAppear { if !listo { texto = textoInicial; hecho = canjeInicial; listo = true } }
    }

    private var escrito: PulsosModel.Escrito { PulsosModel.escrito(texto) }

    @ViewBuilder private var pedir: some View {
        Section {
            VStack(spacing: 8) {
                SimboloPulsos(lado: 52).foregroundStyle(.tint).padding(.bottom, 4).accessibilityHidden(true)
                Text(L("Tu código de fundador")).font(.title2).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                Text(L("Te lo damos por Instagram al mandarnos la palabra del canal de WhatsApp. Vale una vez por cuenta: 500 pulsos y el marco Fundador."))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity).padding(.top, 8).listRowBackground(Color.clear)
        }
        Section {
            TextField("XXXX-XXXX-XXXX-XXXX-XXXX", text: $texto) // i18n: no
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .accessibilityLabel(L("Tu código de fundador"))
                .accessibilityIdentifier("campoCodigo")
                .submitLabel(.go)
                .onSubmit { if escrito == .bien && !canjeando { canjear() } } // Intro canjea: el teclado tapa el botón
                .onChange(of: texto) { t in error = nil; if t.count > 40 { texto = String(t.prefix(40)) } }
        } footer: { Text(L("Da igual mayúsculas, espacios o guiones.")) }
        if let aviso = error ?? (escrito == .malEscrito ? CuentaErrores.mensaje("codigo_mal_escrito") : nil) {
            Section { Estado(ok: false, texto: aviso).accessibilityIdentifier("errorCodigo") }
        }
        Section {
            Button(canjeando ? L("Canjeando…") : L("Canjear")) { canjear() }
                .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                .disabled(canjeando || escrito != .bien)
                .accessibilityIdentifier("botonCanjear")
        }
    }

    private func canjear() {
        guard let c20 = PulsosModel.leerCodigo(texto) else { return }
        canjeando = true
        Task {
            defer { canjeando = false }
            do { hecho = try await PulsosEstado.shared.canjear(c20) }
            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
        }
    }
}

private struct CodigoCanjeado: View {
    let canje: PulsosModel.Canje
    let hecho: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var simbolo: CGFloat = 44
    var body: some View {
        Section {
            VStack(spacing: 2) {
                HStack(spacing: 14) {
                    SimboloPulsos(lado: simbolo).foregroundStyle(.tint)
                    Text(PulsosEstado.cifraConSigno(canje.pulsos)).displayTitle(Tokens.TypeSize.displayBalance).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("{0} pulsos más", PulsosEstado.cifra(canje.pulsos)))
                .accessibilityAddTraits(.isHeader)
                Text(L("pulsos")).font(.headline).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(L("¡Ya eres fundador!")).font(.title3.bold()).multilineTextAlignment(.center).padding(.top, 14)
                Text(L("Ahora tienes {0} pulsos. Gracias por estar desde el principio.", PulsosEstado.cifra(canje.saldo)))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity).padding(.top, 12).listRowBackground(Color.clear)
            .accessibilityIdentifier("codigoCanjeado")
        }
        if canje.expansion == PulsosModel.marcoFundador {
            Section { Fila(titulo: L("Marco Fundador"), subtitulo: L("Lo lucirás en tu perfil cuando llegue."), icono: "rosette") }
        }
        Section {
            Button(L("Hecho"), action: hecho)
                .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                .accessibilityIdentifier("botonHechoCodigo")
        }
    }
}
