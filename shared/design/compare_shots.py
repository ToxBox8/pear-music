#!/usr/bin/env python3
"""Hoja de comparación de capturas iOS | Android.

Empareja las PNG por nombre (01_biblioteca_cristal … 15_importar) y genera:
  - <out>/hoja.png: todas las parejas, iOS a la izquierda y Android a la derecha;
  - <out>/<nombre>.png: cada pareja a tamaño completo, con una tercera columna que marca
    en magenta los píxeles que cambian (ayuda a ver desplazamientos de pocos puntos).

Por defecto lee las ramas que publica la CI («screenshots-ios» y «screenshots»):
  python3 shared/design/compare_shots.py --out /tmp/paridad
También acepta carpetas: --ios DIR --android DIR.
Necesita Pillow (pip install pillow).
"""
import argparse
import io
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

CELL_W = 393          # ancho de cada captura en la hoja (1 pt = 1 px)
PAIRS_PER_ROW = 3
GAP = 16
LABEL_H = 34
BG = (24, 24, 28)
INK = (235, 235, 240)
MUTED = (150, 150, 160)


def from_branch(branch: str) -> dict[str, Image.Image]:
    ref = f"origin/{branch}"
    subprocess.run(["git", "fetch", "-q", "origin", branch], check=False)
    names = subprocess.run(["git", "ls-tree", "--name-only", ref], capture_output=True, text=True, check=True).stdout.split()
    shots = {}
    for n in names:
        if n.endswith(".png"):
            data = subprocess.run(["git", "show", f"{ref}:{n}"], capture_output=True, check=True).stdout
            shots[n[:-4]] = Image.open(io.BytesIO(data)).convert("RGB")
    return shots


def from_dir(d: str) -> dict[str, Image.Image]:
    return {p.stem: Image.open(p).convert("RGB") for p in sorted(Path(d).glob("*.png"))}


def font(size: int):
    for name in ("DejaVuSans-Bold.ttf", "Arial Bold.ttf", "Helvetica.ttc"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def fit(img: Image.Image, w: int) -> Image.Image:
    return img.resize((w, round(img.height * w / img.width)), Image.LANCZOS)


def diff_mask(a: Image.Image, b: Image.Image) -> tuple[Image.Image, float]:
    """Android en gris con los píxeles distintos en magenta, y el % de píxeles distintos."""
    b = b.resize(a.size, Image.LANCZOS)
    d = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 40 else 0)
    base = b.convert("L").convert("RGB").point(lambda v: v // 2 + 64)
    out = Image.composite(Image.new("RGB", a.size, (255, 0, 200)), base, d)
    hist = d.histogram()
    return out, 100 * hist[255] / (a.width * a.height)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ios", help="carpeta con las PNG de iOS (por defecto, la rama screenshots-ios)")
    ap.add_argument("--android", help="carpeta con las PNG de Android (por defecto, la rama screenshots)")
    ap.add_argument("--out", default="paridad", help="carpeta de salida")
    args = ap.parse_args()

    ios = from_dir(args.ios) if args.ios else from_branch("screenshots-ios")
    android = from_dir(args.android) if args.android else from_branch("screenshots")
    names = sorted(set(ios) | set(android))
    if not names:
        print("No hay capturas", file=sys.stderr)
        return 1
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    title_f, label_f, small_f = font(22), font(15), font(12)
    cell_h = max(fit(i, CELL_W).height for i in list(ios.values()) + list(android.values()))
    pair_w = CELL_W * 2 + 4
    rows = (len(names) + PAIRS_PER_ROW - 1) // PAIRS_PER_ROW
    sheet_w = GAP + PAIRS_PER_ROW * (pair_w + GAP)
    sheet_h = 60 + rows * (LABEL_H + cell_h + GAP)
    sheet = Image.new("RGB", (sheet_w, sheet_h), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((GAP, 18), "Pear Music · iOS (izquierda) | Android (derecha)", font=title_f, fill=INK)

    for k, name in enumerate(names):
        a, b = ios.get(name), android.get(name)
        x = GAP + (k % PAIRS_PER_ROW) * (pair_w + GAP)
        y = 60 + (k // PAIRS_PER_ROW) * (LABEL_H + cell_h + GAP)
        pct = None
        if a and b:
            mask, pct = diff_mask(a, b)
            full = Image.new("RGB", (a.width * 3 + 40, a.height), BG)
            full.paste(a, (0, 0))
            full.paste(b.resize(a.size, Image.LANCZOS), (a.width + 20, 0))
            full.paste(mask, (a.width * 2 + 40, 0))
            full.save(out / f"{name}.png")
        info = f"{name}" + (f"  ·  {pct:.1f}% distinto" if pct is not None else "")
        draw.text((x, y + 8), info, font=label_f, fill=INK)
        for j, img in enumerate((a, b)):
            cx = x + j * (CELL_W + 4)
            if img:
                sheet.paste(fit(img, CELL_W), (cx, y + LABEL_H))
            else:
                draw.rectangle((cx, y + LABEL_H, cx + CELL_W, y + LABEL_H + cell_h), outline=MUTED)
                draw.text((cx + 12, y + LABEL_H + 12), "sin captura", font=small_f, fill=MUTED)
        print(info)

    sheet.save(out / "hoja.png", optimize=True)
    print(f"Hoja: {out / 'hoja.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
