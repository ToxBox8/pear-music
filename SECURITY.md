# Seguridad

Si encuentras un fallo de seguridad en Pear Music (las apps, la web o sus servidores), **no abras un issue
público**. Avísalo en privado desde GitHub: pestaña **Security › Report a vulnerability** de este repositorio.

Cuéntanos qué has visto, cómo reproducirlo y qué versión usas (Ajustes › Ayuda y soporte › Acerca de). Contestamos
en unos días y te decimos cuándo sale el arreglo. Si quieres, te damos las gracias por tu nombre en las novedades.

## Qué entra

- Las apps de Android e iPhone, la web y los Workers (`services/`).
- Especialmente: la firma de las publicaciones (`version.json`, `altstore.json`), el estado firmado (interruptor de
  emergencia), la cuenta y la copia cifrada de la biblioteca, el Jam en la red local y el soporte.

## Qué no entra

- Ataques que necesiten un móvil ya comprometido (root, jailbreak) o acceso físico desbloqueado.
- Denegación de servicio por volumen y spam.
- Lo que dependa de YouTube o de Google.

Qué datos se guardan y dónde: `docs/SEGURIDAD.md` y `docs/TELEMETRIA.md`.
