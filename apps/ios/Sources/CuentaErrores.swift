import Foundation

/// Los textos de los errores de la cuenta (cuenta.md §7.1 y los de la app). Sólo Foundation: `scripts/test-linux.sh`
/// comprueba que cada código de la spec tiene el suyo (ErroresCuentaTests), como `ErroresCuentaTest` en Android.
enum CuentaErrores {
    /// Lo que se enseña; discreto, nunca corta la música. Un texto claro por cada código de cuenta.md §7.1 y por los
    /// de la app (orden 11: nada de «Algo ha fallado»). Los que dependen de la operación (`ya_existe`,
    /// `no_encontrado`) los traduce quien llama a uno más concreto. Igual que `ErrorCuenta.mensaje` en Android.
    static func mensaje(_ codigo: String) -> String {
        switch codigo {
        // Red y servidor
        case "sin_conexion": return L("Sin conexión. Cuando vuelva, prueba otra vez")
        case "bloqueado": return L("Conexión bloqueada temporalmente. La música sigue funcionando")
        case "servidor_caido": return L("El servidor no responde ahora. Prueba otra vez dentro de un rato")
        case "error_interno": return L("El servidor ha tenido un problema. Prueba otra vez dentro de un rato")
        case "mantenimiento": return L("La cuenta está en mantenimiento. Vuelve en un rato; la música sigue igual")
        case "servicio_no_disponible", "incidente": return L("La cuenta no está disponible ahora; puedes seguir escuchando")
        case "limite_diario": return L("La cuenta ha llegado a su límite de hoy. Mañana vuelve a funcionar; la música sigue igual")
        case "demasiadas_peticiones": return L("Demasiados intentos. Prueba dentro de un rato")
        case "demasiado_pronto": return L("Espera un poco antes de volver a intentarlo")
        case "peticion_invalida": return L("El servidor no ha entendido la petición. Actualiza Jiyu Pulse y prueba otra vez")
        case "demasiado_grande": return L("Es demasiado grande para enviarlo")
        case "cuota_superada": return L("Tu cuenta ya ocupa el máximo (20 MB)")
        case "version_cambiada": return L("Otro móvil ha cambiado lo mismo a la vez. Prueba otra vez")
        case "version_bloque": return L("Actualiza la app para ver tu biblioteca")
        case "bloque_roto": return L("Tu biblioteca de la nube no se puede abrir")
        // Sesión y firmas
        case "token_invalido", "token_caducado": return L("Tu sesión ha caducado. Prueba otra vez")
        case "firma_invalida": return L("El servidor no reconoce este móvil. Si sigue pasando, entra otra vez con tu clave")
        case "nonce_repetido": return L("Esa petición ya se había enviado. Prueba otra vez")
        case "reloj_desfasado": return L("La hora del móvil no está bien. Ponla en automática y prueba otra vez")
        case "turnstile_invalido": return L("No hemos podido comprobar que eres una persona. Prueba otra vez")
        case "dispositivo_revocado": return L("Este móvil ya no está en tu cuenta")
        case "sin_cuenta": return L("No hay ninguna cuenta en este móvil")
        case "terminos_pendientes", "terminos_nuevos": return L("Hay términos nuevos que aceptar")
        // Según la operación
        case "no_encontrado": return L("No se ha encontrado. Puede que ya no exista")
        case "ya_existe": return L("Eso ya existe. Prueba otra vez")
        case "clave_sin_cuenta": return L("No hay ninguna cuenta con esa clave")
        case "cuenta_llena": return L("Ya hay 10 móviles en tu cuenta. Quita uno antes")
        case "movil_ya_en_cuenta": return L("Este móvil ya está en una cuenta")
        case "sin_borrado": return L("No había ningún borrado pendiente")
        case "movil_no_encontrado": return L("Ese móvil ya no está en tu cuenta")
        // De la app
        case "clave_invalida": return L("Esa clave no es válida")
        case "no_es_la_cuenta": return L("No se ha podido abrir tu cuenta con esa clave")
        case "presencia": return L("Hace falta Face ID, huella o el código del móvil")
        case "nombre_invalido": return L("Pon un nombre de 1 a 40 caracteres")
        case "tope_altas": return L("Ahora no se pueden crear cuentas; prueba mañana")
        case "qr_invalido": return L("Este código no es válido")
        case "emparejamiento_caducado": return L("El código ha caducado. Prueba otra vez")
        case "emparejamiento_usado": return L("Este código ya se ha usado. Prueba otra vez")
        case "qr_adelantado": return L("Otro móvil ha usado este código antes que tú. En el móvil nuevo, pulsa «No coinciden» y empieza otra vez")
        case "no_anadido": return L("No se ha podido añadir este móvil")
        // Uno que esta versión no conoce: se dice cuál (sirve para un reporte), nunca «Algo ha fallado».
        // Uno que esta versión no conoce: se dice cuál (sirve para un reporte), nunca «Algo ha fallado».
        default: return L("No ha salido bien ({0}). Prueba otra vez dentro de un rato", codigo)
        }
    }
}
