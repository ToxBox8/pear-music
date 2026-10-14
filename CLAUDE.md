# CLAUDE.md

Claude Code carga este archivo solo al abrir el repositorio. Con estos dos documentos ya tienes las reglas y cómo funciona la app:

@AGENTS.md
@CONTEXT.md

`DECISIONS.md` **no se carga entero** (es el historial y no para de crecer). Para el porqué de algo, busca sólo lo que necesites: `grep -n -i "<tema>" DECISIONS.md` y lee esa entrada. Para el código, usa el grafo (abajo) en vez de abrir archivos a ciegas.

Las reglas completas están en la sección «Documentos vivos» de `AGENTS.md`. Resumen: cualquier cambio en el proyecto deja `AGENTS.md`, `CONTEXT.md` y `DECISIONS.md` actualizados en el mismo commit (para escribir en `DECISIONS.md` basta con leer su cabecera y añadir la entrada arriba).

## graphify (mapa del código)

El grafo de conocimiento está en `graphify-out/` (no va en git): clases, funciones, pantallas y documentos con sus relaciones, agrupados por temas («iOS Jam Network v2», «Android Player ViewModel»…).

- **Al empezar:** si no existe `graphify-out/graph.json` (otro worktree o clon nuevo), créalo con `graphify update .` (sólo código, sin coste). Si `git rev-parse --short HEAD` no coincide con el commit de «Graph Freshness» de `graphify-out/GRAPH_REPORT.md`, haz también `graphify update .`.
- **Antes del primer grep o lectura de código**, pregunta al grafo: `graphify query "<pregunta>"` (sube `--budget` si sale truncado), `graphify explain "<símbolo>"` para una pieza concreta y `graphify path "<A>" "<B>"` para ver cómo se conectan dos. Lee los archivos sólo en las líneas que el grafo te señale. Pon esta regla en el prompt de cada subagente que explore código.
- Visión general de la arquitectura: `graphify god-nodes` o las secciones «Community Hubs» y «God Nodes» de `graphify-out/GRAPH_REPORT.md`.
- El grafo sabe **qué hay y cómo se conecta**, no **por qué** se decidió: el porqué está en `DECISIONS.md`.
- Tras cambiar código, `graphify update .` (los hooks de git también lo hacen tras cada commit). Si cambias mucha documentación, `graphify extract . --backend claude-cli` vuelve a leer sólo los `.md` cambiados (gasta de la suscripción).
- También existe el servidor MCP `graphify` (grafo global, etiquetas `pear-music` y `pear-music-web`) por si la CLI no está a mano.
