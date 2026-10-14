/*
 * Adaptado de SimpMusic (maxrave-dev/SimpMusic, GPL-3.0): LiquidGlassContainer.kt y
 * GlassLuminance.kt. El reconocedor de gestos viene del catálogo de Kyant
 * (Kyant0/AndroidLiquidGlass, Apache-2.0).
 * Copiado de Open Menus (~/Proyectos/open-menus, sesión «simpmusic rea») para Pear Music: mismo vidrio, tamaños y
 * animaciones. Sólo cambian el paquete, las pestañas, los colores y el mini reproductor (datos de Pear).
 */
package app.libremusic.ui.simpbar

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.fastFirstOrNull
import androidx.compose.ui.util.lerp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.kyant.backdrop.backdrops.LayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.colorControls
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.effects.vibrancy
import com.kyant.backdrop.highlight.Highlight
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.sign

/**
 * Estado de pulsación de una superficie de vidrio: [pressProgress] va de 0 a 1 con un muelle
 * mientras el dedo está abajo, y [touchPosition] centra el brillo radial. Solo observa el gesto,
 * así que los clics de lo que haya dentro siguen funcionando.
 */
class GlassInteraction(
    private val animationScope: CoroutineScope,
) {
    private val pressSpec = spring(dampingRatio = 0.5f, stiffness = 300f, visibilityThreshold = 0.001f)
    private val pressAnimation = Animatable(0f, 0.001f)

    val pressProgress: Float get() = pressAnimation.value

    var touchPosition by mutableStateOf(Offset.Zero)
        private set

    suspend fun detectPress(pointer: PointerInputScope) =
        with(pointer) {
            inspectDragGestures(
                onDragStart = { down ->
                    touchPosition = down.position
                    animationScope.launch { pressAnimation.animateTo(1f, pressSpec) }
                },
                onDragEnd = { animationScope.launch { pressAnimation.animateTo(0f, pressSpec) } },
                onDragCancel = { animationScope.launch { pressAnimation.animateTo(0f, pressSpec) } },
            ) { change, _ ->
                touchPosition = change.position
            }
        }
}

@Composable
fun rememberGlassInteraction(): GlassInteraction {
    val scope = rememberCoroutineScope()
    return remember(scope) { GlassInteraction(scope) }
}

/**
 * El vidrio de SimpMusic: vibrancia + saturación ×1.5, desenfoque que depende del brillo de lo
 * que hay detrás, lente en los bordes y un velo oscuro para que el texto se lea. Al pulsar, la
 * superficie crece un poco, la lente se acentúa y un brillo sigue al dedo.
 *
 * [layer] solo hace falta en la superficie que muestrea el brillo del fondo.
 */
fun Modifier.drawInteractiveGlass(
    backdrop: LayerBackdrop,
    layer: GraphicsLayer?,
    luminance: () -> Float,
    shape: Shape,
    interaction: GlassInteraction?,
    pressedScale: Float = 1.12f,
    minScrim: Float = 0.12f,
    maxScrim: Float = 0.5f,
): Modifier =
    this
        .drawBackdrop(
            backdrop = backdrop,
            shape = { shape },
            highlight = { Highlight.Default },
            effects = {
                val l = (luminance() * 2f - 1f).let { sign(it) * it * it }
                val press = interaction?.pressProgress ?: 0f
                vibrancy()
                colorControls(brightness = 0.05f, contrast = 1f, saturation = 1.5f)
                blur(
                    (if (l > 0f) lerp(8f.dp.toPx(), 16f.dp.toPx(), l) else lerp(8f.dp.toPx(), 2f.dp.toPx(), -l)) +
                        2f.dp.toPx() * press,
                )
                // La altura de refracción se queda por debajo del radio interior de la cápsula para que
                // la refracción de arriba y la de abajo no se junten en el centro (deja una costura).
                lens(size.minDimension / 4f + 2f.dp.toPx() * press, size.minDimension / 2f, false)
            },
            onDrawBackdrop = { drawBackdrop ->
                drawBackdrop()
                layer?.record { drawBackdrop() }
            },
            onDrawSurface = {
                val darken = lerp(minScrim, maxScrim, ((luminance() - 0.3f) / 0.5f).coerceIn(0f, 1f))
                drawRect(Color.Black.copy(alpha = darken))
                val press = interaction?.pressProgress ?: 0f
                if (press > 0f) {
                    drawRect(
                        brush =
                            Brush.radialGradient(
                                colors = listOf(Color.White.copy(alpha = 0.18f * press), Color.Transparent),
                                center = interaction?.touchPosition ?: Offset(size.width / 2f, size.height / 2f),
                                radius = size.minDimension * 1.2f,
                            ),
                        blendMode = BlendMode.Plus,
                    )
                }
            },
            layerBlock =
                if (interaction != null) {
                    {
                        val scale = lerp(1f, pressedScale, interaction.pressProgress)
                        scaleX = scale
                        scaleY = scale
                    }
                } else {
                    null
                },
        ).then(
            if (interaction != null) {
                Modifier.pointerInput(interaction) { interaction.detectPress(this) }
            } else {
                Modifier
            },
        )

private const val SAMPLE_SIZE = 5
private const val LUMINANCE_CHANGE_THRESHOLD = 0.02f

/**
 * Brillo medio (0.3–0.8) de lo que hay detrás de la barra: cada [intervalMs] (1 s en SimpMusic
 * 2.2.0, 2,5 s en 2.3) reduce la capa grabada a
 * 5×5 píxeles y promedia su luminancia. El vidrio lo usa para el desenfoque y el velo.
 */
@Composable
fun rememberGlassLuminance(
    source: GraphicsLayer,
    enabled: Boolean = true,
    intervalMs: Long = 2_500L,
): State<Float> {
    val sample = rememberGraphicsLayer()
    val luminance = remember { Animatable(0f) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val density = LocalDensity.current
    val layoutDirection = LocalLayoutDirection.current

    LaunchedEffect(source, sample, enabled, intervalMs, lifecycle, density, layoutDirection) {
        if (!enabled) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            val pixels = IntArray(SAMPLE_SIZE * SAMPLE_SIZE)
            while (isActive) {
                val sourceSize = source.size
                if (sourceSize.width > 0 && sourceSize.height > 0) {
                    val target =
                        try {
                            sample.record(density, layoutDirection, IntSize(SAMPLE_SIZE, SAMPLE_SIZE)) {
                                scale(
                                    scaleX = SAMPLE_SIZE.toFloat() / sourceSize.width,
                                    scaleY = SAMPLE_SIZE.toFloat() / sourceSize.height,
                                    pivot = Offset.Zero,
                                ) {
                                    drawLayer(source)
                                }
                            }
                            sample.toImageBitmap().readPixels(pixels)
                            val average =
                                pixels.sumOf { color ->
                                    val r = (color shr 16 and 0xFF) / 255.0
                                    val g = (color shr 8 and 0xFF) / 255.0
                                    val b = (color and 0xFF) / 255.0
                                    0.2126 * r + 0.7152 * g + 0.0722 * b
                                } / pixels.size
                            average.toFloat().coerceIn(0.3f, 0.8f)
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (_: Exception) {
                            return@repeatOnLifecycle
                        }
                    if (abs(target - luminance.targetValue) >= LUMINANCE_CHANGE_THRESHOLD) {
                        luminance.animateTo(target, tween(500))
                    }
                }
                delay(intervalMs)
            }
        }
    }
    return luminance.asState()
}

/** Reconocedor de arrastre que no consume eventos (catálogo de Kyant, Apache-2.0). */
suspend fun PointerInputScope.inspectDragGestures(
    onDragStart: (down: PointerInputChange) -> Unit = {},
    onDragEnd: (change: PointerInputChange) -> Unit = {},
    onDragCancel: () -> Unit = {},
    onDrag: (change: PointerInputChange, dragAmount: Offset) -> Unit,
) {
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        val down = awaitFirstDown(requireUnconsumed = false)
        onDragStart(down)
        onDrag(down, Offset.Zero)
        val upEvent = drag(pointerId = down.id, onDrag = { onDrag(it, it.positionChange()) })
        if (upEvent == null) onDragCancel() else onDragEnd(upEvent)
    }
}

private suspend inline fun AwaitPointerEventScope.drag(
    pointerId: PointerId,
    onDrag: (PointerInputChange) -> Unit,
): PointerInputChange? {
    val isPointerUp = currentEvent.changes.fastFirstOrNull { it.id == pointerId }?.pressed != true
    if (isPointerUp) return null
    var pointer = pointerId
    while (true) {
        val change = awaitDragOrUp(pointer) ?: return null
        if (change.isConsumed) return null
        if (change.changedToUpIgnoreConsumed()) return change
        onDrag(change)
        pointer = change.id
    }
}

private suspend inline fun AwaitPointerEventScope.awaitDragOrUp(pointerId: PointerId): PointerInputChange? {
    var pointer = pointerId
    while (true) {
        val event = awaitPointerEvent()
        val dragEvent = event.changes.fastFirstOrNull { it.id == pointer } ?: return null
        if (dragEvent.changedToUpIgnoreConsumed()) {
            val otherDown = event.changes.fastFirstOrNull { it.pressed }
            if (otherDown == null) return dragEvent else pointer = otherDown.id
        } else if (dragEvent.previousPosition != dragEvent.position) {
            return dragEvent
        }
    }
}
