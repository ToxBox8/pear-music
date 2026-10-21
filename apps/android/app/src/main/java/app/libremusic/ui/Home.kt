package app.libremusic.ui


import app.libremusic.L
import androidx.compose.runtime.mutableIntStateOf

import androidx.compose.ui.layout.onSizeChanged

import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.text.font.FontWeight
import kotlin.math.roundToInt
import androidx.compose.ui.layout.layout
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.foundation.lazy.rememberLazyListState
import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.libremusic.LibreMusicApplication
import app.libremusic.data.HomeItem
import app.libremusic.data.HomeShelf
import app.libremusic.data.RemoteCollection
import app.libremusic.data.Song
import app.libremusic.data.YTClient
import app.libremusic.data.SearchResults
import app.libremusic.jam.JamPhase
import app.libremusic.jam.JamService
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Prefs
import app.libremusic.ui.theme.JamIcon
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.semibold
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Calendar

data class HomeUiState(
    val shelves: List<HomeShelf> = emptyList(),
    val forYou: List<Song> = emptyList(),
    val seed: Song? = null,
    /** «Novedades de tus artistas» (lanzamientos de este año). */
    val releases: List<RemoteCollection> = emptyList(),
    val loading: Boolean = false,
    val failed: Boolean = false,
    val query: String = "",
    val results: SearchResults = SearchResults(),
    val searching: Boolean = false,
    /** Texto de la última búsqueda terminada (para no decir «sin resultados» antes de tiempo). */
    val searchedQuery: String = "",
    val searchFailed: Boolean = false,
)

/** Inicio: estanterías de YouTube Music, «Para ti» (radio de lo último que escuchaste) y búsqueda. */
class HomeViewModel(app: Application) : AndroidViewModel(app) {
    private val library = (app as LibreMusicApplication).library
    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    companion object {
        /** Sólo las capturas lo ponen a true. */
        @Volatile var offline = false
    }

    /** Idioma en que se pidieron las estanterías: vienen de YouTube y se vuelven a pedir al cambiarlo (1.8 de x.1.1). */
    private var shelvesLang: String? = null

    fun loadIfNeeded() {
        if ((_state.value.shelves.isEmpty() || shelvesLang != app.libremusic.I18n.youtubeHl) && !_state.value.loading) load()
    }

    fun load() {
        shelvesLang = app.libremusic.I18n.youtubeHl
        // Capturas (`ScreenshotTest`): sin red, como `Demo` en iOS. Si no, la rueda de carga gira mientras la petición
        // espera y la captura no llega a estar quieta.
        if (offline) { _state.value = _state.value.copy(loading = false, failed = true); return }
        _state.value = _state.value.copy(loading = true, failed = false)
        viewModelScope.launch {
            val shelves = withContext(Dispatchers.IO) { runCatching { YTClient.home() } }
            val list = shelves.getOrNull() ?: _state.value.shelves
            val homeSong = list.flatMap { it.items }.firstNotNullOfOrNull { (it as? HomeItem.SongItem)?.song }
            val d = library.data.value
            val seed = d.recents.firstOrNull() ?: d.favorites.firstOrNull() ?: homeSong
            val forYou = seed?.let { s -> withContext(Dispatchers.IO) { runCatching { YTClient.radio(s.id) }.getOrDefault(emptyList()) }.take(20) }
            _state.value = _state.value.copy(
                shelves = list, loading = false, failed = shelves.isFailure && list.isEmpty(),
                seed = seed, forYou = forYou ?: emptyList(),
            )
            // Novedades después, para no retrasar el resto de Inicio (son hasta 16 peticiones la primera vez al día).
            val saved = allSongs(d.favorites, d.playlists, emptyList())
            val artists = app.libremusic.data.Releases.topArtists(saved, app.libremusic.data.PlayStats.data.value)
            val releases = runCatching { app.libremusic.data.Releases.load(getApplication(), artists) }.getOrDefault(emptyList())
            _state.value = _state.value.copy(releases = releases)
        }
    }

    private var searchJob: kotlinx.coroutines.Job? = null

    /** Busca mientras se escribe: espera 350 ms sin teclear (como iOS) y cancela la búsqueda anterior. */
    fun setQuery(q: String) {
        _state.value = _state.value.copy(query = q)
        searchJob?.cancel()
        if (q.isBlank()) {
            _state.value = _state.value.copy(results = SearchResults(), searchFailed = false, searching = false, searchedQuery = "")
            return
        }
        searchJob = viewModelScope.launch {
            kotlinx.coroutines.delay(350)
            runSearch(q.trim())
        }
    }

    /** «Buscar» en el teclado: sin esperar. */
    fun search() {
        val q = _state.value.query.trim()
        if (q.isEmpty()) return
        searchJob?.cancel()
        searchJob = viewModelScope.launch { runSearch(q) }
    }

    private suspend fun runSearch(q: String) {
        _state.value = _state.value.copy(searching = true, searchFailed = false)
        val r = withContext(Dispatchers.IO) { runCatching { YTClient.searchAll(q) } }
        if (_state.value.query.trim() != q) return // ya se escribió otra cosa
        _state.value = _state.value.copy(
            searching = false, searchedQuery = q, results = r.getOrDefault(SearchResults()), searchFailed = r.isFailure,
        )
    }
}

private fun greeting(): String = when (Calendar.getInstance().get(Calendar.HOUR_OF_DAY)) {
    in 6..12 -> L("Buenos días")
    in 13..20 -> L("Buenas tardes")
    else -> L("Buenas noches")
}

/** Botón redondo de la barra superior (Jam, +…), con la superficie del tema. */
@Composable
fun ToolbarButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tint: androidx.compose.ui.graphics.Color = Libre.colors.label, onClick: () -> Unit) {
    val c = Libre.colors
    val circle = androidx.compose.foundation.shape.CircleShape
    val press = rememberGlassPress()
    Box(
        if (LocalGlass.current != null) {
            Modifier.size(44.dp).glassInteractive(press, label, grow = 0.12f, onClick = onClick)
                .liquidGlass(circle, c.dark, GlassStyle.Button, press = press, fallback = app.libremusic.ui.theme.material(c.dark))
        } else {
            Modifier.size(44.dp).background(app.libremusic.ui.theme.material(c.dark, thick = true), circle)
                .tactile(label = label, onClick = onClick)
        },
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = tint, modifier = Modifier.size(21.dp)) }
}

@Composable
fun HomeScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val st by env.home.state.collectAsState()
    val lib by env.library.data.collectAsState()
    val player by env.player.track.collectAsState()
    val searchPlacement by Prefs.searchPlacement.collectAsState()
    val jam by JamService.state.collectAsState()
    val jamActive = jam.phase == JamPhase.Hosting || jam.phase == JamPhase.Joined
    val barStyle by app.libremusic.ui.theme.Prefs.barStyle.collectAsState()
    val language by app.libremusic.I18n.lang.collectAsState()
    LaunchedEffect(language) { env.home.loadIfNeeded() }
    // Con la barra estilo SimpMusic, Buscar es el círculo de la barra: Inicio no lleva buscador.
    val hasSearch = searchPlacement != "tab" && barStyle != "simpmusic"
    val showingSearch = hasSearch && st.query.isNotEmpty()

    // Cabecera como la de iOS (título grande + barra de búsqueda siempre visible): al bajar, el saludo
    // se encoge hasta la barra de arriba, y el botón del Jam y el buscador se quedan fijos.
    val listState = rememberLazyListState()
    val density = LocalDensity.current
    val titleHeight = 52.dp
    val titlePx = with(density) { titleHeight.toPx() }
    val searchHeight = if (hasSearch) 48.dp else 0.dp
    val collapse by remember {
        derivedStateOf { if (listState.firstVisibleItemIndex > 0) 1f else (listState.firstVisibleItemScrollOffset / titlePx).coerceIn(0f, 1f) }
    }
    // Contenido pasando por debajo de la cabecera: aparece el fondo de la barra (scroll edge de iOS).
    val under by remember {
        // A la vez que aparece el título pequeño (antes salía más tarde y el saludo flotaba sobre el contenido).
        derivedStateOf { listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > titlePx * 0.6f }
    }
    val barAlpha by animateFloatAsState(if (under) 1f else 0f, uiEaseOut(200), label = "bar")
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    var toolbarWidth by remember { mutableIntStateOf(0) }

    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = 12.dp)) {
            item { Spacer(Modifier.height(statusTop + 48.dp + titleHeight + searchHeight + 12.dp)) }
            if (showingSearch) {
                searchResultItems(st)
            } else {
                item { ServersBlockedBanner() }
                item { OldVersionBanner() }
                item { FirstStepsCard() }
                item { PinnedRow() }
                if (lib.recents.isNotEmpty()) item { HomeSection(L("Escuchado recientemente")) { SongCardsRow(lib.recents.take(15)) } }
                if (st.forYou.isNotEmpty()) item {
                    HomeSection(L("Para ti"), st.seed?.let { L("Porque escuchaste «{0}»", it.title) }) { QuickPicks(st.forYou) }
                }
                if (st.releases.isNotEmpty()) item {
                    HomeSection(L("Novedades de tus artistas"), L("Lo que han sacado este año")) { ShelfContent(st.releases.map { HomeItem.CollectionItem(it) }) }
                }
                if (lib.userPlaylists.isNotEmpty()) item {
                    HomeSection(L("Tus playlists")) { HomePlaylists() }
                }
                items(st.shelves.size) { i ->
                    val shelf = st.shelves[i]
                    HomeSection(shelf.title) { ShelfContent(shelf.items) }
                }
                if (st.loading && st.shelves.isEmpty()) {
                    item { Box(Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) { Spinner() } }
                } else if (st.failed) {
                    item {
                        Column(Modifier.fillMaxWidth().padding(top = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(L("No se pudieron cargar las recomendaciones."), style = Typo.body, color = c.secondaryLabel)
                            Spacer(Modifier.height(10.dp))
                            PillButton(L("Reintentar"), Icons.Rounded.Refresh, prominent = false, modifier = Modifier.widthIn(max = 220.dp)) { env.home.load() }
                        }
                    }
                }
            }
            item { BottomSpacer() }
        }

        // Cabecera fija encima de la lista.
        Column(
            Modifier
                .fillMaxWidth()
                .drawBehind {
                    if (barAlpha > 0f) {
                        // Fondo opaco (antes dejaba ver el contenido por debajo del saludo) y un borde suave abajo.
                        val solid = c.background.copy(alpha = 1f)
                        drawRect(
                            Brush.verticalGradient(0f to solid, 0.86f to solid, 1f to solid.copy(alpha = 0f)),
                            alpha = barAlpha,
                        )
                    }
                }
                .statusBarsPadding()
                .padding(bottom = 18.dp),
        ) {
            Box(Modifier.fillMaxWidth().height(48.dp).padding(start = 16.dp, end = 12.dp, top = 4.dp)) {
                // Título pequeño de la barra: aparece cuando el grande ya se ha escondido.
                // Centrado, dejando a los dos lados el ancho de los botones de la derecha (los más anchos), para no
                // pisar Ajustes ni el Jam.
                Text(
                    greeting(), style = Typo.headline, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.align(Alignment.Center).fillMaxWidth()
                        .padding(horizontal = with(density) { toolbarWidth.toDp() } + 8.dp)
                        .graphicsLayer { alpha = ((collapse - 0.6f) / 0.4f).coerceIn(0f, 1f) },
                )
                // Ajustes vive siempre aquí, arriba a la izquierda; ya no puede ir en la barra (lo decidió Toxbox).
                Box(Modifier.align(Alignment.CenterStart).tourTarget("tab:settings")) {
                    ToolbarButton(Icons.Rounded.Settings, L("Ajustes"), tint = c.label) { env.app.select(Tab.Settings) }
                }
                Row(
                    Modifier.align(Alignment.CenterEnd).onSizeChanged { toolbarWidth = it.width },
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(Modifier.tourTarget("jam")) {
                        ToolbarButton(
                            JamIcon(filled = jamActive), if (jamActive) L("Abrir el Jam") else L("Jam con amigos"),
                            tint = if (jamActive) c.accent else c.label,
                        ) { env.app.showJam = true }
                    }
                    AvisosBell()
                }
            }
            // La altura se calcula al medir (no al componer): el desplazamiento no recompone la cabecera.
            Box(
                Modifier.fillMaxWidth().clipToBounds().layout { m, cons ->
                    val h = (titlePx * (1f - collapse)).roundToInt()
                    val p = m.measure(cons.copy(minHeight = 0, maxHeight = titlePx.roundToInt()))
                    layout(p.width, h) { p.place(0, 0) }
                },
            ) {
                Text(
                    greeting(), style = Typo.largeTitle, color = c.label,
                    modifier = Modifier
                        .padding(start = 16.dp, end = 16.dp, top = 2.dp)
                        .graphicsLayer { translationY = -titlePx * collapse; alpha = 1f - collapse },
                )
            }
            if (hasSearch) {
                SearchField(st.query, env.home::setQuery, env.home::search, Modifier.padding(horizontal = 16.dp))
            }
        }
    }
}

@Composable
fun CenterNote(text: String, top: androidx.compose.ui.unit.Dp = 48.dp) {
    Text(
        text, style = Typo.body, color = Libre.colors.secondaryLabel, textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(top = top, start = 32.dp, end = 32.dp),
    )
}

@Composable
private fun HomeSection(title: String, subtitle: String? = null, content: @Composable () -> Unit) {
    val c = Libre.colors
    Column(Modifier.padding(top = 18.dp, bottom = 12.dp)) {
        Column(Modifier.padding(horizontal = 16.dp)) {
            Text(title, style = Typo.title2, color = c.label)
            if (subtitle != null) Text(subtitle, style = Typo.subheadline, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.height(12.dp))
        content()
    }
}

@Composable
private fun HomePlaylists() {
    val c = Libre.colors
    val env = LocalEnv.current
    val lib by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        items(lib.userPlaylists, key = { it.id }) { p ->
            Column(Modifier.width(150.dp).tactile(label = p.name) { env.app.push(Route.PlaylistR(p.id)) }) {
                PlaylistCover(p, 150.dp, coverFile = env.library.coverFile(p.id), coverVersion = ver)
                Spacer(Modifier.height(6.dp))
                Text(p.name, style = Typo.subheadline.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(songCount(p.songs.size), style = Typo.caption, color = c.secondaryLabel)
            }
        }
    }
}

@Composable
private fun ShelfContent(all: List<HomeItem>) {
    val items = all.distinctBy { it.key }
    val env = LocalEnv.current
    val songs = items.mapNotNull { (it as? HomeItem.SongItem)?.song }
    if (songs.size == items.size) {
        QuickPicks(songs)
    } else {
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(items, key = { it.key }) { item ->
                when (item) {
                    is HomeItem.SongItem -> {
                        var menu by remember { mutableStateOf(false) }
                        Box(Modifier.tactile(label = item.song.title, onLongClick = { menu = true }) { env.player.play(songs, songs.indexOf(item.song)) }) {
                            CardLabel(item.song.thumb(400), item.song.title, item.song.artist)
                            ContextMenu(menu, { menu = false }, songMenu(item.song), preview = { SongPreview(item.song) })
                        }
                    }
                    is HomeItem.CollectionItem -> Box(Modifier.tactile(label = item.collection.title) { env.app.push(Route.Collection(item.collection)) }) {
                        CardLabel(item.collection.thumb(400), item.collection.title, item.collection.subtitle)
                    }
                }
            }
        }
    }
}

// MARK: Álbum / playlist de YouTube Music ---------------------------------------------------------

@Composable
fun CollectionScreen(collection: RemoteCollection) {
    val c = Libre.colors
    val env = LocalEnv.current
    val player by env.player.track.collectAsState()
    var songs by remember(collection.id) { mutableStateOf<List<Song>>(emptyList()) }
    var loading by remember(collection.id) { mutableStateOf(true) }
    val data by env.library.data.collectAsState()
    // Un álbum («MPREb_…») va a «Tus álbumes»; una playlist de YouTube Music, a Playlists.
    val isAlbum = collection.id.startsWith("MPREb")
    var saved by remember(collection.id) { mutableStateOf(false) }
    val inAlbums = isAlbum && data.album(collection.id) != null
    val save = {
        if (!saved && !inAlbums) {
            saved = true
            env.library.saveCollection(
                collection.title, songs, collection.thumb(600),
                if (isAlbum) app.libremusic.data.AlbumInfo.from(collection.id, collection.subtitle) else null,
            )
        }
    }
    LaunchedEffect(collection.id) {
        songs = withContext(Dispatchers.IO) { runCatching { YTClient.collectionSongs(collection) }.getOrDefault(emptyList()) }
        loading = false
    }
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        LazyColumn(Modifier.fillMaxSize()) {
            item { NavBar(null, onBack = { env.app.pop() }) }
            item {
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    val shape = RoundedCornerShape(22.dp)
                    Box(Modifier.size(220.dp).shadowSoft(16.dp, shape, 0.25f).clip(shape)) { CoverImage(collection.thumb(600), Modifier.fillMaxSize()) }
                    Text(collection.title, style = Typo.title2, color = c.label, textAlign = TextAlign.Center)
                    // «Álbum • Artista • año»: el artista se toca para ir a su perfil (Fase 3.1).
                    val parts = collection.subtitle.split(" • ")
                    if (isAlbum && parts.size >= 2 && parts[1].isNotBlank()) {
                        val scope = rememberCoroutineScope()
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(parts[0] + " · ", style = Typo.subheadline, color = c.secondaryLabel)
                            Text(
                                parts[1], style = Typo.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.accent,
                                modifier = Modifier.tactile(label = L("Ver el perfil de {0}", parts[1])) { openArtistProfile(env, scope, parts[1]) },
                            )
                            if (parts.size >= 3) Text(" · " + parts.last(), style = Typo.subheadline, color = c.secondaryLabel)
                        }
                    } else {
                        Text(collection.subtitle, style = Typo.subheadline, color = c.secondaryLabel, textAlign = TextAlign.Center)
                    }
                    PlayShuffleBar(songs) { list, i -> env.player.play(list, i) }
                    if (isAlbum) {
                        PillButton(
                            if (inAlbums || saved) L("En Tus álbumes") else L("Añadir a Tus álbumes"),
                            if (inAlbums || saved) Icons.Rounded.Check else Icons.Rounded.Add,
                            prominent = false, modifier = Modifier.fillMaxWidth(), enabled = songs.isNotEmpty(),
                        ) {
                            if (inAlbums) {
                                env.app.alert = AlertSpec(
                                    title = L("¿Quitar «{0}» de Tus álbumes?", collection.title),
                                    message = L("Las canciones descargadas se quedan en Descargadas."),
                                    buttons = listOf(
                                        AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
                                        AlertButton(L("Quitar de Tus álbumes"), AlertButton.Role.Destructive) {
                                            data.album(collection.id)?.let { env.library.deletePlaylist(it.id) }
                                            saved = false
                                        },
                                    ),
                                )
                            } else save()
                        }
                    } else {
                        PillButton(
                            if (saved) L("Guardada en tu biblioteca") else L("Guardar en biblioteca"),
                            if (saved) Icons.Rounded.Check else Icons.Rounded.Add,
                            prominent = false, modifier = Modifier.fillMaxWidth(), enabled = songs.isNotEmpty() && !saved,
                        ) { save() }
                    }
                    // Descarga sólo las canciones de este álbum o lista (dueño = su browseId).
                    // Descargar un álbum también lo guarda en «Tus álbumes».
                    DownloadAllButton(collection.id, songs, collection.title, onStart = if (isAlbum) save else null)
                    Spacer(Modifier.height(4.dp))
                }
            }
            when {
                loading -> item { Box(Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) { Spinner() } }
                songs.isEmpty() -> item { CenterNote(L("No se pudieron cargar las canciones"), 32.dp) }
                else -> items(songs, key = { it.id }) { s ->
                    SongRow(s, songs, Modifier.padding(start = 16.dp, end = 8.dp))
                    RowSeparator()
                }
            }
            item { BottomSpacer() }
        }
    }
}

/** Separador fino de lista (listRowSeparatorTint primary 0,08). */
@Composable
fun RowSeparator(start: androidx.compose.ui.unit.Dp = 80.dp) {
    Box(Modifier.fillMaxWidth().padding(start = start).height(0.5.dp).background(Libre.colors.label.copy(alpha = 0.08f)))
}

// MARK: Pestaña Buscar (si se elige en Ajustes) -----------------------------------------------------

@Composable
fun SearchTabScreen() {
    val env = LocalEnv.current
    val st by env.home.state.collectAsState()
    val player by env.player.track.collectAsState()
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                Spacer(Modifier.statusBarsPadding().height(52.dp))
                LargeTitle(L("Buscar"))
                SearchField(st.query, env.home::setQuery, env.home::search, Modifier.padding(16.dp, 8.dp))
            }
            searchResultItems(st)
            item { BottomSpacer() }
        }
    }
}
