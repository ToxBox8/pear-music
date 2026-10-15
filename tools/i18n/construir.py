#!/usr/bin/env python3
"""Monta los catálogos de idiomas (Cierre 1.0) y los copia a las dos apps.

  python3 tools/i18n/construir.py

Lee shared/i18n/src/orden.txt (las claves en español, una por línea) y shared/i18n/src/<idioma>.txt
(«número⇥traducción»), comprueba que cada traducción tiene los mismos {0}, {1}… que el original y escribe
shared/i18n/<idioma>.json, apps/android/app/src/main/assets/i18n/<idioma>.json y apps/ios/Sources/I18n/<idioma>.json.
Lo que falte en un idioma se ve en español.
"""
import json, os, re, glob, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "shared/i18n/src")
unesc = lambda s: s.replace("\\n", "\n").replace("\\\\", "\\")
keys = [unesc(l) for l in open(os.path.join(SRC, "orden.txt"), encoding="utf-8").read().split("\n")[:-1]]
ok = True
for path in sorted(glob.glob(os.path.join(SRC, "*.txt"))):
    lang = os.path.basename(path)[:-4]
    if lang == "orden":
        continue
    out = {}
    for n, line in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        if not line.strip():
            continue
        num, _, text = line.partition("\t")
        i = int(num) - 1
        if not 0 <= i < len(keys):
            print(f"{lang}:{n}: número {num} fuera del catálogo"); ok = False; continue
        key, text = keys[i], unesc(text)
        if sorted(re.findall(r"\{\d+\}", key)) != sorted(re.findall(r"\{\d+\}", text)):
            print(f"{lang}:{num}: los marcadores no coinciden: {key!r} → {text!r}"); ok = False; continue
        # Los espacios del principio y del final son parte del texto (se pegan a otros trozos).
        lead, trail = re.match(r"^\s*", key).group(0), re.search(r"\s*$", key).group(0)
        out[key] = lead + text.strip() + trail if text.strip() else text
    missing = len(keys) - len(out)
    print(f"{lang}: {len(out)} textos{f', faltan {missing}' if missing else ''}")
    for dest in ("shared/i18n", "apps/android/app/src/main/assets/i18n", "apps/ios/Sources/I18n"):
        os.makedirs(os.path.join(ROOT, dest), exist_ok=True)
        json.dump(out, open(os.path.join(ROOT, dest, f"{lang}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0, sort_keys=True)
sys.exit(0 if ok else 1)
