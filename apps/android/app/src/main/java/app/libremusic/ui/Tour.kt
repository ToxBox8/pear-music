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
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.composed
import kotlinx.coroutines.delay
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
 *
 * Desde la 1.1 también sirve para la **guía de Ajustes** (el botón junto a la carta) y el recorrido de
 * **novedades** tras actualizar: cada paso puede abrir una pantalla ([TourStep.enter]), se desplaza hasta lo que
 * resalta y se avanza con «Siguiente»; un paso sin elemento enseña sólo la tarjeta.
 */
object TourTargets {
    val rects = mutableStateMapOf<String, Rect>()
    val requesters = HashMap<String, BringIntoViewRequester>()
}

/** Marca un elemento que el recorrido puede resaltar (y llevar a la vista si está fuera, en una lista). */
fun Modifier.tourTarget(key: String): Modifier = composed {
    val requester = remember { BringIntoViewRequester() }
    DisposableEffect(key) {
        TourTargets.requesters[key] = requester
        onDispose {
            if (TourTargets.requesters[key] === requester) {
                TourTargets.requesters.remove(key)
                TourTargets.rects.remove(key) // fuera de la pantalla: nada de focos sobre un sitio que ya no existe
            }
        }
    }
    bringIntoViewRequester(requester).onGloballyPositioned { TourTargets.rects[key] = it.boundsInWindow() }
}

/** Claves de las filas y secciones de Ajustes (las pone [FormRow] y [FormSection] solas). */
fun rowKey(title: String) = "row:$title"
fun sectionKey(title: String) = "section:$title"

class TourStep(
    val keys: List<String>,
    val title: String,
    val text: String,
    val tab: Tab? = null,
    /** Antes de enseñar el paso (abrir una pantalla). */
    val enter: (AppState.() -> Unit)? = null,
)

private val introSteps get() = listOf(
    TourStep(listOf("tab:discover"), L("Descubrir"), L("Fragmentos de canciones que te pueden gustar, a pantalla completa. Desliza para la siguiente y toca dos veces para «Me gusta». Si no lo usas, deslízalo a la izquierda en Ajustes › Aspecto › Pestañas."), Tab.Discover),
    TourStep(listOf("tab:home"), L("Inicio"), L("Lo último que has escuchado, radios hechas para ti, lo nuevo de tus artistas y lo que fijes arriba. La campana trae los avisos de Pear Music."), Tab.Home),
    TourStep(listOf("jam"), L("Jam"), L("Una playlist compartida con quien esté contigo, aunque tenga un iPhone. Escanea el QR para entrar al momento, o escribe el código."), null),
    TourStep(listOf("tab:library"), L("Biblioteca"), L("Tus playlists, favoritos y descargas, también sin conexión. Fija arriba lo que más escuches con la chincheta y toca un artista para ver toda su discografía."), Tab.Library),
    TourStep(listOf("tab:settings"), L("Ajustes"), L("Tema, reproductor (casete, vinilo, Air), widgets, tu cuenta opcional, tus datos y ayuda."), Tab.Settings),
)

/** Abre Ajustes con esta pila (vacía = la pantalla principal). */
fun AppState.openSettings(vararg routes: Route) {
    tab = Tab.Settings
    stack(Tab.Settings).apply { clear(); addAll(routes) }
}

private fun row(title: String, text: String, vararg route: Route) =
    TourStep(listOf(rowKey(title), sectionKey(title)), title, text, enter = { openSettings(*route) })

/** Guía de Ajustes (1.1): todas las secciones y lo que se puede personalizar. Igual que en iOS. */
val settingsGuideSteps get() = listOf(
    TourStep(listOf("settings:search"), L("Buscar en Ajustes"), L("Escribe lo que buscas, por ejemplo «ecualizador» o «tema», y te lleva directo a la opción."), enter = { openSettings() }),
    TourStep(listOf("settings:mail"), L("Buzón y errores"), L("La carta abre el buzón de sugerencias y el escarabajo, «Informar de un error». Cada envío tiene número de ticket y la respuesta te llega sólo a ti, a la campana."), enter = { openSettings() }),
    row(L("Cuenta"), L("Opcional. Guarda tu biblioteca en la nube, cifrada con una clave que sólo tienes tú, y pásala a otro móvil.")),
    row(L("Tema"), L("Cristal (luz con los colores de la carátula), Aire (plata), Neón (synthwave) o Sistema. Y claro, oscuro o según el móvil."), Route.Appearance),
    row(L("Reproductor"), L("Normal, Casete, Vinilo o Air. También se cambia manteniendo pulsado el mini reproductor."), Route.Appearance),
    row(L("Colores de la portada"), L("La app y el reproductor toman los colores de la canción que suena. Elige dónde y cuánto, con presets o a tu gusto."), Route.Appearance),
    row(L("Pestañas"), L("Ordena las pestañas arrastrándolas. Desliza Descubrir a la izquierda para quitarla de la barra."), Route.Appearance),
    row(L("Barra inferior"), L("La clásica o la estilo SimpMusic: cápsula de cristal con una gota que arrastras, Buscar aparte y plegado al bajar."), Route.Appearance),
    row(L("Ajustes"), L("Ajustes puede ir en la barra o arriba en Inicio, junto al Jam."), Route.Appearance),
    row(L("Cristal líquido"), L("Barras, botones y menús de cristal que refractan lo que hay detrás, como en iOS 26."), Route.Appearance),
    row(L("Idioma"), L("Castellano, català, valencià, galego, euskara, English, Esperanto y português. Cambia al momento.")),
    row(L("Widgets"), L("Cinco widgets para la pantalla de inicio: Ahora suena (pequeño y grande), accesos rápidos, una playlist fijada y recientes.")),
    row(L("Calidad al escuchar"), L("Máxima, o ahorro de datos cuando no tienes wifi. Las descargas siempre van a la máxima."), Route.Audio),
    row(L("Igualar el volumen"), L("Que todas las canciones suenen igual de fuerte, sin subir y bajar el volumen a mano."), Route.Audio),
    row(L("Seguir con canciones parecidas"), L("Cuando se acaba la cola, sigue con una radio de canciones parecidas a la última."), Route.Audio),
    row(L("Ecualizador"), L("Graves, medios y agudos a tu gusto, con presets."), Route.Audio),
    row(L("Fundido entre canciones"), L("La canción baja al final y la siguiente entra suave: 3, 6 o 10 segundos."), Route.Audio),
    row(L("Descargas"), L("Cuánto ocupan tus canciones descargadas y borrarlas.")),
    row(L("Ordenar playlists por"), L("Recientes, A-Z, Z-A, por tamaño o a mano. Con «Editar playlists» las ordenas arrastrando."), Route.LibraryOptions),
    row(L("Descargadas y Favoritos"), L("Como portada grande en Playlists o como fila en «Tu música»."), Route.LibraryOptions),
    row(L("Dónde está Buscar"), L("Una barra arriba en Inicio o una pestaña aparte."), Route.LibraryOptions),
    row(L("Avisos"), L("Las caídas y novedades de Pear Music, también como notificación si quieres."), Route.Help),
    row(L("Guía inicial"), L("Vuelve a ver la bienvenida, el recorrido y las historias."), Route.Help),
    row(L("Tus datos"), L("Exporta todo lo que la app guarda de ti en un archivo o bórralo. Aquí también se activa o se quita la telemetría."), Route.Help),
    row(L("Avanzado"), L("Lo técnico, plegado: calidad de descarga, tolerancia al importar playlists y caché de carátulas.")),
    TourStep(emptyList(), L("¡Listo!"), L("Ya conoces todos los Ajustes. Vuelve a esta guía cuando quieras con el botón junto a la carta."), enter = { openSettings() }),
)

/** Recorrido de lo nuevo de la 1.1 (lo abre el panel de novedades). Igual que en iOS. */
val whatsNewSteps get() = listOf(
    TourStep(listOf("settings:guide"), L("Guía de Ajustes"), L("Nueva: te lleva por todos los Ajustes y te explica cada opción. Está junto a la carta."), enter = { openSettings() }),
    row(L("Idioma"), L("Ya puedes usar Pear Music en português. Y «Español» ahora se llama «Castellano».")),
    TourStep(listOf("settings:mail"), L("Buzón y errores"), L("Con cada reporte o sugerencia va la ficha de tu móvil (modelo y versiones), para ayudarte antes."), enter = { openSettings() }),
    TourStep(emptyList(), L("Y además"), L("Al descargar una versión nueva ves el progreso, y la barra clásica ya no marca Descubrir cuando estás en Ajustes."), enter = { openSettings() }),
)

/**
 * @param guided pasos con «Siguiente» (guía de Ajustes, novedades). Sin él, el recorrido de bienvenida: se avanza
 * tocando lo resaltado y se saltan los pasos que no están a la vista.
 */
@Composable
fun TourOverlay(steps: List<TourStep> = introSteps, guided: Boolean = false, onDone: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    val density = LocalDensity.current
    var index by remember { mutableIntStateOf(0) }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var boxH by remember { mutableStateOf(0f) }
    // Bienvenida: los pasos sin elemento a la vista se saltan. Guiado: todos (cada uno abre su pantalla).
    val visible = if (guided) steps else steps.filter { s -> s.keys.any { TourTargets.rects[it]?.isEmpty == false } }
    LaunchedEffect(visible.size, index) { if (visible.isNotEmpty() && index >= visible.size) onDone() }
    if (visible.isEmpty() || index >= visible.size) return
    val step = visible[index]
    // Guiado: se abre la pantalla del paso, se espera a que su elemento esté pintado y se lleva a la vista.
    var ready by remember(index) { mutableStateOf(!guided) }
    var key by remember(index) { mutableStateOf<String?>(null) }
    if (guided) BackHandler { onDone() }
    LaunchedEffect(index) {
        if (!guided) return@LaunchedEffect
        step.enter?.invoke(env.app)
        var found: String? = null
        for (attempt in 0 until 40) {
            found = step.keys.firstOrNull { TourTargets.rects[it]?.isEmpty == false }
            if (found != null) break
            delay(50)
        }
        found?.let { TourTargets.requesters[it]?.bringIntoView(); delay(260) }
        // Un paso de una opción que no hay en este móvil (p. ej. el cristal en Android 11) se salta.
        if (found == null && step.keys.isNotEmpty()) { if (index == visible.lastIndex) onDone() else index++; return@LaunchedEffect }
        key = found
        ready = true
    }
    val targetKey = if (guided) key else step.keys.firstOrNull { TourTargets.rects[it]?.isEmpty == false }
    val target = targetKey?.let { TourTargets.rects[it] }?.translate(-origin)
    val pad = with(density) { 8.dp.toPx() }
    val holeTarget = target?.let { Rect(it.left - pad, it.top - pad, it.right + pad, it.bottom + pad) }
    val hole by animateRectAsState(holeTarget ?: Rect(Offset.Zero, androidx.compose.ui.geometry.Size.Zero), uiEaseOut(420), label = "hole")
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(0f, 1f, infiniteRepeatable(tween(1400), RepeatMode.Restart), label = "p")
    fun advance() {
        if (!guided) step.tab?.let { env.app.select(it) }
        if (index == visible.lastIndex) onDone() else index++
    }

    Box(
        Modifier.fillMaxSize()
            .onGloballyPositioned { origin = it.positionInWindow(); boxH = it.size.height.toFloat() }
            .pointerInput(index, hole, ready) { detectTapGestures { if (ready && holeTarget != null && hole.contains(it)) advance() } }
            .semantics { contentDescription = L("Recorrido: {0}. {1}", step.title, step.text) },
    ) {
        Canvas(Modifier.fillMaxSize().graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }) {
            drawRect(Color.Black.copy(alpha = 0.62f))
            if (!ready || holeTarget == null) return@Canvas
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
        if (!ready) return@Box
        val centered = holeTarget == null
        val below = !centered && hole.center.y < with(density) { 360.dp.toPx() }
        val cardY = if (below) hole.bottom + with(density) { 18.dp.toPx() } else null
        Column(
            Modifier
                .then(
                    when {
                        centered -> Modifier.align(Alignment.Center)
                        cardY != null -> Modifier.offset { IntOffset(0, cardY.roundToInt()) }
                        else -> Modifier.align(Alignment.BottomCenter).offset { IntOffset(0, -(boxH - hole.top + 18.dp.toPx()).roundToInt()) }
                    },
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
                Text(L("{0} de {1}", index + 1, visible.size), style = Typo.footnote, color = c.secondaryLabel)
            }
            Spacer(Modifier.height(6.dp))
            Text(step.text, style = Typo.callout, color = c.secondaryLabel)
            Spacer(Modifier.height(14.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (guided) {
                    Text(L("Salir"), style = Typo.subheadline, color = c.secondaryLabel, modifier = Modifier.tactile(label = L("Salir de la guía")) { onDone() }.padding(8.dp))
                    Spacer(Modifier.weight(1f))
                    PillButton(if (index == visible.lastIndex) L("Terminar") else L("Siguiente"), null, prominent = true) { advance() }
                } else {
                    Text(L("Toca lo resaltado para seguir"), style = Typo.footnote.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = c.accent, modifier = Modifier.weight(1f))
                    Text(L("Saltar"), style = Typo.subheadline, color = c.secondaryLabel, modifier = Modifier.tactile(label = L("Saltar el recorrido")) { onDone() }.padding(8.dp))
                }
            }
        }
    }
}
