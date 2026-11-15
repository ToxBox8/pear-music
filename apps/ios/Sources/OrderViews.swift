import SwiftUI
import UIKit

// MARK: - Menús y gestos de la Biblioteca (paso B de la revisión del bloque 1; DECISIONS 40)
// Regla: mantener pulsado abre el menú; arrastrar sólo existe en el modo «Ordenar». Aquí están las piezas comunes
// del modo «Ordenar» (asa, barra de botones, texto de ayuda), el aviso para escribir un nombre y la confirmación de
// eliminar. Las reglas (`GridOrder`, `OrderDrag`) están en LibraryModel.swift. Igual que ui/OrderMode.kt en Android.

/// Marco de cada celda dentro de su cuadrícula o carrusel, para saber qué hueco hay bajo el dedo.
struct OrderFrameKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGRect] { [:] }
    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// El asa (≡) de una portada en el modo «Ordenar»: se arrastra al tocarla, sin esperar. Cápsula sumi con el signo
/// en washi, como «Soltar en …», para que se lea sobre cualquier portada en claro y en oscuro. Área de 44 pt.
struct OrderGrip: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Tokens.Brand.washi)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Tokens.Brand.sumi.opacity(0.78)))
            .overlay(Circle().strokeBorder(Tokens.Brand.washi.opacity(0.35), lineWidth: 1))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            // El asa es sólo para el dedo: con VoiceOver se elige la portada y se usan «Antes» y «Después».
            .accessibilityHidden(true)
    }
}

/// Aro de la portada elegida en el modo «Ordenar»: del color del texto (sumi en claro, washi en oscuro), no shu.
struct OrderSelection: ViewModifier {
    let on: Bool
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content.overlay {
            if on {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary, lineWidth: 2.5)
                    .padding(-7)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Cómo se usa el modo «Ordenar».
struct OrderHint: View {
    var body: some View {
        Text(L("Arrastra ≡ o toca una portada y usa los botones."))
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 4)
    }
}

/// Los botones del modo «Ordenar»: lo mismo que arrastrar, sin arrastrar. «Mover a…» (el único relleno shu) sólo
/// donde hay carpetas.
struct OrderButtons: View {
    let canBefore: Bool
    let canAfter: Bool
    /// nil = esta pantalla no tiene «Mover a…» (Fijados, Tus álbumes).
    var onMove: (() -> Void)? = nil
    var canMove = false
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { step(-1) } label: { Label(L("Antes"), systemImage: "chevron.left") }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(!canBefore)
            Button { step(1) } label: {
                HStack(spacing: 6) { Text(L("Después")); Image(systemName: "chevron.right") }
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .disabled(!canAfter)
            if let onMove {
                Button(action: onMove) { Text(L("Mover a…")) }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(!canMove)
            }
        }
    }
}

/// `OrderButtons` como barra fija abajo (Playlists y Tus álbumes).
struct OrderBar: View {
    let canBefore: Bool
    let canAfter: Bool
    var onMove: (() -> Void)? = nil
    var canMove = false
    let step: (Int) -> Void

    var body: some View {
        OrderButtons(canBefore: canBefore, canAfter: canAfter, onMove: onMove, canMove: canMove, step: step)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Escribir un nombre

/// El aviso para escribir un nombre (nueva playlist, nueva carpeta, renombrar). Es un aviso de UIKit y no un
/// `.alert` de SwiftUI por tres cosas: se puede abrir desde cualquier sitio (también desde el menú de una canción,
/// que no tiene dónde colgar un aviso), el botón se apaga con el nombre vacío en cualquier versión de iOS, e Intro
/// en el teclado hace lo mismo que el botón. Los botones van del color del texto, no en shu (DECISIONS 40).
enum NamePrompt {
    static func ask(_ title: String, initial: String = "", confirm: String = L("Crear"), onDone: @escaping (String) -> Void) {
        Task { @MainActor in present(title, initial: initial, confirm: confirm, onDone: onDone) }
    }

    @MainActor
    private static func present(_ title: String, initial: String, confirm: String, onDone: @escaping (String) -> Void) {
        guard let top = topController() else { return }
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let action = UIAlertAction(title: confirm, style: .default) { [weak alert] _ in
            let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { onDone(name) }
        }
        let filled: (String?) -> Bool = { !($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        action.isEnabled = filled(initial)
        alert.addTextField { field in
            field.placeholder = L("Nombre")
            field.text = initial
            field.autocapitalizationType = .sentences
            field.returnKeyType = .done
            field.clearButtonMode = .whileEditing
            field.addAction(UIAction { [weak action, weak field] _ in action?.isEnabled = filled(field?.text) }, for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: L("Cancelar"), style: .cancel))
        alert.addAction(action)
        alert.preferredAction = action
        // Sin texto shu (lo decidió Toxbox): los botones del color del texto, que se lee igual en claro y en oscuro.
        alert.view.tintColor = .label
        top.present(alert, animated: true)
    }

    /// La pantalla que está encima de todo (también de una hoja abierta).
    @MainActor
    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

// MARK: - Eliminar una playlist o un álbum

extension View {
    /// La confirmación de eliminar una playlist o un álbum guardado: la misma en Ajustes › Eliminar de la biblioteca y
    /// en el menú de cada portada (lo decidió Toxbox).
    func deletePlaylistAlert(_ pending: Binding<Playlist?>, library: Library, onDeleted: @escaping (Playlist) -> Void = { _ in }) -> some View {
        alert(L("¿Eliminar «{0}»?", pending.wrappedValue?.name ?? ""),
              isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } })) {
            Button(L("Eliminar"), role: .destructive) {
                if let p = pending.wrappedValue {
                    library.deletePlaylist(p.id)
                    onDeleted(p)
                }
                pending.wrappedValue = nil
            }
            Button(L("Cancelar"), role: .cancel) { pending.wrappedValue = nil }
        } message: {
            Text(L("Se quitará de tu biblioteca con su portada. Las canciones descargadas se quedan en Descargadas. No se puede deshacer."))
        }
    }
}
