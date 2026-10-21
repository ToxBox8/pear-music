"""Pone en la web (repo libremusic-landing) Pear Music 1.2 (Android) y 2.2 (iOS). Lo llama lanzar-x.1.1.sh:

    VA=… VI=… BUILD=… HOY=… SHA_APK=… SIZE_APK=… SHA_IPA=… SIZE_IPA=… IPA_URL=… python3 -I web-x.1.1.py <web>

Toca downloads.ts (versión, tamaño, SHA-256 y enlace del .ipa), changelog.ts (las dos versiones arriba) y
altstore.json (la versión nueva la primera). Después hay que ejecutar `bun scripts/gen-feeds.ts`.
"""
import json
import os
import re
import sys
from pathlib import Path

web = Path(sys.argv[1])
e = os.environ
va, vi = e["VA"], e["VI"]


def mb(n: str) -> str:
    return f"{int(n) / 1_048_576:.1f} MB".replace(".", ",")


def sub(text: str, pattern: str, repl: str, count: int = 1) -> str:
    new, n = re.subn(pattern, repl, text, count=count, flags=re.S)
    if n != count:
        sys.exit(f"web-x.1.1.py: no encuentro {pattern!r}")
    return new


# downloads.ts
p = web / "src/config/downloads.ts"
s = p.read_text()
android, rest = s.split("export const iosDownload", 1)
android = sub(android, r'version: "v[^"]*"', f'version: "v{va}"')
android = sub(android, r'size: "[^"]*"', f'size: "{mb(e["SIZE_APK"])}"')
android = sub(android, r'checksum: "[0-9a-f]{64}"', f'checksum: "{e["SHA_APK"]}"')
rest = sub(rest, r'version: "v[^"]*"', f'version: "v{vi}"')
rest = sub(rest, r'size: "[^"]*"', f'size: "{mb(e["SIZE_IPA"])}"')
rest = sub(rest, r'checksum: "[0-9a-f]{64}"', f'checksum: "{e["SHA_IPA"]}"')
rest = sub(rest, r'url: "https://github\.com/[^"]*\.ipa"', f'url: "{e["IPA_URL"]}"')
p.write_text(android + "export const iosDownload" + rest)

# changelog.ts (x.1.1). Sin hablar de telemetría.
TITLE = "Fijados, cola de verdad y Jam en cada móvil"
COMUN = [
    "Jam: cada uno en su móvil. Quien crea el Jam elige si suena en un altavoz o en el móvil de cada uno a la vez, con sus cascos.",
    "Comparte playlists con un QR: se escanea con la cámara de otro móvil y se añade con sus canciones, su icono y su color.",
    "Biblioteca: tus Fijados arriba, con portadas grandes y en el orden que quieras arrastrándolos. Las playlists, en su carpeta de Tu música.",
    "La cola, como una cola de verdad: lo que añades suena justo después de la canción actual y, si añades más, detrás de lo que ya habías puesto. Sugerencia del ticket 7.",
    "Ajustes, siempre arriba a la izquierda en Inicio, y todo lo de la barra en Ajustes › Aspecto › Barra.",
    "Descubrir: «No me interesa» para que una canción no vuelva a salir.",
]
ANDROID = COMUN + ["Barras más fluidas, sobre todo mientras suena música."]


def entry(platform: str, version: str, highlights: list[str]) -> str:
    return f"""  {{
    platform: "{platform}",
    version: "{version}",
    date: "{e["HOY"]}",
    title: "{TITLE}",
    highlights: {json.dumps(highlights, ensure_ascii=False)},
  }},
"""


p = web / "src/config/changelog.ts"
s = p.read_text()
if not re.search(rf'platform: "android",\s*version: "{re.escape(va)}"', s):
    entries = entry("android", va, ANDROID) + entry("ios", vi, COMUN)
    s = sub(s, r"(export const releases: Release\[\] = \[\n)", r"\g<1>" + entries.replace("\\", "\\\\"))
p.write_text(s)

# altstore.json
p = web / "public/altstore.json"
d = json.loads(p.read_text())
versions = d["apps"][0]["versions"]
if not any(v["version"] == vi for v in versions):
    versions.insert(0, {
        "version": vi,
        "buildVersion": e["BUILD"],
        "date": e["HOY"],
        "localizedDescription": "Pear Music 2.2: Jam en el móvil de cada uno, playlists por QR, Fijados que se ordenan "
        "arrastrando en Biblioteca y una cola de verdad.",
        "downloadURL": e["IPA_URL"],
        "size": int(e["SIZE_IPA"]),
        "minOSVersion": "16.0",
    })
    del versions[3:]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
print("web-x.1.1.py: downloads.ts, changelog.ts y altstore.json al día")
