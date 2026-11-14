// Tests de AppVersion (sólo Foundation) que corren en Linux: scripts/test-linux.sh. iOS no tiene objetivo de tests.
import Foundation

var fallos = 0
func igual<T: Equatable>(_ a: T, _ b: T, _ que: String) {
    if a != b { fallos += 1; print("❌ \(que): \(a) ≠ \(b)") }
}

// Versión completa: JiyuVersion manda sólo si empieza por CFBundleShortVersionString.
igual(AppVersion.full(["CFBundleShortVersionString": "3.0.0", "JiyuVersion": "3.0.0-beta.1"]), "3.0.0-beta.1", "beta")
igual(AppVersion.full(["CFBundleShortVersionString": "3.0.0"]), "3.0.0", "sin JiyuVersion")
igual(AppVersion.full(["CFBundleShortVersionString": "3.0.0", "JiyuVersion": " "]), "3.0.0", "JiyuVersion vacía")
igual(AppVersion.full(["CFBundleShortVersionString": "3.0.1", "JiyuVersion": "3.0.0-beta.1"]), "3.0.1", "JiyuVersion vieja")
igual(AppVersion.full(["CFBundleShortVersionString": "3.0.0", "JiyuVersion": "3.0.0"]), "3.0.0", "definitiva")
igual(AppVersion.full([:]), "1.0", "sin Info.plist")

// Mismos casos que UpdatesTest.kt (Android), más las betas de la 3.0.
igual(AppVersion.compare("1.0.0", "0.9.5"), 1, "1.0.0 > 0.9.5")
igual(AppVersion.compare("0.9.5", "1.0.0-pre1"), -1, "0.9.5 < 1.0.0-pre1")
igual(AppVersion.compare("1.0.0", "1.0.0-pre3"), 1, "1.0.0 > pre3")
igual(AppVersion.compare("1.0.0-pre10", "1.0.0-pre9"), 1, "pre10 > pre9")
igual(AppVersion.compare("v1.0.0", "1.0.0"), 0, "prefijo v")
igual(AppVersion.compare("1.0.1", "1.0"), 1, "1.0.1 > 1.0")
igual(AppVersion.compare("3.0.0-beta.2", "3.0.0-beta.1"), 1, "beta.2 > beta.1")
igual(AppVersion.compare("3.0.0", "3.0.0-beta.1"), 1, "definitiva > beta")
igual(AppVersion.compare("3.0.0-beta.1", "2.2.0"), 1, "beta 3.0 > 2.2.0")
igual(AppVersion.compare("3.0.0-beta.10", "3.0.0-beta.9"), 1, "beta.10 > beta.9")

print(fallos == 0 ? "AppVersion: todo bien." : "AppVersion: \(fallos) fallos.")
exit(fallos == 0 ? 0 : 1)
