import SwiftUI
import UIKit

// MARK: - Por qué crear una cuenta
/// Opcional, ayuda a mejorar la app y pronto tendrá ventajas (lo pidió Toxbox). En Ajustes › Cuenta y en la guía
/// inicial. Mismo texto que `AccountPitch` en Android.
struct AccountPitch: View {
    @Environment(\.accentFill) private var accentFill
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image("Logo").resizable().scaledToFit().frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Tu cuenta de Jiyu Pulse")).font(.title3.bold())
                    Text(L("Opcional · gratis")).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(accentFill.opacity(0.12)))
                }
            }
            Text(L("No la necesitas para nada: Jiyu Pulse funciona igual sin ella. Pero si te la creas nos ayudas muchísimo a mejorar la app, y tú te llevas tu música allá donde vayas."))
                .font(.callout).foregroundStyle(.secondary).padding(.top, 14).padding(.bottom, 6)
                .fixedSize(horizontal: false, vertical: true)
            point("lock.fill", 5, L("Tu biblioteca, cifrada en la nube"), L("Sólo tú tienes la clave. Ni siquiera nosotros podemos leerla."))
            point("iphone.gen3", 2, L("Pásala a otro móvil"), L("Playlists y favoritos en un minuto, también entre iPhone y Android."))
            point("heart.fill", 0, L("Ayudas a mejorar Jiyu Pulse"), L("Saber cuántos sois nos dice dónde poner el esfuerzo."))
            point("sparkles", 4, L("Muy pronto, ventajas"), L("Estamos preparando cosas solo para quien tenga cuenta. Te avisaremos en Avisos."))
        }
        .padding(.horizontal, 20).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
        .accessibilityElement(children: .combine)
    }

    private func point(_ icon: String, _ palette: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GradientIcon(systemName: icon, palette: palette, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Ajustes › Cuenta
/// La cuenta 3.0 sin contraseña (`CuentaViews.swift`, ADR 0004). La del correo (ADR 0001) nunca se desplegó para
/// usuarios y sus pantallas ya no se enseñan; `Account.swift` se quita cuando Toxbox confirme que no hay cuentas viejas
/// (2-C paso 1, «cama 17/PREGUNTAS.md» #1).
struct AccountView: View {
    var body: some View { CuentaView() }
}
