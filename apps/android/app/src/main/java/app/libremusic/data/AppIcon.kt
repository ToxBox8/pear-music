package app.libremusic.data

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * Pear Music tiene un solo icono, el de encendido. Hasta 0.9.5 se podía elegir el violeta (Ajustes › Aspecto ›
 * Icono de la app), que era un `activity-alias` (`.MainActivityViolet`). El alias sigue en el manifiesto, ya con
 * el icono de encendido, para que a quien lo tenía activo no se le quede la app sin icono al actualizar; al
 * abrir la app se vuelve a activar `.MainActivity` y se apaga el alias.
 */
object AppIcon {
    fun migrateLegacy(context: Context) {
        val pm = context.packageManager
        val legacy = ComponentName(context.packageName, "app.libremusic.MainActivityViolet")
        if (pm.getComponentEnabledSetting(legacy) != PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return
        // Primero se activa el de por defecto y después se apaga el antiguo: nunca se queda la app sin icono.
        pm.setComponentEnabledSetting(ComponentName(context.packageName, "app.libremusic.MainActivity"),
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT, PackageManager.DONT_KILL_APP)
        pm.setComponentEnabledSetting(legacy, PackageManager.COMPONENT_ENABLED_STATE_DEFAULT, PackageManager.DONT_KILL_APP)
    }
}
