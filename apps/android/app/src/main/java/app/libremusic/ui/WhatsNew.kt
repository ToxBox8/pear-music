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
        Item(Icons.Rounded.School, 4, L("Guía de Ajustes"), L("Un recorrido por todos los Ajustes que te explica cada opción. Está junto a la carta.")),
        Item(Icons.Rounded.Language, 3, L("Português"), L("Pear Music ya está en portugués. Y «Español» ahora se llama «Castellano».")),
        Item(Icons.Rounded.Mail, 1, L("Soporte más rápido"), L("Con cada reporte o sugerencia va la ficha de tu móvil (modelo y versiones), para ayudarte antes.")),
        Item(Icons.Rounded.DownloadForOffline, 2, L("Actualizaciones"), L("Al descargar una versión nueva ves el progreso, y si hay que dar permiso para instalar no se vuelve a descargar.")),
        Item(Icons.Rounded.TableRows, 0, L("Barra clásica"), L("Ya no marca Descubrir cuando estás en Ajustes.")),
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
