import Foundation

// Modo fútbol (Pulir 2 #2, DECISIONS 100): el reintento que vuelve a fallar programa el siguiente sin cancelarse a sí
// mismo, así que lo que va después en ese intento (las estadísticas) se hace. Igual que ModoFutbolTest en Android.
var fallos = 0, total = 0
func comprobar(_ a: String, _ b: String, _ que: String) { total += 1; if a != b { fallos += 1; print("FALLA (\(que)): «\(a)» en vez de «\(b)»") } }

@MainActor func pruebas() async {
    // Tres intentos bloqueados seguidos: cada uno programa el siguiente desde dentro y aun así termina.
    let r = ReintentoBloqueado()
    var intentos = 0, terminados = 0
    func fallar() {
        r.programar(espera: 5) {
            intentos += 1
            if intentos < 3 { fallar() } // vuelve a dar «bloqueado»: alFallar programa el siguiente
            try? await Task.sleep(nanoseconds: 3_000_000) // lo que va después: las estadísticas
            if !Task.isCancelled { terminados += 1 }
        }
    }
    fallar()
    try? await Task.sleep(nanoseconds: 300_000_000)
    comprobar(String(intentos), "3", "se reintenta cada vez")
    comprobar(String(terminados), "3", "el reintento que vuelve a fallar no se cancela a sí mismo")
    comprobar(String(r.esperando), "false", "al acabar no queda ninguno esperando")

    // Cancelar (salió bien o falló por otra cosa): el que espera no llega a hacerse.
    let r2 = ReintentoBloqueado()
    var hecho = 0
    r2.programar(espera: 50) { hecho += 1 }
    comprobar(String(r2.esperando), "true", "hay uno esperando")
    r2.cancelar()
    try? await Task.sleep(nanoseconds: 120_000_000)
    comprobar(String(hecho), "0", "cancelado antes de tiempo no se hace")

    // Programar otro sustituye al que espera: sólo se hace el último.
    var cual = ""
    r2.programar(espera: 40) { cual += "a" }
    r2.programar(espera: 10) { cual += "b" }
    try? await Task.sleep(nanoseconds: 120_000_000)
    comprobar(cual, "b", "sólo el último que espera")
}

await pruebas()
print("Reintento del modo fútbol: \(total - fallos)/\(total) bien")
exit(fallos == 0 ? 0 : 1)
