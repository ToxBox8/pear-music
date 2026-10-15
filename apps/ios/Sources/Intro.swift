import SwiftUI

// MARK: - Recorrido sobre la app real (Fase 2.1)
/// Mismos pasos y textos que `TourOverlay` en Android. Diferencia aceptada: la barra de pestañas de iOS es del
/// sistema y no deja medir cada botón, así que en los pasos de pestañas se resalta la barra entera y el texto dice
/// cuál tocar; el Jam y Ajustes (arriba) sí llevan su foco exacto.
final class TourTargets: ObservableObject {
    static let shared = TourTargets()
    @Published var rects: [String: CGRect] = [:]
}

extension View {
    /// Marca un elemento que el recorrido puede resaltar (coordenadas globales).
    func tourTarget(_ key: String) -> some View {
        background(GeometryReader { g in
            Color.clear
                .onAppear { TourTargets.shared.rects[key] = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { TourTargets.shared.rects[key] = $0 }
                // Fuera de la pantalla: nada de focos sobre un sitio que ya no existe (guía de Ajustes, 1.1).
                .onDisappear { TourTargets.shared.rects[key] = nil }
        })
    }
}

struct TourOverlay: View {
    /// Cambia de pestaña (clave de `TabOrder`: "discover", "home"…).
    let select: (String) -> Void
    let onDone: () -> Void
    @ObservedObject private var targets = TourTargets.shared
    @AppStorage("showDiscover") private var showDiscover = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var pulse = false

    private struct Step { let key: String; let tab: String?; let title: String; let text: String }
    private let steps = [
        Step(key: "tab", tab: "discover", title: L("Descubrir"), text: L("Fragmentos de canciones que te pueden gustar, a pantalla completa. Desliza para la siguiente y toca dos veces para «Me gusta». Si no lo usas, deslízalo a la izquierda en Ajustes › Aspecto › Pestañas. Toca la pestaña Descubrir.")),
        Step(key: "tab", tab: "home", title: L("Inicio"), text: L("Lo último que has escuchado, radios hechas para ti, lo nuevo de tus artistas y lo que fijes arriba. La campana trae los avisos de Pear Music. Toca la pestaña Inicio.")),
        Step(key: "jam", tab: nil, title: L("Jam"), text: L("Una playlist compartida con quien esté contigo, aunque tenga un Android. Escanea el QR para entrar al momento, o escribe el código.")),
        Step(key: "tab", tab: "library", title: L("Biblioteca"), text: L("Tus playlists, favoritos y descargas, también sin conexión. Fija arriba lo que más escuches con la chincheta y toca un artista para ver toda su discografía. Toca la pestaña Biblioteca.")),
        Step(key: "tab", tab: "settings", title: L("Ajustes"), text: L("Tema, reproductor (casete, vinilo, Air), tu cuenta opcional, tus datos y ayuda.")),
    ]

    var body: some View {
        GeometryReader { g in
            let origin = g.frame(in: .global).origin
            let visible = steps.filter { ($0.tab != "discover" || showDiscover) && ($0.key == "tab" || targets.rects[$0.key].map { !$0.isEmpty } == true) }
            if index < visible.count {
                let step = visible[index]
                // La barra de pestañas: franja inferior (49 pt + zona segura) con margen.
                let barRect = CGRect(x: 8, y: g.size.height - 62, width: g.size.width - 16, height: 58)
                // Ajustes arriba (junto al Jam) en vez de en la barra: se resalta ese botón.
                let key = step.tab == "settings" && targets.rects["settings"] != nil ? "settings" : step.key
                let raw = key == "tab" ? barRect : (targets.rects[key] ?? barRect).offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.62)
                        .mask {
                            Rectangle().overlay(RoundedRectangle(cornerRadius: raw.height / 2.6, style: .continuous)
                                .frame(width: raw.width, height: raw.height).position(x: raw.midX, y: raw.midY).blendMode(.destinationOut))
                                .compositingGroup()
                        }
                    RoundedRectangle(cornerRadius: raw.height / 2.6 + (pulse ? 12 : 0), style: .continuous)
                        .stroke(Color.accentColor.opacity(pulse ? 0 : 0.9), lineWidth: 2.5)
                        .frame(width: raw.width + (pulse ? 24 : 0), height: raw.height + (pulse ? 24 : 0))
                        .position(x: raw.midX, y: raw.midY)
                    card(step, number: index + 1, total: visible.count)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: 520)
                        .position(x: g.size.width / 2, y: raw.midY < 360 ? raw.maxY + 110 : raw.minY - 110)
                }
                .contentShape(Rectangle())
                .onTapGesture { p in if raw.contains(p) { advance(step, total: visible.count) } }
                .animation(.uiEaseOut(0.42), value: index)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
                }
            } else {
                Color.clear.onAppear(perform: onDone)
            }
        }
        .ignoresSafeArea()
    }

    private func advance(_ step: Step, total: Int) {
        if let t = step.tab { select(t) }
        if index >= total - 1 { onDone() } else { index += 1 }
    }

    private func card(_ step: Step, number: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(step.title).font(.title3.bold())
                Spacer()
                Text("\(number) de \(total)").font(.footnote).foregroundStyle(.secondary)
            }
            Text(step.text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(L("Toca lo resaltado para seguir")).font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                Spacer()
                Button(L("Saltar"), action: onDone).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(20)
        // Opaca: sobre el velo oscuro el material dejaría ver el contenido de debajo y no se leería.
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(uiColor: .systemBackground))
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Recorrido: {0}. {1}", step.title, step.text))
    }
}

// MARK: - Guía de Ajustes y novedades (1.1)
/// Igual que `TourOverlay(guided = true)` en Android: cada paso abre su pantalla de Ajustes (`Guide.path`), espera a
/// que se pinte lo que resalta y se avanza con «Siguiente». Un paso sin elemento enseña sólo la tarjeta; uno cuyo
/// elemento no existe en este iPhone se salta. Diferencia aceptada: el buscador de Ajustes es del sistema
/// (`.searchable`) y no se puede medir, así que su paso se salta en iOS.
enum SettingsRoute: Hashable { case aspect, audio, library, help }

@MainActor
final class Guide: ObservableObject {
    static let shared = Guide()
    /// «settings» (botón junto a la carta) o «whatsnew» (desde el panel de novedades).
    @Published var active: String?
    /// La pila de Ajustes mientras dura la guía.
    @Published var path: [SettingsRoute] = []
}

struct GuideStep {
    let keys: [String]
    let title: String
    let text: String
    var route: [SettingsRoute] = []
}

enum GuideSteps {
    private static func row(_ title: String, _ text: String, _ route: SettingsRoute? = nil) -> GuideStep {
        GuideStep(keys: ["row:\(title)", "section:\(title)"], title: title, text: text, route: route.map { [$0] } ?? [])
    }

    static var settings: [GuideStep] { [
        GuideStep(keys: ["settings:search"], title: L("Buscar en Ajustes"), text: L("Escribe lo que buscas, por ejemplo «ecualizador» o «tema», y te lleva directo a la opción.")),
        GuideStep(keys: ["settings:mail"], title: L("Buzón y errores"), text: L("La carta abre el buzón de sugerencias y el escarabajo, «Informar de un error». Cada envío tiene número de ticket y la respuesta te llega sólo a ti, a la campana.")),
        row(L("Cuenta"), L("Opcional. Guarda tu biblioteca en la nube, cifrada con una clave que sólo tienes tú, y pásala a otro móvil.")),
        row(L("Tema"), L("Cristal (luz con los colores de la carátula), Aire (plata), Neón (synthwave) o Sistema. Y claro, oscuro o según el móvil."), .aspect),
        row(L("Reproductor"), L("Normal, Casete, Vinilo o Air. También se cambia manteniendo pulsado el mini reproductor."), .aspect),
        row(L("Colores de la portada"), L("La app y el reproductor toman los colores de la canción que suena. Elige dónde y cuánto, con presets o a tu gusto."), .aspect),
        row(L("Pestañas"), L("Ordena las pestañas arrastrándolas. Desliza Descubrir a la izquierda para quitarla de la barra."), .aspect),
        row(L("Barra inferior"), L("La clásica o la estilo SimpMusic: cápsula de cristal con una gota que arrastras, Buscar aparte y plegado al bajar."), .aspect),
        row(L("Ajustes"), L("Ajustes puede ir en la barra o arriba en Inicio, junto al Jam."), .aspect),
        row(L("Idioma"), L("Castellano, català, valencià, galego, euskara, English, Esperanto y português. Cambia al momento.")),
        row(L("Calidad al escuchar"), L("Máxima, o ahorro de datos cuando no tienes wifi. Las descargas siempre van a la máxima."), .audio),
        row(L("Seguir con canciones parecidas"), L("Cuando se acaba la cola, sigue con una radio de canciones parecidas a la última."), .audio),
        row(L("Fundido entre canciones"), L("La canción baja al final y la siguiente entra suave: 3, 6 o 10 segundos."), .audio),
        row(L("Descargas"), L("Cuánto ocupan tus canciones descargadas y borrarlas.")),
        row(L("Ordenar playlists por"), L("Recientes, A-Z, Z-A, por tamaño o a mano. Con «Editar playlists» las ordenas arrastrando."), .library),
        row(L("Descargadas y Favoritos"), L("Como portada grande en Playlists o como fila en «Tu música»."), .library),
        row(L("Dónde está Buscar"), L("Una barra arriba en Inicio o una pestaña aparte."), .library),
        row(L("Avisos"), L("Las caídas y novedades de Pear Music, también como notificación si quieres."), .help),
        row(L("Guía inicial"), L("Vuelve a ver la bienvenida, el recorrido y las historias."), .help),
        row(L("Tus datos"), L("Exporta todo lo que la app guarda de ti en un archivo o bórralo. Aquí también se activa o se quita la telemetría."), .help),
        row(L("Avanzado"), L("Lo técnico, plegado: calidad de descarga, tolerancia al importar playlists y caché de carátulas.")),
        GuideStep(keys: [], title: L("¡Listo!"), text: L("Ya conoces todos los Ajustes. Vuelve a esta guía cuando quieras con el botón junto a la carta.")),
    ] }

    static var whatsNew: [GuideStep] { [
        GuideStep(keys: ["settings:guide"], title: L("Guía de Ajustes"), text: L("Nueva: te lleva por todos los Ajustes y te explica cada opción. Está junto a la carta.")),
        row(L("Idioma"), L("Ya puedes usar Pear Music en português. Y «Español» ahora se llama «Castellano».")),
        GuideStep(keys: ["settings:mail"], title: L("Buzón y errores"), text: L("Con cada reporte o sugerencia va la ficha de tu móvil (modelo y versiones), para ayudarte antes.")),
        GuideStep(keys: [], title: L("Y además"), text: L("Al descargar una versión nueva ves el progreso, y la barra clásica ya no marca Descubrir cuando estás en Ajustes.")),
    ] }
}

struct GuideOverlay: View {
    let steps: [GuideStep]
    let onDone: () -> Void
    @ObservedObject private var targets = TourTargets.shared
    @ObservedObject private var guide = Guide.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var key: String?
    @State private var ready = false
    @State private var pulse = false

    var body: some View {
        GeometryReader { g in
            let origin = g.frame(in: .global).origin
            let hole = key.flatMap { targets.rects[$0] }?.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8)
            ZStack(alignment: .topLeading) {
                if ready, let hole {
                    Color.black.opacity(0.62)
                        .mask {
                            Rectangle().overlay(RoundedRectangle(cornerRadius: hole.height / 2.6, style: .continuous)
                                .frame(width: hole.width, height: hole.height).position(x: hole.midX, y: hole.midY).blendMode(.destinationOut))
                                .compositingGroup()
                        }
                    RoundedRectangle(cornerRadius: hole.height / 2.6 + (pulse ? 12 : 0), style: .continuous)
                        .stroke(Color.accentColor.opacity(pulse ? 0 : 0.9), lineWidth: 2.5)
                        .frame(width: hole.width + (pulse ? 24 : 0), height: hole.height + (pulse ? 24 : 0))
                        .position(x: hole.midX, y: hole.midY)
                } else {
                    Color.black.opacity(0.62)
                }
                if ready, index < steps.count {
                    card(steps[index])
                        .padding(.horizontal, 20)
                        .frame(maxWidth: 520)
                        .position(x: g.size.width / 2,
                                  y: hole.map { $0.midY < 360 ? $0.maxY + 120 : $0.minY - 120 } ?? g.size.height / 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { p in if ready, let hole, hole.contains(p) { advance() } }
            .animation(.uiEaseOut(0.42), value: index)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
            }
        }
        .ignoresSafeArea()
        .task(id: index) { await prepare() }
    }

    /// Abre la pantalla del paso y espera (hasta 2 s) a que su elemento esté pintado.
    private func prepare() async {
        guard index < steps.count else { onDone(); return }
        ready = false
        key = nil
        let step = steps[index]
        if guide.path != step.route { guide.path = step.route }
        var found: String?
        for _ in 0..<40 {
            found = step.keys.first { targets.rects[$0].map { !$0.isEmpty } == true }
            if found != nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if found == nil, !step.keys.isEmpty { advance(); return }
        if found != nil { try? await Task.sleep(nanoseconds: 300_000_000) } // que termine la animación de entrar
        key = found
        ready = true
    }

    private func advance() {
        if index >= steps.count - 1 { onDone() } else { index += 1 }
    }

    private func card(_ step: GuideStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(step.title).font(.title3.bold())
                Spacer()
                Text(L("{0} de {1}", index + 1, steps.count)).font(.footnote).foregroundStyle(.secondary)
            }
            Text(step.text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("Salir"), action: onDone).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityLabel(L("Salir de la guía"))
                Spacer()
                Button(index >= steps.count - 1 ? L("Terminar") : L("Siguiente"), action: advance)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .fixedSize()
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(uiColor: .systemBackground))
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Recorrido: {0}. {1}", step.title, step.text))
    }
}

// MARK: - Novedades tras actualizar (1.1)
/// Igual que `WhatsNewScreen` en Android: la primera vez que se abre una versión nueva, a pantalla completa y sin
/// poder cerrarla deslizando; «Enséñame lo nuevo» abre el recorrido de novedades y «Ahora no» lo cierra.
enum WhatsNew {
    /// Versión «mayor.menor»: los arreglos (2.1.1) no vuelven a enseñar el panel.
    static var current: String { AboutView.version.split(separator: ".").prefix(2).joined(separator: ".") }

    struct Item: Identifiable { let id = UUID(); let icon: String; let palette: Int; let title: String; let text: String }

    static var items: [Item] { [
        Item(icon: "graduationcap.fill", palette: 4, title: L("Guía de Ajustes"), text: L("Un recorrido por todos los Ajustes que te explica cada opción. Está junto a la carta.")),
        Item(icon: "globe", palette: 3, title: L("Português"), text: L("Pear Music ya está en portugués. Y «Español» ahora se llama «Castellano».")),
        Item(icon: "envelope.fill", palette: 1, title: L("Soporte más rápido"), text: L("Con cada reporte o sugerencia va la ficha de tu móvil (modelo y versiones), para ayudarte antes.")),
        Item(icon: "arrow.down.circle.fill", palette: 2, title: L("Actualizaciones"), text: L("Al descargar una versión nueva ves el progreso, y si hay que dar permiso para instalar no se vuelve a descargar.")),
    ] }
}

struct WhatsNewView: View {
    let onTour: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Novedades")).font(.largeTitle.bold()).padding(.top, 40)
                    Text(L("Lo nuevo de Pear Music {0}", WhatsNew.current)).foregroundStyle(.secondary).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(WhatsNew.items) { item in
                            HStack(alignment: .top, spacing: 16) {
                                GradientIcon(systemName: item.icon, palette: item.palette, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.headline)
                                    Text(item.text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(.top, 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            VStack(spacing: 10) {
                Button(action: onTour) { Text(L("Enséñame lo nuevo")).frame(maxWidth: .infinity) }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button(action: onClose) { Text(L("Ahora no")).frame(maxWidth: .infinity) }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .themed()
        .interactiveDismissDisabled()
    }
}

// MARK: - Historias a pantalla completa
/// Igual que `StoriesScreen` en Android: cinco capturas reales, 6 s cada una; toque a los lados para pasar,
/// mantener pulsado para pausar.
struct StoriesView: View {
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var progress: CGFloat = 0
    @State private var paused = false
    private let tick = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    private struct Story { let image, title, text: String }
    private let stories = [
        Story(image: "Story-biblioteca", title: L("Tu biblioteca, a tu manera"), text: L("Playlists con tu foto, icono y color, favoritos y descargas en un sitio. Fija arriba lo que más escuchas y abre la discografía completa de cada artista.")),
        Story(image: "Story-reproductores", title: L("Reproductores con personalidad"), text: L("Casete con bobinas que giras con el dedo, vinilo que se puede «scratchear» o el Air plateado. Mantén pulsado el mini reproductor para cambiar.")),
        Story(image: "Story-letra", title: L("La letra, al compás"), text: L("Toca la cola y elige Letra: sigue la canción línea a línea y se guarda para verla sin conexión.")),
        Story(image: "Story-jam", title: L("Jam con tus amigos"), text: L("Una playlist a la que todos añaden canciones desde su móvil, iPhone o Android, en la misma Wi-Fi. Con el QR se entra al momento.")),
        Story(image: "Story-temas", title: L("Hazla tuya"), text: L("Cristal, Aire, Neón o Sistema, y colores que salen de la portada. Todo en Ajustes › Aspecto.")),
    ]

    var body: some View {
        let s = stories[index]
        ZStack {
            Color.black.ignoresSafeArea()
            Image(s.image).resizable().scaledToFill().blur(radius: 60).opacity(0.55).ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(stories.indices, id: \.self) { i in
                        GeometryReader { g in
                            Capsule().fill(.white.opacity(0.3))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.white).frame(width: g.size.width * (i < index ? 1 : i == index ? progress : 0))
                                }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                HStack {
                    Text(L("Pear Music")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Button(action: onDone) { Image(systemName: "xmark").font(.headline).foregroundStyle(.white).padding(12) }
                        .accessibilityLabel(L("Cerrar las historias"))
                }
                .padding(.horizontal, 8)
                Image(s.image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.04 * progress)
                    .padding(.horizontal, 28).padding(.vertical, 10)
                    .frame(maxHeight: .infinity)
                    .id(index)
                    .transition(.opacity)
                Text(s.title).font(.title2.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(s.text).font(.callout).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                    .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 18)
                if index == stories.count - 1 {
                    Button(action: onDone) { Text(L("Empezar a escuchar")).frame(maxWidth: .infinity) }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .padding(.horizontal, 20).padding(.bottom, 8)
                } else {
                    Text(L("Toca para seguir · mantén para pausar")).font(.footnote).foregroundStyle(.white.opacity(0.7)).padding(.vertical, 18)
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in paused = true }
            .onEnded { v in
                paused = false
                guard abs(v.translation.width) < 10, abs(v.translation.height) < 10 else { return }
                go(v.location.x < UIScreen.main.bounds.width * 0.3 ? index - 1 : index + 1)
            })
        .onReceive(tick) { _ in
            guard !paused else { return }
            progress += 1.0 / (6 * 30)
            if progress >= 1 { go(index + 1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Historia {0} de {1}: {2}. {3}", index + 1, stories.count, s.title, s.text))
    }

    private func go(_ to: Int) {
        if to >= stories.count { onDone(); return }
        withAnimation(.uiEaseOut(0.38)) { index = max(0, to) }
        progress = 0
    }
}

// MARK: - Primeros pasos
/// Tarjeta de Inicio con seis cosas que se marcan solas al hacerlas (igual que `FirstStepsCard` en Android).
/// Se guarda en `firstSteps` (claves separadas por comas; "hidden" la oculta).
enum FirstSteps {
    static var items: [(String, String)] { [
        ("play", L("Escucha una canción")),
        ("favorite", L("Guarda una favorita con el corazón")),
        ("download", L("Descarga algo para escucharlo sin conexión")),
        ("discover", L("Desliza un rato en Descubrir")),
        ("jam", L("Abre el Jam (el icono de las tres personas)")),
        ("pin", L("Fija un álbum o una playlist con la chincheta")),
    ] }
    static func done(_ raw: String) -> Set<String> { Set(raw.split(separator: ",").map(String.init)) }
    static func mark(_ key: String) {
        let d = UserDefaults.standard
        var set = done(d.string(forKey: "firstSteps") ?? "")
        guard !set.contains("hidden"), set.insert(key).inserted else { return }
        d.set(set.sorted().joined(separator: ","), forKey: "firstSteps")
    }
}

struct FirstStepsCard: View {
    @AppStorage("firstSteps") private var raw = "hidden"
    @AppStorage("showDiscover") private var showDiscover = true

    var body: some View {
        let done = FirstSteps.done(raw)
        // Sin la pestaña Descubrir, su paso no cuenta.
        let items = FirstSteps.items.filter { showDiscover || $0.0 != "discover" }
        let count = items.filter { done.contains($0.0) }.count
        if !done.contains("hidden") && count < items.count {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Primeros pasos")).font(.title3.bold())
                        Text(L("{0} de {1} · se marcan solos", count, items.count)).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Ocultar")) { FirstSteps.mark("hidden") }.font(.subheadline)
                }
                ProgressView(value: Double(count), total: Double(items.count)).tint(.accentColor).padding(.vertical, 10)
                ForEach(items, id: \.0) { key, title in
                    let ok = done.contains(key)
                    HStack(spacing: 12) {
                        Image(systemName: ok ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(ok ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        Text(title).strikethrough(ok).foregroundStyle(ok ? .secondary : .primary)
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .animation(.uiEaseOut(0.3), value: raw)
        }
    }
}
