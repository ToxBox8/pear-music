package app.libremusic.ui.theme

import androidx.compose.foundation.layout.requiredSize
import android.graphics.Bitmap
import android.os.Build
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.libremusic.data.Song
import coil.compose.AsyncImage
import coil.imageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import coil.size.Scale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin

/** «Reducir movimiento» del sistema (animaciones desactivadas): pausa los fondos y efectos. */
val LocalReduceMotion = androidx.compose.runtime.staticCompositionLocalOf { false }

/** Falso en las pestañas que no se ven: sus fondos se paran (en iOS se pausan con onDisappear). */
val LocalScreenVisible = androidx.compose.runtime.compositionLocalOf { true }

// MARK: Paleta de la carátula ---------------------------------------------------------------------

/** Colores dominantes de la canción actual; los fondos de todos los temas los usan (ThemeEngine en iOS). */
object ThemeEngine {
    private val _palette = MutableStateFlow(Tokens.ArtworkFallback)
    val palette: StateFlow<List<Color>> = _palette.asStateFlow()
    /** Hay una canción cargada (para «Colores de la carátula»). */
    private val _active = MutableStateFlow(false)
    val active: StateFlow<Boolean> = _active.asStateFlow()
    private var songId: String? = null
    /** Colores ya calculados por carátula: cada portada se analiza una sola vez. */
    private val cache = object : LinkedHashMap<String, List<Color>>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<Color>>?) = size > 200
    }

    suspend fun update(context: android.content.Context, song: Song?) {
        _active.value = song != null
        if (song == null || song.id == songId) return
        songId = song.id
        cache[song.id]?.let { _palette.value = it; return }
        val url = song.thumb(120) ?: return
        val result = context.imageLoader.execute(
            ImageRequest.Builder(context).data(url).size(16).scale(Scale.FILL).allowHardware(false).build(),
        )
        if (song.id != songId) return
        val bmp = (result as? SuccessResult)?.drawable?.let { (it as? android.graphics.drawable.BitmapDrawable)?.bitmap }
        _palette.value = (bmp?.let(PaletteExtractor::colors) ?: Tokens.ArtworkFallback).also { cache[song.id] = it }
    }
}

/** Mismo algoritmo que PaletteExtractor en iOS: 16×16, 12 grupos por tono, los 3 más presentes, avivados. */
object PaletteExtractor {
    fun colors(src: Bitmap): List<Color>? {
        val bmp = Bitmap.createScaledBitmap(src, 16, 16, true)
        val sums = Array(12) { DoubleArray(4) }
        val hsv = FloatArray(3)
        for (y in 0 until 16) for (x in 0 until 16) {
            val p = bmp.getPixel(x, y)
            val r = android.graphics.Color.red(p) / 255.0
            val g = android.graphics.Color.green(p) / 255.0
            val b = android.graphics.Color.blue(p) / 255.0
            android.graphics.Color.colorToHSV(p, hsv)
            val weight = hsv[1] * hsv[2] + 0.01
            val k = minOf(11, (hsv[0] / 360f * 12).toInt())
            sums[k][0] += r * weight; sums[k][1] += g * weight; sums[k][2] += b * weight; sums[k][3] += weight
        }
        val top = sums.filter { it[3] > 0.6 }.sortedByDescending { it[3] }.take(3)
        if (top.isEmpty()) return null // carátula en blanco y negro
        val out = top.map { s ->
            val rgb = android.graphics.Color.rgb(
                (s[0] / s[3] * 255).toInt(), (s[1] / s[3] * 255).toInt(), (s[2] / s[3] * 255).toInt(),
            )
            android.graphics.Color.colorToHSV(rgb, hsv)
            hsv[1] = max(hsv[1], 0.55f)
            hsv[2] = max(hsv[2], 0.8f)
            Color(android.graphics.Color.HSVToColor(hsv))
        }.toMutableList()
        while (out.size < 3) out += Tokens.ArtworkFallback[out.size]
        return out
    }
}

/** Paleta animada (1,2 s, como en iOS). */
@Composable
fun rememberPalette(): List<Color> {
    val p by ThemeEngine.palette.collectAsState()
    val a by animateColorAsState(p[0], tween(1200), label = "p0")
    val b by animateColorAsState(p[1], tween(1200), label = "p1")
    val c by animateColorAsState(p[2], tween(1200), label = "p2")
    return listOf(a, b, c)
}

// MARK: Superficie de tarjetas ------------------------------------------------------------------

/** Fondo de tarjetas, filas y barras según el tema (ThemeSurface en iOS). */
fun Modifier.themeSurface(radius: Dp, colors: LibreColors, theme: AppTheme = colors.theme): Modifier {
    val r = minOf(radius.value, theme.maxRadius).dp
    val shape = RoundedCornerShape(r)
    return when (theme) {
        AppTheme.Air -> this
            .shadow(6.dp, shape, ambientColor = Color(0x143A4048), spotColor = Color(0x143A4048))
            .background(Brush.verticalGradient(listOf(Color(0xFFFBFBFC), Color(0xFFECEEF1))), shape)
            .border(1.dp, Color.White.copy(alpha = 0.9f), shape)
        AppTheme.Glass -> this
            .background(material(colors.dark), shape)
            .border(
                1.dp,
                Brush.linearGradient(listOf(Color.White.copy(0.5f), Color.White.copy(0.06f), Color.White.copy(0.22f))),
                shape,
            )
        AppTheme.Neon -> this
            .shadow(9.dp, shape, ambientColor = theme.accent.copy(0.55f), spotColor = theme.accent.copy(0.55f))
            .background(Color(0xCC0B0814), shape)
            .border(1.2.dp, theme.accent.copy(alpha = 0.9f), shape)
        AppTheme.Plain -> this.background(colors.secondaryGrouped, shape)
    }
}

/**
 * Equivalente a `.ultraThinMaterial`: en iOS es un desenfoque del fondo con un velo. Encima de los
 * fondos de LibreMusic (que ya son difusos) un velo translúcido se ve igual.
 */
fun material(dark: Boolean, thick: Boolean = false): Color = when {
    thick -> if (dark) Color(0xFF1C1C1E).copy(alpha = 0.86f) else Color(0xFFFFFFFF).copy(alpha = 0.88f)
    // .ultraThinMaterial medido en las capturas de iOS: sobre blanco queda (242,243,244) y sobre negro (33,33,35).
    dark -> Color(0xFF29292C).copy(alpha = 0.8f)
    else -> Color(0xFFE6E7EA).copy(alpha = 0.5f)
}

// MARK: Fondos animados -------------------------------------------------------------------------

private fun fract(x: Double) = x - floor(x)
/** Pseudoaleatorio estable (los mismos números que en iOS). */
private fun hash(n: Double) = fract(sin(n * 12.9898) * 43758.5453)

/** Fase acumulada a la velocidad indicada: cambiar de play a pausa no da saltos. */
@Composable
private fun rememberPhase(speed: Double, paused: Boolean): Double {
    val phase = remember { doubleArrayOf(0.0) }
    val tick = remember { mutableLongStateOf(0L) }
    LaunchedEffect(paused, speed) {
        if (paused) return@LaunchedEffect
        var last = 0L
        while (true) {
            withFrameNanos { now ->
                if (last != 0L) phase[0] += minOf((now - last) / 1e9, 0.1) * speed
                last = now
                tick.longValue = now
            }
        }
    }
    // Leer el reloj hace que quien llama se redibuje en cada fotograma.
    return if (tick.longValue >= 0) phase[0] else 0.0
}

/**
 * La carátula enorme y desenfocada con un velo del color de fondo, como en Descubrir: fondo del
 * reproductor con «Colores de la carátula». Gira muy despacio mientras suena.
 */
@Composable
fun ArtworkBackdrop(url: String?, playing: Boolean) {
    val colors = Libre.colors
    val clock = app.libremusic.ui.rememberClockState(playing && !LocalReduceMotion.current)
    BoxWithConstraints(Modifier.fillMaxSize().background(colors.background).clipToBounds(), contentAlignment = androidx.compose.ui.Alignment.Center) {
        val side = max(maxWidth.value, maxHeight.value).dp * 1.6f
        if (url != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            AsyncImage(
                model = url, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier
                    .requiredSize(side)
                    .graphicsLayer { rotationZ = ((clock.longValue / 1000.0) * 4 % 360).toFloat() }
                    .blur(70.dp, BlurredEdgeTreatment.Unbounded),
            )
        }
        // Velo: el texto del reproductor se sigue leyendo en claro y en oscuro.
        Box(Modifier.fillMaxSize().background(colors.background.copy(alpha = if (colors.dark) 0.42f else 0.5f)))
    }
}

/** Fondo del tema activo detrás de cada pantalla. */
@Composable
fun ThemeBackdrop(playing: Boolean, song: Song?, modifier: Modifier = Modifier, theme: AppTheme? = null, paused: Boolean = false, grouped: Boolean = false) {
    val colors = Libre.colors
    val t = theme ?: colors.theme
    val palette = rememberPalette()
    val reduce = LocalReduceMotion.current || !LocalScreenVisible.current
    Box(modifier.fillMaxSize()) {
        when (t) {
            AppTheme.Glass -> GlassBackdrop(palette, song?.thumb(300), colors.dark, animate = !paused && !reduce)
            AppTheme.Air -> AirPaper(colors.dark, animate = !paused && !reduce)
            AppTheme.Neon -> NeonBackdrop(palette, playing, paused = paused || reduce)
            // Sistema no tiene fondo propio: el de la pantalla (blanco o negro), como el ScrollView de iOS.
            // Los formularios (Ajustes, Importar) piden el gris agrupado con `grouped = true`.
            AppTheme.Plain -> Box(Modifier.fillMaxSize().background(if (grouped) colors.grouped else colors.background))
        }
    }
}

@Composable
fun GlassBackdrop(palette: List<Color>, art: String?, dark: Boolean, animate: Boolean) {
    val drift by if (animate) {
        rememberInfiniteTransition(label = "drift").animateFloat(
            0f, 1f, infiniteRepeatable(tween(14_000, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "d",
        )
    } else {
        remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
    }
    val bg = if (dark) Color.Black else Color.White
    BoxWithConstraints(Modifier.fillMaxSize().background(bg)) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        val density = LocalDensity.current.density
        // Círculos difusos: degradado radial (se ve como un círculo con blur 70 y funciona en cualquier Android).
        Canvas(Modifier.fillMaxSize()) {
            val cx = w / 2
            val cy = h / 2
            fun blob(color: Color, alpha: Float, radiusPt: Float, x0: Float, x1: Float, y0: Float, y1: Float) {
                val r = (radiusPt / 2 + 70) * density
                val c = Offset(cx + (x0 + (x1 - x0) * drift) * density, cy + (y0 + (y1 - y0) * drift) * density)
                drawCircle(
                    Brush.radialGradient(
                        0f to color.copy(alpha = alpha), 0.45f to color.copy(alpha = alpha * 0.8f), 1f to color.copy(alpha = 0f),
                        center = c, radius = r,
                    ),
                    radius = r, center = c,
                )
            }
            blob(palette[0], 0.6f, 340f, -60f, -130f, -190f, -260f)
            blob(palette[1], 0.5f, 300f, 90f, 150f, 130f, 30f)
            blob(palette[2], 0.42f, 260f, 50f, -90f, 250f, 330f)
        }
        if (art != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            AsyncImage(
                model = art, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier
                    .align(androidx.compose.ui.Alignment.Center)
                    .graphicsLayer {
                        translationX = (-20f + 60f * drift) * density
                        translationY = (20f - 60f * drift) * density
                        alpha = 0.5f
                        // Sin búfer intermedio: con alpha < 1 Android dibujaba la capa en un búfer del
                        // tamaño de la imagen y recortaba el desenfoque en un cuadrado de bordes duros.
                        compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.ModulateAlpha
                    }
                    // Unbounded: el desenfoque se difumina fuera de la caja, como `.blur` en SwiftUI.
                    // Con el recorte por defecto se veía un cuadrado de bordes duros (blanco con
                    // carátulas claras) en el tema Cristal.
                    .blur(70.dp, BlurredEdgeTreatment.Unbounded)
                    .size(320.dp),
            )
        }
        Box(Modifier.fillMaxSize().background(bg.copy(alpha = if (dark) 0.3f else 0.2f)))
    }
}

/** Papel de Air OS: plata cepillada con cintas blancas que se desplazan despacio. */
@Composable
fun AirPaper(dark: Boolean, animate: Boolean = true, modifier: Modifier = Modifier) {
    val drift by if (animate) {
        rememberInfiniteTransition(label = "air").animateFloat(
            0f, 1f, infiniteRepeatable(tween(16_000, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "a",
        )
    } else {
        remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
    }
    val paper = if (dark) listOf(Color(0xFF1A1B1D), Color(0xFF0E0E10)) else listOf(Color(0xFFF1F2F4), Color(0xFFE2E4E8), Color(0xFFD4D7DC))
    val ribbon = if (dark) Color.White.copy(alpha = 0.05f) else Color.White.copy(alpha = 0.85f)
    // Como iOS: cintas sólidas con un desenfoque fijo de 40 pt (en una miniatura casi desaparecen). Sin
    // RenderEffect (Android < 12) se imitan con degradados.
    val realBlur = android.os.Build.VERSION.SDK_INT >= 31
    Box(modifier.fillMaxSize().background(Brush.verticalGradient(paper)).clipToBounds()) {
    Canvas(Modifier.fillMaxSize().then(if (realBlur) Modifier.blur(40.dp, BlurredEdgeTreatment.Unbounded) else Modifier)) {
        val w = size.width
        val h = size.height
        fun band(angle: Float, width: Float, height: Float, dx: Float, dy: Float) {
            rotateBand(angle, Offset(w / 2 + dx, h / 2 + dy)) {
                drawRoundRect(
                    if (realBlur) androidx.compose.ui.graphics.SolidColor(ribbon) else Brush.verticalGradient(
                        listOf(ribbon.copy(alpha = 0f), ribbon, ribbon.copy(alpha = 0f)),
                        startY = h / 2 + dy - height / 2, endY = h / 2 + dy + height / 2,
                    ),
                    topLeft = Offset(w / 2 + dx - width / 2, h / 2 + dy - height / 2),
                    size = Size(width, height),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(height / 2),
                )
            }
        }
        band(-28f, w * 1.6f, h * 0.22f, w * 0.06f + (-w * 0.08f - w * 0.06f) * drift, -h * 0.18f)
        band(24f, w * 1.4f, h * 0.16f, -w * 0.04f + (w * 0.1f + w * 0.04f) * drift, h * 0.26f)
        // brillo metálico en diagonal
        val sx = -w * 0.3f + w * 0.6f * drift
        rotateBand(22f, Offset(w / 2 + sx, h / 2)) {
            drawRect(
                Brush.horizontalGradient(
                    listOf(Color.Transparent, Color.White.copy(alpha = if (dark) 0.04f else 0.5f), Color.Transparent),
                    startX = w / 2 + sx - w * 0.175f, endX = w / 2 + sx + w * 0.175f,
                ),
                topLeft = Offset(w / 2 + sx - w * 0.175f, -h * 0.3f),
                size = Size(w * 0.35f, h * 1.6f),
            )
        }
    }
    }
}

private inline fun androidx.compose.ui.graphics.drawscope.DrawScope.rotateBand(
    degrees: Float, pivot: Offset, block: androidx.compose.ui.graphics.drawscope.DrawScope.() -> Unit,
) {
    drawContext.transform.rotate(degrees, pivot)
    block()
    drawContext.transform.rotate(-degrees, pivot)
}

/** Rejilla synthwave que avanza mientras suena (mismo dibujo que NeonBackdrop en iOS). */
@Composable
fun NeonBackdrop(palette: List<Color>, playing: Boolean, paused: Boolean) {
    val t = rememberPhase(if (playing) 1.0 else 0.2, paused)
    Canvas(Modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height
        val horizon = h * 0.44f
        drawRect(Color(0xFF05030C))
        drawRect(
            Brush.radialGradient(
                listOf(palette[0].copy(alpha = if (playing) 0.45f else 0.3f), Color.Transparent),
                center = Offset(w / 2, horizon), radius = w * 0.8f,
            ),
        )
        for (i in 0 until 60) {
            val n = i.toDouble()
            val x = (hash(n) * w).toFloat()
            val y = (hash(n + 9) * horizon * 0.95).toFloat()
            val r = (0.5 + hash(n + 4) * (0.8 + 0.5 * sin(t * 2 + n))).toFloat() * density / 2
            drawCircle(Color.White.copy(alpha = 0.7f), r, Offset(x + r, y + r))
        }
        val horizontal = Path()
        val vertical = Path()
        for (k in 0 until 16) {
            val z = fract((k + t * 0.8) / 16)
            val y = horizon + (h - horizon) * z.pow(2.3).toFloat()
            horizontal.moveTo(0f, y); horizontal.lineTo(w, y)
        }
        for (i in -14..14) {
            val x0 = w / 2 + i * w * 0.018f
            val x1 = w / 2 + i * w * 0.32f
            vertical.moveTo(x0, horizon); vertical.lineTo(x1, h)
        }
        for ((path, color) in listOf(horizontal to palette[1], vertical to palette[0])) {
            drawPath(path, color.copy(alpha = 0.22f), style = Stroke(5f * density))
            drawPath(path, color.copy(alpha = 0.95f), style = Stroke(1.2f * density))
        }
        drawRect(palette[0], topLeft = Offset(0f, horizon - density), size = Size(w, 2 * density))
    }
}

/** Fotograma fijo de un tema para la galería de Ajustes. */
@Composable
fun BackdropPreview(theme: AppTheme, modifier: Modifier = Modifier) {
    val c = Libre.colors
    val dark = theme.forcedDark ?: c.dark
    val palette = rememberPalette()
    Box(modifier) {
        when (theme) {
            AppTheme.Glass -> GlassBackdrop(palette, null, dark, animate = false)
            AppTheme.Air -> AirPaper(dark, animate = false)
            AppTheme.Neon -> NeonBackdrop(palette, playing = false, paused = true)
            AppTheme.Plain -> Box(Modifier.fillMaxSize().background(if (dark) Tokens.SysDark.GroupedBackground else Tokens.SysLight.GroupedBackground))
        }
    }
}
