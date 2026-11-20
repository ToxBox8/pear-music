import Foundation

// PULIR #4: lo que dice la fila de Ajustes › Cuenta según cómo va la sincronización. Igual que EstadoSyncTest en Android.
var fallos = 0, total = 0
func comprobar(_ a: String, _ b: String) { total += 1; if a != b { fallos += 1; print("FALLA: «\(a)» en vez de «\(b)»") } }
let ahora: Double = 1_763_400_000_000
func t(_ v: VistaSync) -> String { v.estado(ahora: ahora).texto }
comprobar(t(VistaSync(fase: .bajando)), "Bajando tu biblioteca…")
comprobar(t(VistaSync(fase: .uniendo, sinRed: true)), "Juntando lo de tus móviles…")
comprobar(t(VistaSync(fase: .subiendo)), "Subiendo tu biblioteca…")
comprobar(t(VistaSync(pendiente: true, sinRed: true)), "Sin conexión: se subirá luego")
comprobar(t(VistaSync(ultimaOk: ahora, pendiente: true)), "Pendiente de subir")
comprobar(t(VistaSync(ultimaOk: ahora - 20_000)), "Sincronizado ahora mismo")
comprobar(t(VistaSync(ultimaOk: ahora - 2 * 60_000)), "Sincronizado hace 2 min")
comprobar(t(VistaSync(ultimaOk: ahora - 3 * 3_600_000)), "Sincronizado hace 3 h")
comprobar(t(VistaSync()), "Aún no se ha sincronizado")
print("Estado de la sincronización: \(total - fallos)/\(total) bien")
exit(fallos == 0 ? 0 : 1)
