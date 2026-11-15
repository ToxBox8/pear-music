// Tests del modo «Ordenar» (paso B de menús y gestos), sólo Foundation: scripts/test-linux.sh.
// Los mismos casos que GridOrderTest.kt en Android.
import Foundation

var fallos = 0
func igual<T: Equatable>(_ a: T, _ b: T, _ que: String) {
    if a != b { fallos += 1; print("❌ \(que): \(a) ≠ \(b)") }
}
struct Song: Identifiable, Hashable, Codable { let id: String; let title: String; let artist: String; let thumbnail: URL? }

// Dos carpetas delante y tres playlists detrás, como en Playlists.
let ids = ["f:Gim", "f:Via", "Noche", "Playa", "Correr"]
let mismoTipo: (String, String) -> Bool = { $0.hasPrefix("f:") == $1.hasPrefix("f:") }

// MARK: «Antes» y «Después»
igual(GridOrder.step("Noche", by: 1, in: ids, canSwap: mismoTipo), ["f:Gim", "f:Via", "Playa", "Noche", "Correr"], "después")
igual(GridOrder.step("Correr", by: -1, in: ids, canSwap: mismoTipo), ["f:Gim", "f:Via", "Noche", "Correr", "Playa"], "antes")
igual(GridOrder.step("Noche", by: -1, in: ids, canSwap: mismoTipo), ids, "una playlist no pasa delante de una carpeta")
igual(GridOrder.step("f:Via", by: 1, in: ids, canSwap: mismoTipo), ids, "una carpeta no pasa detrás de una playlist")
igual(GridOrder.step("f:Gim", by: -1, in: ids, canSwap: mismoTipo), ids, "la primera no sube")
igual(GridOrder.step("Correr", by: 1, in: ids, canSwap: mismoTipo), ids, "la última no baja")
igual(GridOrder.step("No está", by: 1, in: ids), ids, "lo que no está no mueve nada")
igual(GridOrder.step("Noche", by: 2, in: ids), ids, "sólo de uno en uno")
igual(GridOrder.canStep("Noche", by: -1, in: ids, canSwap: mismoTipo), false, "«Antes» apagado")
igual(GridOrder.canStep("Noche", by: 1, in: ids, canSwap: mismoTipo), true, "«Después» encendido")
igual(GridOrder.moved("Correr", to: 2, in: ids), ["f:Gim", "f:Via", "Correr", "Noche", "Playa"], "al puesto 2")
igual(GridOrder.moved("Noche", to: 4, in: ids), ["f:Gim", "f:Via", "Playa", "Correr", "Noche"], "al último")
igual(GridOrder.moved("Noche", to: 9, in: ids), ids, "un puesto que no existe")

// MARK: Arrastrar por el asa: cuadrícula de 2 columnas, celdas de 100 × 120 con 10 de hueco
func hueco(_ i: Int) -> CGRect { CGRect(x: CGFloat(i % 2) * 110, y: CGFloat(i / 2) * 130, width: 100, height: 120) }
let huecos = Dictionary(uniqueKeysWithValues: ids.indices.map { ($0, hueco($0)) })
let admite: (String, String) -> Bool = { !$0.hasPrefix("f:") && $1.hasPrefix("f:") }
func centro(_ i: Int) -> CGPoint { CGPoint(x: hueco(i).midX, y: hueco(i).midY) }

do {
    // «Noche» (puesto 2) hasta el hueco de «Correr» (puesto 4).
    var d = OrderDrag(id: "Noche", slots: huecos, start: 2)
    var orden = ids
    orden = d.move(to: centro(2), translation: .zero, order: orden, canDropInto: admite, canSwap: mismoTipo)
    igual(orden, ids, "sin salir de su hueco no cambia nada")
    igual(d.changed, false, "y no cuenta como movida")
    orden = d.move(to: centro(4), translation: CGSize(width: 0, height: 130), order: orden, canDropInto: admite, canSwap: mismoTipo)
    igual(orden, ["f:Gim", "f:Via", "Playa", "Correr", "Noche"], "arrastrada al último hueco")
    igual(d.offset(in: orden), .zero, "ya está bajo el dedo: sin desplazamiento de más")
    // El dedo sigue en el mismo hueco: no vuelve a moverse (antes de que la pantalla se recoloque).
    igual(d.move(to: centro(4), translation: CGSize(width: 3, height: 133), order: orden, canDropInto: admite, canSwap: mismoTipo), orden, "no rebota")
    igual(d.offset(in: orden), CGSize(width: 3, height: 3), "sigue al dedo desde su hueco nuevo")
}
do {
    // Encima de una carpeta: se marca para soltarla dentro y no se reordena.
    var d = OrderDrag(id: "Noche", slots: huecos, start: 2)
    let orden = d.move(to: centro(1), translation: CGSize(width: 110, height: -130), order: ids, canDropInto: admite, canSwap: mismoTipo)
    igual(orden, ids, "sobre una carpeta no cambia el orden")
    igual(d.into, "f:Via", "la carpeta queda marcada")
    _ = d.move(to: CGPoint(x: 105, y: 60), translation: .zero, order: ids, canDropInto: admite, canSwap: mismoTipo)
    igual(d.into, nil, "entre dos celdas no hay nada marcado")
}
do {
    // Una carpeta sobre una playlist: ni entra ni se apartan.
    var d = OrderDrag(id: "f:Gim", slots: huecos, start: 0)
    igual(d.move(to: centro(3), translation: .zero, order: ids, canDropInto: admite, canSwap: mismoTipo), ids, "carpeta sobre playlist")
    igual(d.into, nil, "nada marcado")
    igual(d.move(to: centro(1), translation: .zero, order: ids, canDropInto: admite, canSwap: mismoTipo), ["f:Via", "f:Gim", "Noche", "Playa", "Correr"], "carpeta sobre carpeta: se ordenan")
}

print(fallos == 0 ? "✅ Modo «Ordenar»: todo bien" : "❌ \(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
