package app.libremusic.playback

import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import app.libremusic.R
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Captura del widget «Ahora suena» (layout de RemoteViews inflado a 4×1). */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "es-rES-w411dp-h891dp-xxhdpi")
class WidgetShotTest {
    @Test fun widget() {
        val ctx = org.robolectric.Robolectric.buildActivity(android.app.Activity::class.java).setup().get()
        val root = FrameLayout(ctx).apply { setBackgroundColor(0x00000000); setPadding(0, 0, 0, 0) }
        val v = LayoutInflater.from(ctx).inflate(R.layout.widget_now_playing, root, false)
        v.findViewById<TextView>(R.id.widget_title).text = "Luz de neón"
        v.findViewById<TextView>(R.id.widget_artist).text = "Aurora Vela"
        v.findViewById<ImageView>(R.id.widget_play).setImageResource(R.drawable.ic_widget_pause)
        v.findViewById<ImageView>(R.id.widget_cover).setImageResource(R.drawable.ic_launcher_power)
        root.addView(v, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, (76 * ctx.resources.displayMetrics.density).toInt()))
        val w = (360 * ctx.resources.displayMetrics.density).toInt()
        ctx.setContentView(root, android.view.ViewGroup.LayoutParams(w, android.view.ViewGroup.LayoutParams.WRAP_CONTENT))
        root.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        root.layout(0, 0, root.measuredWidth, root.measuredHeight)
        root.captureRoboImage("build/shots/w1_widget.png")
    }

    /** Infla un diseño de widget, deja que [fill] lo rellene y lo captura a [wDp]×[hDp]. */
    private fun shot(layout: Int, name: String, wDp: Int, hDp: Int, fill: (View) -> Unit) {
        val ctx = org.robolectric.Robolectric.buildActivity(android.app.Activity::class.java).setup().get()
        val d = ctx.resources.displayMetrics.density
        val root = FrameLayout(ctx)
        val v = LayoutInflater.from(ctx).inflate(layout, root, false)
        fill(v)
        root.addView(v, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, (hDp * d).toInt()))
        val w = (wDp * d).toInt()
        ctx.setContentView(root, android.view.ViewGroup.LayoutParams(w, android.view.ViewGroup.LayoutParams.WRAP_CONTENT))
        root.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        root.layout(0, 0, root.measuredWidth, root.measuredHeight)
        root.captureRoboImage("build/shots/$name.png")
    }

    @Test fun grande() = shot(R.layout.widget_now_playing_large, "w2_ahora_suena_grande", 360, 150) { v ->
        v.findViewById<TextView>(R.id.widget_title).text = "Luz de neón"
        v.findViewById<TextView>(R.id.widget_artist).text = "Aurora Vela"
        v.findViewById<ImageView>(R.id.widget_play).setImageResource(R.drawable.ic_widget_pause)
        v.findViewById<ImageView>(R.id.widget_cover).setImageResource(R.drawable.ic_launcher_power)
    }

    @Test fun accesos() = shot(R.layout.widget_quick, "w3_accesos_rapidos", 360, 80) {}

    @Test fun playlist() = shot(R.layout.widget_playlist, "w4_playlist_fijada", 170, 170) { v ->
        v.findViewById<TextView>(R.id.playlist_name).text = "Viaje en coche"
        v.findViewById<ImageView>(R.id.playlist_cover).setImageResource(R.drawable.story_temas)
    }

    @Test fun recientes() = shot(R.layout.widget_recents, "w5_recientes", 360, 150) { v ->
        listOf(R.id.recent_0_title to "Luz de neón", R.id.recent_1_title to "Mar de fondo", R.id.recent_2_title to "Kilómetro 0", R.id.recent_3_title to "Brisa")
            .forEach { (id, t) -> v.findViewById<TextView>(id).text = t }
        listOf(R.id.recent_0_cover, R.id.recent_1_cover, R.id.recent_2_cover, R.id.recent_3_cover)
            .forEach { v.findViewById<ImageView>(it).setImageResource(R.drawable.ic_launcher_power) }
    }

    @Test fun recientesClaro() = shot(R.layout.widget_recents, "w6_recientes_claro", 360, 150) { v ->
        v.setBackgroundResource(R.drawable.widget_background_light)
        listOf(R.id.recents_header, R.id.recent_0_title, R.id.recent_1_title).forEach { v.findViewById<TextView>(it).setTextColor(0xFF1C1B22.toInt()) }
        v.findViewById<TextView>(R.id.recent_0_title).text = "Luz de neón"
        v.findViewById<TextView>(R.id.recent_1_title).text = "Mar de fondo"
        v.findViewById<View>(R.id.recent_2).visibility = View.INVISIBLE
        v.findViewById<View>(R.id.recent_3).visibility = View.INVISIBLE
    }
}
