import SwiftUI
import Compression
import CoreImage.CIFilterBuiltins

/// Compartir una playlist con un QR, sin servidor (0.6 de x.1.1). El QR es un enlace
/// `libremusic://playlist?v=1&d=<datos>`; `datos` = JSON `{"n": nombre, "i": ids seguidos (11 caracteres cada uno),
/// "ic": icono, "t": color}` comprimido con deflate sin cabecera y en base64url. Sólo van los ids, en orden: el título
/// y el artista se piden a YouTube Music al importar (así caben hasta `maxSongs` en un QR que se lee desde otra
/// pantalla). Una foto propia no viaja. Formato: docs/LIBRARY_FORMAT.md › Compartir. Igual que `PlaylistShare` en
/// Android.
enum PlaylistShare {
    static let maxSongs = 150
    private static let maxName = 100
    private static let prefix = "libremusic://playlist?v=1&d="

    struct Payload: Equatable, Identifiable {
        let name: String
        let ids: [String]
        var icon: String?
        var tint: Int?
        var id: String { ids.joined() }
    }

    private static func validID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// El enlace de la playlist, o nil si no hay canciones o son demasiadas para un QR.
    static func link(name: String, ids: [String], icon: String?, tint: Int?) -> String? {
        guard !ids.isEmpty, ids.count <= maxSongs, ids.allSatisfy(validID) else { return nil }
        var o: [String: Any] = ["n": String(name.prefix(maxName)), "i": ids.joined()]
        if let icon { o["ic"] = String(icon.prefix(64)) }
        if let tint { o["t"] = tint }
        guard let json = try? JSONSerialization.data(withJSONObject: o), let packed = deflate(json) else { return nil }
        return prefix + packed.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Lo que trae un enlace (o el texto de un QR), o nil si no es una playlist válida.
    static func decode(_ text: String) -> Payload? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix(prefix) else { return nil }
        var b64 = String(t.dropFirst(prefix.count).prefix { $0 != "&" && $0 != "#" })
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let raw = inflate(data),
              let o = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any], let joined = o["i"] as? String,
              !joined.isEmpty, joined.count % 11 == 0, joined.count / 11 <= maxSongs else { return nil }
        let chars = Array(joined)
        let ids = stride(from: 0, to: chars.count, by: 11).map { String(chars[$0..<$0 + 11]) }
        guard ids.allSatisfy(validID) else { return nil }
        return Payload(name: String((o["n"] as? String ?? "").prefix(maxName)), ids: ids,
                       icon: (o["ic"] as? String).map { String($0.prefix(64)) }, tint: o["t"] as? Int)
    }

    private static func deflate(_ data: Data) -> Data? {
        var out = Data(count: data.count + 1024)
        let n = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, dst.count,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 ? out.prefix(n) : nil
    }

    /// Con tope: unos datos maliciosos no pueden inflarse a gigas.
    private static func inflate(_ data: Data, max: Int = 64 * 1024) -> Data? {
        var out = Data(count: max)
        let n = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, max,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 && n < max ? out.prefix(n) : nil
    }

    /// QR en blanco y negro (corrección baja: el enlace es largo y así los cuadros son más grandes).
    static func qrImage(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "L"
        guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// El enlace recibido al abrir la app (cámara del sistema o «Compartir enlace»): la raíz enseña la vista previa.
@MainActor
final class PlaylistInbox: ObservableObject {
    static let shared = PlaylistInbox()
    @Published var incoming: PlaylistShare.Payload?
    /// true si el enlace era de una playlist (si no, lo trata quien toque, p. ej. el Jam).
    func receive(_ url: URL) -> Bool {
        guard let p = PlaylistShare.decode(url.absoluteString) else { return false }
        incoming = p
        return true
    }
}

/// «Compartir con QR» de una playlist (0.6 de x.1.1). Igual que `SharePlaylistContent` en Android.
struct SharePlaylistSheet: View {
    let playlist: Playlist
    var body: some View {
        let link = PlaylistShare.link(name: playlist.name, ids: playlist.songs.map(\.id), icon: playlist.icon, tint: playlist.tint)
        VStack(spacing: 14) {
            Text(playlist.name).font(.title2.bold()).multilineTextAlignment(.center)
            if let link, let qr = PlaylistShare.qrImage(link) {
                // Siempre sobre blanco, también en modo oscuro: así lo lee cualquier cámara.
                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 280, height: 280).padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel(L("Código QR de {0}", playlist.name))
                Text(L("Escanéalo con la cámara de otro móvil con Pear Music. Viajan el nombre, las {0} canciones y su orden.", playlist.songs.count)
                     + (PlaylistArt.exists(playlist.id) ? L(" La foto de la portada no cabe en el QR.") : ""))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let url = URL(string: link) {
                    ShareLink(item: url) { Label(L("Compartir enlace"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
            } else {
                Text(playlist.songs.isEmpty ? L("Esta playlist está vacía.") : L("Tiene demasiadas canciones para un QR (como mucho {0}).", PlaylistShare.maxSongs))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .presentationDetents([.large])
        .themed()
    }
}

/// Al abrir un enlace de playlist (0.6 de x.1.1): vista previa y «Añadir a la biblioteca». Los títulos se piden a
/// YouTube Music en ese momento. Igual que `SharedPlaylistContent` en Android.
struct SharedPlaylistSheet: View {
    let payload: PlaylistShare.Payload
    let onDone: (UUID?) -> Void
    @EnvironmentObject var library: Library
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            Text(L("Playlist compartida")).font(.caption).foregroundStyle(.secondary)
            Text(payload.name.isEmpty ? L("Sin nombre") : payload.name).font(.title2.bold()).multilineTextAlignment(.center)
            Text(songCount(payload.ids.count)).foregroundStyle(.secondary)
            if let error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
            Button {
                busy = true
                error = nil
                Task {
                    let songs = await YTClient.songs(ids: payload.ids)
                    busy = false
                    guard !songs.isEmpty else { error = L("No se pudieron cargar las canciones. Revisa la conexión y vuelve a intentarlo."); return }
                    onDone(library.importShared(name: payload.name, songs: songs, icon: payload.icon, tint: payload.tint))
                }
            } label: { Text(busy ? L("Añadiendo…") : L("Añadir a la biblioteca")).frame(maxWidth: .infinity) }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(busy)
            Button(L("Ahora no")) { onDone(nil) }
        }
        .padding(24)
        .presentationDetents([.medium])
        .themed()
    }
}
