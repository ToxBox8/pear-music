import Foundation

/// Primera capa contra reportes no genuinos, antes de gastar el envío: las mismas reglas que el Worker
/// (`services/soporte/src/spam.js`) y que `SupportFilter` en Android. Si cambian allí, se cambian aquí en el mismo
/// commit. Devuelve nil si se puede enviar, o el motivo.
enum SupportFilter {
    private static let strong = [
        "hijo de puta", "hija de puta", "hijoputa", "subnormal", "retrasado", "gilipollas", "malparido", "maricon",
        "puta madre que te pario", "me cago en tu", "muerete", "ojala te mueras", "te voy a matar", "kill yourself",
        "kys", "son of a bitch", "motherfucker", "retard", "faggot",
    ]
    private static let mild: Set<String> = [
        "puta", "puto", "mierda", "joder", "cabron", "cabrona", "imbecil", "idiota", "estupido", "estupida", "tonto",
        "tonta", "pendejo", "pendeja", "capullo", "zorra", "coño", "cono", "polla", "fuck", "fucking", "shit", "bitch",
        "asshole", "dick", "cunt", "stupid", "idiot", "moron",
    ]

    static func problem(_ raw: String) -> String? { textProblem(raw) ?? abuseProblem(raw) }

    private static func count(_ pattern: String, in s: String, _ options: NSRegularExpression.Options = []) -> Int {
        (try? NSRegularExpression(pattern: pattern, options: options))?.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s)) ?? 0
    }
    private static func matches(_ pattern: String, in s: String, _ options: NSRegularExpression.Options = []) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

    static func textProblem(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if count("https?://|www\\.", in: text, .caseInsensitive) > 2 { return "Demasiados enlaces. Cuenta qué ha pasado con tus palabras." }
        let noUrls = text.replacingOccurrences(of: "\\S*(https?://|www\\.)\\S*", with: " ", options: [.regularExpression, .caseInsensitive])
        let letters = count("\\p{L}", in: noUrls)
        let visible = noUrls.replacingOccurrences(of: "\\s", with: "", options: .regularExpression).count
        if visible == 0 || Double(letters) / Double(visible) < 0.5 { return "El texto no se entiende. Cuenta qué ha pasado con palabras." }
        if count("(.)\\1{5,}", in: noUrls) > 0 { return "El texto no se entiende (hay letras repetidas). Cuenta qué ha pasado." }
        let real = matches("\\p{L}+", in: noUrls.lowercased()).filter { $0.count >= 2 }
        if real.count < 3 { return "Cuenta un poco más qué ha pasado (al menos una frase)." }
        let distinct = Set(real).count
        if distinct < min(3, real.count) || (real.count >= 6 && Double(distinct) / Double(real.count) < 0.3) {
            return "El texto se repite mucho. Cuenta qué ha pasado."
        }
        let odd = real.filter { w in
            (w.count >= 4 && count("[aeiouáéíóúüàèìòùâêîôûäëïöy]", in: w, .caseInsensitive) == 0)
                || count("[^aeiouáéíóúüy\\s]{5,}", in: w, .caseInsensitive) > 0
        }.count
        if Double(odd) / Double(real.count) > 0.34 { return "El texto no se entiende. Cuenta qué ha pasado con palabras." }
        let vowels = count("[aeiouáéíóúü]", in: noUrls, .caseInsensitive)
        if letters >= 20 && (Double(vowels) / Double(letters) < 0.2 || Double(vowels) / Double(letters) > 0.75) {
            return "El texto no se entiende. Cuenta qué ha pasado con palabras."
        }
        return nil
    }

    static func abuseProblem(_ raw: String) -> String? {
        let text = raw.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        if strong.contains(where: { text.contains($0) }) {
            return "El mensaje tiene insultos. Cuéntanos qué ha fallado sin ellos y lo miramos encantados."
        }
        let words = matches("\\p{L}+", in: text)
        let n = words.filter { mild.contains($0) }.count
        if n >= 3 || (!words.isEmpty && Double(n) / Double(words.count) > 0.15) {
            return "El mensaje tiene demasiadas palabrotas. Cuéntanos qué ha fallado con calma y lo miramos."
        }
        return nil
    }
}
