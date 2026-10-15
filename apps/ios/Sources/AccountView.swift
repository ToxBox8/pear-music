import SwiftUI
import UIKit

// MARK: - Por qué crear una cuenta
/// Opcional, ayuda a mejorar la app y pronto tendrá ventajas (lo pidió Toxbox). En Ajustes › Cuenta y en la guía
/// inicial. Mismo texto que `AccountPitch` en Android.
struct AccountPitch: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image("Logo").resizable().scaledToFit().frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Tu cuenta de Pear Music")).font(.title3.bold())
                    Text(L("Opcional · gratis")).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
            }
            Text(L("No la necesitas para nada: Pear Music funciona igual sin ella. Pero si te la creas nos ayudas muchísimo a mejorar la app, y tú te llevas tu música allá donde vayas."))
                .font(.callout).foregroundStyle(.secondary).padding(.top, 14).padding(.bottom, 6)
                .fixedSize(horizontal: false, vertical: true)
            point("lock.fill", 5, L("Tu biblioteca, cifrada en la nube"), L("Sólo tú tienes la clave. Ni siquiera nosotros podemos leerla."))
            point("iphone.gen3", 2, L("Pásala a otro móvil"), L("Playlists y favoritos en un minuto, también entre iPhone y Android."))
            point("heart.fill", 0, L("Ayudas a mejorar Pear Music"), L("Saber cuántos sois nos dice dónde poner el esfuerzo."))
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
/// Entrar con un código al correo; la biblioteca viaja cifrada con la clave de recuperación. Mismos pasos y textos
/// que `AccountScreen` en Android.
struct AccountView: View {
    @ObservedObject private var account = Account.shared

    var body: some View {
        Group {
            if account.state.email == nil { AccountSignIn() }
            else if !account.state.hasKey { AccountKeyStep(cloudHasLibrary: account.state.cloudHasLibrary) }
            else { AccountSignedIn() }
        }
        .navigationTitle(L("Cuenta"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}

private struct AccountSignIn: View {
    @State private var available: Bool?
    @State private var askingCode = false
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section { AccountPitch().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            Section {
                switch available {
                case nil: Text("Comprobando…").foregroundStyle(.secondary)
                case false?:
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Las cuentas estarán disponibles muy pronto"))
                        Text(L("Mientras tanto, todo funciona sin cuenta.")).font(.footnote).foregroundStyle(.secondary)
                    }
                case true?:
                    if askingCode {
                        TextField(L("Código de 6 cifras"), text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .onChange(of: code) { v in code = String(v.filter(\.isNumber).prefix(6)) }
                    } else {
                        TextField("tu@correo.com", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
                else if askingCode { Text(L("Te lo hemos mandado a {0}. Caduca en 10 minutos.", email)) }
            }
            .glassRow()
            if available == true {
                Section {
                    if askingCode {
                        Button(L("Entrar")) {
                            busy = true
                            Task {
                                do { try await Account.shared.signIn(email, code: code) } catch { self.error = error.localizedDescription }
                                busy = false
                            }
                        }
                        .disabled(busy || code.count != 6)
                        Button(L("Cambiar el correo")) { askingCode = false; code = "" }
                    } else {
                        Button(L("Mandarme un código")) {
                            busy = true; error = nil
                            Task {
                                do { try await Account.shared.requestCode(email); askingCode = true } catch { self.error = error.localizedDescription }
                                busy = false
                            }
                        }
                        .disabled(busy || !email.contains("@"))
                    }
                }
                .glassRow()
            }
        }
        .task { available = await Account.shared.available() }
    }
}

private struct AccountKeyStep: View {
    let cloudHasLibrary: Bool
    @EnvironmentObject var library: Library
    @State private var fresh = Account.newRecoveryKey()
    @State private var typing = false
    @State private var fromScratch = false
    @State private var typed = ""
    @State private var saved = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmScratch = false
    @State private var notice: String?

    var body: some View {
        Form {
            if !typing {
                Section {
                    Text(fresh).font(.title3.monospaced()).frame(maxWidth: .infinity).padding(.vertical, 8).textSelection(.enabled)
                    Button { UIPasteboard.general.string = fresh; notice = "Clave copiada" } label: { Label("Copiar", systemImage: "doc.on.doc") }
                    Toggle(L("La he guardado"), isOn: $saved)
                } header: {
                    Text(L("Tu clave de recuperación"))
                } footer: {
                    Text(L("Guárdala en tu gestor de contraseñas o apúntala. Es lo que cifra tu biblioteca: sin ella no se puede recuperar la copia de la nube en otro móvil. Pear Music no la guarda y no la puede recuperar."))
                }
                .glassRow()
                Section {
                    Button(L("Continuar")) {
                        busy = true
                        Account.shared.setRecoveryKey(fresh)
                        Task {
                            do { try await Account.shared.upload(library, overwrite: fromScratch || !cloudHasLibrary); notice = L("Biblioteca guardada en la nube") }
                            catch { notice = error.localizedDescription }
                            busy = false
                        }
                    }
                    .disabled(!saved || busy)
                    Button(L("Ya tengo una clave (de otro móvil)")) { typing = true }
                }
                .glassRow()
            } else {
                Section {
                    TextField("XXXX-XXXX-XXXX-…", text: $typed).font(.body.monospaced())
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                } header: {
                    Text(L("Escribe tu clave de recuperación"))
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else { Text(L("La que guardaste al crear la cuenta. 26 letras y números; da igual mayúsculas o guiones.")) }
                }
                .glassRow()
                Section {
                    Button(L("Traer mi biblioteca")) {
                        guard let key = Account.normalizeKey(typed) else { error = L("Esa clave no tiene el formato correcto."); return }
                        busy = true
                        Account.shared.setRecoveryKey(key)
                        Task {
                            do {
                                let added = try await Account.shared.download(library)
                                notice = L("Traídas {0} favoritas y {1} playlists", added.favorites, added.playlists)
                            } catch {
                                self.error = error.localizedDescription
                                Account.shared.setRecoveryKey(nil)
                            }
                            busy = false
                        }
                    }
                    .disabled(busy || typed.isEmpty)
                    Button(L("No tengo la clave: empezar de cero"), role: .destructive) { confirmScratch = true }
                }
                .glassRow()
            }
        }
        .onAppear { typing = cloudHasLibrary }
        .confirmationDialog(L("¿Empezar de cero?"), isPresented: $confirmScratch, titleVisibility: .visible) {
            Button(L("Empezar de cero"), role: .destructive) { fromScratch = true; typing = false }
            Button(L("Cancelar"), role: .cancel) {}
        } message: {
            Text(L("Se borrará la copia de la nube que no puedes abrir y se creará una clave nueva. La biblioteca de este móvil no se toca."))
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button(L("Vale"), role: .cancel) {} }
    }
}

private struct AccountSignedIn: View {
    @ObservedObject private var account = Account.shared
    @EnvironmentObject var library: Library
    @State private var busy = false
    @State private var notice: String?
    @State private var showKey = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Correo"), value: account.state.email ?? "")
                LabeledContent(L("Última copia en la nube"), value: account.state.lastSync.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? L("Nunca"))
            } footer: { Text(L("Tu biblioteca viaja cifrada con tu clave de recuperación: el servidor no puede leerla.")) }
            .glassRow()
            Section {
                Button { run { try await Account.shared.upload(library); return L("Biblioteca guardada") } } label: {
                    Label("Guardar ahora en la nube", systemImage: "icloud.and.arrow.up")
                }
                Button {
                    run {
                        let a = try await Account.shared.download(library)
                        return L("Traídas {0} favoritas y {1} playlists", a.favorites, a.playlists)
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Label("Traer de la nube", systemImage: "icloud.and.arrow.down")
                        Text(L("Une la copia con lo de este móvil, sin borrar nada")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button { showKey = true } label: { Label("Ver clave de recuperación", systemImage: "key.fill") }
            }
            .disabled(busy)
            .glassRow()
            Section {
                Button { Task { await Account.shared.signOut(); notice = L("Sesión cerrada") } } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Borrar la cuenta", systemImage: "person.crop.circle.badge.minus") }
            } footer: { Text(L("Borrar la cuenta elimina al momento tu correo y la copia de la nube. La biblioteca de este móvil se queda.")) }
            .disabled(busy)
            .glassRow()
        }
        .alert(L("Clave de recuperación"), isPresented: $showKey) {
            Button(L("Copiar")) { UIPasteboard.general.string = Account.shared.recoveryKey }
            Button(L("Cerrar"), role: .cancel) {}
        } message: { Text(Account.shared.recoveryKey ?? "") }
        .alert(L("¿Borrar tu cuenta?"), isPresented: $confirmDelete) {
            Button(L("Borrar la cuenta"), role: .destructive) { run { try await Account.shared.delete(); return L("Cuenta borrada") } }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { Text(L("Se borran tu correo y la copia de la nube. No se puede deshacer.")) }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button(L("Vale"), role: .cancel) {} }
    }

    private func run(_ work: @escaping () async throws -> String) {
        busy = true
        Task {
            do { notice = try await work() } catch { notice = error.localizedDescription }
            busy = false
        }
    }
}
