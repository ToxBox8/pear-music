package app.libremusic.ui


import app.libremusic.L
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateRectAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo
import kotlin.math.roundToInt

/**
 * Recorrido sobre la app real (Fase 2.1): la app se oscurece y un foco resalta cada sección; al tocar lo
 * resaltado se hace lo de verdad (cambia de pestaña) y se pasa al siguiente. Lo que no está a la vista (p. ej.
 * Ajustes arriba en vez de en la barra) se salta. Mismos pasos y textos que `TourOverlay` en iOS.
 */
object TourTargets {
    val rects = mutableStateMapOf<String, Rect>()
}

/** Marca un elemento que el recorrido puede resaltar. */
fun Modifier.tourTarget(key: String): Modifier = onGloballyPositioned { TourTargets.rects[key] = it.boundsInWindow() }

private data class TourStep(val keys: List<String>, val title: String, val text: String, val tab: Tab?)

private val steps get() = listOf(
    TourStep(listOf("tab:discover"), L("Descubrir"), L("Fragmentos de canciones que te pueden gustar, a pantalla completa. Desliza para la siguiente y toca dos veces para «Me gusta». Si no lo usas, deslízalo a la izquierda en Ajustes › Aspecto › Pestañas."), Tab.Discover),
    TourStep(listOf("tab:home"), L("Inicio"), L("Lo último que has escuchado, radios hechas para ti, lo nuevo de tus artistas y lo que fijes arriba. La campana trae los avisos de Pear Music."), Tab.Home),
    TourStep(listOf("jam"), L("Jam"), L("Una playlist compartida con quien esté contigo, aunque tenga un iPhone. Escanea el QR para entrar al momento, o escribe el código."), null),
    TourStep(listOf("tab:library"), L("Biblioteca"), L("Tus playlists, favoritos y descargas, también sin conexión. Fija arriba lo que más escuches con la chincheta y toca un artista para ver toda su discografía."), Tab.Library),
    TourStep(listOf("tab:settings"), L("Ajustes"), L("Tema, reproductor (casete, vinilo, Air), widgets, tu cuenta opcional, tus datos y ayuda."), Tab.Settings),
)

@Composable
fun TourOverlay(onDone: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    val density = LocalDensity.current
    var index by remember { mutableIntStateOf(0) }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var boxH by remember { mutableStateOf(0f) }
    // Los pasos sin elemento a la vista se saltan.
    val visible = steps.filter { s -> s.keys.any { TourTargets.rects[it]?.isEmpty == false } }
    LaunchedEffect(visible.size, index) { if (visible.isNotEmpty() && index >= visible.size) onDone() }
    if (visible.isEmpty() || index >= visible.size) return
    val step = visible[index]
    val target = step.keys.firstNotNullOf { TourTargets.rects[it]?.takeIf { r -> !r.isEmpty } }.translate(-origin)
    val pad = with(density) { 8.dp.toPx() }
    val hole by animateRectAsState(
        Rect(target.left - pad, target.top - pad, target.right + pad, target.bottom + pad), uiEaseOut(420), label = "hole",
    )
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(0f, 1f, infiniteRepeatable(tween(1400), RepeatMode.Restart), label = "p")
    fun advance() {
        step.tab?.let { env.app.select(it) }
        if (index == visible.lastIndex) onDone() else index++
    }

    Box(
        Modifier.fillMaxSize()
            .onGloballyPositioned { origin = it.positionInWindow(); boxH = it.size.height.toFloat() }
            .pointerInput(index, hole) { detectTapGestures { if (hole.contains(it)) advance() } }
            .semantics { contentDescription = L("Recorrido: {0}. {1}", step.title, step.text) },
    ) {
        Canvas(Modifier.fillMaxSize().graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }) {
            drawRect(Color.Black.copy(alpha = 0.62f))
            val r = CornerRadius(hole.height / 2.6f)
            drawRoundRect(Color.Black, hole.topLeft, hole.size, r, blendMode = BlendMode.Clear)
            // Anillo que late alrededor del foco: «toca aquí».
            val grow = pulse * with(density) { 14.dp.toPx() }
            drawRoundRect(
                c.accent.copy(alpha = 0.9f * (1 - pulse)), Offset(hole.left - grow, hole.top - grow),
                androidx.compose.ui.geometry.Size(hole.width + grow * 2, hole.height + grow * 2), CornerRadius(r.x + grow),
                style = Stroke(with(density) { 2.5.dp.toPx() }),
            )
        }
        val below = hole.center.y < with(density) { 360.dp.toPx() }
        val cardY = if (below) hole.bottom + with(density) { 18.dp.toPx() } else null
        Column(
            Modifier
                .then(
                    if (cardY != null) Modifier.offset { IntOffset(0, cardY.roundToInt()) }
                    else Modifier.align(Alignment.BottomCenter).offset { IntOffset(0, -(boxH - hole.top + 18.dp.toPx()).roundToInt()) },
                )
                .fillMaxWidth().padding(horizontal = 20.dp)
                .widthIn(max = 520.dp)
                // Opaca: sobre el velo oscuro el cristal dejaría ver el contenido de debajo y no se leería.
                .shadowSoft(18.dp, androidx.compose.foundation.shape.RoundedCornerShape(22.dp), 0.3f)
                .background(c.background, androidx.compose.foundation.shape.RoundedCornerShape(22.dp))
                .padding(20.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(step.title, style = Typo.title3.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = c.label, modifier = Modifier.weight(1f))
                Text("${index + 1} de ${visible.size}", style = Typo.footnote, color = c.secondaryLabel)
            }
            Spacer(Modifier.height(6.dp))
            Text(step.text, style = Typo.callout, color = c.secondaryLabel)
            Spacer(Modifier.height(14.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(L("Toca lo resaltado para seguir"), style = Typo.footnote.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = c.accent, modifier = Modifier.weight(1f))
                Text(L("Saltar"), style = Typo.subheadline, color = c.secondaryLabel, modifier = Modifier.tactile(label = L("Saltar el recorrido")) { onDone() }.padding(8.dp))
            }
        }
    }
}
