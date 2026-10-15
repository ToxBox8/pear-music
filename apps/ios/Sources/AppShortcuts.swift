import AppIntents
import SwiftUI

/// Lo que ha pedido un atajo de Siri / Atajos al abrir la app; lo consume `RootView`.
@MainActor
final class ShortcutRouter: ObservableObject {
    static let shared = ShortcutRouter()
    enum Kind: String { case favorites, downloads, discover, search }
    @Published var pending: Kind?
}

/// Atajos de Siri y de la app Atajos: los mismos cuatro que los del icono en Android (`AppShortcuts.kt`).
/// App Intents no necesita ningún permiso de Apple, así que funciona también instalada con AltStore o SideStore.
@available(iOS 16.0, *)
struct ShuffleFavoritesIntent: AppIntent {
    static let title: LocalizedStringResource = "Mezclar mis favoritas"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { ShortcutRouter.shared.pending = .favorites; return .result() }
}

@available(iOS 16.0, *)
struct ShuffleDownloadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Mezclar lo descargado"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { ShortcutRouter.shared.pending = .downloads; return .result() }
}

@available(iOS 16.0, *)
struct OpenDiscoverIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir Descubrir"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { ShortcutRouter.shared.pending = .discover; return .result() }
}

@available(iOS 16.0, *)
struct OpenSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Buscar música"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { ShortcutRouter.shared.pending = .search; return .result() }
}

@available(iOS 16.0, *)
struct LibreMusicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShuffleFavoritesIntent(), phrases: ["Mezcla mis favoritas en \(.applicationName)", "Pon mis favoritas en \(.applicationName)"])
        AppShortcut(intent: ShuffleDownloadsIntent(), phrases: ["Pon lo descargado en \(.applicationName)"])
        AppShortcut(intent: OpenDiscoverIntent(), phrases: ["Abre Descubrir en \(.applicationName)"])
        AppShortcut(intent: OpenSearchIntent(), phrases: ["Busca música en \(.applicationName)"])
    }
}
