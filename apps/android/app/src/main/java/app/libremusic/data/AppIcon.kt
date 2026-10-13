package app.libremusic.data

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * Icono de la app (Ajustes › Aspecto › Icono de la app). Cada icono es un `activity-alias` del manifiesto y
 * sólo uno está activo. Mismas claves que `AppIcon` en iOS (allí, iconos alternativos del sistema).
 *
 * Limitaciones de Android: el lanzador puede tardar unos segundos en cambiarlo y, según el lanzador, quita
 * el acceso directo de la pantalla de inicio al cambiar (hay que volver a ponerlo desde el cajón de apps).
 */
enum class AppIcon(val key: String, val title: String, val alias: String) {
    Power("power", "Encendido", ".MainActivity"),
    Violet("violet", "Violeta", ".MainActivityViolet");

    companion object {
        private fun component(context: Context, icon: AppIcon) = ComponentName(context.packageName, "app.libremusic" + icon.alias)

        /** El activo, leído del sistema (es la fuente de verdad, no un ajuste guardado). */
        fun current(context: Context): AppIcon = entries.firstOrNull { icon ->
            when (context.packageManager.getComponentEnabledSetting(component(context, icon))) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> icon == Power
                else -> false
            }
        } ?: Power

        fun set(context: Context, icon: AppIcon) {
            if (current(context) == icon) return
            val pm = context.packageManager
            // Primero se activa el nuevo y después se apaga el anterior: nunca se queda la app sin icono.
            pm.setComponentEnabledSetting(component(context, icon), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            entries.filter { it != icon }.forEach {
                pm.setComponentEnabledSetting(component(context, it), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            }
        }
    }
}
