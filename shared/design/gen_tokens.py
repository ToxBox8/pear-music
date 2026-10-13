#!/usr/bin/env python3
"""Genera Tokens.swift (iOS) y Tokens.kt (Android) desde shared/design/tokens.json.

Uso:
    python3 shared/design/gen_tokens.py          # escribe los dos archivos
    python3 shared/design/gen_tokens.py --check  # falla si no están al día (CI)
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "shared/design/tokens.json"
SWIFT = ROOT / "apps/ios/Sources/Tokens.swift"
KOTLIN = ROOT / "apps/android/app/src/main/java/app/libremusic/ui/theme/Tokens.kt"

HEADER = "Generado por shared/design/gen_tokens.py desde shared/design/tokens.json. No editar a mano."


def rgba(hexstr: str):
    h = hexstr.lstrip("#")
    if len(h) == 6:
        h += "FF"
    if len(h) != 8:
        raise ValueError(f"Color no válido: {hexstr}")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16)


def swift_color(hexstr: str) -> str:
    r, g, b, a = rgba(hexstr)
    rgb = f"0x{r:02X}{g:02X}{b:02X}"
    return f"Color(hex: {rgb})" if a == 255 else f"Color(hex: {rgb}, opacity: {a / 255:.3f})"


def kotlin_color(hexstr: str) -> str:
    r, g, b, a = rgba(hexstr)
    return f"Color(0x{a:02X}{r:02X}{g:02X}{b:02X})"


def camel(s: str) -> str:
    return s[0].upper() + s[1:]


def num(v) -> str:
    return str(int(v)) if float(v).is_integer() else repr(float(v))


def gen_swift(t: dict) -> str:
    L = [f"// {HEADER}", "import SwiftUI", "", "enum Tokens {"]
    L.append("    enum Brand {")
    for k, v in t["brand"].items():
        L.append(f"        static let {k} = {swift_color(v)}")
    L.append("    }")
    L.append(f"    static let artworkFallback: [Color] = [{', '.join(swift_color(c) for c in t['artworkFallback'])}]")
    L.append("")
    L.append("    struct ThemeSpec {")
    L.append("        let name: String")
    L.append("        let blurb: String")
    L.append("        let accent: Color")
    L.append("        let onAccent: Color")
    L.append("        let scheme: ColorScheme?")
    L.append("        let rounded: Bool")
    L.append("        let maxRadius: CGFloat")
    L.append("    }")
    L.append("    static let themes: [String: ThemeSpec] = [")
    for key, s in t["themes"].items():
        scheme = "nil" if s["scheme"] is None else f".{s['scheme']}"
        L.append(
            f'        "{key}": ThemeSpec(name: "{s["name"]}", blurb: "{s["blurb"]}", accent: {swift_color(s["accent"])}, '
            f'onAccent: {swift_color(s["onAccent"])}, scheme: {scheme}, rounded: {str(s["font"] == "rounded").lower()}, '
            f'maxRadius: {num(s["maxRadius"])}),'
        )
    L.append("    ]")
    L.append(f'    static let themeOrder = [{", ".join(chr(34) + k + chr(34) for k in t["themeOrder"])}]')
    L.append(f'    static let defaultTheme = "{t["defaultTheme"]}"')
    L.append("")
    L.append("    enum Radius {")
    for k, v in t["radius"].items():
        L.append(f"        static let {k}: CGFloat = {num(v)}")
    L.append("    }")
    L.append("    enum TypeSize {")
    for k, v in t["type"].items():
        if k.startswith("$"):
            continue
        L.append(f"        static let {k}: CGFloat = {num(v)}")
    L.append("    }")
    L.append("    static let playlistPalettes: [[Color]] = [")
    for pair in t["playlistPalettes"]:
        L.append(f"        [{', '.join(swift_color(c) for c in pair)}],")
    L.append("    ]")
    L.append(f"    static let holoRainbow: [Color] = [{', '.join(swift_color(c) for c in t['holoRainbow'])}]")
    L.append("    enum AirLight {")
    for k, v in t["air"]["light"].items():
        L.append(f"        static let {k} = {swift_color(v)}")
    L.append("    }")
    L.append("    enum AirDark {")
    for k, v in t["air"]["dark"].items():
        L.append(f"        static let {k} = {swift_color(v)}")
    L.append("    }")
    e = t["motion"]["easeOut"]
    L.append("    enum Motion {")
    L.append(f"        static let easeOut: (Double, Double, Double, Double) = ({', '.join(num(x) for x in e)})")
    for k in ("fast", "normal", "slow"):
        L.append(f"        static let {k}: Double = {num(t['motion'][k])}")
    L.append("    }")
    L.append("}")
    return "\n".join(L) + "\n"


def gen_kotlin(t: dict) -> str:
    L = [f"// {HEADER}", "package app.libremusic.ui.theme", "", "import androidx.compose.ui.graphics.Color", "", "object Tokens {"]
    L.append("    object Brand {")
    for k, v in t["brand"].items():
        L.append(f"        val {camel(k)} = {kotlin_color(v)}")
    L.append("    }")
    L.append(f"    val ArtworkFallback = listOf({', '.join(kotlin_color(c) for c in t['artworkFallback'])})")
    L.append("")
    L.append("    data class ThemeSpec(")
    L.append("        val name: String,")
    L.append("        val blurb: String,")
    L.append("        val accent: Color,")
    L.append("        val onAccent: Color,")
    L.append("        /** \"light\", \"dark\" o null (el que elija el usuario). */")
    L.append("        val scheme: String?,")
    L.append("        val rounded: Boolean,")
    L.append("        val maxRadius: Float,")
    L.append("    )")
    L.append("    val Themes: Map<String, ThemeSpec> = mapOf(")
    for key, s in t["themes"].items():
        scheme = "null" if s["scheme"] is None else f'"{s["scheme"]}"'
        L.append(
            f'        "{key}" to ThemeSpec("{s["name"]}", "{s["blurb"]}", {kotlin_color(s["accent"])}, '
            f'{kotlin_color(s["onAccent"])}, {scheme}, {str(s["font"] == "rounded").lower()}, {num(s["maxRadius"])}f),'
        )
    L.append("    )")
    L.append(f'    val ThemeOrder = listOf({", ".join(chr(34) + k + chr(34) for k in t["themeOrder"])})')
    L.append(f'    const val DefaultTheme = "{t["defaultTheme"]}"')
    L.append("")
    L.append("    object Radius {")
    for k, v in t["radius"].items():
        L.append(f"        const val {camel(k)} = {num(v)}f")
    L.append("    }")
    L.append("    object TypeSize {")
    for k, v in t["type"].items():
        if k.startswith("$"):
            continue
        L.append(f"        const val {camel(k)} = {num(v)}f")
    L.append("    }")
    for mode in ("light", "dark"):
        L.append(f"    object Sys{camel(mode)} {{")
        for k, v in t[mode].items():
            L.append(f"        val {camel(k)} = {kotlin_color(v)}")
        L.append("    }")
    L.append("    val PlaylistPalettes: List<List<Color>> = listOf(")
    for pair in t["playlistPalettes"]:
        L.append(f"        listOf({', '.join(kotlin_color(c) for c in pair)}),")
    L.append("    )")
    L.append(f"    val HoloRainbow = listOf({', '.join(kotlin_color(c) for c in t['holoRainbow'])})")
    for mode in ("light", "dark"):
        L.append(f"    object Air{camel(mode)} {{")
        for k, v in t["air"][mode].items():
            L.append(f"        val {camel(k)} = {kotlin_color(v)}")
        L.append("    }")
    e = t["motion"]["easeOut"]
    L.append("    object Motion {")
    L.append(f"        val EaseOut = floatArrayOf({', '.join(num(x) + 'f' for x in e)})")
    for k in ("fast", "normal", "slow"):
        L.append(f"        const val {camel(k)}Ms = {int(t['motion'][k] * 1000)}")
    L.append("    }")
    L.append("}")
    return "\n".join(L) + "\n"


def main() -> int:
    tokens = json.loads(SRC.read_text(encoding="utf-8"))
    outputs = {SWIFT: gen_swift(tokens), KOTLIN: gen_kotlin(tokens)}
    if "--check" in sys.argv:
        stale = [str(p.relative_to(ROOT)) for p, text in outputs.items() if not p.exists() or p.read_text(encoding="utf-8") != text]
        if stale:
            print("Tokens desactualizados (ejecuta python3 shared/design/gen_tokens.py):", *stale, sep="\n  ")
            return 1
        print("Tokens al día.")
        return 0
    for path, text in outputs.items():
        path.write_text(text, encoding="utf-8")
        print("Escrito", path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
