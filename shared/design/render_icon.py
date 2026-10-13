#!/usr/bin/env python3
"""Dibuja el icono de LibreMusic (mismo diseño que AppIcon.svg) con Pillow y lo exporta
a los tamaños de iOS y Android. Así no hace falta ningún conversor de SVG.

    python3 shared/design/render_icon.py
"""
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
S = 2048          # se dibuja a 2× y se reduce (suavizado)
K = S / 1024      # escala desde las coordenadas del SVG

VIOLET_BG = [(0.0, (0x2A, 0x1B, 0x8F)), (0.5, (0x5B, 0x21, 0xB6)), (1.0, (0x8B, 0x5C, 0xF6))]
HUB = (0x4C, 0x1D, 0x95)
NOTE_TOP, NOTE_BOTTOM = (0xFF, 0xFF, 0xFF), (0xED, 0xE4, 0xFF)
# Manchas de luz: azul, magenta, ámbar y lila (los colores de la marca).
BLOBS = [(210, 230, 300, (0x4D, 0x6B, 0xFF), 0.85), (860, 360, 260, (0xEC, 0x48, 0x99), 0.75),
         (640, 900, 320, (0xF5, 0x9E, 0x0B), 0.80), (150, 860, 220, (0xB4, 0x4C, 0xFF), 0.60)]


def lerp(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def gradient_diag(stops):
    """Degradado de la esquina superior izquierda a la inferior derecha."""
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
                if t0 <= t <= t1:
                    px[x, y] = lerp(c0, c1, (t - t0) / (t1 - t0))
                    break
    return img.resize((S, S), Image.BICUBIC)


def vertical(c0, c1, size):
    w, h = size
    col = Image.new("RGB", (1, h))
    for y in range(h):
        col.putpixel((0, y), lerp(c0, c1, y / max(1, h - 1)))
    return col.resize((w, h))


def circle_mask(cx, cy, r):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse([(cx - r) * K, (cy - r) * K, (cx + r) * K, (cy + r) * K], fill=255)
    return m


def bezier(p0, p1, p2, p3, n=40):
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t ** 2
        d = t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def note_mask():
    """Plica, bandera y bobina (con los 6 dientes) en una máscara."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    dx, dy = -22, -14
    def P(x, y): return ((x + dx) * K, (y + dy) * K)
    d.rounded_rectangle([*P(574, 282), *P(608, 612)], radius=17 * K, fill=255)
    flag = [(591, 282)] + bezier((591, 282), (660, 300), (720, 340), (712, 430))[1:] \
        + bezier((712, 430), (700, 395), (660, 372), (600, 370))[1:]
    d.polygon([P(x, y) for x, y in flag], fill=255)
    cx, cy = 482, 640
    d.ellipse([*P(cx - 128, cy - 128), *P(cx + 128, cy + 128)], fill=255)
    return m


def hub_layer():
    """Buje oscuro con los dientes claros recortados."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    dx, dy = -22, -14
    cx, cy = (482 + dx) * K, (640 + dy) * K
    d.ellipse([cx - 64 * K, cy - 64 * K, cx + 64 * K, cy + 64 * K], fill=255)
    teeth = Image.new("L", (S, S), 0)
    td = ImageDraw.Draw(teeth)
    for i in range(6):
        a = math.radians(i * 60)
        # rectángulo 16×26 a 36–62 px del centro, girado
        pts = []
        for (x, y) in [(-8, -62), (8, -62), (8, -36), (-8, -36)]:
            rx = x * math.cos(a) - y * math.sin(a)
            ry = x * math.sin(a) + y * math.cos(a)
            pts.append((cx + rx * K, cy + ry * K))
        td.polygon(pts, fill=255)
    return ImageChops.subtract(m, teeth)


def shadow(mask, opacity=0.35):
    sh = mask.filter(ImageFilter.GaussianBlur(22 * K))
    sh = ImageChops.offset(sh, 0, int(18 * K))
    return sh.point(lambda v: int(v * opacity))


def render(dark: bool) -> Image.Image:
    base = Image.new("RGB", (S, S), (0x0C, 0x0A, 0x1F)) if dark else gradient_diag(VIOLET_BG)
    blobs = Image.new("RGB", (S, S), (0, 0, 0))
    alpha = Image.new("L", (S, S), 0)
    for cx, cy, r, color, op in BLOBS:
        op = op * (0.52 if dark else 1)
        layer = Image.new("RGB", (S, S), color)
        m = circle_mask(cx, cy, r).point(lambda v, o=op: int(v * o))
        blobs.paste(layer, (0, 0), m)
        alpha = ImageChops.lighter(alpha, m)
    blobs_rgba = blobs.convert("RGBA")
    blobs_rgba.putalpha(alpha)
    blobs_rgba = blobs_rgba.filter(ImageFilter.GaussianBlur(90 * K))
    img = base.convert("RGBA")
    img.alpha_composite(blobs_rgba)

    # Disco de cristal
    disc = circle_mask(512, 512, 330)
    black = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    black.putalpha(shadow(disc))
    img.alpha_composite(black)
    glass = vertical((255, 255, 255), (255, 255, 255), (S, S)).convert("RGBA")
    ga = Image.new("L", (S, S))
    gpx = [int(255 * (0.34 + (0.10 - 0.34) * (y / (S - 1)))) for y in range(S)]
    ga = Image.new("L", (1, S))
    ga.putdata(gpx)
    ga = ga.resize((S, S))
    glass.putalpha(ImageChops.multiply(ga, disc))
    img.alpha_composite(glass)
    # brillo interior
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).ellipse([(420 - 300) * K, (300 - 150) * K, (420 + 300) * K, (300 + 150) * K], fill=int(255 * 0.22 * 0.55))
    hl = ImageChops.multiply(hl.filter(ImageFilter.GaussianBlur(18 * K)), disc)
    white = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    white.putalpha(hl)
    img.alpha_composite(white)
    # aro
    ring = Image.new("L", (S, S), 0)
    rd = ImageDraw.Draw(ring)
    r = 328
    rd.ellipse([(512 - r) * K, (512 - r) * K, (512 + r) * K, (512 + r) * K], outline=255, width=int(5 * K))
    rim_alpha = Image.new("L", (S, S))
    rim_small = Image.new("L", (64, 64))
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            a = 0.95 + (0.15 - 0.95) * (t / 0.45) if t < 0.45 else 0.15 + (0.55 - 0.15) * ((t - 0.45) / 0.55)
            rim_small.putpixel((x, y), int(255 * a))
    rim_alpha = rim_small.resize((S, S), Image.BICUBIC)
    rim = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    rim.putalpha(ImageChops.multiply(ring, rim_alpha))
    img.alpha_composite(rim)

    # Nota
    nm = note_mask()
    black = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    black.putalpha(shadow(nm))
    img.alpha_composite(black)
    note = vertical(NOTE_TOP, NOTE_BOTTOM, (S, S)).convert("RGBA")
    note.putalpha(nm)
    img.alpha_composite(note)
    # surco de la bobina y buje
    groove = Image.new("L", (S, S), 0)
    cx, cy = (482 - 22) * K, (640 - 14) * K
    ImageDraw.Draw(groove).ellipse([cx - 120 * K, cy - 120 * K, cx + 120 * K, cy + 120 * K], outline=int(255 * 0.18), width=int(6 * K))
    g = Image.new("RGBA", (S, S), HUB + (0,))
    g.putalpha(groove)
    img.alpha_composite(g)
    hub = Image.new("RGBA", (S, S), HUB + (0,))
    hub.putalpha(hub_layer())
    img.alpha_composite(hub)
    return img.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def main():
    light, dark = render(False), render(True)
    ios = ROOT / "apps/ios/Sources/Assets.xcassets"
    # Desde 0.8.1 este icono (nota y bobina, violeta) es el alternativo «Violeta»; el de por defecto es el
    # original de encendido (AppIcon-Encendido.svg/.png), que se copia tal cual.
    light.save(ios / "AppIcon-Violeta.appiconset/AppIcon.png")
    dark.save(ios / "AppIcon-Violeta.appiconset/AppIcon-Dark.png")
    power = Image.open(ROOT / "shared/design/AppIcon-Encendido.png").convert("RGB")
    power.save(ios / "AppIcon.appiconset/AppIcon.png")
    power.save(ios / "AppIcon.appiconset/AppIcon-Dark.png")
    power.resize((384, 384), Image.LANCZOS).save(ios / "Logo.imageset/Logo.png")
    light.resize((384, 384), Image.LANCZOS).save(ios / "IconPreviewViolet.imageset/IconPreviewViolet.png")
    light.save(ROOT / "shared/design/AppIcon.png")
    dark.save(ROOT / "shared/design/AppIcon-Dark.png")

    # Android: el icono violeta como alternativo (mipmap ic_launcher_violet*) y logo para Acerca de. El de
    # por defecto es un vector (drawable/ic_launcher_power.xml).
    res = ROOT / "apps/android/app/src/main/res"
    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    mask = Image.new("L", (1024, 1024), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 1023, 1023], radius=230, fill=255)
    rounded = light.convert("RGBA")
    rounded.putalpha(mask)
    round_mask = Image.new("L", (1024, 1024), 0)
    ImageDraw.Draw(round_mask).ellipse([0, 0, 1023, 1023], fill=255)
    circ = light.convert("RGBA")
    circ.putalpha(round_mask)
    for name, px in sizes.items():
        d = res / f"mipmap-{name}"
        d.mkdir(parents=True, exist_ok=True)
        rounded.resize((px, px), Image.LANCZOS).save(d / "ic_launcher_violet.png")
        circ.resize((px, px), Image.LANCZOS).save(d / "ic_launcher_violet_round.png")
        # Icono adaptativo: el sistema recorta el centro (72 de 108 dp), así que se amplía 1,5×.
        fg = int(px * 108 / 48)
        full = light.resize((fg, fg), Image.LANCZOS)
        full.save(d / "ic_launcher_full.png")
    drawable = res / "drawable-nodpi"
    drawable.mkdir(parents=True, exist_ok=True)
    power.resize((512, 512), Image.LANCZOS).save(drawable / "logo.png")
    print("Iconos generados")


if __name__ == "__main__":
    main()
