package app.libremusic.ui


import app.libremusic.L
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.libremusic.data.PlayStats
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo

/**
 * «Estadísticas» en Tu música: lo que más escuchas este mes, este año o siempre. Sólo con lo guardado en este móvil
 * ([PlayStats]). Mismo contenido que `StatsView` en iOS.
 */
@Composable
fun StatsScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val player by env.player.state.collectAsState()
    val data by PlayStats.data.collectAsState()
    var periodKey by rememberSaveable { mutableStateOf(PlayStats.Period.Month.key) }
    val period = PlayStats.Period.entries.first { it.key == periodKey }
    val summary = remember(data, period) { PlayStats.summary(data, PlayStats.since(period)) }
    val tnum = Typo.subheadline.copy(fontFeatureSettings = "tnum")
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        LazyColumn(Modifier.fillMaxSize()) {
            item { NavBar(null, onBack = { env.app.pop() }) }
            item { LargeTitle(L("Estadísticas"), Modifier.padding(bottom = 8.dp)) }
            item {
                Box(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                    Segmented(PlayStats.Period.entries.map { it.key to it.title }, periodKey) { periodKey = it }
                }
            }
            if (summary.plays == 0) {
                item { CenterNote(L("Aún no hay escuchas en este periodo. Cuenta cada canción que suena al menos 30 segundos."), 48.dp) }
            } else {
                item {
                    Text(
                        "${times(summary.plays, "escucha", "escuchas")} de ${songCount(summary.songs)} y ${times(summary.artists, "artista", "artistas")}",
                        style = Typo.subheadline, color = c.secondaryLabel,
                        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 6.dp),
                    )
                }
                item { StatsHeader(L("Lo que más escuchas")) }
                val top = summary.topSongs.map { it.first }
                itemsIndexed(summary.topSongs, key = { _, it -> "s" + it.first.id }) { i, (song, n) ->
                    GlassRowItem({ env.player.play(top, i) }) {
                        Text("${i + 1}", style = tnum.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryLabel, textAlign = TextAlign.End, modifier = Modifier.widthIn(min = 22.dp))
                        Spacer(Modifier.width(10.dp))
                        CoverImage(song.thumb(160), Modifier.size(46.dp).clip(RoundedCornerShape(8.dp)))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(song.title, style = Typo.body.copy(fontWeight = FontWeight.Medium), color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(song.artist, style = Typo.caption, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Spacer(Modifier.width(8.dp))
                        Text(times(n, "vez", "veces"), style = tnum, color = c.secondaryLabel)
                    }
                }
                item { StatsHeader(L("Tus artistas")) }
                itemsIndexed(summary.topArtists, key = { _, it -> "a" + it.first }) { i, (name, n) ->
                    val cover = summary.topSongs.firstOrNull { primaryArtist(it.first.artist) == name }?.first
                        ?: data.songs.values.firstOrNull { primaryArtist(it.artist) == name }
                    GlassRowItem({ env.app.push(Route.Artist(name)) }) {
                        Text("${i + 1}", style = tnum.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryLabel, textAlign = TextAlign.End, modifier = Modifier.widthIn(min = 22.dp))
                        Spacer(Modifier.width(10.dp))
                        CoverImage(cover?.thumb(160), Modifier.size(46.dp).clip(CircleShape))
                        Spacer(Modifier.width(12.dp))
                        Text(name, style = Typo.body.copy(fontWeight = FontWeight.Medium), color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Spacer(Modifier.width(8.dp))
                        Text(times(n, "escucha", "escuchas"), style = tnum, color = c.secondaryLabel)
                    }
                }
            }
            if (data.plays.isNotEmpty()) {
                item {
                    Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 28.dp)) {
                        HoldToConfirmButton(L("Mantén para borrar las estadísticas")) { PlayStats.clear() }
                        Text(
                            L("Se guardan sólo en este móvil y no salen en la copia de la biblioteca."),
                            style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }
                }
            }
            item { BottomSpacer() }
        }
    }
}

@Composable
private fun StatsHeader(text: String) {
    Text(text, style = Typo.title3.copy(fontWeight = FontWeight.Bold), color = Libre.colors.label, modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 22.dp, bottom = 6.dp))
}

private fun times(n: Int, one: String, many: String) = "$n ${if (n == 1) one else many}"
