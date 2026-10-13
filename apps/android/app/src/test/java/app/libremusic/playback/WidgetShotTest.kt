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
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
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
}
