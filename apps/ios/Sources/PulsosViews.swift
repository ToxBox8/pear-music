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
    ])

    /// La primera página (al abrir «Pulsos» y con «Probar otra vez»). Si falla, se queda lo último bueno y el error.
    func cargar() async { await pedir(nil) }
    /// «Ver más»: la página siguiente, debajo de lo que ya hay.
    func masAntiguos() async { if let s = vista.siguiente { await pedir(s) } }
    /// Al salir de la cuenta (cerrar sesión, borrarla o quitar este dispositivo).
    func olvidar() { vista = Vista() }

    private func pedir(_ cursor: String?) async {
        guard !vista.cargando, !dePrueba else { return }
        vista.cargando = true; vista.error = nil
        do {
            let datos = try await CuentaPear.shared.pedirPulsos(cursor)
            guard !dePrueba else { return }
            guard let p = PulsosModel.leer(datos) else { vista.cargando = false; vista.error = "error_interno"; return }
            if cursor == nil {
                vista = Vista(saldo: p.saldo, movimientos: p.movimientos, siguiente: p.siguiente)
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

    /// Un entero en el idioma de la app («1.250», «1,250»…).
    nonisolated static func cifra(_ n: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: I18n.current == "va" ? "ca" : I18n.current)
        return f.string(from: NSNumber(value: n)) ?? String(n)
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
