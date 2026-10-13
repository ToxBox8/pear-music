package app.libremusic.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material.icons.rounded.FastRewind
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.libremusic.data.Song
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.LocalReduceMotion
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Casete y tocadiscos: réplica de Kitchen.swift y Deck.swift (el «Cassette Audio Player» de dqnamo
// y el tocadiscos con el brazo que sigue el progreso).

private fun hex(v: Long, a: Float = 1f) = Color(0xFF000000 or v).copy(alpha = a)

/** Diferencia entre dos ángulos en (-π, π]. */
fun angleDelta(a: Double, b: Double): Double {
    var d = a - b
    while (d > PI) d -= 2 * PI
    while (d <= -PI) d += 2 * PI
    return d
}

/**
 * Reloj de animación: milisegundos acumulados mientras [running] (no avanza en pausa, así que al
 * reanudar no hay salto). Antes devolvía la hora del sistema y los ángulos (~10¹¹ grados) perdían
 * la precisión al pasar a Float: el vinilo y el casete parecían parados.
 */
@Composable
fun rememberClock(running: Boolean): Long = rememberClockState(running).longValue

/**
 * El mismo reloj como estado, para leerlo dentro de `graphicsLayer {}` o de un Canvas: así sólo se
 * redibuja, sin recomponer toda la pantalla en cada fotograma.
 */
@Composable
fun rememberClockState(running: Boolean): androidx.compose.runtime.MutableLongState {
    val t = remember { mutableLongStateOf(0L) }
    LaunchedEffect(running) {
        var last = 0L
        while (running) withFrameMillis { now ->
            if (last != 0L) t.longValue += now - last
            last = now
        }
    }
    return t
}

private object Tape {
    val shell = listOf(hex(0x373735), hex(0x20201F), hex(0x0E0E0D))
    val window = hex(0x1B1A18)
    const val ROTATION_PER_SECOND = 300.0
    fun label(dark: Boolean) = if (dark) hex(0xDC2626) else hex(0xFCFCFC)
    fun ink(dark: Boolean) = if (dark) Color.White else hex(0x1C1C1A)
    fun stripes(dark: Boolean) = if (dark) listOf(Color.White, Color.White, Color.White) else listOf(hex(0x22C55E), hex(0x14B8A6), hex(0x3B82F6))
}

// MARK: Casete ---------------------------------------------------------------------------------

@Composable
fun CassetteView(song: Song) {
    val c = Libre.colors
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val reduce = LocalReduceMotion.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val dark = c.dark
    var scrub by remember { mutableStateOf<Double?>(null) }
    var wind by remember { mutableStateOf<Double?>(null) }
    var windAngle by remember { mutableDoubleStateOf(0.0) }
    var windWasPlaying by remember { mutableStateOf(false) }
    var windTick by remember { mutableDoubleStateOf(0.0) }
    val rewind = remember { Animatable(0f) }
    val duration = st.duration
    val fraction = if (duration > 0) (st.progress / duration).coerceIn(0.0, 1.0) else 0.0
    val current = scrub ?: wind?.let { if (duration > 0) (it / duration).coerceIn(0.0, 1.0) else 0.0 } ?: fraction
    val shown = current * (1 - rewind.value)
    val catalogue = "%06d".format(song.id.fold(7L) { acc, ch -> (acc * 31 + ch.code) % 1_000_000 })
    val clock = rememberClockState(st.isPlaying && !reduce)
    val progressNow = st.progress
    // Se lee al dibujar (no al componer): las bobinas giran sin recomponer el casete entero.
    val angle = {
        val spin = (clock.longValue / 1000.0) * Tape.ROTATION_PER_SECOND
        val back = min(progressNow * Tape.ROTATION_PER_SECOND, 2160.0) * rewind.value
        ((if (reduce) 0.0 else spin - back) + windAngle) % 360.0
    }

    fun windBy(radians: Double) {
        if (wind == null) {
            windWasPlaying = st.isPlaying
            if (windWasPlaying) env.player.pause()
            wind = st.progress
        }
        windAngle += radians * 180 / PI
        wind = ((wind ?: 0.0) + radians / (2 * PI) * 6).coerceIn(0.0, max(duration, 0.0))
        windTick += kotlin.math.abs(radians)
        if (windTick > 0.6) { haptics.tick(); windTick = 0.0 }
    }

    fun windEnd() {
        wind?.let { env.player.seekSeconds(it) }
        wind = null
        if (windWasPlaying) env.player.resume()
    }

    fun restart() {
        val wasPlaying = st.isPlaying
        if (reduce || st.progress <= 0) { env.player.seekSeconds(0.0); return }
        if (wasPlaying) env.player.pause()
        val ms = ((0.22 + 0.78 * fraction) * 1000).toInt()
        scope.launch {
            rewind.animateTo(1f, tween(ms, easing = CubicBezierEasing(0.65f, 0f, 0.35f, 1f)))
            env.player.seekSeconds(0.0)
            rewind.snapTo(0f)
            if (wasPlaying) env.player.resume()
        }
    }

    BoxWithConstraints(Modifier.fillMaxWidth().aspectRatio(1.58f)) {
        val w = maxWidth
        val h = maxHeight
        val density = LocalDensity.current
        // Carcasa
        Canvas(Modifier.fillMaxSize().shadow(24.dp, RoundedCornerShape(w * 0.034f), clip = false, ambientColor = Color.Black.copy(0.24f), spotColor = Color.Black.copy(0.24f))) {
            val r = size.width * 0.034f
            drawRoundRect(Brush.linearGradient(Tape.shell, Offset(size.width * 0.37f, 0f), Offset(size.width * 0.63f, size.height)), cornerRadius = CornerRadius(r))
            drawRoundRect(hex(0x050505), cornerRadius = CornerRadius(r), style = Stroke(1.dp.toPx()))
            val inset = 6.dp.toPx()
            drawRoundRect(
                Color.White.copy(0.12f), Offset(inset, inset), Size(size.width - 2 * inset, size.height - 2 * inset),
                CornerRadius(size.width * 0.025f), style = Stroke(1.dp.toPx()),
            )
            drawRoundRect(
                Brush.verticalGradient(listOf(Color.White.copy(0.2f), Color.Transparent), 0f, size.height / 2),
                cornerRadius = CornerRadius(r), style = Stroke(2.dp.toPx()),
            )
            val screw = size.width * 0.033f
            listOf(
                Offset(size.width * 0.0253f + screw / 2, size.height * 0.04f + screw / 2),
                Offset(size.width - size.width * 0.0253f - screw / 2, size.height * 0.04f + screw / 2),
                Offset(size.width * 0.0253f + screw / 2, size.height - size.height * 0.04f - screw / 2),
                Offset(size.width - size.width * 0.0253f - screw / 2, size.height - size.height * 0.04f - screw / 2),
            ).forEach { drawScrew(it, screw) }
        }

        // Etiqueta
        val lw = w * 0.83f
        val lh = h * 0.665f
        val bg = Tape.label(dark)
        val ink = Tape.ink(dark)
        val small = with(density) { max(8f, (lw * 0.024f).toPx() / this.density / fontScale) }
        Box(
            Modifier.offset(x = (w - lw) / 2, y = h * 0.095f).size(lw, lh).clip(RoundedCornerShape(9.dp)).background(bg)
                .border(4.dp, if (dark) Color.White.copy(0.15f) else bg.copy(0.5f), RoundedCornerShape(9.dp)),
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().padding(start = lw * 0.045f, end = lw * 0.045f, top = lw * 0.04f), verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f)) {
                        Text(song.artist.uppercase(), style = tightLine, color = ink.copy(0.85f), fontSize = small.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, letterSpacing = 0.14.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.height(lh * 0.04f))
                        val titleSize = with(density) { max(13f, (lw * 0.052f).toPx() / this.density / fontScale) }
                        Text(song.title, style = tightLine, color = ink, fontSize = titleSize.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.03).em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Spacer(Modifier.width(8.dp))
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            "LADO A", style = tightLine, color = bg, fontSize = small.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, letterSpacing = 0.1.em,
                            modifier = Modifier.background(ink, CircleShape).padding(horizontal = 7.dp, vertical = 3.dp),
                        )
                        Spacer(Modifier.height(lh * 0.04f))
                        Text(catalogue, style = tightLine, color = ink.copy(0.7f), fontSize = (small * 0.9f).sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, letterSpacing = 0.08.em)
                    }
                }
                // Rayas y ventana
                Box(Modifier.fillMaxWidth().padding(top = lh * 0.06f).height(lh * 0.34f), contentAlignment = Alignment.Center) {
                    Column(Modifier.fillMaxWidth().height(lh * 0.34f * 0.58f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Tape.stripes(dark).forEach { Box(Modifier.fillMaxWidth().weight(1f).background(it)) }
                    }
                    TapeWindow(
                        fraction = shown, angle = angle, ring = bg.copy(0.5f),
                        onWind = ::windBy, onWindEnd = ::windEnd,
                        modifier = Modifier.padding(horizontal = lw * 0.175f).fillMaxSize(),
                    )
                }
                Spacer(Modifier.weight(1f))
                // Progreso
                Column(Modifier.padding(start = lw * 0.045f, end = lw * 0.045f, bottom = lw * 0.035f)) {
                    BoxWithConstraints(
                        Modifier.fillMaxWidth().height(22.dp).pointerInput(duration) {
                            detectDragGestures(
                                onDragStart = { o -> scrub = (o.x / size.width).toDouble().coerceIn(0.0, 1.0) },
                                onDrag = { ch, _ -> scrub = (ch.position.x / size.width).toDouble().coerceIn(0.0, 1.0) },
                                onDragEnd = { scrub?.let { env.player.seekSeconds(it * duration) }; scrub = null },
                            )
                        },
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        val bw = maxWidth
                        Box(Modifier.fillMaxWidth().height(3.dp).background(ink.copy(0.28f), CircleShape))
                        Box(Modifier.width(bw * shown.toFloat()).height(3.dp).background(ink, CircleShape))
                        Box(
                            Modifier.offset(x = ((bw * shown.toFloat()) - 6.5.dp).coerceIn(0.dp, bw - 13.dp)).size(13.dp)
                                .dropShadow(CircleShape, hex(0x25211D, 0.38f), blur = 2.dp, offsetY = 1.dp)
                                .background(Color.White, CircleShape).border(2.dp, bg, CircleShape),
                        )
                    }
                    Spacer(Modifier.height(4.dp))
                    Row(Modifier.fillMaxWidth()) {
                        Text(timeString(current * duration), style = tightLine, color = ink, fontSize = 12.sp)
                        Spacer(Modifier.weight(1f))
                        Text(timeString(duration), style = tightLine, color = ink, fontSize = 12.sp)
                    }
                }
            }
        }

        // Botonera trapezoidal
        val cw = w * 0.46f
        val ch = h * 0.16f
        Box(Modifier.offset(x = (w - cw) / 2, y = h - h * 0.035f - h * 0.16f).size(cw, ch), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val p = trapezoid(size)
                drawPath(p, hex(0x63635E, 0.2f))
                drawPath(p, Brush.verticalGradient(listOf(Color.Black.copy(0.45f), Color.Transparent), 0f, size.height / 2))
            }
            val smallKey = (cw * 0.14f).coerceIn(26.dp, 50.dp)
            val bigKey = (cw * 0.18f).coerceIn(32.dp, 64.dp)
            Row(horizontalArrangement = Arrangement.spacedBy(cw * 0.05f), verticalAlignment = Alignment.CenterVertically) {
                CassetteKey(Icons.Rounded.Replay, smallKey, false, "Volver al inicio", enabled = st.progress > 0) { restart() }
                CassetteKey(if (st.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, bigKey, true, if (st.isPlaying) "Pausa" else "Reproducir") { env.player.togglePlay() }
                CassetteKey(Icons.Rounded.FastForward, smallKey, false, "Siguiente") { env.player.next() }
            }
        }
    }
}

/** Una línea con la altura justa de la letra (1,2), sin el relleno de fuente de Android. */
private val tightLine = TextStyle(
    lineHeight = 1.2.em,
    platformStyle = PlatformTextStyle(includeFontPadding = false),
    lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.Both),
)

private fun trapezoid(s: Size) = Path().apply {
    moveTo(s.width * 0.13f, 0f); lineTo(s.width * 0.87f, 0f); lineTo(s.width, s.height); lineTo(0f, s.height); close()
}

private fun DrawScope.drawScrew(center: Offset, size: Float) {
    drawCircle(
        Brush.radialGradient(listOf(hex(0x5F5F5C), hex(0x30302E), hex(0x171716)), Offset(center.x - size * 0.14f, center.y - size * 0.2f), size * 0.8f),
        size / 2, center,
    )
    drawCircle(hex(0x060606), size / 2, center, style = Stroke(0.8f * density))
    listOf(45f, -45f).forEach { a ->
        rotate(a, center) {
            drawRoundRect(
                hex(0x1D1D1B), Offset(center.x - size * 0.32f, center.y - max(1f, size * 0.07f)),
                Size(size * 0.64f, max(1f, size * 0.14f)), CornerRadius(size * 0.07f),
            )
        }
    }
}

@Composable
private fun CassetteKey(icon: androidx.compose.ui.graphics.vector.ImageVector, size: androidx.compose.ui.unit.Dp, big: Boolean, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    val shape = CircleShape
    Box(Modifier.size(max(44f, size.value).dp).tactile(enabled, label, onClick = onClick), contentAlignment = Alignment.Center) {
        Box(
            Modifier.size(size)
                .shadow(if (big) 4.dp else 2.5.dp, shape, ambientColor = Color.Black.copy(if (big) 0.32f else 0.28f), spotColor = Color.Black.copy(if (big) 0.32f else 0.28f))
                .background(if (big) hex(0x8D8D86) else hex(0x63635E), shape)
                .border(1.dp, if (big) hex(0xBCBBB5, 0.5f) else hex(0x82827C), shape),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, tint = hex(0xFDFDFC), modifier = Modifier.size(size * 0.62f)) }
    }
}

/** Ventana en cápsula con las bobinas y la cinta pasando de un carrete a otro. */
@Composable
private fun TapeWindow(
    fraction: Double,
    angle: () -> Double,
    ring: Color,
    onWind: (Double) -> Unit,
    onWindEnd: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val wind by androidx.compose.runtime.rememberUpdatedState(onWind)
    val windEnd by androidx.compose.runtime.rememberUpdatedState(onWindEnd)
    Canvas(
        modifier.pointerInput(Unit) {
            var lastAngle: Double? = null
            var lastX: Float? = null
            var onReel: Offset? = null
            detectDragGestures(
                onDragStart = { start ->
                    val h = size.height.toFloat()
                    val reels = listOf(Offset(h / 2, h / 2), Offset(size.width - h / 2, h / 2))
                    onReel = reels.firstOrNull { hypot(start.x - it.x, start.y - it.y) < h * 0.55f }
                    lastAngle = null; lastX = null
                },
                onDrag = { ch, _ ->
                    val p = ch.position
                    val reel = onReel
                    if (reel != null) {
                        val a = atan2((p.y - reel.y).toDouble(), (p.x - reel.x).toDouble())
                        lastAngle?.let { wind(angleDelta(a, it)) }
                        lastAngle = a
                    } else {
                        lastX?.let { wind(((p.x - it) / (size.height * 0.39f)).toDouble()) }
                        lastX = p.x
                    }
                },
                onDragEnd = { windEnd() },
                onDragCancel = { windEnd() },
            )
        },
    ) {
        val w = size.width
        val h = size.height
        val cap = CornerRadius(h / 2)
        drawRoundRect(Tape.window, cornerRadius = cap)
        drawRoundRect(Brush.verticalGradient(listOf(Color.White.copy(0.13f), Color.Transparent), 0f, h * 0.45f), cornerRadius = cap)
        // Cinta enrollada vista por el rectángulo central
        val rectW = w * 0.44f
        val rectH = h * 0.76f
        val rx = (w - rectW) / 2
        val ry = (h - rectH) / 2
        val clip = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(rx, ry, rx + rectW, ry + rectH, CornerRadius(3.dp.toPx()))) }
        drawContext.canvas.save()
        drawContext.canvas.clipPath(clip)
        drawRect(hex(0x393631))
        fun spool(cx: Float, d: Float) {
            drawCircle(hex(0x050505), d / 2, Offset(cx, h / 2))
            for (i in 1 until 9) drawCircle(hex(0x171717), d * i / 18, Offset(cx, h / 2), style = Stroke(1.5f))
        }
        spool(h / 2, rectH * 3.6f * (1 - 0.4f * fraction.toFloat()))
        spool(w - h / 2, rectH * 3.6f * (0.6f + 0.4f * fraction.toFloat()))
        for (i in 1..5) {
            val x = rx + rectW * i / 6f
            drawRect(Color(224 / 255f, 215 / 255f, 195 / 255f, 0.28f), Offset(x - 1, h / 2 - rectH * 0.21f), Size(2f, rectH * 0.42f))
        }
        drawContext.canvas.restore()
        drawRoundRect(hex(0x11100F), Offset(rx, ry), Size(rectW, rectH), CornerRadius(3.dp.toPx()), style = Stroke(2.dp.toPx()))
        // Bobinas
        listOf(h / 2, w - h / 2).forEach { cx -> drawReel(Offset(cx, h / 2), h * 0.78f, angle().toFloat()) }
        drawRoundRect(ring, Offset(-3.dp.toPx() / 2, -3.dp.toPx() / 2), Size(w + 3.dp.toPx(), h + 3.dp.toPx()), CornerRadius(h / 2 + 3.dp.toPx()), style = Stroke(3.dp.toPx()))
    }
}

/** Bobina del original: disco claro con 6 dientes oscuros en el borde. */
private fun DrawScope.drawReel(center: Offset, s: Float, degrees: Float) {
    rotate(degrees, center) {
        drawCircle(hex(0xFCFCFC), s / 2, center)
        for (i in 0 until 6) {
            rotate(i * 60f, center) {
                val tw = s * 0.08f
                val th = s * 0.11f
                val top = center.y - s * 0.415f - th / 2
                drawRoundRect(hex(0x1B1A18), Offset(center.x - tw / 2, top), Size(tw, th), CornerRadius(s * 0.02f))
            }
        }
        drawCircle(Tape.window, s / 2 - max(1f, s * 0.03f) / 2, center, style = Stroke(max(1f, s * 0.03f)))
    }
}

/** Casete en miniatura para el mini reproductor. */
@Composable
fun MiniCassette(isPlaying: Boolean, modifier: Modifier = Modifier) {
    val dark = Libre.colors.dark
    val clockState = rememberClockState(isPlaying)
    Canvas(modifier.aspectRatio(1f)) {
        // Se lee al dibujar: el mini reproductor no se recompone en cada fotograma.
        val angle = ((clockState.longValue / 1000.0) * Tape.ROTATION_PER_SECOND % 360).toFloat()
        val s = size.width
        drawRect(Brush.linearGradient(Tape.shell, Offset(s * 0.37f, 0f), Offset(s * 0.63f, s)))
        val cy = s / 2 - s * 0.06f
        drawRoundRect(Tape.label(dark), Offset(s * 0.08f, cy - s * 0.29f), Size(s * 0.84f, s * 0.58f), CornerRadius(s * 0.08f))
        val sy = s / 2 - s * 0.04f
        val stripeH = s * 0.13f
        val gap = max(0.5f, s * 0.02f)
        Tape.stripes(dark).forEachIndexed { i, col ->
            val each = (stripeH - 2 * gap) / 3
            drawRect(col, Offset(s * 0.08f, sy - stripeH / 2 + i * (each + gap)), Size(s * 0.84f, each))
        }
        drawRoundRect(Tape.window, Offset(s * 0.17f, sy - s * 0.14f), Size(s * 0.66f, s * 0.28f), CornerRadius(s * 0.14f))
        val reelGap = s * 0.66f - 2 * s * 0.28f
        val r = s * 0.22f
        drawReel(Offset(s / 2 - reelGap / 2 - r / 2, sy), r, angle)
        drawReel(Offset(s / 2 + reelGap / 2 + r / 2, sy), r, angle)
        val tz = trapezoid(Size(s * 0.5f, s * 0.11f))
        drawContext.canvas.save()
        drawContext.canvas.translate(s * 0.25f, s / 2 + s * 0.38f - s * 0.055f)
        drawPath(tz, hex(0x63635E, 0.45f))
        drawContext.canvas.restore()
    }
}

// MARK: Vinilo ----------------------------------------------------------------------------------

@Composable
fun VinylView(song: Song) {
    val c = Libre.colors
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val latest by androidx.compose.runtime.rememberUpdatedState(st)
    val reduce = LocalReduceMotion.current
    val haptics = rememberHaptics()
    var scratch by remember { mutableStateOf<Double?>(null) }
    var extraAngle by remember { mutableDoubleStateOf(0.0) }
    var lastTouch by remember { mutableStateOf<Double?>(null) }
    var armFraction by remember { mutableStateOf<Double?>(null) }
    var wasPlaying by remember { mutableStateOf(false) }
    var tick by remember { mutableDoubleStateOf(0.0) }
    val duration = st.duration
    val fraction = armFraction ?: (scratch ?: st.progress).let { t -> if (duration > 0) (t / duration).coerceIn(0.0, 1.0) else 0.0 }
    val clock = rememberClockState(st.isPlaying && !reduce && scratch == null)

    BoxWithConstraints(Modifier.fillMaxWidth().aspectRatio(1f), contentAlignment = Alignment.Center) {
        val sd = min(maxWidth.value, maxHeight.value).dp
        val density = LocalDensity.current
        val s = with(density) { sd.toPx() }
        val center = Offset(s * 0.44f, s * 0.52f)
        val pivot = Offset(s * 0.86f, s * 0.15f)
        val armLength = s * 0.6f
        val rOuter = s * 0.37f
        val rInner = s * 0.17f
        val theta = armAngle(center, pivot, armLength, rOuter - (rOuter - rInner) * fraction.toFloat())
        val animatedTheta by animateFloatAsState(theta.toFloat(), if (armFraction == null) tween(600) else tween(0), label = "arm")
        val lifted = !st.isPlaying || scratch != null

        Box(Modifier.size(sd)) {
            // Plinto
            Box(
                Modifier.fillMaxSize()
                    .shadow(24.dp, RoundedCornerShape(sd * 0.05f), ambientColor = Color.Black.copy(0.35f), spotColor = Color.Black.copy(0.35f))
                    .background(Brush.linearGradient(listOf(hex(0x2E2D31), hex(0x1A191C), hex(0x111012))), RoundedCornerShape(sd * 0.05f))
                    .border(1.5.dp, Brush.verticalGradient(listOf(Color.White.copy(0.18f), Color.Transparent, Color.Black.copy(0.6f))), RoundedCornerShape(sd * 0.05f)),
            )
            Canvas(Modifier.fillMaxSize()) {
                drawCircle(hex(0x0C0C0E), s * 0.43f, center)
                drawCircle(hex(0x3A393E), s * 0.43f - s * 0.004f, center, style = Stroke(s * 0.008f))
            }
            // Disco
            val recordSize = sd * 0.8f
            Box(
                Modifier
                    .offset(x = with(density) { (center.x - s * 0.4f).toDp() }, y = with(density) { (center.y - s * 0.4f).toDp() })
                    .size(recordSize)
                    .pointerInput(duration) {
                        val cx = size.width / 2f
                        val cy = size.height / 2f
                        detectDragGestures(
                            onDragStart = {
                                wasPlaying = latest.isPlaying
                                if (wasPlaying) env.player.pause()
                                scratch = latest.progress
                                lastTouch = null
                            },
                            onDrag = { ch, _ ->
                                val a = atan2((ch.position.y - cy).toDouble(), (ch.position.x - cx).toDouble())
                                lastTouch?.let { last ->
                                    val d = angleDelta(a, last)
                                    extraAngle += d * 180 / PI
                                    scratch = ((scratch ?: 0.0) + d / (2 * PI) * 4.0).coerceIn(0.0, max(duration, 0.0))
                                    tick += kotlin.math.abs(d)
                                    if (tick > PI / 6) { haptics.tick(); tick = 0.0 }
                                }
                                lastTouch = a
                            },
                            onDragEnd = {
                                scratch?.let { env.player.seekSeconds(it) }
                                scratch = null; lastTouch = null
                                if (wasPlaying) env.player.resume()
                            },
                        )
                    }
                    .semanticsButton("Disco") {},
            ) {
                Record(
                    song.thumb(600),
                    Modifier.fillMaxSize().graphicsLayer {
                        val spin = if (reduce) 0.0 else (clock.longValue / 1000.0) * 200.0
                        rotationZ = ((spin + extraAngle) % 360.0).toFloat()
                    },
                )
                // Brillo fijo: la luz no gira con el disco.
                Canvas(Modifier.fillMaxSize()) {
                    val ring = size.width * 0.11f
                    drawCircle(
                        Brush.sweepGradient(listOf(Color.Transparent, Color.White.copy(0.13f), Color.Transparent, Color.Transparent, Color.White.copy(0.09f), Color.Transparent, Color.Transparent)),
                        size.width / 2 - ring, style = Stroke(ring * 2),
                    )
                }
            }
            // Velocidad
            Column(
                Modifier.offset(x = sd * 0.07f - 10.dp, y = sd * 0.08f - 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    Modifier.size(sd * 0.022f).shadow(if (st.isPlaying) 4.dp else 0.dp, CircleShape, ambientColor = c.accent, spotColor = c.accent)
                        .background(if (st.isPlaying) c.accent else hex(0x3A393E), CircleShape),
                )
                Spacer(Modifier.height(2.dp))
                Text("33", color = hex(0x8A8990), fontSize = max(9f, sd.value * 0.03f).sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
            }
            // Brazo
            val armW = sd * 0.1f
            val armH = with(density) { (armLength + s * 0.12f).toDp() }
            val pivotFromTop = with(density) { (s * 0.12f).toDp() }
            Box(
                Modifier
                    .offset(x = with(density) { pivot.x.toDp() } - armW / 2, y = with(density) { pivot.y.toDp() } - pivotFromTop)
                    .size(armW, armH)
                    .graphicsLayer {
                        rotationZ = animatedTheta
                        transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, pivotFromTop.toPx() / armH.toPx())
                    }
                    .pointerInput(duration) {
                        detectDragGestures(
                            onDragStart = { haptics.tick() },
                            onDrag = { ch, _ ->
                                // posición del dedo en el sistema del tocadiscos
                                val local = ch.position
                                val ang = Math.toRadians(animatedTheta.toDouble())
                                val ox = local.x - size.width / 2f
                                val oy = local.y - pivotFromTop.toPx()
                                val gx = pivot.x + (ox * cos(ang) - oy * sin(ang)).toFloat()
                                val gy = pivot.y + (ox * sin(ang) + oy * cos(ang)).toFloat()
                                val a = atan2((pivot.x - gx).toDouble(), (gy - pivot.y).toDouble())
                                val nx = pivot.x - armLength * sin(a).toFloat()
                                val ny = pivot.y + armLength * cos(a).toFloat()
                                val r = hypot(nx - center.x, ny - center.y)
                                armFraction = ((rOuter - r) / (rOuter - rInner)).toDouble().coerceIn(0.0, 1.0)
                            },
                            onDragEnd = {
                                armFraction?.let { env.player.seekSeconds(it * duration) }
                                armFraction = null
                                haptics.tick()
                            },
                        )
                    },
            ) { Tonearm(sd, lifted) }
            // Controles del plinto
            Row(Modifier.offset(x = sd * 0.84f - 44.dp, y = sd * 0.9f - 22.dp), horizontalArrangement = Arrangement.spacedBy(sd * 0.03f)) {
                DeckKey(Icons.Rounded.FastRewind, sd * 0.1f, "Anterior") { env.player.previous() }
                DeckKey(Icons.Rounded.FastForward, sd * 0.1f, "Siguiente") { env.player.next() }
            }
            Box(
                Modifier.offset(x = sd * 0.13f - max(56f, sd.value * 0.17f).dp / 2, y = sd * 0.9f - max(44f, sd.value * 0.1f).dp / 2)
                    .size(max(56f, sd.value * 0.17f).dp, max(44f, sd.value * 0.1f).dp)
                    .shadow(3.dp, RoundedCornerShape(6.dp), ambientColor = Color.Black.copy(0.4f), spotColor = Color.Black.copy(0.4f))
                    .background(hex(0x3B3A3F), RoundedCornerShape(6.dp))
                    .border(1.dp, Color.White.copy(0.15f), RoundedCornerShape(6.dp))
                    .tactile(label = if (st.isPlaying) "Pausa" else "Reproducir") { env.player.togglePlay() },
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(if (st.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = hex(0xE8E6E1), modifier = Modifier.size(max(18f, sd.value * 0.056f).dp))
                    Text("START·STOP", color = hex(0xE8E6E1), fontSize = max(7f, sd.value * 0.02f).sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                }
            }
        }
    }
}

/** Ángulo del brazo (0° = reposo) para que la aguja caiga a [radius] del centro (búsqueda binaria). */
private fun armAngle(center: Offset, pivot: Offset, length: Float, radius: Float): Double {
    fun needle(deg: Double): Double {
        val a = Math.toRadians(deg)
        val nx = pivot.x - length * sin(a)
        val ny = pivot.y + length * cos(a)
        return hypot(nx - center.x, ny - center.y)
    }
    val closest = Math.toDegrees(atan2((pivot.x - center.x).toDouble(), (center.y - pivot.y).toDouble()))
    var lo = 0.0
    var hi = closest
    repeat(24) {
        val mid = (lo + hi) / 2
        if (needle(mid) > radius) lo = mid else hi = mid
    }
    return (lo + hi) / 2
}

/** Disco: surcos, pistas y la carátula como galleta central. */
@Composable
private fun Record(art: String?, modifier: Modifier) {
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val d = maxWidth
        Canvas(Modifier.fillMaxSize()) {
            val cc = Offset(size.width / 2, size.height / 2)
            drawCircle(hex(0x0A0A0B), size.width / 2, cc)
            var r = size.width * 0.21f
            var i = 0
            val step = 1.4f * density
            while (r < size.width * 0.49f) {
                if (i % 37 == 36) drawCircle(Color.Black, r, cc, style = Stroke(1.6f * density))
                else drawCircle(Color.White.copy(0.045f), r, cc, style = Stroke(0.6f * density))
                r += step
                i++
            }
        }
        CoverImage(art, Modifier.size(d * 0.36f).clip(CircleShape).border(1.dp, Color.Black.copy(0.35f), CircleShape))
        Box(Modifier.size(d * 0.028f).background(hex(0xD5D3CE), CircleShape))
    }
}

/** Brazo: contrapeso, tubo, pivote y cápsula con aguja. */
@Composable
private fun Tonearm(size: androidx.compose.ui.unit.Dp, lifted: Boolean) {
    val lift by animateFloatAsState(if (lifted) 1f else 0f, tween(300), label = "lift")
    Canvas(Modifier.fillMaxSize().graphicsLayer { scaleX = 1 + 0.03f * lift; scaleY = 1 + 0.03f * lift }) {
        val w = this.size.width
        val h = this.size.height
        val top = size.toPx() * 0.12f
        drawRoundRect(
            Brush.horizontalGradient(listOf(hex(0x6E6D72), hex(0x2C2B2F))),
            Offset(w * 0.19f, top * 0.05f), Size(w * 0.62f, top * 0.55f), CornerRadius(w * 0.15f),
        )
        val tubeW = max(3f * density, w * 0.16f)
        drawRoundRect(
            Brush.horizontalGradient(listOf(hex(0xE4E3DF), hex(0x8F8E93))),
            Offset(w / 2 - tubeW / 2, top * 0.4f), Size(tubeW, h - top * 0.5f), CornerRadius(tubeW / 2),
        )
        drawCircle(Brush.radialGradient(listOf(hex(0x8D8C91), hex(0x2A292D)), Offset(w * 0.3f, top - w * 0.3f), w * 0.5f), w * 0.4f, Offset(w / 2, top))
        val capW = w * 0.42f
        val capH = size.toPx() * 0.07f
        rotate(-18f, Offset(w / 2 - w * 0.08f, h - capH / 2)) {
            drawRoundRect(hex(0x1E1D21), Offset(w / 2 - w * 0.08f - capW / 2, h - capH), Size(capW, capH), CornerRadius(2.dp.toPx()))
            drawRoundRect(Color.White.copy(0.25f), Offset(w / 2 - w * 0.08f - capW / 2, h - capH), Size(capW, capH), CornerRadius(2.dp.toPx()), style = Stroke(0.8f * density))
        }
    }
}

@Composable
private fun DeckKey(icon: androidx.compose.ui.graphics.vector.ImageVector, size: androidx.compose.ui.unit.Dp, label: String, onClick: () -> Unit) {
    Box(Modifier.size(44.dp).tactile(label = label, onClick = onClick), contentAlignment = Alignment.Center) {
        val k = max(36f, size.value).dp
        Box(
            Modifier.size(k).shadow(3.dp, CircleShape, ambientColor = Color.Black.copy(0.4f), spotColor = Color.Black.copy(0.4f))
                .background(hex(0x3B3A3F), CircleShape).border(1.dp, Color.White.copy(0.15f), CircleShape),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, tint = hex(0xE8E6E1), modifier = Modifier.size(max(15f, size.value * 0.45f).dp)) }
    }
}

/** Vinilo en miniatura para el mini reproductor. */
@Composable
fun MiniVinyl(isPlaying: Boolean, art: String?, modifier: Modifier = Modifier) {
    val clock = rememberClockState(isPlaying)
    Box(modifier.aspectRatio(1f).background(hex(0x16151A)), contentAlignment = Alignment.Center) {
        Record(art, Modifier.padding(2.dp).fillMaxSize().graphicsLayer { rotationZ = ((clock.longValue / 1000.0) * 200 % 360).toFloat() })
    }
}
