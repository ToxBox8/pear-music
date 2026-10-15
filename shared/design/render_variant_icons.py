#!/usr/bin/env python3
"""Iconos de Pear Dev y Pear Pref (las variantes de Toxbox; nunca se publican). Lo pidió Toxbox el 15-10-2026:
símbolo invertido y una cinta con el nombre.

- Pear Dev: fondo lila, símbolo noche y cinta noche con «DEV» en lila.
- Pear Pref: fondo blanco, símbolo noche y cinta noche con «PREF» en blanco.

El símbolo es el trazo de AppIcon-Encendido.svg (librsvg vía ImageMagick); la cinta y el texto, con Pillow y la
Inter de la app. Genera el primer plano del icono adaptable de Android (fondo en colors.xml del flavor) y el
icono de 1024 de iOS:

    python3 shared/design/render_variant_icons.py
"""
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "apps/android/app/src/main/res/font/inter_display_heavy.ttf"
NIGHT, LILAC, WHITE = "#07070A", "#A78BFA", "#FFFFFF"
PATH = "M12,13a11,11 0,1 0,15 0M16,16a6,6 0,1 0,8 0M20,9v12"

VARIANTS = {
    "dev": {"bg": LILAC, "symbol": NIGHT, "band": NIGHT, "text": LILAC, "label": "DEV", "ios": "AppIcon-Dev"},
    "pref": {"bg": WHITE, "symbol": NIGHT, "band": NIGHT, "text": WHITE, "label": "PREF", "ios": "AppIcon-Pref"},
}


def svg(size, transform, color, bg=None, px=None):
    rect = f'<rect width="{size}" height="{size}" fill="{bg}"/>' if bg else ""
    px = px or size  # se dibuja ya al tamaño final: nada de ampliar (saldría borroso)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{px}" height="{px}" viewBox="0 0 {size} {size}">{rect}'
            f'<g transform="{transform}"><path d="{PATH}" fill="none" stroke="{color}" stroke-width="2.5" '
            f'stroke-linecap="round"/></g></svg>')


def render(svg_text, px):
    with tempfile.TemporaryDirectory() as d:
        src, out = Path(d) / "i.svg", Path(d) / "i.png"
        src.write_text(svg_text)
        subprocess.run(["magick", "-background", "none", f"RSVG:{src}", "-resize", f"{px}x{px}", f"PNG32:{out}"], check=True)
        return Image.open(out).convert("RGBA")


def band(img, v, top, height, inset=0):
    """Cinta horizontal de lado a lado (la máscara del icono recorta los extremos) con el nombre centrado."""
    w = img.width
    draw = ImageDraw.Draw(img)
    draw.rectangle([inset, top, w - inset, top + height], fill=v["band"])
    font = ImageFont.truetype(str(FONT), int(height * 0.62))
    label = " ".join(v["label"])  # un poco de aire entre letras: se lee mejor en pequeño
    box = draw.textbbox((0, 0), label, font=font)
    x = (w - (box[2] - box[0])) / 2 - box[0]
    y = top + (height - (box[3] - box[1])) / 2 - box[1]
    draw.text((x, y), label, font=font, fill=v["text"])
    return img


def android(name, v):
    # Primer plano del icono adaptable: lienzo de 108 dp a 4× (xxxhdpi). Zona visible segura: círculo de 66 dp.
    # Símbolo algo más arriba que en la pública para dejar sitio a la cinta.
    fg = render(svg(108, "translate(31 22) scale(1.15)", v["symbol"], px=432), 432)
    fg = band(fg, v, top=int(432 * 0.60), height=int(432 * 0.13))
    res = ROOT / f"apps/android/app/src/{name}/res"
    (res / "drawable-nodpi").mkdir(parents=True, exist_ok=True)
    fg.save(res / "drawable-nodpi/ic_launcher_variant.png", optimize=True)
    (res / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f'<!-- Icono de Pear {name.capitalize()} (sólo el móvil de Toxbox): generado por shared/design/render_variant_icons.py. -->\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/icon_variant_bg" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_variant" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_power" />\n'
        '</adaptive-icon>\n')
    (res / "values").mkdir(parents=True, exist_ok=True)
    (res / "values/icon_colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="icon_variant_bg">#FF{v["bg"][1:]}</color>\n</resources>\n')


def ios(v):
    # Mismo encuadre que AppIcon-Encendido.svg, subido un poco por la cinta.
    icon = render(svg(1024, "translate(272 200) scale(12.3)", v["symbol"], v["bg"]), 1024)
    icon = band(icon, v, top=int(1024 * 0.70), height=int(1024 * 0.15))
    d = ROOT / f"apps/ios/Sources/Assets.xcassets/{v['ios']}.appiconset"
    d.mkdir(parents=True, exist_ok=True)
    icon.convert("RGB").save(d / f"{v['ios']}.png", optimize=True)
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{v['ios']}.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


if __name__ == "__main__":
    for name, v in VARIANTS.items():
        android(name, v)
        ios(v)
        print(f"Pear {name.capitalize()}: Android e iOS")
