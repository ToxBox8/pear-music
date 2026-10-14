package app.libremusic.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.libremusic.ui.theme.AppTheme
import app.libremusic.ui.theme.ArtworkLevel
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Prefs
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.rememberPalette

/**
 * Guía inicial (Fase 4): tres pantallas la primera vez —tema, colores de la portada y descargas— que dejan
 * la app configurada sin entrar a Ajustes. Mismos pasos y textos que `OnboardingView` en iOS. Se puede
 * saltar y volver a ver desde Ajustes › Ayuda y soporte.
 */
@Composable
fun OnboardingScreen(onDone: () -> Unit) {
    val c = Libre.colors
    var page by rememberSaveable { mutableIntStateOf(0) }
    Box(Modifier.fillMaxSize().background(c.background)) {
        ThemeBackdrop(false, null)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (page > 0) {
                    Text("Atrás", style = Typo.body, color = c.accent, modifier = Modifier.tactile(label = "Atrás") { page-- }.padding(12.dp))
                }
                Spacer(Modifier.weight(1f))
                Text("Saltar", style = Typo.body, color = c.accent, modifier = Modifier.tactile(label = "Saltar la guía") { onDone() }.padding(12.dp))
            }
            AnimatedContent(
                page, Modifier.weight(1f), label = "guide",
                transitionSpec = {
                    val dir = if (targetState > initialState) 1 else -1
                    (slideInHorizontally(uiEaseOut(320)) { it / 4 * dir } + fadeIn(uiEaseOut(320))) togetherWith
                        (slideOutHorizontally(uiEaseOut(220)) { -it / 4 * dir } + fadeOut(uiEaseOut(220)))
                },
            ) { p ->
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
                    when (p) {
                        0 -> ThemeStep()
                        1 -> ColorsStep()
                        else -> DownloadsStep()
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalArrangement = Arrangement.Center) {
                repeat(3) { i ->
                    val w by animateDpAsState(if (i == page) 22.dp else 8.dp, uiEaseOut(250), label = "dot")
                    Box(Modifier.padding(horizontal = 4.dp).size(w, 8.dp).background(if (i == page) c.accent else c.tertiaryLabel, CircleShape))
                }
            }
            PillButton(if (page < 2) "Siguiente" else "Empezar", null, prominent = true, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp)) {
                if (page < 2) page++ else onDone()
            }
        }
    }
}

@Composable
private fun StepTitle(title: String, text: String) {
    val c = Libre.colors
    Text(title, style = Typo.largeTitle, color = c.label, modifier = Modifier.padding(top = 8.dp))
    Spacer(Modifier.height(8.dp))
    Text(text, style = Typo.body, color = c.secondaryLabel)
    Spacer(Modifier.height(22.dp))
}

@Composable
private fun ThemeStep() {
    val current by Prefs.theme.collectAsState()
    val appearance by Prefs.appearance.collectAsState()
    StepTitle("Elige tu tema", "Cambia el fondo, las tarjetas, el color y la letra de toda la app. Puedes cambiarlo cuando quieras en Ajustes › Aspecto.")
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        AppTheme.ordered.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                pair.forEach { t -> Box(Modifier.weight(1f).tactile(label = t.title) { Prefs.setTheme(t) }) { ThemeCard(t, t == current) } }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
    Spacer(Modifier.height(18.dp))
    Segmented(listOf("system" to "Automático", "light" to "Claro", "dark" to "Oscuro"), appearance, enabled = current.forcedDark == null) { Prefs.setAppearance(it) }
}

@Composable
private fun ColorsStep() {
    val level by Prefs.artworkLevel.collectAsState()
    val on = Prefs.artworkColorsApp.collectAsState().value || Prefs.artworkColorsPlayer.collectAsState().value
    val palette = rememberPalette()
    StepTitle("Colores de la portada", "Mientras suena una canción, la app toma colores parecidos a los de su portada. Elige cuánto; el texto siempre se lee bien.")
    ArtworkPreview(palette[0], if (on) level else ArtworkLevel.Off)
    Spacer(Modifier.height(18.dp))
    val selected = if (!on || !level.enabled) "off" else ArtworkLevel.presets.firstOrNull { it.first == level.title }?.first ?: ""
    Segmented(listOf("off" to "No") + ArtworkLevel.presets.map { it.first to it.first }, selected) { key ->
        val enable = key != "off"
        Prefs.setArtworkColorsApp(enable); Prefs.setArtworkColorsPlayer(enable)
        if (enable) Prefs.setArtworkLevel(ArtworkLevel.presets.first { it.first == key }.second)
    }
}

@Composable
private fun DownloadsStep() {
    val c = Libre.colors
    val quality by Prefs.quality.collectAsState()
    StepTitle(
        "Descargas",
        "Descarga una canción con su flecha, o una playlist o un álbum entero con «Descargar todo». Se guardan en este móvil a la máxima calidad y las tienes en Biblioteca › Descargadas, también sin conexión.",
    )
    Text("Calidad al escuchar sin descargar", style = Typo.headline, color = c.label)
    Spacer(Modifier.height(10.dp))
    Segmented(listOf("max" to "Máxima", "low" to "Ahorro de datos"), quality) { Prefs.setQuality(it) }
    Spacer(Modifier.height(8.dp))
    Text(
        if (quality == "low") "Gasta menos datos móviles (48 kbps)." else "Mejor sonido (Opus, unos 160 kbps).",
        style = Typo.footnote, color = c.secondaryLabel, textAlign = TextAlign.Start,
    )
}
