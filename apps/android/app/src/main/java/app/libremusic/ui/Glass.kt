package app.libremusic.ui

import android.graphics.BlurMaskFilter
import android.graphics.ColorMatrix
import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.shape.CornerBasedShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.addOutline
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import app.libremusic.ui.theme.LocalReduceMotion
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min

// Cristal líquido de iOS 26 para Android (opcional: Ajustes › Apariencia › Cristal líquido).
//
// Lo que hay detrás (las pantallas) se graba en una capa ([glassSource]). Cada pieza de cristal
// ([liquidGlass]) dibuja su trozo de esa capa con tres efectos encadenados, como el material de
// Apple: desenfoque suave, más saturación (vibrancia) y refracción en los bordes con un shader
// AGSL (el borde «dobla» lo que hay detrás hacia dentro, con un poco de dispersión de color).
// Encima va el brillo del borde, la sombra exterior y el reflejo del dedo al pulsar.
//
// Refracción: Android 13+ (RuntimeShader). Desenfoque: Android 12+. En versiones anteriores se
// usa el velo translúcido de siempre.

/** La capa con lo que hay detrás del cristal y dónde está en la pantalla. */
@Stable
class GlassSource internal constructor(internal val layer: GraphicsLayer) {
    internal var origin by mutableStateOf(Offset.Zero)
}

/** null = cristal líquido desactivado (o Android < 12): cada pieza usa su aspecto normal. */
val LocalGlass = staticCompositionLocalOf<GlassSource?> { null }

/**
 * true dentro de lo que se graba: ahí el cristal no puede refractar la capa (se estaría
 * dibujando a sí mismo) y sólo pinta velo, brillo y sombra. Los Popup lo devuelven a false.
 */
val LocalInsideGlassSource = staticCompositionLocalOf { false }

val glassSupported: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

@Composable
fun rememberGlassSource(): GlassSource {
    val layer = rememberGraphicsLayer()
    return remember(layer) { GlassSource(layer) }
}

/** Graba el contenido en la capa de [source] y lo dibuja tal cual. */
fun Modifier.glassSource(source: GlassSource): Modifier = this
    .onGloballyPositioned { source.origin = it.positionOnScreen() }
    .drawWithContent {
        source.layer.record { this@drawWithContent.drawContent() }
        drawLayer(source.layer)
    }

/** Aspecto de cada tipo de cristal (medido a ojo contra iOS 26.1). */
@Stable
data class GlassStyle(
    val blur: Dp,
    val refraction: Dp,
    val depth: Dp,
    val saturation: Float = 1.6f,
    val lightTint: Color = Color.White.copy(alpha = 0.16f),
    val darkTint: Color = Color(0xFF16161A).copy(alpha = 0.32f),
    val dispersion: Float = 0.6f,
    val shadow: Dp = 14.dp,
) {
    companion object {
        /** Barra de pestañas y mini reproductor: transparente, con mucha refracción. */
        val Bar = GlassStyle(
            blur = 7.dp, refraction = 18.dp, depth = 22.dp,
            lightTint = Color.White.copy(alpha = 0.34f), darkTint = Color(0xFF16161A).copy(alpha = 0.42f),
        )
        /** Botones redondos de la barra superior. */
        val Button = GlassStyle(blur = 2.dp, refraction = 12.dp, depth = 14.dp, shadow = 10.dp)
        /** Menús y avisos: más esmerilado para que el texto se lea. */
        val Menu = GlassStyle(
            blur = 22.dp, refraction = 14.dp, depth = 18.dp, saturation = 1.8f,
            lightTint = Color.White.copy(alpha = 0.55f), darkTint = Color(0xFF1C1C1E).copy(alpha = 0.6f), shadow = 24.dp,
        )
        /** La gota de la pestaña elegida: casi sin desenfoque, lupa y borde muy brillante. */
        val Drop = GlassStyle(
            blur = 0.dp, refraction = 12.dp, depth = 9.dp, saturation = 1.2f,
            lightTint = Color.White.copy(alpha = 0.10f), darkTint = Color.White.copy(alpha = 0.06f), dispersion = 1f, shadow = 12.dp,
        )
    }
}

/** Reflejo del dedo al pulsar un cristal interactivo (`.glassEffect(.regular.interactive())`). */
@Stable
class GlassPress {
    /** 0 suelto · 1 pulsado (con rebote). */
    internal val amount = Animatable(0f)
    internal var touch by mutableStateOf(Offset.Unspecified)
}

// MARK: Shader de refracción --------------------------------------------------------------------

private const val LENS_AGSL = """
uniform shader content;
uniform float2 size;
uniform float radius;
uniform float band;
uniform float depth;
uniform float dispersion;
uniform float zoom;

float sdRoundRect(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + float2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

half4 main(float2 xy) {
    float2 hs = size * 0.5;
    float2 p = xy - hs;
    float r = min(radius, min(hs.x, hs.y));
    float2 src = hs + p / zoom;
    float inner = -sdRoundRect(p, hs, r);
    if (inner >= band || inner < -1.0) return content.eval(src);

    float e = 0.5;
    float2 g = float2(
        sdRoundRect(p + float2(e, 0.0), hs, r) - sdRoundRect(p - float2(e, 0.0), hs, r),
        sdRoundRect(p + float2(0.0, e), hs, r) - sdRoundRect(p - float2(0.0, e), hs, r));
    float2 n = g / max(length(g), 0.0001);
    // Perfil de cristal abombado: casi plano dentro, cada vez más inclinado hacia el borde.
    float t = clamp(1.0 - inner / band, 0.0, 1.0);
    float k = 1.0 - sqrt(max(0.0, 1.0 - t * t));
    float2 d = -n * k * depth;
    if (dispersion <= 0.0) return content.eval(src + d);
    half4 cr = content.eval(src + d * (1.0 + 0.12 * dispersion));
    half4 cg = content.eval(src + d);
    half4 cb = content.eval(src + d * (1.0 - 0.12 * dispersion));
    return half4(cr.r, cg.g, cb.b, cg.a);
}
"""

@RequiresApi(Build.VERSION_CODES.S)
private fun glassEffect(
    shader: RuntimeShader?,
    size: Size,
    radius: Float,
    blurPx: Float,
    style: GlassStyle,
    density: Float,
    zoom: Float,
): android.graphics.RenderEffect {
    val sat = ColorMatrix().apply { setSaturation(style.saturation) }
    val vibrant = if (blurPx > 0.5f) {
        android.graphics.RenderEffect.createColorFilterEffect(
            android.graphics.ColorMatrixColorFilter(sat),
            android.graphics.RenderEffect.createBlurEffect(blurPx, blurPx, android.graphics.Shader.TileMode.CLAMP),
        )
    } else {
        android.graphics.RenderEffect.createColorFilterEffect(android.graphics.ColorMatrixColorFilter(sat))
    }
    if (shader == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return vibrant
    shader.setFloatUniform("size", size.width, size.height)
    shader.setFloatUniform("radius", radius)
    shader.setFloatUniform("band", style.refraction.value * density)
    shader.setFloatUniform("depth", style.depth.value * density)
    shader.setFloatUniform("dispersion", style.dispersion)
    shader.setFloatUniform("zoom", zoom)
    return android.graphics.RenderEffect.createChainEffect(
        android.graphics.RenderEffect.createRuntimeShaderEffect(shader, "content"),
        vibrant,
    )
}

@Composable
internal fun rememberLensShader(): RuntimeShader? = remember {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) RuntimeShader(LENS_AGSL) else null
}

private fun CornerBasedShape.radiusPx(size: Size, scope: DrawScope): Float =
    min(topStart.toPx(size, scope), size.minDimension / 2)

// MARK: Cristal ---------------------------------------------------------------------------------

/**
 * Fondo de cristal líquido con la forma [shape]. Sin [LocalGlass] dibuja [fallback] (el aspecto
 * de siempre). [press]: reflejo del dedo y brillo al pulsar.
 */
fun Modifier.liquidGlass(
    shape: CornerBasedShape,
    dark: Boolean,
    style: GlassStyle = GlassStyle.Bar,
    tint: Color = Color.Unspecified,
    press: GlassPress? = null,
    fallback: Color? = null,
): Modifier = composed {
    val source = LocalGlass.current
    if (source == null || !glassSupported) {
        return@composed if (fallback != null) drawBehind { drawOutline(shape.createOutline(size, layoutDirection, this), fallback) } else Modifier
    }
    if (LocalInsideGlassSource.current) {
        return@composed drawBehind {
            val outline = shape.createOutline(size, layoutDirection, this)
            drawGlassShadow(outline, style.shadow.toPx(), dark)
            fallback?.let { drawOutline(outline, it) }
            drawGlassSurface(outline, size, dark, style, tint, press)
        }
    }
    val layer = rememberGraphicsLayer()
    val shader = rememberLensShader()
    var origin by remember { mutableStateOf(Offset.Zero) }
    this
        .onGloballyPositioned { origin = it.positionOnScreen() }
        .drawBehind {
            val outline = shape.createOutline(size, layoutDirection, this)
            val radius = shape.radiusPx(size, this)
            drawGlassShadow(outline, style.shadow.toPx(), dark)
            drawBackdrop(layer, source, origin - source.origin, size, radius, style, shader, zoom = 1f)
            drawGlassSurface(outline, size, dark, style, tint, press)
        }
}

/** Sombras ya desenfocadas, por tamaño: desenfocar en cada fotograma costaba milisegundos. */
private val shadowCache = object : android.util.LruCache<String, android.graphics.Bitmap>(24) {}

/** Sombra suave sólo por fuera (el cristal es translúcido: una sombra debajo lo ensuciaría). */
private fun DrawScope.drawGlassShadow(outline: Outline, blur: Float, dark: Boolean) {
    if (blur < 1f || size.width < 1f || size.height < 1f) return
    val b = blur.toInt().toFloat()
    val pad = (b * 2).toInt()
    val key = "${size.width.toInt()}x${size.height.toInt()}|${b.toInt()}|$dark|${outline.hashCode()}"
    val bitmap = shadowCache.get(key) ?: android.graphics.Bitmap.createBitmap(
        size.width.toInt() + pad * 2, size.height.toInt() + pad * 2, android.graphics.Bitmap.Config.ALPHA_8,
    ).also { bmp ->
        val c = android.graphics.Canvas(bmp)
        c.translate(pad.toFloat(), pad.toFloat())
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.BLACK
            maskFilter = BlurMaskFilter(b, BlurMaskFilter.Blur.NORMAL)
        }
        c.drawPath(Path().apply { addOutline(outline) }.asAndroidPath(), paint)
        shadowCache.put(key, bmp)
    }
    val path = Path().apply { addOutline(outline) }
    clipPath(path, ClipOp.Difference) {
        drawIntoCanvas { canvas ->
            val paint = android.graphics.Paint().apply { color = Color.Black.copy(alpha = if (dark) 0.35f else 0.14f).toArgb() }
            canvas.nativeCanvas.drawBitmap(bitmap, -pad.toFloat(), -pad + b * 0.25f, paint)
        }
    }
}

/** Efecto ya creado de cada capa: crearlo en cada fotograma obligaba a redibujarla entera. */
private val effectCache = java.util.WeakHashMap<GraphicsLayer, Pair<String, androidx.compose.ui.graphics.RenderEffect>>()

/** El trozo de lo que hay detrás, con desenfoque, vibrancia y refracción, recortado a la forma. */
private fun DrawScope.drawBackdrop(
    layer: GraphicsLayer,
    source: GlassSource,
    offset: Offset,
    size: Size,
    radius: Float,
    style: GlassStyle,
    shader: RuntimeShader?,
    zoom: Float,
    extra: (DrawScope.() -> Unit)? = null,
    topLeft: Offset = Offset.Zero,
) {
    if (size.width < 1f || size.height < 1f || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    layer.record(IntSize(size.width.toInt(), size.height.toInt())) {
        translate(-offset.x - topLeft.x, -offset.y - topLeft.y) { drawLayer(source.layer) }
        extra?.invoke(this)
    }
    val key = "${size.width.toInt()}x${size.height.toInt()}|$radius|${style.hashCode()}|${(zoom * 100).toInt()}"
    val cached = effectCache[layer]
    if (cached?.first != key) {
        val effect = glassEffect(shader, size, radius, style.blur.toPx(), style, density, zoom).asComposeRenderEffect()
        effectCache[layer] = key to effect
        layer.renderEffect = effect
    }
    layer.setRoundRectOutline(Offset.Zero, size, radius)
    layer.clip = true
    layer.topLeft = androidx.compose.ui.unit.IntOffset(topLeft.x.toInt(), topLeft.y.toInt())
    drawLayer(layer)
}

/** Velo, brillo del borde (luz arriba a la izquierda) y reflejo del dedo. */
private fun DrawScope.drawGlassSurface(
    outline: Outline,
    size: Size,
    dark: Boolean,
    style: GlassStyle,
    tint: Color,
    press: GlassPress?,
    topLeft: Offset = Offset.Zero,
) {
    translate(topLeft.x, topLeft.y) {
        drawOutline(outline, if (dark) style.darkTint else style.lightTint)
        if (tint != Color.Unspecified) drawOutline(outline, tint)
        val p = press?.amount?.value ?: 0f
        val path = Path().apply { addOutline(outline) }
        if (p > 0.01f) {
            clipPath(path) {
                val at = press!!.touch.takeIf { it != Offset.Unspecified } ?: Offset(size.width / 2, size.height / 2)
                drawCircle(
                    Brush.radialGradient(
                        listOf(Color.White.copy(alpha = (if (dark) 0.22f else 0.38f) * p), Color.Transparent),
                        center = at, radius = max(size.minDimension * 1.2f, 1f),
                    ),
                    radius = max(size.minDimension * 1.2f, 1f), center = at,
                )
            }
        }
        // Brillo especular del borde: fuerte arriba a la izquierda y abajo a la derecha.
        val w = 1.1.dp.toPx()
        val hi = if (dark) 0.55f else 0.9f
        drawOutline(
            outline,
            Brush.linearGradient(
                0f to Color.White.copy(alpha = hi),
                0.28f to Color.White.copy(alpha = hi * 0.18f),
                0.62f to Color.White.copy(alpha = hi * 0.06f),
                1f to Color.White.copy(alpha = hi * 0.55f),
                start = Offset.Zero, end = Offset(size.width, size.height),
            ),
            style = Stroke(w),
            blendMode = BlendMode.Plus,
        )
        // Luz interior en la parte de arriba (grosor del cristal).
        clipPath(path) {
            drawRect(
                Brush.verticalGradient(
                    0f to Color.White.copy(alpha = if (dark) 0.07f else 0.16f),
                    0.45f to Color.Transparent,
                ),
            )
        }
    }
}

// MARK: Pulsación interactiva --------------------------------------------------------------------

/**
 * Pulsar un cristal interactivo: crece con rebote, se ilumina donde está el dedo y vuelve al
 * soltar, como los botones de cristal de iOS 26. Sustituye a [tactile] (que se hunde) cuando el
 * cristal líquido está activo. Sin vibración.
 */
fun Modifier.glassInteractive(
    press: GlassPress,
    label: String? = null,
    enabled: Boolean = true,
    grow: Float = 0.08f,
    onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit,
): Modifier = composed {
    val reduce = LocalReduceMotion.current
    val scope = rememberCoroutineScope()
    // Igual que tactile: sin reiniciar el gesto en cada recomposición.
    val currentClick by rememberUpdatedState(onClick)
    val currentLong by rememberUpdatedState(onLongClick)
    val hasLong = onLongClick != null
    val pressSpring = if (reduce) tween<Float>(120) else spring(dampingRatio = 0.5f, stiffness = 520f)
    val releaseSpring = if (reduce) tween<Float>(160) else spring(dampingRatio = 0.42f, stiffness = Spring.StiffnessMediumLow)
    this
        .graphicsLayer {
            val s = 1f + grow * press.amount.value
            scaleX = s
            scaleY = s
            alpha = if (enabled) 1f else 0.45f
        }
        .semantics {
            role = Role.Button
            if (label != null) contentDescription = label
            if (enabled) {
                this.onClick(label = null) { onClick(); true }
                if (onLongClick != null) this.onLongClick(label = null) { onLongClick(); true }
            }
        }
        .then(
            if (!enabled) Modifier else Modifier.pointerInput(hasLong) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    press.touch = down.position
                    scope.launch { press.amount.animateTo(1f, pressSpring) }
                    var longFired = false
                    var longJob: Job? = null
                    if (hasLong) {
                        longJob = scope.launch {
                            delay(viewConfiguration.longPressTimeoutMillis)
                            longFired = true
                            currentLong?.invoke()
                            press.amount.animateTo(0f, releaseSpring)
                        }
                    }
                    var cancelled = false
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        // Un botón de dentro (▶︎, ⏭) ya se ha quedado el toque: no se abre el reproductor.
                        if (change.isConsumed) { cancelled = true; break }
                        if (!change.pressed) {
                            change.consume()
                            break
                        }
                        press.touch = change.position
                        val p = change.position
                        if (p.x < -24f || p.y < -24f || p.x > size.width + 24f || p.y > size.height + 24f ||
                            change.positionChange().getDistance() > viewConfiguration.touchSlop * 4
                        ) {
                            cancelled = true
                        }
                    }
                    longJob?.cancel()
                    scope.launch { press.amount.animateTo(0f, releaseSpring) }
                    if (!cancelled && !longFired) currentClick()
                }
            },
        )
}

/** Cristal interactivo completo: fondo + pulsación (botones redondos, mini reproductor…). */
@Composable
fun rememberGlassPress(): GlassPress = remember { GlassPress() }

// MARK: Gota de la barra de pestañas --------------------------------------------------------------

/**
 * Dibuja la «gota» de cristal que sigue al dedo por la barra de pestañas: amplía lo que hay
 * debajo (el fondo y los iconos de la propia barra) y refracta en el borde.
 */
internal fun DrawScope.drawGlassDrop(
    layer: GraphicsLayer,
    source: GlassSource,
    barOrigin: Offset,
    barContent: GraphicsLayer,
    rect: androidx.compose.ui.geometry.Rect,
    lift: Float,
    dark: Boolean,
    shader: RuntimeShader?,
) {
    val size = rect.size
    val radius = size.minDimension / 2
    val style = GlassStyle.Drop
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(50)
    val outline = shape.createOutline(size, layoutDirection, this)
    translate(rect.left, rect.top) { drawGlassShadow(outline, style.shadow.toPx() * lift, dark) }
    drawBackdrop(
        layer, source, barOrigin - source.origin, size, radius, style, shader, zoom = 1f + 0.1f * lift,
        extra = { translate(-rect.left, -rect.top) { drawLayer(barContent) } },
        topLeft = rect.topLeft,
    )
    drawGlassSurface(outline, size, dark, style, Color.Unspecified, null, topLeft = rect.topLeft)
}
