import Foundation

/// Idiomas (Cierre 1.0; lo pidió Toxbox): español, catalán, valenciano, gallego, euskera, inglés y esperanto. Los
/// textos van en español dentro de `L("…")`; el catálogo común está en `shared/i18n/<idioma>.json` y `tools/i18n/`
/// lo copia a `Sources/I18n/`. Lo que falte se ve en español. Igual que `I18n` en Android.
enum I18n {
    struct Lang: Identifiable { let id: String; let name: String; let spain: Bool }

    static let langs: [Lang] = [
        Lang(id: "es", name: "Español", spain: true),
        Lang(id: "ca", name: "Català", spain: true),
        Lang(id: "va", name: "Valencià", spain: true),
        Lang(id: "gl", name: "Galego", spain: true),
        Lang(id: "eu", name: "Euskara", spain: true),
        Lang(id: "en", name: "English", spain: false),
        Lang(id: "eo", name: "Esperanto", spain: false),
    ]

    private static let lock = NSLock()
    private static var table: [String: String] = [:]
    private(set) static var current = "es"

    /// El del sistema si es uno de los nuestros; si no, español.
    static func systemDefault() -> String {
        let id = Locale.preferredLanguages.first?.lowercased() ?? "es"
        if id.hasPrefix("ca") { return id.contains("valencia") ? "va" : "ca" }
        for code in ["gl", "eu", "en", "eo"] where id.hasPrefix(code) { return code }
        return "es"
    }

    static var chosen: Bool { UserDefaults.standard.string(forKey: "language") != nil }

    static func load() { apply(UserDefaults.standard.string(forKey: "language") ?? systemDefault()) }

    static func set(_ code: String) {
        apply(code)  // antes de guardarlo: al guardarlo, la app se vuelve a dibujar con la tabla nueva
        UserDefaults.standard.set(code, forKey: "language")
    }

    private static func apply(_ code: String) {
        let l = langs.contains { $0.id == code } ? code : "es"
        var t: [String: String] = [:]
        if l != "es", let url = Bundle.main.url(forResource: l, withExtension: "json"),
           let data = try? Data(contentsOf: url), let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            t = dict.filter { !$0.value.isEmpty }
        }
        lock.lock(); table = t; current = l; lock.unlock()
    }

    static func t(_ s: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return table[s] ?? s
    }
}

/// Texto en el idioma elegido. `{0}`, `{1}`… se cambian por los argumentos en orden.
func L(_ s: String, _ args: Any...) -> String {
    var r = I18n.t(s)
    for (i, v) in args.enumerated() { r = r.replacingOccurrences(of: "{\(i)}", with: "\(v)") }
    return r
}
