package app.libremusic.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Block
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.QrCode2
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.DownloadForOffline
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Mail
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.TableRows
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import app.libremusic.BuildConfig
import app.libremusic.L
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Typo

/**
 * Novedades tras actualizar (1.1, lo pidió Toxbox): la primera vez que se abre una versión nueva, a pantalla
 * completa y sin poder cerrarla con atrás o deslizando: hay que elegir «Enséñame lo nuevo» (recorrido guiado por
 * lo nuevo) o «Ahora no». En una instalación nueva no sale (ya está la bienvenida). Igual que `WhatsNewView` en iOS.
 */
object WhatsNew {
    /** Versión «mayor.menor»: los arreglos (1.1.1) no vuelven a enseñar el panel. */
    val current: String get() = BuildConfig.VERSION_NAME.substringBefore('-').split('.').take(2).joinToString(".")

    data class Item(val icon: ImageVector, val palette: Int, val title: String, val text: String)

    val items get() = listOf(
        // 1.2 (x.1.1). Texto público: lo aprueba Toxbox antes de publicar.
        Item(Icons.Rounded.Groups, 4, L("Jam: cada uno en su móvil"), L("Quien crea el Jam elige: que suene en un altavoz o en el móvil de cada uno a la vez, con sus cascos.")),
        Item(Icons.Rounded.QrCode2, 3, L("Comparte playlists con un QR"), L("Otro móvil lo escanea con la cámara y se la lleva con sus canciones y su orden.")),
        Item(Icons.Rounded.GridView, 1, L("Biblioteca a tu gusto"), L("Playlists en cuadrícula, como Tus álbumes. Mantén pulsada una portada y arrástrala para ordenarlas.")),
        Item(Icons.Rounded.Block, 2, L("No me interesa"), L("En Descubrir, en «⋯». Esa canción no vuelve, y si un artista no te va, deja de salir un tiempo.")),
        Item(Icons.Rounded.Settings, 0, L("Ajustes, arriba a la izquierda"), L("En Inicio. Y en Ajustes › Aspecto › Barra está todo lo de la barra junto.")),
    )
}

@Composable
fun WhatsNewScreen(onTour: () -> Unit, onClose: () -> Unit) {
    val c = Libre.colors
    // No se cierra con atrás: hay que elegir uno de los dos botones.
    BackHandler {}
    Box(Modifier.fillMaxSize().background(c.background)) {
        ThemeBackdrop(false, null)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
                Spacer(Modifier.height(40.dp))
                Text(L("Novedades"), style = Typo.largeTitle, color = c.label)
                Spacer(Modifier.height(6.dp))
                Text(L("Lo nuevo de Pear Music {0}", WhatsNew.current), style = Typo.body, color = c.secondaryLabel)
                Spacer(Modifier.height(28.dp))
                WhatsNew.items.forEach { item ->
                    Row(Modifier.fillMaxWidth().padding(bottom = 22.dp), verticalAlignment = Alignment.Top) {
                        GradientIcon(item.icon, item.palette, 40.dp)
                        Spacer(Modifier.width(16.dp))
                        Column(Modifier.weight(1f)) {
                            Text(item.title, style = Typo.headline, color = c.label)
                            Spacer(Modifier.height(2.dp))
                            Text(item.text, style = Typo.subheadline, color = c.secondaryLabel)
                        }
                    }
                }
            }
            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                PillButton(L("Enséñame lo nuevo"), null, prominent = true, modifier = Modifier.fillMaxWidth(), onClick = onTour)
                PillButton(L("Ahora no"), null, prominent = false, modifier = Modifier.fillMaxWidth(), onClick = onClose)
            }
        }
    }
}
