#!/usr/bin/env python3
"""Idiomas (Cierre 1.0): convierte los textos visibles en español de las dos apps en llamadas L("…") y genera el
catálogo común shared/i18n/es.json (clave = texto en español; {0}, {1}… para los datos que van dentro).

  python3 tools/i18n/extraer.py --dry      enseña qué cambiaría
  python3 tools/i18n/extraer.py            reescribe el código y el catálogo

Heurística: un literal es texto visible si tiene letras y un espacio, una tilde o ñ/¿/¡, o es una palabra con
mayúscula inicial en una carpeta de interfaz. Se saltan claves, URLs, constantes, anotaciones, registros, `case` y
literales con comillas dentro de una interpolación (se quedan en español: los informa --dry).
"""
import json, re, sys, glob, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DRY = "--dry" in sys.argv
SPANISH = re.compile(r"[áéíóúñÁÉÍÓÚÑ¿¡«»]")
SKIP_LINE = re.compile(r"#\"|'\"'|'\\\\\"'|^\s*(@|import |package |//|\*|/\*)|const val|Logs\.[a-z]\(|Log\.[a-z]\(|Regex\(|\bcase \"|print\(|NSLog|fatalError|assert|require\(|check\(|error\(\"|precondition|\.header\(|getString\(|putString\(|getBoolean|forKey:|@AppStorage|UserDefaults|SharedPreferences|URL\(string|systemImage: \"|Image\(systemName|\.url\(|contentType|MediaType|\"Content-|bounds|testTag|tourTarget\(|semanticsButton\(\"Mover")


DATA_TEXT = re.compile(r"^PearMusic|^Music Database$|^(Accept|Authorization|Cookie|Origin|Referer|User-Agent)$|Content-|form-data|\b(SELECT|JOIN|WHERE|INSERT|ORDER BY)\b|Mozilla/|MMM|yyyy|HH:mm|Access-Control|^GET /|^Panel ")


def visible(text, ui):
    t = text.strip()
    if DATA_TEXT.search(t):
        return False
    # Fuera de la interfaz, todo en minúsculas son términos de emparejado o filtros, no textos para leer.
    if not ui and t == t.lower() and not SPANISH.search(t.replace("¿", "").replace("¡", "")):
        return False
    if not t or len(t) < 2 or not re.search(r"[A-Za-zÁÉÍÓÚáéíóúñÑ]", t):
        return False
    if re.match(r"^(https?:|mailto:|file:|[a-z0-9_.\-/:]+$|[A-Z_0-9]+$|%[@a-z])", t):
        return False
    if re.search(r"\.(json|jpg|png|zip|m4a|txt|kt|swift)\b", t) and " " not in t:
        return False
    if SPANISH.search(t):
        return True
    if " " in t and re.search(r"[a-záéíóú]{3,}", t):
        return True
    return ui and re.match(r"^[A-ZÁÉÍÓÚ][a-záéíóúñ]+$", t) is not None


def kotlin_literals(src):
    """(inicio, fin, contenido) de cada "…" de una línea (sin raw strings)."""
    i, out = 0, []
    while i < len(src):
        c = src[i]
        if src.startswith('"""', i):
            return out  # raw string: no se toca la línea
        if c == '"':
            j, depth = i + 1, 0
            while j < len(src):
                ch = src[j]
                if ch == "\\":
                    j += 2
                    continue
                if src.startswith("${", j):
                    depth += 1
                    j += 2
                    continue
                if ch == "}" and depth:
                    depth -= 1
                elif ch == '"' and not depth:
                    break
                elif ch == '"' and depth:
                    # comillas dentro de una interpolación: se salta todo el literal
                    k = src.find('"', j + 1)
                    j = k if k > 0 else len(src)
                j += 1
            out.append((i, j + 1, src[i + 1 : j]))
            i = j + 1
        else:
            i += 1
    return out


def swift_literals(src):
    i, out = 0, []
    while i < len(src):
        if src.startswith('"""', i):
            return out
        if src[i] == '"':
            j, depth = i + 1, 0
            while j < len(src):
                ch = src[j]
                if ch == "\\" and src[j + 1 : j + 2] == "(":
                    depth += 1
                    j += 2
                    continue
                if ch == "\\":
                    j += 2
                    continue
                if ch == "(" and depth:
                    depth += 1
                elif ch == ")" and depth:
                    depth -= 1
                elif ch == '"' and not depth:
                    break
                j += 1
            out.append((i, j + 1, src[i + 1 : j]))
            i = j + 1
        else:
            i += 1
    return out


def template(content, lang):
    """Texto con {0}… y la lista de expresiones; None si no se puede (comillas dentro de una interpolación)."""
    args, out, i = [], "", 0
    while i < len(content):
        if lang == "kt" and content.startswith("${", i):
            j, depth = i + 2, 1
            while j < len(content) and depth:
                depth += {"{": 1, "}": -1}.get(content[j], 0)
                j += 1
            expr = content[i + 2 : j - 1]
            if '"' in expr:
                return None
            out += "{%d}" % len(args)
            args.append(expr)
            i = j
        elif lang == "kt" and content[i] == "$" and i + 1 < len(content) and (content[i + 1].isalpha() or content[i + 1] == "_"):
            m = re.match(r"[A-Za-z_][A-Za-z0-9_.]*", content[i + 1 :])
            name = m.group(0).rstrip(".")
            out += "{%d}" % len(args)
            args.append(name)
            i += 1 + len(name)
        elif lang == "swift" and content.startswith("\\(", i):
            j, depth = i + 2, 1
            while j < len(content) and depth:
                depth += {"(": 1, ")": -1}.get(content[j], 0)
                j += 1
            expr = content[i + 2 : j - 1]
            if '"' in expr:
                return None
            out += "{%d}" % len(args)
            args.append(expr)
            i = j
        elif content[i] == "\\":
            out += content[i : i + 2]
            i += 2
        else:
            out += content[i]
            i += 1
    if re.fullmatch(r"(\{\d+\}\s*)+", out.strip()):
        return None
    return out, args


def unescape(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\$", "$").replace("\\\\", "\\")


def process(path, lang, ui, catalog, skipped):
    lines = open(path, encoding="utf-8").read().split("\n")
    changed = 0
    for n, line in enumerate(lines):
        if SKIP_LINE.search(line):
            continue
        lits = kotlin_literals(line) if lang == "kt" else swift_literals(line)
        for start, end, content in reversed(lits):
            before = line[:start].rstrip()
            after = line[end:].lstrip()
            # «"clave" ->» (when de Kotlin) y comparaciones son claves; «-> "texto"» sí es texto.
            if after.startswith(("->", "==", "!=", ":")) and lang == "kt" and not after.startswith("::"):
                continue
            # Nombres de recursos (imágenes, colores…), nunca texto visible.
            if re.search(r"(Image|named:|Color|systemName:|forResource:)\s*\($|(Image|Color)\($|named:\s*$", before):
                continue
            if before.endswith(("L(", "case", "==", "!=")) or re.search(r"(Key|key|Id|id|Prefs\.\w+\(|\.put\(|optString\(|opt\w+\()\s*\(?$", before):
                continue
            raw_text = re.sub(r"\$\{[^}]*\}|\$[A-Za-z_]\w*|\\\([^)]*\)", "", content)
            if not visible(unescape(raw_text) + (" " if ("${" in content or "\\(" in content) else ""), ui):
                continue
            t = template(content, lang)
            if t is None:
                skipped.append(f"{os.path.relpath(path, ROOT)}:{n + 1}: {content[:70]}")
                continue
            text, args = t
            catalog.setdefault(unescape(text), os.path.relpath(path, ROOT))
            call = 'L("%s"%s)' % (text, "".join(", " + a for a in args))
            line = line[:start] + call + line[end:]
            changed += 1
        lines[n] = line
    if changed and not DRY:
        text = "\n".join(lines)
        # Kotlin: L está en el paquete app.libremusic; los demás paquetes lo importan.
        if lang == "kt" and "\nimport app.libremusic.L\n" not in text and not re.search(r"^package app\.libremusic\s*$", text, re.M):
            text = re.sub(r"^(package [\w.]+\s*\n)", r"\1\nimport app.libremusic.L\n", text, count=1, flags=re.M)
        open(path, "w", encoding="utf-8").write(text)
    return changed


def collect(files):
    """Todos los textos que hay dentro de L("…") en el código (la clave del catálogo)."""
    found = {}
    for f in files:
        lang = "kt" if f.endswith(".kt") else "swift"
        for line in open(f, encoding="utf-8"):
            if 'L("' not in line:
                continue
            for start, end, content in (kotlin_literals(line) if lang == "kt" else swift_literals(line)):
                if line[:start].endswith("L("):
                    found.setdefault(unescape(content), os.path.relpath(f, ROOT))
    return found


def main():
    catalog, skipped, total = {}, [], 0
    kt = glob.glob(os.path.join(ROOT, "apps/android/app/src/main/java/app/libremusic/**/*.kt"), recursive=True)
    sw = glob.glob(os.path.join(ROOT, "apps/ios/Sources/*.swift"))
    no = ("Tokens.kt", "Tokens.swift", "I18n.kt", "I18n.swift", "Screenshots.swift", "YTClient.kt", "Client.swift",
          "PanelKey.kt", "SupportFilter.kt", "SupportFilter.swift", "Logs.kt",
          "AppShortcuts.swift")  # App Intents exige literales: L() no compila ahí
    swift_data = ("AppleMusic.swift", "ExternalImport.swift", "Telemetry.swift", "Incident.swift", "Updates.swift",
                  "Account.swift", "Auth.swift", "Ficha.swift", "UserData.swift", "Lyrics.swift", "Releases.swift", "PendingImports.swift", "JamNet.swift",
                  "Jam.swift", "Discography.swift", "Store.swift", "Player.swift", "AutoBackup.swift", "PlayStats.swift")
    for f in kt:
        if os.path.basename(f) in no:
            continue
        total += process(f, "kt", "/ui/" in f, catalog, skipped)
    for f in sw:
        if os.path.basename(f) in no:
            continue
        total += process(f, "swift", os.path.basename(f) not in swift_data, catalog, skipped)
    print(f"{total} literales, {len(catalog)} textos distintos, {len(skipped)} sin convertir")
    if "--skipped" in sys.argv:
        print("\n".join(skipped))
    if not DRY:
        catalog = collect(kt + sw)
        out = os.path.join(ROOT, "shared/i18n/es.json")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        old = json.load(open(out)) if os.path.exists(out) else {}
        merged = {**{k: k for k in catalog}, **{k: v for k, v in old.items() if k in catalog}}
        json.dump(dict(sorted(merged.items())), open(out, "w"), ensure_ascii=False, indent=1)
        # El orden de las traducciones (shared/i18n/src/orden.txt) sólo crece: los textos nuevos van al final, así
        # los números de cada <idioma>.txt no cambian. Los que ya no se usan se quedan (no molestan).
        orden = os.path.join(ROOT, "shared/i18n/src/orden.txt")
        esc = lambda k: k.replace("\\", "\\\\").replace("\n", "\\n")
        have = open(orden, encoding="utf-8").read().split("\n")[:-1] if os.path.exists(orden) else []
        new = [esc(k) for k in sorted(catalog) if esc(k) not in set(have)]
        open(orden, "w", encoding="utf-8").write("\n".join(have + new) + "\n")
        print(f"orden.txt: {len(new)} textos nuevos al final ({len(have) + len(new)} en total)")


if __name__ == "__main__":
    main()
