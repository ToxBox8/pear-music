package app.libremusic.ui


import app.libremusic.L
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Widgets
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import app.libremusic.playback.Widgets
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo

/**
 * Ajustes › Widgets (Fase 3.4; antes «Personalización», renombrado por Toxbox): los widgets de la pantalla de inicio (añadirlos, su tema y la playlist del
 * widget «Playlist fijada»). Sólo Android: en iPhone los widgets necesitan una extensión de WidgetKit.
 */
@Composable
fun PersonalizationScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val context = LocalContext.current
    val data by env.library.data.collectAsState()
    var theme by remember { mutableStateOf(Widgets.theme(context)) }
    var playlist by remember { mutableStateOf(Widgets.playlistId(context)) }
    // Al volver del lanzador tras añadir uno, se mira otra vez cuáles están puestos.
    var tick by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { tick++ }

    SettingsPage(L("Widgets")) {
        FormSection(
            L("Widgets"),
            footer = L("También puedes mantener pulsada la pantalla de inicio › Widgets › Pear Music. Se pueden cambiar de tamaño."),
        ) {
            Widgets.Kind.entries.forEachIndexed { i, kind ->
                val placed = remember(tick) { Widgets.installed(context, kind) }
                FormRow(
                    kind.title, subtitle = kind.text, icon = Icons.Rounded.Widgets, iconPalette = 1 + i % 6, last = i == Widgets.Kind.entries.lastIndex,
                    trailing = {
                        if (placed) {
                            Icon(Icons.Rounded.CheckCircle, L("Puesto"), tint = c.accent, modifier = Modifier.size(22.dp))
                        } else {
                            Text(
                                L("Añadir"), style = Typo.body.copy(fontWeight = FontWeight.SemiBold), color = c.accent,
                                modifier = Modifier.tactile(label = L("Añadir {0} a la pantalla de inicio", kind.title)) {
                                    if (!Widgets.requestPin(context, kind)) env.app.toast = L("Tu lanzador no deja añadirlo desde aquí: mantén pulsada la pantalla de inicio › Widgets")
                                }.padding(8.dp),
                            )
                        }
                    },
                )
            }
        }
        FormSection(L("Aspecto de los widgets")) {
            Box(Modifier.padding(16.dp)) {
                Segmented(listOf("dark" to L("Oscuro"), "light" to L("Claro")), theme) { theme = it; Widgets.setTheme(context, it) }
            }
        }
        val lists = data.playlists
        FormSection(L("Playlist fijada"), footer = if (lists.isEmpty()) L("Crea una playlist o guarda un álbum para elegirlo.") else L("La que sale en el widget «Playlist fijada».")) {
            FormRow(L("La primera fijada en Biblioteca"), checked = playlist == null, last = lists.isEmpty()) {
                playlist = null; Widgets.setPlaylistId(context, null)
            }
            lists.forEachIndexed { i, p ->
                FormRow(p.name, subtitle = p.album?.line?.ifEmpty { null } ?: songCount(p.songs.size), checked = playlist == p.id, last = i == lists.lastIndex) {
                    playlist = p.id; Widgets.setPlaylistId(context, p.id)
                }
            }
        }
    }
}
