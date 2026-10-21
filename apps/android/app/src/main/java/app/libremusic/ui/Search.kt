package app.libremusic.ui


import app.libremusic.L
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.ui.semantics.semantics
import androidx.compose.material.icons.rounded.Album
import androidx.compose.foundation.background
import androidx.compose.material3.Icon
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.libremusic.data.ArtistPage
import app.libremusic.data.RemoteArtist
import app.libremusic.data.RemoteCollection
import app.libremusic.data.YTClient
import app.libremusic.data.albumLine
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.bold
import app.libremusic.ui.theme.semibold
import androidx.compose.material3.Text
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// MARK: Resultados de búsqueda (los usan Inicio y la pestaña Buscar), como SearchResultsView en iOS -------

/**
 * Artistas, álbumes y canciones en secciones separadas. La búsqueda se lanza mientras se escribe
 * (HomeViewModel.setQuery, con una pausa corta); YouTube Music ya ignora mayúsculas y acentos.
 */
fun LazyListScope.searchResultItems(st: HomeUiState) {
    val q = st.query.trim()
    val r = st.results
    when {
        q.isEmpty() -> item { CenterNote(L("Busca canciones, álbumes o artistas")) }
        st.searching && r.isEmpty -> item { Box(Modifier.fillMaxWidth().padding(top = 48.dp), contentAlignment = Alignment.Center) { Spinner() } }
        st.searchFailed -> item { CenterNote(L("No se pudo buscar. Revisa tu conexión.")) }
        r.isEmpty && st.searchedQuery == q -> item { CenterNote(L("No hay resultados para «{0}»", q)) }
        r.isEmpty -> item { Box(Modifier.fillMaxWidth().padding(top = 48.dp), contentAlignment = Alignment.Center) { Spinner() } }
        else -> {
            if (r.artists.isNotEmpty()) item(key = "artists") {
                ResultSection(L("Artistas"), dim = st.searching) {
                    val env = LocalEnv.current
                    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        items(r.artists, key = { it.id }) { a -> ArtistCard(a) { env.app.push(Route.RemoteArtistR(a)) } }
                    }
                }
            }
            if (r.albums.isNotEmpty()) item(key = "albums") {
                ResultSection(L("Álbumes"), dim = st.searching) {
                    val env = LocalEnv.current
                    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        items(r.albums, key = { it.id }) { c -> AlbumCard(c) { env.app.push(Route.Collection(c)) } }
                    }
                }
            }
            if (r.songs.isNotEmpty()) {
                item(key = "songsTitle") { ResultTitle(L("Canciones"), Modifier.padding(top = 18.dp, bottom = 6.dp)) }
                items(r.songs.distinctBy { it.id }, key = { "r" + it.id }) { s ->
                    SongRow(s, r.songs, Modifier.padding(start = 16.dp, end = 8.dp).alpha(if (st.searching) 0.6f else 1f), more = true)
                }
            }
        }
    }
}

@Composable
private fun ResultTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = Typo.title3.bold, color = Libre.colors.label, modifier = modifier.padding(horizontal = 16.dp))
}

@Composable
private fun ResultSection(title: String, dim: Boolean = false, content: @Composable () -> Unit) {
    Column(Modifier.padding(top = 18.dp).alpha(if (dim) 0.6f else 1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ResultTitle(title)
        content()
    }
}

/** Tarjeta redonda de artista, como ArtistCard en iOS. */
@Composable
fun ArtistCard(artist: RemoteArtist, onClick: () -> Unit) {
    val c = Libre.colors
    Column(
        Modifier.width(112.dp).tactile(label = L("Artista {0}", artist.name), onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(104.dp).shadowSoft(8.dp, CircleShape, 0.18f).clip(CircleShape)) {
            CoverImage(artist.thumbnail, Modifier.fillMaxSize())
        }
        Text(artist.name, style = Typo.subheadline.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

/** Tarjeta de álbum con portada, título y «artista · año» (o «tipo · año» en la página del artista). */
@Composable
fun AlbumCard(collection: RemoteCollection, size: Dp = 150.dp, showArtist: Boolean = true, onClick: () -> Unit) {
    val c = Libre.colors
    val shape = RoundedCornerShape(14.dp)
    Column(Modifier.width(size).tactile(label = collection.title, onClick = onClick), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(size).clip(shape)) { CoverImage(collection.thumb(400), Modifier.fillMaxSize()) }
        Text(collection.title, style = Typo.subheadline.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(if (showArtist) albumLine(collection.subtitle) else albumYear(collection.subtitle), style = Typo.caption, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** En la página del artista no se repite su nombre: «Single · 2024». */
private fun albumYear(subtitle: String): String {
    val parts = subtitle.split(" • ")
    if (parts.size < 3) return albumLine(subtitle)
    return listOf(parts.first(), parts.last()).filter { it != "Álbum" }.joinToString(" · ")
}

// MARK: Página de artista, como ArtistView en iOS ----------------------------------------------------

@Composable
fun RemoteArtistScreen(artist: RemoteArtist) {
    val c = Libre.colors
    val env = LocalEnv.current
    val player by env.player.track.collectAsState()
    var page by remember(artist.id) { mutableStateOf<ArtistPage?>(null) }
    var loading by remember(artist.id) { mutableStateOf(true) }
    LaunchedEffect(artist.id) {
        page = withContext(Dispatchers.IO) { runCatching { YTClient.artist(artist) }.getOrNull() }
        loading = false
    }
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        LazyColumn(Modifier.fillMaxSize()) {
            item { NavBar(null, onBack = { env.app.pop() }) }
            item {
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.size(180.dp).shadowSoft(16.dp, CircleShape, 0.25f).clip(CircleShape)) {
                        CoverImage(page?.thumbnail ?: artist.thumbnail, Modifier.fillMaxSize())
                    }
                    Text(page?.name ?: artist.name, style = Typo.largeTitle, color = c.label, textAlign = TextAlign.Center)
                    if (artist.subtitle.isNotEmpty()) Text(artist.subtitle, style = Typo.subheadline, color = c.secondaryLabel)
                    page?.songs?.takeIf { it.isNotEmpty() }?.let { songs ->
                        Spacer(Modifier.height(4.dp))
                        PlayShuffleBar(songs) { list, i -> env.player.play(list, i) }
                    }
                    // Lo que tienes guardado de este artista (lo que antes se abría desde «Tu música › Artistas»).
                    val lib by env.library.data.collectAsState()
                    val downloaded by env.library.downloadedSongs.collectAsState()
                    val name = page?.name ?: artist.name
                    val mine = remember(lib, downloaded, name) {
                        allSongs(lib.favorites, lib.playlists, downloaded).count { primaryArtist(it.artist).equals(name, ignoreCase = true) }
                    }
                    if (mine > 0) {
                        Text(
                            L("En tu biblioteca: {0}", songCount(mine)), style = Typo.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.accent,
                            modifier = Modifier.tactile(label = L("Ver tus canciones de {0}", name)) { env.app.push(Route.Artist(name)) }.padding(8.dp),
                        )
                    }
                }
            }
            val p = page
            when {
                loading -> item { Box(Modifier.fillMaxWidth().padding(top = 32.dp), contentAlignment = Alignment.Center) { Spinner() } }
                p == null -> item { CenterNote(L("No se pudo cargar el artista. Revisa tu conexión."), 32.dp) }
                p.songs.isEmpty() && p.albums.isEmpty() && p.singles.isEmpty() -> item { CenterNote(L("Este artista no tiene canciones ni álbumes disponibles."), 32.dp) }
                else -> {
                    if (p.songs.isNotEmpty()) {
                        item { ResultTitle(L("Canciones más escuchadas"), Modifier.padding(top = 26.dp, bottom = 6.dp)) }
                        items(p.songs, key = { "t" + it.id }) { s -> SongRow(s, p.songs, Modifier.padding(start = 16.dp, end = 8.dp)) }
                    }
                    val disco = { kind: String -> Route.Discography(p.name, kind, p.albums, p.singles, p.albumsMore, p.singlesMore) }
                    if (p.albums.isNotEmpty()) item { ArtistAlbums(L("Álbumes"), p.albums) { env.app.push(disco("albums")) } }
                    if (p.singles.isNotEmpty()) item { ArtistAlbums(L("Singles y EP"), p.singles) { env.app.push(disco("singles")) } }
                }
            }
            item { BottomSpacer() }
        }
    }
}

@Composable
private fun ArtistAlbums(title: String, list: List<RemoteCollection>, onSeeAll: () -> Unit) {
    val env = LocalEnv.current
    val c = Libre.colors
    Column(Modifier.padding(top = 26.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // «Ver todo»: la discografía completa (YouTube Music + MusicBrainz), siempre, porque el carrusel nunca la trae entera.
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            ResultTitle(title, Modifier.weight(1f))
            Text(L("Ver todo"), style = Typo.body, color = c.accent, modifier = Modifier.tactile(label = L("Ver todos: {0}", title), onClick = onSeeAll).padding(horizontal = 16.dp, vertical = 6.dp))
        }
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(list, key = { it.id }) { c -> AlbumCard(c, showArtist = false) { env.app.push(Route.Collection(c)) } }
        }
    }
}

// MARK: Discografía completa (Fase 3.1), como DiscographyView en iOS ---------------------------------------

/**
 * Todos los álbumes o todos los singles y EP de un artista: lo de YouTube Music («Ver todo», se puede escuchar) y,
 * detrás, lo que MusicBrainz conoce y YouTube Music no tiene, atenuado como «No disponible para escuchar».
 */
@Composable
fun DiscographyScreen(route: Route.Discography) {
    val c = Libre.colors
    val env = LocalEnv.current
    val player by env.player.track.collectAsState()
    var kind by remember { mutableStateOf(route.kind) }
    var albums by remember { mutableStateOf<List<app.libremusic.data.Discography.Item>?>(null) }
    var singles by remember { mutableStateOf<List<app.libremusic.data.Discography.Item>?>(null) }
    LaunchedEffect(route) {
        withContext(Dispatchers.IO) {
            val ytAlbums = route.albumsRef?.let { runCatching { YTClient.discography(it, route.artist) }.getOrNull() } ?: route.albums
            val ytSingles = route.singlesRef?.let { runCatching { YTClient.discography(it, route.artist) }.getOrNull() } ?: route.singles
            // Primero lo de YouTube Music (rápido); luego se completa con MusicBrainz (1 petición por segundo).
            albums = ytAlbums.map { app.libremusic.data.Discography.Item.Playable(it) }
            singles = ytSingles.map { app.libremusic.data.Discography.Item.Playable(it) }
            val mb = app.libremusic.data.Discography.musicBrainz(route.artist).orEmpty()
            albums = app.libremusic.data.Discography.merge(ytAlbums, mb, app.libremusic.data.Discography.Kind.Album)
            singles = app.libremusic.data.Discography.merge(ytSingles, mb, app.libremusic.data.Discography.Kind.Single)
        }
    }
    val list = if (kind == "albums") albums else singles
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        LazyVerticalGrid(
            GridCells.Adaptive(150.dp), Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) { NavBar(route.artist, onBack = { env.app.pop() }) }
            item(span = { GridItemSpan(maxLineSpan) }) {
                Segmented(listOf("albums" to L("Álbumes"), "singles" to L("Singles y EP")), kind) { kind = it }
            }
            when {
                list == null -> item(span = { GridItemSpan(maxLineSpan) }) { Box(Modifier.fillMaxWidth().padding(top = 32.dp), contentAlignment = Alignment.Center) { Spinner() } }
                list.isEmpty() -> item(span = { GridItemSpan(maxLineSpan) }) { CenterNote(if (kind == "albums") L("No hay álbumes.") else L("No hay singles ni EP."), 32.dp) }
                else -> items(list.size, key = { i -> list[i].let { if (it is app.libremusic.data.Discography.Item.Playable) it.collection.id else "mb$i" } }) { i ->
                    when (val item = list[i]) {
                        is app.libremusic.data.Discography.Item.Playable ->
                            AlbumCard(item.collection, size = 150.dp, showArtist = false) { env.app.push(Route.Collection(item.collection)) }
                        is app.libremusic.data.Discography.Item.Missing -> MissingAlbumCard(item.release)
                    }
                }
            }
        }
    }
}

/** Un disco que existe (MusicBrainz) pero no está en YouTube Music: atenuado y sin acción. */
@Composable
private fun MissingAlbumCard(release: app.libremusic.data.Discography.MbRelease) {
    val c = Libre.colors
    val shape = RoundedCornerShape(14.dp)
    Column(Modifier.width(150.dp).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(150.dp).clip(shape).background(c.fill), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Album, null, tint = c.tertiaryLabel, modifier = Modifier.size(44.dp))
        }
        Text(release.title, style = Typo.subheadline.semibold, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(
            listOf(release.year, L("No disponible para escuchar")).filter { it.isNotEmpty() }.joinToString(" · "),
            style = Typo.caption, color = c.tertiaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
    }
}
