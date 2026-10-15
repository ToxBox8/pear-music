package app.libremusic.ui


import app.libremusic.L
import app.libremusic.data.Ficha
import app.libremusic.data.Incident
import app.libremusic.playback.PlaylistWidget
import app.libremusic.playback.RecentsWidget
import app.libremusic.data.Telemetry
import app.libremusic.data.Updates
import app.libremusic.avisos.AvisosRepo
import androidx.compose.runtime.snapshotFlow
import app.libremusic.ui.theme.rememberSettingsTop
import app.libremusic.data.AppShortcuts
import app.libremusic.data.TabOrder
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Subscriptions
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.animation.core.spring
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import app.libremusic.ui.simpbar.FoldStyle
import app.libremusic.ui.simpbar.GlassBottomBar
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewmodel.compose.viewModel
import app.libremusic.jam.JamScreen
import app.libremusic.reels.ReelsScreen
import app.libremusic.reels.ReelsViewModel
import app.libremusic.ui.theme.DeckStyle
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.LocalReduceMotion
import app.libremusic.ui.theme.LocalScreenVisible
import app.libremusic.ui.theme.Prefs
import app.libremusic.ui.theme.ThemeEngine
import app.libremusic.ui.theme.Tokens
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.material
import app.libremusic.ui.theme.semibold
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** Raíz de la app: pestañas, mini reproductor, reproductor completo y hojas (RootView en iOS). */
@Composable
fun LibreMusicApp(jamCode: String?, onDismissJam: () -> Unit, onBarsDark: (Boolean) -> Unit = {}) {
    val start = remember {
        TabOrder.run { start(Prefs.lastTab, visible(Prefs.tabOrder.value, Prefs.searchPlacement.value == "tab")) }
    }
    LibreMusicRoot(remember { AppState().apply { tab = Tab.of(start) } }, viewModel(), viewModel(), viewModel(), viewModel(), jamCode, onDismissJam, onBarsDark)
}

/** La app con sus ViewModels ya creados (las capturas de pantalla pasan los suyos). */
@Composable
fun LibreMusicRoot(
    app: AppState,
    playerVm: PlayerViewModel,
    libraryVm: LibraryViewModel,
    homeVm: HomeViewModel,
    reelsVm: ReelsViewModel,
    jamCode: String? = null,
    onDismissJam: () -> Unit = {},
    onBarsDark: (Boolean) -> Unit = {},
    forceReduceMotion: Boolean? = null,
) {
    val context = LocalContext.current
    val player by playerVm.state.collectAsState()
    val searchPlacement by Prefs.searchPlacement.collectAsState()
    val deck by Prefs.deck.collectAsState()
    val liquidGlass by Prefs.liquidGlass.collectAsState()
    val glassSource = rememberGlassSource()
    val glass = if (liquidGlass && glassSupported) glassSource else null

    // «Reducir movimiento»: con las animaciones del sistema desactivadas se paran fondos y efectos.
    val reduceMotion = forceReduceMotion ?: remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }

    LaunchedEffect(player.current?.id) { ThemeEngine.update(context, player.current) }
    LaunchedEffect(jamCode) { if (jamCode != null) app.showJam = true }
    LaunchedEffect(app.toast) { if (app.toast != null) { delay(2600); app.toast = null } }

    val tabOrder by Prefs.tabOrder.collectAsState()
    val barStyle by Prefs.barStyle.collectAsState()
    // Barra estilo SimpMusic: en la cápsula van tus pestañas sin Buscar (es un círculo aparte). Ajustes puede ir en
    // la barra o arriba en Inicio, junto al Jam (Ajustes › Aspecto; por defecto arriba con esta barra y en la barra
    // con la clásica). Lo que no está en la barra sigue montado para conservar su pila.
    val simpBar = barStyle == "simpmusic"
    val settingsTop = rememberSettingsTop()
    val showDiscover by Prefs.showDiscover.collectAsState()
    val tabs = TabOrder.visible(tabOrder, !simpBar && searchPlacement == "tab", showDiscover).map(Tab::of)
        .filter { !(settingsTop && it == Tab.Settings) }
    // Descubrir apagado mientras se estaba en ella: a Inicio.
    LaunchedEffect(showDiscover) { if (!showDiscover && app.tab == Tab.Discover) app.tab = Tab.Home }
    val shownTabs = (tabs + listOfNotNull(Tab.Search.takeIf { simpBar }, Tab.Settings.takeIf { settingsTop })).distinct()
    LaunchedEffect(searchPlacement, simpBar) { if (!simpBar && app.tab == Tab.Search && searchPlacement != "tab") app.tab = Tab.Home }
    // Deslizar entre pestañas: estado compartido entre el contenido y las barras (ver TabPager).
    val pager = remember { TabPager() }
    // Plegada al bajar por una lista; se despliega al subir, al cambiar de pestaña o tocando el círculo.
    var barCollapsed by remember { mutableStateOf(false) }
    // Vidrio de Kyant (como Open Menus): necesita Android 13 (shaders de GPU); antes, la barra plana con el mismo
    // movimiento. El fondo pinta el color del tema y luego las pantallas.
    val simpGlass = simpBar && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU
    val bgColor = Libre.colors.background
    val simpBackdrop = rememberLayerBackdrop { drawRect(bgColor); drawContent() }
    LaunchedEffect(app.tab, simpBar) { barCollapsed = false }
    val collapseOnScroll = remember {
        object : androidx.compose.ui.input.nestedscroll.NestedScrollConnection {
            override fun onPostScroll(consumed: Offset, available: Offset, source: androidx.compose.ui.input.nestedscroll.NestedScrollSource): Offset {
                // Como SimpMusic: desplegada sólo con la lista arriba del todo (!canScrollBackward). Bajar la pliega;
                // si al subir sobra recorrido, la lista ha llegado arriba.
                if (consumed.y < 0f) barCollapsed = true
                if (available.y > 0f) barCollapsed = false
                return Offset.Zero
            }
        }
    }
    // Atrás desde Buscar o Ajustes cuando no están en la barra vuelve a la última pestaña de la barra.
    var lastBarTab by remember { mutableStateOf(Tab.Home) }
    LaunchedEffect(app.tab, tabs) { if (app.tab in tabs) lastBarTab = app.tab }
    androidx.activity.compose.BackHandler(enabled = app.tab !in tabs) { app.tab = lastBarTab }
    // La app vuelve a abrirse en la última pestaña usada.
    LaunchedEffect(app.tab) { Prefs.setLastTab(app.tab.key) }
    // Atajos del icono de la app (mantener pulsado) y del Asistente.
    // Widgets de recientes y de playlist: se redibujan al cambiar lo que enseñan.
    val libForWidgets by libraryVm.data.collectAsState()
    LaunchedEffect(libForWidgets.recents.take(4).map { it.id }, libForWidgets.playlists.map { it.id to it.pinned }) {
        RecentsWidget.render(context.applicationContext)
        PlaylistWidget.render(context.applicationContext)
    }
    // Widgets: reproducir una playlist fijada o una canción reciente.
    val play by AppShortcuts.pendingPlay.collectAsState()
    LaunchedEffect(play) {
        val (type, id) = play ?: return@LaunchedEffect
        AppShortcuts.pendingPlay.value = null
        val lib = libraryVm.data.value
        when (type) {
            "playlist" -> lib.playlists.firstOrNull { it.id == id }?.songs?.takeIf { it.isNotEmpty() }?.let { playerVm.play(it, 0) }
            "song" -> lib.recents.indexOfFirst { it.id == id }.takeIf { it >= 0 }?.let { playerVm.play(lib.recents, it) }
        }
    }
    val shortcut by AppShortcuts.pending.collectAsState()
    val libData by libraryVm.data.collectAsState()
    val downloadedNow by libraryVm.downloadedSongs.collectAsState()
    LaunchedEffect(shortcut) {
        val k = shortcut ?: return@LaunchedEffect
        AppShortcuts.pending.value = null
        when (k) {
            AppShortcuts.Kind.Favorites ->
                if (libData.favorites.isEmpty()) app.toast = L("Aún no hay favoritas") else playerVm.play(libData.favorites.shuffled())
            AppShortcuts.Kind.Downloads ->
                if (downloadedNow.isEmpty()) app.toast = L("Aún no hay nada descargado") else playerVm.play(downloadedNow.shuffled())
            AppShortcuts.Kind.Discover -> app.tab = Tab.Discover
            AppShortcuts.Kind.Search -> app.tab = if (simpBar || searchPlacement == "tab") Tab.Search else Tab.Home
        }
    }

    // Cada vez que la app pasa a primer plano se bajan los avisos (como Open Menus): la campana de Inicio sale al día
    // sin esperar a la comprobación de fondo de cada 15 min. Lo que ya se ve en la app no se notifica después.
    val avisosScope = rememberCoroutineScope()
    // Telemetría: sólo con consentimiento (Telemetry.kt); mide mientras la app está a la vista.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { Telemetry.onForeground(context.applicationContext) }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { avisosScope.launch { Telemetry.onBackground(context.applicationContext) } }
    LifecycleEventEffect(Lifecycle.Event.ON_START) {
        // Estado de incidencias firmado (Fase 4): al abrir; sin red, se queda el último válido.
        avisosScope.launch { Incident.refresh(context.applicationContext) }
        avisosScope.launch { AvisosRepo.refrescarAlAbrir(context.applicationContext) }
        // Instalaciones activas: un contador por versión, una vez al día y sin identificadores.
        avisosScope.launch {
            Ficha.pingActive(context.applicationContext)
            Ficha.reportDecision(context.applicationContext)
        }
        // Versión nueva (sólo la variante pública, como mucho cada 6 h): novedades, «Descargar» o «Recordarme mañana».
        avisosScope.launch {
            val release = Updates.check(context.applicationContext) ?: return@launch
            app.alert = AlertSpec(
                L("Pear Music {0}", release.version) + if (release.title.isNotBlank()) ": ${release.title}" else "",
                release.highlights.joinToString("\n") { "• $it" } +
                    L("\n\nSe actualiza encima: no pierdes tu biblioteca ni tus canciones descargadas."),
                buttons = listOf(
                    AlertButton(L("Descargar")) {
                        avisosScope.launch {
                            app.toast = L("Descargando Pear Music {0}…", release.version)
                            // Progreso en el mismo aviso, de 10 en 10 para no redibujar en cada bloque.
                            var shown = -1
                            val (apk, error) = Updates.download(context.applicationContext, release) { pct ->
                                val step = pct / 10 * 10
                                if (step != shown) {
                                    shown = step
                                    app.toast = L("Descargando Pear Music {0}… {1} %", release.version, step)
                                }
                            }
                            if (apk == null) app.toast = error
                            else if (!Updates.install(context, apk)) {
                                app.toast = L("Permite instalar apps de Pear Music y vuelve a pulsar Descargar.")
                            }
                        }
                    },
                    AlertButton(L("Recordarme mañana"), AlertButton.Role.Cancel) {
                        Updates.snooze(context.applicationContext, release)
                    },
                ),
            )
        }
    }

    // Pulsar una notificación de aviso abre Avisos (también con la app ya abierta).
    val abrirAvisos by AvisosRepo.abrir.collectAsState()
    LaunchedEffect(abrirAvisos) {
        if (!abrirAvisos) return@LaunchedEffect
        AvisosRepo.abrir.value = false
        app.showPlayer = false
        app.push(Route.Avisos)
    }

    val barsDark = Libre.colors.dark || (app.tab == Tab.Discover && !app.showPlayer)
    LaunchedEffect(barsDark) { onBarsDark(barsDark) }

    val landscape = LocalConfiguration.current.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
    val immersive = landscape && player.current != null && deck.isObject

    CompositionLocalProvider(LocalReduceMotion provides reduceMotion, LocalGlass provides glass) {
        ProvideApp(app) {
            val env = ScreenEnv(app, playerVm, libraryVm, homeVm)
            FirstStepsWatcher(env)
            CompositionLocalProvider(LocalEnv provides env) {
                Box(Modifier.fillMaxSize().background(Libre.colors.background)) {
                    // Atrás dentro de una pestaña: lo gestiona TabStack (gesto del sistema con vista previa).

                    val hasMini = player.current != null
                    val bottomInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() +
                        (if (simpBar) (if (hasMini) 64.dp + 12.dp + 56.dp else 64.dp) else if (hasMini) 62.dp + 48.dp + 8.dp else 62.dp) + 20.dp
                    CompositionLocalProvider(LocalBottomInset provides bottomInset) {
                      // Deslizar a los lados cambia de pestaña (como Instagram). Lo que esté dentro y se
                      // arrastre en horizontal (carruseles, filas que se deslizan, «atrás» de una pila)
                      // tiene prioridad: si ya se ha quedado el arrastre, no se cambia de pestaña.
                      //
                      // Fluidez (0.9.4): el desplazamiento es un estado que se lee sólo al dibujar (no recompone las
                      // pantallas ni lanza una corrutina por evento), al soltar sigue un muelle con la velocidad del
                      // dedo, un toque a mitad de animación la atrapa, y las barras siguen al dedo vía [pager].
                      var contentWidth by remember { mutableStateOf(1f) }
                      val swipeScope = rememberCoroutineScope()
                      val swipeEnabled = !app.showPlayer && !app.showJam && app.editing == null && !app.showImport && app.tab in tabs
                      LaunchedEffect(tabs, app.tab) { pager.index = tabs.indexOf(app.tab) }
                      // Con el cristal líquido, las pantallas se graban para que el cristal las refracte.
                      Box(
                          Modifier
                              .fillMaxSize()
                              .onSizeChanged { contentWidth = it.width.toFloat().coerceAtLeast(1f); pager.width = contentWidth }
                              .pointerInput(tabs, swipeEnabled) {
                                  if (!swipeEnabled) return@pointerInput
                                  awaitEachGesture {
                                      val down = awaitFirstDown(requireUnconsumed = false)
                                      // Atrapar: si la animación anterior iba a otra pestaña, se da por hecha y el
                                      // dedo sigue desde donde está la pantalla.
                                      pager.catchSettle { target -> app.tab = target }
                                      val tracker = androidx.compose.ui.input.pointer.util.VelocityTracker()
                                      var dx = 0f
                                      var dy = 0f
                                      var claimed = pager.offset != 0f
                                      while (true) {
                                          val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                                          if (!change.pressed) break
                                          val d = change.positionChange()
                                          if (!claimed) {
                                              if (change.isConsumed) return@awaitEachGesture
                                              dx += d.x
                                              dy += d.y
                                              val slop = viewConfiguration.touchSlop
                                              if (kotlin.math.abs(dx) > slop || kotlin.math.abs(dy) > slop) {
                                                  if (!isHorizontal(dx, dy, slop)) return@awaitEachGesture
                                                  claimed = true
                                              }
                                          }
                                          if (claimed) {
                                              change.consume()
                                              tracker.addPosition(change.uptimeMillis, change.position)
                                              pager.dragBy(d.x, tabs)
                                          }
                                      }
                                      if (!claimed) return@awaitEachGesture
                                      val v = tracker.calculateVelocity().x
                                      pager.settle(swipeScope, v, density, reduceMotion, tabs) { target -> app.tab = target }
                                  }
                              }
                              .then(if (simpBar) Modifier.nestedScroll(collapseOnScroll) else Modifier)
                              .then(if (simpGlass) Modifier.layerBackdrop(simpBackdrop) else Modifier)
                              .then(if (glass != null) Modifier.glassSource(glass) else Modifier),
                      ) {
                      CompositionLocalProvider(LocalInsideGlassSource provides (glass != null)) {
                        // Las pestañas se conservan montadas para no perder el desplazamiento ni la pila. Su posición
                        // se calcula al dibujar: arrastrar no recompone ni vuelve a medir ninguna pantalla, y las que
                        // no se ven quedan lejos y transparentes (tampoco reciben toques).
                        shownTabs.forEach { t ->
                            val active = app.tab == t
                            Box(
                                Modifier
                                    .fillMaxSize()
                                    .graphicsLayer {
                                        val x = pager.screenX(t, app.tab, tabs)
                                        alpha = if (x == null) 0f else 1f
                                        translationX = x ?: 100_000f
                                    },
                            ) {
                                CompositionLocalProvider(LocalScreenVisible provides (active && !app.showPlayer)) {
                                when (t) {
                                    Tab.Home -> TabStack(t, { HomeScreen() }) { RouteScreen(it) }
                                    Tab.Discover -> ReelsScreen(reelsVm, playerVm, libraryVm, visible = active && !app.showPlayer)
                                    Tab.Search -> TabStack(t, { SearchTabScreen() }) { RouteScreen(it) }
                                    Tab.Library -> TabStack(t, { LibraryScreen() }) { RouteScreen(it) }
                                    Tab.Settings -> TabStack(t, { SettingsScreen() }) { RouteScreen(it) }
                                }
                                }
                            }
                        }
                      }
                      }
                    }

                    // Barra inferior: mini reproductor (accesorio) y pestañas, flotando como en iOS 26.
                    // En horizontal no pasa de 520 dp y queda centrada, como en el iPhone (si no,
                    // ocupaba todo el ancho y tapaba la lista).
                    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
                    if (simpBar) {
                        val libNow by libraryVm.data.collectAsState()
                        val song = player.current
                        GlassBottomBar(
                            foldStyle = FoldStyle.V220,
                            barTabs = tabs, selected = app.tab, onSelect = { app.select(it) },
                            isScrolledToTop = !barCollapsed, backdrop = simpBackdrop, glass = simpGlass,
                            follow = pager::position,
                            nowPlaying = song, isPlaying = player.isPlaying, onTogglePlay = { playerVm.togglePlay() },
                            isLiked = song != null && libNow.favorites.any { it.id == song.id },
                            onToggleLike = { song?.let { libraryVm.toggleFavorite(it) } },
                            onOpenPlayer = { app.showPlayer = true },
                            modifier = Modifier.align(Alignment.BottomCenter).widthIn(max = 520.dp),
                        )
                    } else Column(
                        Modifier.align(Alignment.BottomCenter).widthIn(max = 520.dp).padding(horizontal = 21.dp).padding(bottom = maxOf(navBottom - 13.dp, 8.dp)),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        AnimatedVisibility(hasMini, enter = fadeIn() + slideInVertically { it / 2 }, exit = fadeOut() + slideOutVertically { it / 2 }) {
                            MiniPlayerAccessory(onOpen = { app.showPlayer = true })
                        }
                        if (glass != null) LiquidTabBar(tabs, app.tab, dark = app.tab == Tab.Discover, follow = pager::position) { app.select(it) }
                        else TabBar(tabs, app.tab, dark = app.tab == Tab.Discover, follow = pager::position) { app.select(it) }
                    }

                    // Reproductor completo como hoja.
                    Sheet(visible = app.showPlayer, onDismiss = { app.showPlayer = false }, full = true) {
                        PlayerScreen(onClose = { app.showPlayer = false })
                    }
                    Sheet(visible = app.showJam, onDismiss = { app.showJam = false; onDismissJam() }) {
                        JamScreen(playerVm, libraryVm, initialCode = jamCode, onClose = { app.showJam = false; onDismissJam() })
                    }
                    Sheet(visible = app.editing != null, onDismiss = { app.editing = null }) {
                        app.editing?.let { PlaylistEditor(it, onDone = { app.editing = null }) }
                    }
                    Sheet(visible = app.showImport, onDismiss = { app.showImport = false }) {
                        ImportScreen(onDone = { app.showImport = false })
                    }

                    if (immersive) ImmersiveDeck(deck)

                    // Bienvenida (también desde Ajustes › Ayuda y soporte). Quien ya usaba la app antes de la 1.0 sólo ve la
                    // pantalla de privacidad, una vez. Después: recorrido sobre la app → historias → (cuenta, si la pidió).
                    val onboarded by Prefs.onboarded.collectAsState()
                    val termsAccepted by Prefs.termsAccepted.collectAsState()
                    val introStage by Prefs.introStage.collectAsState()
                    androidx.compose.animation.AnimatedVisibility(
                        !onboarded || !termsAccepted, enter = androidx.compose.animation.fadeIn(uiEaseOut(250)), exit = androidx.compose.animation.fadeOut(uiEaseOut(250)),
                    ) {
                        val privacyOnly = onboarded && !termsAccepted
                        OnboardingScreen(privacyOnly = privacyOnly, onDone = {
                            if (privacyOnly) {
                                if (Prefs.openAccountAfterIntro) { Prefs.openAccountAfterIntro = false; app.tab = Tab.Settings; app.push(Route.AccountR) }
                            } else {
                                Prefs.setOnboarded(true)
                                Prefs.setIntroStage("tour")
                            }
                        })
                    }
                    if (onboarded && termsAccepted && introStage == "tour") TourOverlay(onDone = { Prefs.setIntroStage("stories") })
                    androidx.compose.animation.AnimatedVisibility(
                        onboarded && termsAccepted && introStage == "stories",
                        enter = androidx.compose.animation.fadeIn(uiEaseOut(300)), exit = androidx.compose.animation.fadeOut(uiEaseOut(250)),
                    ) {
                        StoriesScreen(onDone = {
                            Prefs.setIntroStage("")
                            if (Prefs.openAccountAfterIntro) { Prefs.openAccountAfterIntro = false; app.tab = Tab.Settings; app.push(Route.AccountR) }
                        })
                    }

                    // Novedades tras actualizar (1.1): una vez por versión, sin poder cerrarlo sin elegir.
                    val whatsNewSeen by Prefs.whatsNewSeen.collectAsState()
                    androidx.compose.animation.AnimatedVisibility(
                        onboarded && termsAccepted && introStage.isEmpty() && app.guide == null && whatsNewSeen != WhatsNew.current,
                        enter = androidx.compose.animation.fadeIn(uiEaseOut(300)), exit = androidx.compose.animation.fadeOut(uiEaseOut(250)),
                    ) {
                        WhatsNewScreen(
                            onTour = { Prefs.setWhatsNewSeen(WhatsNew.current); app.guide = "whatsnew" },
                            onClose = { Prefs.setWhatsNewSeen(WhatsNew.current) },
                        )
                    }
                    // Guía de Ajustes (botón junto a la carta) y recorrido de lo nuevo: pasos con «Siguiente».
                    app.guide?.let { g ->
                        androidx.compose.runtime.key(g) {
                            TourOverlay(steps = if (g == "settings") settingsGuideSteps else whatsNewSteps, guided = true, onDone = {
                                app.guide = null
                                app.openSettings()
                            })
                        }
                    }

                    // Estado de incidencias (Fase 4): aviso o modo seguro arriba; bloqueo total a pantalla completa.
                    IncidentOverlay()

                    app.alert?.let { AlertHost(it, onDismiss = { app.alert = null }) }
                    Toast(app.toast)
                }
            }
        }
    }
}

/** Lo que casi todas las pantallas necesitan, sin pasarlo de una a otra. */
class ScreenEnv(val app: AppState, val player: PlayerViewModel, val library: LibraryViewModel, val home: HomeViewModel)

val LocalEnv = androidx.compose.runtime.staticCompositionLocalOf<ScreenEnv> { error("Sin ScreenEnv") }

/** Pantalla de una ruta apilada. */
@Composable
fun RouteScreen(route: Route) {
    when (route) {
        is Route.Collection -> CollectionScreen(route.collection)
        is Route.Discography -> DiscographyScreen(route)
        is Route.PlaylistR -> PlaylistDetailScreen(route.id)
        is Route.Smart -> SmartListScreen(route.kind)
        is Route.Songs -> SongListScreen(route.title, route.songs)
        Route.AllSongs -> AllSongsScreen()
        Route.Recents -> RecentsScreen()
        Route.Stats -> StatsScreen()
        is Route.PendingImport -> PendingImportScreen(route.playlistId)
        Route.Artists -> ArtistsScreen()
        is Route.Artist -> ArtistScreen(route.name)
        is Route.RemoteArtistR -> RemoteArtistScreen(route.artist)
        Route.Playlists -> PlaylistsListScreen()
        Route.Albums -> AlbumsScreen()
        Route.ArtworkColors -> ArtworkColorsScreen()
        Route.TabOrderR -> TabOrderScreen()
        Route.DownloadsSettings -> DownloadsSettingsScreen()
        Route.Help -> HelpScreen()
        Route.MyData -> MyDataScreen()
        Route.AccountR -> AccountScreen()
        Route.Personalization -> PersonalizationScreen()
        Route.Admin -> AdminScreen()
        is Route.Support -> SupportScreen(route.draftId)
        is Route.Suggest -> SupportScreen(route.draftId, suggestion = true)
        Route.Language -> SettingsPage(L("Idioma")) {
            Text(L("Toda la app cambia al momento. Lo que aún no está traducido se ve en español."), style = app.libremusic.ui.theme.Typo.footnote, color = app.libremusic.ui.theme.Libre.colors.secondaryLabel, modifier = Modifier.padding(start = 32.dp, end = 32.dp, top = 8.dp))
            LanguagePicker()
        }
        Route.SupportDrafts -> SupportDraftsScreen()
        Route.Appearance -> AppearanceScreen()
        Route.ThemePicker -> ThemePickerScreen()
        Route.PlayerPicker -> PlayerPickerScreen()
        Route.LibraryOptions -> LibraryOptionsScreen()
        Route.SearchOptions -> SearchOptionsScreen()
        Route.Audio -> AudioScreen()
        Route.About -> AboutScreen()
        Route.ManagePlaylists -> ManagePlaylistsScreen()
        Route.ReorderPlaylists -> ReorderPlaylistsScreen()
        Route.Avisos -> AvisosScreen()
    }
}

// MARK: Barra de pestañas ------------------------------------------------------------------------

internal fun Tab.icon(): ImageVector = when (this) {
    Tab.Home -> Icons.Rounded.Home
    Tab.Discover -> Icons.Rounded.Subscriptions
    Tab.Search -> Icons.Rounded.Search
    Tab.Library -> Icons.Rounded.LibraryMusic
    Tab.Settings -> Icons.Rounded.Settings
}

/** Barra de pestañas flotante de cristal (iOS 26). En Descubrir se oscurece, como en iOS. */
@Composable
private fun TabBar(tabs: List<Tab>, selected: Tab, dark: Boolean, follow: () -> Float? = { null }, onSelect: (Tab) -> Unit) {
    val c = Libre.colors
    val isDark = dark || c.dark
    val shape = RoundedCornerShape(31.dp)
    val reduce = LocalReduceMotion.current
    val selIndex = tabs.indexOf(selected)
    // Una sola píldora que se desliza: sigue al dedo al deslizar entre pestañas y va a la nueva al tocar.
    val pillPos = remember { Animatable(selIndex.toFloat()) }
    LaunchedEffect(Unit) { snapshotFlow { follow() }.collect { p -> if (p != null) pillPos.snapTo(p.coerceIn(0f, tabs.lastIndex.toFloat())) } }
    LaunchedEffect(selIndex) {
        if (selIndex < 0) return@LaunchedEffect
        if (reduce) pillPos.snapTo(selIndex.toFloat()) else pillPos.animateTo(selIndex.toFloat(), spring(dampingRatio = 0.85f, stiffness = 500f))
    }
    val highlight by remember(selIndex) { derivedStateOf { follow()?.roundToInt() ?: selIndex } }
    val pill = if (isDark) Color.White.copy(0.1f) else Color.Black.copy(0.06f)
    Row(
        Modifier
            .fillMaxWidth()
            .height(62.dp)
            .clip(shape)
            .background(if (dark) Color(0xEB0E0E10) else material(c.dark, thick = true))
            .border(0.5.dp, Color.White.copy(alpha = if (isDark) 0.12f else 0.6f), shape)
            .drawBehind {
                if (selIndex < 0 && follow() == null) return@drawBehind
                val pad = 8.dp.toPx()
                val extra = 5.dp.toPx()
                val itemW = (size.width - 2 * pad) / tabs.size
                val h = 54.dp.toPx()
                drawRoundRect(
                    pill, Offset(pad + itemW * pillPos.value - extra, (size.height - h) / 2), Size(itemW + 2 * extra, h), CornerRadius(h / 2),
                )
            }
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        tabs.forEachIndexed { i, t ->
            val on = i == highlight
            val tint = if (on) (if (dark && c.theme == app.libremusic.ui.theme.AppTheme.Air) Color.White else c.accent)
            else if (isDark) Color.White.copy(alpha = 0.85f) else c.label
            Column(
                Modifier
                    .weight(1f)
                    .height(54.dp)
                    .tourTarget("tab:${t.key}")
                    .tactile(label = t.title) { onSelect(t) },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                // Los SF Symbols de la barra miden ~25 pt; el glifo de Material ocupa ~3/4 de su caja.
                Icon(t.icon(), null, tint = tint, modifier = Modifier.size(32.dp))
                Text(t.title, style = Typo.caption2.copy(fontSize = 10.sp, fontWeight = FontWeight.SemiBold), color = tint, maxLines = 1)
            }
        }
    }
}

/**
 * Barra de pestañas de cristal líquido (iOS 26): al tocar o arrastrar, la pestaña elegida se
 * convierte en una gota de cristal que sigue al dedo, amplía lo que tiene debajo y, al soltar,
 * se posa con rebote en la pestaña nueva.
 */
@Composable
private fun LiquidTabBar(tabs: List<Tab>, selected: Tab, dark: Boolean, follow: () -> Float? = { null }, onSelect: (Tab) -> Unit) {
    val c = Libre.colors
    val isDark = dark || c.dark
    val source = LocalGlass.current ?: return TabBar(tabs, selected, dark, follow, onSelect)
    val reduce = LocalReduceMotion.current
    val scope = rememberCoroutineScope()
    val contentLayer = androidx.compose.ui.graphics.rememberGraphicsLayer()
    val dropLayer = androidx.compose.ui.graphics.rememberGraphicsLayer()
    val shader = rememberLensShader()
    var barOrigin by remember { mutableStateOf(Offset.Zero) }
    var barWidth by remember { mutableStateOf(0f) }
    val density = LocalDensity.current
    val padH = with(density) { 8.dp.toPx() }
    // -1 si la pestaña actual no está en la barra (Ajustes arriba en Inicio): no se marca ninguna. Antes se tomaba
    // la 0 y, estando en Ajustes, la barra clásica marcaba Descubrir (1.1).
    val selIndex = tabs.indexOf(selected)
    val x = remember { Animatable(-1f) }
    val lift = remember { Animatable(0f) }

    fun tabWidth() = (barWidth - 2 * padH) / tabs.size
    fun center(i: Int) = padH + tabWidth() * (i + 0.5f)
    fun nearest(px: Float) = ((px - padH) / tabWidth()).toInt().coerceIn(0, tabs.lastIndex)

    LaunchedEffect(selIndex, barWidth, tabs.size) {
        if (barWidth <= 0f || selIndex < 0) return@LaunchedEffect
        if (x.value < 0f || reduce) x.snapTo(center(selIndex))
        else if (lift.value == 0f) x.animateTo(center(selIndex), spring(dampingRatio = 0.7f, stiffness = 380f))
    }
    // Al deslizar entre pestañas, la píldora sigue al dedo (sin levantar la gota, que es del toque en la barra).
    LaunchedEffect(Unit) {
        snapshotFlow { follow() }.collect { p ->
            if (p != null && barWidth > 0f && lift.value == 0f) {
                val i = p.coerceIn(0f, tabs.lastIndex.toFloat())
                x.snapTo(padH + tabWidth() * (i + 0.5f))
            }
        }
    }
    // derivedStateOf: la gota se mueve en cada fotograma, pero la barra sólo se recompone cuando cambia la pestaña
    // resaltada (antes se recomponía entera en cada fotograma de la animación).
    val highlight by remember(selIndex, tabs.size) {
        derivedStateOf {
            val p = follow()
            when {
                p != null -> p.roundToInt().coerceIn(0, tabs.lastIndex)
                lift.value > 0.05f && barWidth > 0f && x.value >= 0f -> nearest(x.value)
                else -> selIndex
            }
        }
    }
    val pill = if (isDark) Color.White.copy(0.1f) else Color.Black.copy(0.06f)
    val shape = RoundedCornerShape(31.dp)

    Row(
        Modifier
            .fillMaxWidth()
            .height(62.dp)
            .onGloballyPositioned { barOrigin = it.positionOnScreen(); barWidth = it.size.width.toFloat() }
            .liquidGlass(shape, isDark, GlassStyle.Bar, tint = if (dark) Color(0x800E0E10) else Color.Unspecified)
            .drawWithContent {
                val cx = x.value
                val pillW = tabWidth() + 10.dp.toPx()
                val pillH = 54.dp.toPx()
                if (cx >= 0f && (selIndex >= 0 || lift.value > 0f)) {
                    drawRoundRect(
                        pill.copy(alpha = pill.alpha * (1f - lift.value).coerceIn(0f, 1f)),
                        Offset(cx - pillW / 2, (size.height - pillH) / 2), Size(pillW, pillH), CornerRadius(pillH / 2),
                    )
                }
                contentLayer.record { this@drawWithContent.drawContent() }
                drawLayer(contentLayer)
                if (lift.value > 0.01f && cx >= 0f) {
                    val w = pillW * (1f + 0.22f * lift.value)
                    val h = pillH * (1f + 0.34f * lift.value)
                    drawGlassDrop(
                        dropLayer, source, barOrigin, contentLayer,
                        androidx.compose.ui.geometry.Rect(Offset(cx - w / 2, size.height / 2 - h / 2), Size(w, h)),
                        lift.value, isDark, shader,
                    )
                }
            }
            .pointerInput(tabs) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    if (barWidth <= 0f) return@awaitEachGesture
                    val clampX = { px: Float -> px.coerceIn(center(0), center(tabs.lastIndex)) }
                    var lastX = down.position.x
                    scope.launch { lift.animateTo(1f, if (reduce) tween(120) else spring(dampingRatio = 0.55f, stiffness = 420f)) }
                    scope.launch { x.animateTo(clampX(lastX), if (reduce) tween(120) else spring(dampingRatio = 0.75f, stiffness = 600f)) }
                    var dragging = false
                    while (true) {
                        val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) { change.consume(); break }
                        if ((change.position - down.position).getDistance() > viewConfiguration.touchSlop) dragging = true
                        if (dragging) {
                            change.consume()
                            lastX = change.position.x
                            scope.launch { x.snapTo(clampX(lastX)) }
                        }
                    }
                    val target = nearest(clampX(lastX))
                    onSelect(tabs[target])
                    scope.launch { x.animateTo(center(target), if (reduce) tween(160) else spring(dampingRatio = 0.55f, stiffness = 380f)) }
                    scope.launch { lift.animateTo(0f, if (reduce) tween(160) else spring(dampingRatio = 0.8f, stiffness = 300f)) }
                }
            }
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        tabs.forEachIndexed { i, t ->
            val on = i == highlight
            val isSelected = t == selected
            val tint = if (on) (if (dark && c.theme == app.libremusic.ui.theme.AppTheme.Air) Color.White else c.accent)
            else if (isDark) Color.White.copy(alpha = 0.85f) else c.label
            Column(
                Modifier
                    .weight(1f)
                    .height(54.dp)
                    .tourTarget("tab:${t.key}")
                    .semantics { role = Role.Tab; this.selected = isSelected; contentDescription = t.title; onClick(label = null) { onSelect(t); true } },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(t.icon(), null, tint = tint, modifier = Modifier.size(32.dp))
                Text(t.title, style = Typo.caption2.copy(fontSize = 10.sp, fontWeight = FontWeight.SemiBold), color = tint, maxLines = 1)
            }
        }
    }
}

// MARK: Hojas ------------------------------------------------------------------------------------

/** Hoja que sube desde abajo y se cierra arrastrándola (sheet de iOS). */
@Composable
fun Sheet(visible: Boolean, onDismiss: () -> Unit, full: Boolean = false, content: @Composable () -> Unit) {
    val c = Libre.colors
    val density = LocalDensity.current
    val drag = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val dim by animateFloatAsState(if (visible) 0.35f else 0f, tween(300), label = "dim")
    if (dim > 0f) {
        Box(
            Modifier.fillMaxSize().background(Color.Black.copy(alpha = dim))
                .clickable(remember { MutableInteractionSource() }, null) { onDismiss() },
        )
    }
    AnimatedVisibility(
        visible,
        enter = slideInVertically(tween(420, easing = UiEaseOut)) { it },
        exit = slideOutVertically(tween(320, easing = UiEaseOut)) { it },
    ) {
        BackHandler { onDismiss() }
        LaunchedEffect(Unit) { drag.snapTo(0f) }
        val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
        Box(
            Modifier
                .fillMaxSize()
                .padding(top = top)
                .offset { IntOffset(0, drag.value.roundToInt()) }
                .clip(RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp))
                .background(c.background)
                .pointerInput(Unit) {
                    detectVerticalDragGestures(
                        onVerticalDrag = { change, dy ->
                            if (drag.value + dy >= 0f) {
                                change.consume()
                                scope.launch { drag.snapTo(drag.value + dy) }
                            }
                        },
                        onDragEnd = {
                            scope.launch {
                                if (drag.value > with(density) { 140.dp.toPx() }) onDismiss() else drag.animateTo(0f, tween(250, easing = UiEaseOut))
                            }
                        },
                    )
                },
        ) {
            // Sin asa: en iOS la dibuja el reproductor clásico (PlayerScreen) y las demás hojas no la tienen.
            content()
        }
    }
}

// MARK: Avisos -----------------------------------------------------------------------------------

/** UIAlertController: título, mensaje, campo de texto opcional y botones. */
@Composable
private fun AlertHost(spec: AlertSpec, onDismiss: () -> Unit) {
    val c = Libre.colors
    var text by remember(spec) { mutableStateOf(spec.fieldInitial) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val glass = LocalGlass.current != null
        val shape = RoundedCornerShape(if (glass) 30.dp else 14.dp)
        Column(
            Modifier.widthIn(max = 280.dp)
                .then(if (glass) Modifier.liquidGlass(shape, c.dark, GlassStyle.Menu).clip(shape) else Modifier.clip(shape).background(material(c.dark, thick = true))),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.padding(16.dp, 19.dp, 16.dp, 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(spec.title, style = Typo.headline, color = c.label, textAlign = TextAlign.Center)
                spec.message?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(it, style = Typo.footnote, color = c.label, textAlign = TextAlign.Center)
                }
                if (spec.field != null) {
                    Spacer(Modifier.height(14.dp))
                    Box(
                        Modifier.fillMaxWidth().background(c.background, RoundedCornerShape(7.dp))
                            .border(0.5.dp, c.separator, RoundedCornerShape(7.dp)).padding(8.dp, 7.dp),
                    ) {
                        if (text.isEmpty()) Text(spec.field, style = Typo.subheadline, color = c.tertiaryLabel)
                        BasicTextField(
                            text, { text = it }, singleLine = true, textStyle = Typo.subheadline.copy(color = c.label),
                            cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
            Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.separator))
            val horizontal = spec.buttons.size == 2
            if (horizontal) {
                Row(Modifier.fillMaxWidth().height(44.dp)) {
                    spec.buttons.forEachIndexed { i, b ->
                        if (i > 0) Box(Modifier.width(0.5.dp).height(44.dp).background(c.separator))
                        AlertButtonView(b, Modifier.weight(1f)) { onDismiss(); b.onClick(text) }
                    }
                }
            } else {
                spec.buttons.forEachIndexed { i, b ->
                    if (i > 0) Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.separator))
                    AlertButtonView(b, Modifier.fillMaxWidth()) { onDismiss(); b.onClick(text) }
                }
            }
        }
    }
}

@Composable
private fun AlertButtonView(b: AlertButton, modifier: Modifier, onClick: () -> Unit) {
    val c = Libre.colors
    Box(modifier.height(44.dp).rowHighlight(onClick = onClick), contentAlignment = Alignment.Center) {
        Text(
            b.label,
            style = if (b.role == AlertButton.Role.Cancel) Typo.body.semibold else Typo.body,
            color = if (b.role == AlertButton.Role.Destructive) c.destructive else c.accent,
        )
    }
}

@Composable
private fun Toast(text: String?) {
    val c = Libre.colors
    Box(Modifier.fillMaxSize().padding(top = 60.dp), contentAlignment = Alignment.TopCenter) {
        AnimatedVisibility(text != null, enter = fadeIn() + scaleIn(initialScale = 0.9f), exit = fadeOut() + scaleOut(targetScale = 0.9f)) {
            Text(
                text.orEmpty(), style = Typo.subheadline.semibold, color = c.label,
                modifier = Modifier
                    .then(
                        if (LocalGlass.current != null) Modifier.liquidGlass(RoundedCornerShape(22.dp), c.dark, GlassStyle.Menu)
                        else Modifier.clip(RoundedCornerShape(22.dp)).background(material(c.dark, thick = true)),
                    )
                    .padding(18.dp, 11.dp),
            )
        }
    }
}
