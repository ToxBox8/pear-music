package app.libremusic.ui

import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import app.libremusic.ui.theme.LocalReduceMotion
import app.libremusic.ui.theme.LocalScreenVisible
import kotlinx.coroutines.launch
import kotlin.math.abs
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBackIosNew
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.libremusic.data.RemoteCollection
import app.libremusic.data.Song
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.material
import app.libremusic.ui.theme.semibold

// Navegación con pestañas y una pila por pestaña, como TabView + NavigationStack en iOS.

/** [key]: la clave de `TabOrder` (igual que en iOS). */
enum class Tab(val title: String, val key: String) {
    Home("Inicio", "home"), Discover("Descubrir", "discover"), Search("Buscar", "search"), Library("Biblioteca", "library"), Settings("Ajustes", "settings");

    companion object {
        fun of(key: String): Tab = entries.firstOrNull { it.key == key } ?: Home
    }
}

enum class SmartList(val title: String) { Downloads("Descargadas"), Favorites("Favoritos") }

/** Pantallas que se apilan dentro de una pestaña. */
sealed interface Route {
    data class Collection(val collection: RemoteCollection) : Route
    data class PlaylistR(val id: String) : Route
    data class Smart(val kind: SmartList) : Route
    data class Songs(val title: String, val songs: List<Song>) : Route
    data object AllSongs : Route
    data object Recents : Route
    data object Stats : Route
    data class PendingImport(val playlistId: String) : Route
    data object Artists : Route
    data class Artist(val name: String) : Route
    data class RemoteArtistR(val artist: app.libremusic.data.RemoteArtist) : Route
    data object Playlists : Route
    data object Albums : Route
    data object ArtworkColors : Route
    data object TabOrderR : Route
    data object DownloadsSettings : Route
    data object Help : Route
    data object AppIconR : Route
    /** «Informar de un error»: un reporte nuevo (null) o un borrador. */
    data class Support(val draftId: String?) : Route
    data object SupportDrafts : Route
    data object Appearance : Route
    data object ThemePicker : Route
    data object PlayerPicker : Route
    data object LibraryOptions : Route
    data object SearchOptions : Route
    data object Audio : Route
    data object About : Route
    data object ManagePlaylists : Route
    data object ReorderPlaylists : Route
    data object Avisos : Route
}

/** Un aviso centrado (UIAlertController .alert). */
data class AlertSpec(
    val title: String,
    val message: String? = null,
    val field: String? = null,
    val fieldInitial: String = "",
    val buttons: List<AlertButton>,
)

data class AlertButton(val label: String, val role: Role = Role.Default, val onClick: (String) -> Unit = {}) {
    enum class Role { Default, Cancel, Destructive }
}

class AppState {
    var tab by mutableStateOf(Tab.Home)
    private val stacks = HashMap<Tab, SnapshotStateList<Route>>()
    var showPlayer by mutableStateOf(false)
    /** Panel con el que se abre el reproductor (capturas de pantalla); null = la carátula. */
    var initialPanel: PlayerPanel? = null
    var showJam by mutableStateOf(false)
    var alert by mutableStateOf<AlertSpec?>(null)
    var toast by mutableStateOf<String?>(null)
    /** Editor de playlist abierto como hoja (id). */
    var editing by mutableStateOf<String?>(null)
    var showImport by mutableStateOf(false)

    fun stack(t: Tab): SnapshotStateList<Route> = stacks.getOrPut(t) { mutableStateListOf() }
    fun push(r: Route) { stack(tab).add(r) }
    fun pop(): Boolean {
        val s = stack(tab)
        if (s.isEmpty()) return false
        s.removeAt(s.lastIndex)
        return true
    }

    /** Tocar la pestaña activa vuelve a la raíz, como en iOS. */
    fun select(t: Tab) {
        if (t == tab) stack(t).clear() else tab = t
    }
}

val LocalApp = staticCompositionLocalOf { AppState() }
/** Espacio que ocupan la barra de pestañas y el mini reproductor: las listas lo dejan libre al final. */
val LocalBottomInset = compositionLocalOf { 0.dp }

/** Curva de UINavigationController al apilar y desapilar. */
private val IosNavEasing = CubicBezierEasing(0.2f, 0.9f, 0.25f, 1f)

/** Arrastre horizontal claro: más de [slop] y bastante más horizontal que vertical. */
internal fun isHorizontal(dx: Float, dy: Float, slop: Float) = abs(dx) > slop && abs(dx) > abs(dy) * 1.3f

/**
 * Pila de una pestaña como UINavigationController de iOS: la pantalla nueva entra por la
 * derecha y la anterior se aparta un 30 % y se oscurece un poco. Para volver: el botón atrás,
 * arrastrar hacia la derecha desde cualquier punto (como iOS 26) o el gesto atrás de Android,
 * que mueven la pantalla con el dedo. Las pantallas de debajo guardan su estado (desplazamiento…).
 */
@Composable
fun TabStack(tab: Tab, root: @Composable () -> Unit, screen: @Composable (Route) -> Unit) {
    val app = LocalApp.current
    val stack = app.stack(tab)
    val holder = rememberSaveableStateHolder()
    val scope = rememberCoroutineScope()
    val reduce = LocalReduceMotion.current
    val active = LocalScreenVisible.current
    // 0 = la de arriba en su sitio · 1 = la de arriba fuera por la derecha.
    val offset = remember { Animatable(0f) }
    var shown by remember { mutableStateOf(stack.toList()) }
    // Lo que queda debajo mientras se desapila (puede ser la raíz si se tocó la pestaña).
    var below by remember { mutableStateOf<List<Route>?>(null) }
    var gesturePop by remember { mutableStateOf(false) }
    val pushSpec = if (reduce) tween<Float>(1) else tween(460, easing = IosNavEasing)
    val popSpec = if (reduce) tween<Float>(1) else tween(340, easing = IosNavEasing)

    fun keyOf(list: List<Route>) = if (list.isEmpty()) "root" else "${list.size}:${list.last().hashCode()}"

    LaunchedEffect(stack.size, stack.lastOrNull()) {
        val target = stack.toList()
        when {
            target.size > shown.size || (target.size == shown.size && target != shown) -> {
                below = shown
                shown = target
                offset.snapTo(1f)
                offset.animateTo(0f, pushSpec)
                below = null
            }
            target.size < shown.size -> {
                val gone = shown
                below = target
                if (!gesturePop) offset.animateTo(1f, popSpec)
                gesturePop = false
                // Las pantallas que se cierran olvidan su estado; las de debajo lo conservan.
                for (n in target.size + 1..gone.size) holder.removeState(keyOf(gone.take(n)))
                shown = target
                below = null
                offset.snapTo(0f)
            }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val width = constraints.maxWidth.toFloat()
        val dragging = offset.value > 0f
        val under = below ?: shown.dropLast(1).takeIf { shown.isNotEmpty() }

        @Composable
        fun Entry(list: List<Route>) {
            val k = keyOf(list)
            key(k) { holder.SaveableStateProvider(k) { if (list.isEmpty()) root() else screen(list.last()) } }
        }

        // Atrás interactivo: arrastrar hacia la derecha. Si algo de dentro (carrusel, fila que se
        // desliza, control) ya se ha quedado el arrastre, no se hace nada.
        val canPop = shown.isNotEmpty() && below == null && active
        Box(
            Modifier.fillMaxSize().pointerInput(canPop, width) {
                if (!canPop) return@pointerInput
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val tracker = VelocityTracker()
                    var dx = 0f
                    var dy = 0f
                    var claimed = false
                    while (true) {
                        val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        val d = change.positionChange()
                        if (!claimed) {
                            if (change.isConsumed) return@awaitEachGesture
                            dx += d.x
                            dy += d.y
                            if (abs(dx) > viewConfiguration.touchSlop || abs(dy) > viewConfiguration.touchSlop) {
                                if (dx > 0 && isHorizontal(dx, dy, viewConfiguration.touchSlop)) claimed = true else return@awaitEachGesture
                            }
                        }
                        if (claimed) {
                            change.consume()
                            tracker.addPosition(change.uptimeMillis, change.position)
                            scope.launch { offset.snapTo((offset.value + d.x / width).coerceIn(0f, 1f)) }
                        }
                    }
                    if (!claimed) return@awaitEachGesture
                    val v = tracker.calculateVelocity().x
                    scope.launch {
                        if (offset.value > 0.45f || v > 900f * density) {
                            offset.animateTo(1f, popSpec)
                            gesturePop = true
                            app.pop()
                        } else {
                            offset.animateTo(0f, popSpec)
                        }
                    }
                }
            },
        ) {
            if (under != null && (dragging || below != null)) {
                Box(Modifier.fillMaxSize().graphicsLayer { translationX = -0.3f * width * (1f - offset.value) }) {
                    Entry(under)
                    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.1f * (1f - offset.value))))
                }
            }
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer { translationX = width * offset.value }
                    .drawBehind {
                        // Sombra en el borde izquierdo de la pantalla que se mueve, como en iOS.
                        if (offset.value > 0f) {
                            val w = 18.dp.toPx()
                            drawRect(
                                Brush.horizontalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.14f)), startX = -w, endX = 0f),
                                topLeft = Offset(-w, 0f), size = Size(w, size.height),
                            )
                        }
                    },
            ) { Entry(shown) }
        }
    }

    // Gesto atrás del sistema (Android 13+ con vista previa): mueve la pantalla igual que el dedo.
    PredictiveBackHandler(enabled = shown.isNotEmpty() && below == null && active) { progress ->
        try {
            progress.collect { e -> offset.snapTo(e.progress.coerceIn(0f, 1f)) }
            offset.animateTo(1f, popSpec)
            gesturePop = true
            app.pop()
        } catch (e: kotlin.coroutines.cancellation.CancellationException) {
            scope.launch { offset.animateTo(0f, popSpec) }
            throw e
        }
    }
}

/** Barra de navegación de una pantalla apilada: botón atrás redondo (iOS 26), título en línea y acciones. */
@Composable
fun NavBar(title: String?, onBack: (() -> Unit)?, trailing: @Composable () -> Unit = {}) {
    val c = Libre.colors
    Box(
        Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .height(44.dp)
            .padding(horizontal = 16.dp),
    ) {
        if (onBack != null) {
            val press = rememberGlassPress()
            Box(
                Modifier
                    .align(Alignment.CenterStart)
                    .size(44.dp)
                    .then(
                        if (LocalGlass.current != null) {
                            Modifier.glassInteractive(press, "Atrás", grow = 0.12f, onClick = onBack)
                                .liquidGlass(CircleShape, c.dark, GlassStyle.Button, press = press, fallback = material(c.dark))
                        } else {
                            Modifier.background(material(c.dark, thick = true), CircleShape).tactile(label = "Atrás", onClick = onBack)
                        },
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.ArrowBackIosNew, null, tint = c.label, modifier = Modifier.padding(end = 3.dp).size(26.dp))
            }
        }
        if (title != null) {
            Text(
                title, style = Typo.headline, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center, modifier = Modifier.align(Alignment.Center).padding(horizontal = 60.dp),
            )
        }
        Row(Modifier.align(Alignment.CenterEnd), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            trailing()
        }
    }
}

/** Título grande de una pantalla raíz (navigationTitle con large title). */
@Composable
fun LargeTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = Typo.largeTitle, color = Libre.colors.label, modifier = modifier.padding(horizontal = 16.dp))
}

/** Hueco al final de una lista para que no la tapen la barra de pestañas ni el mini reproductor. */
@Composable
fun BottomSpacer(extra: Dp = 0.dp) {
    Spacer(Modifier.height(LocalBottomInset.current + extra))
}

@Composable
fun ProvideApp(app: AppState, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalApp provides app, content = content)
}
