package app.libremusic.ui


import app.libremusic.L
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.libremusic.data.Lyrics
import app.libremusic.data.LyricsClient
import app.libremusic.data.Song
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.LocalReduceMotion
import app.libremusic.ui.theme.Typo

private sealed interface LyricsLoad {
    data object Loading : LyricsLoad
    data class Ready(val lyrics: Lyrics?) : LyricsLoad
    data object Failed : LyricsLoad
}

/**
 * Letra de la canción que suena, en el sitio de la carátula (pestaña «Letra» junto a «Cola»). Si está sincronizada,
 * la línea actual se resalta y se mantiene centrada; tocar una línea salta a ese momento. Mismo aspecto que
 * `LyricsView` en iOS.
 */
@Composable
fun LyricsView(song: Song, modifier: Modifier = Modifier) {
    val c = Libre.colors
    val env = LocalEnv.current
    val context = LocalContext.current
    val st by env.player.state.collectAsState()
    var attempt by remember { mutableIntStateOf(0) }
    val load by produceState<LyricsLoad>(LyricsLoad.Loading, song.id, attempt, st.durationMs > 0) {
        value = LyricsLoad.Loading
        value = runCatching { LyricsLoad.Ready(LyricsClient.lyrics(context, song, st.durationMs / 1000.0)) }
            .getOrDefault(LyricsLoad.Failed)
    }
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        when (val l = load) {
            LyricsLoad.Loading -> Spinner()
            LyricsLoad.Failed -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(L("No se pudo cargar la letra"), style = Typo.headline, color = c.label)
                Text(L("Revisa la conexión e inténtalo otra vez."), style = Typo.subheadline, color = c.secondaryLabel)
                PillButton(L("Reintentar"), Icons.Rounded.Refresh, prominent = false) { attempt++ }
            }
            is LyricsLoad.Ready -> {
                val lyrics = l.lyrics
                when {
                    lyrics == null -> LyricsNote(L("No hay letra para esta canción"))
                    lyrics.instrumental -> LyricsNote(L("Instrumental"))
                    lyrics.synced -> SyncedLyrics(lyrics)
                    else -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 16.dp)) {
                        Text(lyrics.plain.orEmpty(), style = Typo.title3.copy(fontWeight = FontWeight.SemiBold), color = c.label)
                        LyricsCredit()
                    }
                }
            }
        }
    }
}

@Composable
private fun SyncedLyrics(lyrics: Lyrics) {
    val c = Libre.colors
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val reduce = LocalReduceMotion.current
    // El progreso llega cada 0,5 s; entre medias se calcula en cada fotograma para que la línea cambie a tiempo.
    val position by produceState(st.positionMs, st.positionMs, st.isPlaying, st.rate) {
        val base = st.positionMs
        val t0 = System.nanoTime()
        value = base
        if (st.isPlaying) while (true) withFrameMillis { value = base + ((System.nanoTime() - t0) / 1_000_000.0 * st.rate).toLong() }
    }
    val current by remember(lyrics) { derivedStateOf { lyrics.indexAt(position) } }
    val list = rememberLazyListState()
    var userScrolledAt by remember { mutableStateOf(0L) }
    val centerOffset = with(LocalDensity.current) { -140.dp.roundToPx() }
    LaunchedEffect(list.isScrollInProgress) { if (list.isScrollInProgress) userScrolledAt = System.currentTimeMillis() }
    LaunchedEffect(current) {
        // Si la persona está moviendo la letra, se le deja 3 s antes de volver a seguir la canción.
        if (current < 0 || System.currentTimeMillis() - userScrolledAt < 3000) return@LaunchedEffect
        if (reduce) list.scrollToItem(current, centerOffset) else list.animateScrollToItem(current, centerOffset)
    }
    LazyColumn(Modifier.fillMaxSize().edgeFade(48.dp), state = list, contentPadding = PaddingValues(top = 140.dp, bottom = 200.dp)) {
        itemsIndexed(lyrics.lines, key = { i, _ -> i }) { i, line ->
            val color by animateColorAsState(
                when {
                    i == current -> c.label
                    i < current -> c.secondaryLabel.copy(alpha = 0.55f)
                    else -> c.secondaryLabel
                },
                uiEaseOut(300), label = "line",
            )
            Text(
                line.text.ifBlank { "♪" },
                style = Typo.title3.copy(fontWeight = FontWeight.Bold),
                color = color,
                modifier = Modifier.fillMaxWidth()
                    .rowHighlight { env.player.seekTo(line.timeMs) }
                    .padding(horizontal = 24.dp, vertical = 9.dp),
            )
        }
        item { LyricsCredit() }
    }
}

@Composable
private fun LyricsNote(text: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(text, style = Typo.headline, color = Libre.colors.secondaryLabel)
    }
}

@Composable
private fun LyricsCredit() {
    Text(
        L("Letra de LRCLIB"), style = Typo.caption, color = Libre.colors.tertiaryLabel,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 20.dp),
    )
}
