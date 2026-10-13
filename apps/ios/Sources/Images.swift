import SwiftUI
import UIKit

// MARK: - Carátulas con caché
// AsyncImage cancela la descarga si la vista se redibuja mientras carga (el mini
// reproductor lo hace cada 0,5 s con el progreso) y se queda en el placeholder.
// Este cargador comparte una caché en memoria y no depende del ciclo de la vista.
/// NSCache es seguro entre hilos: se lee de forma síncrona al crear la vista para que
/// una carátula ya cargada aparezca al instante (sin parpadeo) aunque la vista se recree.
let imageMemory: NSCache<NSURL, UIImage> = {
    let c = NSCache<NSURL, UIImage>()
    c.countLimit = 300
    return c
}()

actor ImageCache {
    static let shared = ImageCache()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    func image(for url: URL) async -> UIImage? {
        if let img = imageMemory.object(forKey: url as NSURL) { return img }
        if let task = inFlight[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return UIImage(data: data)
        }
        inFlight[url] = task
        let img = await task.value
        inFlight[url] = nil
        if let img { imageMemory.setObject(img, forKey: url as NSURL) }
        return img
    }
}

struct CoverImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholder = true
    @State private var image: UIImage?

    init(url: URL?, contentMode: ContentMode = .fill, placeholder: Bool = true) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { imageMemory.object(forKey: $0 as NSURL) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if !placeholder {
                Color.clear
            } else {
                Rectangle().fill(.gray.opacity(0.25))
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let cached = imageMemory.object(forKey: url as NSURL) { image = cached; return }
            let img = await ImageCache.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}

// MARK: - Estilos de playlist (iconos y colores elegibles)
enum PlaylistStyle {
    static let palettes: [[Color]] = Tokens.playlistPalettes
    static let icons = [
        "music.note.list", "heart.fill", "star.fill", "flame.fill", "bolt.fill", "moon.stars.fill",
        "sun.max.fill", "car.fill", "figure.run", "dumbbell.fill", "headphones", "guitars.fill",
        "pianokeys", "mic.fill", "party.popper.fill", "cup.and.saucer.fill", "book.fill", "leaf.fill",
        "airplane", "gamecontroller.fill", "sparkles", "cloud.rain.fill", "beach.umbrella.fill", "bed.double.fill"
    ]

    static func gradient(_ index: Int?) -> LinearGradient {
        let colors = palettes[(index ?? 1) % palettes.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Icono en un cuadrado redondeado con degradado, estilo Ajustes/Apple Music.
struct GradientIcon: View {
    let systemName: String
    var palette: Int?
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(PlaylistStyle.gradient(palette))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .overlay(Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1))
            .frame(width: size, height: size)
    }
}

/// Portada de una playlist: foto propia › icono elegido › mosaico de carátulas › icono por defecto.
/// Con `size: nil` ocupa el ancho disponible (cuadrada).
struct PlaylistCover: View {
    let playlist: Playlist
    var size: CGFloat? = 56
    /// Radio de esquina propio; por defecto el 20 % del lado.
    var radius: CGFloat? = nil
    @EnvironmentObject var library: Library   // se redibuja al cambiar la foto

    var body: some View {
        if let size {
            content(size)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius ?? size * 0.2, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius ?? size * 0.2, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { GeometryReader { g in content(g.size.width) } }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        }
    }

    @ViewBuilder private func content(_ side: CGFloat) -> some View {
        if let img = PlaylistArt.image(playlist.id) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: side, height: side)
        } else if let icon = playlist.icon {
            GradientIcon(systemName: icon, palette: playlist.tint, size: side)
        } else if playlist.songs.count >= 4 {
            let thumbs = playlist.songs.prefix(4).map { $0.thumb(Int(side * 2)) }
            VStack(spacing: 0) {
                HStack(spacing: 0) { CoverImage(url: thumbs[0]); CoverImage(url: thumbs[1]) }
                HStack(spacing: 0) { CoverImage(url: thumbs[2]); CoverImage(url: thumbs[3]) }
            }
            .frame(width: side, height: side)
        } else if let first = playlist.songs.first {
            CoverImage(url: first.thumb(Int(side * 3))).frame(width: side, height: side)
        } else {
            GradientIcon(systemName: "music.note.list", palette: playlist.tint, size: side)
        }
    }
}

// MARK: - Portada pequeña para los menús
/// Los menús de iOS sólo aceptan imágenes: la portada de cada playlist en «Añadir a playlist»
/// se dibuja a 30 pt (foto propia › icono › carátula de la primera canción ya en caché › nota).
@MainActor
enum PlaylistMenuIcon {
    private static var cache: [String: UIImage] = [:]

    static func image(for p: Playlist) -> UIImage {
        let side: CGFloat = 30
        let firstThumb = p.songs.first?.thumb(120)
        let key = "\(p.id)|\(p.icon ?? "")|\(p.tint ?? -1)|\(PlaylistArt.exists(p.id))|\(firstThumb?.absoluteString ?? "")"
        if let hit = cache[key] { return hit }
        let base: UIImage?
        if let photo = PlaylistArt.image(p.id) {
            base = photo
        } else if p.icon == nil, let url = firstThumb, let thumb = imageMemory.object(forKey: url as NSURL) {
            base = thumb
        } else {
            let renderer = ImageRenderer(content: GradientIcon(systemName: p.icon ?? "music.note.list", palette: p.tint, size: side))
            renderer.scale = 3
            base = renderer.uiImage
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: 7).addClip()
            base?.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }.withRenderingMode(.alwaysOriginal)
        cache[key] = out
        return out
    }
}
