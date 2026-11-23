import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Ajustes › Cuenta (3.0, 2-C paso 3): pantallas de la cuenta sin contraseña
// Una pose de la mascota por pantalla (brandbook pág. 17, «con cuentas»), un solo shu por pantalla (docs/COLOR.md),
// textos en L("…") con la voz del brandbook. Las poses de la mascota, el gestor y el enlace legal los decidió Toxbox (órdenes 6 y 9 del 18-11).

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

/// La clave en sus 7 grupos (6 de 4 y uno de 2), en dos filas (1–4 y 5–7) con su número encima, para que se vea qué es
/// «el grupo N». `resaltar`: el que se pide al confirmar, con borde y número en `.tint` sobre `systemFill` (no es relleno
/// de acento: no gasta el shu de la pantalla). Orden 11. Igual que `ClaveEnGrupos` en Android.
struct ClaveEnGrupos: View {
    let clave: String
    var resaltar: Int?
    var body: some View {
        let grupos = stride(from: 0, to: clave.count, by: 4).map { i -> String in
            let a = clave.index(clave.startIndex, offsetBy: i), b = clave.index(a, offsetBy: min(4, clave.count - i))
            return String(clave[a..<b])
        }
        VStack(spacing: 10) {
            ForEach([Array(0..<min(4, grupos.count)), Array(min(4, grupos.count)..<grupos.count)], id: \.self) { fila in
                HStack(spacing: 8) {
                    ForEach(fila, id: \.self) { i in
                        let n = i + 1, si = n == resaltar
                        VStack(spacing: 2) {
                            Text("\(n)").font(.caption.weight(si ? .bold : .regular))
                                .foregroundStyle(si ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            Text(grupos[i]).font(.system(.headline, design: .monospaced)).lineLimit(1).fixedSize()
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(si ? Color(.systemFill) : .clear, in: RoundedRectangle(cornerRadius: Tokens.Radius.artworkSmall))
                                .overlay { if si { RoundedRectangle(cornerRadius: Tokens.Radius.artworkSmall).strokeBorder(.tint, lineWidth: 2) } }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("Grupo {0}: {1}", String(n), grupos[i].map(String.init).joined(separator: " ")))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .accessibilityIdentifier("claveMostrada")
    }
}

/// Copia la clave sólo en este móvil (`localOnly`: no pasa a otros por Handoff) y caduca a los 60 s
/// (`expirationDate`: el sistema la borra aunque la app esté cerrada). Orden 11. Igual que `copiarClave` en Android.
@MainActor func copiarClave(_ texto: String) {
    UIPasteboard.general.setItems([[UTType.plainText.identifier: texto]],
                                  options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
}

/// PULIR #3: mientras se baja, se une o se sube la biblioteca (si tarda más de 0,8 s, para no parpadear en cada 304) y
/// «Biblioteca al día» 2 s cuando han llegado cambios de otro móvil. Arriba, sin tapar nada que se toque. Con «Reducir
/// movimiento», icono quieto en vez de la rueda. Igual que `AvisoSync` en Android.
struct AvisoSync: View {
    @ObservedObject private var sync = SyncBiblioteca.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var texto: String?
    @State private var girando = false
    var body: some View {
        VStack {
            if let texto {
                HStack(spacing: 10) {
                    if girando && !reduceMotion { ProgressView().controlSize(.small) }
                    else { Image(systemName: girando ? "arrow.triangle.2.circlepath" : "checkmark.icloud").foregroundStyle(.secondary) }
                    Text(texto).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thickMaterial, in: Capsule())
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("avisoSync")
            }
            Spacer()
        }
        .padding(.top, 8)
        .allowsHitTesting(false)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.25), value: texto)
        .task(id: sync.vista.fase) {
            let f = sync.vista.fase
            if f == .quieta { if girando { texto = nil; girando = false }; return }
            if texto == nil { try? await Task.sleep(nanoseconds: 800_000_000) }
            guard !Task.isCancelled, sync.vista.fase == f else { return }
            texto = f.texto; girando = true
            UIAccessibility.post(notification: .announcement, argument: f.texto)
        }
        .task(id: sync.vista.traido) {
            let t = sync.vista.traido
            guard t > 0, Date().timeIntervalSince1970 * 1000 - t < 3000 else { return }
            texto = L("Biblioteca al día"); girando = false
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !girando { texto = nil }
        }
    }
}

/// PULIR #5: Ajustes › Cuenta › «Lo que se sincroniza». Las carpetas, playlists, álbumes, favoritas y artistas que
/// viajan entre tus móviles; al tocar uno, dos cosas distintas (lo decidió Toxbox el 19-11): «No sincronizar esto» (sólo
/// en este móvil; en los demás no se toca; sync.md §5.6) y «Quitar de todos mis móviles» (se borra, con confirmación).
/// Una carpeta marcada arrastra lo de dentro. Sin shu. Igual que `Sincronizado` en Android.
struct SincronizadoView: View {
    @EnvironmentObject private var library: Library
    @ObservedObject private var sync = SyncBiblioteca.shared
    @State private var elegido: Elemento?
    @State private var confirmar: Elemento?
    @State private var verTodas = false

    enum Tipo {
        case carpeta, playlist, album, favorita, artista
        var icono: String {
            switch self {
            case .carpeta: return "folder.fill"
            case .playlist: return "music.note.list"
            case .album: return "square.stack"
            case .favorita: return "heart.fill"
            case .artista: return "person.fill"
            }
        }
        var aviso: String {
            switch self {
            case .carpeta: return L("Se borra la carpeta aquí y en tus otros móviles; lo que tiene dentro sube un nivel. No se puede deshacer.")
            case .playlist: return L("Se borra la playlist aquí y en tus otros móviles. No se puede deshacer.")
            case .album: return L("Se quita el álbum de tu biblioteca aquí y en tus otros móviles.")
            case .favorita: return L("Deja de ser favorita aquí y en tus otros móviles.")
            case .artista: return L("Dejas de seguirlo aquí y en tus otros móviles.")
            }
        }
    }
    struct Elemento: Identifiable, Equatable { let clave: String, nombre: String, tipo: Tipo, detalle: String?; var id: String { clave } }

    private var enteras: Set<String> {
        let lib = try? JV.leer(library.exportData(covers: false))
        return Set(SyncModel.soloAquiEntero(lib, Array(sync.soloAqui)))
    }

    var body: some View {
        let enteras = self.enteras
        Form {
            Cabecera(pose: "con-cascos", titulo: L("Lo que se sincroniza"),
                     texto: L("Esto viaja cifrado entre tus móviles. Toca algo para dejarlo sólo en este móvil o para quitarlo de todos."))
            seccion(L("Carpetas"), library.folders.map { f in
                Elemento(clave: "folder:\(f.id)", nombre: f.name, tipo: .carpeta,
                         detalle: PlaylistFolders.path(f.id, in: library.folders).dropLast().map(\.name).joined(separator: " › ").nilSiVacio)
            }, vacio: L("No tienes carpetas."), enteras: enteras)
            seccion(L("Playlists"), library.userPlaylists.map {
                Elemento(clave: "playlist:\($0.id.uuidString)", nombre: $0.name, tipo: .playlist, detalle: L("{0} canciones", String($0.songs.count)))
            }, vacio: L("No tienes playlists."), enteras: enteras)
            seccion(L("Álbumes"), library.albums.map {
                Elemento(clave: "playlist:\($0.id.uuidString)", nombre: $0.name, tipo: .album, detalle: $0.album?.artist)
            }, vacio: L("No tienes álbumes guardados."), enteras: enteras)
            seccion(L("Favoritas"), library.favorites.map {
                Elemento(clave: "favorite:\($0.id)", nombre: $0.title, tipo: .favorita, detalle: $0.artist.nilSiVacio)
            }, vacio: L("No tienes favoritas."), enteras: enteras, tope: verTodas ? .max : 30)
            seccion(L("Artistas que sigues"), library.followedArtists.map {
                Elemento(clave: "artist:\($0.browseId)", nombre: $0.name, tipo: .artista, detalle: nil)
            }, vacio: L("No sigues a ningún artista."), enteras: enteras)
        }
        .navigationTitle(L("Lo que se sincroniza")).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(elegido?.nombre ?? "", isPresented: Binding(get: { elegido != nil }, set: { if !$0 { elegido = nil } }),
                            titleVisibility: .visible, presenting: elegido) { e in
            let heredada = enteras.contains(e.clave) && !sync.soloAqui.contains(e.clave)
            if !heredada {
                Button(sync.soloAqui.contains(e.clave) ? L("Volver a sincronizar") : L("No sincronizar esto")) {
                    sync.soloEnEsteMovil(e.clave, !sync.soloAqui.contains(e.clave))
                }
            }
            Button(L("Quitar de todos mis móviles"), role: .destructive) { confirmar = e }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { e in
            Text(enteras.contains(e.clave) && !sync.soloAqui.contains(e.clave)
                 ? L("Va con su carpeta, que no se sincroniza. Para volver a sincronizarlo, vuelve a sincronizar la carpeta.")
                 : sync.soloAqui.contains(e.clave)
                 ? L("Ahora sólo está en este móvil. Si lo vuelves a sincronizar, pasará a tus otros móviles.")
                 : L("«No sincronizar esto» lo deja sólo en este móvil (en los demás se queda como está). «Quitar de todos mis móviles» lo borra aquí y en los demás."))
        }
        .alert(L("¿Quitar \"{0}\" de todos tus móviles?", confirmar?.nombre ?? ""),
               isPresented: Binding(get: { confirmar != nil }, set: { if !$0 { confirmar = nil } }), presenting: confirmar) { e in
            Button(L("Quitar"), role: .destructive) { quitar(e) }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { e in Text(e.tipo.aviso) }
    }

    @ViewBuilder
    private func seccion(_ titulo: String, _ elementos: [Elemento], vacio: String, enteras: Set<String>, tope: Int = .max) -> some View {
        Section {
            ForEach(elementos.prefix(tope)) { e in
                Button { elegido = e } label: {
                    HStack(spacing: 12) {
                        Image(systemName: e.tipo.icono).foregroundStyle(Color(uiColor: .secondaryLabel)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.nombre).foregroundStyle(Color(uiColor: .label))
                            let sub = sync.soloAqui.contains(e.clave) ? L("Sólo en este móvil")
                                : enteras.contains(e.clave) ? L("Sólo en este móvil: va con su carpeta") : e.detalle
                            if let sub { Text(sub).font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel)) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("sinc-\(e.clave)")
            }
            if elementos.count > tope { Button(L("Ver las {0}", String(elementos.count))) { verTodas = true } }
        } header: { Text(titulo) } footer: { if elementos.isEmpty { Text(vacio) } }
    }

    private func quitar(_ e: Elemento) {
        let id = String(e.clave.split(separator: ":", maxSplits: 1).last ?? "")
        switch e.tipo {
        case .carpeta: library.deleteFolder(id)
        case .playlist, .album: if let u = UUID(uuidString: id) { library.deletePlaylist(u) }
        case .favorita: if let s = library.favorites.first(where: { $0.id == id }) { library.toggleFavorite(s) }
        case .artista: library.unfollow(id)
        }
        if sync.soloAqui.contains(e.clave) { sync.soloEnEsteMovil(e.clave, false) }
    }
}

private extension String { var nilSiVacio: String? { isEmpty ? nil : self } }

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
    @State private var crear = false
    var body: some View {
        Form {
            Section { AccountPitch().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            // PULIR #2: quien ya tiene la cuenta en otro móvil lo ve lo primero (antes estaba debajo de «Crear cuenta» y
            // no se encontraba). Filas con icono; el shu sigue siendo «Crear cuenta», el único de la pantalla.
            Section {
                NavigationLink(destination: QrNuevoView()) { Label(L("Entrar desde otro móvil"), systemImage: "qrcode") }
                    .accessibilityIdentifier("entrarDesdeOtro")
                NavigationLink(destination: EntrarConClaveView()) { Label(L("Entrar con tu clave de recuperación"), systemImage: "key") }
                    .accessibilityIdentifier("entrarConClave")
            } header: { Text(L("¿Ya tienes cuenta?")) } footer: {
                Text(L("Con tu otro móvil a mano, entra con un código QR. Si lo has perdido, con la clave que apuntaste."))
            }
            Section {
                // Un NavigationLink dentro de un Form se pinta como fila y pierde el botón shu: botón + destino.
                Button(L("Crear cuenta")) { crear = true }
                    .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("crearCuenta")
            }
        }
        .navigationDestination(isPresented: $crear) { CrearCuentaView() }
    }
}

// MARK: Crear cuenta (§7.2: dos casillas obligatorias y la telemetría aparte)

struct CrearCuentaView: View {
    @State private var terminos = false
    @State private var edad = false
    @State private var telemetria = false
    @State private var borrador: CuentaPear.Borrador?
    /// Términos y privacidad en el idioma de la app (lo decidió Toxbox, orden 9 del 18-11).
    private var legal: URL { CuentaViewsLegal.url }

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
        .navigationTitle(L("Crear cuenta")).navigationBarTitleDisplayMode(.inline)
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
            // Orden 11: qué es, para qué sirve y qué hay que hacer, sin pensar.
            Cabecera(pose: "brazos-cruzados", titulo: L("Tu clave de recuperación"),
                     texto: L("Es la llave de tu cuenta. Si pierdes este móvil, con ella entras desde otro. Apúntala en papel y guárdala: no se puede ver otra vez ni cambiar por otra."))
            Section {
                ClaveEnGrupos(clave: borrador.clave, resaltar: confirmando ? grupo : nil)
                Button { copiarClave(CuentaCripto.mostrarClave(borrador.clave)); copiada = true } label: {
                    Label(copiada ? L("Copiada: se borra en 1 minuto") : L("Copiar"), systemImage: copiada ? "checkmark" : "doc.on.doc")
                }
                // Lo decidió Toxbox (orden 6, 18-11): iOS no deja guardar una contraseña sin dominio en el gestor del sistema;
                // se ofrece compartirla con el gestor que tenga (Contraseñas, 1Password…), sin marcar por defecto.
                ShareLink(item: CuentaCripto.mostrarClave(borrador.clave)) {
                    Label(L("Guardar en un gestor de contraseñas"), systemImage: "key")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Son 26 caracteres en 7 grupos: seis de 4 y uno de 2. Lo redondo es siempre un cero: en tu clave nunca hay letra O (ni I, L o U)."))
                    if !confirmando { Text(L("Si alguien conoce el código de tu móvil, también podrá ver esta clave. Lo más seguro es apuntarla en papel.")) }
                }
            }
            if confirmando {
                Section {
                    TextField(L("Grupo {0}", String(grupo)), text: $escrito)
                        .font(.system(.body, design: .monospaced)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .accessibilityIdentifier("campoGrupo")
                    if fallo { Estado(ok: false, texto: L("No es ese grupo. Prueba con otro")) }
                    if let error { Estado(ok: false, texto: error) }
                } header: { Text(L("Escribe el grupo {0} de tu clave", String(grupo))) } footer: {
                    Text(L("Un grupo son los 4 caracteres que van juntos, con su número encima. Cuenta desde la izquierda: el {0} es el que está marcado arriba.", String(grupo)))
                }
            }
            Section {
                Button(confirmando ? L("Crear cuenta") : L("Ya la he apuntado")) { siguiente() }
                    .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .disabled(creando || (confirmando && escrito.isEmpty))
                    .accessibilityIdentifier("botonClave")
            }
        }
        .navigationTitle(L("Tu clave")).navigationBarTitleDisplayMode(.inline)
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
            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
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
        .navigationTitle(L("Entrar")).navigationBarTitleDisplayMode(.inline)
    }

    private func entrar() {
        // Sin llamar al servidor: «Esa clave no es válida» (§3).
        guard CuentaCripto.leerClave(clave) != nil else { error = CuentaPear.ErrorCuenta(codigo: "clave_invalida").mensaje; return }
        entrando = true
        Task {
            defer { entrando = false }
            do { try await CuentaPear.shared.entrarConClave(clave); dismiss() }
            catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
        }
    }
}

// MARK: Con cuenta: avisos y secciones

private struct CuentaConectada: View {
    @ObservedObject private var cuenta = CuentaPear.shared
    @ObservedObject private var sync = SyncBiblioteca.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("accountName") private var nombreCuenta = ""
    @State private var cambiarNombre = false
    @State private var nombreNuevo = ""
    @State private var error: String?
    @State private var terminos = false

    var body: some View {
        Form {
            if let fecha = cuenta.borrarEn {
                Section {
                    Estado(ok: false, texto: L("Se va a borrar tu cuenta el {0}", Date(timeIntervalSince1970: TimeInterval(fecha))
                        .formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: I18n.current == "va" ? "ca" : I18n.current)))))
                    Button(L("Cancelar el borrado")) { hacer { try await cuenta.cancelarBorrado() } }
                }
            }
            if cuenta.terminosPendientes {
                Section {
                    Text(L("Hay términos nuevos. Para seguir usando la cuenta, léelos y acéptalos."))
                    Button(L("Ver los términos nuevos")) { terminos = true }
                }
            }
            // La biblioteca de la cuenta (2-D, sync.md §4 y §5.4): lo que hay que contar una vez.
            if let aviso = sync.aviso {
                Section {
                    Text(aviso)
                    Button(L("Entendido")) { sync.avisoVisto() }
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
            // PULIR #6: el nombre de la cuenta, sólo para ti (cifrado; sólo lo ven tus móviles). Sin @usuario ni buscador.
            Section {
                Button { nombreNuevo = nombreCuenta; cambiarNombre = true } label: {
                    HStack {
                        Label(L("Nombre de la cuenta"), systemImage: "person.text.rectangle").foregroundStyle(Color(uiColor: .label))
                        Spacer()
                        Text(nombreCuenta.isEmpty ? L("Sin nombre") : nombreCuenta).foregroundStyle(Color(uiColor: .secondaryLabel)).lineLimit(1)
                    }
                }
                .accessibilityIdentifier("nombreCuenta")
            } footer: { Text(L("Sólo para ti: va cifrado y sólo lo ven tus móviles. No es un nombre de usuario: nadie te puede buscar por él.")) }
            // PULIR #4: cómo va la sincronización; tocar la fila sincroniza ya. Igual en Android.
            Section {
                let e = sync.vista.estado()
                Button { sync.alEntrar() } label: {
                    HStack {
                        Label(e.texto, systemImage: e.icono).foregroundStyle(Color(uiColor: .label))
                        Spacer(minLength: 0)
                        if sync.vista.fase != .quieta && !reduceMotion { ProgressView() }
                    }
                }
                .accessibilityIdentifier("estadoSync")
            } footer: { Text(L("Toca para sincronizar ahora.")) }
            // PULIR #2: «Añadir un móvil» también aquí, no sólo dentro de Dispositivos (no se encontraba).
            Section {
                NavigationLink(destination: AnadirMovilView()) { Label(L("Añadir un móvil"), systemImage: "qrcode.viewfinder") }
                    .disabled(cuenta.dispositivos.count >= 10)
                    .accessibilityIdentifier("anadirUnMovilCuenta")
            } footer: {
                Text(cuenta.dispositivos.count >= 10 ? L("Ya hay 10 móviles en tu cuenta. Quita uno antes")
                                                     : L("Para entrar en tu cuenta desde otro móvil sin escribir la clave: en el móvil nuevo, «Entrar desde otro móvil»."))
            }
            Section {
                NavigationLink(destination: SincronizadoView()) { Label(L("Lo que se sincroniza"), systemImage: "checklist") } // PULIR #5
                    .accessibilityIdentifier("loQueSeSincroniza")
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
        .alert(L("Nombre de la cuenta"), isPresented: $cambiarNombre) {
            TextField(L("Por ejemplo, Mi música"), text: $nombreNuevo)
            Button(L("Guardar")) { if let n = LibraryFile.nombreCuentaValido(nombreNuevo) { nombreCuenta = n } }
                .disabled(LibraryFile.nombreCuentaValido(nombreNuevo) == nil)
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(L("Para que reconozcas tu cuenta en tus móviles. Hasta 40 caracteres; vacío, sin nombre.")) }
    }

    private func hacer(_ trabajo: @escaping () async throws -> Void) {
        Task {
            do { try await trabajo(); error = nil }
            catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
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
                            enlace: (L("Leer los textos"), CuentaViewsLegal.url))
                    Casilla(marcada: $edad, titulo: L("Tengo 14 años o más"))
                    if let error { Estado(ok: false, texto: error) }
                }
                Section {
                    Button(L("Aceptar")) {
                        Task {
                            do { try await CuentaPear.shared.aceptarTerminos(); dismiss() }
                            catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
                            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
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
    @State private var renombrar: CuentaPear.Dispositivo?
    @State private var nombreNuevo = ""
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
                        // Tocar el nombre lo cambia (orden 6 del 18-11): sirve para este móvil y para los demás.
                        Button { nombreNuevo = d.nombre; renombrar = d } label: {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    // Colores del sistema explícitos: dentro de un botón, .primary/.secondary salen con el
                                    // tinte (shu) y la pantalla tendría varios (COLOR.md, un solo shu; captura 60 del 18-11).
                                    Text(d.nombre).foregroundStyle(Color(uiColor: .label))
                                    Text(d.este ? L("Este móvil") : visto(d)).font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "pencil").font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel)).accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityHint(L("Cambiar nombre"))
                        .accessibilityIdentifier("renombrar-\(d.id)")
                        Button(L("Quitar"), role: .destructive) { quitar = d }.buttonStyle(.borderless)
                    }
                    .frame(minHeight: 44)
                }
            } footer: {
                if cuenta.soloEsteMovil { Text(L("Sólo tienes este móvil en tu cuenta. Si lo pierdes, sólo podrás entrar con tu clave de recuperación.")) }
            }
            Section {
                NavigationLink(destination: AnadirMovilView()) { Label(L("Añadir un móvil"), systemImage: "qrcode.viewfinder") }
                    .disabled(cuenta.dispositivos.count >= 10)
                    .accessibilityIdentifier("anadirUnMovil")
            } footer: {
                Text(cuenta.dispositivos.count >= 10 ? L("Ya hay 10 móviles en tu cuenta. Quita uno antes")
                                                     : L("Escanea el código que enseña el móvil nuevo."))
            }
            if let error { Section { Estado(ok: false, texto: error) } }
            if cuenta.dispositivos.count > 1 {
                Section {
                    Button(L("Quitar todos los demás móviles"), role: .destructive) { losDemas = true }
                } footer: { Text(L("Si te han robado un móvil: sale todo de golpe menos este. Hace falta tu clave de recuperación.")) }
            }
        }
        .navigationTitle(L("Dispositivos")).navigationBarTitleDisplayMode(.inline)
        .task { try? await cuenta.cargar() }
        .confirmationDialog(L("¿Quitar \"{0}\"?", quitar?.nombre ?? ""), isPresented: Binding(get: { quitar != nil }, set: { if !$0 { quitar = nil } }), titleVisibility: .visible) {
            Button(L("Quitar"), role: .destructive) {
                if let d = quitar { hacer { try await cuenta.quitar(d.id) } }
            }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(quitar?.este == true ? L("Este móvil saldrá de tu cuenta.") : L("Ese móvil ya no podrá entrar en tu cuenta.")) }
        .alert(L("Cambiar nombre"), isPresented: Binding(get: { renombrar != nil }, set: { if !$0 { renombrar = nil } })) {
            TextField(L("Nombre del móvil"), text: $nombreNuevo).accessibilityIdentifier("nombre-movil")
            Button(L("Guardar")) {
                if let d = renombrar { let n = nombreNuevo; hacer { try await cuenta.renombrar(d.id, a: n) } }
            }
            .disabled(CuentaCripto.nombreValido(nombreNuevo) == nil)
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(L("Así lo verás en tus móviles. De 1 a 40 caracteres.")) }
        .alert(L("Quitar todos los demás móviles"), isPresented: $losDemas) {
            TextField(L("Tu clave de recuperación"), text: $clave).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button(L("Quitar todos"), role: .destructive) { let c = clave; clave = ""; hacer { try await cuenta.quitarLosDemas(clave: c) } }
            Button(L("Cancelar"), role: .cancel) { clave = "" }
        } message: { Text(L("Escribe tu clave de recuperación para confirmarlo.")) }
    }

    private func visto(_ d: CuentaPear.Dispositivo) -> String {
        guard let v = d.visto else { return L("Nunca") }
        // Fecha en el idioma de la app (no en el del sistema), igual que Android: «Visto 17 nov 2025».
        let idioma = I18n.current == "va" ? "ca" : I18n.current
        return L("Visto {0}", Date(timeIntervalSince1970: TimeInterval(v))
            .formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: idioma))))
    }
    private func hacer(_ trabajo: @escaping () async throws -> Void) {
        Task {
            do { try await trabajo(); error = nil }
            catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
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
        .navigationTitle(L("Comprobar mi clave")).navigationBarTitleDisplayMode(.inline)
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
        .navigationTitle(L("Borrar cuenta")).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("¿Borrar tu cuenta?"), isPresented: $confirmar, titleVisibility: .visible) {
            Button(L("Borrar la cuenta"), role: .destructive) {
                let c = clave
                Task {
                    do { try await cuenta.borrar(clave: c.isEmpty ? nil : c); dismiss() }
                    catch let e as CuentaPear.ErrorCuenta { error = e.mensaje }
                    catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
                }
            }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(L("No se puede deshacer.")) }
    }
}

/// `/legal/<idioma>` de la web: los Términos de uso y la Política de privacidad en el idioma de la app.
enum CuentaViewsLegal {
    static var url: URL { URL(string: "https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev/legal/\(I18n.current)")! }
}

// MARK: - Por qué crear una cuenta
/// Opcional, ayuda a mejorar la app y pronto tendrá ventajas (lo pidió Toxbox). En Ajustes › Cuenta y en la guía
/// inicial. Mismo texto que `AccountPitch` en Android.
struct AccountPitch: View {
    @Environment(\.accentFill) private var accentFill
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image("Logo").resizable().scaledToFit().frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Tu cuenta de Jiyu Pulse")).font(.title3.bold())
                    Text(L("Opcional · gratis")).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(accentFill.opacity(0.12)))
                }
            }
            Text(L("No la necesitas para nada: Jiyu Pulse funciona igual sin ella. Pero si te la creas nos ayudas muchísimo a mejorar la app, y tú te llevas tu música allá donde vayas."))
                .font(.callout).foregroundStyle(.secondary).padding(.top, 14).padding(.bottom, 6)
                .fixedSize(horizontal: false, vertical: true)
            point("lock.fill", 5, L("Tu biblioteca, cifrada en la nube"), L("Sólo tú tienes la clave. Ni siquiera nosotros podemos leerla."))
            point("iphone.gen3", 2, L("Pásala a otro móvil"), L("Playlists y favoritos en un minuto, también entre iPhone y Android."))
            point("heart.fill", 0, L("Ayudas a mejorar Jiyu Pulse"), L("Saber cuántos sois nos dice dónde poner el esfuerzo."))
            point("sparkles", 4, L("Muy pronto, ventajas"), L("Estamos preparando cosas solo para quien tenga cuenta. Te avisaremos en Avisos."))
        }
        .padding(.horizontal, 20).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
        .accessibilityElement(children: .combine)
    }

    private func point(_ icon: String, _ palette: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GradientIcon(systemName: icon, palette: palette, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }
}
