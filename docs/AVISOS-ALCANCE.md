# Alcance de los avisos: Discord frente a FCM + APNs (Fase 4.2)

Consultado el 14-10-2026 en la documentación oficial. Lo que no se pudo leer en una fuente oficial va marcado
**sin verificar**.

## Datos

| Criterio | Discord | FCM (Android) | APNs (iOS) |
|---|---|---|---|
| Quién recibe | Sólo quien está en el servidor de Discord y tiene sus notificaciones activas | Cualquier instalación suscrita al *topic* | Cada dispositivo por su *token*; no hay *topics* generales |
| Suscriptores | Límite de miembros del servidor: **sin verificar** (la página oficial de ayuda devuelve 403; fuentes no oficiales hablan de 250 000–500 000) | «Topic messaging supports unlimited subscriptions for each topic» ([Firebase](https://firebase.google.com/docs/cloud-messaging/android/topic-messaging)); hasta 2 000 *topics* por instalación | El *broadcast* por canales existe desde iOS 18, pero **sólo para Live Activities** ([Apple](https://developer.apple.com/tutorials/data/documentation/usernotifications/setting-up-broadcast-push-notifications.md), [WWDC24](https://developer.apple.com/videos/play/wwdc2024/10069/)) |
| Límites de envío | Mensajes de hasta 2 000 caracteres ([Discord](https://docs.discord.com/developers/resources/webhook)); los límites de ritmo de los webhooks no están en esa página (cabeceras de *rate limit*) | 1 000 *fanouts* simultáneos por proyecto, no ampliable; ~10 000 QPS de reparto habitual, sin garantía ([Firebase](https://firebase.google.com/docs/cloud-messaging/android/topic-messaging)) | Sin cifra publicada; responde 429 si se excede (**sin verificar el texto**: la página de Apple no se pudo leer) |
| Fiabilidad | Depende de que la persona tenga Discord, esté en el servidor y no haya silenciado el canal | Entrega del sistema, **si** el móvil tiene Google Play Services | Entrega del sistema, **si** la app tiene el permiso de push |
| Requisitos para Pear Music | Nada en la app | SDK de Firebase en la app (tercero nuevo y encargado de tratamiento, RGPD) y Google Play Services | Capacidad *Push Notifications* en la firma. Con un Apple ID gratuito (AltStore/SideStore) probablemente **no** está disponible: **sin verificar** (la tabla oficial de capacidades no se pudo leer como texto: [Apple](https://developer.apple.com/help/account/reference/supported-capabilities-ios)) |

## Máximo teórico de dispositivos alcanzables

- **Discord:** como mucho los miembros del servidor (cifra exacta sin verificar), y en la práctica sólo los que tienen
  activadas sus notificaciones. Hoy el servidor de Pear Music es pequeño: el alcance real es una fracción de los
  usuarios.
- **FCM:** todas las instalaciones Android con Google Play Services suscritas al *topic* (sin límite por *topic*).
- **APNs:** todos los iPhone con token… pero Pear Music se instala con AltStore/SideStore, que firman con el Apple ID
  de cada persona: si el push no está disponible con esa firma (pendiente de verificar), el alcance real por APNs es 0.
- **Lo que ya existe (sin push):** cada apertura de la app lee los avisos (`/api/avisos`) y el estado firmado
  (`/estado`); Android además cada 15 min en segundo plano. Llega a **todas** las instalaciones que se abran, sin
  terceros nuevos.

## Recomendación

La hipótesis («FCM/APNs como canal principal, incluido el kill switch; Discord para administración y comunidad») se
**confirma a medias**:

1. **Kill switch: no por push.** Tiene que funcionar en todas las instalaciones, sin terceros y fallando en abierto.
   El estado firmado que la app lee al abrirse ya lo cumple. Un push sólo serviría para que se lea antes, y en iOS
   seguramente no está disponible.
2. **Avisos a todos: lo que ya hay, y FCM opcional en Android.** Si algún día hace falta inmediatez (una caída
   grave), se puede añadir FCM *sólo* en Android, con consentimiento y documentado en la política de privacidad. En
   iOS, mientras se distribuya por AltStore/SideStore, el canal es la apertura de la app y el `BGAppRefreshTask`.
3. **Discord: administración y comunidad** (alertas del botón de pánico, `#avisos-pear-music`, `#novedades`). Se
   confirma.

Pendiente de comprobar en un navegador: el límite de miembros de Discord y la columna «Apple Developer» de la
fila *Push notifications* de la tabla de Apple.
