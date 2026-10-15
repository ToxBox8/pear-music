package app.libremusic.ui


import app.libremusic.L
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Prefs
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.themeSurface

/**
 * «Primeros pasos» (Fase 2.1), lo último de la bienvenida: una tarjeta en Inicio con seis cosas que se marcan
 * solas al hacerlas. Se oculta con «Ocultar» o al completarla. Sólo en instalaciones nuevas. Igual en iOS.
 */
val FIRST_STEPS get() = listOf(
    "play" to L("Escucha una canción"),
    "favorite" to L("Guarda una favorita con el corazón"),
    "download" to L("Descarga algo para escucharlo sin conexión"),
    "discover" to L("Desliza un rato en Descubrir"),
    "jam" to L("Abre el Jam (el icono de las tres personas)"),
    "pin" to L("Fija un álbum o una playlist con la chincheta"),
)

/** Detecta los primeros pasos mirando el estado de la app (se llama una vez en la raíz). */
@Composable
fun FirstStepsWatcher(env: ScreenEnv) {
    val steps by Prefs.firstSteps.collectAsState()
    if ("hidden" in steps || FIRST_STEPS.all { it.first in steps }) return
    LaunchedEffect(Unit) { env.player.state.collect { if (it.current != null) Prefs.markFirstStep("play") } }
    LaunchedEffect(Unit) { env.library.data.collect { if (it.favorites.isNotEmpty()) Prefs.markFirstStep("favorite") } }
    LaunchedEffect(Unit) { env.library.downloadedSongs.collect { if (it.isNotEmpty()) Prefs.markFirstStep("download") } }
    LaunchedEffect(Unit) { snapshotFlow { env.app.tab }.collect { if (it == Tab.Discover) Prefs.markFirstStep("discover") } }
    LaunchedEffect(Unit) { snapshotFlow { env.app.showJam }.collect { if (it) Prefs.markFirstStep("jam") } }
    LaunchedEffect(Unit) { env.library.data.collect { if (it.playlists.any { p -> p.pinned }) Prefs.markFirstStep("pin") } }
}

@Composable
fun FirstStepsCard() {
    val c = Libre.colors
    val steps by Prefs.firstSteps.collectAsState()
    val showDiscover by Prefs.showDiscover.collectAsState()
    // Sin la pestaña Descubrir, su paso no cuenta.
    val items = FIRST_STEPS.filter { showDiscover || it.first != "discover" }
    val done = items.count { it.first in steps }
    if ("hidden" in steps || done == items.size) return
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).themeSurface(22.dp, c).padding(18.dp).animateContentSize(uiEaseOut(300)),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(L("Primeros pasos"), style = Typo.title3.copy(fontWeight = FontWeight.Bold), color = c.label)
                Text(L("{0} de {1} · se marcan solos", done, items.size), style = Typo.footnote, color = c.secondaryLabel)
            }
            Text(L("Ocultar"), style = Typo.subheadline, color = c.accent, modifier = Modifier.tactile(label = L("Ocultar primeros pasos")) { Prefs.markFirstStep("hidden") }.padding(8.dp))
        }
        Spacer(Modifier.height(10.dp))
        // Barra de progreso.
        Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(c.fill)) {
            Box(Modifier.fillMaxWidth(done / items.size.toFloat()).height(6.dp).clip(CircleShape).background(c.accent))
        }
        Spacer(Modifier.height(8.dp))
        items.forEach { (key, title) ->
            val ok = key in steps
            Row(Modifier.padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (ok) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null, tint = if (ok) c.accent else c.tertiaryLabel, modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(12.dp))
                Text(title, style = Typo.body, color = if (ok) c.secondaryLabel else c.label, textDecoration = if (ok) TextDecoration.LineThrough else null)
            }
        }
    }
}
