import SwiftUI

/// Elegir idioma (Cierre 1.0; lo pidió Toxbox): banderas, y al tocar la de España se despliegan español, catalán,
/// valenciano, gallego y euskera. Inglés (Reino Unido) y esperanto aparte. En la bienvenida y en Ajustes › Idioma.
/// Igual que `LanguagePicker` en Android.
struct LanguagePicker: View {
    @AppStorage("language") private var language = ""
    @State private var spainOpen = true

    private var current: String { I18n.current }
    private var spain: [I18n.Lang] { I18n.langs.filter(\.spain) }

    var body: some View {
        Section {
            Button {
                withAnimation(.uiEaseOut(0.3)) { spainOpen.toggle() }
            } label: {
                HStack(spacing: 14) {
                    FlagView(code: "es").frame(width: 34, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("España")).foregroundStyle(.primary)
                        Text(spain.map(\.name).joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(spainOpen ? 180 : 0))
                }
            }
            if spainOpen {
                ForEach(spain) { l in row(l).padding(.leading, 18) }
            }
            ForEach(I18n.langs.filter { !$0.spain }) { l in row(l) }
        }
        .glassRow()
        .onAppear { spainOpen = spain.contains { $0.id == current } }
    }

    private func row(_ l: I18n.Lang) -> some View {
        Button {
            I18n.set(l.id)
            language = l.id
        } label: {
            HStack(spacing: 14) {
                FlagView(code: l.id).frame(width: 34, height: 24)
                Text(l.name).foregroundStyle(.primary)
                Spacer()
                if current == l.id { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel(L("Elegido")) }
            }
        }
    }
}

/// Banderas dibujadas (sin emoji: se ven igual en todos los móviles). Mismos colores que Android.
struct FlagView: View {
    let code: String

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func rect(_ r: CGRect, _ c: Color) { ctx.fill(Path(r), with: .color(c)) }
            func stripes(_ parts: [(Color, CGFloat)]) {
                let total = parts.reduce(0) { $0 + $1.1 }
                var y: CGFloat = 0
                for (c, weight) in parts {
                    let hh = h * weight / total
                    rect(CGRect(x: 0, y: y, width: w, height: hh + 0.5), c)
                    y += hh
                }
            }
            func line(_ a: CGPoint, _ b: CGPoint, _ c: Color, _ width: CGFloat) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(c), lineWidth: width)
            }
            let senyera = (0..<9).map { ($0 % 2 == 0 ? Color(hex: 0xFCDD09) : Color(hex: 0xDA121A), CGFloat(1)) }
            switch code {
            case "es": stripes([(Color(hex: 0xAA151B), 1), (Color(hex: 0xF1BF00), 2), (Color(hex: 0xAA151B), 1)])
            case "ca": stripes(senyera)
            case "va":
                stripes(senyera)
                rect(CGRect(x: 0, y: 0, width: w * 0.26, height: h), Color(hex: 0x0B57A4))
            case "gl":
                rect(CGRect(x: 0, y: 0, width: w, height: h), .white)
                var p = Path()
                p.move(to: .zero); p.addLine(to: CGPoint(x: w * 0.16, y: 0)); p.addLine(to: CGPoint(x: w, y: h * 0.84))
                p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w * 0.84, y: h)); p.addLine(to: CGPoint(x: 0, y: h * 0.16))
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(hex: 0x0099CC)))
            case "eu":
                rect(CGRect(x: 0, y: 0, width: w, height: h), Color(hex: 0xD52B1E))
                let lw = h * 0.16
                line(.zero, CGPoint(x: w, y: h), Color(hex: 0x009B48), lw)
                line(CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), Color(hex: 0x009B48), lw)
                line(CGPoint(x: w / 2, y: 0), CGPoint(x: w / 2, y: h), .white, lw)
                line(CGPoint(x: 0, y: h / 2), CGPoint(x: w, y: h / 2), .white, lw)
            case "en":
                rect(CGRect(x: 0, y: 0, width: w, height: h), Color(hex: 0x012169))
                line(.zero, CGPoint(x: w, y: h), .white, h * 0.2)
                line(CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), .white, h * 0.2)
                line(.zero, CGPoint(x: w, y: h), Color(hex: 0xC8102E), h * 0.07)
                line(CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), Color(hex: 0xC8102E), h * 0.07)
                rect(CGRect(x: w / 2 - h * 0.17, y: 0, width: h * 0.34, height: h), .white)
                rect(CGRect(x: 0, y: h / 2 - h * 0.17, width: w, height: h * 0.34), .white)
                rect(CGRect(x: w / 2 - h * 0.1, y: 0, width: h * 0.2, height: h), Color(hex: 0xC8102E))
                rect(CGRect(x: 0, y: h / 2 - h * 0.1, width: w, height: h * 0.2), Color(hex: 0xC8102E))
            case "pt":
                // Portugal: verde y rojo (2:3) con la esfera armilar amarilla en la unión.
                rect(CGRect(x: 0, y: 0, width: w * 0.4, height: h), Color(hex: 0x006600))
                rect(CGRect(x: w * 0.4, y: 0, width: w * 0.6, height: h), Color(hex: 0xFF0000))
                let c = CGPoint(x: w * 0.4, y: h / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - h * 0.24, y: c.y - h * 0.24, width: h * 0.48, height: h * 0.48)), with: .color(Color(hex: 0xFFCC00)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - h * 0.13, y: c.y - h * 0.13, width: h * 0.26, height: h * 0.26)), with: .color(Color(hex: 0xFF0000)))
            case "eo":
                let green = Color(hex: 0x009900)
                rect(CGRect(x: 0, y: 0, width: w, height: h), green)
                let s = h / 2
                rect(CGRect(x: 0, y: 0, width: s, height: s), .white)
                var star = Path()
                for i in 0..<10 {
                    let r = (i % 2 == 0 ? s * 0.36 : s * 0.15)
                    let a = (-90.0 + Double(i) * 36.0) * .pi / 180
                    let pt = CGPoint(x: s / 2 + r * cos(a), y: s / 2 + r * sin(a))
                    if i == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
                }
                star.closeSubpath()
                ctx.fill(star, with: .color(green))
            default: break
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Ajustes › Idioma.
struct LanguageSettings: View {
    var body: some View {
        Form {
            Section {} footer: { Text(L("Toda la app cambia al momento. Lo que aún no está traducido se ve en español.")) }
            LanguagePicker()
        }
        .navigationTitle(L("Idioma"))
        .navigationBarTitleDisplayMode(.inline)
        .themed()
    }
}
