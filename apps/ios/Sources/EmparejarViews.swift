import AVFoundation
import SwiftUI

// MARK: - Móvil nuevo por QR (2-E; docs/spec/cuenta.md §4.2 y §4.3)
// El nuevo (N) enseña el QR y espera; el viejo (V) lo escanea desde Dispositivos › Añadir un móvil, confirma «¿Añadir…?»
// con presencia y los dos enseñan los mismos 6 emojis. Una pose de la mascota por pantalla y un solo shu (docs/COLOR.md).
// Las poses y los textos son PROVISIONAL (los revisa Toxbox con las capturas 63–65). Igual que EmparejarScreens.kt.

/// Los nombres de los 64 emojis para VoiceOver, en el idioma de la app (la tabla está en `CuentaCripto.tablaEmojis` y en
/// `shared/spec/emojis-qr.json`; PROVISIONAL).
enum EmojisQr {
    static var nombres: [String] {
        [
            L("elefante"), L("jirafa"), L("tortuga"), L("pulpo"), L("mariposa"), L("abeja"), L("pingüino"), L("cangrejo"),
            L("caracol"), L("ballena"), L("búho"), L("serpiente"), L("unicornio"), L("cactus"), L("girasol"), L("seta"),
            L("trébol"), L("arcoíris"), L("muñeco de nieve"), L("rayo"), L("fuego"), L("mundo"), L("estrella"), L("manzana"),
            L("plátano"), L("uvas"), L("sandía"), L("piña"), L("cerezas"), L("zanahoria"), L("maíz"), L("pizza"),
            L("dónut"), L("queso"), L("helado"), L("café"), L("calabaza"), L("guitarra"), L("trompeta"), L("tambor"),
            L("linterna"), L("regalo"), L("llave"), L("campana"), L("bombilla"), L("despertador"), L("cámara"), L("paraguas"),
            L("ancla"), L("martillo"), L("libros"), L("sombrero de copa"), L("gafas"), L("corona"), L("diamante"), L("calcetines"),
            L("bicicleta"), L("cohete"), L("velero"), L("coche"), L("casa"), L("dado"), L("balón"), L("diana"),
        ]
    }
    static func nombre(_ i: Int) -> String { nombres.indices.contains(i) ? nombres[i] : "" }
}

/// Los 6 emojis de comprobación, en dos filas de 3, con su nombre debajo (para leerlos en voz alta si hace falta).
struct EmojisComprobacion: View {
    let indices: [Int]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
            ForEach(Array(indices.enumerated()), id: \.offset) { _, i in
                VStack(spacing: 4) {
                    Text(CuentaCripto.tablaEmojis[i]).font(.system(size: 44))
                    Text(EmojisQr.nombre(i)).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 84)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Emojis: {0}", indices.map(EmojisQr.nombre).joined(separator: ", ")))
        .accessibilityIdentifier("emojisQr")
    }
}

/// Un QR legible: módulos negros sobre blanco con su margen, en claro y en oscuro (los lectores no leen el invertido).
private struct ImagenQr: View {
    let texto: String
    var body: some View {
        Group {
            if let img = QRCode.image(texto) {
                Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
            } else { Color.clear }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(L("Código QR para añadir este móvil"))
        .accessibilityIdentifier("imagenQr")
    }
}

private struct CabeceraQr: View {
    let pose: String, titulo: String, texto: String
    var body: some View {
        VStack(spacing: 10) {
            Image("mascota-\(pose)").resizable().scaledToFit().frame(height: 120).frame(maxWidth: .infinity).accessibilityHidden(true)
            Text(titulo).font(.title2.bold()).multilineTextAlignment(.center)
            Text(texto).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }
}

private struct AvisoQr: View {
    let texto: String
    var body: some View {
        Label { Text(texto) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            .font(.subheadline)
            .accessibilityIdentifier("errorQr")
    }
}

private func mensaje(_ e: Error) -> String {
    CuentaPear.mensajeDe(e)
}

// MARK: Móvil nuevo: «Entrar desde otro móvil»

struct QrNuevoView: View {
    /// Sólo capturas (`-screenshotScenario`): el QR o los emojis de los vectores, sin red ni claves.
    enum Prueba { case qr, emojis }
    var prueba: Prueba? = nil

    private enum Paso: Equatable { case cargando, qr, comparar, noCoinciden, error(String) }
    @State private var paso: Paso = .cargando
    @State private var sesion: CuentaPear.QrNuevo?
    @State private var recibido: CuentaPear.QrRecibido?
    @State private var texto = ""
    @State private var emojis: [Int] = []
    @State private var quedan: TimeInterval = 300
    @State private var aceptando = false
    @State private var intento = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            switch paso {
            case .cargando:
                CabeceraQr(pose: "corriendo", titulo: L("Entrar desde otro móvil"), texto: L("Preparando el código…"))
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .qr:
                CabeceraQr(pose: "corriendo", titulo: L("Entrar desde otro móvil"),
                           texto: L("En tu otro móvil, abre Ajustes › Cuenta › Añadir un móvil y escanea este código."))
                Section {
                    ImagenQr(texto: texto).listRowBackground(Color.clear)
                } footer: {
                    Text(L("Caduca en {0}", String(format: "%d:%02d", Int(quedan) / 60, Int(quedan) % 60)))
                        .frame(maxWidth: .infinity).monospacedDigit()
                }
                Section { Text(L("No enseñes este código a nadie: sirve para entrar en tu cuenta.")).font(.footnote).foregroundStyle(.secondary) }
            case .comparar:
                CabeceraQr(pose: "pensando", titulo: L("¿Ves lo mismo en tu otro móvil?"),
                           texto: L("Los dos móviles tienen que enseñar los mismos emojis, en el mismo orden."))
                Section { EmojisComprobacion(indices: emojis) }
                Section {
                    Button(L("Sí, coinciden")) { aceptar() }
                        .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                        .disabled(aceptando).accessibilityIdentifier("siCoinciden")
                }
                // Aparte y sin tarjeta, como el botón de texto de Android: en la misma sección, el botón shu (sin fondo de
                // fila) quedaba pegado a la tarjeta de éste (PULIR #2).
                Section {
                    Button(L("No coinciden"), role: .destructive) { recibido = nil; paso = .noCoinciden }
                        .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("noCoinciden")
                        .listRowBackground(Color.clear)
                }
            case .noCoinciden:
                CabeceraQr(pose: "brazos-cruzados", titulo: L("No coinciden"),
                           texto: L("No uses este código y quita el móvil de tu cuenta desde el otro."))
                Section { Button(L("Empezar otra vez")) { intento += 1 }.frame(maxWidth: .infinity, minHeight: 44) }
            case .error(let m):
                CabeceraQr(pose: "brazos-cruzados", titulo: L("Entrar desde otro móvil"), texto: L("No ha salido bien. Puedes probar otra vez."))
                Section { AvisoQr(texto: m) }
                Section {
                    Button(L("Empezar otra vez")) { intento += 1 }
                        .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle(L("Entrar desde otro móvil")).navigationBarTitleDisplayMode(.inline)
        .task(id: intento) { await empezar() }
    }

    private func empezar() async {
        sesion = nil; recibido = nil
        if let prueba {
            // Los vectores de shared/spec/vectores/emparejamiento.json (el QR y sus emojis).
            texto = "libremusic://emparejar?v=2&id=TJJTHK2BVQ9V2A6H6Q72KQ1AKR&e=fN5zZb1kxNQ071Lig_cG5rqroyaNNenLj0XzEqTO-xY&h=5hBWhGzljWG1TvmutMQjjhCQagunS0RhHOItbyVk4_c&s=Hm9gO6fgYW9dUU7ojHhqKg&n=iPhone%2016"
            quedan = 272; emojis = [59, 29, 27, 61, 23, 38]
            paso = prueba == .qr ? .qr : .comparar
            return
        }
        paso = .cargando
        do {
            let q = try await CuentaPear.shared.empezarQr()
            sesion = q; texto = q.texto; quedan = q.quedan; paso = .qr
            // Paso 8: cada 2 s hasta `completado` o los 5 min (reloj monótono).
            while !Task.isCancelled, paso == .qr {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                quedan = q.quedan
                if let r = try await CuentaPear.shared.esperarQr(q) {
                    recibido = r; emojis = r.emojis; paso = .comparar
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        } catch is CancellationError {
        } catch { paso = .error(mensaje(error)) }
    }

    private func aceptar() {
        guard let q = sesion, let r = recibido else { return }
        aceptando = true
        Task {
            defer { aceptando = false }
            do { try await CuentaPear.shared.aceptarQr(q, r); dismiss() } catch is CancellationError {} catch { paso = .error(mensaje(error)) }
        }
    }
}

// MARK: Móvil viejo: Dispositivos › «Añadir un móvil»

struct AnadirMovilView: View {
    /// Sólo capturas: «¿Añadir…?» o los emojis, sin cámara ni red.
    enum Prueba { case confirmar, emojis }
    var prueba: Prueba? = nil

    private enum Paso: Equatable { case escaner, leyendo, confirmar, emojis, error(String) }
    @State private var paso: Paso = .escaner
    @State private var leido: CuentaPear.QrLeido?
    @State private var nombre = ""
    @State private var emojis: [Int] = []
    @State private var aviso: String?
    @State private var completando = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            switch paso {
            case .escaner, .leyendo:
                CabeceraQr(pose: "con-movil", titulo: L("Añadir un móvil"),
                           texto: L("En el móvil nuevo, abre Ajustes › Cuenta › Entrar desde otro móvil y apunta la cámara a su código."))
                Section {
                    if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                        Text(L("Jiyu Pulse no puede usar la cámara. Actívala en los ajustes del iPhone."))
                        if let url = URL(string: UIApplication.openSettingsURLString) { Link(L("Abrir Ajustes"), destination: url) }
                    } else {
                        QRScanner(alTexto: { t in leer(t) })
                            .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay { if paso == .leyendo { ProgressView().tint(.white) } }
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                            .accessibilityLabel(L("Cámara para escanear el código"))
                    }
                    if let aviso { AvisoQr(texto: aviso) }
                }
            case .confirmar:
                CabeceraQr(pose: "saltando", titulo: L("¿Añadir \"{0}\" a tu cuenta?", nombre),
                           texto: L("Podrá usar tu cuenta y ver tu biblioteca. Te pediremos Face ID, huella o el código del móvil."))
                if let aviso { Section { AvisoQr(texto: aviso) } }
                Section {
                    Button(L("Añadir")) { completar() }
                        .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                        .disabled(completando).accessibilityIdentifier("anadirMovil")
                }
                // Aparte y sin tarjeta, como en comparar (y como Android): si no, el shu quedaba pegado a «Cancelar».
                Section {
                    Button(L("Cancelar")) { dismiss() }.frame(maxWidth: .infinity, minHeight: 44).listRowBackground(Color.clear)
                }
            case .emojis:
                CabeceraQr(pose: "victoria", titulo: L("Comprueba los emojis"), texto: L("Comprueba que el otro móvil enseña lo mismo."))
                Section { EmojisComprobacion(indices: emojis) } footer: {
                    Text(L("Si no coinciden, quita \"{0}\" de tu cuenta en Dispositivos.", nombre))
                }
                Section {
                    Button(L("Hecho")) { dismiss() }
                        .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            case .error(let m):
                CabeceraQr(pose: "brazos-cruzados", titulo: L("Añadir un móvil"), texto: L("No se ha añadido nada a tu cuenta."))
                Section { AvisoQr(texto: m) }
                Section {
                    Button(L("Escanear otra vez")) { aviso = nil; paso = .escaner }
                        .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle(L("Añadir un móvil")).navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let prueba else { return }
            nombre = L("Pixel de Ana"); emojis = [59, 29, 27, 61, 23, 38]
            paso = prueba == .confirmar ? .confirmar : .emojis
        }
    }

    /// Lo que lee la cámara: sólo un QR de emparejar bien formado sigue (cualquier otro: «Este código no es válido»).
    private func leer(_ texto: String) -> Bool {
        guard paso == .escaner else { return false }
        guard CuentaCripto.leerQr(texto) != nil else { aviso = CuentaPear.ErrorCuenta(codigo: "qr_invalido").mensaje; return false }
        aviso = nil; paso = .leyendo
        Task {
            do {
                let l = try await CuentaPear.shared.leerQrDeOtro(texto)
                leido = l; nombre = l.qr.nombre; paso = .confirmar
            } catch is CancellationError {
            } catch { paso = .error(mensaje(error)) }
        }
        return true
    }

    private func completar() {
        guard let l = leido else { return }
        completando = true
        Task {
            defer { completando = false }
            do { emojis = try await CuentaPear.shared.completarQr(l); paso = .emojis }
            catch let e as CuentaPear.ErrorCuenta where e.codigo == "presencia" { aviso = e.mensaje }
            catch is CancellationError {}
            catch { paso = .error(mensaje(error)) }
        }
    }
}
