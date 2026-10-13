import Foundation

/// Fundido entre canciones (ajuste `crossfade`, en segundos; 0 = no). La canción baja de volumen en sus últimos N
/// segundos y la siguiente entra subiendo en N/2. No se solapan (eso pediría dos reproductores). Mismas reglas que
/// `Fade` en Android.
enum Fade {
    /// Opciones del ajuste.
    static let options = [0, 3, 6, 10]

    /// Factor de volumen en `position` de una canción de `duration` (segundos); `hasNext`: si al acabar suena otra.
    static func factor(position: Double, duration: Double, hasNext: Bool, seconds: Int) -> Float {
        guard seconds > 0, duration > 0 else { return 1 }
        let s = Double(seconds)
        let fadeOut = hasNext ? min(1, max(0, (duration - position) / s)) : 1
        let fadeIn = min(1, max(0, position / (s / 2)))
        // En canciones muy cortas los dos fundidos se juntarían y no se oiría entera: se usa el mayor de los dos.
        return Float(duration < s * 3 ? max(fadeIn, fadeOut) : min(fadeIn, fadeOut))
    }
}
