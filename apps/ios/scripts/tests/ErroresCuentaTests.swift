import Foundation

// Orden 11: cada código de error del servidor (la tabla de docs/spec/cuenta.md §7.1, leída de la spec) y cada uno de la
// app da un texto propio, nunca el de «no lo conozco». Igual que ErroresCuentaTest en Android.
let spec = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "../../docs/spec/cuenta.md"
var fallos = 0, total = 0
func comprobar(_ ok: Bool, _ que: String) { total += 1; if !ok { fallos += 1; print("FALLA: \(que)") } }

let texto = try String(contentsOfFile: spec, encoding: .utf8)
var tabla = texto.components(separatedBy: "### 7.1 Códigos de error")[1]
tabla = tabla.components(separatedBy: "\n## ")[0]
let re = try NSRegularExpression(pattern: "^\\| `([a-z_]+)` \\|", options: .anchorsMatchLines)
let codigos = re.matches(in: tabla, range: NSRange(tabla.startIndex..., in: tabla))
    .map { String(tabla[Range($0.range(at: 1), in: tabla)!]) }.filter { $0 != "codigo" }
comprobar(codigos.count == 23, "la tabla de §7.1 tiene 23 códigos (salen \(codigos.count))")
let desconocido = CuentaErrores.mensaje("codigo_que_no_existe").components(separatedBy: "(")[0]
for c in codigos {
    let m = CuentaErrores.mensaje(c)
    comprobar(!m.hasPrefix(desconocido), "«\(c)» no tiene texto propio: \(m)")
    comprobar(!m.contains("Algo ha fallado"), "«\(c)»: nada de «Algo ha fallado»")
}
for c in ["sin_conexion", "bloqueado", "servidor_caido", "incidente", "version_bloque", "bloque_roto", "sin_cuenta",
          "clave_sin_cuenta", "cuenta_llena", "movil_ya_en_cuenta", "sin_borrado", "movil_no_encontrado", "clave_invalida",
          "no_es_la_cuenta", "presencia", "nombre_invalido", "tope_altas", "qr_invalido", "qr_adelantado", "no_anadido"] {
    comprobar(!CuentaErrores.mensaje(c).hasPrefix(desconocido), "«\(c)» no tiene texto propio")
}
comprobar(CuentaErrores.mensaje("http_418").contains("http_418"), "el que no se conoce dice cuál")
print("Errores de la cuenta: \(total - fallos)/\(total) bien")
exit(fallos == 0 ? 0 : 1)
