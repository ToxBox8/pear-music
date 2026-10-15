// La web se llamaba libremusic-landing.8toxbox8-69a.workers.dev y pasó a pearmusic-by-toxbox (15-10-2026, lo pidió
// Toxbox). Este Worker ocupa el nombre antiguo y lo manda todo a la dirección nueva con la misma ruta y consulta:
// así siguen funcionando las apps 1.0 / 2.0 (version.json, /api/avisos, el APK), las fuentes de AltStore/SideStore
// ya añadidas y los enlaces viejos (Discord, GitHub, RSS). Las apps siguen las redirecciones solas.
export const NEW_ORIGIN = "https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev";

export default {
  fetch(request) {
    const url = new URL(request.url);
    const target = NEW_ORIGIN + url.pathname + url.search;
    // 308 conserva el método (y el cuerpo) en las peticiones que no son GET; 301 para el resto, que cachea bien.
    const status = request.method === "GET" || request.method === "HEAD" ? 301 : 308;
    return new Response(null, {
      status,
      headers: { location: target, "cache-control": "public, max-age=3600", "access-control-allow-origin": "*" },
    });
  },
};
