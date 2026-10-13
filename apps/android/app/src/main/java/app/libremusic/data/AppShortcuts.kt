package app.libremusic.data

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import app.libremusic.AppActivity
import app.libremusic.R
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Atajos al mantener pulsado el icono de la app (y para el Asistente): mezclar favoritas, mezclar descargadas,
 * Descubrir y Buscar. Son dinámicos (no `shortcuts.xml`) porque la versión de pruebas tiene otro paquete y los
 * iconos de la app son `activity-alias`. Los mismos que los atajos de Siri en iOS (`AppShortcuts.swift`).
 */
object AppShortcuts {
    const val ACTION = "app.libremusic.action.SHORTCUT"
    const val EXTRA = "shortcut"

    enum class Kind(val key: String, val short: String, val long: String, val icon: Int) {
        Favorites("favorites", "Mezclar favoritas", "Mezclar mis favoritas", R.drawable.ic_shortcut_shuffle),
        Downloads("downloads", "Descargadas", "Mezclar lo descargado", R.drawable.ic_shortcut_download),
        Discover("discover", "Descubrir", "Abrir Descubrir", R.drawable.ic_shortcut_discover),
        Search("search", "Buscar", "Buscar música", R.drawable.ic_shortcut_search),
        ;

        companion object { fun of(key: String?) = entries.firstOrNull { it.key == key } }
    }

    /** El atajo que acaba de abrir la app; lo consume la interfaz. */
    val pending = MutableStateFlow<Kind?>(null)

    fun handle(intent: Intent?) {
        if (intent?.action == ACTION) Kind.of(intent.getStringExtra(EXTRA))?.let { pending.value = it }
    }

    fun publish(context: Context) {
        val list = Kind.entries.map { k ->
            ShortcutInfoCompat.Builder(context, k.key)
                .setShortLabel(k.short)
                .setLongLabel(k.long)
                .setIcon(IconCompat.createWithResource(context, k.icon))
                .setIntent(Intent(context, AppActivity::class.java).setAction(ACTION).putExtra(EXTRA, k.key).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP))
                .build()
        }
        runCatching { ShortcutManagerCompat.setDynamicShortcuts(context, list) }
    }
}
