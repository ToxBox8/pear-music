package app.libremusic.ui

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
import androidx.compose.ui.zIndex
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
    s.replace(Regex("\\s*(,| y | & | x | feat\\.? | ft\\.? | · ).*$", RegexOption.IGNORE_CASE), "").ifEmpty { "Desconocido" }

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
        "Nueva playlist", field = "Nombre",
        buttons = listOf(AlertButton("Cancelar", AlertButton.Role.Cancel), AlertButton("Crear") { onCreate(it) }),
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
    val player by env.player.state.collectAsState()
    val sort by Prefs.playlistSort.collectAsState()
    val jam by JamService.state.collectAsState()
    var addMenu by remember { mutableStateOf(false) }
    var sortMenu by remember { mutableStateOf(false) }
    val songs = remember(data, downloaded) { allSongs(data.favorites, data.playlists, downloaded) }
    val stats by app.libremusic.data.PlayStats.data.collectAsState()
    val monthPlays = remember(stats) { stats.plays.count { it.at >= app.libremusic.data.PlayStats.since(app.libremusic.data.PlayStats.Period.Month) } }
    val order by Prefs.playlistOrder.collectAsState()
    val placement by Prefs.smartPlacement.collectAsState()
    val smartInPlaylists = placement != "music"
    val byId = data.playlists.associateBy { it.id }
    val keys = LibraryOrder.keys(data.userPlaylists, sort, order, smartInPlaylists)
    val newPlaylist = { env.app.askNewPlaylist { env.library.createPlaylist(it) } }

    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(top = 6.dp)) {
            // Cabecera
            Row(Modifier.fillMaxWidth().padding(horizontal = INSET), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text("Biblioteca", style = Typo.display(Tokens.TypeSize.DisplayLibrary, c.theme), color = c.label)
                    Spacer(Modifier.height(4.dp))
                    val off = downloaded.size
                    val summary = if (songs.isEmpty()) "Aún no has guardado nada" else songCount(songs.size) + if (off > 0) " · $off sin conexión" else ""
                    Text(summary, style = Typo.subheadline, color = c.secondaryLabel)
                }
                Spacer(Modifier.width(12.dp))
                Box {
                    Box(
                        Modifier.size(44.dp).themeSurface(22.dp, c).clip(CircleShape).tactile(label = "Añadir playlist") { addMenu = true },
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Rounded.Add, null, tint = c.accent, modifier = Modifier.size(24.dp)) }
                    ContextMenu(addMenu, { addMenu = false }, listOf(
                        MenuEntry.Action("Nueva playlist", Icons.AutoMirrored.Rounded.PlaylistAdd) { newPlaylist() },
                        MenuEntry.Action("Importar de Apple Music", Icons.Rounded.Download) { env.app.showImport = true },
                        MenuEntry.Divider,
                        MenuEntry.Action("Jam con amigos", app.libremusic.ui.theme.JamIcon()) { env.app.showJam = true },
                    ))
                }
            }
            Spacer(Modifier.height(34.dp))

            // Playlists
            Row(Modifier.fillMaxWidth().padding(horizontal = INSET), verticalAlignment = Alignment.CenterVertically) {
                Text("Playlists", style = Typo.display(Tokens.TypeSize.DisplaySection, c.theme), color = c.label, modifier = Modifier.weight(1f).alignByBaseline())
                if (data.userPlaylists.size > 1) {
                    Box {
                        Box(Modifier.size(36.dp).tactile(label = "Ordenar playlists") { sortMenu = true }, contentAlignment = Alignment.Center) {
                            Icon(Icons.Rounded.SwapVert, null, tint = c.accent, modifier = Modifier.size(24.dp))
                        }
                        ContextMenu(sortMenu, { sortMenu = false }, listOf(
                            MenuEntry.Action("Añadidas recientemente", Icons.Rounded.Schedule, checked = sort == "recent") { Prefs.setPlaylistSort("recent") },
                            MenuEntry.Action("Nombre (A-Z)", null, checked = sort == "name") { Prefs.setPlaylistSort("name") },
                            MenuEntry.Action("Nombre (Z-A)", null, checked = sort == "nameDesc") { Prefs.setPlaylistSort("nameDesc") },
                            MenuEntry.Action("Nº de canciones", null, checked = sort == "count") { Prefs.setPlaylistSort("count") },
                            MenuEntry.Divider,
                            MenuEntry.Action("A mano…", Icons.Rounded.DragHandle, checked = sort == "custom") { env.app.push(Route.ReorderPlaylists) },
                        ))
                    }
                }
                Text("Ver todas", style = Typo.subheadline.semibold, color = c.accent, modifier = Modifier.alignByBaseline().tactile(label = "Ver todas") { env.app.push(Route.Playlists) }.padding(start = 8.dp))
            }
            Spacer(Modifier.height(14.dp))
            val listState = rememberLazyListState()
            LazyRow(
                state = listState,
                flingBehavior = rememberSnapFlingBehavior(listState),
                contentPadding = PaddingValues(horizontal = INSET),
                horizontalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                jam.jam?.let { state ->
                    item("jam") {
                        val active = jam.phase == JamPhase.Hosting || jam.phase == JamPhase.Joined
                        CarouselTile(
                            title = state.name,
                            subtitle = if (active) "Jam en directo · ${state.members.size}" else "Jam sin conexión",
                            onClick = { env.app.showJam = true },
                        ) {
                            Box(Modifier.size(CARD.dp).clip(RoundedCornerShape(Tokens.Radius.PlaylistCard.dp)).background(playlistGradient(1)), contentAlignment = Alignment.Center) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Icon(app.libremusic.ui.theme.JamIcon(filled = true), null, tint = Color.White, modifier = Modifier.size(48.dp))
                                    Spacer(Modifier.height(12.dp))
                                    Text(state.code, style = Typo.mono(20f).copy(letterSpacing = androidx.compose.ui.unit.TextUnit(0.15f, androidx.compose.ui.unit.TextUnitType.Em)), color = Color.White)
                                }
                            }
                        }
                    }
                }
                items(keys, key = { it }) { key ->
                    when (key) {
                        LibraryOrder.DOWNLOADS -> CarouselTile(SmartList.Downloads.title, songCount(downloaded.size), onClick = { env.app.push(Route.Smart(SmartList.Downloads)) }) {
                            SmartCover(SmartList.Downloads, CARD.dp, Tokens.Radius.PlaylistCard.dp)
                        }
                        LibraryOrder.FAVORITES -> CarouselTile(SmartList.Favorites.title, songCount(data.favorites.size), onClick = { env.app.push(Route.Smart(SmartList.Favorites)) }) {
                            SmartCover(SmartList.Favorites, CARD.dp, Tokens.Radius.PlaylistCard.dp)
                        }
                        else -> byId[key]?.let { p -> PlaylistTile(p, ver) }
                    }
                }
                item("new") {
                    var menu by remember { mutableStateOf(false) }
                    Box {
                        CarouselTile("Nueva playlist", "Vacía o importada", onLongClick = { menu = true }, onClick = newPlaylist) {
                            val stroke = c.label.copy(alpha = 0.22f)
                            Box(
                                Modifier.size(CARD.dp).drawDashedBorder(stroke, Tokens.Radius.PlaylistCard.dp),
                                contentAlignment = Alignment.Center,
                            ) { Icon(Icons.Rounded.Add, null, tint = c.secondaryLabel, modifier = Modifier.size(32.dp)) }
                        }
                        ContextMenu(menu, { menu = false }, listOf(
                            MenuEntry.Action("Nueva playlist", Icons.AutoMirrored.Rounded.PlaylistAdd) { newPlaylist() },
                            MenuEntry.Action("Importar de Apple Music", Icons.Rounded.Download) { env.app.showImport = true },
                            MenuEntry.Action("Jam con amigos", app.libremusic.ui.theme.JamIcon()) { env.app.showJam = true },
                        ))
                    }
                }
            }
            if (data.userPlaylists.isEmpty()) {
                Text(
                    "Crea una playlist con + o tráete las tuyas desde Apple Music.",
                    style = Typo.subheadline, color = c.secondaryLabel, modifier = Modifier.padding(horizontal = INSET, vertical = 14.dp),
                )
            }
            Spacer(Modifier.height(34.dp))

            // El resto de la música
            Text("Tu música", style = Typo.display(Tokens.TypeSize.DisplaySection, c.theme), color = c.label, modifier = Modifier.padding(horizontal = INSET))
            Spacer(Modifier.height(12.dp))
            Column(Modifier.padding(horizontal = INSET)) {
                if (!smartInPlaylists) {
                    // Descargadas y Favoritos como filas (Ajustes › Apariencia › Biblioteca).
                    LibraryLinkRow(SmartList.Downloads.title, downloaded.size, Icons.Rounded.DownloadForOffline) { env.app.push(Route.Smart(SmartList.Downloads)) }
                    LibraryLinkRow(SmartList.Favorites.title, data.favorites.size, Icons.Rounded.Favorite) { env.app.push(Route.Smart(SmartList.Favorites)) }
                }
                LibraryLinkRow("Tus álbumes", data.albums.size, Icons.Rounded.LibraryMusic) { env.app.push(Route.Albums) }
                LibraryLinkRow("Canciones", songs.size, Icons.Rounded.MusicNote) { env.app.push(Route.AllSongs) }
                LibraryLinkRow("Artistas", songs.map { primaryArtist(it.artist) }.toSet().size, Icons.Rounded.Mic) { env.app.push(Route.Artists) }
                LibraryLinkRow("Recientes", data.recents.size, Icons.Rounded.Schedule) { env.app.push(Route.Recents) }
                LibraryLinkRow("Estadísticas", monthPlays, Icons.Rounded.BarChart, last = true) { env.app.push(Route.Stats) }
            }
            BottomSpacer(28.dp)
        }
    }
}

/** Tarjeta de una playlist en el carrusel, con su menú (Reproducir, Aleatorio, Editar). */
@Composable
private fun PlaylistTile(p: app.libremusic.data.Playlist, ver: Int) {
    val env = LocalEnv.current
    var menu by remember { mutableStateOf(false) }
    val dl by env.library.downloads.collectAsState()
    val offline = p.songs.count { dl[it.id]?.isDone == true }
    Box {
        CarouselTile(
            p.name, songCount(p.songs.size), offlineAll = offline > 0 && offline == p.songs.size,
            onLongClick = { menu = true }, onClick = { env.app.push(Route.PlaylistR(p.id)) },
        ) {
            PlaylistCover(p, CARD.dp, Tokens.Radius.PlaylistCard.dp, env.library.coverFile(p.id), ver)
        }
        ContextMenu(menu, { menu = false }, listOf(
            MenuEntry.Action("Reproducir", Icons.Rounded.PlayArrow) { if (p.songs.isNotEmpty()) env.player.play(p.songs, 0) },
            MenuEntry.Action("Aleatorio", Icons.Rounded.Shuffle) { if (p.songs.isNotEmpty()) env.player.play(p.songs.shuffled(), 0) },
            MenuEntry.Action("Editar", Icons.Rounded.Edit) { env.app.editing = p.id },
        ))
    }
}

/** Borde discontinuo de la tarjeta «Nueva playlist». */
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

@Composable
private fun CarouselTile(
    title: String,
    subtitle: String,
    offlineAll: Boolean = false,
    onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit,
    cover: @Composable () -> Unit,
) {
    val c = Libre.colors
    Column(Modifier.width(CARD.dp).tactile(label = title, onLongClick = onLongClick, onClick = onClick)) {
        Box(Modifier.shadowSoft(16.dp, RoundedCornerShape(Tokens.Radius.PlaylistCard.dp), 0.14f)) { cover() }
        Spacer(Modifier.height(10.dp))
        Text(title, style = Typo.callout.bold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(2.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(subtitle, style = Typo.caption, color = c.secondaryLabel, maxLines = 1)
            if (offlineAll) {
                Spacer(Modifier.width(4.dp))
                Icon(Icons.Rounded.DownloadForOffline, "Descargada", tint = c.secondaryLabel, modifier = Modifier.size(13.dp))
            }
        }
    }
}

/** Fila grande de navegación: icono en círculo, título, recuento y chevron, con líneas finas. */
@Composable
private fun LibraryLinkRow(title: String, count: Int, icon: androidx.compose.ui.graphics.vector.ImageVector, last: Boolean = false, onClick: () -> Unit) {
    val c = Libre.colors
    Column(Modifier.fillMaxWidth().rowHighlight(onClick = onClick)) {
        Row(Modifier.fillMaxWidth().padding(vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(36.dp).themeSurface(18.dp, c).clip(CircleShape), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = c.label, modifier = Modifier.size(18.dp))
            }
            Spacer(Modifier.width(14.dp))
            Text(title, style = Typo.title3.semibold, color = c.label, modifier = Modifier.weight(1f))
            Text("$count", style = Typo.subheadline, color = c.secondaryLabel)
            Spacer(Modifier.width(6.dp))
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = c.tertiaryLabel, modifier = Modifier.size(20.dp))
        }
        if (!last) Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.separator))
    }
}

// MARK: Detalle común (playlists, listas inteligentes, canciones) --------------------------------------

private enum class SongFilter(val title: String) { All("Todas"), Downloaded("Descargadas"), Favorites("Favoritas") }

@Composable
private fun CollectionDetail(
    title: String,
    songs: List<Song>,
    filters: Boolean = true,
    /** Lista dueña de «Descargar todo» (id de la playlist o «favorites»); null = sin el botón. */
    bulkOwner: String? = null,
    emptyText: String = "Todavía no hay nada aquí",
    onRemove: ((Song) -> Unit)? = null,
    onEdit: (() -> Unit)? = null,
    /** Fila extra encima de las canciones (p. ej. «Sin añadir» de una importación). */
    above: (@Composable () -> Unit)? = null,
    cover: @Composable (Dp) -> Unit,
) {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val dl by env.library.downloads.collectAsState()
    val player by env.player.state.collectAsState()
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
                    if (onEdit != null) ToolbarButton(Icons.Rounded.Edit, "Editar playlist", onClick = onEdit)
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
                    Text(songCount(songs.size) + if (offline > 0) " · $offline sin conexión" else "", style = Typo.subheadline, color = c.secondaryLabel)
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
                    filter == SongFilter.Downloaded -> "Ninguna canción de esta lista está descargada."
                    filter == SongFilter.Favorites -> "Aún no has marcado favoritas aquí."
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
                PillButton("$done de $total · Pausar", null, prominent = false, modifier = Modifier.weight(1f), leading = { Spinner(16.dp, c.accent) }) { env.library.pauseBulk(owner) }
            } else {
                PillButton("Reanudar · $done de $total", Icons.Rounded.PlayCircleOutline, prominent = false, modifier = Modifier.weight(1f)) {
                    env.library.downloadAll(owner, songs)
                }
            }
            Text(
                "Cancelar", style = Typo.subheadline.semibold, color = c.accent,
                modifier = Modifier.heightIn(min = 44.dp).tactile(label = "Cancelar la descarga; lo ya descargado se queda") { env.library.cancelBulk(owner) }
                    .padding(horizontal = 8.dp, vertical = 12.dp),
            )
        }
        return
    }
    when {
        complete -> PillButton("Disponible sin conexión", Icons.Rounded.CheckCircle, prominent = false, modifier = Modifier.fillMaxWidth()) {
            env.app.alert = AlertSpec(
                title = "¿Quitar las descargas${title?.let { " de «$it»" } ?: ""}?",
                message = "Dejarán de estar disponibles sin conexión, también en otras listas que las tengan.",
                buttons = listOf(
                    AlertButton("Cancelar", AlertButton.Role.Cancel),
                    AlertButton("Quitar ${songCount(done)}", AlertButton.Role.Destructive) { songs.forEach(env.library::removeDownload) },
                ),
            )
        }
        else -> PillButton(
            if (done > 0) "Descargar las ${total - done} que faltan" else "Descargar todo",
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
        emptyText = "Mantén pulsada una canción en Buscar o Inicio para añadirla.",
        onRemove = { env.library.removeFromPlaylist(p.id, it.id) },
        onEdit = { env.app.editing = p.id },
        above = pending.takeIf { it.isNotEmpty() }?.let { l ->
            {
                GlassRowItem({ env.app.push(Route.PendingImport(p.id)) }) {
                    Icon(Icons.Rounded.ManageSearch, null, tint = Libre.colors.accent, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Sin añadir: ${songCount(l.size)}", style = Typo.body.copy(fontWeight = FontWeight.Medium), color = Libre.colors.label)
                        Text("De la importación. Toca para buscarlas otra vez.", style = Typo.caption, color = Libre.colors.secondaryLabel)
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
            emptyText = "Descarga canciones con la flecha de cada fila o con «Descargar todo» en una playlist.",
            onRemove = { env.library.removeDownload(it) },
        ) { side -> SmartCover(kind, side, 0.dp) }
        SmartList.Favorites -> CollectionDetail(
            kind.title, data.favorites, filters = false, bulkOwner = "favorites",
            emptyText = "Toca el corazón de una canción para guardarla aquí.",
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
    SongListScreen("Canciones", allSongs(data.favorites, data.playlists, downloaded).sortedBy { it.title.lowercase() })
}

@Composable
fun RecentsScreen() {
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    SongListScreen("Recientes", data.recents)
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
    content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit,
) {
    val env = LocalEnv.current
    val player by env.player.state.collectAsState()
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        // imePadding: el teclado no tapa el final de la lista.
        LazyColumn(Modifier.fillMaxSize().imePadding()) {
            item { NavBar(null, onBack = { env.app.pop() }) }
            item { LargeTitle(title, Modifier.padding(bottom = 8.dp)) }
            if (search != null && empty == null) item(key = "search") {
                SearchField(search.first, search.second, { keyboard?.hide() }, Modifier.padding(start = 16.dp, end = 16.dp, bottom = 10.dp), placeholder = "Buscar en ${title.lowercase()}")
            }
            content()
            if (empty != null) item { CenterNote(empty, 60.dp) }
            else if (noMatches && search != null) item { CenterNote("Nada coincide con «${search.first.trim()}»", 40.dp) }
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
    val groups = remember(data, downloaded) {
        allSongs(data.favorites, data.playlists, downloaded).groupBy { primaryArtist(it.artist) }.toList().sortedBy { it.first.lowercase() }
    }
    var query by rememberSaveable { mutableStateOf("") }
    // Los nombres se normalizan una vez por lista; al escribir sólo se compara (rápido con miles).
    val folded = remember(groups) { groups.map { app.libremusic.data.LocalSearch.fold(it.first) } }
    val shown = remember(groups, query) { app.libremusic.data.LocalSearch.filter(groups, folded, query) }
    PlainListScreen("Artistas", if (groups.isEmpty()) "Guarda canciones para ver sus artistas" else null, query to { q: String -> query = q }, noMatches = shown.isEmpty()) {
        items(shown, key = { it.first }) { (name, songs) ->
            GlassRowItem({ env.app.push(Route.Artist(name)) }) {
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

@Composable
fun PlaylistsListScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    val sort by Prefs.playlistSort.collectAsState()
    val order by Prefs.playlistOrder.collectAsState()
    val byId = data.playlists.associateBy { it.id }
    val ordered = LibraryOrder.keys(data.userPlaylists, sort, order, smartInPlaylists = false).mapNotNull { byId[it] }
    var query by rememberSaveable { mutableStateOf("") }
    val shown = remember(ordered, query) { app.libremusic.data.LocalSearch.filter(ordered, query) { it.name } }
    PlainListScreen("Playlists", if (data.userPlaylists.isEmpty()) "Todavía no hay playlists" else null, query to { q: String -> query = q }, noMatches = shown.isEmpty()) {
        items(shown, key = { it.id }) { p ->
            GlassRowItem({ env.app.push(Route.PlaylistR(p.id)) }) {
                PlaylistCover(p, 56.dp, coverFile = env.library.coverFile(p.id), coverVersion = ver)
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(p.name, style = Typo.body.copy(fontWeight = FontWeight.Medium), color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(songCount(p.songs.size), style = Typo.caption, color = c.secondaryLabel)
                }
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = c.tertiaryLabel, modifier = Modifier.size(20.dp))
            }
        }
    }
}

/** «Tus álbumes»: los álbumes guardados o descargados desde su página, en cuadrícula y con buscador. */
@Composable
fun AlbumsScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    val albums = data.albums
    var query by rememberSaveable { mutableStateOf("") }
    val shown = remember(albums, query) { app.libremusic.data.LocalSearch.filter(albums, query) { "${it.name} ${it.album?.artist.orEmpty()}" } }
    val side = ((androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp - 16 * 2 - 16) / 2).dp
    PlainListScreen("Tus álbumes", null, if (albums.isEmpty()) null else query to { q: String -> query = q }, noMatches = albums.isNotEmpty() && shown.isEmpty()) {
        if (albums.isEmpty()) item { AlbumsEmpty() } else item { Spacer(Modifier.height(8.dp)) }
        items(shown.chunked(2), key = { row -> row.first().id }) { row ->
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 22.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                row.forEach { p ->
                    Column(Modifier.width(side).tactile(label = "${p.name}, ${p.album?.line.orEmpty()}") { env.app.push(Route.PlaylistR(p.id)) }) {
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

/** Sin álbumes todavía: qué es esto y cómo se llena. */
@Composable
private fun AlbumsEmpty() {
    val c = Libre.colors
    Column(Modifier.fillMaxWidth().padding(top = 56.dp, start = 40.dp, end = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Rounded.LibraryMusic, null, tint = c.secondaryLabel, modifier = Modifier.size(40.dp))
        Spacer(Modifier.height(10.dp))
        Text("Todavía no tienes álbumes", style = Typo.headline, color = c.label, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text(
            "Busca un álbum o entra en un artista y pulsa «Añadir a Tus álbumes» o «Descargar todo».",
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
        SheetHeader("Editar playlist", trailing = "Listo") {
            env.library.renamePlaylist(id, name)
            onDone()
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Box(Modifier.fillMaxWidth().padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
                PlaylistCover(p, 150.dp, coverFile = env.library.coverFile(id), coverVersion = ver)
            }
            FormSection("Nombre") {
                FormTextField(name, { name = it }, "Nombre")
            }
            FormSection("Foto", footer = "Si hay foto se muestra en lugar del icono.") {
                FormRow(if (hasPhoto) "Cambiar foto" else "Elegir foto", icon = Icons.Rounded.Image, tint = c.accent) {
                    photo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
                if (hasPhoto) FormRow("Quitar foto", icon = Icons.Rounded.Delete, tint = c.destructive, last = true) { env.library.setCover(id, null) }
            }
            FormSection("Icono") {
                val all = listOf<String?>(null) + SfIcons.playlistIcons
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    all.chunked(6).forEach { row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            row.forEach { icon ->
                                val on = p.icon == icon
                                Box(
                                    Modifier.size(42.dp).background(if (on) c.accent.copy(alpha = 0.25f) else Color.Transparent, CircleShape)
                                        .tactile(label = icon ?: "Mosaico") { env.library.setIcon(id, icon) },
                                    contentAlignment = Alignment.Center,
                                ) { Icon(SfIcons.of(icon ?: "square.grid.2x2"), null, tint = c.accent, modifier = Modifier.size(22.dp)) }
                            }
                            repeat(6 - row.size) { Spacer(Modifier.size(42.dp)) }
                        }
                    }
                }
            }
            FormSection("Color") {
                Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Tokens.PlaylistPalettes.indices.forEach { i ->
                        val on = (p.tint ?: 1) == i
                        Box(
                            Modifier.size(30.dp).clip(CircleShape).background(playlistGradient(i))
                                .then(if (on) Modifier.border(2.5.dp, c.label, CircleShape) else Modifier)
                                .tactile(label = "Color ${i + 1}") { env.library.setTint(id, i) },
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
                .onFailure { status = ImportStatus.Idle; error = it.message ?: "No se pudo leer la playlist." }
        }
    }

    val csvFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        read {
            val name = context.contentResolver.query(uri, null, null, null, null)?.use { cur ->
                val i = cur.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (cur.moveToFirst() && i >= 0) cur.getString(i) else null
            } ?: "Playlist de Spotify"
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
                .onSuccess { lists -> if (lists.isEmpty()) { status = ImportStatus.Idle; error = "La copia no tiene playlists." } else status = ImportStatus.SimpPick(lists) }
                .onFailure { status = ImportStatus.Idle; error = it.message ?: "No se pudo leer la copia." }
        }
    }

    // En iOS esta hoja es un Form normal (sin las tarjetas del tema).
    CompositionLocalProvider(LocalNativeForm provides true) {
    Column(Modifier.fillMaxSize().background(c.grouped)) {
        SheetHeader("Importar playlist", trailing = "Cerrar", trailingEnabled = !busy, onTrailing = onDone)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            when (val s = status) {
                is ImportStatus.Matching -> FormSection(null, footer = "Puedes cerrar la app: al volver, la importación sigue donde se quedó.") {
                    Column(Modifier.padding(16.dp, 12.dp)) {
                        Text("Importando «${s.name}»", style = Typo.headline, color = c.label)
                        Spacer(Modifier.height(8.dp))
                        LinearBar(s.done.toFloat() / maxOf(s.total, 1))
                        Spacer(Modifier.height(8.dp))
                        Text("Buscando en YouTube Music… ${s.done} de ${s.total}", style = Typo.caption, color = c.secondaryLabel)
                    }
                }
                is ImportStatus.Review -> {
                    ImportReview(s.playlist, s.job, onCancel = { s.job.discard(); status = ImportStatus.Idle }) { songs, left ->
                        // Las que no se añaden quedan en la playlist para volver a buscarlas («Sin añadir»).
                        env.library.saveCollection(s.playlist.name, songs, s.playlist.artwork) { p -> app.libremusic.data.PendingImports.set(p.id, left) }
                        s.job.discard()
                        status = ImportStatus.Finished(
                            "«${s.playlist.name}» importada",
                            "${songs.size} de ${s.playlist.tracks.size} canciones. Ya está en tu Biblioteca; no se ha descargado nada (usa «Descargar todo» si la quieres sin conexión)." +
                                if (left.isEmpty()) "" else " Las ${left.size} que faltan quedan en la playlist, en «Sin añadir», para buscarlas otra vez.",
                        )
                    }
                    return@Column
                }
                is ImportStatus.SimpPick -> {
                    SimpMusicPick(s.lists, onCancel = { status = ImportStatus.Idle }) { chosen ->
                        chosen.forEach { env.library.saveCollection(it.name, it.songs, it.cover) }
                        status = ImportStatus.Finished(
                            if (chosen.size == 1) "Playlist importada" else "${chosen.size} playlists importadas",
                            "${chosen.sumOf { it.songs.size }} canciones, iguales que en SimpMusic. No se ha descargado nada.",
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
                    FormRow("Listo", tint = c.accent, last = true, onClick = onDone)
                }
                ImportStatus.Reading -> FormSection(null) {
                    Row(Modifier.padding(16.dp, 14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Spinner(); Spacer(Modifier.width(8.dp)); Text("Leyendo la playlist…", style = Typo.body, color = c.label)
                    }
                }
                ImportStatus.Idle -> Unit
            }
            pending?.let { job ->
                if (status == ImportStatus.Idle) FormSection("Sin terminar", footer = "Se cortó a medias; sigue donde se quedó.") {
                    FormRow("«${job.playlist.name}»", "${job.results.size} de ${job.playlist.tracks.size}", tint = c.label)
                    FormRow("Continuar", tint = c.accent) { match(job) }
                    FormRow("Descartar", tint = c.destructive, last = true) { job.discard(); pending = null }
                }
            }
            FormSection(
                "Desde un enlace",
                footer = "Apple Music o Spotify: abre la playlist → Compartir → Copiar enlace. Tiene que ser pública. De Spotify llegan hasta unas 100 canciones; para listas más largas, usa el CSV de Exportify.",
            ) {
                FormTextField(link, { link = it }, "Enlace de Spotify o Apple Music")
                Box(Modifier.fillMaxWidth().padding(start = 16.dp).height(0.5.dp).background(c.separator))
                Row(Modifier.fillMaxWidth().padding(start = 7.dp, end = 16.dp, top = 13.dp, bottom = 13.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    CapsuleButton("Pegar", Icons.Rounded.ContentPaste, prominent = false, enabled = !busy) { link = clipboard.getText()?.text ?: link }
                    CapsuleButton("Importar", Icons.Rounded.SaveAlt, prominent = true, enabled = !busy && link.isNotEmpty()) {
                        val l = link
                        read { if (SpotifyImporter.isSpotify(l)) SpotifyImporter.fetchPublic(l) else AppleMusicImporter.fetchPublic(l) }
                    }
                }
            }
            FormSection(
                "Desde un archivo",
                footer = "Spotify: exporta la playlist en exportify.app (gratis, entra con tu cuenta de Spotify) y elige el .csv; trae todas las canciones y su ISRC, que empareja mejor. SimpMusic: Ajustes › Copia de seguridad, y elige el archivo .backup; sus canciones ya son de YouTube Music, así que llegan exactas.",
            ) {
                FormRow("CSV de Exportify (Spotify)", icon = Icons.Rounded.Description, tint = c.accent, enabled = !busy) {
                    csvFile.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "*/*"))
                }
                FormRow("Copia de SimpMusic (.backup)", icon = Icons.Rounded.Restore, tint = c.accent, last = true, enabled = !busy) {
                    simpFile.launch(arrayOf("application/zip", "application/octet-stream", "*/*"))
                }
            }
            FormSection(
                "Copia de la biblioteca",
                footer = "Archivo library.json de Pear Music (también el de iOS). Se añade lo que no tengas, sin borrar nada.",
            ) {
                FormRow("Importar copia", icon = Icons.Rounded.SaveAlt, tint = c.accent, enabled = !busy) { importFile.launch(arrayOf("application/json", "*/*")) }
                FormRow("Exportar copia", icon = Icons.Rounded.IosShare, tint = c.accent, last = true, enabled = !busy) { exportFile.launch("libremusic-library.json") }
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
            Text("$good bien · ${review.size} para revisar · ${none.size} no encontradas", style = Typo.headline, color = c.label)
            Text(
                if (review.isEmpty() && none.isEmpty()) "Todas encajan con su versión en YouTube Music."
                else "Toca las dudosas para elegir la versión correcta. Las que dejes sin elegir no se añaden.",
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
                    m.track.title, subtitle = trackLine(m.track) + "\n" + (pick?.let { "→ ${it.title} · ${it.artist}" } ?: if (m.candidates.isEmpty()) "Sin resultados" else "Sin elegir"),
                    tint = c.label, chevron = m.candidates.isNotEmpty(), last = k == indices.lastIndex && open != i,
                ) { if (m.candidates.isNotEmpty()) open = if (open == i) null else i }
                if (open == i) {
                    m.candidates.forEachIndexed { j, cand ->
                        FormRow(
                            cand.song.title, subtitle = cand.song.artist + if (j == 0) " · más probable" else "",
                            checked = pick?.id == cand.song.id, tint = c.label,
                        ) { picks[i] = cand.song; open = null }
                    }
                    FormRow("Ninguna (no añadir)", checked = pick == null, tint = c.secondaryLabel, last = k == indices.lastIndex) { picks[i] = null; open = null }
                }
            }
        }
    }
    rows("Para revisar", review)
    rows("No encontradas", none)
    Column(Modifier.padding(16.dp, 22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        PillButton("Crear playlist con ${songCount(songs.size)}", null, prominent = true, modifier = Modifier.fillMaxWidth(), enabled = songs.isNotEmpty()) {
            onCreate(songs, matches.indices.filter { chosen(it) == null }.map { matches[it].track })
        }
        PillButton("Cancelar", null, prominent = false, modifier = Modifier.fillMaxWidth(), onClick = onCancel)
    }
}

/** Elegir qué playlists de SimpMusic traer (todas marcadas al principio). */
@Composable
private fun SimpMusicPick(lists: List<SimpPlaylist>, onCancel: () -> Unit, onImport: (List<SimpPlaylist>) -> Unit) {
    val c = Libre.colors
    val selected = remember(lists) { androidx.compose.runtime.mutableStateListOf<Int>().apply { addAll(lists.indices.filter { lists[it].songs.isNotEmpty() }) } }
    FormSection("Copia de SimpMusic", footer = "Las canciones ya son de YouTube Music: llegan exactas, sin buscar. No se descarga nada.") {
        lists.forEachIndexed { i, l ->
            FormRow(l.name, subtitle = songCount(l.songs.size), checked = i in selected, tint = c.label, enabled = l.songs.isNotEmpty(), last = i == lists.lastIndex) {
                if (i in selected) selected.remove(i) else selected.add(i)
            }
        }
    }
    Column(Modifier.padding(16.dp, 22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        PillButton(
            if (selected.size == 1) "Importar 1 playlist" else "Importar ${selected.size} playlists", null, prominent = true,
            modifier = Modifier.fillMaxWidth(), enabled = selected.isNotEmpty(),
        ) { onImport(selected.sorted().map { lists[it] }) }
        PillButton("Cancelar", null, prominent = false, modifier = Modifier.fillMaxWidth(), onClick = onCancel)
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

    PlainListScreen("Ordenar playlists", if (items.isEmpty()) "Todavía no hay playlists" else null) {
        item {
            Text(
                "Arrastra ≡ para cambiar el orden del carrusel. Al mover algo, Playlists se ordena «A mano».",
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
    SettingsPage("Sin añadir") {
        if (tracks.isEmpty()) {
            CenterNote("No queda ninguna canción por añadir", 60.dp)
            return@SettingsPage
        }
        FormSection(null, footer = if (searching) "Buscando en YouTube Music… $done de ${tracks.size}" else "Se buscan otra vez en YouTube Music (a veces aparecen versiones nuevas). Elige la buena y se añade a la playlist.") {
            FormCustomRow {
                Box(Modifier.padding(16.dp, 10.dp)) {
                    PillButton(if (searching) "Buscando…" else "Buscar otra vez", Icons.Rounded.Refresh, prominent = true, modifier = Modifier.fillMaxWidth(), enabled = !searching) {
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
                    t.title, subtitle = trackLine(t) + (m?.let { "\n" + if (it.candidates.isEmpty()) "Sin resultados" else "${it.candidates.size} posibles" } ?: ""),
                    tint = c.label, chevron = m?.candidates?.isNotEmpty() == true, last = k == tracks.lastIndex && open != t,
                    trailing = { IconTap(Icons.Rounded.Close, "Descartar ${t.title}", tint = c.secondaryLabel) { app.libremusic.data.PendingImports.remove(playlistId, t) } },
                ) { if (m?.candidates?.isNotEmpty() == true) open = if (open == t) null else t }
                if (open == t && m != null) {
                    m.candidates.forEachIndexed { j, cand ->
                        FormRow(cand.song.title, subtitle = cand.song.artist + if (j == 0) " · más probable" else "", tint = c.label, last = k == tracks.lastIndex && j == m.candidates.lastIndex) {
                            env.library.addToPlaylist(playlistId, cand.song)
                            app.libremusic.data.PendingImports.remove(playlistId, t)
                            open = null
                            env.app.toast = "Añadida a la playlist"
                        }
                    }
                }
            }
        }
    }
}
