package app.libremusic.ui


import app.libremusic.L
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.libremusic.R
import app.libremusic.ui.theme.LocalReduceMotion
import app.libremusic.ui.theme.Typo

/**
 * Historias a pantalla completa (Fase 2.1), después del recorrido: cinco capturas reales de la app con lo que se
 * puede hacer en cada sección. Avanzan solas cada 6 s; toque a la derecha o a la izquierda para pasar, mantener
 * pulsado para pausar. Mismas historias y textos que `StoriesView` en iOS.
 */
private class Story(val image: Int, val title: String, val text: String)

private val stories get() = listOf(
    Story(R.drawable.story_biblioteca, L("Tu biblioteca, a tu manera"), L("Playlists con tu foto, icono y color, favoritos y descargas en un sitio. Fija arriba lo que más escuchas y abre la discografía completa de cada artista.")),
    Story(R.drawable.story_reproductores, L("Reproductores con personalidad"), L("Casete con bobinas que giras con el dedo, vinilo que se puede «scratchear» o el Air plateado. Mantén pulsado el mini reproductor para cambiar.")),
    Story(R.drawable.story_letra, L("La letra, al compás"), L("Toca la cola y elige Letra: sigue la canción línea a línea y se guarda para verla sin conexión.")),
    Story(R.drawable.story_jam, L("Jam con tus amigos"), L("Una playlist a la que todos añaden canciones desde su móvil, iPhone o Android, en la misma Wi-Fi. Con el QR se entra al momento.")),
    Story(R.drawable.story_temas, L("Hazla tuya"), L("Cristal, Aire, Neón o Sistema, y colores que salen de la portada. Todo en Ajustes › Aspecto.")),
)

private const val STORY_MS = 6_000

@Composable
fun StoriesScreen(onDone: () -> Unit) {
    val reduce = LocalReduceMotion.current
    var index by remember { mutableIntStateOf(0) }
    var paused by remember { mutableStateOf(false) }
    val progress = remember { Animatable(0f) }
    fun go(to: Int) = if (to >= stories.size) onDone() else index = to.coerceAtLeast(0)

    var shown by remember { mutableIntStateOf(-1) }
    // Un solo efecto: al cambiar de historia empieza de cero; al pausar se para donde iba y al soltar sigue.
    LaunchedEffect(index, paused) {
        if (shown != index) { progress.snapTo(0f); shown = index }
        if (paused) return@LaunchedEffect
        progress.animateTo(1f, tween(((1f - progress.value) * STORY_MS).toInt().coerceAtLeast(1), easing = LinearEasing))
        go(index + 1)
    }

    val story = stories[index]
    Box(
        Modifier.fillMaxSize().background(Color.Black)
            .semantics { contentDescription = L("Historia {0} de {1}: {2}. {3}", index + 1, stories.size, story.title, story.text) }
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    paused = true
                    val start = System.currentTimeMillis()
                    val up = waitForUpOrCancellation()
                    paused = false
                    if (up != null && System.currentTimeMillis() - start < 300) {
                        if (down.position.x < size.width * 0.3f) go(index - 1) else go(index + 1)
                    }
                }
            },
    ) {
        // Fondo: la misma captura, muy desenfocada, para que cada historia tenga su color.
        Image(
            painterResource(story.image), null, contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().blur(60.dp).graphicsLayer { alpha = 0.55f },
        )
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)))
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                stories.indices.forEach { i ->
                    val fill = when { i < index -> 1f; i == index -> progress.value; else -> 0f }
                    Box(Modifier.weight(1f).height(3.dp).clip(RoundedCornerShape(2.dp)).background(Color.White.copy(alpha = 0.3f))) {
                        Box(Modifier.fillMaxHeight().fillMaxWidth(fill).background(Color.White))
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(L("Pear Music"), style = Typo.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = Color.White, modifier = Modifier.padding(start = 8.dp).weight(1f))
                Icon(Icons.Rounded.Close, L("Cerrar las historias"), tint = Color.White, modifier = Modifier.tactile(label = L("Cerrar")) { onDone() }.padding(12.dp))
            }
            AnimatedContent(index, Modifier.weight(1f), label = "story", transitionSpec = { fadeIn(uiEaseOut(380)) togetherWith fadeOut(uiEaseOut(200)) }) { i ->
                val s = stories[i]
                Column(Modifier.fillMaxSize().padding(horizontal = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                        // Zoom lento mientras dura la historia (nada con «Reducir movimiento»).
                        val zoom = if (reduce || i != index) 1f else 1f + 0.04f * progress.value
                        Image(
                            painterResource(s.image), null, contentScale = ContentScale.Fit,
                            modifier = Modifier.fillMaxHeight().aspectRatio(1179f / 2556f)
                                .graphicsLayer { scaleX = zoom; scaleY = zoom; shadowElevation = 30f; shape = RoundedCornerShape(30.dp); clip = true },
                        )
                    }
                    Text(s.title, style = Typo.title2, color = Color.White)
                    Spacer(Modifier.height(8.dp))
                    Text(s.text, style = Typo.callout, color = Color.White.copy(alpha = 0.85f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    Spacer(Modifier.height(18.dp))
                }
            }
            if (index == stories.lastIndex) {
                PillButton(L("Empezar a escuchar"), null, prominent = true, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp)) { onDone() }
            } else {
                Text(
                    L("Toca para seguir · mantén para pausar"), style = Typo.footnote, color = Color.White.copy(alpha = 0.7f),
                    modifier = Modifier.align(Alignment.CenterHorizontally).padding(vertical = 18.dp),
                )
            }
        }
    }
}
