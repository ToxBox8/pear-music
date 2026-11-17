import SwiftUI
import UIKit

// MARK: - Menús y gestos de la Biblioteca (pasos B y C de la revisión del bloque 1; DECISIONS 40, 42 y 43)
// Regla: mantener pulsado abre el menú; arrastrar sólo existe en el modo «Ordenar», y en él sólo se arrastra (sin
// barra, asa, aro ni buscador). Se coge la portada entera con el dedo quieto 0,2 s; si el dedo se mueve más de 10 pt
// antes, es desplazar. La portada levantada sigue al dedo sin animación (sólo se animan las que se apartan) y, cerca
// del borde, la lista o el carrusel avanzan solos. Aquí están las piezas comunes; las reglas (`GridOrder`,
// `OrderDrag`) están en LibraryModel.swift. Igual que ui/OrderMode.kt en Android.

/// Marco de cada celda dentro de su cuadrícula o carrusel, para saber qué hueco hay bajo el dedo.
struct OrderFrameKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGRect] { [:] }
    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Los números del gesto (la propuesta del paso C): cuánto quieto, cuánto se puede mover antes y el borde.
enum OrderGesture {
    /// Dedo quieto este tiempo sobre una portada → se levanta.
    static let holdSeconds = 0.2
    /// Si antes se mueve más que esto, es desplazar y la portada no se coge.
    static let slop: CGFloat = 10
    /// Cuadrícula: distancia al borde de arriba o de abajo a la que la lista empieza a desplazarse sola.
    static let verticalEdge: CGFloat = 72
    /// Carrusel de Fijados: lo mismo con los bordes izquierdo y derecho.
    static let horizontalEdge: CGFloat = 48
    /// Velocidad del desplazamiento al borde: de la mínima (al entrar en la zona) a la máxima (en el borde), en pt/s.
    static let minSpeed: CGFloat = 200
    static let maxSpeed: CGFloat = 900
    /// La portada levantada: un 4 % más grande e inclinada como en el boceto (con «Reducir movimiento», nada).
    static let liftScale: CGFloat = 1.04
    static let liftTilt: Double = -3

    /// Dedo quieto 0,2 s y luego arrastrar. `onLift` cuando se levanta (aún sin mover) y `onMove` con el dedo en
    /// coordenadas de la ventana cada vez que se mueve. `pressing` vuelve a false si el gesto acaba o se cancela.
    static func lift(pressing: GestureState<Bool>, onLift: @escaping () -> Void,
                     onMove: @escaping (_ start: CGPoint, _ now: CGPoint) -> Void,
                     onEnd: @escaping () -> Void) -> some Gesture {
        LongPressGesture(minimumDuration: holdSeconds, maximumDistance: slop)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating(pressing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if let drag { onMove(drag.startLocation, drag.location) } else { onLift() }
            }
            .onEnded { _ in onEnd() }
    }
}

/// Un `UIView` vacío de fondo de la cuadrícula o del carrusel. Sirve para dos cosas: pasar el dedo (en coordenadas de
/// la ventana) a las de la cuadrícula, que se mueven con el desplazamiento aunque el dedo esté quieto, y encontrar los
/// `UIScrollView` que la contienen para desplazarlos al borde y pararlos mientras se arrastra.
@MainActor
final class OrderAnchor {
    fileprivate weak var view: UIView?
    /// La vista existe y está en pantalla.
    var attached: Bool { view?.window != nil }

    /// El dedo en coordenadas de la cuadrícula.
    func local(_ window: CGPoint) -> CGPoint? { view.map { $0.convert(window, from: nil) } }

    /// Los `UIScrollView` que la contienen, del más cercano al más lejano.
    var scrollViews: [UIScrollView] {
        var out: [UIScrollView] = []
        var v = view?.superview
        while let cur = v { if let s = cur as? UIScrollView { out.append(s) }; v = cur.superview }
        return out
    }
}

struct OrderAnchorView: UIViewRepresentable {
    let anchor: OrderAnchor

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        anchor.view = v
        return v
    }
    func updateUIView(_ v: UIView, context: Context) { anchor.view = v }
}

/// Desplaza un `UIScrollView` solo mientras el dedo esté cerca de su borde (en el eje que se le diga), más rápido
/// cuanto más cerca. Un borde sólo cuenta si, desde que cogió la portada (`from`), el dedo ha estado fuera de su zona o
/// se ha movido más de `OrderGesture.slop` hacia él: así, coger una que ya está cerca del borde y alejarla no hace
/// saltar la lista. Cada fotograma que se mueve llama a `onTick`, para que la portada levantada y el orden sigan al
/// dedo aunque el dedo no se mueva. Con «Reducir movimiento» también funciona: es la única forma de llegar a lo que
/// no se ve.
@MainActor
final class EdgeScroller: NSObject {
    private weak var scroll: UIScrollView?
    private var axis: Axis = .vertical
    private var zone: CGFloat = OrderGesture.verticalEdge
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    /// El dedo, en coordenadas de la ventana.
    var finger: CGPoint?
    /// Dónde cogió la portada, en coordenadas de la ventana.
    var from: CGPoint?
    private var lowOK = false
    private var highOK = false
    var onTick: () -> Void = {}

    func start(_ scroll: UIScrollView?, axis: Axis) {
        stop()
        self.scroll = scroll
        self.axis = axis
        zone = axis == .vertical ? OrderGesture.verticalEdge : OrderGesture.horizontalEdge
        guard scroll != nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        last = 0
        lowOK = false
        highOK = false
    }

    func stop() {
        link?.invalidate()
        link = nil
        finger = nil
        from = nil
    }

    @objc private func step(_ l: CADisplayLink) {
        defer { last = l.timestamp }
        guard let sv = scroll, let p = finger, last > 0 else { return }
        let dt = min(l.timestamp - last, 1.0 / 30)
        let frame = sv.convert(sv.bounds, to: nil)
        let inset = sv.adjustedContentInset
        let vertical = axis == .vertical
        // Lo que se ve: en vertical, sin las barras de arriba y abajo; en horizontal, la pantalla de lado a lado.
        let lo = vertical ? frame.minY + max(inset.top, sv.safeAreaInsets.top) : frame.minX
        let hi = vertical ? frame.maxY - max(inset.bottom, sv.safeAreaInsets.bottom) : frame.maxX
        let pos = vertical ? p.y : p.x
        let start = from.map { vertical ? $0.y : $0.x } ?? pos
        if pos >= lo + zone || start - pos > OrderGesture.slop { lowOK = true }
        if pos <= hi - zone || pos - start > OrderGesture.slop { highOK = true }
        let near: CGFloat
        if pos < lo + zone && lowOK { near = -min(1, (lo + zone - pos) / zone) }
        else if pos > hi - zone && highOK { near = min(1, (pos - (hi - zone)) / zone) }
        else { return }
        let speed = OrderGesture.minSpeed + (OrderGesture.maxSpeed - OrderGesture.minSpeed) * abs(near)
        let delta = (near < 0 ? -speed : speed) * CGFloat(dt)
        var off = sv.contentOffset
        if vertical {
            let minY = -inset.top, maxY = max(minY, sv.contentSize.height + inset.bottom - sv.bounds.height)
            off.y = min(max(off.y + delta, minY), maxY)
        } else {
            let minX = -inset.left, maxX = max(minX, sv.contentSize.width + inset.right - sv.bounds.width)
            off.x = min(max(off.x + delta, minX), maxX)
        }
        guard off != sv.contentOffset else { return }
        sv.contentOffset = off
        onTick()
    }
}

/// Cuadrícula de dos columnas como la `LazyVGrid` de Playlists (mismas medidas), pero sin ser perezosa: mientras se
/// arrastra, la portada cogida no puede dejar de existir aunque su hueco salga de la pantalla al desplazar el borde
/// (el gesto se cortaría). Sólo se usa en el modo «Ordenar».
struct OrderGridLayout: Layout {
    var spacing: CGFloat = 16
    var rowSpacing: CGFloat = 22

    private func columnWidth(_ width: CGFloat) -> CGFloat { max(0, (width - spacing) / 2) }

    private func rows(_ subviews: Subviews, _ w: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: 2).map { i in
            (i..<min(i + 2, subviews.count)).map { subviews[$0].sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let heights = rows(subviews, columnWidth(width))
        return CGSize(width: width, height: heights.reduce(0, +) + rowSpacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = columnWidth(bounds.width)
        var y = bounds.minY
        for (r, h) in rows(subviews, w).enumerated() {
            for c in 0..<2 where r * 2 + c < subviews.count {
                subviews[r * 2 + c].place(at: CGPoint(x: bounds.minX + CGFloat(c) * (w + spacing), y: y), anchor: .topLeading,
                                          proposal: ProposedViewSize(width: w, height: h))
            }
            y += h + rowSpacing
        }
    }
}

/// El hueco de la portada levantada: su sitio se queda marcado con un borde de rayas (como el hueco vacío de Fijados).
struct OrderHole: View {
    var radius: CGFloat = Tokens.Radius.row
    var side: CGFloat? = nil
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [5, 6]))
            .aspectRatio(1, contentMode: .fit)
            .frame(width: side, height: side)
            .allowsHitTesting(false)
    }
}

/// El temblor del modo «Ordenar» (prompt 2-0 del bloque 2): todas las portadas que se pueden mover tiemblan, como los
/// iconos del iPhone al reordenar las apps. Suave (poco ángulo, como el de «Tu música») y cada portada con su desfase y
/// su ritmo, para que no vayan todas a la vez. La cogida no tiembla. Con «Reducir movimiento» no tiembla ninguna: cada
/// portada lleva un borde fino del color del texto (`OrderMark`). Sin shu. Igual que `orderWiggle` en Android.
enum OrderWiggle {
    /// Cuánto se inclina a cada lado, en grados.
    static let degrees: Double = 1.1
    /// Una ida y vuelta, en segundos: de `period` a `period + spread` según la portada.
    static let period: Double = 0.52
    static let spread: Double = 0.12
    /// El borde de «Reducir movimiento», en puntos.
    static let border: CGFloat = 1

    /// «Reducir movimiento» del sistema o, sólo en las capturas y los tests, el del escenario (`Demo`).
    static func reduced(_ system: Bool) -> Bool { system || Demo.current?.reduceMotion == true }

    /// El ángulo de una portada en un momento: un seno con el desfase y el ritmo que salen de `seed` (su id).
    static func angle(at date: Date, seed: Int) -> Double {
        let bits = UInt(bitPattern: seed)
        let phase = Double(bits % 997) / 997
        let rate = period + spread * Double((bits / 997) % 101) / 100
        let t = date.timeIntervalSinceReferenceDate / rate + phase
        return degrees * sin(2 * .pi * t)
    }
}

extension View {
    /// Tiembla mientras `on` (en «Ordenar», no cogida y sin «Reducir movimiento»). Es un giro de dibujo: no cambia el
    /// marco que mide el arrastre (`OrderFrameKey` se lee fuera). Con `on` apagado el reloj se para y se queda recta.
    func orderWiggle(_ on: Bool, seed: Int) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !on)) { tl in
            rotationEffect(.degrees(on ? OrderWiggle.angle(at: tl.date, seed: seed) : 0))
        }
    }
}

/// «Reducir movimiento» en «Ordenar»: en vez de temblar, un borde fino del color del texto alrededor de la portada.
struct OrderMark: View {
    var radius: CGFloat = Tokens.Radius.row
    var side: CGFloat? = nil
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.primary, lineWidth: OrderWiggle.border)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: side, height: side)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// La portada levantada: un poco más grande, inclinada y con sombra (con «Reducir movimiento», sólo la sombra).
    /// Se dibuja encima de la cuadrícula en el sitio del dedo, sin animación.
    func orderLifted(reduceMotion: Bool) -> some View {
        scaleEffect(reduceMotion ? 1 : OrderGesture.liftScale)
            .rotationEffect(.degrees(reduceMotion ? 0 : OrderGesture.liftTilt))
            .shadow(color: .black.opacity(0.24), radius: 16, y: 10)
            .allowsHitTesting(false)
    }
}

/// El arrastre del modo «Ordenar», común a la cuadrícula (Playlists, carpetas, Tus álbumes) y al carrusel de
/// Fijados. Guarda el orden mientras se mueve (`order`), la portada cogida (`drag`, con las reglas de `OrderDrag`) y
/// cuánto se ha movido desde su sitio (`shift`), que la vista aplica a la copia levantada sin animación. Para los
/// `UIScrollView` mientras se arrastra y desplaza el del eje al llegar al borde (`EdgeScroller`).
@MainActor
final class OrderLift<ID: Hashable>: ObservableObject {
    @Published var order: [ID] = []
    @Published private(set) var drag: OrderDrag<ID>?
    @Published private(set) var shift: CGSize = .zero
    /// El dedo sigue puesto (la copia levantada aún no ha vuelto a su hueco).
    private(set) var holding = false
    /// Marcos de cada celda (en la cuadrícula); se leen al levantar.
    var frames: [ID: CGRect] = [:]
    let anchor = OrderAnchor()
    private let scroller = EdgeScroller()
    private var startLocal: CGPoint?
    private var paused: [UIScrollView] = []
    private var canDropInto: (ID, ID) -> Bool = { _, _ in false }
    private var canSwap: (ID, ID) -> Bool = { _, _ in true }
    private var reduceMotion = false
    private var generation = 0
    /// Sólo en los tests de interfaz y las capturas (`-screenshotScenario`): qué ha pasado con el último gesto, para
    /// que un test que falla diga por qué (si el arrastre arrancó y con cuántas celdas medidas). `OrderDebugLabel` lo
    /// enseña como texto invisible.
    @Published private(set) var debug = ""
    private var asked = 0, started = 0, moves = 0, ended = 0
    private var lastFail = "-"

    private func log(_ fail: String? = nil) {
        guard Demo.current != nil else { return }
        if let fail { lastFail = fail }
        let text = OrderLog.lift(asked: asked, started: started, fail: lastFail, cells: frames.count, order: order.count)
            + "ancla=\(anchor.attached ? "si" : "no") listas=\(anchor.scrollViews.count) movimientos=\(moves) "
            + "inicio=\(startLocal == nil ? "no" : "si") soltados=\(ended)"
        if text != debug { debug = text }
    }

    init() { scroller.onTick = { [weak self] in self?.follow() } }

    /// El dedo lleva 0,2 s quieto sobre `id`: se levanta. `axis` es hacia dónde se desplaza al llegar al borde.
    func lift(_ id: ID, axis: Axis, reduceMotion: Bool,
              canDropInto: @escaping (ID, ID) -> Bool = { _, _ in false },
              canSwap: @escaping (ID, ID) -> Bool = { _, _ in true }) {
        asked += 1
        guard !holding else { log("ya-hay-una-cogida"); return }
        guard let start = order.firstIndex(of: id) else { log("no-esta-en-el-orden"); return }
        var slots: [Int: CGRect] = [:]
        for (i, other) in order.enumerated() { if let f = frames[other] { slots[i] = f } }
        guard slots[start] != nil else { log("celda-sin-medir"); return }
        started += 1
        generation += 1
        holding = true
        self.reduceMotion = reduceMotion
        self.canDropInto = canDropInto
        self.canSwap = canSwap
        startLocal = nil
        shift = .zero
        drag = OrderDrag(id: id, slots: slots, start: start)
        // Mientras se arrastra no se desplaza nada con el dedo: en el carrusel, tampoco la Biblioteca de debajo.
        let views = anchor.scrollViews
        paused = Array(views.prefix(axis == .vertical ? 1 : 2)).filter(\.isScrollEnabled)
        paused.forEach { $0.isScrollEnabled = false }
        scroller.start(views.first, axis: axis)
        // Ni deslizar entre pestañas mientras se arrastra (en Fijados, a los lados, se lo quedaba también).
        TabSwipe.blockedUntil = .distantFuture
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        log("-")
    }

    /// El dedo se ha movido (coordenadas de la ventana): `start` es donde estaba al levantarse.
    func move(start: CGPoint, now: CGPoint) {
        guard holding else { return }
        if startLocal == nil { startLocal = anchor.local(start); scroller.from = start }
        scroller.finger = now
        moves += 1
        follow()
        log()
    }

    /// Recoloca la copia levantada bajo el dedo y aparta las demás si ha cambiado el hueco. También en cada fotograma
    /// del desplazamiento al borde, con el dedo quieto.
    private func follow() {
        guard holding, var d = drag, let w = scroller.finger, let p = anchor.local(w), let s = startLocal else { return }
        let moved = CGSize(width: p.x - s.x, height: p.y - s.y)
        let before = d.into
        let next = d.move(to: p, translation: moved, order: order, now: CACurrentMediaTime(), canDropInto: canDropInto, canSwap: canSwap)
        // En el centro de una carpeta pero aún sin el tiempo: con el dedo quieto no llega ningún movimiento, así que se
        // vuelve a mirar al cumplirse (prompt 2-0).
        if d.into == nil, d.pendingInto != nil {
            let token = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + OrderDrag<ID>.intoDwell + 0.02) { [weak self] in
                guard let self, self.generation == token else { return }
                self.follow()
            }
        }
        if next != order {
            UISelectionFeedbackGenerator().selectionChanged()
            // Sólo se animan las que se apartan; la levantada va con el dedo (`shift`, fuera de la animación).
            withAnimation(reduceMotion ? nil : .uiEaseOut(0.22)) { order = next }
        } else if d.into != before, d.into != nil {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        drag = d
        shift = moved
    }

    /// El dedo se ha levantado (o el gesto se ha cortado). Devuelve cómo acabó, para guardar el orden o meterla en una
    /// carpeta; nil si no había nada cogido. La copia baja a su hueco y desaparece.
    @discardableResult
    func end() -> OrderDrag<ID>? {
        guard holding, let d = drag else { return nil }
        holding = false
        ended += 1
        log()
        TabSwipe.blockedUntil = Date().addingTimeInterval(0.4)
        scroller.stop()
        paused.forEach { $0.isScrollEnabled = true }
        paused = []
        let token = generation
        let clear = { [weak self] in
            guard let self, self.generation == token else { return }
            self.drag = nil
            self.shift = .zero
        }
        if let into = d.into, into != d.id {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(reduceMotion ? nil : .uiEaseOut(0.18)) { clear() }
        } else if !reduceMotion, let from = d.slots[d.start], let to = d.slots[order.firstIndex(of: d.id) ?? d.start] {
            withAnimation(.uiEaseOut(0.22)) { shift = CGSize(width: to.minX - from.minX, height: to.minY - from.minY) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { clear() }
        } else {
            clear()
        }
        if d.changed && d.into == nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        return d
    }
}

/// Sólo en los tests de interfaz y las capturas: el registro de `OrderLift` como texto que no se ve (1 pt,
/// transparente), para que el test lo lea (`orden-registro`). En la app normal no se dibuja nada.
struct OrderDebugLabel: View {
    let text: String
    var id = "orden-registro"
    var body: some View {
        if Demo.current != nil {
            Text(text.isEmpty ? "sin-gestos" : text)
                .font(.system(size: 1)).foregroundStyle(.clear)
                .accessibilityIdentifier(id)
                .allowsHitTesting(false)
        }
    }
}

/// Cómo se usa el modo «Ordenar».
struct OrderHint: View {
    var body: some View {
        Text(L("Mantén un momento una portada y arrástrala."))
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 4)
    }
}

// MARK: - Escribir un nombre

/// El aviso para escribir un nombre (nueva playlist, nueva carpeta, renombrar). Es un aviso de UIKit y no un
/// `.alert` de SwiftUI por tres cosas: se puede abrir desde cualquier sitio (también desde el menú de una canción,
/// que no tiene dónde colgar un aviso), el botón se apaga con el nombre vacío en cualquier versión de iOS, e Intro
/// en el teclado hace lo mismo que el botón. Los botones van del color del texto, no en shu (DECISIONS 40).
enum NamePrompt {
    static func ask(_ title: String, initial: String = "", confirm: String = L("Crear"), onDone: @escaping (String) -> Void) {
        Task { @MainActor in present(title, initial: initial, confirm: confirm, onDone: onDone) }
    }

    @MainActor
    private static func present(_ title: String, initial: String, confirm: String, onDone: @escaping (String) -> Void) {
        guard let top = topController() else { return }
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let action = UIAlertAction(title: confirm, style: .default) { [weak alert] _ in
            let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { onDone(name) }
        }
        let filled: (String?) -> Bool = { !($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        action.isEnabled = filled(initial)
        alert.addTextField { field in
            field.placeholder = L("Nombre")
            field.text = initial
            field.autocapitalizationType = .sentences
            field.returnKeyType = .done
            field.clearButtonMode = .whileEditing
            field.addAction(UIAction { [weak action, weak field] _ in action?.isEnabled = filled(field?.text) }, for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: L("Cancelar"), style: .cancel))
        alert.addAction(action)
        alert.preferredAction = action
        // Sin texto shu (lo decidió Toxbox): los botones del color del texto, que se lee igual en claro y en oscuro.
        alert.view.tintColor = .label
        top.present(alert, animated: true)
    }

    /// La pantalla que está encima de todo (también de una hoja abierta).
    @MainActor
    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

// MARK: - Eliminar una playlist o un álbum

extension View {
    /// La confirmación de eliminar una playlist o un álbum guardado: la misma en Ajustes › Eliminar de la biblioteca y
    /// en el menú de cada portada (lo decidió Toxbox).
    func deletePlaylistAlert(_ pending: Binding<Playlist?>, library: Library, onDeleted: @escaping (Playlist) -> Void = { _ in }) -> some View {
        alert(L("¿Eliminar «{0}»?", pending.wrappedValue?.name ?? ""),
              isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } })) {
            Button(L("Eliminar"), role: .destructive) {
                if let p = pending.wrappedValue {
                    library.deletePlaylist(p.id)
                    onDeleted(p)
                }
                pending.wrappedValue = nil
            }
            Button(L("Cancelar"), role: .cancel) { pending.wrappedValue = nil }
        } message: {
            Text(L("Se quitará de tu biblioteca con su portada. Las canciones descargadas se quedan en Descargadas. No se puede deshacer."))
        }
    }
}
