package app.libremusic.data


import app.libremusic.L
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

    enum class Kind(val key: String, private val shortEs: String, private val longEs: String, val icon: Int) {
        Favorites("favorites", L("Mezclar favoritas"), L("Mezclar mis favoritas"), R.drawable.ic_shortcut_shuffle),
        Downloads("downloads", "Descargadas", L("Mezclar lo descargado"), R.drawable.ic_shortcut_download),
        Discover("discover", "Descubrir", L("Abrir Descubrir"), R.drawable.ic_shortcut_discover),
        Search("search", "Buscar", L("Buscar música"), R.drawable.ic_shortcut_search),
        ;
    val short: String get() = L(shortEs)
    val long: String get() = L(longEs)

        companion object { fun of(key: String?) = entries.firstOrNull { it.key == key } }
    }

    /** El atajo que acaba de abrir la app; lo consume la interfaz. */
    val pending = MutableStateFlow<Kind?>(null)

    /** Desde los widgets (Fase 3.4): reproducir una playlist («playlist», id) o una canción reciente («song», id). */
    const val ACTION_PLAY = "app.libremusic.action.PLAY"
    const val EXTRA_TYPE = "type"
    const val EXTRA_ID = "id"
    val pendingPlay = MutableStateFlow<Pair<String, String>?>(null)

    fun handle(intent: Intent?) {
        if (intent?.action == ACTION) Kind.of(intent.getStringExtra(EXTRA))?.let { pending.value = it }
        if (intent?.action == ACTION_PLAY) {
            val type = intent.getStringExtra(EXTRA_TYPE)
            val id = intent.getStringExtra(EXTRA_ID)
            if (type != null && id != null) pendingPlay.value = type to id
        }
    }

    /** Intent que abre la app en [kind] (para los widgets de accesos rápidos). */
    fun intent(context: Context, kind: Kind): Intent =
        Intent(context, AppActivity::class.java).setAction(ACTION).putExtra(EXTRA, kind.key).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)

    fun playIntent(context: Context, type: String, id: String): Intent =
        Intent(context, AppActivity::class.java).setAction(ACTION_PLAY).putExtra(EXTRA_TYPE, type).putExtra(EXTRA_ID, id)
            .setData(android.net.Uri.parse("libremusic-widget://$type/$id")) // único por destino: PendingIntent distintos
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)

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
