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
// Revisión del bloque 2, B2-6: el límite de la sync por dispositivo. Pendiente, sin «sin conexión»; el pie dice por qué;
// no se intenta antes del Retry-After (15 min si no viene; entre 1 min y 1 h).
var lim = VistaSync(ultimaOk: ahora, pendiente: true); lim.limitado = true; lim.reintentoEn = ahora + 1_200_000
comprobar(t(lim), "Pendiente de subir")
comprobar(lim.detalle ?? "", "Has sincronizado muchas veces en poco rato. Lo pendiente se subirá solo dentro de un rato")
comprobar(String(lim.puedeIntentar(ahora: ahora + 600_000)), "false")
comprobar(String(lim.puedeIntentar(ahora: ahora + 1_200_000)), "true")
comprobar(String(Int(VistaSync.esperaLimitado(nil))), "900000")
comprobar(String(Int(VistaSync.esperaLimitado(3))), "60000")
comprobar(String(Int(VistaSync.esperaLimitado(99_999))), "3600000")
// B2-8: «Cerrar sesión» conserva «No sincronizar esto» con su cuenta; quitado desde otro (sin conservar), no; al entrar en
// la misma cuenta siguen, en otra se olvidan.
let cerrada = MarcasSoloAqui.alSalir(["playlist:b", "playlist:a"], cuenta: "1X99", conservar: true)
comprobar(cerrada.map { $0.marcas.joined(separator: ",") + "@" + $0.cuenta } ?? "nada", "playlist:a,playlist:b@1X99")
comprobar(MarcasSoloAqui.alSalir(["playlist:a"], cuenta: "1X99", conservar: false) == nil ? "nada" : "algo", "nada")
comprobar(MarcasSoloAqui.alSalir([], cuenta: "1X99", conservar: true) == nil ? "nada" : "algo", "nada")
comprobar(String(MarcasSoloAqui.siguen(en: "1X99", de: "1X99")), "true")
comprobar(String(MarcasSoloAqui.siguen(en: "2B88", de: "1X99")), "false")
comprobar(String(MarcasSoloAqui.siguen(en: "2B88", de: nil)), "true")
print("Estado de la sincronización: \(total - fallos)/\(total) bien")
exit(fallos == 0 ? 0 : 1)
