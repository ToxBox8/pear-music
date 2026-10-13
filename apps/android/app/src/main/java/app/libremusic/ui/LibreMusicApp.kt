package app.libremusic.ui

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
    val tabs = TabOrder.visible(tabOrder, searchPlacement == "tab").map(Tab::of)
    LaunchedEffect(searchPlacement) { if (app.tab == Tab.Search && searchPlacement != "tab") app.tab = Tab.Home }
    // La app vuelve a abrirse en la última pestaña usada.
    LaunchedEffect(app.tab) { Prefs.setLastTab(app.tab.key) }
    // Atajos del icono de la app (mantener pulsado) y del Asistente.
    val shortcut by AppShortcuts.pending.collectAsState()
    val libData by libraryVm.data.collectAsState()
    val downloadedNow by libraryVm.downloadedSongs.collectAsState()
    LaunchedEffect(shortcut) {
        val k = shortcut ?: return@LaunchedEffect
        AppShortcuts.pending.value = null
        when (k) {
            AppShortcuts.Kind.Favorites ->
                if (libData.favorites.isEmpty()) app.toast = "Aún no hay favoritas" else playerVm.play(libData.favorites.shuffled())
            AppShortcuts.Kind.Downloads ->
                if (downloadedNow.isEmpty()) app.toast = "Aún no hay nada descargado" else playerVm.play(downloadedNow.shuffled())
            AppShortcuts.Kind.Discover -> app.tab = Tab.Discover
            AppShortcuts.Kind.Search -> app.tab = if (searchPlacement == "tab") Tab.Search else Tab.Home
        }
    }

    val barsDark = Libre.colors.dark || (app.tab == Tab.Discover && !app.showPlayer)
    LaunchedEffect(barsDark) { onBarsDark(barsDark) }

    val landscape = LocalConfiguration.current.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
    val immersive = landscape && player.current != null && deck.isObject

    CompositionLocalProvider(LocalReduceMotion provides reduceMotion, LocalGlass provides glass) {
        ProvideApp(app) {
            val env = ScreenEnv(app, playerVm, libraryVm, homeVm)
            CompositionLocalProvider(LocalEnv provides env) {
                Box(Modifier.fillMaxSize().background(Libre.colors.background)) {
                    // Atrás dentro de una pestaña: lo gestiona TabStack (gesto del sistema con vista previa).

                    val hasMini = player.current != null
                    val bottomInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() +
                        (if (hasMini) 62.dp + 48.dp + 8.dp else 62.dp) + 20.dp
                    CompositionLocalProvider(LocalBottomInset provides bottomInset) {
                      // Deslizar a los lados cambia de pestaña (como Instagram). Lo que esté dentro y se
                      // arrastre en horizontal (carruseles, filas que se deslizan, «atrás» de una pila)
                      // tiene prioridad: si ya se ha quedado el arrastre, no se cambia de pestaña.
                      val swipe = remember { Animatable(0f) }
                      var swipeTo by remember { mutableStateOf<Tab?>(null) }
                      var contentWidth by remember { mutableStateOf(1f) }
                      val swipeScope = rememberCoroutineScope()
                      val swipeEnabled = !app.showPlayer && !app.showJam && app.editing == null && !app.showImport
                      // Con el cristal líquido, las pantallas se graban para que el cristal las refracte.
                      Box(
                          Modifier
                              .fillMaxSize()
                              .onSizeChanged { contentWidth = it.width.toFloat().coerceAtLeast(1f) }
                              .pointerInput(tabs, app.tab, swipeEnabled) {
                                  if (!swipeEnabled) return@pointerInput
                                  awaitEachGesture {
                                      val down = awaitFirstDown(requireUnconsumed = false)
                                      val tracker = androidx.compose.ui.input.pointer.util.VelocityTracker()
                                      val index = tabs.indexOf(app.tab)
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
                                              val slop = viewConfiguration.touchSlop
                                              if (kotlin.math.abs(dx) > slop || kotlin.math.abs(dy) > slop) {
                                                  if (!isHorizontal(dx, dy, slop)) return@awaitEachGesture
                                                  claimed = true
                                                  swipeTo = tabs.getOrNull(if (dx < 0) index + 1 else index - 1)
                                              }
                                          }
                                          if (claimed) {
                                              change.consume()
                                              tracker.addPosition(change.uptimeMillis, change.position)
                                              // Sin pestaña a ese lado, se resiste (como al final de una lista).
                                              val step = if (swipeTo == null) d.x * 0.3f else d.x
                                              swipeScope.launch { swipe.snapTo(swipe.value + step) }
                                          }
                                      }
                                      if (!claimed) return@awaitEachGesture
                                      val v = tracker.calculateVelocity().x
                                      val target = swipeTo
                                      val goes = target != null && (kotlin.math.abs(swipe.value) > contentWidth * 0.33f ||
                                          (kotlin.math.abs(v) > 800f * density && kotlin.math.sign(v) == kotlin.math.sign(swipe.value)))
                                      swipeScope.launch {
                                          val spec = if (reduceMotion) tween<Float>(120) else tween(320, easing = UiEaseOut)
                                          if (goes && target != null) {
                                              swipe.animateTo(if (swipe.value < 0) -contentWidth else contentWidth, spec)
                                              app.tab = target
                                              swipe.snapTo(0f)
                                          } else {
                                              swipe.animateTo(0f, spec)
                                          }
                                          swipeTo = null
                                      }
                                  }
                              }
                              .then(if (glass != null) Modifier.glassSource(glass) else Modifier),
                      ) {
                      CompositionLocalProvider(LocalInsideGlassSource provides (glass != null)) {
                        // Las pestañas se conservan montadas para no perder el desplazamiento ni la pila.
                        tabs.forEach { t ->
                            val active = app.tab == t
                            val neighbor = t == swipeTo
                            val visible = active || neighbor
                            Box(
                                Modifier
                                    .fillMaxSize()
                                    .graphicsLayer {
                                        alpha = if (visible) 1f else 0f
                                        translationX = when {
                                            active -> swipe.value
                                            neighbor -> swipe.value + if (tabs.indexOf(t) > tabs.indexOf(app.tab)) contentWidth else -contentWidth
                                            else -> 0f
                                        }
                                    }
                                    .then(if (visible) Modifier else Modifier.offset { IntOffset(100_000, 0) }),
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
                    Column(
                        Modifier.align(Alignment.BottomCenter).widthIn(max = 520.dp).padding(horizontal = 21.dp).padding(bottom = maxOf(navBottom - 13.dp, 8.dp)),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        AnimatedVisibility(hasMini, enter = fadeIn() + slideInVertically { it / 2 }, exit = fadeOut() + slideOutVertically { it / 2 }) {
                            MiniPlayerAccessory(onOpen = { app.showPlayer = true })
                        }
                        if (glass != null) LiquidTabBar(tabs, app.tab, dark = app.tab == Tab.Discover) { app.select(it) }
                        else TabBar(tabs, app.tab, dark = app.tab == Tab.Discover) { app.select(it) }
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

                    // Primera vez: guía de tres pantallas (también desde Ajustes › Ayuda y soporte).
                    val onboarded by Prefs.onboarded.collectAsState()
                    androidx.compose.animation.AnimatedVisibility(
                        !onboarded, enter = androidx.compose.animation.fadeIn(uiEaseOut(250)), exit = androidx.compose.animation.fadeOut(uiEaseOut(250)),
                    ) { OnboardingScreen(onDone = { Prefs.setOnboarded(true) }) }

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
        Route.AppIconR -> AppIconScreen()
        is Route.Support -> SupportScreen(route.draftId)
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
    }
}

// MARK: Barra de pestañas ------------------------------------------------------------------------

private fun Tab.icon(): ImageVector = when (this) {
    Tab.Home -> Icons.Rounded.Home
    Tab.Discover -> Icons.Rounded.Subscriptions
    Tab.Search -> Icons.Rounded.Search
    Tab.Library -> Icons.Rounded.LibraryMusic
    Tab.Settings -> Icons.Rounded.Settings
}

/** Barra de pestañas flotante de cristal (iOS 26). En Descubrir se oscurece, como en iOS. */
@Composable
private fun TabBar(tabs: List<Tab>, selected: Tab, dark: Boolean, onSelect: (Tab) -> Unit) {
    val c = Libre.colors
    val isDark = dark || c.dark
    val shape = RoundedCornerShape(31.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .height(62.dp)
            .clip(shape)
            .background(if (dark) Color(0xEB0E0E10) else material(c.dark, thick = true))
            .border(0.5.dp, Color.White.copy(alpha = if (isDark) 0.12f else 0.6f), shape)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        tabs.forEach { t ->
            val on = t == selected
            val tint = if (on) (if (dark && c.theme == app.libremusic.ui.theme.AppTheme.Air) Color.White else c.accent)
            else if (isDark) Color.White.copy(alpha = 0.85f) else c.label
            val pill = if (on) (if (isDark) Color.White.copy(0.1f) else Color.Black.copy(0.06f)) else Color.Transparent
            Column(
                Modifier
                    .weight(1f)
                    .height(54.dp)
                    .drawBehind {
                        val extra = 5.dp.toPx()
                        drawRoundRect(pill, Offset(-extra, 0f), Size(size.width + 2 * extra, size.height), CornerRadius(size.height / 2))
                    }
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
private fun LiquidTabBar(tabs: List<Tab>, selected: Tab, dark: Boolean, onSelect: (Tab) -> Unit) {
    val c = Libre.colors
    val isDark = dark || c.dark
    val source = LocalGlass.current ?: return TabBar(tabs, selected, dark, onSelect)
    val reduce = LocalReduceMotion.current
    val scope = rememberCoroutineScope()
    val contentLayer = androidx.compose.ui.graphics.rememberGraphicsLayer()
    val dropLayer = androidx.compose.ui.graphics.rememberGraphicsLayer()
    val shader = rememberLensShader()
    var barOrigin by remember { mutableStateOf(Offset.Zero) }
    var barWidth by remember { mutableStateOf(0f) }
    val density = LocalDensity.current
    val padH = with(density) { 8.dp.toPx() }
    val selIndex = tabs.indexOf(selected).coerceAtLeast(0)
    val x = remember { Animatable(-1f) }
    val lift = remember { Animatable(0f) }

    fun tabWidth() = (barWidth - 2 * padH) / tabs.size
    fun center(i: Int) = padH + tabWidth() * (i + 0.5f)
    fun nearest(px: Float) = ((px - padH) / tabWidth()).toInt().coerceIn(0, tabs.lastIndex)

    LaunchedEffect(selIndex, barWidth, tabs.size) {
        if (barWidth <= 0f) return@LaunchedEffect
        if (x.value < 0f || reduce) x.snapTo(center(selIndex))
        else if (lift.value == 0f) x.animateTo(center(selIndex), spring(dampingRatio = 0.7f, stiffness = 380f))
    }
    val highlight = if (lift.value > 0.05f && barWidth > 0f && x.value >= 0f) nearest(x.value) else selIndex
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
                if (cx >= 0f) {
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
