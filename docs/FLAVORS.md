# Variantes (flavors): usr, pref y dev

Pear Music son **tres apps con el mismo código**, sin repos ni código duplicados. Lo que cambia entre ellas son
banderas de compilación. Lo decidió Toxbox (Fase 1 de Android 1.0 / iOS 2.0, 14-10-2026).

| Variante | Para quién | Nombre bajo el icono | Android `applicationId` | iOS bundle id | Qué lleva |
|---|---|---|---|---|---|
| **usr** | Todo el mundo (web, GitHub, AltStore, Obtainium) | Pear Music | `app.libremusic` | `com.example.libremusic` | La app normal. Minificada y ofuscada con R8 en release. Sin herramientas de depuración ni registro de depuración. |
| **pref** | Sólo el móvil de Toxbox | Pear Pref | `app.libremusic.pref` | `com.example.libremusic.pref` | Igual que usr, instalable al lado. Sin herramientas de administración. |
| **dev** | Sólo el móvil de Toxbox | Pear Dev | `app.libremusic.dev` | `com.example.libremusic.dev` | Ajustes › Ayuda y soporte › **Administración**: canal y versión, registro reciente en memoria y **botón de pánico** remoto (publica un estado firmado: aviso, modo seguro, bloqueo o normal; `docs/RUNBOOK-INCIDENTES.md`). Registro detallado. |

**pref y dev no se publican nunca**: ni en Releases, ni en la web, ni en el repo público. En Android se instalan
por cable (`adb`) con el móvil en depuración USB; en iOS, con iloader/Sideloadly desde un `.ipa` de su scheme.
usr conserva los identificadores de siempre para que quien ya tiene la app la actualice encima.

## Banderas

| | usr | pref | dev |
|---|---|---|---|
| Android `BuildConfig.CHANNEL` / iOS `Channel.current` | `"usr"` | `"pref"` | `"dev"` |
| `ADMIN_TOOLS` / `Channel.adminTools` (pantalla Administración) | no | no | sí |
| `VERBOSE_LOGS` / `Channel.verboseLogs` (`Logs.d`/`i` y registro en memoria) | no | no | sí |

El código pregunta a esas banderas; nunca hay una copia de una pantalla por variante. Los avisos y errores
(`Logs.w`/`e`) llegan al logcat en todas, pero **nunca llevan datos personales** (ver `docs/SEGURIDAD.md`).

## Android

`productFlavors` con la dimensión `canal` en `apps/android/app/build.gradle.kts`, combinados con los tipos de
siempre (`debug`, `release`, `perf`): `usrRelease` es la pública, `devDebug` se instala como
`app.libremusic.dev.debug`, `usrPerf` mide fluidez, etc. El nombre de dev y pref sale de `src/dev` y `src/pref`.

```bash
cd apps/android
scripts/variante.sh usr release     # APK público → app/build/outputs/apk/usr/release/app-usr-release.apk
scripts/variante.sh pref            # compila Pear Pref y la instala en el móvil conectado
scripts/variante.sh dev             # compila Pear Dev y la instala en el móvil conectado
gradle testUsrDebugUnitTest         # tests (los de capturas usan usr)
```

Para firmar con la clave de release, exporta antes las variables `ANDROID_KEYSTORE_*` (`docs/RELEASING.md`). Sin
ellas, `release` se firma con la clave de depuración: sirve para pref y dev, pero **no mezcles** las dos claves en
la misma variante del mismo móvil (Android no deja actualizar si cambia la firma; habría que desinstalar).

## iOS

XcodeGen (`apps/ios/project.yml`): cuatro configuraciones, cada una con su `Config/*.xcconfig` (bundle id, nombre
`APP_DISPLAY_NAME` y `SWIFT_ACTIVE_COMPILATION_CONDITIONS` = `CHANNEL_PREF` / `CHANNEL_DEV`), y un scheme por canal.

| Scheme | Configuración | Canal |
|---|---|---|
| `LibreMusic` | Debug / Release | usr (el que usan la CI y las releases; no cambia de nombre) |
| `Pear Pref` | Pref | pref |
| `Pear Dev` | Dev | dev |

```bash
cd apps/ios && xcodegen generate
xcodebuild -project LibreMusic.xcodeproj -scheme "Pear Dev" -configuration Dev -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO build      # luego se empaqueta el .app en un .ipa como en ios.yml
```

Sin Mac, el `.ipa` de una variante sale de la CI del repo público cambiando `-scheme`/`-configuration` en el
`workflow_dispatch` (pendiente: hoy `ios.yml` sólo compila usr).

## Datos del usuario y telemetría

Las tres variantes tienen Ajustes › Ayuda y soporte › **Tus datos** (exportar todo en un .zip y borrar todos los
datos). Más adelante habrá telemetría: tendrá que pedir **consentimiento explícito, separado y retirable**
(RGPD), apagada por defecto, y su identificador y su consentimiento tendrán que entrar en «Exportar» y «Borrar».
