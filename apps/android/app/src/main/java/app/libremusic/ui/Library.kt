package app.libremusic.ui


import app.libremusic.L
import androidx.compose.animation.core.animateFloat

import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.SortByAlpha
import androidx.compose.material.icons.rounded.Refresh

import androidx.compose.runtime.mutableIntStateOf

import androidx.compose.material.icons.rounded.Close

import androidx.compose.material.icons.rounded.ManageSearch

import app.libremusic.data.ImportJob
import app.libremusic.data.ImportMatcher
import app.libremusic.data.SpotifyImporter
import app.libremusic.data.ExportifyCsv
import app.libremusic.data.SimpMusicBackup
import app.libremusic.data.SimpPlaylist
import app.libremusic.data.TrackMatch
import app.libremusic.data.Matcher
import app.libremusic.data.AMTrack
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Restore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.compose.ui.graphics.graphicsLayer

import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.input.pointer.pointerInput
import kotlin.math.roundToInt
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.ui.zIndex
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.rounded.DragHandle
import app.libremusic.data.LibraryOrder
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.PlaylistAdd
import androidx.compose.material.icons.outlined.ArrowCircleDown
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.DownloadForOffline
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PlayCircleOutline
import androidx.compose.material.icons.rounded.RemoveCircle
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SwapVert
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.SaveAlt
import androidx.compose.material.icons.rounded.IosShare
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.foundation.layout.imePadding
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material.icons.rounded.QrCode2
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.libremusic.data.AMPlaylist
import app.libremusic.data.AppleMusicImporter
import app.libremusic.data.Playlist
import app.libremusic.data.Song
import app.libremusic.jam.JamPhase
import app.libremusic.jam.JamService
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Prefs
import app.libremusic.ui.theme.SfIcons
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Tokens
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.bold
import app.libremusic.ui.theme.semibold
import app.libremusic.ui.theme.themeSurface
import kotlinx.coroutines.launch

// Biblioteca «1.1» (LibraryV11.swift): las playlists son lo primero, en un carrusel de portadas
// grandes con Descargadas y Favoritos delante; debajo, el resto de la música en filas sobrias.

private const val CARD = 176
private val INSET = 20.dp

/** Artista principal: «Clarent y Quevedo» → «Clarent» (primaryArtist en iOS). */
fun primaryArtist(s: String): String =
    s.replace(Regex("\\s*(,| y | & | x | feat\\.? | ft\\.? | · ).*$", RegexOption.IGNORE_CASE), "").ifEmpty { L("Desconocido") }

/** Canciones únicas de favoritos, playlists y descargas. */
fun allSongs(favorites: List<Song>, playlists: List<Playlist>, downloads: List<Song>): List<Song> {
    val seen = HashSet<String>()
    return (favorites + playlists.flatMap { it.songs } + downloads).filter { seen.add(it.id) }
}

@Composable
private fun smartPalette(kind: SmartList) = if (kind == SmartList.Downloads) 2 else 0

@Composable
private fun SmartCover(kind: SmartList, size: Dp, radius: Dp) {
    Box(
        Modifier.size(size).clip(RoundedCornerShape(radius)).background(playlistGradient(smartPalette(kind))),
        contentAlignment = Alignment.Center,
    ) {
        // El glifo de Material ocupa 20/24 de su caja: ×1,2 para que mida lo mismo que el SF Symbol a 0,34.
        val icon = if (kind == SmartList.Downloads) Icons.Rounded.ArrowDownward else Icons.Rounded.Favorite
        val glyph = size * 0.34f * 1.2f
        Icon(icon, null, tint = Color.Black.copy(alpha = 0.18f), modifier = Modifier.offset(y = 3.dp).blur(6.dp).size(glyph))
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(glyph))
    }
}

/** Abre «Nueva playlist» (aviso con campo de texto). */
fun AppState.askNewPlaylist(onCreate: (String) -> Unit) {
    alert = AlertSpec(
        L("Nueva playlist"), field = L("Nombre"),
        buttons = listOf(AlertButton(L("Cancelar"), AlertButton.Role.Cancel), AlertButton(L("Crear")) { onCreate(it) }),
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LibraryScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val downloaded by env.library.downloadedSongs.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    val player by env.player.track.collectAsState()
    var addMenu by remember { mutableStateOf(false) }
    val songs = remember(data, downloaded) { allSongs(data.favorites, data.playlists, downloaded) }
    val stats by app.libremusic.data.PlayStats.data.collectAsState()
    val monthPlays = remember(stats) { stats.plays.count { it.at >= app.libremusic.data.PlayStats.since(app.libremusic.data.PlayStats.Period.Month) } }
    val placement by Prefs.smartPlacement.collectAsState()
    val smartInPlaylists = placement != "music"
    val newPlaylist = { env.app.askNewPlaylist { env.library.createPlaylist(it) } }

    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(top = 6.dp)) {
            // Cabecera
            Row(Modifier.fillMaxWidth().padding(horizontal = INSET), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(L("Biblioteca"), style = Typo.display(Tokens.TypeSize.DisplayLibrary, c.theme), color = c.label)
                    Spacer(Modifier.height(4.dp))
                    val off = downloaded.size
                    val summary = if (songs.isEmpty()) L("Aún no has guardado nada") else songCount(songs.size) + if (off > 0) L(" · {0} sin conexión", off) else ""
                    Text(summary, style = Typo.subheadline, color = c.secondaryLabel)
                }
                Spacer(Modifier.width(12.dp))
                Box {
                    Box(
                        Modifier.size(44.dp).themeSurface(22.dp, c).clip(CircleShape).tactile(label = L("Añadir playlist")) { addMenu = true },
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Rounded.Add, null, tint = c.accent, modifier = Modifier.size(24.dp)) }
                    ContextMenu(addMenu, { addMenu = false }, listOf(
                        MenuEntry.Action(L("Nueva playlist"), Icons.AutoMirrored.Rounded.PlaylistAdd) { newPlaylist() },
                        MenuEntry.Action(L("Importar de Apple Music"), Icons.Rounded.Download) { env.app.showImport = true },
                        MenuEntry.Divider,
                        MenuEntry.Action(L("Jam con amigos"), app.libremusic.ui.theme.JamIcon()) { env.app.showJam = true },
                    ))
                }
            }
            Spacer(Modifier.height(34.dp))

            // Fijados (x.1.1): en el sitio del antiguo carrusel de Playlists, con portadas igual de grandes y en el orden
            // que les dé uno arrastrando. Las playlists están ya sólo en la carpeta de «Tu música».
            PinnedCarousel(ver)
            Spacer(Modifier.height(34.dp))

            // El resto de la música
            MusicFolders(
                buildMap {
                    if (!smartInPlaylists) {
                        // Descargadas y Favoritos como filas (Ajustes › Apariencia › Biblioteca).
                        put("downloads", MusicFolder(SmartList.Downloads.title, downloaded.size, Icons.Rounded.DownloadForOffline) { env.app.push(Route.Smart(SmartList.Downloads)) })
                        put("favorites", MusicFolder(SmartList.Favorites.title, data.favorites.size, Icons.Rounded.Favorite) { env.app.push(Route.Smart(SmartList.Favorites)) })
                    }
                    put("playlists", MusicFolder(L("Playlists"), data.userPlaylists.size, Icons.AutoMirrored.Rounded.QueueMusic) { env.app.push(Route.Playlists) })
                    put("albums", MusicFolder(L("Tus álbumes"), data.albums.size, Icons.Rounded.LibraryMusic) { env.app.push(Route.Albums) })
                    put("songs", MusicFolder(L("Canciones"), songs.size, Icons.Rounded.MusicNote) { env.app.push(Route.AllSongs) })
                    put("artists", MusicFolder(L("Artistas"), songs.map { primaryArtist(it.artist) }.toSet().size, Icons.Rounded.Mic) { env.app.push(Route.Artists) })
                    put("recents", MusicFolder(L("Recientes"), data.recents.size, Icons.Rounded.Schedule) { env.app.push(Route.Recents) })
                    put("stats", MusicFolder(L("Estadísticas"), monthPlays, Icons.Rounded.BarChart) { env.app.push(Route.Stats) })
                },
            )
            BottomSpacer(28.dp)
        }
    }
}

private class MusicFolder(val title: String, val count: Int, val icon: androidx.compose.ui.graphics.vector.ImageVector, val open: () -> Unit)

/**
 * «Tu música» con sus carpetas en el orden de `musicOrder`. Mantener pulsada una carpeta entra en el modo edición
 * (como la pantalla de inicio de iOS o Android): las filas tiemblan, se arrastran con el asa y «Hecho» lo guarda.
 * Lo pidió Toxbox. Igual que `MusicFolders` en iOS.
 */
@Composable
private fun MusicFolders(folders: Map<String, MusicFolder>) {
    val c = Libre.colors
    val order by Prefs.musicOrder.collectAsState()
    var editing by remember { mutableStateOf(false) }
    val items = remember { androidx.compose.runtime.mutableStateListOf<String>() }
    LaunchedEffect(order, folders.keys) { items.clear(); items.addAll(order.filter { it in folders }) }
    val rowPx = with(androidx.compose.ui.platform.LocalDensity.current) { 62.dp.toPx() }
    var dragging by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableStateOf(0f) }
    val reduce = app.libremusic.ui.theme.LocalReduceMotion.current
    val wiggle = androidx.compose.animation.core.rememberInfiniteTransition(label = "wiggle")
    val angle by wiggle.animateFloat(
        // Suave (lo pidió Toxbox): poco ángulo y lento, con entrada y salida suaves.
        -0.45f, 0.45f,
        androidx.compose.animation.core.infiniteRepeatable(
            androidx.compose.animation.core.tween<Float>(320, easing = androidx.compose.animation.core.FastOutSlowInEasing),
            androidx.compose.animation.core.RepeatMode.Reverse,
        ),
        label = "angle",
    )
    fun done() {
        editing = false
        // Las que no se ven (Descargadas y Favoritos en el carrusel) conservan su sitio relativo al final.
        Prefs.setMusicOrder(items.toList() + order.filter { it !in items })
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = INSET), verticalAlignment = Alignment.Bottom) {
        Text(L("Tu música"), style = Typo.display(Tokens.TypeSize.DisplaySection, c.theme), color = c.label, modifier = Modifier.weight(1f))
        if (editing) {
            Text(L("Hecho"), style = Typo.body.semibold, color = c.accent, modifier = Modifier.tactile(label = L("Terminar de ordenar")) { done() }.padding(8.dp))
        }
    }
    if (editing) {
        Text(L("Arrastra ≡ para cambiar el orden."), style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(horizontal = INSET, vertical = 4.dp))
    }
    Spacer(Modifier.height(12.dp))
    Column(Modifier.padding(horizontal = INSET)) {
        items.forEachIndexed { i, key -> androidx.compose.runtime.key(key) { folders[key]?.let { f ->
            val isDragging = dragging == key
            Box(
                Modifier.zIndex(if (isDragging) 1f else 0f).graphicsLayer {
                    translationY = if (isDragging) dragOffset else 0f
                    rotationZ = if (editing && !isDragging && !reduce) angle * (if (i % 2 == 0) 1f else -1f) else 0f
                    // Bordes redondeados también al levantarla (antes era un rectángulo).
                    shape = RoundedCornerShape(16.dp)
                    clip = isDragging
                    if (isDragging) { scaleX = 1.03f; scaleY = 1.03f; shadowElevation = 14.dp.toPx() }
                },
            ) {
                LibraryLinkRow(
                    f.title, f.count, f.icon, last = i == items.lastIndex,
                    onLongClick = if (editing) null else ({ editing = true }),
                    trailing = if (!editing) null else { {
                        Box(
                            Modifier.size(44.dp).semanticsButton("Mover ${f.title}") {}.pointerInput(key) {
                                detectDragGestures(
                                    onDragStart = { dragging = key; dragOffset = 0f },
                                    onDragEnd = { dragging = null; dragOffset = 0f },
                                    onDragCancel = { dragging = null; dragOffset = 0f },
                                    onDrag = { change, amount ->
                                        change.consume()
                                        dragOffset += amount.y
                                        val from = items.indexOf(key)
                                        val to = (from + (dragOffset / rowPx).roundToInt()).coerceIn(0, items.lastIndex)
                                        if (to != from) { items.add(to, items.removeAt(from)); dragOffset -= (to - from) * rowPx }
                                    },
                                )
                            },
                            contentAlignment = Alignment.Center,
                        ) { Icon(Icons.Rounded.DragHandle, null, tint = c.tertiaryLabel, modifier = Modifier.size(24.dp)) }
                    } },
                ) { if (editing) Unit else f.open() }
            }
        } } }
    }
}

/**
 * «Fijados» en Biblioteca (x.1.1): ocupa el sitio del antiguo carrusel de Playlists, con portadas igual de grandes.
 * Manteniendo pulsada una portada se levanta y se arrastra a otro sitio; si se suelta sin moverla, sale su menú. El
 * orden se guarda en [Prefs.pinnedOrder] y lo sigue también la fila de Inicio. Igual que `PinnedCarousel` en iOS.
 */
@Composable
private fun PinnedCarousel(ver: Int) {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val order by Prefs.pinnedOrder.collectAsState()
    val dl by env.library.downloads.collectAsState()
    val pinned = LibraryOrder.pinned(data.playlists.filter { it.pinned }, order)
    val byId = pinned.associateBy { it.id }
    Text(L("Fijados"), style = Typo.display(Tokens.TypeSize.DisplaySection, c.theme), color = c.label, modifier = Modifier.padding(horizontal = INSET))
    Spacer(Modifier.height(14.dp))
    if (pinned.isEmpty()) {
        // Vacío: el hueco se queda, con lo que hay que hacer para llenarlo.
        Row(Modifier.fillMaxWidth().padding(horizontal = INSET), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(CARD.dp).drawDashedBorder(c.label.copy(alpha = 0.22f), Tokens.Radius.PlaylistCard.dp),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Outlined.PushPin, null, tint = c.secondaryLabel, modifier = Modifier.size(32.dp)) }
            Spacer(Modifier.width(18.dp))
            Text(
                L("Pulsa la chincheta en una playlist o un álbum y lo tendrás aquí, en el orden que quieras."),
                style = Typo.subheadline, color = c.secondaryLabel, modifier = Modifier.weight(1f),
            )
        }
        return
    }
    ReorderRow(
        pinned.map { it.id }, CARD.dp, 18.dp, INSET,
        onMoved = { Prefs.setPinnedOrder(it) },
        onOpen = { env.app.push(Route.PlaylistR(it)) },
        label = { id -> byId[id]?.name.orEmpty() },
    ) { id, menu, closeMenu ->
        val p = byId[id] ?: return@ReorderRow
        val offline = p.songs.count { dl[it.id]?.isDone == true }
        Box {
            CoverTile(p.name, p.album?.line?.ifEmpty { null } ?: songCount(p.songs.size), offlineAll = offline > 0 && offline == p.songs.size) {
                PlaylistCover(p, CARD.dp, Tokens.Radius.PlaylistCard.dp, env.library.coverFile(p.id), ver)
            }
            ContextMenu(menu, closeMenu, listOf(
                MenuEntry.Action(L("Reproducir"), Icons.Rounded.PlayArrow) { if (p.songs.isNotEmpty()) env.player.play(p.songs, 0) },
                MenuEntry.Action(L("Aleatorio"), Icons.Rounded.Shuffle) { if (p.songs.isNotEmpty()) env.player.play(p.songs.shuffled(), 0) },
                MenuEntry.Action(L("Soltar de arriba"), Icons.Outlined.PushPin) { env.library.setPinned(p.id, false) },
            ))
        }
    }
}

/**
 * Fila horizontal que se reordena manteniendo pulsado y arrastrando, como [ReorderGrid] pero en una sola fila: la
 * portada se levanta, las demás se apartan y, al acercarla a un borde, la fila se desplaza sola. Soltar sin haberla
 * movido abre su menú ([cell] recibe `menu` y cómo cerrarlo). Las celdas miden [side] de ancho.
 */
@Composable
private fun ReorderRow(
    keys: List<String>,
    side: Dp,
    gap: Dp,
    inset: Dp,
    onMoved: (List<String>) -> Unit,
    onOpen: (String) -> Unit,
    label: (String) -> String,
    cell: @Composable (key: String, menu: Boolean, closeMenu: () -> Unit) -> Unit,
) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
    val reduceMotion = app.libremusic.ui.theme.LocalReduceMotion.current
    val scroll = rememberScrollState()
    val items = remember { androidx.compose.runtime.mutableStateListOf<String>() }
    var dragging by remember { mutableStateOf<String?>(null) }
    var drag by remember { mutableStateOf(0f) }
    var moved by remember { mutableStateOf(false) }
    var menuKey by remember { mutableStateOf<String?>(null) }
    var viewport by remember { mutableStateOf(0) }
    LaunchedEffect(keys) { if (dragging == null) { items.clear(); items.addAll(keys) } }
    val step = with(density) { (side + gap).roundToPx() }
    val insetPx = with(density) { inset.roundToPx() }
    val sidePx = with(density) { side.roundToPx() }

    // La celda arrastrada pasa a la posición que tiene debajo; el desplazamiento se cuenta desde la nueva.
    fun follow(key: String) {
        val from = items.indexOf(key)
        if (from < 0) return
        val to = (from + (drag / step).roundToInt()).coerceIn(0, items.lastIndex)
        if (to != from) {
            items.add(to, items.removeAt(from))
            drag -= (to - from) * step
        }
    }
    // Cerca de un borde, la fila avanza sola en cada fotograma mientras se arrastra.
    LaunchedEffect(dragging) {
        val key = dragging ?: return@LaunchedEffect
        val edge = with(density) { 56.dp.toPx() }
        val max = with(density) { 14.dp.toPx() }
        while (dragging == key) {
            androidx.compose.runtime.withFrameNanos { }
            val i = items.indexOf(key)
            if (i < 0) break
            val left = insetPx + i * step + drag - scroll.value
            val right = left + sidePx
            val speed = when {
                left < edge -> -((edge - left) / edge * max)
                right > viewport - edge -> (right - (viewport - edge)) / edge * max
                else -> 0f
            }.coerceIn(-max, max)
            if (speed != 0f) {
                drag += scroll.dispatchRawDelta(speed)
                follow(key)
            }
        }
    }

    val width = inset * 2 + side * items.size + gap * (items.size - 1).coerceAtLeast(0)
    Box(Modifier.fillMaxWidth().onSizeChanged { viewport = it.width }.horizontalScroll(scroll)) {
        Box(Modifier.width(width)) {
            items.forEachIndexed { index, key -> androidx.compose.runtime.key(key) {
                val isDragging = dragging == key
                val target = androidx.compose.ui.unit.IntOffset(insetPx + index * step, 0)
                val placed by androidx.compose.animation.core.animateIntOffsetAsState(
                    target, if (reduceMotion) androidx.compose.animation.core.snap<androidx.compose.ui.unit.IntOffset>() else uiEaseOut<androidx.compose.ui.unit.IntOffset>(220), label = "pinned",
                )
                val lift by androidx.compose.animation.core.animateFloatAsState(if (isDragging) 1f else 0f, if (reduceMotion) androidx.compose.animation.core.snap() else uiEaseOut(160), label = "lift")
                Box(
                    Modifier
                        .offset { if (isDragging) target else placed }
                        .width(side)
                        .zIndex(if (isDragging) 1f else 0f)
                        .graphicsLayer {
                            if (isDragging) translationX = drag
                            scaleX = 1f + 0.05f * lift; scaleY = scaleX
                            shadowElevation = 16.dp.toPx() * lift
                        }
                        .tactile(label = label(key)) { onOpen(key) }
                        .pointerInput(key) {
                            detectDragGesturesAfterLongPress(
                                onDragStart = {
                                    dragging = key; drag = 0f; moved = false
                                    haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                                },
                                onDragEnd = {
                                    dragging = null; drag = 0f
                                    if (moved) {
                                        haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove)
                                        onMoved(items.toList())
                                    } else menuKey = key
                                },
                                onDragCancel = { dragging = null; drag = 0f },
                                onDrag = { change, amount ->
                                    change.consume()
                                    drag += amount.x
                                    if (kotlin.math.abs(drag) > viewConfiguration.touchSlop) moved = true
                                    follow(key)
                                },
                            )
                        },
                ) { cell(key, menuKey == key) { menuKey = null } }
            } }
        }
    }
}

/** Borde discontinuo del hueco de Fijados cuando no hay nada fijado. */
private fun Modifier.drawDashedBorder(color: Color, radius: Dp) = this.drawBehind {
    val w = 1.5.dp.toPx()
    drawRoundRect(
        color = color,
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius.toPx()),
        style = Stroke(width = w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 6.dp.toPx()))),
        topLeft = androidx.compose.ui.geometry.Offset(w / 2, w / 2),
        size = androidx.compose.ui.geometry.Size(size.width - w, size.height - w),
    )
}

/** Portada grande con título y una línea (Fijados en Biblioteca). Sólo dibuja: el toque lo lleva quien la usa. */
@Composable
private fun CoverTile(title: String, subtitle: String, offlineAll: Boolean = false, cover: @Composable () -> Unit) {
    val c = Libre.colors
    Column(Modifier.width(CARD.dp)) {
        Box(Modifier.shadowSoft(16.dp, RoundedCornerShape(Tokens.Radius.PlaylistCard.dp), 0.14f)) { cover() }
        Spacer(Modifier.height(10.dp))
        Text(title, style = Typo.callout.bold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(2.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(subtitle, style = Typo.caption, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            if (offlineAll) {
                Spacer(Modifier.width(4.dp))
                Icon(Icons.Rounded.DownloadForOffline, L("Descargada"), tint = c.secondaryLabel, modifier = Modifier.size(13.dp))
            }
        }
    }
}

/** Fila grande de navegación: icono en círculo, título, recuento y chevron, con líneas finas. */
@Composable
private fun LibraryLinkRow(
    title: String, count: Int, icon: androidx.compose.ui.graphics.vector.ImageVector, last: Boolean = false,
    onLongClick: (() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null, onClick: () -> Unit,
) {
    val c = Libre.colors
    // El resaltado al tocar, con las esquinas redondeadas (lo pidió Toxbox).
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).rowHighlight(onLongClick = onLongClick, onClick = onClick)) {
        Row(Modifier.fillMaxWidth().padding(vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(36.dp).themeSurface(18.dp, c).clip(CircleShape), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = c.label, modifier = Modifier.size(18.dp))
            }
            Spacer(Modifier.width(14.dp))
            Text(title, style = Typo.title3.semibold, color = c.label, modifier = Modifier.weight(1f))
            Text("$count", style = Typo.subheadline, color = c.secondaryLabel)
            Spacer(Modifier.width(6.dp))
            if (trailing != null) trailing()
            else Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = c.tertiaryLabel, modifier = Modifier.size(20.dp))
        }
        if (!last) Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.separator))
    }
}

// MARK: Detalle común (playlists, listas inteligentes, canciones) --------------------------------------

private enum class SongFilter(private val titleText: () -> String) { All({ L("Todas") }), Downloaded({ L("Descargadas") }), Favorites({ L("Favoritas") }) ;
    val title: String get() = titleText()
}

@Composable
private fun CollectionDetail(
    title: String,
    songs: List<Song>,
    filters: Boolean = true,
    /** Lista dueña de «Descargar todo» (id de la playlist o «favorites»); null = sin el botón. */
    bulkOwner: String? = null,
    emptyText: String = L("Todavía no hay nada aquí"),
    onRemove: ((Song) -> Unit)? = null,
    onEdit: (() -> Unit)? = null,
    /** «Compartir con QR» (0.6 de x.1.1; null = sin el botón). */
    onShare: (() -> Unit)? = null,
    /** Fijar arriba en Biblioteca e Inicio (null = sin el botón). */
    pinned: Boolean? = null,
    onPin: (() -> Unit)? = null,
    /** Fila extra encima de las canciones (p. ej. «Sin añadir» de una importación). */
    above: (@Composable () -> Unit)? = null,
    cover: @Composable (Dp) -> Unit,
) {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val dl by env.library.downloads.collectAsState()
    val player by env.player.track.collectAsState()
    var filter by remember { mutableStateOf(SongFilter.All) }
    val offline = songs.count { dl[it.id]?.isDone == true }
    val favCount = songs.count { s -> data.favorites.any { it.id == s.id } }
    val visible = when (filter) {
        SongFilter.All -> songs.distinctBy { it.id }
        SongFilter.Downloaded -> songs.filter { dl[it.id]?.isDone == true }
        SongFilter.Favorites -> songs.filter { s -> data.favorites.any { it.id == s.id } }
    }
    val lit = if (songs.isEmpty()) 0.0 else offline.toDouble() / songs.size
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                NavBar(null, onBack = { env.app.pop() }) {
                    if (onPin != null && pinned != null) {
                        ToolbarButton(
                            if (pinned) Icons.Rounded.PushPin else Icons.Outlined.PushPin, if (pinned) L("Soltar de arriba") else L("Fijar arriba"),
                            tint = if (pinned) c.accent else c.label, onClick = onPin,
                        )
                    }
                    if (onShare != null) ToolbarButton(Icons.Rounded.QrCode2, L("Compartir con QR"), tint = c.label, onClick = onShare)
                    if (onEdit != null) ToolbarButton(Icons.Rounded.Edit, L("Editar playlist"), onClick = onEdit)
                }
            }
            item {
                Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Spacer(Modifier.height(24.dp))
                    Box(Modifier.size(268.dp), contentAlignment = Alignment.Center) {
                        DotRing(lit, 262.dp, c.accent)
                        Box(Modifier.size(228.dp).shadowSoft(22.dp, CircleShape, 0.2f).clip(CircleShape)) { cover(228.dp) }
                    }
                    Spacer(Modifier.height(18.dp))
                    Text(title, style = Typo.display(Tokens.TypeSize.DisplayScreen, c.theme), color = c.label, textAlign = TextAlign.Center, maxLines = 2)
                    Spacer(Modifier.height(6.dp))
                    Text(songCount(songs.size) + if (offline > 0) L(" · {0} sin conexión", offline) else "", style = Typo.subheadline, color = c.secondaryLabel)
                    Spacer(Modifier.height(20.dp))
                    PlayShuffleBar(visible.ifEmpty { songs }) { list, i -> env.player.play(list, i) }
                    if (bulkOwner != null) {
                        Spacer(Modifier.height(20.dp))
                        DownloadAllButton(bulkOwner, songs)
                    }
                    if (filters && songs.isNotEmpty()) {
                        Spacer(Modifier.height(20.dp))
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SongFilter.entries.forEach { f ->
                                val on = filter == f
                                Row(
                                    Modifier.height(36.dp)
                                        .then(if (on) Modifier.background(c.label, CircleShape) else Modifier.themeSurface(18.dp, c))
                                        .clip(CircleShape)
                                        .tactile(label = f.title) { filter = f }
                                        .padding(horizontal = 14.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    val fg = if (on) c.background else c.label
                                    Text(f.title, style = Typo.subheadline.semibold, color = fg)
                                    if (f != SongFilter.All) {
                                        Spacer(Modifier.width(5.dp))
                                        Text("${if (f == SongFilter.Downloaded) offline else favCount}", style = Typo.subheadline.semibold, color = fg.copy(alpha = 0.7f))
                                    }
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }
            }
            if (above != null) item(key = "above") { above() }
            items(visible, key = { it.id }) { s ->
                if (onRemove != null) {
                    SwipeToRemove(onRemove = { onRemove(s) }) { SongRow(s, visible, Modifier.padding(start = 16.dp, end = 8.dp)) }
                } else {
                    SongRow(s, visible, Modifier.padding(start = 16.dp, end = 8.dp))
                }
                RowSeparator()
            }
            if (visible.isEmpty()) item {
                val text = when {
                    songs.isEmpty() -> emptyText
                    filter == SongFilter.Downloaded -> L("Ninguna canción de esta lista está descargada.")
                    filter == SongFilter.Favorites -> L("Aún no has marcado favoritas aquí.")
                    else -> emptyText
                }
                CenterNote(text, 8.dp)
            }
            item { BottomSpacer() }
        }
    }
}


/**
 * «Descargar todo» de una lista (playlist, Favoritos o álbum): pendiente → progreso (tocar detiene)
 * → completa (tocar ofrece quitar lo descargado, con confirmación). Igual que en iOS.
 */
@Composable
fun DownloadAllButton(owner: String, songs: List<Song>, title: String? = null, onStart: (() -> Unit)? = null) {
    val env = LocalEnv.current
    val dl by env.library.downloads.collectAsState()
    val bulk by env.library.bulk.collectAsState()
    val total = songs.size
    val done = songs.count { dl[it.id]?.isDone == true }
    // Sólo «Descargando» en la lista que lo pidió, aunque otras compartan canciones.
    val mine = bulk[owner].orEmpty()
    val running = songs.any { it.id in mine && dl[it.id]?.isDone != true }
    val complete = total > 0 && done == total
    val pausedSet by env.library.paused.collectAsState()
    val paused = !complete && !running && owner in pausedSet
    val c = Libre.colors
    // Pausar o Cancelar mientras descarga; Reanudar o Cancelar en pausa. Cancelar no borra lo ya descargado.
    if (running || paused) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (running) {
                PillButton(L("{0} de {1} · Pausar", done, total), null, prominent = false, modifier = Modifier.weight(1f), leading = { Spinner(16.dp, c.accent) }) { env.library.pauseBulk(owner) }
            } else {
                PillButton(L("Reanudar · {0} de {1}", done, total), Icons.Rounded.PlayCircleOutline, prominent = false, modifier = Modifier.weight(1f)) {
                    env.library.downloadAll(owner, songs)
                }
            }
            Text(
                L("Cancelar"), style = Typo.subheadline.semibold, color = c.accent,
                modifier = Modifier.heightIn(min = 44.dp).tactile(label = L("Cancelar la descarga; lo ya descargado se queda")) { env.library.cancelBulk(owner) }
                    .padding(horizontal = 8.dp, vertical = 12.dp),
            )
        }
        return
    }
    when {
        complete -> PillButton(L("Disponible sin conexión"), Icons.Rounded.CheckCircle, prominent = false, modifier = Modifier.fillMaxWidth()) {
            env.app.alert = AlertSpec(
                title = if (title != null) L("¿Quitar las descargas de «{0}»?", title) else L("¿Quitar las descargas?"),
                message = L("Dejarán de estar disponibles sin conexión, también en otras listas que las tengan."),
                buttons = listOf(
                    AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
                    AlertButton(L("Quitar {0}", songCount(done)), AlertButton.Role.Destructive) { songs.forEach(env.library::removeDownload) },
                ),
            )
        }
        else -> PillButton(
            if (done > 0) L("Descargar las {0} que faltan", total - done) else L("Descargar todo"),
            Icons.Outlined.ArrowCircleDown, prominent = false, modifier = Modifier.fillMaxWidth(), enabled = total > 0,
        ) { env.library.downloadAll(owner, songs); onStart?.invoke() }
    }
}

@Composable
fun PlaylistDetailScreen(id: String) {
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    val p = data.playlists.firstOrNull { it.id == id } ?: return
    val pendingAll by app.libremusic.data.PendingImports.all.collectAsState()
    val pending = pendingAll[p.id].orEmpty()
    CollectionDetail(
        p.name, p.songs, bulkOwner = p.id,
        onShare = { env.app.sharing = p.id },
        emptyText = L("Mantén pulsada una canción en Buscar o Inicio para añadirla."),
        onRemove = { env.library.removeFromPlaylist(p.id, it.id) },
        onEdit = { env.app.editing = p.id },
        pinned = p.pinned,
        onPin = {
            env.library.setPinned(p.id, !p.pinned)
            env.app.toast = if (p.pinned) L("Ya no está fijado") else L("Fijado arriba en Biblioteca e Inicio")
        },
        above = pending.takeIf { it.isNotEmpty() }?.let { l ->
            {
                GlassRowItem({ env.app.push(Route.PendingImport(p.id)) }) {
                    Icon(Icons.Rounded.ManageSearch, null, tint = Libre.colors.accent, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(L("Sin añadir: {0}", songCount(l.size)), style = Typo.body.copy(fontWeight = FontWeight.Medium), color = Libre.colors.label)
                        Text(L("De la importación. Toca para buscarlas otra vez."), style = Typo.caption, color = Libre.colors.secondaryLabel)
                    }
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = Libre.colors.tertiaryLabel, modifier = Modifier.size(20.dp))
                }
            }
        },
    ) { side -> PlaylistCover(p, side, 0.dp, env.library.coverFile(p.id), ver) }
}

@Composable
fun SmartListScreen(kind: SmartList) {
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val downloaded by env.library.downloadedSongs.collectAsState()
    when (kind) {
        SmartList.Downloads -> CollectionDetail(
            kind.title, downloaded, filters = false,
            emptyText = L("Descarga canciones con la flecha de cada fila o con «Descargar todo» en una playlist."),
            onRemove = { env.library.removeDownload(it) },
        ) { side -> SmartCover(kind, side, 0.dp) }
        SmartList.Favorites -> CollectionDetail(
            kind.title, data.favorites, filters = false, bulkOwner = "favorites",
            emptyText = L("Toca el corazón de una canción para guardarla aquí."),
            onRemove = { env.library.toggleFavorite(it) },
        ) { side -> SmartCover(kind, side, 0.dp) }
    }
}

@Composable
fun SongListScreen(title: String, songs: List<Song>) {
    CollectionDetail(title, songs) { side -> CoverImage(songs.firstOrNull()?.thumb((side.value * 3).toInt()), Modifier.fillMaxSize()) }
}

@Composable
fun AllSongsScreen() {
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val downloaded by env.library.downloadedSongs.collectAsState()
    SongListScreen(L("Canciones"), allSongs(data.favorites, data.playlists, downloaded).sortedBy { it.title.lowercase() })
}

@Composable
fun RecentsScreen() {
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    SongListScreen(L("Recientes"), data.recents)
}

@Composable
fun ArtistScreen(name: String) {
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val downloaded by env.library.downloadedSongs.collectAsState()
    SongListScreen(name, allSongs(data.favorites, data.playlists, downloaded).filter { primaryArtist(it.artist) == name })
}

/** Lista con el estilo de los List de iOS sobre el fondo del tema (para Artistas y Playlists). */
@Composable
private fun PlainListScreen(
    title: String,
    empty: String?,
    /** Buscador de la lista (texto y cambio), como `.searchable` en iOS; null = sin buscador. */
    search: Pair<String, (String) -> Unit>? = null,
    noMatches: Boolean = false,
    /** Botón arriba a la derecha (p. ej. ordenar). */
    navTrailing: @Composable () -> Unit = {},
    content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit,
) {
    val env = LocalEnv.current
    val player by env.player.track.collectAsState()
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        // imePadding: el teclado no tapa el final de la lista.
        LazyColumn(Modifier.fillMaxSize().imePadding()) {
            item { NavBar(null, onBack = { env.app.pop() }, trailing = navTrailing) }
            item { LargeTitle(title, Modifier.padding(bottom = 8.dp)) }
            if (search != null && empty == null) item(key = "search") {
                SearchField(search.first, search.second, { keyboard?.hide() }, Modifier.padding(start = 16.dp, end = 16.dp, bottom = 10.dp), placeholder = L("Buscar en {0}", title.lowercase()))
            }
            content()
            if (empty != null) item { CenterNote(empty, 60.dp) }
            else if (noMatches && search != null) item { CenterNote(L("Nada coincide con «{0}»", search.first.trim()), 40.dp) }
            item { BottomSpacer() }
        }
    }
}

/** Fila con la superficie del tema (glassRow con inset). */
@Composable
fun GlassRowItem(onClick: () -> Unit, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    val c = Libre.colors
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 3.dp)
            .then(if (c.theme.styled) Modifier.themeSurface(Tokens.Radius.Row.dp, c) else Modifier.background(c.secondaryGrouped, RoundedCornerShape(10.dp)))
            .clip(RoundedCornerShape(Tokens.Radius.Row.dp))
            .rowHighlight(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Composable
fun ArtistsScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val downloaded by env.library.downloadedSongs.collectAsState()
    // Orden A-Z / Z-A con el botón de arriba a la derecha (Fase 3.1); se recuerda (ajuste `artistsSort`).
    var descending by remember { mutableStateOf(Prefs.artistsDescending) }
    val groups = remember(data, downloaded, descending) {
        val sorted = allSongs(data.favorites, data.playlists, downloaded).groupBy { primaryArtist(it.artist) }.toList()
            .sortedBy { app.libremusic.data.LocalSearch.fold(it.first) }
        if (descending) sorted.reversed() else sorted
    }
    var query by rememberSaveable { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    // Los nombres se normalizan una vez por lista; al escribir sólo se compara (rápido con miles).
    val folded = remember(groups) { groups.map { app.libremusic.data.LocalSearch.fold(it.first) } }
    val shown = remember(groups, query) { app.libremusic.data.LocalSearch.filter(groups, folded, query) }
    PlainListScreen(
        L("Artistas"), if (groups.isEmpty()) L("Guarda canciones para ver sus artistas") else null, query to { q: String -> query = q }, noMatches = shown.isEmpty(),
        navTrailing = {
            if (groups.isNotEmpty()) {
                Row(
                    Modifier.tactile(label = if (descending) L("Ordenar de la A a la Z") else L("Ordenar de la Z a la A")) {
                        descending = !descending; Prefs.artistsDescending = descending
                    }.padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.SortByAlpha, null, tint = c.accent, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(if (descending) "Z-A" else "A-Z", style = Typo.body.copy(fontWeight = FontWeight.SemiBold), color = c.accent)
                }
            }
        },
    ) {
        items(shown, key = { it.first }) { (name, songs) ->
            // Al tocar se abre su perfil de YouTube Music (discografía completa); sin red o sin encontrarlo, sus canciones.
            GlassRowItem({ openArtistProfile(env, scope, name) }) {
                CoverImage(songs.first().thumb(160), Modifier.size(46.dp).clip(CircleShape))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(name, style = Typo.body.copy(fontWeight = FontWeight.Medium), color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(songCount(songs.size), style = Typo.caption, color = c.secondaryLabel)
                }
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = c.tertiaryLabel, modifier = Modifier.size(20.dp))
            }
        }
    }
}

/**
 * Playlists (2.9 de x.1.1): la carpeta de «Tu música», en cuadrícula como «Tus álbumes». Es el único sitio de las
 * playlists: el carrusel de Biblioteca lo ocupa ahora Fijados. Con Descargadas y Favoritos «en Playlists» (Ajustes ›
 * Biblioteca), van aquí con su portada. Manteniendo pulsada una portada se arrastra y el orden pasa a «A mano». El
 * lápiz lleva a «Editar playlists» (ordenar por…).
 */
@Composable
fun PlaylistsListScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val downloaded by env.library.downloadedSongs.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    val sort by Prefs.playlistSort.collectAsState()
    val order by Prefs.playlistOrder.collectAsState()
    val placement by Prefs.smartPlacement.collectAsState()
    val byId = data.playlists.associateBy { it.id }
    val smartIn = placement != "music"
    val keys = LibraryOrder.keys(data.userPlaylists, sort, order, smartIn)
    val title = { key: String ->
        when (key) {
            LibraryOrder.DOWNLOADS -> SmartList.Downloads.title
            LibraryOrder.FAVORITES -> SmartList.Favorites.title
            else -> byId[key]?.name.orEmpty()
        }
    }
    val subtitle = { key: String ->
        when (key) {
            LibraryOrder.DOWNLOADS -> songCount(downloaded.size)
            LibraryOrder.FAVORITES -> songCount(data.favorites.size)
            else -> songCount(byId[key]?.songs?.size ?: 0)
        }
    }
    var query by rememberSaveable { mutableStateOf("") }
    val shown = remember(keys, query, data) { app.libremusic.data.LocalSearch.filter(keys, query) { title(it) } }
    PlainListScreen(
        L("Playlists"), if (keys.isEmpty()) L("Todavía no hay playlists") else null, query to { q: String -> query = q }, noMatches = shown.isEmpty(),
        navTrailing = { ToolbarButton(Icons.Rounded.Edit, L("Editar el orden de las playlists"), tint = c.label) { env.app.push(Route.ReorderPlaylists) } },
    ) {
        if (shown.isNotEmpty()) {
            item { ReorderHint(query.isBlank()) }
            item {
                ReorderGrid(
                    shown, enabled = query.isBlank(),
                    onMoved = { moved ->
                        Prefs.setPlaylistOrder(LibraryOrder.merge(keys, moved))
                        Prefs.setPlaylistSort("custom")
                    },
                    onOpen = { key ->
                        env.app.push(when (key) {
                            LibraryOrder.DOWNLOADS -> Route.Smart(SmartList.Downloads)
                            LibraryOrder.FAVORITES -> Route.Smart(SmartList.Favorites)
                            else -> Route.PlaylistR(key)
                        })
                    },
                    label = { "${title(it)}, ${subtitle(it)}" },
                ) { key, side ->
                    Column {
                        Box(Modifier.dropShadow(RoundedCornerShape(14.dp), Color.Black.copy(alpha = 0.14f), blur = 12.dp, offsetY = 6.dp)) {
                            when (key) {
                                LibraryOrder.DOWNLOADS -> SmartCover(SmartList.Downloads, side, 14.dp)
                                LibraryOrder.FAVORITES -> SmartCover(SmartList.Favorites, side, 14.dp)
                                else -> byId[key]?.let { PlaylistCover(it, side, radius = 14.dp, coverFile = env.library.coverFile(it.id), coverVersion = ver) }
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(title(key), style = Typo.subheadline.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(subtitle(key), style = Typo.caption, color = c.secondaryLabel, maxLines = 1)
                    }
                }
            }
        }
    }
}

/** Cómo se reordena la cuadrícula; buscando no se puede (se ordenaría sólo lo encontrado). */
@Composable
private fun ReorderHint(enabled: Boolean) {
    Text(
        if (enabled) L("Mantén pulsada una portada y arrástrala para cambiar el orden.") else L("Borra la búsqueda para cambiar el orden."),
        style = Typo.footnote, color = Libre.colors.secondaryLabel, modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 4.dp, bottom = 12.dp),
    )
}

/** «Tus álbumes»: los álbumes guardados o descargados desde su página, en cuadrícula y con buscador. */
@Composable
fun AlbumsScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    val albumSort by Prefs.albumSort.collectAsState()
    val albumOrder by Prefs.albumOrder.collectAsState()
    // Orden propio arrastrando (2.9 de x.1.1), como Playlists.
    val albums = LibraryOrder.albums(data.albums, albumSort, albumOrder)
    val byId = albums.associateBy { it.id }
    var query by rememberSaveable { mutableStateOf("") }
    val shown = remember(albums, query) { app.libremusic.data.LocalSearch.filter(albums, query) { "${it.name} ${it.album?.artist.orEmpty()}" } }
    PlainListScreen(L("Tus álbumes"), null, if (albums.isEmpty()) null else query to { q: String -> query = q }, noMatches = albums.isNotEmpty() && shown.isEmpty()) {
        if (albums.isEmpty()) item { AlbumsEmpty() } else if (shown.isNotEmpty()) {
            item { ReorderHint(query.isBlank()) }
            item {
                ReorderGrid(
                    shown.map { it.id }, enabled = query.isBlank(),
                    onMoved = { Prefs.setAlbumOrder(it); Prefs.setAlbumSort("custom") },
                    onOpen = { env.app.push(Route.PlaylistR(it)) },
                    label = { id -> byId[id]?.let { "${it.name}, ${it.album?.line.orEmpty()}" }.orEmpty() },
                ) { id, side ->
                    val p = byId[id] ?: return@ReorderGrid
                    Column {
                        Box(Modifier.dropShadow(RoundedCornerShape(14.dp), Color.Black.copy(alpha = 0.14f), blur = 12.dp, offsetY = 6.dp)) {
                            PlaylistCover(p, side, radius = 14.dp, coverFile = env.library.coverFile(p.id), coverVersion = ver)
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(p.name, style = Typo.subheadline.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(p.album?.line?.ifEmpty { null } ?: songCount(p.songs.size), style = Typo.caption, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

/**
 * Cuadrícula de dos columnas que se reordena manteniendo pulsado y arrastrando (2.9 de x.1.1): la portada se levanta
 * (escala 1,05 y sombra), las demás se apartan con suavidad y al soltar llega el orden nuevo a [onMoved]. Todas las
 * celdas cuelgan del mismo padre y se colocan por su índice, para que el gesto no se corte al cambiar de fila. Con
 * [enabled] = false (buscando) sólo se tocan. Igual que `ReorderGrid` en iOS.
 */
@Composable
fun ReorderGrid(
    keys: List<String>,
    enabled: Boolean,
    onMoved: (List<String>) -> Unit,
    onOpen: (String) -> Unit,
    label: (String) -> String,
    cell: @Composable (key: String, side: androidx.compose.ui.unit.Dp) -> Unit,
) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
    val reduceMotion = app.libremusic.ui.theme.LocalReduceMotion.current
    val items = remember { androidx.compose.runtime.mutableStateListOf<String>() }
    var dragging by remember { mutableStateOf<String?>(null) }
    var drag by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    LaunchedEffect(keys) { if (dragging == null) { items.clear(); items.addAll(keys) } }
    val side = ((androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp - 16 * 2 - 16) / 2).dp
    // Alto de una celda (portada y dos líneas): se mide la primera; hasta entonces, una estimación.
    var cellH by remember { mutableStateOf(with(density) { (side + 46.dp).roundToPx() }) }
    val stepX = with(density) { (side + 16.dp).roundToPx() }
    val stepY = cellH + with(density) { 22.dp.roundToPx() }
    val rows = (items.size + 1) / 2
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(with(density) { (rows * stepY).toDp() })) {
        items.forEachIndexed { index, key -> androidx.compose.runtime.key(key) {
            val isDragging = dragging == key
            val target = androidx.compose.ui.unit.IntOffset((index % 2) * stepX, (index / 2) * stepY)
            val moved by androidx.compose.animation.core.animateIntOffsetAsState(
                target, if (reduceMotion) androidx.compose.animation.core.snap<androidx.compose.ui.unit.IntOffset>() else uiEaseOut<androidx.compose.ui.unit.IntOffset>(220), label = "cell",
            )
            Box(
                Modifier
                    .offset { if (isDragging) target else moved }
                    .width(side)
                    .onSizeChanged { if (index == 0 && it.height > 0) cellH = it.height }
                    .zIndex(if (isDragging) 1f else 0f)
                    .graphicsLayer {
                        if (isDragging) {
                            translationX = drag.x; translationY = drag.y
                            scaleX = 1.05f; scaleY = 1.05f; shadowElevation = 16.dp.toPx()
                        }
                    }
                    .tactile(label = label(key)) { onOpen(key) }
                    .then(if (!enabled) Modifier else Modifier.pointerInput(key) {
                        detectDragGesturesAfterLongPress(
                            onDragStart = {
                                dragging = key; drag = androidx.compose.ui.geometry.Offset.Zero
                                haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                            },
                            onDragEnd = {
                                dragging = null; drag = androidx.compose.ui.geometry.Offset.Zero
                                haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove)
                                onMoved(items.toList())
                            },
                            onDragCancel = { dragging = null; drag = androidx.compose.ui.geometry.Offset.Zero },
                            onDrag = { change, amount ->
                                change.consume()
                                drag += amount
                                val from = items.indexOf(key)
                                val col = (from % 2 + (drag.x / stepX).roundToInt()).coerceIn(0, 1)
                                val row = (from / 2 + (drag.y / stepY).roundToInt()).coerceAtLeast(0)
                                val to = (row * 2 + col).coerceIn(0, items.lastIndex)
                                if (to != from) {
                                    items.add(to, items.removeAt(from))
                                    // La celda cambia de sitio: el desplazamiento se cuenta desde el nuevo, y sigue al dedo.
                                    drag -= androidx.compose.ui.geometry.Offset(((to % 2) - (from % 2)) * stepX.toFloat(), ((to / 2) - (from / 2)) * stepY.toFloat())
                                }
                            },
                        )
                    }),
            ) { cell(key, side) }
        } }
    }
}

/** Sin álbumes todavía: qué es esto y cómo se llena. */
@Composable
private fun AlbumsEmpty() {
    val c = Libre.colors
    Column(Modifier.fillMaxWidth().padding(top = 56.dp, start = 40.dp, end = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Rounded.LibraryMusic, null, tint = c.secondaryLabel, modifier = Modifier.size(40.dp))
        Spacer(Modifier.height(10.dp))
        Text(L("Todavía no tienes álbumes"), style = Typo.headline, color = c.label, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text(
            L("Busca un álbum o entra en un artista y pulsa «Añadir a Tus álbumes» o «Descargar todo»."),
            style = Typo.subheadline, color = c.secondaryLabel, textAlign = TextAlign.Center,
        )
    }
}

// MARK: Editor de playlist: nombre, foto, icono y color ----------------------------------------------

@Composable
fun PlaylistEditor(id: String, onDone: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    val p = data.playlists.firstOrNull { it.id == id } ?: return
    var name by remember(id) { mutableStateOf(p.name) }
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) env.library.setCover(id, uri) }
    val hasPhoto = env.library.coverFile(id).exists()
    Column(Modifier.fillMaxSize().background(c.grouped)) {
        SheetHeader(L("Editar playlist"), trailing = L("Listo")) {
            env.library.renamePlaylist(id, name)
            onDone()
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Box(Modifier.fillMaxWidth().padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
                PlaylistCover(p, 150.dp, coverFile = env.library.coverFile(id), coverVersion = ver)
            }
            FormSection(L("Nombre")) {
                FormTextField(name, { name = it }, L("Nombre"))
            }
            FormSection(L("Foto"), footer = L("Si hay foto se muestra en lugar del icono.")) {
                FormRow(if (hasPhoto) L("Cambiar foto") else L("Elegir foto"), icon = Icons.Rounded.Image, tint = c.accent) {
                    photo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
                if (hasPhoto) FormRow(L("Quitar foto"), icon = Icons.Rounded.Delete, tint = c.destructive, last = true) { env.library.setCover(id, null) }
            }
            FormSection(L("Icono")) {
                val all = listOf<String?>(null) + SfIcons.playlistIcons
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    all.chunked(6).forEach { row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            row.forEach { icon ->
                                val on = p.icon == icon
                                Box(
                                    Modifier.size(42.dp).background(if (on) c.accent.copy(alpha = 0.25f) else Color.Transparent, CircleShape)
                                        .tactile(label = icon ?: L("Mosaico")) { env.library.setIcon(id, icon) },
                                    contentAlignment = Alignment.Center,
                                ) { Icon(SfIcons.of(icon ?: "square.grid.2x2"), null, tint = c.accent, modifier = Modifier.size(22.dp)) }
                            }
                            repeat(6 - row.size) { Spacer(Modifier.size(42.dp)) }
                        }
                    }
                }
            }
            FormSection(L("Color")) {
                Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Tokens.PlaylistPalettes.indices.forEach { i ->
                        val on = (p.tint ?: 1) == i
                        Box(
                            Modifier.size(30.dp).clip(CircleShape).background(playlistGradient(i))
                                .then(if (on) Modifier.border(2.5.dp, c.label, CircleShape) else Modifier)
                                .tactile(label = L("Color {0}", i + 1)) { env.library.setTint(id, i) },
                        )
                    }
                }
            }
            Spacer(Modifier.height(40.dp))
        }
    }
}

// MARK: Importar ---------------------------------------------------------------------------------

private sealed interface ImportStatus {
    data object Idle : ImportStatus
    data object Reading : ImportStatus
    data class Matching(val name: String, val done: Int, val total: Int) : ImportStatus
    /** Resumen de una importación con emparejado: lo bueno, lo dudoso y lo que no se encontró. */
    data class Review(val playlist: AMPlaylist, val job: ImportJob) : ImportStatus
    /** Playlists de una copia de SimpMusic para elegir cuáles traer. */
    data class SimpPick(val lists: List<SimpPlaylist>) : ImportStatus
    data class Finished(val title: String, val detail: String) : ImportStatus
}

/**
 * Importar playlists (Fase 2D): enlace de Apple Music o de Spotify, CSV de Exportify, copia de SimpMusic y
 * copia de la biblioteca. Las de fuera se emparejan con YouTube Music y lo dudoso se revisa a mano antes de
 * crear la playlist. Nunca se descarga nada al importar. Igual que `ImportView` en iOS.
 */
@Composable
fun ImportScreen(onDone: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var link by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<ImportStatus>(ImportStatus.Idle) }
    var error by remember { mutableStateOf<String?>(null) }
    var pending by remember { mutableStateOf(ImportJob.pending(context)) }
    val busy = status is ImportStatus.Reading || status is ImportStatus.Matching
    val clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
    val importFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let(env.library::importFrom) }
    val exportFile = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri -> uri?.let(env.library::exportTo) }

    fun match(job: ImportJob) {
        val pl = job.playlist
        pending = null
        scope.launch {
            val total = pl.tracks.size
            status = ImportStatus.Matching(pl.name, job.results.size, total)
            ImportMatcher.matchAll(pl.tracks, job) { d -> status = ImportStatus.Matching(pl.name, d, total) }
            status = ImportStatus.Review(pl, job)
        }
    }

    fun read(load: suspend () -> AMPlaylist) {
        error = null
        status = ImportStatus.Reading
        scope.launch {
            runCatching { load() }
                .onSuccess { match(ImportJob.start(context, it)) }
                .onFailure { status = ImportStatus.Idle; error = it.message ?: L("No se pudo leer la playlist.") }
        }
    }

    val csvFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        read {
            val name = context.contentResolver.query(uri, null, null, null, null)?.use { cur ->
                val i = cur.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (cur.moveToFirst() && i >= 0) cur.getString(i) else null
            } ?: L("Playlist de Spotify")
            val text = withContext(Dispatchers.IO) { context.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() }.orEmpty() }
            ExportifyCsv.parse(name, text)
        }
    }
    val simpFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        error = null
        status = ImportStatus.Reading
        scope.launch {
            runCatching { SimpMusicBackup.read(context, uri) }
                .onSuccess { lists -> if (lists.isEmpty()) { status = ImportStatus.Idle; error = L("La copia no tiene playlists.") } else status = ImportStatus.SimpPick(lists) }
                .onFailure { status = ImportStatus.Idle; error = it.message ?: L("No se pudo leer la copia.") }
        }
    }

    // En iOS esta hoja es un Form normal (sin las tarjetas del tema).
    CompositionLocalProvider(LocalNativeForm provides true) {
    Column(Modifier.fillMaxSize().background(c.grouped)) {
        SheetHeader(L("Importar playlist"), trailing = L("Cerrar"), trailingEnabled = !busy, onTrailing = onDone)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            when (val s = status) {
                is ImportStatus.Matching -> FormSection(null, footer = L("Puedes cerrar la app: al volver, la importación sigue donde se quedó.")) {
                    Column(Modifier.padding(16.dp, 12.dp)) {
                        Text(L("Importando «{0}»", s.name), style = Typo.headline, color = c.label)
                        Spacer(Modifier.height(8.dp))
                        LinearBar(s.done.toFloat() / maxOf(s.total, 1))
                        Spacer(Modifier.height(8.dp))
                        Text(L("Buscando en YouTube Music… {0} de {1}", s.done, s.total), style = Typo.caption, color = c.secondaryLabel)
                    }
                }
                is ImportStatus.Review -> {
                    ImportReview(s.playlist, s.job, onCancel = { s.job.discard(); status = ImportStatus.Idle }) { songs, left ->
                        // Las que no se añaden quedan en la playlist para volver a buscarlas («Sin añadir»).
                        env.library.saveCollection(s.playlist.name, songs, s.playlist.artwork) { p -> app.libremusic.data.PendingImports.set(p.id, left) }
                        s.job.discard()
                        status = ImportStatus.Finished(
                            L("«{0}» importada", s.playlist.name),
                            L("{0} de {1} canciones. Ya está en tu Biblioteca; no se ha descargado nada (usa «Descargar todo» si la quieres sin conexión).", songs.size, s.playlist.tracks.size) +
                                if (left.isEmpty()) "" else L(" Las {0} que faltan quedan en la playlist, en «Sin añadir», para buscarlas otra vez.", left.size),
                        )
                    }
                    return@Column
                }
                is ImportStatus.SimpPick -> {
                    SimpMusicPick(s.lists, onCancel = { status = ImportStatus.Idle }) { chosen ->
                        chosen.forEach { env.library.saveCollection(it.name, it.songs, it.cover) }
                        status = ImportStatus.Finished(
                            if (chosen.size == 1) L("Playlist importada") else L("{0} playlists importadas", chosen.size),
                            L("{0} canciones, iguales que en SimpMusic. No se ha descargado nada.", chosen.sumOf { it.songs.size }),
                        )
                    }
                    return@Column
                }
                is ImportStatus.Finished -> FormSection(null) {
                    Column(Modifier.padding(16.dp, 12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.CheckCircle, null, tint = c.green, modifier = Modifier.size(20.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(s.title, style = Typo.headline, color = c.green)
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(s.detail, style = Typo.subheadline, color = c.label)
                    }
                    FormRow(L("Listo"), tint = c.accent, last = true, onClick = onDone)
                }
                ImportStatus.Reading -> FormSection(null) {
                    Row(Modifier.padding(16.dp, 14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Spinner(); Spacer(Modifier.width(8.dp)); Text(L("Leyendo la playlist…"), style = Typo.body, color = c.label)
                    }
                }
                ImportStatus.Idle -> Unit
            }
            pending?.let { job ->
                if (status == ImportStatus.Idle) FormSection(L("Sin terminar"), footer = L("Se cortó a medias; sigue donde se quedó.")) {
                    FormRow("«${job.playlist.name}»", "${job.results.size} de ${job.playlist.tracks.size}", tint = c.label)
                    FormRow(L("Continuar"), tint = c.accent) { match(job) }
                    FormRow(L("Descartar"), tint = c.destructive, last = true) { job.discard(); pending = null }
                }
            }
            FormSection(
                L("Desde un enlace"),
                footer = L("Apple Music o Spotify: abre la playlist → Compartir → Copiar enlace. Tiene que ser pública. De Spotify llegan hasta unas 100 canciones; para listas más largas, usa el CSV de Exportify."),
            ) {
                FormTextField(link, { link = it }, L("Enlace de Spotify o Apple Music"))
                Box(Modifier.fillMaxWidth().padding(start = 16.dp).height(0.5.dp).background(c.separator))
                Row(Modifier.fillMaxWidth().padding(start = 7.dp, end = 16.dp, top = 13.dp, bottom = 13.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    CapsuleButton(L("Pegar"), Icons.Rounded.ContentPaste, prominent = false, enabled = !busy) { link = clipboard.getText()?.text ?: link }
                    CapsuleButton(L("Importar"), Icons.Rounded.SaveAlt, prominent = true, enabled = !busy && link.isNotEmpty()) {
                        val l = link
                        read { if (SpotifyImporter.isSpotify(l)) SpotifyImporter.fetchPublic(l) else AppleMusicImporter.fetchPublic(l) }
                    }
                }
            }
            FormSection(
                L("Desde un archivo"),
                footer = L("Spotify: exporta la playlist en exportify.app (gratis, entra con tu cuenta de Spotify) y elige el .csv; trae todas las canciones y su ISRC, que empareja mejor. SimpMusic: Ajustes › Copia de seguridad, y elige el archivo .backup; sus canciones ya son de YouTube Music, así que llegan exactas."),
            ) {
                FormRow(L("CSV de Exportify (Spotify)"), icon = Icons.Rounded.Description, tint = c.accent, enabled = !busy) {
                    csvFile.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "*/*"))
                }
                FormRow(L("Copia de SimpMusic (.backup)"), icon = Icons.Rounded.Restore, tint = c.accent, last = true, enabled = !busy) {
                    simpFile.launch(arrayOf("application/zip", "application/octet-stream", "*/*"))
                }
            }
            FormSection(
                L("Copia de la biblioteca"),
                footer = L("Archivo library.json de Pear Music (también el de iOS). Se añade lo que no tengas, sin borrar nada."),
            ) {
                FormRow(L("Importar copia"), icon = Icons.Rounded.SaveAlt, tint = c.accent, enabled = !busy) { importFile.launch(arrayOf("application/json", "*/*")) }
                FormRow(L("Exportar copia"), icon = Icons.Rounded.IosShare, tint = c.accent, last = true, enabled = !busy) { exportFile.launch("pear-music-library.json") }
            }
            error?.let { e ->
                FormSection(null) {
                    Row(Modifier.padding(16.dp, 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Warning, null, tint = c.orange, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.width(10.dp))
                        Text(e, style = Typo.body, color = c.orange)
                    }
                }
            }
            Spacer(Modifier.height(40.dp))
        }
    }
    }
}

private fun trackLine(t: AMTrack): String {
    val d = t.duration.toInt()
    return listOfNotNull(t.artist.ifEmpty { null }, if (d > 0) "%d:%02d".format(d / 60, d % 60) else null).joinToString(" · ")
}

/**
 * Resumen de una importación: cuántas encajan, cuántas hay que revisar y cuántas no se encontraron. Lo
 * dudoso no se elige solo: se toca y se escoge entre los candidatos (o «Ninguna»).
 */
@Composable
private fun ImportReview(pl: AMPlaylist, job: ImportJob, onCancel: () -> Unit, onCreate: (List<Song>, List<AMTrack>) -> Unit) {
    val c = Libre.colors
    val matches = remember(job) { pl.tracks.indices.map { job.results[it] ?: TrackMatch(pl.tracks[it], null, Matcher.Confidence.None, emptyList()) } }
    val picks = remember(job) { androidx.compose.runtime.mutableStateMapOf<Int, Song?>() }
    var open by remember { mutableStateOf<Int?>(null) }
    fun chosen(i: Int): Song? = if (picks.containsKey(i)) picks[i] else matches[i].choice
    val good = matches.count { it.confidence == Matcher.Confidence.Good }
    val review = matches.indices.filter { matches[it].confidence == Matcher.Confidence.Review }
    val none = matches.indices.filter { matches[it].confidence == Matcher.Confidence.None }
    val songs = matches.indices.mapNotNull(::chosen).distinctBy { it.id }

    FormSection("«${pl.name}»") {
        Column(Modifier.padding(16.dp, 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(L("{0} bien · {1} para revisar · {2} no encontradas", good, review.size, none.size), style = Typo.headline, color = c.label)
            Text(
                if (review.isEmpty() && none.isEmpty()) L("Todas encajan con su versión en YouTube Music.")
                else L("Toca las dudosas para elegir la versión correcta. Las que dejes sin elegir no se añaden."),
                style = Typo.subheadline, color = c.secondaryLabel,
            )
        }
    }
    @Composable
    fun rows(title: String, indices: List<Int>) {
        if (indices.isEmpty()) return
        FormSection(title) {
            indices.forEachIndexed { k, i ->
                val m = matches[i]
                val pick = chosen(i)
                FormRow(
                    m.track.title, subtitle = trackLine(m.track) + "\n" + (pick?.let { "→ ${it.title} · ${it.artist}" } ?: if (m.candidates.isEmpty()) L("Sin resultados") else L("Sin elegir")),
                    tint = c.label, chevron = m.candidates.isNotEmpty(), last = k == indices.lastIndex && open != i,
                ) { if (m.candidates.isNotEmpty()) open = if (open == i) null else i }
                if (open == i) {
                    m.candidates.forEachIndexed { j, cand ->
                        FormRow(
                            cand.song.title, subtitle = cand.song.artist + if (j == 0) L(" · más probable") else "",
                            checked = pick?.id == cand.song.id, tint = c.label,
                        ) { picks[i] = cand.song; open = null }
                    }
                    FormRow(L("Ninguna (no añadir)"), checked = pick == null, tint = c.secondaryLabel, last = k == indices.lastIndex) { picks[i] = null; open = null }
                }
            }
        }
    }
    rows(L("Para revisar"), review)
    rows(L("No encontradas"), none)
    Column(Modifier.padding(16.dp, 22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        PillButton(L("Crear playlist con {0}", songCount(songs.size)), null, prominent = true, modifier = Modifier.fillMaxWidth(), enabled = songs.isNotEmpty()) {
            onCreate(songs, matches.indices.filter { chosen(it) == null }.map { matches[it].track })
        }
        PillButton(L("Cancelar"), null, prominent = false, modifier = Modifier.fillMaxWidth(), onClick = onCancel)
    }
}

/** Elegir qué playlists de SimpMusic traer (todas marcadas al principio). */
@Composable
private fun SimpMusicPick(lists: List<SimpPlaylist>, onCancel: () -> Unit, onImport: (List<SimpPlaylist>) -> Unit) {
    val c = Libre.colors
    val selected = remember(lists) { androidx.compose.runtime.mutableStateListOf<Int>().apply { addAll(lists.indices.filter { lists[it].songs.isNotEmpty() }) } }
    FormSection(L("Copia de SimpMusic"), footer = L("Las canciones ya son de YouTube Music: llegan exactas, sin buscar. No se descarga nada.")) {
        lists.forEachIndexed { i, l ->
            FormRow(l.name, subtitle = songCount(l.songs.size), checked = i in selected, tint = c.label, enabled = l.songs.isNotEmpty(), last = i == lists.lastIndex) {
                if (i in selected) selected.remove(i) else selected.add(i)
            }
        }
    }
    Column(Modifier.padding(16.dp, 22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        PillButton(
            if (selected.size == 1) L("Importar 1 playlist") else L("Importar {0} playlists", selected.size), null, prominent = true,
            modifier = Modifier.fillMaxWidth(), enabled = selected.isNotEmpty(),
        ) { onImport(selected.sorted().map { lists[it] }) }
        PillButton(L("Cancelar"), null, prominent = false, modifier = Modifier.fillMaxWidth(), onClick = onCancel)
    }
}

@Composable
fun LinearBar(progress: Float, modifier: Modifier = Modifier, tint: Color = Libre.colors.accent) {
    val c = Libre.colors
    Box(modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(c.fill)) {
        Box(Modifier.fillMaxWidth(progress.coerceIn(0f, 1f)).height(4.dp).background(tint, CircleShape))
    }
}

// MARK: Ordenar playlists a mano ------------------------------------------------------------------

/**
 * Orden propio del carrusel de Playlists: se arrastra cada fila por su asa (≡). Incluye
 * Descargadas y Favoritos si están en Playlists. Al mover algo, el orden pasa a ser «A mano».
 */
@Composable
fun ReorderPlaylistsScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    val downloaded by env.library.downloadedSongs.collectAsState()
    val sort by Prefs.playlistSort.collectAsState()
    val order by Prefs.playlistOrder.collectAsState()
    val placement by Prefs.smartPlacement.collectAsState()
    val byId = data.playlists.associateBy { it.id }
    val items = remember { androidx.compose.runtime.mutableStateListOf<String>() }
    LaunchedEffect(data.userPlaylists.size, placement) {
        items.clear()
        items.addAll(LibraryOrder.keys(data.userPlaylists, sort, order, placement != "music"))
    }
    val density = androidx.compose.ui.platform.LocalDensity.current
    val rowPx = with(density) { 68.dp.toPx() }
    var dragging by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableStateOf(0f) }

    fun save() {
        Prefs.setPlaylistOrder(items.toList())
        Prefs.setPlaylistSort("custom")
    }

    PlainListScreen(L("Editar playlists"), if (items.isEmpty()) L("Todavía no hay playlists") else null) {
        item {
            FormSection(L("Ordenar por")) {
                listOf("recent" to L("Añadidas recientemente"), "name" to L("Nombre (A-Z)"), "nameDesc" to L("Nombre (Z-A)"), "count" to L("Nº de canciones"), "custom" to L("A mano"))
                    .forEachIndexed { i, (key, label) ->
                        FormRow(label, checked = sort == key, last = i == 4) {
                            Prefs.setPlaylistSort(key)
                            items.clear(); items.addAll(LibraryOrder.keys(data.userPlaylists, key, order, placement != "music"))
                        }
                    }
            }
        }
        item {
            Text(
                L("Arrastra ≡ para cambiar el orden del carrusel. Al mover algo, Playlists se ordena «A mano»."),
                style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp),
            )
        }
        item {
            Column(Modifier.fillMaxWidth()) {
                items.forEach { key -> androidx.compose.runtime.key(key) {
                    // Cada fila sigue a su playlist al reordenar (si no, el gesto del asa se cortaba).
                    val isDragging = dragging == key
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .height(68.dp)
                            .zIndex(if (isDragging) 1f else 0f)
                            .graphicsLayer {
                                translationY = if (isDragging) dragOffset else 0f
                                if (isDragging) { scaleX = 1.02f; scaleY = 1.02f; shadowElevation = 12.dp.toPx() }
                            }
                            .padding(horizontal = 10.dp, vertical = 3.dp)
                            .then(if (c.theme.styled) Modifier.themeSurface(Tokens.Radius.Row.dp, c) else Modifier.background(c.secondaryGrouped, RoundedCornerShape(10.dp)))
                            .padding(start = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        val title: String
                        val subtitle: String
                        when (key) {
                            LibraryOrder.DOWNLOADS -> { SmartCover(SmartList.Downloads, 48.dp, 10.dp); title = SmartList.Downloads.title; subtitle = songCount(downloaded.size) }
                            LibraryOrder.FAVORITES -> { SmartCover(SmartList.Favorites, 48.dp, 10.dp); title = SmartList.Favorites.title; subtitle = songCount(data.favorites.size) }
                            else -> {
                                val p = byId[key]
                                if (p != null) PlaylistCover(p, 48.dp, 10.dp, env.library.coverFile(p.id), ver)
                                title = p?.name.orEmpty(); subtitle = songCount(p?.songs?.size ?: 0)
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(title, style = Typo.body.copy(fontWeight = FontWeight.Medium), color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(subtitle, style = Typo.caption, color = c.secondaryLabel)
                        }
                        // Asa: se arrastra en vertical; al pasar media fila, intercambia con la vecina.
                        Box(
                            Modifier
                                .size(52.dp)
                                .semanticsButton("Mover $title") {}
                                .pointerInput(key) {
                                    detectDragGestures(
                                        onDragStart = { dragging = key; dragOffset = 0f },
                                        onDragEnd = { dragging = null; dragOffset = 0f; save() },
                                        onDragCancel = { dragging = null; dragOffset = 0f },
                                        onDrag = { change, amount ->
                                            change.consume()
                                            dragOffset += amount.y
                                            val from = items.indexOf(key)
                                            val to = (from + (dragOffset / rowPx).roundToInt()).coerceIn(0, items.lastIndex)
                                            if (to != from) {
                                                items.add(to, items.removeAt(from))
                                                dragOffset -= (to - from) * rowPx
                                            }
                                        },
                                    )
                                },
                            contentAlignment = Alignment.Center,
                        ) { Icon(Icons.Rounded.DragHandle, null, tint = c.tertiaryLabel, modifier = Modifier.size(24.dp)) }
                    }
                } }
            }
        }
    }
}


/** «Sin añadir»: canciones de una importación que no se añadieron. Se vuelven a buscar y se elige la versión. */
@Composable
fun PendingImportScreen(playlistId: String) {
    val c = Libre.colors
    val env = LocalEnv.current
    val all by app.libremusic.data.PendingImports.all.collectAsState()
    val tracks = all[playlistId].orEmpty()
    var results by remember(playlistId) { mutableStateOf<Map<AMTrack, TrackMatch>>(emptyMap()) }
    var searching by remember { mutableStateOf(false) }
    var done by remember { mutableIntStateOf(0) }
    var open by remember { mutableStateOf<AMTrack?>(null) }
    val scope = rememberCoroutineScope()
    SettingsPage(L("Sin añadir")) {
        if (tracks.isEmpty()) {
            CenterNote(L("No queda ninguna canción por añadir"), 60.dp)
            return@SettingsPage
        }
        FormSection(null, footer = if (searching) L("Buscando en YouTube Music… {0} de {1}", done, tracks.size) else L("Se buscan otra vez en YouTube Music (a veces aparecen versiones nuevas). Elige la buena y se añade a la playlist.")) {
            FormCustomRow {
                Box(Modifier.padding(16.dp, 10.dp)) {
                    PillButton(if (searching) "Buscando…" else L("Buscar otra vez"), Icons.Rounded.Refresh, prominent = true, modifier = Modifier.fillMaxWidth(), enabled = !searching) {
                        searching = true; done = 0
                        scope.launch {
                            val r = app.libremusic.data.ImportMatcher.matchAll(tracks, null) { done = it }
                            results = tracks.zip(r).toMap()
                            searching = false
                        }
                    }
                }
            }
        }
        FormSection(songCount(tracks.size)) {
            tracks.forEachIndexed { k, t ->
                val m = results[t]
                FormRow(
                    t.title, subtitle = trackLine(t) + (m?.let { "\n" + if (it.candidates.isEmpty()) L("Sin resultados") else "${it.candidates.size} posibles" } ?: ""),
                    tint = c.label, chevron = m?.candidates?.isNotEmpty() == true, last = k == tracks.lastIndex && open != t,
                    trailing = { IconTap(Icons.Rounded.Close, L("Descartar {0}", t.title), tint = c.secondaryLabel) { app.libremusic.data.PendingImports.remove(playlistId, t) } },
                ) { if (m?.candidates?.isNotEmpty() == true) open = if (open == t) null else t }
                if (open == t && m != null) {
                    m.candidates.forEachIndexed { j, cand ->
                        FormRow(cand.song.title, subtitle = cand.song.artist + if (j == 0) L(" · más probable") else "", tint = c.label, last = k == tracks.lastIndex && j == m.candidates.lastIndex) {
                            env.library.addToPlaylist(playlistId, cand.song)
                            app.libremusic.data.PendingImports.remove(playlistId, t)
                            open = null
                            env.app.toast = L("Añadida a la playlist")
                        }
                    }
                }
            }
        }
    }
}

/**
 * Abre el perfil (YouTube Music) del artista con ese nombre; si no se encuentra o no hay red, la lista de sus
 * canciones guardadas. Desde «Tu música › Artistas» y desde la cabecera de un álbum (Fase 3.1).
 */
fun openArtistProfile(env: ScreenEnv, scope: kotlinx.coroutines.CoroutineScope, name: String) {
    scope.launch {
        val found = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { runCatching { app.libremusic.data.YTClient.findArtist(name) }.getOrNull() }
        env.app.push(if (found != null) Route.RemoteArtistR(found) else Route.Artist(name))
    }
}

/**
 * «Fijados» (Fase 3.3) en Inicio: los álbumes y playlists con la chincheta, en el orden de Biblioteca. Mantener pulsado
 * suelta. Igual que `PinnedRow` en iOS.
 */
@Composable
fun PinnedRow(modifier: Modifier = Modifier) {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    val order by Prefs.pinnedOrder.collectAsState()
    val pinned = LibraryOrder.pinned(data.playlists.filter { it.pinned }, order)
    if (pinned.isEmpty()) return
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(L("Fijados"), style = Typo.display(Tokens.TypeSize.DisplaySection, c.theme), color = c.label, modifier = Modifier.padding(horizontal = 16.dp))
        androidx.compose.foundation.lazy.LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(pinned, key = { it.id }) { p ->
                var menu by remember { mutableStateOf(false) }
                Box {
                    Column(
                        Modifier.width(132.dp).tactile(label = p.name, onLongClick = { menu = true }) { env.app.push(Route.PlaylistR(p.id)) },
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        PlaylistCover(p, 132.dp, radius = 14.dp, coverFile = env.library.coverFile(p.id), coverVersion = ver)
                        Text(p.name, style = Typo.subheadline.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(p.album?.line?.ifEmpty { null } ?: songCount(p.songs.size), style = Typo.caption, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    ContextMenu(menu, { menu = false }, listOf(
                        MenuEntry.Action(L("Reproducir"), Icons.Rounded.PlayArrow) { if (p.songs.isNotEmpty()) env.player.play(p.songs, 0) },
                        MenuEntry.Action(L("Soltar de arriba"), Icons.Outlined.PushPin) { env.library.setPinned(p.id, false) },
                    ))
                }
            }
        }
    }
}
