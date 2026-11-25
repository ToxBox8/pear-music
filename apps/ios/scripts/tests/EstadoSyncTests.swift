import Foundation

// PULIR #4: lo que dice la fila de Ajustes › Cuenta según cómo va la sincronización. Igual que EstadoSyncTest en Android.
var fallos = 0, total = 0
func comprobar(_ a: String, _ b: String) { total += 1; if a != b { fallos += 1; print("FALLA: «\(a)» en vez de «\(b)»") } }
let ahora: Double = 1_763_400_000_000
func t(_ v: VistaSync) -> String { v.estado(ahora: ahora).texto }
comprobar(t(VistaSync(fase: .bajando)), "Bajando tu biblioteca…")
comprobar(t(VistaSync(fase: .uniendo, sinRed: true)), "Juntando lo de tus dispositivos…")
comprobar(t(VistaSync(fase: .subiendo)), "Subiendo tu biblioteca…")
comprobar(t(VistaSync(pendiente: true, sinRed: true)), "Sin conexión: se subirá luego")
comprobar(t(VistaSync(ultimaOk: ahora, pendiente: true)), "Pendiente de subir")
comprobar(t(VistaSync(ultimaOk: ahora - 20_000)), "Sincronizado ahora mismo")
comprobar(t(VistaSync(ultimaOk: ahora - 2 * 60_000)), "Sincronizado hace 2 min")
comprobar(t(VistaSync(ultimaOk: ahora - 3 * 3_600_000)), "Sincronizado hace 3 h")
comprobar(t(VistaSync()), "Aún no se ha sincronizado")
// Pulir 2 #2, modo fútbol: no es un error, la espera crece hasta 30 min (±10 %) y no se intenta antes de la hora.
var bloq = VistaSync(pendiente: true, sinRed: true); bloq.bloqueado = true; bloq.reintentoEn = ahora + 60_000
comprobar(t(bloq), "No se puede llegar al servidor")
comprobar(bloq.detalle ?? "", "En España pasa a veces durante los partidos de fútbol. Se volverá a intentar sola.")
comprobar(VistaSync().detalle ?? "nada", "nada")
comprobar((0...7).map { String(Int(VistaSync.esperaBloqueado($0, azar: 0.5) / 60_000)) }.joined(separator: ","), "1,2,4,8,16,30,30,30")
comprobar(String(Int(VistaSync.esperaBloqueado(0, azar: 0))), "54000")
comprobar(String(Int(VistaSync.esperaBloqueado(0, azar: 1))), "66000")
comprobar(String(Int(VistaSync.esperaBloqueado(40, azar: 0.5) / 60_000)), "30")
comprobar(String(bloq.puedeIntentar(ahora: ahora + 30_000)), "false")
comprobar(String(bloq.puedeIntentar(ahora: ahora + 60_000)), "true")
comprobar(String(VistaSync(sinRed: true).puedeIntentar(ahora: ahora)), "true")
print("Estado de la sincronización: \(total - fallos)/\(total) bien")
exit(fallos == 0 ? 0 : 1)
