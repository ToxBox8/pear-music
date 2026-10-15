"""Pone en la web (repo libremusic-landing) Pear Music 1.1 (Android) y 2.1 (iOS). Lo llama lanzar-1.1.sh:

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

# changelog.ts (texto aprobado por Toxbox el 15-10-2026)
COMUN = [
    "Novedades al actualizar: la primera vez que abres una versión nueva te cuenta lo nuevo y, si quieres, te lo enseña con un recorrido.",
    "Guía de Ajustes: el birrete junto a la carta te lleva por todos los Ajustes y te explica cada opción y personalización.",
    "Português, y «Español» ahora se llama «Castellano».",
]
WEB = "Web nueva: pearmusic-by-toxbox.8toxbox8-69a.workers.dev (la dirección antigua sigue funcionando)."
ANDROID = COMUN + [
    "Actualizaciones: ves el porcentaje de la descarga, y si tienes que dar permiso para instalar no se vuelve a descargar.",
    "Barra clásica: ya no marca Descubrir cuando estás en Ajustes.",
    WEB,
]
entries = f"""  {{
    platform: "android",
    version: "{va}",
    date: "{e["HOY"]}",
    title: "Novedades, guía de Ajustes y português",
    highlights: {json.dumps(ANDROID, ensure_ascii=False)},
  }},
  {{
    platform: "ios",
    version: "{vi}",
    date: "{e["HOY"]}",
    title: "Novedades, guía de Ajustes y português",
    highlights: {json.dumps(COMUN + [WEB], ensure_ascii=False)},
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
        "localizedDescription": "Pear Music 2.1: novedades al actualizar con un recorrido, guía de Ajustes junto a la carta, "
        "português, y «Español» ahora se llama «Castellano».",
        "downloadURL": e["IPA_URL"],
        "size": int(e["SIZE_IPA"]),
        "minOSVersion": "16.0",
    })
    del versions[3:]  # las 3 últimas: las viejas apuntan a archivos que siguen en GitHub, pero no hacen falta
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
print("web-1.0.py: downloads.ts, changelog.ts y altstore.json al día")
