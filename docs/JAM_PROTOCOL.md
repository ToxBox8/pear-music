# Protocolo del Jam

Especificación compartida por iOS y Android. Cualquier cambio en el formato de los mensajes se hace aquí primero y sube la versión del protocolo.

## Estado actual (v1, solo iOS)

La app iOS 1.x implementa el Jam con **MultipeerConnectivity** (`apps/ios/Sources/Jam.swift`):

- Servicio `lm-jam` (Bonjour `_lm-jam._tcp` / `_lm-jam._udp`), `discoveryInfo = ["code": CÓDIGO]`.
- El invitado se une con `invitePeer(..., withContext: CÓDIGO)`; el anfitrión acepta si el código coincide.
- Máximo 8 personas (límite de MultipeerConnectivity), anfitrión incluido.
- Mensajes JSON (`JSONEncoder` de Swift) del enum `JamMessage`: `hello(name)`, `state(JamState)`, `add(JamEntry)`, `remove(songID)`, `ended`.

**Limitación:** MultipeerConnectivity es un protocolo cerrado de Apple (cifrado y entramado propios). Android **no** puede hablarlo, aunque vea el anuncio Bonjour. Para un Jam iPhone ↔ Android hace falta la v2.

## Código y enlace (comunes a v1 y v2)

- Código de 6 caracteres del alfabeto `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (sin `0 O 1 I` para evitar confusiones).
- Normalización: mayúsculas, se descartan caracteres fuera del alfabeto, máximo 6.
- Enlace: `libremusic://jam/CÓDIGO` (QR y deep link en ambas plataformas).
- Implementaciones de referencia: `JamService.code(from:)` (Swift) y `JamLink.codeFrom()` (Kotlin), con tests equivalentes.

## Propuesta v2 (multiplataforma)

Transporte abierto que ambas plataformas implementan con APIs nativas:

| | iOS | Android |
|---|---|---|
| Anuncio / descubrimiento | `NWListener` / `NWBrowser` (Network.framework) | `NsdManager` |
| Conexión | `NWConnection` (TCP) | `java.net.Socket` / Ktor sockets |

- Servicio DNS-SD: `_lm-jam2._tcp` (distinto del `_lm-jam._tcp` que ya usa MultipeerConnectivity en v1, para que ningún sistema confunda los anuncios del otro), nombre de instancia = nombre del Jam.
- Registro TXT: `v=2`, `code=CÓDIGO`, `host=NOMBRE`.
- Mensajes: JSON UTF-8, uno por línea (*newline-delimited JSON*), con campo `type`:

```json
{"v":2,"type":"hello","name":"Ana","code":"ABC234"}
{"v":2,"type":"state","state":{"name":"Jam de Ana","code":"ABC234","host":"Ana","members":["Ana","Luis"],"entries":[{"song":{"id":"dQw4w9WgXcQ","title":"…","artist":"…","thumbnail":"https://…"},"by":"Luis"}]}}
{"v":2,"type":"add","entry":{"song":{…},"by":"Luis"}}
{"v":2,"type":"remove","songID":"dQw4w9WgXcQ"}
{"v":2,"type":"ended"}
```

- El anfitrión rechaza (`{"type":"error","reason":"bad_code"}` y cierra) si el `code` del `hello` no coincide.
- El anfitrión es la fuente de verdad: recibe `add`/`remove` y reenvía `state` completo a todos.
- Sin límite fijo de 8; Android limita a 16 (`{"type":"error","reason":"full"}` si está lleno).
- Nombres repetidos: el anfitrión los desambigua («Ana (2)»).
- Android usa `NsdManager` con `_lm-jam2._tcp.`; iOS usa `NWListener`/`NWBrowser` (`apps/ios/Sources/JamNet.swift`) con `_lm-jam2._tcp`.
- Sincronización de reproducción (opcional, v2.1): `{"type":"sync","videoId":"…","positionMs":12345,"serverTimeMs":…}`.

## Permisos

- iOS: `NSLocalNetworkUsageDescription` y `NSBonjourServices` (`_lm-jam._tcp`, `_lm-jam._udp` para v1 y `_lm-jam2._tcp` para v2) en `project.yml`.
- Android: `INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`; en Android 13+ `NEARBY_WIFI_DEVICES` con `neverForLocation`.

## Plan

1. Android implementa v2 desde el principio. **Hecho en Android 0.5.0** (`apps/android/.../jam/`, con tests del formato).
2. iOS añade v2 junto a v1: el anfitrión anuncia los dos y el invitado busca en los dos y se queda con el primero que encuentre el código. **Hecho en iOS 1.2.0** (pendiente de prueba en dispositivos). Retirar v1 más adelante.
3. Probar pronto con dispositivos reales iPhone ↔ Android en la misma Wi-Fi, incluidas redes con aislamiento de clientes.

## Entrar más rápido (Android 1.0 / iOS 2.0)

- **Enlace y QR con la dirección del anfitrión:** `libremusic://jam/CÓDIGO?h=IP:PUERTO` (IPv4 privada de la Wi-Fi y
  puerto TCP del Jam). Quien lo escanea abre la conexión directa **a la vez** que la búsqueda en la red y gana la
  primera que conecte; el intento directo se abandona a los 2 s. Sólo se aceptan IPs privadas (10/8, 172.16/12,
  192.168/16) y puertos 1024–65535. Las versiones anteriores leen sólo la ruta e ignoran `?h=`.
- **Código en el nombre del anuncio:** `«Nombre del Jam» · CÓDIGO`. Android sólo puede resolver un anuncio a la vez:
  los invitados ponen delante de la cola el que acaba en su código. El código sigue en el TXT, que es lo que vale.
- **Cola de resolución en Android** en lugar de reintentos con espera: antes, con varios Jams en la red, el bueno
  podía descartarse tras 5 reintentos.
- Tiempo de entrada en el registro: `LMJam join_ms=… via=directo|wifi` (`adb logcat -s LMJam`).
