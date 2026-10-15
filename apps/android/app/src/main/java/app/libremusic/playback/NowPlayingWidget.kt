package app.libremusic.playback

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.view.KeyEvent
import android.widget.RemoteViews
import androidx.core.graphics.drawable.toBitmap
import androidx.media3.common.Player
import app.libremusic.AppActivity
import app.libremusic.R
import app.libremusic.data.Song
import coil.imageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Widget «Ahora suena» (4×1): carátula, título, artista y anterior / reproducir / siguiente. Lo actualiza
 * [PlaybackService] al cambiar de canción o de estado; los botones mandan teclas multimedia al servicio, así que
 * funcionan con la app cerrada. Con la app cerrada sigue enseñando la última canción y «reproducir» la retoma; sólo si nunca ha sonado nada, tocarlo abre la app. Sólo Android por ahora (en iOS haría falta una
 * extensión de WidgetKit).
 */
class NowPlayingWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // Al añadirlo (o si el proceso se cerró): lo último conocido; si no, la última cola guardada en pausa.
        val song = last.first ?: LastQueue.load(context)?.let { it.songs[it.index] }
        render(context, song, last.second, lastCover)
    }

    companion object {
        private var last: Pair<Song?, Boolean> = null to false
        private var lastCover: Bitmap? = null
        private var lastCoverId: String? = null
        private var scope: CoroutineScope? = null

        /** Lo llama el servicio con el reproductor: se engancha a sus cambios. */
        fun attach(context: Context, player: Player) {
            val app = context.applicationContext
            val s = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            scope = s
            player.addListener(object : Player.Listener {
                override fun onEvents(p: Player, events: Player.Events) {
                    if (events.containsAny(Player.EVENT_MEDIA_ITEM_TRANSITION, Player.EVENT_IS_PLAYING_CHANGED, Player.EVENT_PLAYBACK_STATE_CHANGED)) {
                        update(app, s, p.currentMediaItem?.toSong(), p.playWhenReady)
                    }
                }
            })
        }

        fun detach(context: Context) {
            scope?.cancel()
            scope = null
            // El servicio se cierra: se queda la última canción en pausa y «reproducir» la retoma
            // (onPlaybackResumption), en vez de dejar el widget vacío y que todo abra la app.
            val app = context.applicationContext
            val song = LastQueue.load(app)?.let { it.songs[it.index] }
            last = song to false
            render(app, song, false, lastCover.takeIf { song?.id == lastCoverId })
        }

        private fun update(context: Context, scope: CoroutineScope, song: Song?, playing: Boolean) {
            last = song to playing
            if (song?.id != lastCoverId) {
                lastCover = null
                lastCoverId = song?.id
                val url = song?.thumb(240)
                if (url != null) scope.launch {
                    val r = context.imageLoader.execute(ImageRequest.Builder(context).data(url).size(240).allowHardware(false).build())
                    val bmp = (r as? SuccessResult)?.drawable?.toBitmap(240, 240)
                    if (bmp != null && lastCoverId == song.id) {
                        lastCover = rounded(bmp, 28f)
                        render(context, last.first, last.second, lastCover)
                    }
                }
            }
            render(context, song, playing, lastCover)
        }

        /** Vuelve a dibujar con lo último conocido (al cambiar el tema de los widgets). */
        fun refresh(context: Context) = render(context.applicationContext, last.first, last.second, lastCover)

        /** Al añadir el grande: lo último conocido o la última cola guardada, como el pequeño. */
        fun refreshOrLoad(context: Context) {
            val song = last.first ?: LastQueue.load(context)?.let { it.songs[it.index] }
            render(context.applicationContext, song, last.second, lastCover)
        }

        /** El pequeño (4×1) y el grande (4×2) comparten ids: se dibujan igual, cada uno con su diseño. */
        private fun render(context: Context, song: Song?, playing: Boolean, cover: Bitmap?) {
            render(context, song, playing, cover, NowPlayingWidget::class.java, R.layout.widget_now_playing)
            render(context, song, playing, cover, NowPlayingLargeWidget::class.java, R.layout.widget_now_playing_large)
        }

        private fun render(context: Context, song: Song?, playing: Boolean, cover: Bitmap?, provider: Class<*>, layout: Int) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) return
            val v = RemoteViews(context.packageName, layout)
            Widgets.applyTheme(context, v, R.id.widget_root, titles = listOf(R.id.widget_title), subtitles = listOf(R.id.widget_artist))
            val open = PendingIntent.getActivity(context, 0, Intent(context, AppActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            v.setOnClickPendingIntent(R.id.widget_root, open)
            v.setTextViewText(R.id.widget_title, song?.title ?: context.getString(R.string.widget_idle_title))
            v.setTextViewText(R.id.widget_artist, song?.artist ?: context.getString(R.string.widget_idle_subtitle))
            if (cover != null) v.setImageViewBitmap(R.id.widget_cover, cover) else v.setImageViewResource(R.id.widget_cover, R.drawable.ic_launcher_power)
            v.setImageViewResource(R.id.widget_play, if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
            v.setContentDescription(R.id.widget_play, context.getString(R.string.widget_play))
            if (song != null && scope != null) {
                v.setOnClickPendingIntent(R.id.widget_prev, mediaKey(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                v.setOnClickPendingIntent(R.id.widget_play, mediaKey(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                v.setOnClickPendingIntent(R.id.widget_next, mediaKey(context, KeyEvent.KEYCODE_MEDIA_NEXT))
            } else if (song != null) {
                // Servicio cerrado: cualquier botón retoma la última cola (onPlaybackResumption). Anterior/siguiente
                // no tendrían cola que mover y el servicio arrancado tiene que ponerse a sonar enseguida.
                val resume = mediaKey(context, KeyEvent.KEYCODE_MEDIA_PLAY)
                listOf(R.id.widget_prev, R.id.widget_play, R.id.widget_next).forEach { v.setOnClickPendingIntent(it, resume) }
            } else {
                // Sin nada sonando los botones también abren la app (no hay cola que controlar).
                listOf(R.id.widget_prev, R.id.widget_play, R.id.widget_next).forEach { v.setOnClickPendingIntent(it, open) }
            }
            manager.updateAppWidget(ids, v)
        }

        /** Tecla multimedia para el servicio (Media3 la recibe en onStartCommand, también con la app cerrada). */
        private fun mediaKey(context: Context, code: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
                .setComponent(ComponentName(context, PlaybackService::class.java))
                .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, code))
            return PendingIntent.getForegroundService(context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        private fun rounded(src: Bitmap, radius: Float): Bitmap {
            val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
            val c = Canvas(out)
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            c.drawRoundRect(RectF(0f, 0f, src.width.toFloat(), src.height.toFloat()), radius, radius, p)
            p.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            c.drawBitmap(src, 0f, 0f, p)
            return out
        }
    }
}

/** «Ahora suena» grande (4×2, Fase 3.4): lo dibuja [NowPlayingWidget] con su propio diseño. */
class NowPlayingLargeWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = NowPlayingWidget.refreshOrLoad(context)
}
