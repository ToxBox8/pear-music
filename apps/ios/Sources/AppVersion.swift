import Foundation

/// Versión completa de la app, con la etiqueta de beta (3.0, lo decidió Toxbox el 14-11-2026).
///
/// `CFBundleShortVersionString` sólo admite números (`3.0.0`), así que la beta lleva su nombre entero en la clave
/// `JiyuVersion` del Info.plist (`3.0.0-beta.1`, igual que `versionName` en Android). Se usa en el aviso de versión
/// nueva, Ajustes, el soporte y la telemetría. Si `JiyuVersion` falta o se quedó vieja (no empieza por la versión
/// numérica), manda `CFBundleShortVersionString`. Sólo Foundation: se prueba en Linux con `scripts/test-linux.sh`.
enum AppVersion {
    static var current: String { full(Bundle.main.infoDictionary ?? [:]) }

    static func full(_ info: [String: Any]) -> String {
        let short = (info["CFBundleShortVersionString"] as? String) ?? "1.0"
        guard let tagged = (info["JiyuVersion"] as? String)?.trimmingCharacters(in: .whitespaces), !tagged.isEmpty,
              tagged.split(separator: "-", maxSplits: 1).first.map(String.init) == short else { return short }
        return tagged
    }

    /// -1, 0 o 1. Semver con pre-releases (2.0.0-pre1 < 2.0.0, 3.0.0-beta.1 < 3.0.0-beta.2 < 3.0.0).
    /// Mismo algoritmo que `Updates.compare` en Android. Lo usa `Updates.compare`.
    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ v: String) -> ([Int], String?) {
            var clean = v.trimmingCharacters(in: .whitespaces)
            if clean.hasPrefix("v") { clean.removeFirst() }
            let pieces = clean.split(separator: "-", maxSplits: 1).map(String.init)
            var core = pieces[0].split(separator: ".").map { Int($0) ?? 0 }
            while core.count < 3 { core.append(0) }
            return (core, pieces.count > 1 ? pieces[1] : nil)
        }
        let (ca, pa) = parts(a), (cb, pb) = parts(b)
        for i in 0..<3 where ca[i] != cb[i] { return ca[i] < cb[i] ? -1 : 1 }
        switch (pa, pb) {
        case (nil, nil): return 0
        case (nil, _): return 1
        case (_, nil): return -1
        case let (x?, y?):
            let nx = Int(x.filter(\.isNumber)), ny = Int(y.filter(\.isNumber))
            if let nx, let ny, x.filter({ !$0.isNumber }) == y.filter({ !$0.isNumber }) { return nx == ny ? 0 : (nx < ny ? -1 : 1) }
            return x == y ? 0 : (x < y ? -1 : 1)
        }
    }
}
