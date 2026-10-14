/*
 * Adaptado de SimpMusic (maxrave-dev/SimpMusic, GPL-3.0): LiquidGlassTabBar.android.kt y los
 * modificadores de plegado de AppBottomNavigationBar.kt. DampedDragAnimation es un port del
 * catálogo de Kyant (Kyant0/AndroidLiquidGlass, Apache-2.0).
 * Copiado de Open Menus (~/Proyectos/open-menus, sesión «simpmusic rea») para Pear Music: mismo vidrio, tamaños y
 * animaciones. Sólo cambian el paquete, las pestañas, los colores y el mini reproductor (datos de Pear).
 */
package app.libremusic.ui.simpbar

import android.os.SystemClock
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.MutatorMutex
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Sensors
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.util.fastCoerceIn
import androidx.compose.ui.util.lerp
import com.kyant.backdrop.backdrops.LayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.colorControls
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.effects.vibrancy
import com.kyant.backdrop.highlight.Highlight
import com.kyant.backdrop.shadow.InnerShadow
import com.kyant.backdrop.shadow.Shadow
import app.libremusic.ui.Tab
import app.libremusic.ui.icon
import app.libremusic.ui.theme.Libre
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sign

val CapsuleShape = RoundedCornerShape(percent = 50)
private val TabWidth = 96.dp
internal val BarHeight = 64.dp
private val BlobHeight = 56.dp

// Aire entre el borde de la cápsula y la gota en la primera y la última pestaña.
private val BarInset = 6.dp

// La barra se pliega en un círculo de este tamaño al hacer scroll.
internal val CollapsedBarSize = 48.dp

/**
 * Barra de pestañas "liquid glass" estilo iOS 26, en tres capas:
 *  1. la cápsula de vidrio,
 *  2. una gota esmerilada que se desliza hasta la pestaña activa y se estira y aplasta según la
 *     velocidad del arrastre ([DampedDragAnimation]),
 *  3. iconos y textos nítidos encima.
 *
 * Con [glass] en false dibuja lo mismo en plano, con el mismo movimiento.
 */
@Composable
fun LiquidGlassTabBar(
    tabs: List<Tab>,
    selectedTab: Int,
    backdrop: LayerBackdrop,
    layer: GraphicsLayer,
    luminance: State<Float>,
    glass: Boolean,
    availableWidth: Dp,
    onTabSelected: (Int) -> Unit,
    collapsedContent: @Composable () -> Unit,
    /** Pestaña fraccionaria mientras se desliza el contenido de la app (null si no): la gota la sigue. */
    follow: () -> Float? = { null },
) {
    val density = LocalDensity.current
    val tabsCount = tabs.size
    // Todas las pestañas miden lo mismo: la gota se coloca en `index * tabWidth` y el arrastre
    // divide por ese ancho.
    val tabWidth = tabWidthFor(tabsCount, availableWidth)
    val fullWidth = tabWidth * tabsCount + BarInset * 2
    val tabWidthPx = with(density) { tabWidth.toPx() }
    val currentTabWidthPx by rememberUpdatedState(tabWidthPx)
    val isLtr = LocalLayoutDirection.current == LayoutDirection.Ltr
    val animationScope = rememberCoroutineScope()
    val barInteraction = rememberGlassInteraction()

    var currentIndex by remember { mutableIntStateOf(selectedTab.coerceAtLeast(0)) }
    // [0] = hubo un arrastre real (no un toque), para que la gota no robe el toque a una pestaña.
    val draggedFlag = remember { booleanArrayOf(false) }

    val dampedDrag =
        remember(animationScope, tabsCount) {
            DampedDragAnimation(
                animationScope = animationScope,
                initialValue = selectedTab.coerceAtLeast(0).toFloat(),
                valueRange = 0f..(tabsCount - 1).toFloat(),
                visibilityThreshold = 0.001f,
                initialScale = 1f,
                // Al pulsar, la gota pasa de 56 a ~76 dp y sobresale de la barra de 64 dp.
                pressedScale = 76f / 56f,
                onDragStarted = { draggedFlag[0] = false },
                onDragStopped = {
                    if (draggedFlag[0]) {
                        val target = targetValue.roundToInt().coerceIn(0, tabsCount - 1)
                        currentIndex = target
                        // Encaja siempre en una pestaña, aunque el destino no cambie, o se queda a medias.
                        animateToValue(target.toFloat())
                    }
                },
                onDrag = { _, dragAmount ->
                    if (dragAmount.x != 0f) draggedFlag[0] = true
                    updateValue(
                        (targetValue + dragAmount.x / currentTabWidthPx * if (isLtr) 1f else -1f)
                            .coerceIn(0f, (tabsCount - 1).toFloat()),
                    )
                },
            )
        }

    // Resaltada: la más cercana a la gota mientras se desliza el contenido; si no, la elegida.
    val highlighted by remember { derivedStateOf { follow()?.roundToInt() ?: currentIndex } }

    // La selección también puede cambiar desde fuera (botón Atrás).
    LaunchedEffect(selectedTab) {
        if (selectedTab >= 0 && currentIndex != selectedTab) currentIndex = selectedTab
    }
    // Pear: al deslizar entre pestañas, la gota sigue al dedo (levantada y estirándose con la velocidad, como al
    // arrastrarla) y se posa al soltar.
    LaunchedEffect(dampedDrag) {
        var following = false
        snapshotFlow { follow() }.collect { p ->
            if (p != null) {
                if (!following) {
                    following = true
                    dampedDrag.press()
                }
                dampedDrag.followTo(p.coerceIn(0f, (tabsCount - 1).toFloat()))
            } else if (following) {
                following = false
                dampedDrag.release()
            }
        }
    }
    LaunchedEffect(dampedDrag) {
        snapshotFlow { currentIndex }
            .drop(1)
            .collectLatest { index ->
                // Si la gota ya llegó siguiendo al dedo, no se vuelve a animar (evita un segundo rebote).
                if (abs(dampedDrag.value - index) > 0.02f) dampedDrag.animateToValue(index.toFloat())
                // Los toques ya navegan en su onClick; aquí solo navega el arrastre al soltar.
                if (draggedFlag[0]) onTabSelected(index)
            }
    }

    Box(
        modifier =
            Modifier
                .height(BarHeight)
                .width(fullWidth)
                .pointerInput(barInteraction) { barInteraction.detectPress(this) },
        contentAlignment = Alignment.CenterStart,
    ) {
        // 1) Cápsula.
        Box(
            Modifier
                .matchParentSize()
                .then(
                    if (glass) {
                        Modifier.drawInteractiveGlass(backdrop, layer, { luminance.value }, CapsuleShape, barInteraction)
                    } else {
                        Modifier.flatSurface(CapsuleShape)
                    },
                ),
        )

        // Las pestañas se maquetan a ancho completo y se recortan a la cápsula mientras se despliega.
        Box(Modifier.matchParentSize().unfoldingTabs(fullWidth, CapsuleShape)) {
            Box(
                Modifier
                    .wrapContentSize(Alignment.CenterStart, unbounded = true)
                    .size(fullWidth, BarHeight),
                contentAlignment = Alignment.CenterStart,
            ) {
                // 2) Gota.
                Box(
                    Modifier
                        .graphicsLayer {
                            translationX =
                                (if (isLtr) dampedDrag.value else (tabsCount - 1) - dampedDrag.value) * tabWidthPx +
                                BarInset.toPx()
                        }.then(
                            if (glass) {
                                Modifier.glassBlob(backdrop, luminance, dampedDrag)
                            } else {
                                Modifier
                                    .graphicsLayer {
                                        scaleX = dampedDrag.scaleX
                                        scaleY = dampedDrag.scaleY
                                        val velocity = dampedDrag.velocity / 10f
                                        scaleX /= 1f - (velocity * 0.75f).fastCoerceIn(-0.2f, 0.2f)
                                        scaleY *= 1f - (velocity * 0.25f).fastCoerceIn(-0.2f, 0.2f)
                                    }.clip(CapsuleShape)
                                    .background(Color.White.copy(alpha = 0.12f))
                            },
                        ).width(tabWidth)
                        .height(BlobHeight),
                )

                // 3) Iconos y textos, que también llevan el gesto de arrastre de la gota.
                Row(
                    Modifier
                        .matchParentSize()
                        .padding(horizontal = BarInset)
                        .then(dampedDrag.modifier),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    tabs.forEachIndexed { position, tab ->
                        TabItem(tab = tab, selected = highlighted == position, width = tabWidth) {
                            if (position == currentIndex) {
                                onTabSelected(position)
                            } else {
                                // Navega ya: pasar el toque por snapshotFlow lo perdía si un fin de
                                // arrastre devolvía currentIndex a su valor anterior antes de emitir.
                                currentIndex = position
                                onTabSelected(position)
                            }
                        }
                    }
                }
            }
        }

        // 4) Plegada en círculo, la barra muestra solo la pestaña activa.
        Box(Modifier.matchParentSize().foldedCircle(fullWidth), contentAlignment = Alignment.Center) {
            collapsedContent()
        }
    }
}

private fun Modifier.glassBlob(
    backdrop: LayerBackdrop,
    luminance: State<Float>,
    dampedDrag: DampedDragAnimation,
): Modifier =
    drawBackdrop(
        backdrop = backdrop,
        shape = { CapsuleShape },
        effects = {
            val l = (luminance.value * 2f - 1f).let { sign(it) * it * it }
            val progress = dampedDrag.pressProgress
            vibrancy()
            colorControls(brightness = 0.05f, contrast = 1f, saturation = 1.5f)
            // Más desenfoque que la cápsula, para que la gota se lea como vidrio esmerilado.
            blur(
                (if (l > 0f) lerp(8f.dp.toPx(), 16f.dp.toPx(), l) else lerp(8f.dp.toPx(), 2f.dp.toPx(), -l)) +
                    20f.dp.toPx(),
            )
            lens(10f.dp.toPx() * progress, 14f.dp.toPx() * progress, chromaticAberration = true)
        },
        highlight = { Highlight.Default.copy(alpha = 0.6f) },
        shadow = { Shadow(radius = 4f.dp, alpha = 0.4f) },
        innerShadow = {
            val progress = dampedDrag.pressProgress
            InnerShadow(radius = 8f.dp * progress, alpha = progress)
        },
        layerBlock = {
            scaleX = dampedDrag.scaleX
            scaleY = dampedDrag.scaleY
            val velocity = dampedDrag.velocity / 10f
            scaleX /= 1f - (velocity * 0.75f).fastCoerceIn(-0.2f, 0.2f)
            scaleY *= 1f - (velocity * 0.25f).fastCoerceIn(-0.2f, 0.2f)
        },
        onDrawSurface = {
            val lumNorm = ((luminance.value - 0.3f) / 0.5f).coerceIn(0f, 1f)
            drawRect(Color.Black.copy(alpha = lerp(0.22f, 0.55f, lumNorm)))
        },
    )

/** Superficie plana para comparar con el vidrio: mismo contorno, sin muestrear el fondo. */
fun Modifier.flatSurface(shape: Shape): Modifier = clip(shape).background(Color(0xFF1E1E24).copy(alpha = 0.94f))

private fun tabWidthFor(
    tabsCount: Int,
    availableWidth: Dp,
): Dp =
    if (availableWidth.isSpecified && availableWidth > 0.dp) {
        ((availableWidth - BarInset * 2) / tabsCount).coerceAtMost(TabWidth)
    } else {
        TabWidth
    }

internal fun liquidGlassTabBarWidth(
    tabsCount: Int,
    availableWidth: Dp,
): Dp = tabWidthFor(tabsCount, availableWidth) * tabsCount + BarInset * 2

@Composable
private fun TabItem(
    tab: Tab,
    selected: Boolean,
    width: Dp,
    onClick: () -> Unit,
) {
    val color = if (selected) Libre.colors.accent else BarContent
    Column(
        Modifier
            .width(width)
            .fillMaxHeight()
            .clip(CapsuleShape)
            .clickable(interactionSource = null, indication = null, role = Role.Tab, onClick = onClick),
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CompositionLocalProvider(LocalContentColor provides color) {
            Icon(tab.icon(), contentDescription = null)
            Text(text = tab.title, style = MaterialTheme.typography.labelSmall, color = color, maxLines = 1)
        }
    }
}

// 0 en el círculo plegado, 1 a ancho completo, según el ancho que de verdad recibe la barra.
private fun Density.foldProgress(
    width: Int,
    fullWidth: Dp,
): Float {
    val folded = CollapsedBarSize.roundToPx()
    return ((width - folded).toFloat() / (fullWidth.roundToPx() - folded).coerceAtLeast(1)).coerceIn(0f, 1f)
}

/** Las pestañas aparecen cuando ya se ha ido el icono del círculo, recortadas a [clipShape] a mitad de despliegue. */
internal fun Modifier.unfoldingTabs(
    fullWidth: Dp,
    clipShape: Shape?,
): Modifier =
    layout { measurable, constraints ->
        val progress = foldProgress(constraints.maxWidth, fullWidth)
        val placeable = measurable.measure(constraints)
        layout(placeable.width, placeable.height) {
            val tabsAlpha = ((progress - 0.3f) / 0.7f).coerceIn(0f, 1f)
            if (tabsAlpha > 0f) {
                placeable.placeRelativeWithLayer(0, 0) {
                    alpha = tabsAlpha
                    if (clipShape != null) {
                        // Solo a mitad del pliegue: en reposo la gota pulsada tiene que poder sobresalir.
                        clip = progress < 1f
                        shape = clipShape
                    }
                }
            }
        }
    }

/** El contenido del círculo plegado: un cuadrado de [CollapsedBarSize] que se desvanece al desplegar. */
internal fun Modifier.foldedCircle(fullWidth: Dp): Modifier =
    layout { measurable, constraints ->
        val progress = foldProgress(constraints.maxWidth, fullWidth)
        val size = CollapsedBarSize.roundToPx()
        val placeable = measurable.measure(Constraints.fixed(size, size))
        layout(constraints.maxWidth, constraints.maxHeight) {
            val circleAlpha = (1f - progress / 0.4f).coerceIn(0f, 1f)
            if (circleAlpha > 0f) {
                placeable.placeRelativeWithLayer(0, (constraints.maxHeight - size) / 2) {
                    alpha = circleAlpha
                }
            }
        }
    }

/**
 * Animación 1-D con muelles: sigue un [value] continuo entre pestañas, la [velocity] del arrastre
 * (para estirar y aplastar), un [pressProgress] (reposo → vidrio levantado) y muelles separados
 * para [scaleX] y [scaleY].
 */
class DampedDragAnimation(
    private val animationScope: CoroutineScope,
    val initialValue: Float,
    val valueRange: ClosedRange<Float>,
    val visibilityThreshold: Float,
    val initialScale: Float,
    val pressedScale: Float,
    val onDragStarted: DampedDragAnimation.(position: Offset) -> Unit,
    val onDragStopped: DampedDragAnimation.() -> Unit,
    val onDrag: DampedDragAnimation.(size: IntSize, dragAmount: Offset) -> Unit,
) {
    private val valueAnimationSpec = spring(1f, 1000f, visibilityThreshold)
    private val velocityAnimationSpec = spring(0.5f, 300f, visibilityThreshold * 10f)
    private val pressProgressAnimationSpec = spring(1f, 1000f, 0.001f)
    private val scaleXAnimationSpec = spring(0.6f, 250f, 0.001f)
    private val scaleYAnimationSpec = spring(0.7f, 250f, 0.001f)

    private val valueAnimation = Animatable(initialValue, visibilityThreshold)
    private val velocityAnimation = Animatable(0f, 5f)
    private val pressProgressAnimation = Animatable(0f, 0.001f)
    private val scaleXAnimation = Animatable(initialScale, 0.001f)
    private val scaleYAnimation = Animatable(initialScale, 0.001f)

    private val mutatorMutex = MutatorMutex()
    private val velocityTracker = VelocityTracker()

    val value: Float get() = valueAnimation.value
    val targetValue: Float get() = valueAnimation.targetValue
    val pressProgress: Float get() = pressProgressAnimation.value
    val scaleX: Float get() = scaleXAnimation.value
    val scaleY: Float get() = scaleYAnimation.value
    val velocity: Float get() = velocityAnimation.value

    val modifier: Modifier =
        Modifier.pointerInput(Unit) {
            inspectDragGestures(
                onDragStart = { down ->
                    onDragStarted(down.position)
                    press()
                },
                onDragEnd = {
                    onDragStopped()
                    release()
                },
                onDragCancel = {
                    onDragStopped()
                    release()
                },
            ) { _, dragAmount ->
                onDrag(size, dragAmount)
            }
        }

    fun press() {
        velocityTracker.resetTracking()
        animationScope.launch {
            launch { pressProgressAnimation.animateTo(1f, pressProgressAnimationSpec) }
            launch { scaleXAnimation.animateTo(pressedScale, scaleXAnimationSpec) }
            launch { scaleYAnimation.animateTo(pressedScale, scaleYAnimationSpec) }
        }
    }

    fun release() {
        animationScope.launch {
            withFrameNanos {}
            if (value != targetValue) {
                val threshold = (valueRange.endInclusive - valueRange.start) * 0.025f
                snapshotFlow { valueAnimation.value }
                    .filter { abs(it - valueAnimation.targetValue) < threshold }
                    .first()
            }
            launch { pressProgressAnimation.animateTo(0f, pressProgressAnimationSpec) }
            launch { scaleXAnimation.animateTo(initialScale, scaleXAnimationSpec) }
            launch { scaleYAnimation.animateTo(initialScale, scaleYAnimationSpec) }
        }
    }

    /** Pear: pone la gota en [value] al instante (sigue al dedo) y mide la velocidad para estirarla. */
    fun followTo(value: Float) {
        animationScope.launch {
            valueAnimation.snapTo(value.coerceIn(valueRange.start, valueRange.endInclusive))
            updateVelocity()
        }
    }

    fun updateValue(value: Float) {
        val target = value.coerceIn(valueRange.start, valueRange.endInclusive)
        animationScope.launch {
            valueAnimation.animateTo(target, valueAnimationSpec) { updateVelocity() }
        }
    }

    fun animateToValue(value: Float) {
        animationScope.launch {
            mutatorMutex.mutate {
                press()
                val target = value.coerceIn(valueRange.start, valueRange.endInclusive)
                launch { valueAnimation.animateTo(target, valueAnimationSpec) }
                if (velocity != 0f) {
                    launch { velocityAnimation.animateTo(0f, velocityAnimationSpec) }
                }
                release()
            }
        }
    }

    private fun updateVelocity() {
        velocityTracker.addPosition(SystemClock.uptimeMillis(), Offset(value, 0f))
        val targetVelocity =
            velocityTracker.calculateVelocity().x / (valueRange.endInclusive - valueRange.start)
        animationScope.launch { velocityAnimation.animateTo(targetVelocity, velocityAnimationSpec) }
    }
}

/** Color de iconos y textos sobre el vidrio oscuro (el onSurface del tema oscuro de Open Menus). */
internal val BarContent = Color(0xFFE6E1E5)
