package app.libremusic.playback


import app.libremusic.L
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.view.View
import android.widget.RemoteViews
import androidx.core.graphics.drawable.toBitmap
import app.libremusic.LibreMusicApplication
import app.libremusic.R
import app.libremusic.data.AppShortcuts
import coil.imageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Widgets de la pantalla de inicio (Fase 3.4), configurables en Ajustes › Widgets: «Ahora suena» pequeño y
 * grande ([NowPlayingWidget]), accesos rápidos, playlist fijada y recientes. Sólo Android por ahora.
 */
object Widgets {
    private const val PREFS = "widgets"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    enum class Kind(val provider: Class<*>, private val titleText: () -> String, private val textText: () -> String) {
        NowPlaying(NowPlayingWidget::class.java, { L("Ahora suena") }, { L("Carátula, título y controles en una fila (4×1).") }),
        NowPlayingLarge(NowPlayingLargeWidget::class.java, { L("Ahora suena grande") }, { L("Carátula grande y controles (4×2).") }),
        Quick(QuickWidget::class.java, { L("Accesos rápidos") }, { L("Mezclar favoritas o descargadas, Descubrir y Buscar (4×1).") }),
        Playlist(PlaylistWidget::class.java, { L("Playlist fijada") }, { L("La playlist que elijas abajo, para ponerla a sonar de un toque (2×2).") }),
        Recents(RecentsWidget::class.java, { L("Recientes") }, { L("Las cuatro últimas canciones que escuchaste (4×2).") }),
    ;
    val title: String get() = titleText()
    val text: String get() = textText()
}

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** «dark» (por defecto) o «light». */
    fun theme(c: Context): String = prefs(c).getString("theme", "dark") ?: "dark"
    fun setTheme(c: Context, v: String) { prefs(c).edit().putString("theme", v).apply(); refreshAll(c) }

    /** Id de la playlist del widget «Playlist fijada» (null = la primera fijada). */
    fun playlistId(c: Context): String? = prefs(c).getString("playlist", null)
    fun setPlaylistId(c: Context, id: String?) { prefs(c).edit().putString("playlist", id).apply(); refreshAll(c) }

    fun applyTheme(c: Context, v: RemoteViews, root: Int, titles: List<Int>, subtitles: List<Int>) {
        val light = theme(c) == "light"
        v.setInt(root, "setBackgroundResource", if (light) R.drawable.widget_background_light else R.drawable.widget_background)
        titles.forEach { v.setTextColor(it, if (light) 0xFF1C1B22.toInt() else 0xFFFFFFFF.toInt()) }
        subtitles.forEach { v.setTextColor(it, if (light) 0xB33C3C43.toInt() else 0xB3EBEBF5.toInt()) }
    }

    /** ¿Está puesto en alguna pantalla de inicio? */
    fun installed(c: Context, kind: Kind) = AppWidgetManager.getInstance(c).getAppWidgetIds(ComponentName(c, kind.provider)).isNotEmpty()

    /** Pide al lanzador que lo añada (Android 8+, si el lanzador lo admite). Devuelve si se pudo pedir. */
    fun requestPin(c: Context, kind: Kind): Boolean {
        val m = AppWidgetManager.getInstance(c)
        return m.isRequestPinAppWidgetSupported && m.requestPinAppWidget(ComponentName(c, kind.provider), null, null)
    }

    /** Vuelve a dibujar todos (tras cambiar el tema, la playlist o los recientes). */
    fun refreshAll(c: Context) {
        val app = c.applicationContext
        NowPlayingWidget.refresh(app)
        QuickWidget.render(app)
        PlaylistWidget.render(app)
        RecentsWidget.render(app)
    }

    fun library(c: Context) = (c.applicationContext as? LibreMusicApplication)?.library

    internal fun open(c: Context, intent: android.content.Intent, code: Int): PendingIntent =
        PendingIntent.getActivity(c, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    /** Carátula redondeada, cargada en segundo plano; [done] se llama en el hilo principal. */
    internal fun cover(c: Context, url: String?, size: Int, done: (Bitmap?) -> Unit) {
        if (url == null) { done(null); return }
        scope.launch {
            val r = c.imageLoader.execute(ImageRequest.Builder(c).data(url).size(size).allowHardware(false).build())
            done((r as? SuccessResult)?.drawable?.toBitmap(size, size)?.let { rounded(it, size * 0.12f) })
        }
    }

    private fun rounded(src: Bitmap, radius: Float): Bitmap {
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawRoundRect(RectF(0f, 0f, src.width.toFloat(), src.height.toFloat()), radius, radius, p)
        p.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(src, 0f, 0f, p)
        return out
    }
}

/** Accesos rápidos (4×1): los mismos atajos que el icono de la app. */
class QuickWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context)

    companion object {
        fun render(c: Context) {
            val m = AppWidgetManager.getInstance(c)
            val ids = m.getAppWidgetIds(ComponentName(c, QuickWidget::class.java))
            if (ids.isEmpty()) return
            val v = RemoteViews(c.packageName, R.layout.widget_quick)
            val labels = listOf(R.id.quick_favorites_label, R.id.quick_downloads_label, R.id.quick_discover_label, R.id.quick_search_label)
            Widgets.applyTheme(c, v, R.id.widget_root, titles = labels, subtitles = emptyList())
            listOf(
                R.id.quick_favorites to AppShortcuts.Kind.Favorites, R.id.quick_downloads to AppShortcuts.Kind.Downloads,
                R.id.quick_discover to AppShortcuts.Kind.Discover, R.id.quick_search to AppShortcuts.Kind.Search,
            ).forEachIndexed { i, (id, kind) -> v.setOnClickPendingIntent(id, Widgets.open(c, AppShortcuts.intent(c, kind), 100 + i)) }
            m.updateAppWidget(ids, v)
        }
    }
}

/** Playlist fijada (2×2): la elegida en Ajustes › Widgets o, si no, la primera fijada en Biblioteca. */
class PlaylistWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context)

    companion object {
        fun render(c: Context) {
            val m = AppWidgetManager.getInstance(c)
            val ids = m.getAppWidgetIds(ComponentName(c, PlaylistWidget::class.java))
            if (ids.isEmpty()) return
            val lib = Widgets.library(c)
            val all = lib?.data?.value?.playlists.orEmpty()
            val p = Widgets.playlistId(c)?.let { id -> all.firstOrNull { it.id == id } } ?: all.firstOrNull { it.pinned }
            val v = RemoteViews(c.packageName, R.layout.widget_playlist)
            Widgets.applyTheme(c, v, R.id.widget_root, titles = emptyList(), subtitles = emptyList())
            if (p == null) {
                v.setTextViewText(R.id.playlist_name, c.getString(R.string.widget_playlist_empty))
                v.setImageViewResource(R.id.playlist_cover, R.drawable.ic_launcher_power)
                v.setOnClickPendingIntent(R.id.widget_root, Widgets.open(c, AppShortcuts.intent(c, AppShortcuts.Kind.Favorites).setAction(android.content.Intent.ACTION_MAIN), 200))
                m.updateAppWidget(ids, v)
                return
            }
            v.setTextViewText(R.id.playlist_name, p.name)
            v.setOnClickPendingIntent(R.id.widget_root, Widgets.open(c, AppShortcuts.playIntent(c, "playlist", p.id), 201))
            // Portada propia si la hay; si no, la de su primera canción.
            val own = lib?.coverFile(p.id)?.takeIf { it.exists() }?.let { android.graphics.BitmapFactory.decodeFile(it.path) }
            if (own != null) {
                v.setImageViewBitmap(R.id.playlist_cover, own)
                m.updateAppWidget(ids, v)
            } else {
                v.setImageViewResource(R.id.playlist_cover, R.drawable.ic_launcher_power)
                m.updateAppWidget(ids, v)
                Widgets.cover(c, p.songs.firstOrNull()?.thumb(400), 400) { bmp ->
                    if (bmp != null) { v.setImageViewBitmap(R.id.playlist_cover, bmp); m.updateAppWidget(ids, v) }
                }
            }
        }
    }
}

/** Recientes (4×2): las cuatro últimas canciones; tocar una la pone a sonar con las demás detrás. */
class RecentsWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context)

    companion object {
        private val slots = listOf(
            Triple(R.id.recent_0, R.id.recent_0_cover, R.id.recent_0_title),
            Triple(R.id.recent_1, R.id.recent_1_cover, R.id.recent_1_title),
            Triple(R.id.recent_2, R.id.recent_2_cover, R.id.recent_2_title),
            Triple(R.id.recent_3, R.id.recent_3_cover, R.id.recent_3_title),
        )

        fun render(c: Context) {
            val m = AppWidgetManager.getInstance(c)
            val ids = m.getAppWidgetIds(ComponentName(c, RecentsWidget::class.java))
            if (ids.isEmpty()) return
            val recents = Widgets.library(c)?.data?.value?.recents.orEmpty().take(4)
            val v = RemoteViews(c.packageName, R.layout.widget_recents)
            Widgets.applyTheme(c, v, R.id.widget_root, titles = listOf(R.id.recents_header) + slots.map { it.third }, subtitles = listOf(R.id.recents_empty))
            v.setViewVisibility(R.id.recents_empty, if (recents.isEmpty()) View.VISIBLE else View.GONE)
            v.setViewVisibility(R.id.recents_row, if (recents.isEmpty()) View.GONE else View.VISIBLE)
            slots.forEachIndexed { i, (slot, cover, title) ->
                val s = recents.getOrNull(i)
                v.setViewVisibility(slot, if (s == null) View.INVISIBLE else View.VISIBLE)
                if (s == null) return@forEachIndexed
                v.setTextViewText(title, s.title)
                v.setContentDescription(slot, "${s.title}, ${s.artist}")
                v.setImageViewResource(cover, R.drawable.ic_launcher_power)
                v.setOnClickPendingIntent(slot, Widgets.open(c, AppShortcuts.playIntent(c, "song", s.id), 300 + i))
            }
            m.updateAppWidget(ids, v)
            recents.forEachIndexed { i, s ->
                Widgets.cover(c, s.thumb(240), 240) { bmp ->
                    if (bmp != null) { v.setImageViewBitmap(slots[i].second, bmp); m.updateAppWidget(ids, v) }
                }
            }
        }
    }
}
