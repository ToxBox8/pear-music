package app.libremusic.reels

import android.content.Intent
import android.os.Build
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.rounded.Autorenew
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import app.libremusic.data.Song
import app.libremusic.jam.JamPhase
import app.libremusic.jam.JamService
import app.libremusic.ui.ContextMenu
import app.libremusic.ui.CoverImage
import app.libremusic.ui.LibraryViewModel
import app.libremusic.ui.LocalEnv
import app.libremusic.ui.MenuEntry
import app.libremusic.ui.PillButton
import app.libremusic.ui.PlayerViewModel
import app.libremusic.ui.Spinner
import app.libremusic.ui.rememberClock
import app.libremusic.ui.rememberHaptics
import app.libremusic.ui.songMenu
import app.libremusic.ui.tactile
import app.libremusic.ui.theme.AppTheme
import app.libremusic.ui.theme.DarkSection
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.LocalReduceMotion
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Tokens
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.bold
import app.libremusic.ui.theme.medium
import app.libremusic.ui.theme.semibold
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Descubrir (Reels.swift): feed vertical a pantalla completa, cada página suena 30 s desde la
// zona del estribillo, en bucle. Desliza para la siguiente, doble toque para «Me gusta».

/** Los reels son siempre oscuros: el acento negro de Aire se cambia por blanco. */
private fun AppTheme.reelAccent(): Color = if (this == AppTheme.Air) Color.White else accent
private fun AppTheme.reelOnAccent(): Color = if (this == AppTheme.Air) Color.Black else onAccent

@Composable
fun ReelsScreen(reelsVm: ReelsViewModel, playerVm: PlayerViewModel, libraryVm: LibraryViewModel, visible: Boolean) {
    val state by reelsVm.state.collectAsState()
    val library by libraryVm.data.collectAsState()
    val player by playerVm.state.collectAsState()
    val seeds = library.favorites.take(12) + library.recents.take(12)
    val exclude = library.favorites.map { it.id }.toSet()

    LaunchedEffect(Unit) { reelsVm.load(seeds, exclude) }
    // Suena sólo mientras la pestaña está a la vista y la app en primer plano.
    LaunchedEffect(visible) { reelsVm.setVisible(visible) }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { reelsVm.setVisible(false) }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { if (visible) reelsVm.setVisible(true) }
    // El reproductor principal empezó a sonar: el fragmento se calla.
    LaunchedEffect(player.isPlaying) { if (player.isPlaying) reelsVm.yieldToMainPlayer() }

    DarkSection {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (state.items.isEmpty()) {
                Box(Modifier.fillMaxSize().graphicsLayer { alpha = 0.5f }) { ThemeBackdrop(false, null) }
                EmptyState(state.loading || !state.failed) { reelsVm.load(seeds, exclude, force = true) }
            } else {
                key(state.items.firstOrNull()?.id) { ReelsPager(state, reelsVm, playerVm) }
            }
            // Cabecera
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(start = 20.dp, end = 20.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Descubrir", style = Typo.display(Tokens.TypeSize.DisplayScreen, Libre.colors.theme), color = Color.White, modifier = Modifier.weight(1f))
                Box(
                    Modifier.size(44.dp).tactile(enabled = !state.loading, label = "Mezclar otra vez") { reelsVm.load(seeds, exclude, force = true) },
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Rounded.Autorenew, null, tint = Color.White, modifier = Modifier.size(22.dp)) }
            }
        }
    }
}

@Composable
private fun EmptyState(loading: Boolean, onRetry: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        if (loading) {
            Spinner(36.dp, Color.White)
            Spacer(Modifier.height(14.dp))
            Text("Buscando música para ti…", style = Typo.headline, color = Color.White)
        } else {
            Icon(Icons.Rounded.WifiOff, null, tint = Color.White, modifier = Modifier.size(34.dp))
            Spacer(Modifier.height(14.dp))
            Text("No hay fragmentos ahora mismo", style = Typo.headline, color = Color.White)
            Spacer(Modifier.height(6.dp))
            Text("Revisa la conexión y vuelve a intentarlo.", style = Typo.subheadline, color = Color.White.copy(0.72f), textAlign = TextAlign.Center)
            Spacer(Modifier.height(20.dp))
            PillButton("Reintentar", Icons.Rounded.Refresh, prominent = true, modifier = Modifier.widthIn(max = 220.dp), onClick = onRetry)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ReelsPager(state: ReelsState, reelsVm: ReelsViewModel, playerVm: PlayerViewModel) {
    val env = LocalEnv.current
    val pager = rememberPagerState(initialPage = state.index) { state.items.size }
    val haptics = rememberHaptics()
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect {
            if (it != reelsVm.state.value.index) haptics.tick()
            reelsVm.go(it)
        }
    }
    VerticalPager(state = pager, modifier = Modifier.fillMaxSize(), beyondViewportPageCount = 1) { page ->
        val song = state.items[page]
        ReelPage(song, page == state.index, state, reelsVm, onListenFull = {
            reelsVm.yieldToMainPlayer()
            // Pasa al reproductor con el resto del feed como cola.
            playerVm.play(state.items.drop(page), 0)
            env.app.showPlayer = true
        })
    }
}

@Composable
private fun ReelPage(song: Song, isCurrent: Boolean, state: ReelsState, reelsVm: ReelsViewModel, onListenFull: () -> Unit) {
    val env = LocalEnv.current
    val theme = Libre.colors.theme
    val reduce = LocalReduceMotion.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val playing = isCurrent && state.isPlaying
    val broken = song.id in state.broken
    var flash by remember { mutableStateOf<ImageVector?>(null) }
    val burst = remember { Animatable(0f) }

    fun like() {
        if (!env.library.isFavorite(song)) env.library.toggleFavorite(song)
        haptics.medium()
        scope.launch {
            burst.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = 380f))
            delay(700)
            burst.animateTo(0f, tween(350))
        }
    }

    fun toggle() {
        if (!isCurrent || state.buffering) return
        val icon = if (state.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow
        reelsVm.toggle()
        flash = icon
        scope.launch { delay(550); if (flash == icon) flash = null }
    }

    // El detector no se reinicia cuando empieza a sonar o deja de cargar (antes, un toque o el
    // doble toque que caía justo en ese momento se perdía); las acciones leen el estado al disparar.
    val onTap by androidx.compose.runtime.rememberUpdatedState({ toggle() })
    val onDoubleTap by androidx.compose.runtime.rememberUpdatedState({ like() })
    BoxWithConstraints(
        Modifier.fillMaxSize().pointerInput(Unit) {
            detectTapGestures(onDoubleTap = { onDoubleTap() }, onTap = { onTap() })
        },
    ) {
        val side = minOf(maxWidth - 64.dp, maxHeight * 0.46f)
        ReelBackground(song.thumb(400), playing && !reduce)
        Column(Modifier.fillMaxSize()) {
            Spacer(Modifier.statusBarsPadding().height(64.dp))
            Spacer(Modifier.weight(1f))
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                ReelArtwork(song.thumb(900), side, min(30f, theme.maxRadius).dp, playing && !reduce)
                if (isCurrent && state.buffering) Spinner(36.dp, Color.White)
                androidx.compose.animation.AnimatedVisibility(flash != null, enter = fadeIn() + scaleIn(initialScale = 0.6f), exit = fadeOut() + scaleOut(targetScale = 0.6f)) {
                    Icon(flash ?: Icons.Rounded.PlayArrow, null, tint = Color.White, modifier = Modifier.size(64.dp))
                }
                Icon(
                    Icons.Rounded.Favorite, null, tint = theme.reelAccent(),
                    modifier = Modifier.size(120.dp).graphicsLayer {
                        val v = burst.value
                        scaleX = 0.4f + 0.68f * v; scaleY = scaleX; alpha = v.coerceIn(0f, 1f)
                    },
                )
            }
            Spacer(Modifier.height(24.dp))
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(song.title, style = Typo.display(26f, theme).copy(shadow = ReelShadow), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Spacer(Modifier.height(6.dp))
                    Text(song.artist, style = Typo.body.medium.copy(shadow = ReelShadow), color = Color.White.copy(0.85f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (broken) {
                        Spacer(Modifier.height(6.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.Warning, null, tint = Color.White.copy(0.85f), modifier = Modifier.size(15.dp))
                            Spacer(Modifier.size(6.dp))
                            Text("Este fragmento no se pudo cargar", style = Typo.footnote.semibold, color = Color.White.copy(0.85f))
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                    Row(
                        Modifier.height(40.dp).background(theme.reelAccent(), CircleShape).tactile(label = "Escuchar completa", onClick = onListenFull).padding(horizontal = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Rounded.PlayArrow, null, tint = theme.reelOnAccent(), modifier = Modifier.size(18.dp))
                        Spacer(Modifier.size(6.dp))
                        Text("Escuchar completa", style = Typo.subheadline.bold, color = theme.reelOnAccent())
                    }
                }
                Actions(song, theme)
            }
            ClipProgress(if (isCurrent) state.clipProgress else 0f, theme.reelAccent(), Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 14.dp))
            Spacer(Modifier.height(app.libremusic.ui.LocalBottomInset.current - 20.dp))
        }
    }
}

@Composable
private fun Actions(song: Song, theme: AppTheme) {
    val env = LocalEnv.current
    val context = LocalContext.current
    val data by env.library.data.collectAsState()
    val jam by JamService.state.collectAsState()
    val fav = data.favorites.any { it.id == song.id }
    var addMenu by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }
    val jamActive = jam.phase == JamPhase.Hosting || jam.phase == JamPhase.Joined
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        ActionLabel(if (fav) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, "Me gusta", if (fav) theme.reelAccent() else Color.White) {
            env.library.toggleFavorite(song)
        }
        Box {
            ActionLabel(Icons.Outlined.AddCircleOutline, "Añadir") { addMenu = true }
            ContextMenu(addMenu, { addMenu = false }, buildList {
                if (jamActive) add(MenuEntry.Action("Añadir al Jam", app.libremusic.ui.theme.JamIcon(), enabled = jam.jam?.entries?.none { it.song.id == song.id } != false) { JamService.add(song) })
                data.userPlaylists.forEach { p -> add(MenuEntry.Action(p.name) { env.library.addToPlaylist(p.id, song) }) }
                if (data.userPlaylists.isEmpty() && !jamActive) add(MenuEntry.Note("Crea una playlist en Biblioteca"))
            })
        }
        ActionLabel(Icons.AutoMirrored.Rounded.Send, "Compartir") {
            val url = "https://music.youtube.com/watch?v=${song.id}"
            val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_SUBJECT, song.title)
                .putExtra(Intent.EXTRA_TEXT, "${song.title} — ${song.artist}\n$url")
            context.startActivity(Intent.createChooser(send, null))
        }
        Box {
            ActionLabel(Icons.Rounded.MoreHoriz, "Más") { moreMenu = true }
            ContextMenu(moreMenu, { moreMenu = false }, songMenu(song))
        }
    }
}

@Composable
private fun ActionLabel(icon: ImageVector, text: String, tint: Color = Color.White, onClick: () -> Unit) {
    Column(Modifier.widthIn(min = 56.dp).tactile(label = text, onClick = onClick), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(48.dp, 40.dp), contentAlignment = Alignment.Center) { Icon(icon, null, tint = tint, modifier = Modifier.size(28.dp)) }
        Spacer(Modifier.height(4.dp))
        Text(text, style = Typo.caption2.semibold.copy(shadow = ReelShadow), color = tint)
    }
}

/** Sombra suave bajo los textos blancos de Descubrir, por si la carátula es clara justo ahí. */
private val ReelShadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(0.55f), androidx.compose.ui.geometry.Offset(0f, 1f), 8f)

@Composable
private fun ClipProgress(progress: Float, tint: Color, modifier: Modifier) {
    Box(modifier.fillMaxWidth().height(3.dp).clip(CircleShape).background(Color.White.copy(0.22f))) {
        Box(Modifier.fillMaxWidth(progress.coerceIn(0f, 1f)).height(3.dp).background(tint, CircleShape))
    }
}

/** Carátula que respira y se inclina despacio mientras suena. */
@Composable
private fun ReelArtwork(url: String?, side: Dp, radius: Dp, animating: Boolean) {
    val clock = app.libremusic.ui.rememberClockState(animating)
    val shape = RoundedCornerShape(radius)
    Box(
        Modifier.size(side)
            .graphicsLayer {
                val t = clock.longValue / 1000.0
                val breath = if (animating) 1 + 0.022 * sin(t * 2 * PI / 4.2) else 1.0
                val tilt = if (animating) 5 * sin(t * 2 * PI / 9) else 0.0
                scaleX = breath.toFloat(); scaleY = breath.toFloat()
                rotationY = tilt.toFloat(); rotationX = (tilt * 0.25).toFloat()
                cameraDistance = 12 * density
            }
            .shadow(34.dp, shape, ambientColor = Color.Black.copy(0.45f), spotColor = Color.Black.copy(0.45f))
            .clip(shape)
            .border(1.dp, Color.White.copy(0.14f), shape),
    ) { CoverImage(url, Modifier.fillMaxSize()) }
}

/** La propia carátula, enorme y desenfocada, girando muy despacio detrás de todo. */
@Composable
private fun ReelBackground(url: String?, animating: Boolean) {
    val clock = app.libremusic.ui.rememberClockState(animating)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val side = max(maxWidth.value, maxHeight.value).dp * 1.6f
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CoverImage(
                    // requiredSize: con size() el cuadrado se quedaba del tamaño de la pantalla y al girar
                    // asomaban las esquinas negras. Unbounded: sin bordes duros en el desenfoque.
                    url, Modifier.requiredSize(side).graphicsLayer { rotationZ = ((clock.longValue / 1000.0) * 4 % 360).toFloat() }
                        .blur(70.dp, androidx.compose.ui.draw.BlurredEdgeTreatment.Unbounded),
                    placeholder = false,
                )
            }
        } else {
            // Sin desenfoque en Android < 12: la carátula muy oscurecida hace de fondo.
            CoverImage(url, Modifier.fillMaxSize().graphicsLayer { alpha = 0.35f }, placeholder = false)
        }
        // Velo: arriba deja ver la carátula; en la franja del título y los botones oscurece lo bastante para que el
        // blanco se lea aunque la portada sea clara (≥ 4,5:1 con la sombra del texto).
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    0f to Color.Black.copy(0.35f), 0.3f to Color.Black.copy(0.15f), 0.5f to Color.Black.copy(0.35f),
                    0.68f to Color.Black.copy(0.78f), 1f to Color.Black.copy(0.9f),
                ),
            ),
        )
    }
}
