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
/// «Biblioteca al día» 2 s cuando han llegado cambios de otro dispositivo. Arriba, sin tapar nada que se toque. Con «Reducir
/// movimiento», icono quieto en vez de la rueda. Igual que `AvisoSync` en Android.
struct AvisoSync: View {
    @ObservedObject private var sync = SyncBiblioteca.shared
    /// En las pantallas de la cuenta no sale: la fila de la sincronización ya lo dice, y la cápsula tapaba el título y
    /// esa fila (captura 69; Pulir 2 · notas de la opción A). Igual que `AvisoSync` en Android.
    @ObservedObject private var enCuenta = CuentaEnPantalla.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var texto: String?
    @State private var girando = false
    /// Modo fútbol (Pulir 2 #2): «Intentar más tarde» la cierra hasta que se llegue al servidor y se vuelva a perder.
    @State private var cerrado = false
    var body: some View {
        VStack {
            if enCuenta.visible { EmptyView() }
            else if sync.vista.bloqueado && !cerrado && texto == nil {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "icloud.slash").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(VistaSync.textoBloqueado).font(.subheadline.weight(.semibold))
                            Text(VistaSync.detalleBloqueado).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    Button(L("Intentar más tarde")) { cerrado = true }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                        .frame(minHeight: 44).padding(.horizontal, 8)
                        .accessibilityIdentifier("intentarMasTarde")
                }
                .padding(.leading, 16).padding(.trailing, 8).padding(.top, 12)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16)
                .transition(.opacity)
                .accessibilityIdentifier("avisoSyncBloqueado")
            }
            if let texto, !enCuenta.visible {
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
                .allowsHitTesting(false)
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.25), value: texto)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.25), value: sync.vista.bloqueado && !cerrado)
        .onChange(of: sync.vista.bloqueado) { b in if !b { cerrado = false } }
        .task(id: sync.vista.fase) {
            let f = sync.vista.fase
            if f == .quieta { if girando { texto = nil; girando = false }; return }
            if texto == nil { try? await Task.sleep(nanoseconds: 800_000_000) }
            guard !Task.isCancelled, sync.vista.fase == f else { return }
            texto = f.texto; girando = true
            if !enCuenta.visible { UIAccessibility.post(notification: .announcement, argument: f.texto) }
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

/// Pulir 2 #3: «Comprobar ahora» de la fila de la sincronización, cápsula `systemFill` con el texto en `.tint` (no
/// cuenta como shu). Mientras comprueba, «Comprobando…» con la rueda (sin ella con «Reducir movimiento») y no se toca.
/// Igual que `BotonComprobar` en Android.
struct BotonComprobar: View {
    let comprobando: Bool
    let alTocar: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: alTocar) {
            HStack(spacing: 6) {
                if comprobando && !reduceMotion { ProgressView().controlSize(.mini) }
                Text(comprobando ? L("Comprobando…") : L("Comprobar ahora"))
                    .font(.subheadline.weight(.semibold)).lineLimit(1).fixedSize()
                    .foregroundStyle(comprobando ? AnyShapeStyle(Color(uiColor: .secondaryLabel)) : AnyShapeStyle(.tint))
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(Color(uiColor: .systemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(comprobando)
        .accessibilityIdentifier("comprobarAhora")
    }
}

/// PULIR #5: Ajustes › Cuenta › «Lo que se sincroniza». Las carpetas, playlists, álbumes, favoritas y artistas que
/// viajan entre tus dispositivos; al tocar uno, su menú (`Menu`, anclado a la fila; Pulir 2 · notas de la opción A #3)
/// con dos cosas distintas (lo decidió Toxbox el 19-11): «No sincronizar esto» (sólo en este dispositivo; en los demás
/// no se toca; sync.md §5.6) y «Quitar de todos mis dispositivos» (se borra, con la confirmación de eliminar). Una
/// carpeta marcada arrastra lo de dentro. Sin shu. Igual que `Sincronizado` en Android.
struct SincronizadoView: View {
    @EnvironmentObject private var library: Library
    @ObservedObject private var sync = SyncBiblioteca.shared
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
            case .carpeta: return L("Se borra la carpeta aquí y en tus otros dispositivos; lo que tiene dentro sube un nivel. No se puede deshacer.")
            case .playlist: return L("Se borra la playlist aquí y en tus otros dispositivos. No se puede deshacer.")
            case .album: return L("Se quita el álbum de tu biblioteca aquí y en tus otros dispositivos.")
            case .favorita: return L("Deja de ser favorita aquí y en tus otros dispositivos.")
            case .artista: return L("Dejas de seguirlo aquí y en tus otros dispositivos.")
            }
        }
    }
    /// La carpeta, playlist, canción o artista de la biblioteca, para dibujar su imagen (Pulir 2 #1).
    enum Cosa { case carpeta(PlaylistFolder), playlist(Playlist), cancion(Song), artista(FollowedArtist) }
    struct Elemento: Identifiable, Equatable {
        let clave: String, nombre: String, tipo: Tipo, detalle: String?
        var cosa: Cosa? = nil
        var id: String { clave }
        static func == (a: Elemento, b: Elemento) -> Bool { a.clave == b.clave && a.nombre == b.nombre && a.detalle == b.detalle }
    }

    private var enteras: Set<String> {
        let lib = try? JV.leer(library.exportData(covers: false))
        return Set(SyncModel.soloAquiEntero(lib, Array(sync.soloAqui)))
    }

    var body: some View {
        let enteras = self.enteras
        Form {
            Cabecera(pose: "con-cascos", titulo: L("Lo que se sincroniza"),
                     texto: L("Esto viaja cifrado entre tus dispositivos. Toca algo para dejarlo sólo en este dispositivo o para quitarlo de todos."))
            seccion(L("Carpetas"), library.folders.map { f in
                Elemento(clave: "folder:\(f.id)", nombre: f.name, tipo: .carpeta,
                         detalle: PlaylistFolders.path(f.id, in: library.folders).dropLast().map(\.name).joined(separator: " › ").nilSiVacio, cosa: .carpeta(f))
            }, vacio: L("No tienes carpetas."), enteras: enteras)
            seccion(L("Playlists"), library.userPlaylists.map {
                Elemento(clave: "playlist:\($0.id.uuidString)", nombre: $0.name, tipo: .playlist, detalle: L("{0} canciones", String($0.songs.count)), cosa: .playlist($0))
            }, vacio: L("No tienes playlists."), enteras: enteras)
            seccion(L("Álbumes"), library.albums.map {
                Elemento(clave: "playlist:\($0.id.uuidString)", nombre: $0.name, tipo: .album, detalle: $0.album?.artist, cosa: .playlist($0))
            }, vacio: L("No tienes álbumes guardados."), enteras: enteras)
            seccion(L("Favoritas"), library.favorites.map {
                Elemento(clave: "favorite:\($0.id)", nombre: $0.title, tipo: .favorita, detalle: $0.artist.nilSiVacio, cosa: .cancion($0))
            }, vacio: L("No tienes favoritas."), enteras: enteras, tope: verTodas ? .max : 30)
            seccion(L("Artistas que sigues"), library.followedArtists.map {
                Elemento(clave: "artist:\($0.browseId)", nombre: $0.name, tipo: .artista, detalle: nil, cosa: .artista($0))
            }, vacio: L("No sigues a ningún artista."), enteras: enteras)
        }
        .navigationTitle(L("Lo que se sincroniza")).navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func seccion(_ titulo: String, _ elementos: [Elemento], vacio: String, enteras: Set<String>, tope: Int = .max) -> some View {
        Section {
            ForEach(elementos.prefix(tope)) { e in
                let sub = sync.soloAqui.contains(e.clave) ? L("Sólo en este dispositivo")
                    : enteras.contains(e.clave) ? L("Sólo en este dispositivo: va con su carpeta") : e.detalle
                Menu { menu(e, enteras: enteras) } label: {
                    HStack(spacing: 12) {
                        portada(e)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.nombre).foregroundStyle(Color(uiColor: .label))
                            if let sub { Text(sub).font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel)) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "ellipsis").foregroundStyle(Color(uiColor: .tertiaryLabel)).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("sinc-\(e.clave)")
            }
            if elementos.count > tope { Button(L("Ver las {0}", String(elementos.count))) { verTodas = true } }
        } header: { Text(titulo) } footer: { if elementos.isEmpty { Text(vacio) } }
    }

    /// Pulir 2 #1: la imagen de cada fila, con los mismos componentes que la Biblioteca: la carpeta con su mosaico o su
    /// icono (`FolderCover`), la playlist y el álbum con su portada, su icono y color o su carátula (`PlaylistCover`), la
    /// favorita con su carátula y el artista con su foto, redonda como en Artistas › Siguiendo (sin foto, su silueta).
    /// Igual que `Portada` en Android.
    @ViewBuilder
    private func portada(_ e: Elemento) -> some View {
        let lado: CGFloat = 44
        let forma = RoundedRectangle(cornerRadius: Tokens.Radius.artworkSmall, style: .continuous)
        switch e.cosa {
        case .carpeta(let f): FolderCover(folder: f).frame(width: lado, height: lado)
        case .playlist(let p): PlaylistCover(playlist: p, size: lado, radius: Tokens.Radius.artworkSmall)
        case .cancion(let c): CoverImage(url: c.thumb(132)).frame(width: lado, height: lado).clipShape(forma)
        case .artista(let a):
            if let t = a.thumbnail { CoverImage(url: t).frame(width: lado, height: lado).clipShape(Circle()) }
            else {
                Circle().fill(Color(uiColor: .systemFill)).frame(width: lado, height: lado)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(Color(uiColor: .secondaryLabel)))
            }
        case nil: Image(systemName: e.tipo.icono).foregroundStyle(Color(uiColor: .secondaryLabel)).frame(width: lado)
        }
    }

    /// El menú de una fila: «No sincronizar esto» (o «Volver a sincronizar») y «Quitar de todos mis dispositivos», que
    /// pide la confirmación de eliminar. Lo que va con su carpeta sólo explica por qué. Igual que `menuDe` en Android.
    @ViewBuilder
    private func menu(_ e: Elemento, enteras: Set<String>) -> some View {
        let marcada = sync.soloAqui.contains(e.clave)
        if enteras.contains(e.clave) && !marcada {
            Text(L("Va con su carpeta, que no se sincroniza. Para volver a sincronizarlo, vuelve a sincronizar la carpeta."))
        } else if marcada {
            // La explicación, de subtítulo del botón (suelta, el menú la cortaba a tres líneas).
            Button { sync.soloEnEsteMovil(e.clave, false) } label: {
                Text(L("Volver a sincronizar"))
                Text(L("Ahora sólo está en este dispositivo. Si lo vuelves a sincronizar, pasará a tus otros dispositivos."))
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        } else {
            Button { sync.soloEnEsteMovil(e.clave, true) } label: {
                Text(L("No sincronizar esto"))
                Text(L("Se queda sólo en este dispositivo; en los demás no se toca."))
                Image(systemName: "icloud.slash")
            }
        }
        Divider()
        Button(role: .destructive) {
            AppAlert.confirm(L("¿Quitar «{0}» de todos tus dispositivos?", e.nombre), message: e.tipo.aviso, confirm: L("Quitar")) { quitar(e) }
        } label: { Label(L("Quitar de todos mis dispositivos"), systemImage: "trash") }
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

// MARK: Raíz y navegación (Pulir 2 · notas de la opción A #1 y #2)

/// Las pantallas de Ajustes › Cuenta: como mucho dos niveles (Cuenta › una de estas). El mapa, en
/// `version 3/ESTADO.md` y DECISIONS 101. El título de cada una es la fila que la abre. Igual que `PantallaCuenta` en
/// Android.
enum PantallaCuenta: Hashable {
    case crear, clave, entrar, qrNuevo, anadirMovil, sincronizado, comprobar, cerrarSesion, borrar, terminos
}

/// Cómo se va de Cuenta a una de sus pantallas. `ir` la abre encima de Cuenta (la flecha y el gesto atrás vuelven a
/// Cuenta); `cambiar` sustituye la que está abierta por otra, como «Crear cuenta» › «Tu clave de recuperación» (atrás
/// vuelve a Cuenta, no a «Crear cuenta»). Para volver a Cuenta al acabar, cada pantalla usa `dismiss`. Igual que
/// `NavCuenta` en Android.
struct NavCuenta {
    var ir: (PantallaCuenta) -> Void = { _ in }
    var cambiar: (PantallaCuenta) -> Void = { _ in }
}
private struct NavCuentaClave: EnvironmentKey { static let defaultValue = NavCuenta() }
extension EnvironmentValues {
    var navCuenta: NavCuenta {
        get { self[NavCuentaClave.self] }
        set { self[NavCuentaClave.self] = newValue }
    }
}

/// Si se está viendo alguna pantalla de la cuenta (la cápsula de la sync no sale ahí: la fila de la sync ya lo dice y
/// la cápsula tapaba el título; captura 69) y el aviso corto de abajo («Has cerrado sesión…»).
@MainActor
final class CuentaEnPantalla: ObservableObject {
    static let shared = CuentaEnPantalla()
    @Published fileprivate(set) var abiertas = 0
    @Published var aviso: String?
    var visible: Bool { abiertas > 0 }
}
private struct EnLaCuenta: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { CuentaEnPantalla.shared.abiertas += 1 }
            .onDisappear { CuentaEnPantalla.shared.abiertas = Swift.max(0, CuentaEnPantalla.shared.abiertas - 1) }
    }
}
extension View { fileprivate func enLaCuenta() -> some View { modifier(EnLaCuenta()) } }

/// Sólo capturas (56b y 67b): «Qué ganas con la cuenta» o «Seguridad y cuenta» ya abiertos y la página bajada hasta lo
/// último (`id("fin")`), como `seguridadAbiertaCapturas` de Android.
enum CuentaCapturas {
    /// 56b: «Qué ganas con la cuenta» abierto.
    static var queGanas: Bool { Demo.current?.route == .cuentaSinCrearAbierto }
    /// 67b: «Seguridad y cuenta» abierto.
    static var seguridad: Bool { Demo.current?.route == .cuentaSeguridad }
}
private struct AlFinalEnCapturas<Contenido: View>: View {
    let si: Bool
    @ViewBuilder let contenido: () -> Contenido
    var body: some View {
        ScrollViewReader { proxy in
            contenido().task {
                guard si else { return }
                try? await Task.sleep(nanoseconds: 600_000_000)
                proxy.scrollTo("fin", anchor: .bottom)
            }
        }
    }
}

struct CuentaView: View {
    @ObservedObject private var cuenta = CuentaPear.shared
    @ObservedObject private var enCuenta = CuentaEnPantalla.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var abierta: PantallaCuenta?

    private var nav: NavCuenta { NavCuenta(ir: { abierta = $0 }, cambiar: { abierta = $0 }) }

    var body: some View {
        Group {
            if cuenta.tieneCuenta { CuentaConectada() } else { CuentaSinCrear() }
        }
        .navigationTitle(L("Cuenta"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
        .environment(\.navCuenta, nav)
        // Una sola pantalla encima de Cuenta (dos niveles como mucho): la flecha y el gesto atrás vuelven aquí.
        // `cambiar` cambia la de encima sin apilar otra (`.id`: empieza de cero).
        .navigationDestination(isPresented: Binding(get: { abierta != nil }, set: { if !$0 { abierta = nil } })) {
            if let p = abierta { CuentaPantalla(p).id(p).environment(\.navCuenta, nav) }
        }
        .enLaCuenta()
        .overlay(alignment: .bottom) {
            if let texto = enCuenta.aviso {
                Text(texto).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thickMaterial, in: Capsule())
                    .padding(.bottom, 96).padding(.horizontal, 16)
                    .transition(.opacity)
                    .accessibilityIdentifier("avisoCuenta")
                    .task {
                        UIAccessibility.post(notification: .announcement, argument: texto)
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        enCuenta.aviso = nil
                    }
            }
        }
        .animation(reduceMotion ? nil : Animation.uiEaseOut(0.25), value: enCuenta.aviso)
    }
}

/// Una pantalla de la cuenta por su nombre (también la usan las capturas, `Screenshots.swift`).
struct CuentaPantalla: View {
    let pantalla: PantallaCuenta
    init(_ pantalla: PantallaCuenta) { self.pantalla = pantalla }
    var body: some View {
        Group {
            switch pantalla {
            case .crear: CrearCuentaView()
            case .clave: ClaveNuevaView()
            case .entrar: EntrarConClaveView()
            case .qrNuevo: QrNuevoView()
            case .anadirMovil: AnadirMovilView()
            case .sincronizado: SincronizadoView()
            case .comprobar: ComprobarClaveView()
            case .cerrarSesion: CerrarSesionView()
            case .borrar: BorrarCuentaView()
            case .terminos: TerminosNuevosView()
            }
        }
        .enLaCuenta()
    }
}

/// Una fila de la cuenta: icono, título, la frase de debajo y, a la derecha, el valor, «⋯» (abre un menú) o la flecha
/// (abre una pantalla). Colores del sistema explícitos: dentro de un botón, `.primary` saldría con el tinte (shu) y la
/// pantalla tendría varios (COLOR.md). Igual que `FormRow` en Android.
private struct Fila: View {
    let titulo: String
    var subtitulo: String? = nil
    var icono: String? = nil
    var valor: String? = nil
    var rojo = false
    var flecha = false
    var mas = false
    var body: some View {
        HStack(spacing: 12) {
            if let icono {
                Image(systemName: icono).font(.body).frame(width: 28)
                    .foregroundStyle(rojo ? Color.red : Color(uiColor: .label)).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).foregroundStyle(rojo ? Color.red : Color(uiColor: .label))
                if let subtitulo { Text(subtitulo).font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel)) }
            }
            Spacer(minLength: 0)
            if let valor { Text(valor).foregroundStyle(Color(uiColor: .secondaryLabel)).lineLimit(1) }
            if mas { Image(systemName: "ellipsis").foregroundStyle(Color(uiColor: .tertiaryLabel)).accessibilityHidden(true) }
            if flecha {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel)).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// «Hace algo y deja el error» de cada pantalla, con el texto de `CuentaPear.mensajeDe`.
@MainActor private func intentar(_ fallo: Binding<String?>, _ trabajo: @escaping () async throws -> Void) {
    Task {
        do { try await trabajo(); fallo.wrappedValue = nil }
        catch is CancellationError {} catch { fallo.wrappedValue = CuentaPear.mensajeDe(error) }
    }
}

// MARK: Sin cuenta (opción A «Ordenar», lo decidió Toxbox el 25-11)

private struct CuentaSinCrear: View {
    @Environment(\.navCuenta) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var abierto = CuentaCapturas.queGanas
    var body: some View {
        AlFinalEnCapturas(si: CuentaCapturas.queGanas) { formulario }
    }

    private var formulario: some View {
        Form {
            // «Crear cuenta» se ve sin bajar, en una tarjeta corta con la mascota: el único shu de la pantalla.
            Section {
                HStack(spacing: 14) {
                    Image("mascota-con-cascos").resizable().scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Tu música en todos tus dispositivos")).font(.title3.bold())
                        Text(L("Opcional y gratis. Va cifrada: ni nosotros podemos leerla."))
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
                .listRowSeparator(.hidden)
                .accessibilityElement(children: .combine)
                Button(L("Crear cuenta")) { nav.ir(.crear) }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 14, trailing: 16))
                    .accessibilityIdentifier("crearCuenta")
            }
            // PULIR #2: quien ya tiene la cuenta en otro dispositivo encuentra aquí cómo entrar, sin palabras técnicas.
            Section {
                Button { nav.ir(.qrNuevo) } label: {
                    Fila(titulo: L("Entrar con otro dispositivo"), subtitulo: L("Escanea un código con el que ya tiene tu cuenta."),
                         icono: "qrcode", flecha: true)
                }
                .accessibilityIdentifier("entrarDesdeOtro")
                Button { nav.ir(.entrar) } label: {
                    Fila(titulo: L("Usar mi clave de recuperación"), subtitulo: L("La que apuntaste al crear la cuenta."),
                         icono: "key", flecha: true)
                }
                .accessibilityIdentifier("entrarConClave")
            } header: { Text(L("¿Ya tienes cuenta en otro dispositivo?")) }
            // Plegado: por qué crearla (los mismos puntos que AccountPitch de la guía inicial). El `DisclosureGroup` dice
            // a VoiceOver si está abierto, como `FoldRow` en Android.
            Section {
                DisclosureGroup(isExpanded: $abierto.animation(reduceMotion ? nil : Animation.uiEaseOut(0.25))) {
                    PuntosCuenta().padding(.bottom, 8).id("fin")
                } label: {
                    // El identificador en la fila: en el `DisclosureGroup` pisaría los de lo de dentro.
                    Fila(titulo: L("Qué ganas con la cuenta"),
                         subtitulo: abierto ? nil : L("Copia cifrada, cambiar de dispositivo y ventajas que vienen"), icono: "info.circle")
                        .accessibilityIdentifier("queGanas")
                }
            }
        }
    }
}

// MARK: Crear cuenta (§7.2: dos casillas obligatorias y la telemetría aparte)

struct CrearCuentaView: View {
    @Environment(\.navCuenta) private var nav
    @State private var terminos = false
    @State private var edad = false
    @State private var telemetria = false
    /// Términos y privacidad en el idioma de la app (lo decidió Toxbox, orden 9 del 18-11).
    private var legal: URL { CuentaViewsLegal.url }

    var body: some View {
        Form {
            Cabecera(pose: "saltando", titulo: L("Tu cuenta, sin contraseña"),
                     texto: L("Nada que recordar ni que te puedan robar. Tu biblioteca viaja cifrada: sólo tus dispositivos pueden leerla."))
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
                    CuentaPear.shared.pendiente = CuentaPear.shared.borrador()
                    // «Tu clave de recuperación» sustituye a esta pantalla: atrás vuelve a Cuenta.
                    nav.cambiar(.clave)
                }
                .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                .disabled(!(terminos && edad))
                .accessibilityIdentifier("botonCrear")
            }
        }
        .navigationTitle(L("Crear cuenta")).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Tu clave de recuperación: se enseña UNA vez y se confirma un grupo (§3)

struct ClaveNuevaView: View {
    private let borrador: CuentaPear.Borrador
    @Environment(\.dismiss) private var dismiss
    @State private var confirmando = false
    @State private var grupo = Int.random(in: 1...6)
    @State private var escrito = ""
    @State private var fallo = false
    @State private var creando = false
    @State private var error: String?
    @State private var copiada = false

    /// El borrador de «Crear cuenta» (`CuentaPear.pendiente`); sin él (capturas), uno nuevo.
    init(borrador: CuentaPear.Borrador? = nil) {
        if let b = borrador ?? CuentaPear.shared.pendiente { self.borrador = b }
        else { let b = CuentaPear.shared.borrador(); CuentaPear.shared.pendiente = b; self.borrador = b }
    }

    var body: some View {
        Form {
            // Orden 11: qué es, para qué sirve y qué hay que hacer, sin pensar.
            Cabecera(pose: "brazos-cruzados", titulo: L("Tu clave de recuperación"),
                     texto: L("Es la llave de tu cuenta. Si pierdes este dispositivo, con ella entras desde otro. Apúntala en papel y guárdala: no se puede ver otra vez ni cambiar por otra."))
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
        .navigationTitle(L("Tu clave de recuperación")).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(creando)
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
            do {
                try await CuentaPear.shared.crear(borrador)
                CuentaPear.shared.pendiente = nil
                // El aviso de la app (el mismo que los de la Biblioteca) y de vuelta a Cuenta, como Android.
                AppAlert.show(L("Cuenta creada"), message: L("Sólo tienes este dispositivo en tu cuenta. Si lo pierdes, sólo podrás entrar con tu clave de recuperación."))
                dismiss()
            }
            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
        }
    }
}

// MARK: Usar mi clave de recuperación (§7.3 punto 1)

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
        .navigationTitle(L("Usar mi clave de recuperación")).navigationBarTitleDisplayMode(.inline)
        .onChange(of: clave) { _ in error = nil }
    }

    private func entrar() {
        // Sin llamar al servidor: «Esa clave no es válida» (§3).
        guard CuentaCripto.leerClave(clave) != nil else { error = CuentaPear.ErrorCuenta(codigo: "clave_invalida").mensaje; return }
        entrando = true
        Task {
            defer { entrando = false }
            do { try await CuentaPear.shared.entrarConClave(clave); dismiss() }
            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
        }
    }
}

// MARK: Con cuenta (opción A «Ordenar»): avisos, la sync, tus dispositivos, lo que viaja y, plegado, lo demás

private struct CuentaConectada: View {
    @Environment(\.navCuenta) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var cuenta = CuentaPear.shared
    @ObservedObject private var sync = SyncBiblioteca.shared
    @AppStorage("accountName") private var nombreCuenta = ""
    @State private var error: String?
    @State private var abierto = CuentaCapturas.seguridad

    var body: some View {
        AlFinalEnCapturas(si: CuentaCapturas.seguridad && cuenta.tieneCuenta) { formulario }
            .task { intentar($error) { try await cuenta.cargar() } }
    }

    private var formulario: some View {
        let n = cuenta.dispositivos.count
        let lleno = n >= 10
        return Form {
            if let fecha = cuenta.borrarEn {
                Section {
                    Estado(ok: false, texto: L("Se va a borrar tu cuenta el {0}", Date(timeIntervalSince1970: TimeInterval(fecha))
                        .formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: I18n.current == "va" ? "ca" : I18n.current)))))
                    Button { intentar($error) { try await cuenta.cancelarBorrado() } } label: { Label(L("Cancelar el borrado"), systemImage: "arrow.uturn.backward") }
                }
            }
            if cuenta.terminosPendientes {
                Section {
                    Text(L("Hay términos nuevos. Para seguir usando la cuenta, léelos y acéptalos."))
                    Button { nav.ir(.terminos) } label: { Label(L("Ver los términos nuevos"), systemImage: "doc.text") }
                }
            }
            // La biblioteca de la cuenta (2-D, sync.md §4 y §5.4): lo que hay que contar una vez.
            if let aviso = sync.aviso {
                Section {
                    Text(aviso)
                    Button { sync.avisoVisto() } label: { Label(L("Entendido"), systemImage: "checkmark") }
                }
            }
            ForEach(cuenta.avisos) { a in
                Section {
                    switch a.aviso {
                    case .nuevo(let id):
                        Text(L("Se ha añadido \"{0}\" a tu cuenta. ¿No has sido tú? Quítalo", a.nombre))
                        Button(role: .destructive) { intentar($error) { try await cuenta.quitar(id); cuenta.avisoVisto(id) } } label: {
                            Label(L("Quitar"), systemImage: "minus.circle")
                        }
                        Button { cuenta.avisoVisto(id) } label: { Label(L("He sido yo"), systemImage: "checkmark") }
                    case .quitado(let id):
                        Text(L("Se añadió \"{0}\" a tu cuenta y ya se ha quitado. ¿No has sido tú? Revisa tus dispositivos", a.nombre))
                        Button { cuenta.avisoVisto(id) } label: { Label(L("Entendido"), systemImage: "checkmark") }
                    }
                }
            }
            // Un recordatorio cada tantos meses, no un segundo menú: lleva a «Comprobar mi clave» (DECISIONS 101).
            if cuenta.tocaSugerirClave {
                Section {
                    Text(L("¿Sigues teniendo tu clave de recuperación? Compruébala un momento."))
                    Button { nav.ir(.comprobar) } label: { Label(L("Comprobar ahora"), systemImage: "key") }
                    Button { cuenta.posponerSugerencia() } label: { Label(L("Ahora no"), systemImage: "clock") }
                }
            }
            if let error { Section { Estado(ok: false, texto: error) } }

            // 1. Cómo va la sincronización, con «Comprobar ahora» (Pulir 2 #3). Cápsula neutra: no es el shu de la pantalla.
            Section {
                let e = sync.vista.estado()
                let v = sync.vista
                let comprobando = v.fase != .quieta
                let alDia = !comprobando && !v.bloqueado && !v.sinRed && !v.pendiente && v.ultimaOk > 0 && n > 1
                // Sin envolver en otro Button: en un Form, un botón dentro de otro se lleva el toque de la fila entera.
                HStack(spacing: 8) {
                    Image(systemName: e.icono).foregroundStyle(Color(uiColor: .label)).frame(width: 28).accessibilityHidden(true)
                    // El identificador en los textos, no en la fila: en la fila tapaba el de «Comprobar ahora».
                    // «Comprobar ahora» al lado si el texto cabe entero en una línea; si no (letra grande, idiomas
                    // largos), debajo: nunca parte «Pendiente de subir» (revisión del bloque 2). Igual que
                    // `TextOrTrailingBelow` en Android.
                    VStack(alignment: .leading, spacing: 2) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                Text(e.texto).foregroundStyle(Color(uiColor: .label)).fixedSize()
                                    .accessibilityIdentifier("estadoSync")
                                Spacer(minLength: 0)
                                BotonComprobar(comprobando: comprobando) { sync.alEntrar() }
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(e.texto).foregroundStyle(Color(uiColor: .label)).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("estadoSync")
                                BotonComprobar(comprobando: comprobando) { sync.alEntrar() }
                            }
                        }
                        if alDia {
                            Text(L("Tu música está igual en tus {0} dispositivos", String(n)))
                                .font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if !comprobando { sync.alEntrar() } }
            } footer: {
                // Modo fútbol: la explicación en el pie (junto al botón quedaba en una columna estrecha). Igual en Android.
                if let d = sync.vista.detalle { Text(d) }
            }

            // 2. Tus dispositivos: tocar uno abre su menú (cambiar el nombre; quitar, si no es este), y «Añadir un
            // dispositivo», el único shu de la pantalla.
            Section {
                ForEach(cuenta.dispositivos) { d in FilaDispositivo(d: d, error: $error) }
                Button { nav.ir(.anadirMovil) } label: { Label(L("Añadir un dispositivo"), systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .disabled(lleno)
                    .accessibilityIdentifier("anadirDispositivo")
            } header: { Text(L("Tus dispositivos")) } footer: {
                Text(lleno ? L("Ya hay 10 dispositivos en tu cuenta. Quita uno antes")
                     : cuenta.soloEsteMovil ? L("Sólo tienes este dispositivo en tu cuenta. Si lo pierdes, sólo podrás entrar con tu clave de recuperación.")
                     : L("En el nuevo, abre Jiyu Pulse, elige «Entrar con otro dispositivo» y escanea el código que te enseña."))
            }

            // 3. Lo que viaja (PULIR #5).
            Section {
                Button { nav.ir(.sincronizado) } label: { Fila(titulo: L("Lo que se sincroniza"), icono: "checklist", flecha: true) }
                    .accessibilityIdentifier("loQueSeSincroniza")
            } footer: { Text(L("Tu biblioteca viaja cifrada: el servidor no puede leerla.")) }

            // 4. Plegado: la clave, el nombre, los términos, quitar los demás, cerrar sesión y borrar. Como «Avanzado».
            Section {
                DisclosureGroup(isExpanded: $abierto.animation(reduceMotion ? nil : Animation.uiEaseOut(0.25))) {
                    Button { nav.ir(.comprobar) } label: { Fila(titulo: L("Comprobar mi clave"), icono: "key", flecha: true) }
                        .accessibilityIdentifier("comprobarMiClave")
                    // PULIR #6: el nombre de la cuenta, sólo para ti (cifrado). El aviso con campo, como «Renombrar».
                    Button {
                        NamePrompt.ask(L("Nombre de la cuenta"), initial: nombreCuenta, confirm: L("Guardar"),
                                       message: L("Para que reconozcas tu cuenta en tus dispositivos. Hasta 40 caracteres; vacío, sin nombre."),
                                       placeholder: L("Por ejemplo, Mi música"), valid: { LibraryFile.nombreCuentaValido($0) != nil }) { t in
                            if let v = LibraryFile.nombreCuentaValido(t) { nombreCuenta = v }
                        }
                    } label: {
                        Fila(titulo: L("Nombre de la cuenta"), icono: "person.text.rectangle", valor: nombreCuenta.isEmpty ? L("Sin nombre") : nombreCuenta, flecha: true)
                    }
                    .accessibilityIdentifier("nombreCuenta")
                    Link(destination: CuentaViewsLegal.url) { Fila(titulo: L("Términos y privacidad"), icono: "doc.text", flecha: true) }
                    // Si te han robado uno: sale todo de golpe menos este (antes, en la pantalla Dispositivos, que ya no hay).
                    if n > 1 {
                        Button {
                            NamePrompt.ask(L("Quitar todos los demás dispositivos"), confirm: L("Quitar todos"),
                                           message: L("Escribe tu clave de recuperación para confirmarlo."),
                                           placeholder: L("Tu clave de recuperación"), secret: true, destructive: true) { k in
                                intentar($error) { try await cuenta.quitarLosDemas(clave: k) }
                            }
                        } label: {
                            Fila(titulo: L("Quitar todos los demás dispositivos"), subtitulo: L("Si te han robado uno. Hace falta tu clave de recuperación."),
                                 icono: "minus.circle", rojo: true)
                        }
                        .accessibilityIdentifier("quitarLosDemas")
                    }
                    Button { nav.ir(.cerrarSesion) } label: {
                        Fila(titulo: L("Cerrar sesión"), icono: "rectangle.portrait.and.arrow.right", flecha: true)
                    }
                    .accessibilityIdentifier("cerrarSesion")
                    Button { nav.ir(.borrar) } label: {
                        Fila(titulo: L("Borrar cuenta"), icono: "person.crop.circle.badge.minus", rojo: true, flecha: true)
                    }
                    .accessibilityIdentifier("borrarCuenta")
                    .id("fin")
                } label: {
                    Fila(titulo: L("Seguridad y cuenta"),
                         subtitulo: abierto ? nil : L("Clave de recuperación, nombre, términos, cerrar sesión y borrar la cuenta"), icono: "shield")
                        .accessibilityIdentifier("seguridadYCuenta")
                }
            } footer: {
                if abierto {
                    Text(L("El nombre de la cuenta es sólo para ti: va cifrado y sólo lo ven tus dispositivos. No es un nombre de usuario: nadie te puede buscar por él."))
                }
            }
        }
        .refreshable { intentar($error) { try await cuenta.cargar() } }
    }
}

/// Un dispositivo de «Tus dispositivos». Tocarlo abre su menú (`Menu`, anclado a la fila como el de una playlist):
/// «Cambiar nombre» (el aviso con campo, como «Renombrar») y, si no es este, «Quitar de la cuenta» (con la confirmación
/// de eliminar). Este dispositivo sale con «Cerrar sesión», en «Seguridad y cuenta». Igual que `FilaDispositivo` en Android.
private struct FilaDispositivo: View {
    let d: CuentaPear.Dispositivo
    @Binding var error: String?
    @ObservedObject private var cuenta = CuentaPear.shared

    var body: some View {
        Menu {
            Button {
                NamePrompt.ask(L("Cambiar nombre"), initial: d.nombre, confirm: L("Guardar"),
                               message: L("Así lo verás en tus dispositivos. De 1 a 40 caracteres."),
                               placeholder: L("Nombre del dispositivo"), valid: { CuentaCripto.nombreValido($0) != nil }) { n in
                    intentar($error) { try await cuenta.renombrar(d.id, a: n) }
                }
            } label: { Label(L("Cambiar nombre"), systemImage: "pencil") }
            if !d.este {
                Button(role: .destructive) {
                    AppAlert.confirm(L("¿Quitar «{0}»?", d.nombre), message: L("Ese dispositivo ya no podrá entrar en tu cuenta."), confirm: L("Quitar")) {
                        intentar($error) { try await cuenta.quitar(d.id) }
                    }
                } label: { Label(L("Quitar de la cuenta"), systemImage: "minus.circle") }
            }
        } label: {
            Fila(titulo: d.nombre, subtitulo: d.este ? L("Este dispositivo") : visto, icono: d.plataforma == "ios" ? "iphone" : "smartphone", mas: true)
        }
        .accessibilityIdentifier("disp-\(d.id)")
    }

    private var visto: String {
        guard let v = d.visto else { return L("Nunca") }
        // Fecha en el idioma de la app (no en el del sistema), igual que Android: «Visto 17 nov 2025».
        let idioma = I18n.current == "va" ? "ca" : I18n.current
        return L("Visto {0}", Date(timeIntervalSince1970: TimeInterval(v))
            .formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: idioma))))
    }
}

/// Términos nuevos (antes una hoja): las dos casillas y «Aceptar», el shu de la pantalla. Vuelve a Cuenta.
struct TerminosNuevosView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var terminos = false
    @State private var edad = false
    @State private var enviando = false
    @State private var error: String?
    var body: some View {
        Form {
            Cabecera(pose: "pensando", titulo: L("Términos nuevos"), texto: L("Hay términos nuevos. Para seguir usando la cuenta, léelos y acéptalos."))
            Section {
                Casilla(marcada: $terminos, titulo: L("Acepto los Términos de uso y la Política de privacidad"),
                        enlace: (L("Leer los textos"), CuentaViewsLegal.url))
                    .accessibilityIdentifier("casillaTerminosNuevos")
                Casilla(marcada: $edad, titulo: L("Tengo 14 años o más")).accessibilityIdentifier("casillaEdadNuevos")
                if let error { Estado(ok: false, texto: error) }
            }
            Section {
                Button(L("Aceptar")) {
                    enviando = true
                    Task {
                        defer { enviando = false }
                        do { try await CuentaPear.shared.aceptarTerminos(); dismiss() }
                        catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: true)).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                .disabled(!(terminos && edad) || enviando)
                .accessibilityIdentifier("botonTerminos")
            }
        }
        .navigationTitle(L("Términos nuevos")).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Comprobar mi clave (§7.3 punto 7): la clave entera, sin red

struct ComprobarClaveView: View {
    @State private var clave = ""
    @State private var resultado: Bool?

    var body: some View {
        Form {
            Cabecera(pose: "pensando", titulo: L("Comprobar mi clave"), texto: L("Escríbela entera. Se comprueba en este dispositivo: no se envía a ningún sitio."))
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

// MARK: Cerrar sesión (Pulir 2 · notas de la opción A #4)

/// Este dispositivo sale de la cuenta y la biblioteca se queda aquí, sin sincronizar. Si es el único de la cuenta, un
/// aviso grande: para volver a entrar hará falta la clave. Pide presencia (`CuentaPear.cerrarSesion`). Sin shu: no es la
/// acción que se quiere empujar. Igual que `CerrarSesion` en Android.
struct CerrarSesionView: View {
    @ObservedObject private var cuenta = CuentaPear.shared
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        let solo = cuenta.soloEsteMovil
        Form {
            Cabecera(pose: "corriendo", titulo: L("Cerrar sesión en este dispositivo"),
                     texto: L("Este dispositivo sale de tu cuenta. Tu biblioteca se queda aquí, pero ya no se sincroniza. No se borra nada."))
            if solo {
                // Aviso grande: icono naranja (aviso, no error) + texto en `label`; el color nunca es la única pista.
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(.orange).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Es tu único dispositivo")).font(.title3.bold())
                            Text(L("Para volver a entrar en tu cuenta hará falta tu clave de recuperación. Sin ella, la cuenta y lo que hay en la nube se pierden."))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(L("Puedes comprobarla antes en Seguridad y cuenta › Comprobar mi clave."))
                                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("avisoUnico")
                }
            }
            if let error { Section { Estado(ok: false, texto: error) } }
            Section {
                Button {
                    AppAlert.confirm(L("¿Cerrar sesión en este dispositivo?"),
                                     message: solo ? L("Es tu único dispositivo: sólo podrás volver a entrar con tu clave de recuperación.")
                                                   : L("Saldrá de tu cuenta. Tu biblioteca se queda aquí, sin sincronizar."),
                                     confirm: L("Cerrar sesión")) { cerrar() }
                } label: { Fila(titulo: L("Cerrar sesión"), icono: "rectangle.portrait.and.arrow.right", rojo: true) }
                .accessibilityIdentifier("botonCerrarSesion")
            } header: {
                // Antes del botón, como en Android: primero lo que pasa, después la acción.
                if !solo {
                    Text(L("Tus otros dispositivos siguen en la cuenta y verán que este ya no está."))
                        .font(.footnote).textCase(nil).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L("Cerrar sesión")).navigationBarTitleDisplayMode(.inline)
    }

    private func cerrar() {
        Task {
            do {
                try await cuenta.cerrarSesion()
                CuentaEnPantalla.shared.aviso = L("Has cerrado sesión. Tu biblioteca sigue aquí.")
                dismiss()
            }
            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
        }
    }
}

// MARK: Borrar cuenta (§7.3 punto 6)

struct BorrarCuentaView: View {
    @ObservedObject private var cuenta = CuentaPear.shared
    @Environment(\.dismiss) private var dismiss
    @State private var clave = ""
    @State private var error: String?

    var body: some View {
        Form {
            Cabecera(pose: "de-espaldas", titulo: L("Borrar tu cuenta"),
                     texto: L("Se borran tu cuenta y todo lo que hay en la nube. Lo que tienes en tus dispositivos se queda."))
            Section {
                CampoClave(texto: $clave, titulo: L("Tu clave de recuperación (opcional)"))
            } footer: {
                Text(L("Con tu clave se borra al momento. Sin ella, se borra dentro de 14 días y lo verás en todos tus dispositivos, por si no has sido tú."))
            }
            if let error { Section { Estado(ok: false, texto: error) } }
            Section {
                Button {
                    AppAlert.confirm(L("¿Borrar tu cuenta?"), message: L("No se puede deshacer."), confirm: L("Borrar la cuenta")) { borrar() }
                } label: { Fila(titulo: clave.isEmpty ? L("Borrar dentro de 14 días") : L("Borrar ahora"), icono: "trash", rojo: true) }
                .accessibilityIdentifier("botonBorrar")
            }
        }
        .navigationTitle(L("Borrar cuenta")).navigationBarTitleDisplayMode(.inline)
    }

    private func borrar() {
        let c = clave
        Task {
            do { try await cuenta.borrar(clave: c.isEmpty ? nil : c); dismiss() }
            catch is CancellationError {} catch { self.error = CuentaPear.mensajeDe(error) }
        }
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
            PuntosCuenta()
        }
        .padding(.horizontal, 20).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
        .accessibilityElement(children: .combine)
    }
}

/// Lo que ganas con la cuenta: en la guía inicial (`AccountPitch`) y plegado en Ajustes › Cuenta sin cuenta. Igual que
/// `PuntosCuenta` en Android.
struct PuntosCuenta: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            point("lock.fill", 5, L("Tu biblioteca, cifrada en la nube"), L("Sólo tú tienes la clave. Ni siquiera nosotros podemos leerla."))
            point("iphone.gen3", 2, L("Pásala a otro dispositivo"), L("Playlists y favoritos en un minuto, también entre iPhone y Android."))
            point("heart.fill", 0, L("Ayudas a mejorar Jiyu Pulse"), L("Saber cuántos sois nos dice dónde poner el esfuerzo."))
            point("sparkles", 4, L("Muy pronto, ventajas"), L("Estamos preparando cosas solo para quien tenga cuenta. Te avisaremos en Avisos."))
        }
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
