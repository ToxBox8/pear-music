package app.libremusic.ui

import app.libremusic.ui.theme.withArtwork
import app.libremusic.ui.theme.ArtworkBackdrop
import androidx.compose.foundation.layout.displayCutoutPadding
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.FormatListBulleted
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Lyrics
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.BlurCircular
import androidx.compose.material.icons.rounded.Cast
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ClearAll
import androidx.compose.material.icons.rounded.DragHandle
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material.icons.rounded.FastRewind
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.OpenInFull
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PauseCircleFilled
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PlayCircleFilled
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RemoveCircle
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Voicemail
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import app.libremusic.data.Song
import app.libremusic.playback.SleepTimer
import app.libremusic.ui.theme.AirPaper
import app.libremusic.ui.theme.DarkSection
import app.libremusic.ui.theme.DeckStyle
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Prefs
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Tokens
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.material
import app.libremusic.ui.theme.medium
import app.libremusic.ui.theme.semibold
import app.libremusic.ui.theme.themeSurface
import kotlin.math.roundToInt

fun DeckStyle.icon(): ImageVector = when (this) {
    DeckStyle.Normal -> Icons.Rounded.Tune
    DeckStyle.Cassette -> Icons.Rounded.Voicemail
    DeckStyle.Vinyl -> Icons.Rounded.Album
    DeckStyle.Air -> Icons.Rounded.BlurCircular
}

/** Elegir reproductor (submenú del mini reproductor y de la cabecera del casete). */
@Composable
fun deckMenu(selected: DeckStyle): List<MenuEntry> =
    DeckStyle.entries.map { d -> MenuEntry.Action(d.title, d.icon(), checked = d == selected) { Prefs.setDeck(d) } }

// MARK: Mini reproductor (accesorio sobre la barra de pestañas) ---------------------------------------------

/** Tocar abre el reproductor; mantener pulsado deja elegir el tipo de reproductor (como en iOS 1.3). */
@Composable
fun MiniPlayerAccessory(onOpen: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val deck by Prefs.deck.collectAsState()
    val song = st.current ?: return
    var menu by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(24.dp)
    val glass = LocalGlass.current != null
    val press = rememberGlassPress()
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .height(48.dp)
                .then(
                    if (glass) Modifier
                        .glassInteractive(press, "Abrir reproductor", grow = 0.035f, onLongClick = { menu = true }, onClick = onOpen)
                        .liquidGlass(shape, c.dark, GlassStyle.Bar, press = press)
                    else Modifier
                        .clip(shape)
                        .background(material(c.dark, thick = true))
                        .border(0.5.dp, Color.White.copy(alpha = if (c.dark) 0.12f else 0.6f), shape)
                        .tactile(label = "Abrir reproductor", onLongClick = { menu = true }, onClick = onOpen),
                )
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(38.dp).clip(RoundedCornerShape(9.dp))) {
                when (deck) {
                    DeckStyle.Normal -> CoverImage(song.thumb(120), Modifier.fillMaxSize())
                    DeckStyle.Cassette -> MiniCassette(st.isPlaying, Modifier.fillMaxSize())
                    DeckStyle.Vinyl -> MiniVinyl(st.isPlaying, song.thumb(120), Modifier.fillMaxSize())
                    DeckStyle.Air -> MiniAirDisc(song.thumb(120), Modifier.fillMaxSize())
                }
            }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(song.title, style = Typo.subheadline.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(st.error ?: song.artist, style = Typo.caption, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            // Cajas de 44 y 40 dp (área táctil) con huecos más pequeños: los iconos quedan donde
            // estaban con cajas de 34 y 30 dp, pero se aciertan mejor.
            Spacer(Modifier.width(5.dp))
            IconTap(if (st.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, if (st.isPlaying) "Pausa" else "Reproducir", size = 28.dp, box = 44.dp) { env.player.togglePlay() }
            IconTap(Icons.Rounded.FastForward, "Siguiente", size = 24.dp, box = 40.dp) { env.player.next() }
        }
        ContextMenu(menu, { menu = false }, listOf(
            MenuEntry.Sub("Reproductor", deck.icon(), deckMenu(deck)),
            MenuEntry.Action("Abrir reproductor", Icons.Rounded.OpenInFull) { onOpen() },
        ))
    }
}

// MARK: Reproductor completo --------------------------------------------------------------------

@Composable
fun PlayerScreen(onClose: () -> Unit) {
    val artworkPlayer by Prefs.artworkColorsPlayer.collectAsState()
    val level by Prefs.artworkLevel.collectAsState()
    val palette = app.libremusic.ui.theme.rememberPalette()
    val base = Libre.colors
    // Con «Colores de la portada» en el reproductor, los controles toman el color de la canción.
    app.libremusic.ui.theme.ProvideLibre(if (artworkPlayer) base.withArtwork(palette[0], level) else base) { PlayerScreenContent(onClose) }
}

@Composable
private fun PlayerScreenContent(onClose: () -> Unit) {
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val deck by Prefs.deck.collectAsState()
    val c = Libre.colors
    var showQueue by remember { mutableStateOf(env.app.initialPanel != null) }
    // Lo que ocupa el sitio de la carátula al pulsar el botón de la cola: la cola o la letra (se recuerda).
    var panel by remember { mutableStateOf(env.app.initialPanel ?: PlayerPanel.Queue) }
    val openLyrics = { panel = PlayerPanel.Lyrics; showQueue = true }
    val song = st.current
    LaunchedEffect(song == null) { if (song == null) onClose() }
    if (song == null) return

    AnimatedContent(deck == DeckStyle.Air && !showQueue, label = "deck", transitionSpec = { fadeIn(uiEaseOut(300)) togetherWith fadeOut(uiEaseOut(300)) }) { air ->
        if (air) {
            Box(Modifier.fillMaxSize()) {
                AirPaper(c.dark)
                AirPlayerView(song, onQueue = { showQueue = true }, onClose = onClose)
            }
        } else {
            Box(Modifier.fillMaxSize()) {
                val artworkPlayer by Prefs.artworkColorsPlayer.collectAsState()
                val level by Prefs.artworkLevel.collectAsState()
                when {
                    deck == DeckStyle.Air -> AirPaper(c.dark)
                    // «Colores de la portada» en el reproductor (Air conserva su papel plateado).
                    artworkPlayer && level.enabled -> ArtworkBackdrop(song.thumb(400), st.isPlaying)
                    c.theme.styled -> ThemeBackdrop(st.isPlaying, song)
                    else -> Box(Modifier.fillMaxSize().background(c.background))
                }
                // Asa del reproductor (Capsule de 40×5 a 8 pt del borde, como en iOS).
                Box(
                    Modifier.align(Alignment.TopCenter).padding(top = 8.dp).size(40.dp, 5.dp)
                        .background(c.secondaryLabel.copy(alpha = 0.4f), RoundedCornerShape(3.dp)),
                )
                val landscape = LocalConfiguration.current.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
                if (landscape && deck == DeckStyle.Normal && !showQueue) {
                    // En horizontal no cabe en columna (la carátula se quedaba sin sitio): dos columnas.
                    // Casete y vinilo pasan a pantalla completa (ImmersiveDeck).
                    Row(
                        Modifier.fillMaxSize().navigationBarsPadding().displayCutoutPadding().padding(top = 20.dp, bottom = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                            PlayerArtwork(song, st.isPlaying, Modifier, fitHeight = true)
                        }
                        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                            TitleBlock(song, st.error, openLyrics)
                            Spacer(Modifier.height(10.dp))
                            Controls(song, showQueue) { showQueue = !showQueue }
                        }
                    }
                } else
                Column(Modifier.fillMaxSize().navigationBarsPadding().padding(top = 27.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    if (showQueue) {
                        PanelTabs(panel) { panel = it }
                        Spacer(Modifier.height(12.dp))
                        if (panel == PlayerPanel.Lyrics) LyricsView(song, Modifier.weight(1f)) else QueueView(Modifier.weight(1f))
                    } else when (deck) {
                        DeckStyle.Normal, DeckStyle.Air -> {
                            // Carátula y título arriba; el hueco que sobra queda encima de los controles.
                            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                                Spacer(Modifier.height(8.dp))
                                PlayerArtwork(song, st.isPlaying, Modifier.weight(1f, fill = false))
                                Spacer(Modifier.height(14.dp))
                                TitleBlock(song, st.error, openLyrics)
                            }
                        }
                        DeckStyle.Cassette, DeckStyle.Vinyl -> {
                            CompactHeader(song, st.error, deck, openLyrics)
                            Spacer(Modifier.height(14.dp))
                            Spacer(Modifier.weight(1f))
                            Spacer(Modifier.height(14.dp))
                            Box(Modifier.padding(horizontal = 8.dp)) {
                                if (deck == DeckStyle.Cassette) CassetteView(song) else VinylView(song)
                            }
                            Spacer(Modifier.height(14.dp))
                            Spacer(Modifier.weight(1f))
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    if (deck.isObject && !showQueue) {
                        SecondaryControls(song, showQueue) { showQueue = !showQueue }
                        Spacer(Modifier.height(10.dp))
                    } else {
                        Controls(song, showQueue) { showQueue = !showQueue }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlayerArtwork(song: Song, playing: Boolean, modifier: Modifier, fitHeight: Boolean = false) {
    val c = Libre.colors
    // Se encoge un poco en pausa, como un objeto que «descansa».
    val scale by animateFloatAsState(if (playing) 1f else 0.9f, spring(dampingRatio = 0.8f, stiffness = 200f), label = "art")
    val shape = RoundedCornerShape(Tokens.Radius.ArtworkPlayer.dp)
    Box(
        modifier
            .padding(horizontal = 24.dp)
            .sizeIn(maxWidth = 340.dp, maxHeight = 340.dp)
            .aspectRatio(1f, matchHeightConstraintsFirst = fitHeight)
            .scale(scale)
            .dropShadow(shape, Color.Black.copy(alpha = 0.3f), blur = 18.dp, offsetY = 8.dp)
            .clip(shape)
            .then(if (c.theme.styled) Modifier.border(1.dp, Color.White.copy(alpha = 0.25f), shape) else Modifier),
    ) { CoverImage(song.thumb(1000), Modifier.fillMaxSize()) }
}

@Composable
private fun TitleBlock(song: Song, error: String?, onLyrics: () -> Unit) {
    val c = Libre.colors
    val scramble by Prefs.scramble.collectAsState()
    // Temporizador a la izquierda y «⋯» a la derecha, del mismo ancho: el título sigue centrado.
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        SleepTimerButton()
        Column(Modifier.weight(1f).padding(horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            ScrambleText(song.title, Typo.title3.copy(fontWeight = FontWeight.Bold), maxLines = 2, textAlign = TextAlign.Center, enabled = scramble)
            Spacer(Modifier.height(4.dp))
            Text(song.artist, style = Typo.body, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
            SleepTimerLabel()
            if (error != null) Text(error, style = Typo.caption, color = c.destructive, textAlign = TextAlign.Center)
        }
        SongMoreButton(song, onLyrics)
    }
}

/** Luna del temporizador para dormir: en acento mientras cuenta; el menú elige minutos, «al acabar la canción» o apagarlo. */
@Composable
private fun SleepTimerButton() {
    val c = Libre.colors
    val timer by SleepTimer.state.collectAsState()
    val on = timer != SleepTimer.State.Off
    var menu by remember { mutableStateOf(false) }
    Box {
        IconTap(
            if (on) Icons.Rounded.Bedtime else Icons.Outlined.Bedtime,
            if (on) "Temporizador: ${SleepTimer.label(timer)}" else "Temporizador para dormir",
            tint = if (on) c.accent else c.label,
        ) { menu = true }
        ContextMenu(menu, { menu = false }, sleepMenu(timer))
    }
}

private fun sleepMenu(timer: SleepTimer.State): List<MenuEntry> = buildList {
    SleepTimer.label(timer)?.let { add(MenuEntry.Note(it)) }
    SleepTimer.presets.forEach { m ->
        add(MenuEntry.Action("$m minutos", checked = (timer as? SleepTimer.State.At)?.minutes == m) { SleepTimer.start(m) })
    }
    add(MenuEntry.Action("Al acabar la canción", Icons.Rounded.MusicNote, checked = timer == SleepTimer.State.EndOfSong) { SleepTimer.endOfSong() })
    if (timer != SleepTimer.State.Off) {
        add(MenuEntry.Divider)
        add(MenuEntry.Action("Desactivar temporizador", Icons.Rounded.Close, destructive = true) { SleepTimer.cancel() })
    }
}

/** «Se para en 12 min» debajo del artista mientras el temporizador cuenta. */
@Composable
private fun SleepTimerLabel() {
    val timer by SleepTimer.state.collectAsState()
    val text = SleepTimer.label(timer) ?: return
    Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.Bedtime, null, tint = Libre.colors.accent, modifier = Modifier.size(13.dp))
        Spacer(Modifier.width(4.dp))
        Text(text, style = Typo.caption.copy(fontFeatureSettings = "tnum"), color = Libre.colors.accent, maxLines = 1)
    }
}

/** «⋯» del reproductor: el mismo menú de canción que en el resto de la app. */
@Composable
private fun SongMoreButton(song: Song, onLyrics: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        IconTap(Icons.Rounded.MoreHoriz, "Más opciones de ${song.title}", tint = Libre.colors.label) { menu = true }
        ContextMenu(menu, { menu = false }, listOf(MenuEntry.Action("Ver letra", Icons.Rounded.Lyrics, onClick = onLyrics), MenuEntry.Divider) + songMenu(song))
    }
}

enum class PlayerPanel { Queue, Lyrics }

/** «Cola | Letra» encima del panel que sustituye a la carátula. */
@Composable
private fun PanelTabs(panel: PlayerPanel, onSelect: (PlayerPanel) -> Unit) {
    Box(Modifier.padding(horizontal = 20.dp)) {
        Segmented(listOf("queue" to "Cola", "lyrics" to "Letra"), if (panel == PlayerPanel.Lyrics) "lyrics" else "queue") {
            onSelect(if (it == "lyrics") PlayerPanel.Lyrics else PlayerPanel.Queue)
        }
    }
}

@Composable
private fun CompactHeader(song: Song, error: String?, deck: DeckStyle, onLyrics: () -> Unit) {
    val c = Libre.colors
    val scramble by Prefs.scramble.collectAsState()
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        CoverImage(song.thumb(240), Modifier.size(56.dp).clip(RoundedCornerShape(10.dp)))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            ScrambleText(song.title, Typo.headline, enabled = scramble)
            Text(error ?: song.artist, style = Typo.subheadline, color = if (error == null) c.secondaryLabel else c.destructive, maxLines = 2)
            SleepTimerLabel()
        }
        SleepTimerButton()
        SongMoreButton(song, onLyrics)
        Box {
            IconTap(deck.icon(), "Cambiar reproductor", tint = c.accent) { menu = true }
            ContextMenu(menu, { menu = false }, deckMenu(deck))
        }
    }
}

/** Progreso, anterior/reproducir/siguiente y la fila secundaria, en una tarjeta del tema. */
@Composable
private fun Controls(song: Song, showQueue: Boolean, onQueue: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val glass = c.theme.styled
    Column(
        Modifier
            .padding(horizontal = if (glass) 12.dp else 16.dp)
            .padding(bottom = 8.dp)
            .then(if (glass) Modifier.themeSurface(28.dp, c) else Modifier)
            .padding(if (glass) 16.dp else 0.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Scrubber()
        Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
            IconTap(Icons.Rounded.FastRewind, "Anterior", size = 50.dp, box = 56.dp) { env.player.previous() }
            if (glass) {
                LipButton(if (st.isPlaying) "Pausa" else "Reproducir", onClick = { env.player.togglePlay() }) {
                    Icon(if (st.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = c.label, modifier = Modifier.size(44.dp))
                }
            } else {
                Box(Modifier.size(76.dp).tactile(label = if (st.isPlaying) "Pausa" else "Reproducir") { env.player.togglePlay() }, contentAlignment = Alignment.Center) {
                    Icon(if (st.isPlaying) Icons.Rounded.PauseCircleFilled else Icons.Rounded.PlayCircleFilled, null, tint = c.accent, modifier = Modifier.size(72.dp))
                }
            }
            IconTap(Icons.Rounded.FastForward, "Siguiente", size = 50.dp, box = 56.dp) { env.player.next() }
        }
        SecondaryControls(song, showQueue, onQueue)
    }
}

/** Botón redondo de cristal con un «labio» inferior que desaparece al pulsar (TactileButtonStyle lip). */
@Composable
private fun LipButton(label: String, onClick: () -> Unit, content: @Composable () -> Unit) {
    val c = Libre.colors
    var pressed by remember { mutableStateOf(false) }
    val down by animateFloatAsState(if (pressed) 1f else 0f, uiEaseOut(150), label = "lip")
    Box(
        Modifier.size(76.dp)
            .pointerInput(Unit) {
                detectTapGestures(
                    onPress = { pressed = true; tryAwaitRelease(); pressed = false },
                    onTap = { onClick() },
                )
            }
            .semanticsButton(label, onClick),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.matchParentSize().offset(y = (4 - 3 * down).dp).background(Color.Black.copy(alpha = 0.28f), CircleShape))
        Box(
            Modifier.matchParentSize().offset(y = (3 * down).dp).scale(1 - 0.03f * down).clip(CircleShape)
                .background(material(c.dark))
                .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(0.7f), Color.White.copy(0.05f))), CircleShape),
            contentAlignment = Alignment.Center,
        ) { content() }
    }
}

/** Favorito, descarga, salida de audio, bucle y cola: comunes a los controles normales y al casete/vinilo. */
@Composable
private fun SecondaryControls(song: Song, showQueue: Boolean, onQueue: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val context = LocalContext.current
    val st by env.player.state.collectAsState()
    val fav = data.favorites.any { it.id == song.id }
    val favScale by animateFloatAsState(if (fav) 1.1f else 1f, spring(dampingRatio = 0.5f, stiffness = 400f), label = "fav")
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(44.dp).tactile(label = if (fav) "Quitar de favoritos" else "Añadir a favoritos") { env.library.toggleFavorite(song) }, contentAlignment = Alignment.Center) {
            Icon(if (fav) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, null, tint = if (fav) c.accent else c.label, modifier = Modifier.size(26.dp).scale(favScale))
        }
        DownloadButton(song)
        IconTap(Icons.Rounded.Cast, "Salida de audio", size = 24.dp) { openOutputSwitcher(context) }
        RepeatButton(st.repeatMode) { env.player.cycleRepeat() }
        IconTap(if (showQueue) Icons.Rounded.MusicNote else Icons.AutoMirrored.Rounded.FormatListBulleted, if (showQueue) "Ver carátula" else "Ver cola", size = 26.dp, onClick = onQueue)
    }
}

/** «Descargar» → «Descargando 40 %» → «Descargado» (o «Reintentar»), con la etiqueta deslizándose. */
@Composable
fun DownloadButton(song: Song) {
    val c = Libre.colors
    val env = LocalEnv.current
    val dl by env.library.downloads.collectAsState()
    val st = dl[song.id]
    val phase = when {
        st?.isDone == true -> 2
        st?.isActive == true -> 1
        st?.isFailed == true -> 3
        else -> 0
    }
    val pct = (st?.percent ?: 0f).roundToInt()
    val fg = if (phase == 3) c.destructive else c.label
    val compact = LocalDensity.current.fontScale >= 1.2f
    Box(
        Modifier.height(34.dp).themeSurface(17.dp, c)
            .then(if (phase == 3) Modifier.border(1.dp, c.destructive.copy(alpha = 0.6f), CircleShape) else Modifier)
            .tactile(enabled = phase == 0 || phase == 3, label = when (phase) { 0 -> "Descargar"; 1 -> "Descargando $pct %"; 2 -> "Descargado"; else -> "Reintentar descarga" }) { env.library.toggleDownload(song) }
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        AnimatedContent(phase, label = "dl", transitionSpec = {
            (fadeIn(uiEaseOut(260)) + androidx.compose.animation.slideInVertically(uiEaseOut(260)) { it / 3 }) togetherWith
                (fadeOut(uiEaseOut(200)) + androidx.compose.animation.slideOutVertically(uiEaseOut(200)) { -it / 3 })
        }) { p ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                when (p) {
                    0 -> Icon(Icons.Rounded.ArrowDownward, null, tint = fg, modifier = Modifier.size(20.dp))
                    1 -> Spinner(15.dp)
                    2 -> Icon(Icons.Rounded.Check, null, tint = fg, modifier = Modifier.size(20.dp))
                    else -> Icon(Icons.Rounded.Refresh, null, tint = fg, modifier = Modifier.size(20.dp))
                }
                // Con letra grande (≥ 120 %) sólo el icono: si no, la fila no cabe y la cola se sale de la pantalla.
                if (!compact) {
                    Spacer(Modifier.width(6.dp))
                    Text(
                        when (p) { 0 -> "Descargar"; 1 -> "Descargando $pct %"; 2 -> "Descargado"; else -> "Reintentar" },
                        style = Typo.subheadline.medium, color = fg,
                    )
                }
            }
        }
    }
}

/** Barra de progreso arrastrable con los tiempos (Slider de iOS). */
@Composable
private fun Scrubber() {
    val c = Libre.colors
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    var dragging by remember { mutableStateOf<Float?>(null) }
    val duration = st.duration.coerceAtLeast(1.0)
    val fraction = dragging ?: (st.progress / duration).toFloat().coerceIn(0f, 1f)
    Column(Modifier.fillMaxWidth()) {
        BoxWithConstraints(
            Modifier.fillMaxWidth().height(31.dp)
                .pointerInput(duration) {
                    detectDragGestures(
                        onDragStart = { o -> dragging = (o.x / size.width).coerceIn(0f, 1f) },
                        onDrag = { change, _ -> dragging = (change.position.x / size.width).coerceIn(0f, 1f) },
                        onDragEnd = { dragging?.let { env.player.seekSeconds(it * duration) }; dragging = null },
                        onDragCancel = { dragging = null },
                    )
                }
                .pointerInput(duration) {
                    detectTapGestures { o -> env.player.seekSeconds((o.x / size.width).coerceIn(0f, 1f) * duration) }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            val w = maxWidth
            Box(Modifier.fillMaxWidth().height(4.dp).background(c.fill, CircleShape))
            Box(Modifier.width(w * fraction).height(4.dp).background(c.accent, CircleShape))
            Box(
                Modifier.offset(x = (w - 37.dp) * fraction).size(37.dp, 24.dp)
                    .dropShadow(CircleShape, Color.Black.copy(alpha = 0.18f), blur = 4.dp, offsetY = 1.dp)
                    .background(Color.White, CircleShape),
            )
        }
        Spacer(Modifier.height(4.dp))
        Row(Modifier.fillMaxWidth()) {
            Text(timeString(dragging?.let { it * duration } ?: st.progress), style = Typo.caption, color = c.secondaryLabel)
            Spacer(Modifier.weight(1f))
            Text(timeString(st.duration), style = Typo.caption, color = c.secondaryLabel)
        }
    }
}

// MARK: Cola -----------------------------------------------------------------------------------

@Composable
private fun QueueView(modifier: Modifier) {
    val c = Libre.colors
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    var editing by remember { mutableStateOf(false) }
    val upcoming = (st.queue.size - st.index - 1).coerceAtLeast(0)
    val rowPx = with(LocalDensity.current) { 56.dp.toPx() }
    var dragIndex by remember { mutableIntStateOf(-1) }
    var dragOffset by remember { mutableFloatStateOf(0f) }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("A continuación", style = Typo.headline, color = c.label)
                Text(songCount(upcoming), style = Typo.caption, color = c.secondaryLabel)
            }
            if (upcoming > 0) {
                Text(if (editing) "Listo" else "Editar", style = Typo.subheadline.semibold, color = c.accent, modifier = Modifier.tactile(label = "Editar cola") { editing = !editing }.padding(8.dp))
            }
        }
        LazyColumn(Modifier.weight(1f).edgeFade()) {
            itemsIndexed(st.queue, key = { i, s -> "$i-${s.id}" }) { i, song ->
                val dragged = i == dragIndex
                var menu by remember { mutableStateOf(false) }
                val row: @Composable () -> Unit = {
                    Row(
                        Modifier.fillMaxWidth().height(56.dp)
                            .graphicsLayer { translationY = if (dragged) dragOffset else 0f; shadowElevation = if (dragged) 8f else 0f }
                            .background(if (dragged) c.secondaryGrouped else Color.Transparent)
                            .then(if (editing) Modifier else Modifier.rowHighlight(onLongClick = { menu = true }) { env.player.skipTo(i) })
                            .padding(horizontal = 20.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (editing) {
                            IconTap(Icons.Rounded.RemoveCircle, "Quitar ${song.title}", tint = c.destructive) { env.player.removeFromQueue(i) }
                        }
                        if (i == st.index) {
                            Icon(Icons.AutoMirrored.Rounded.VolumeUp, null, tint = c.accent, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                        }
                        Column(Modifier.weight(1f)) {
                            Text(song.title, style = Typo.body, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(song.artist, style = Typo.caption, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        if (editing) {
                            Icon(
                                Icons.Rounded.DragHandle, "Mover", tint = c.tertiaryLabel,
                                modifier = Modifier.size(44.dp).padding(10.dp).pointerInput(i) {
                                    detectDragGestures(
                                        onDragStart = { dragIndex = i; dragOffset = 0f },
                                        onDrag = { change, d -> change.consume(); dragOffset += d.y },
                                        onDragEnd = {
                                            val to = (i + (dragOffset / rowPx).roundToInt()).coerceIn(0, st.queue.lastIndex)
                                            if (to != i) env.player.move(i, to)
                                            dragIndex = -1; dragOffset = 0f
                                        },
                                        onDragCancel = { dragIndex = -1; dragOffset = 0f },
                                    )
                                },
                            )
                        }
                    }
                }
                Box {
                    if (editing) row() else SwipeToRemove("Eliminar", onRemove = { env.player.removeFromQueue(i) }) { row() }
                    // Mantener pulsada una fila de la cola abre el mismo menú de canción que en el resto de la app.
                    ContextMenu(menu, { menu = false }, songMenu(song), preview = { SongPreview(song) })
                }
            }
        }
        if (upcoming > 0) {
            Box(Modifier.padding(horizontal = 20.dp)) {
                HoldToConfirmButton("Mantén para vaciar la cola", Icons.Rounded.ClearAll) { env.player.clearUpcoming() }
            }
        }
    }
}

// MARK: Horizontal: el casete o el vinilo a pantalla completa --------------------------------------------

@Composable
fun ImmersiveDeck(style: DeckStyle) {
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val song = st.current ?: return
    val scramble by Prefs.scramble.collectAsState()
    // Como iOS (.statusBarHidden + .persistentSystemOverlays(.hidden)): sin barra de estado ni de
    // navegación, que si no se dibujan encima del aparato. Asoman deslizando desde el borde.
    val view = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.DisposableEffect(view) {
        val window = (view.context as? android.app.Activity)?.window
        val bars = window?.let { androidx.core.view.WindowCompat.getInsetsController(it, view) }
        bars?.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        bars?.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
        onDispose { bars?.show(androidx.core.view.WindowInsetsCompat.Type.systemBars()) }
    }
    DarkSection {
        val c = Libre.colors
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            Box(Modifier.fillMaxSize().graphicsLayer { alpha = 0.55f }) { ThemeBackdrop(st.isPlaying, song) }
            Box(Modifier.fillMaxSize().padding(horizontal = 8.dp, vertical = 12.dp), contentAlignment = Alignment.Center) {
                if (style == DeckStyle.Vinyl) {
                    Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.fillMaxHeight().aspectRatio(1f)) { VinylView(song) }
                        Column(Modifier.widthIn(max = 300.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            ScrambleText(song.title, Typo.title, maxLines = 3, enabled = scramble)
                            Text(song.artist, style = Typo.title3, color = c.secondaryLabel, maxLines = 2)
                            Text("${timeString(st.progress)} / ${timeString(st.duration)}", style = Typo.headline, color = c.secondaryLabel)
                        }
                    }
                } else {
                    Box(Modifier.fillMaxHeight().aspectRatio(1.58f)) { CassetteView(song) }
                }
            }
        }
    }
}

/**
 * Bucle de tres estados, como RepeatButton en iOS: del color de los demás botones desactivado, con el
 * color del tema y fondo suave al repetir la lista, y con el «1» al repetir la canción.
 */
@Composable
private fun RepeatButton(mode: Int, onClick: () -> Unit) {
    val c = Libre.colors
    val on = mode != androidx.media3.common.Player.REPEAT_MODE_OFF
    val bg by androidx.compose.animation.animateColorAsState(if (on) c.accent.copy(alpha = 0.16f) else Color.Transparent, uiEaseOut(200), label = "repeatBg")
    Box(
        Modifier.size(44.dp).tactile(label = app.libremusic.playback.Repeat.label(mode), onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(38.dp, 34.dp).background(bg, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
            Icon(
                if (mode == androidx.media3.common.Player.REPEAT_MODE_ONE) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat,
                contentDescription = null,
                tint = if (on) c.accent else c.label,
                modifier = Modifier.size(24.dp),
            )
        }
    }
}
