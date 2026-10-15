# Runbook de incidentes (kill switch y botón de pánico)

Qué hacer cuando algo va mal en Pear Music. Lo usa Toxbox (o quien él autorice) con el móvil o el PC. El sistema
está en [`services/estado/README.md`](../services/estado/README.md); la decisión, en `DECISIONS.md` (Fase 4).

## Lo básico en 30 segundos

- Las apps leen un **estado firmado** al abrirse (Android, además, cada 15 min en segundo plano). Si no pueden
  leerlo, siguen normal: **el kill switch falla en abierto**.
- Para cambiar el estado: **Pear Dev › Ajustes › Ayuda y soporte › Administración › Botón de pánico**, o
  **`/panico`** en el canal de administración de Discord. Siempre con **contraseña + código de 6 cifras** de la app
  de autenticación.
- Cada cambio **tarda en llegar** lo que tarde cada persona en abrir la app (o ≤ 15 min en Android con la app en
  segundo plano), más 1 min de caché. No es instantáneo y no puede serlo sin push (`docs/AVISOS-ALCANCE.md`).
- La música **descargada** sigue sonando en los niveles 0–2. Sólo el nivel 3 bloquea la app entera.

## Niveles

| Nivel | Cuándo | Qué ve la gente | Qué se apaga | Gravedad |
|---|---|---|---|---|
| **0 · Normal** | Todo va bien, o el incidente se ha resuelto | Nada | Nada | — |
| **1 · Aviso** | Algo falla y conviene que se sepa (YouTube no deja reproducir, una función rota) | Banner arriba con el mensaje; caduca solo a las 24 h | Nada | SEV3–SEV4 |
| **2 · Modo seguro** | Una función remota puede hacer daño o filtrar datos (actualización mala, fallo en la cuenta, telemetría o soporte, una dependencia comprometida) | Banner de modo seguro | Aviso de versión nueva e instalación de APK, búsqueda remota, soporte, telemetría y cuenta | SEV2 |
| **3 · Bloqueo total** | La app entera pone en riesgo a la gente (fallo de seguridad grave, requerimiento legal) | Pantalla de mantenimiento; no se puede usar | Todo | SEV1 |

Los mensajes son fijos (están firmados en el lote); un texto concreto sólo se puede publicar desde el PC
(«Mensaje propio», abajo).

## Pasos

### 1. Detectar y decidir (5 min)

1. Confirma que es real: reportes en `#soporte-pear-music`, el registro de Pear Dev (Administración › Registro
   reciente), `adb logcat` con el móvil, o reproducirlo tú.
2. Elige el **nivel más bajo que proteja a la gente**. Ante la duda entre 1 y 2, el 2: se deshace en cuanto quieras
   y la música sigue funcionando.
3. Anota la hora de inicio (la usarás en el postmortem).

### 2. Activar

**Desde Pear Dev:** Administración › Botón de pánico › elige el nivel › contraseña › código › *Publicar este
nivel* › confirma. La respuesta dice «✅ Hecho» y cuántos cambios quedan en el lote.

**Desde Discord:** en el canal de administración, `/panico accion:<nivel>` › en el modal, contraseña y código. La
respuesta sólo la ves tú.

**Nivel 3 (en dos pasos, para que un susto no tumbe la app):**
1. *Pedir bloqueo total* (o `/panico accion:3`). Queda pendiente.
2. Espera **10 minutos** (y como mucho 1 h) y *Confirmar bloqueo pendiente* (o `/panico accion:confirmar`) con un
   **código nuevo**, distinto del de la petición.
3. ¿Era un error? *Cancelar bloqueo pendiente* (o `/panico accion:cancelar`).

Reglas que te puedes encontrar: entre dos cambios tiene que haber **5 minutos**; tras **5 fallos** de contraseña o
código en una hora, todo queda bloqueado hasta la hora siguiente (y te llega una alerta al canal de
administración).

### 3. Comunicar (en los 15 min siguientes)

| Dónde | Qué |
|---|---|
| Discord `#avisos-pear-music` | Qué pasa, a quién afecta, qué hacer (normalmente «nada: tu música descargada sigue funcionando») y cuándo vuelves a informar. Sale también en la campana de la app y en la web `/avisos`. |
| Web `/avisos` | Sale sola desde el mismo canal. |
| `#soporte-pear-music` | Si hay reportes abiertos del mismo problema, una línea con el enlace al aviso. |

Plantilla del aviso:

> **[Investigando | Identificado | Resuelto] · <título corto>**
> Qué pasa: <una frase>. A quién afecta: <Android / iOS / todo el mundo>.
> Qué puedes hacer: <nada, tu música descargada sigue funcionando | no actualices | …>.
> Próxima actualización: <hora>.

Hechos, no suposiciones. Actualiza cada vez que cambie algo o, como mucho, cada 2 horas mientras dure.

### 4. Arreglar

- Si es una versión mala: publica la anterior (o la arreglada) por el camino de siempre (`docs/RELEASING.md`) y
  `version.json` de la web. En modo seguro las apps no ofrecen actualizaciones: vuelve al nivel 0 **después** de
  publicar la buena.
- Si es un Worker (`api`, `soporte`, `estado`): `npx wrangler rollback` en su carpeta.
- Si es una clave filtrada: ver «Rotar la clave» o el README del Worker afectado.

### 5. Recuperar

1. Publica **0 · Normal** (Pear Dev o `/panico accion:0`).
2. Comprueba con `node tools/estado/estado.mjs ver` que el estado publicado es el nivel 0, y abre la app pública en
   un móvil: sin banner ni pantalla de mantenimiento.
3. Aviso de «Resuelto» en `#avisos-pear-music`.

### 6. Postmortem (en las 48 h siguientes)

Sin culpables. En `docs/incidentes/AAAA-MM-DD-<tema>.md`: resumen, impacto (quién y cuánto tiempo), cronología,
causa (5 porqués), qué fue bien y qué no, y tareas con fecha. La auditoría del Worker (*Ver estado y auditoría*)
da la cronología del kill switch.

## Mantenimiento

### Renovar el lote (cada 30 días, o cuando queden pocos cambios)

Los estados prefirmados caducan con el lote (30 días por defecto) y cada cambio de nivel gasta uno de los 20
huecos. *Ver estado y auditoría* enseña los que quedan y la fecha de caducidad.

```bash
node tools/estado/estado.mjs lote            # en el PC; firma 20 cambios × 4 niveles y los sube
node tools/estado/estado.mjs lote --dias 60  # si te vas una temporada
```

Si el lote caduca, el botón de pánico responde «No hay estados prefirmados vigentes». **El estado publicado no se
borra**, pero también caduca: las apps vuelven a normal cuando pasa su `expiresAt` (fallan en abierto). Pon un
recordatorio cada 4 semanas.

### Mensaje propio (sólo desde el PC)

```bash
node tools/estado/estado.mjs publicar --nivel 1 --mensaje "YouTube está fallando; lo estamos mirando." --horas 12
```

Firma con un contador mayor que todos los del lote vigente, así que después el botón de pánico ya no puede
publicar desde ese lote («Se han gastado todos los cambios»). **Tras un `publicar`, haz siempre un `lote` nuevo.**

### Rotar la clave (si se pierde o se filtra la privada)

La clave pública va dentro de las apps: rotarla exige **versión nueva** de las dos.

1. Mueve la clave vieja: `mv ~/.config/pear-music/estado-ed25519.pem{,.vieja}` (y bórrala de tu gestor cuando
   acabes).
2. `node tools/estado/estado.mjs clave` → clave pública nueva.
3. Cámbiala en `Incident.kt` (Android), `Incident.swift` (iOS) y `services/estado/wrangler.toml`; tests, versión
   nueva y publicar.
4. `npx wrangler deploy` en `services/estado` y `node tools/estado/estado.mjs lote`.
5. Mientras haya gente con la versión vieja, un estado firmado con la clave nueva no le llega (lo descarta y sigue
   normal). Si la vieja se **filtró**, quien la tenga podría firmar estados para esas versiones: avisa en
   `#avisos-pear-music` para que actualicen.

Guarda la clave privada (el `.pem`) en tu gestor de contraseñas: sin ella no se pueden firmar lotes.

### Rotar contraseña o TOTP

`node services/estado/scripts/preparar-secretos.mjs` vuelve a crear los tres (contraseña, TOTP y token de
subida). Para sólo uno: `npx wrangler secret put PANIC_PASSWORD` (con el hash de `hashPassword`) o
`TOTP_SECRET`.

## Probarlo (simulacro, una vez por versión mayor)

En el Cierre de cada versión, con el Worker desplegado y en el móvil de pruebas: nivel 1 → banner en la app
pública; nivel 2 → banner de modo seguro y Buscar sin resultados remotos; pedir 3 y cancelar; 0 → todo normal.
Apunta el resultado en `docs/pruebas/`. Sin desplegar, los tests cubren la lógica: `npm test` en
`services/estado` y `IncidentTest` en Android.
