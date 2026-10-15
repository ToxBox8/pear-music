"""Pone en la web (repo libremusic-landing) Pear Music 1.0 (Android) y 2.0 (iOS). Lo llama lanzar-1.0.sh:

    VA=… VI=… BUILD=… HOY=… SHA_APK=… SIZE_APK=… SHA_IPA=… SIZE_IPA=… IPA_URL=… python3 -I web-1.0.py <web>

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
        sys.exit(f"web-1.0.py: no encuentro {pattern!r}")
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

# changelog.ts
COMUN = [
    "Siete idiomas: español, català, valencià, galego, euskara, English y Esperanto. Elígelo al empezar o en Ajustes.",
    "Avisa de cada versión nueva con sus novedades y se actualiza encima sin perder nada.",
    "Buzón de sugerencias y tickets: la respuesta te llega sólo a ti en la campana.",
    "La discografía completa de cada artista, y álbumes y playlists fijados arriba.",
    "Bienvenida nueva, recorrido por la app y «Tus datos» para exportarlo o borrarlo todo.",
]
entries = f"""  {{
    platform: "android",
    version: "{va}",
    date: "{e["HOY"]}",
    title: "Pear Music 1.0",
    highlights: {json.dumps(COMUN[:3] + ["Cinco widgets nuevos y un Jam más rápido, con QR."] + COMUN[3:], ensure_ascii=False)},
  }},
  {{
    platform: "ios",
    version: "{vi}",
    date: "{e["HOY"]}",
    title: "Pear Music 2.0",
    highlights: {json.dumps(COMUN[:3] + ["Un Jam más rápido: con el QR se entra al momento."] + COMUN[3:], ensure_ascii=False)},
  }},
"""
p = web / "src/config/changelog.ts"
s = p.read_text()
if not re.search(rf'platform: "android",\s*version: "{re.escape(va)}"', s):
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
        "localizedDescription": "Pear Music 2.0: siete idiomas, buzón de sugerencias con tickets, discografía completa de "
        "cada artista, fijar álbumes y playlists, Jam más rápido con QR y aviso de cada versión nueva.",
        "downloadURL": e["IPA_URL"],
        "size": int(e["SIZE_IPA"]),
        "minOSVersion": "16.0",
    })
    del versions[3:]  # las 3 últimas: las viejas apuntan a archivos que siguen en GitHub, pero no hacen falta
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
print("web-1.0.py: downloads.ts, changelog.ts y altstore.json al día")
