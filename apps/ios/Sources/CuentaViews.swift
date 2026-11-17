import SwiftUI

// MARK: - Ajustes › Cuenta (3.0, 2-C paso 3): pantallas de la cuenta sin contraseña
// Una pose de la mascota por pantalla (brandbook pág. 17, «con cuentas»), un solo shu por pantalla (docs/COLOR.md),
// textos en L("…") con la voz del brandbook. Lo marcado PROVISIONAL está en «cama 17/PREGUNTAS.md».

/// La mascota de cada pantalla (Assets: mascota-*), con su texto para VoiceOver.
private struct Mascota: View {
    let pose: String
    var alto: CGFloat = 132
    var body: some View {
        Image("mascota-\(pose)").resizable().scaledToFit().frame(height: alto)
            .frame(maxWidth: .infinity).accessibilityHidden(true)
    }
}

/// Cabecera de cada pantalla: mascota, título y una frase.
private struct Cabecera: View {
    let pose: String, titulo: String, texto: String
    var body: some View {
        VStack(spacing: 10) {
            Mascota(pose: pose)
            Text(titulo).font(.title2.bold()).multilineTextAlignment(.center)
            Text(texto).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }
}

/// Error o éxito: icono en color + texto en `label` (el color nunca es la única pista).
private struct Estado: View {
    let ok: Bool, texto: String
    var body: some View {
        Label { Text(texto) } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? .green : .red)
        }
        .font(.subheadline)
    }
}

/// Campo para escribir la clave de recuperación (monoespaciada: es un código que se copia a mano).
private struct CampoClave: View {
    @Binding var texto: String
    var titulo = L("Tu clave de recuperación")
    var body: some View {
        TextField(titulo, text: $texto, axis: .vertical)
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
            .accessibilityIdentifier("campoClave")
    }
}

/// Casilla sin marcar por defecto, como las de la bienvenida (`ConsentBox`): cuadrado en `.tint` (texto, no relleno:
/// no gasta el shu de la pantalla).
private struct Casilla: View {
    @Binding var marcada: Bool
    let titulo: String
    var enlace: (String, URL)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: marcada ? "checkmark.square.fill" : "square").font(.title3)
                .foregroundStyle(marcada ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo).fixedSize(horizontal: false, vertical: true)
                if let enlace { Link(enlace.0, destination: enlace.1).font(.footnote.weight(.semibold)) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { marcada.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(marcada ? L("Marcada") : L("Sin marcar"))
    }
}

// MARK: Raíz

struct CuentaView: View {
    @ObservedObject private var cuenta = CuentaPear.shared
    var body: some View {
        Group {
            if cuenta.tieneCuenta { CuentaConectada() } else { CuentaSinCrear() }
        }
        .navigationTitle(L("Cuenta"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

private struct CuentaSinCrear: View {
    var body: some View {
        Form {
            Section { AccountPitch().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            Section {
                NavigationLink(destination: CrearCuentaView()) { Text(L("Crear cuenta")) }
                    .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("crearCuenta")
            }
            Section {
                NavigationLink(L("Entrar con tu clave de recuperación"), destination: EntrarConClaveView())
                    .accessibilityIdentifier("entrarConClave")
            } footer: { Text(L("Si ya tienes cuenta en otro móvil y has perdido el móvil, entra con la clave que apuntaste.")) }
        }
    }
}

// MARK: Crear cuenta (§7.2: dos casillas obligatorias y la telemetría aparte)

struct CrearCuentaView: View {
    @State private var terminos = false
    @State private var edad = false
    @State private var telemetria = false
    @State private var borrador: CuentaPear.Borrador?
    private let legal = URL(string: "https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev/legal")! // PROVISIONAL (PREGUNTAS #6)

    var body: some View {
        Form {
            Cabecera(pose: "saltando", titulo: L("Tu cuenta, sin contraseña"),
                     texto: L("Nada que recordar ni que te puedan robar. Tu biblioteca viaja cifrada: sólo tus móviles pueden leerla."))
            Section {
                Casilla(marcada: $terminos, titulo: L("Acepto los Términos de uso y la Política de privacidad"), enlace: (L("Leer los textos"), legal))
                    .accessibilityIdentifier("casillaTerminos")
                Casilla(marcada: $edad, titulo: L("Tengo 14 años o más")).accessibilityIdentifier("casillaEdad")
            }
            Section {
                Casilla(marcada: $telemetria, titulo: L("Enviar estadísticas de uso anónimas")).accessibilityIdentifier("casillaTelemetria")
            } footer: { Text(L("Opcional. Puedes crear la cuenta sin marcarla y cambiarlo cuando quieras en Tus datos.")) }
            Section {
                Button(L("Crear cuenta")) {
                    if telemetria { Telemetry.shared.setConsent(true) }
                    borrador = CuentaPear.shared.borrador()
                }
                .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                .disabled(!(terminos && edad))
                .accessibilityIdentifier("botonCrear")
            }
        }
        .navigationTitle(L("Crear cuenta"))
        .navigationDestination(isPresented: Binding(get: { borrador != nil }, set: { if !$0 { borrador = nil } })) {
            if let b = borrador { ClaveNuevaView(borrador: b) }
        }
    }
}

// MARK: Tu clave de recuperación: se enseña UNA vez y se confirma un grupo (§3)

struct ClaveNuevaView: View {
    let borrador: CuentaPear.Borrador
    @Environment(\.dismiss) private var dismiss
    @State private var confirmando = false
    @State private var grupo = Int.random(in: 1...6)
    @State private var escrito = ""
    @State private var fallo = false
    @State private var creando = false
    @State private var error: String?
    @State private var hecho = false
    @State private var copiada = false

    var body: some View {
        Form {
            Cabecera(pose: "brazos-cruzados", titulo: L("Tu clave de recuperación"),
                     texto: L("Apúntala en papel y guárdala bien. Sin ella y sin tu móvil no se puede recuperar nada, y si la pierdes no se puede poner otra."))
            Section {
                Text(CuentaCripto.mostrarClave(borrador.clave))
                    .font(.system(.headline, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                    .textSelection(.enabled).frame(maxWidth: .infinity).padding(.vertical, 6)
                    .accessibilityIdentifier("claveMostrada")
                Button { UIPasteboard.general.string = borrador.clave; copiada = true } label: {
                    Label(copiada ? L("Copiada") : L("Copiar"), systemImage: copiada ? "checkmark" : "doc.on.doc")
                }
                // PROVISIONAL (PREGUNTAS #6): iOS no deja guardar una contraseña sin dominio en el gestor del sistema;
                // se ofrece compartirla con el gestor que tenga (Contraseñas, 1Password…), sin marcar por defecto.
                ShareLink(item: CuentaCripto.mostrarClave(borrador.clave)) {
                    Label(L("Guardar en un gestor de contraseñas"), systemImage: "key")
                }
            } footer: {
                Text(L("Si alguien conoce el código de tu móvil, también podrá ver esta clave. Lo más seguro es apuntarla en papel."))
            }
            if confirmando {
                Section {
                    TextField(L("Grupo {0}", String(grupo)), text: $escrito)
                        .font(.system(.body, design: .monospaced)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .accessibilityIdentifier("campoGrupo")
                    if fallo { Estado(ok: false, texto: L("No es ese grupo. Prueba con otro")) }
                    if let error { Estado(ok: false, texto: error) }
                } header: { Text(L("Escribe el grupo {0} de tu clave", String(grupo))) }
            }
            Section {
                Button(confirmando ? L("Crear cuenta") : L("Ya la he apuntado")) { siguiente() }
                    .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .disabled(creando || (confirmando && escrito.isEmpty))
                    .accessibilityIdentifier("botonClave")
            }
        }
        .navigationTitle(L("Tu clave"))
        .navigationBarBackButtonHidden(creando)
        .alert(L("Cuenta creada"), isPresented: $hecho) {
            Button(L("Vale"), role: .cancel) { dismiss() }
        } message: { Text(L("Sólo tienes este móvil en tu cuenta. Si lo pierdes, sólo podrás entrar con tu clave de recuperación.")) }
    }

    private func siguiente() {
        guard confirmando else { confirmando = true; return }
        let esperado = CuentaCripto.grupo(borrador.clave, grupo)
        guard CuentaCripto.normalizarGrupo(escrito) == esperado else {
            fallo = true
            escrito = ""
            grupo = ([1, 2, 3, 4, 5, 6].filter { $0 != grupo }).randomElement()!
            return
        }
        fallo = false
        creando = true
        Task {
            defer { creando = false }
            do { try await CuentaPear.shared.crear(borrador); hecho = true }
            catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
            catch { self.error = CuentaPear.ErrorCuenta(codigo: "error_interno").mensaje }
        }
    }
}

// MARK: Entrar con tu clave de recuperación (§7.3 punto 1)

struct EntrarConClaveView: View {
    @State private var clave = ""
    @State private var error: String?
    @State private var entrando = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Cabecera(pose: "con-movil", titulo: L("Entrar con tu clave"),
                     texto: L("Escribe la clave de recuperación que apuntaste al crear la cuenta. Da igual mayúsculas, espacios o guiones."))
            Section {
                CampoClave(texto: $clave)
                if let error { Estado(ok: false, texto: error) }
            }
            Section {
                Button(L("Entrar")) { entrar() }
                    .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .disabled(entrando || clave.isEmpty)
                    .accessibilityIdentifier("botonEntrar")
            }
        }
        .navigationTitle(L("Entrar"))
    }

    private func entrar() {
        // Sin llamar al servidor: «Esa clave no es válida» (§3).
        guard CuentaCripto.leerClave(clave) != nil else { error = CuentaPear.ErrorCuenta(codigo: "clave_invalida").mensaje; return }
        entrando = true
        Task {
            defer { entrando = false }
            do { try await CuentaPear.shared.entrarConClave(clave); dismiss() }
            catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
            catch { self.error = CuentaPear.ErrorCuenta(codigo: "error_interno").mensaje }
        }
    }
}

// MARK: Con cuenta: avisos y secciones

private struct CuentaConectada: View {
    @ObservedObject private var cuenta = CuentaPear.shared
    @State private var error: String?
    @State private var terminos = false

    var body: some View {
        Form {
            if let fecha = cuenta.borrarEn {
                Section {
                    Estado(ok: false, texto: L("Se va a borrar tu cuenta el {0}", Date(timeIntervalSince1970: TimeInterval(fecha)).formatted(date: .long, time: .omitted)))
                    Button(L("Cancelar el borrado")) { hacer { try await cuenta.cancelarBorrado() } }
                }
            }
            if cuenta.terminosPendientes {
                Section {
                    Text(L("Hay términos nuevos. Para seguir usando la cuenta, léelos y acéptalos."))
                    Button(L("Ver los términos nuevos")) { terminos = true }
                }
            }
            ForEach(cuenta.avisos) { a in
                Section {
                    switch a.aviso {
                    case .nuevo(let id):
                        Text(L("Se ha añadido \"{0}\" a tu cuenta. ¿No has sido tú? Quítalo", a.nombre))
                        Button(L("Quitar"), role: .destructive) { hacer { try await cuenta.quitar(id); cuenta.avisoVisto(id) } }
                        Button(L("He sido yo")) { cuenta.avisoVisto(id) }
                    case .quitado(let id):
                        Text(L("Se añadió \"{0}\" a tu cuenta y ya se ha quitado. ¿No has sido tú? Revisa tus móviles", a.nombre))
                        Button(L("Entendido")) { cuenta.avisoVisto(id) }
                    }
                }
            }
            if cuenta.soloEsteMovil {
                Section { Text(L("Sólo tienes este móvil en tu cuenta. Si lo pierdes, sólo podrás entrar con tu clave de recuperación.")).font(.footnote) }
            }
            if cuenta.tocaSugerirClave {
                Section {
                    Text(L("¿Sigues teniendo tu clave de recuperación? Compruébala un momento."))
                    NavigationLink(L("Comprobar ahora"), destination: ComprobarClaveView())
                    Button(L("Ahora no")) { cuenta.posponerSugerencia() }
                }
            }
            if let error { Section { Estado(ok: false, texto: error) } }
            Section {
                NavigationLink(destination: DispositivosView()) { Label(L("Dispositivos"), systemImage: "iphone.gen3") }
                NavigationLink(destination: ComprobarClaveView()) { Label(L("Comprobar mi clave"), systemImage: "key") }
            } footer: { Text(L("Tu biblioteca viaja cifrada: el servidor no puede leerla.")) }
            Section {
                NavigationLink(destination: BorrarCuentaView()) { Label(L("Borrar cuenta"), systemImage: "person.crop.circle.badge.minus").foregroundStyle(.red) }
            }
        }
        .task { hacer { try await cuenta.cargar() } }
        .refreshable { hacer { try await cuenta.cargar() } }
        .sheet(isPresented: $terminos) { TerminosNuevosView() }
    }

    private func hacer(_ trabajo: @escaping () async throws -> Void) {
        Task {
            do { try await trabajo(); error = nil }
            catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
            catch { self.error = CuentaPear.ErrorCuenta(codigo: "error_interno").mensaje }
        }
    }
}

/// Términos nuevos: las mismas dos casillas que al crear la cuenta (§7.2).
private struct TerminosNuevosView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var terminos = false
    @State private var edad = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Casilla(marcada: $terminos, titulo: L("Acepto los Términos de uso y la Política de privacidad"),
                            enlace: (L("Leer los textos"), URL(string: "https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev/legal")!))
                    Casilla(marcada: $edad, titulo: L("Tengo 14 años o más"))
                    if let error { Estado(ok: false, texto: error) }
                }
                Section {
                    Button(L("Aceptar")) {
                        Task {
                            do { try await CuentaPear.shared.aceptarTerminos(); dismiss() }
                            catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
                        }
                    }
                    .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .disabled(!(terminos && edad))
                }
            }
            .navigationTitle(L("Términos nuevos")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Ahora no")) { dismiss() } } }
        }
    }
}

// MARK: Dispositivos (§7.3 puntos 3, 7 y 9)

struct DispositivosView: View {
    @ObservedObject private var cuenta = CuentaPear.shared
    @State private var quitar: CuentaPear.Dispositivo?
    @State private var losDemas = false
    @State private var clave = ""
    @State private var error: String?

    var body: some View {
        Form {
            Cabecera(pose: "con-cascos", titulo: L("Tus móviles"), texto: L("Los móviles que pueden entrar en tu cuenta. Si no reconoces alguno, quítalo."))
            Section {
                ForEach(cuenta.dispositivos) { d in
                    HStack(spacing: 12) {
                        Image(systemName: d.plataforma == "ios" ? "iphone" : "smartphone").foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.nombre)
                            Text(d.este ? L("Este móvil") : visto(d)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Quitar"), role: .destructive) { quitar = d }.buttonStyle(.borderless)
                    }
                    .frame(minHeight: 44)
                }
            } footer: {
                if cuenta.soloEsteMovil { Text(L("Sólo tienes este móvil en tu cuenta. Si lo pierdes, sólo podrás entrar con tu clave de recuperación.")) }
            }
            if let error { Section { Estado(ok: false, texto: error) } }
            if cuenta.dispositivos.count > 1 {
                Section {
                    Button(L("Quitar todos los demás móviles"), role: .destructive) { losDemas = true }
                } footer: { Text(L("Si te han robado un móvil: sale todo de golpe menos este. Hace falta tu clave de recuperación.")) }
            }
        }
        .navigationTitle(L("Dispositivos"))
        .task { try? await cuenta.cargar() }
        .confirmationDialog(L("¿Quitar \"{0}\"?", quitar?.nombre ?? ""), isPresented: Binding(get: { quitar != nil }, set: { if !$0 { quitar = nil } }), titleVisibility: .visible) {
            Button(L("Quitar"), role: .destructive) {
                if let d = quitar { hacer { try await cuenta.quitar(d.id) } }
            }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(quitar?.este == true ? L("Este móvil saldrá de tu cuenta.") : L("Ese móvil ya no podrá entrar en tu cuenta.")) }
        .alert(L("Quitar todos los demás móviles"), isPresented: $losDemas) {
            TextField(L("Tu clave de recuperación"), text: $clave).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button(L("Quitar todos"), role: .destructive) { let c = clave; clave = ""; hacer { try await cuenta.quitarLosDemas(clave: c) } }
            Button(L("Cancelar"), role: .cancel) { clave = "" }
        } message: { Text(L("Escribe tu clave de recuperación para confirmarlo.")) }
    }

    private func visto(_ d: CuentaPear.Dispositivo) -> String {
        guard let v = d.visto else { return L("Nunca") }
        return L("Visto {0}", Date(timeIntervalSince1970: TimeInterval(v)).formatted(.relative(presentation: .named)))
    }
    private func hacer(_ trabajo: @escaping () async throws -> Void) {
        Task {
            do { try await trabajo(); error = nil }
            catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
            catch { self.error = CuentaPear.ErrorCuenta(codigo: "error_interno").mensaje }
        }
    }
}

// MARK: Comprobar mi clave (§7.3 punto 7): la clave entera, sin red

struct ComprobarClaveView: View {
    @State private var clave = ""
    @State private var resultado: Bool?

    var body: some View {
        Form {
            Cabecera(pose: "pensando", titulo: L("Comprobar mi clave"), texto: L("Escríbela entera. Se comprueba en este móvil: no se envía a ningún sitio."))
            Section {
                CampoClave(texto: $clave)
                if let resultado { Estado(ok: resultado, texto: resultado ? L("Está bien") : L("Esa no es tu clave")).accessibilityIdentifier("resultadoClave") }
            }
            Section {
                Button(L("Comprobar")) {
                    resultado = CuentaPear.shared.esMiClave(clave)
                    if resultado == true { CuentaPear.shared.posponerSugerencia() }
                }
                .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                .disabled(clave.isEmpty)
                .accessibilityIdentifier("botonComprobar")
            }
        }
        .navigationTitle(L("Comprobar mi clave"))
        .onChange(of: clave) { _ in resultado = nil }
    }
}

// MARK: Borrar cuenta (§7.3 punto 6)

struct BorrarCuentaView: View {
    @ObservedObject private var cuenta = CuentaPear.shared
    @Environment(\.dismiss) private var dismiss
    @State private var clave = ""
    @State private var confirmar = false
    @State private var error: String?

    var body: some View {
        Form {
            Cabecera(pose: "de-espaldas", titulo: L("Borrar tu cuenta"),
                     texto: L("Se borran tu cuenta y todo lo que hay en la nube. Lo que tienes en tus móviles se queda."))
            Section {
                CampoClave(texto: $clave, titulo: L("Tu clave de recuperación (opcional)"))
                if let error { Estado(ok: false, texto: error) }
            } footer: {
                Text(L("Con tu clave se borra al momento. Sin ella, se borra dentro de 14 días y lo verás en todos tus móviles, por si no has sido tú."))
            }
            Section {
                Button(clave.isEmpty ? L("Borrar dentro de 14 días") : L("Borrar ahora"), role: .destructive) { confirmar = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("botonBorrar")
            }
        }
        .navigationTitle(L("Borrar cuenta"))
        .confirmationDialog(L("¿Borrar tu cuenta?"), isPresented: $confirmar, titleVisibility: .visible) {
            Button(L("Borrar la cuenta"), role: .destructive) {
                let c = clave
                Task {
                    do { try await cuenta.borrar(clave: c.isEmpty ? nil : c); dismiss() }
                    catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
                }
            }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(L("No se puede deshacer.")) }
    }
}
