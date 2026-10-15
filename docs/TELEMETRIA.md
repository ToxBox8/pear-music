# Telemetría de Pear Music: qué se envía, para qué y cómo se retira

Desde Android 1.0 / iOS 2.0. Responsable: Toxbox (España). Base legal: **consentimiento** (RGPD art. 6.1.a),
pedido aparte de la cuenta y de los términos, con la casilla **sin marcar**. Sin consentimiento no se mide ni se
envía nada.

## Para qué

Sólo para saber si la app va fluida y rápida en móviles reales y arreglar los que van mal (arranque lento, tirones,
memoria). No se usa para publicidad, perfiles ni nada más, y no se comparte con nadie.

## Qué se envía (lista cerrada)

**Un informe por semana** (desde la Fase 4b). Cada sesión se apunta sólo en el móvil y, cuando empieza una semana
nueva, se envía el resumen de la anterior: la mediana de cada medida y cuántas sesiones hubo. Si no hay red, se
reintenta más tarde (al salir de la app o en la comprobación de fondo). El servidor (`services/api/src/telemetry.js`) rechaza
cualquier informe con un campo que no esté aquí.

**Pear Dev es sólo manual** (lo decidió Toxbox el 15-10-2026): mide siempre en el móvil, pero nunca envía sola; sólo
manda algo con «Enviar ahora». La app pública (y Pear Pref) envía el resumen semanal automáticamente si se activó.

| Campo | Ejemplo | Qué es |
|---|---|---|
| `install` | `9f2c…` (32 hex) | Identificador **aleatorio** de esta instalación. No es el de la cuenta ni del móvil; cambia al retirar el consentimiento. |
| `platform` | `android` | `android` o `ios` |
| `channel` | `usr` | Variante: `usr`, `pref` o `dev` |
| `app_version` | `1.0.0` | Versión de Pear Music |
| `os_version` | `16` | Versión de Android o iOS |
| `device_model` | `Nothing A065` / `iPhone16,1` | Modelo del móvil (fabricante y modelo; nunca el nombre que le has puesto) |
| `week` | `2026-W42` | Semana ISO del resumen |
| `kind` | `semanal` | `semanal` (automático) o `manual` (sólo Pear Dev, «Enviar ahora») |
| `sessions` | `9` | Cuántas veces se abrió la app esa semana |
| `startup_ms` | `640` | Cuánto tarda en abrir (mediana; sólo la primera vez de cada arranque) |
| `fps_median` | `59.8` | Fotogramas por segundo, mediana de la sesión |
| `jank_percent` | `1.9` | % de fotogramas lentos (más de 1,5 veces lo que debería durar uno) |
| `memory_mb` | `210` | Memoria que usa la app |
| `session_minutes` | `12` | Minutos por sesión (mediana) |

Lo recibe el servidor junto con la hora de llegada. **No** se envían: correo, cuenta, canciones, búsquedas,
biblioteca, ubicación, contactos, IP guardada (Cloudflare la ve para entregar la petición, pero no se guarda),
identificadores de publicidad ni del dispositivo.

## Dónde y cuánto tiempo

Base D1 `pear-music` del Worker `pear-music-api` (Cloudflare), tabla `telemetry`, **sin relación** con las cuentas.
Se borra sola a los **90 días** (tarea diaria).

## Cómo se retira

- **Ajustes › Ayuda y soporte › Tus datos › Telemetría**: al apagarla, la app pide al servidor que borre todo lo
  enviado desde esa instalación (`DELETE /v1/telemetria`) y cambia el identificador.
- **Borrar todos mis datos** hace lo mismo antes de borrar el móvil.

## Panel (sólo Toxbox)

Página escondida de la web (`/panel-t`, sin enlaces y `noindex`) que **sólo existe con el móvil de Toxbox
conectado por USB**: sin él es un 404 y el menú no la enseña (lo pidió Toxbox). Funciona así:

1. Pear Dev › Ajustes › Ayuda y soporte › Administración › **Llave del panel por USB** (escucha sólo en
   `127.0.0.1:8765` dentro del móvil, sólo responde a la web y se apaga a los 10 min).
2. En el PC: `adb forward tcp:8765 tcp:8765`.
3. La web pregunta `/hola` y pide una llave de 5 min (`/llave`, firmada con Ed25519; la privada, cifrada en Pear Dev,
   nunca sale del móvil). Con ella lee `GET /v1/telemetria/panel` de la API: resumen por semana, versión y modelo, y
   los 30 últimos informes **sin** identificador.

El menú sólo prueba `127.0.0.1` en el navegador donde ya se abrió el panel (marca en `localStorage`); el resto de
visitantes nunca hace esa petición. Una vez: «Copiar clave pública» en Pear Dev y ponerla en `PANEL_PUBLIC_KEY`
(`services/api/wrangler.toml`). *Diferencia aceptada:* la llave por USB sólo existe en Android (el móvil de Toxbox);
iOS tiene «Enviar ahora».

## Para desarrolladores

- Android: `data/Telemetry.kt`; iOS: `Telemetry.swift`. Los dos miden lo mismo.
- Añadir un campo exige: esta tabla, `FIELDS` en el Worker, el esquema D1, las dos apps y el texto del
  consentimiento, en el mismo cambio. Un campo nuevo que permita identificar a alguien necesita una nueva
  evaluación (y probablemente un consentimiento nuevo).
