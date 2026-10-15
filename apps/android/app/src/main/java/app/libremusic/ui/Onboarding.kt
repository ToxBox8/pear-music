package app.libremusic.ui


import app.libremusic.L
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.DownloadForOffline
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.draw.clip
import app.libremusic.ui.theme.themeSurface
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
 * Bienvenida (Fase 2.1 de la 1.0): bienvenida → privacidad (condiciones y telemetría, por separado y sin marcar;
 * la cuenta, opcional) → tema → colores → descargas. Después siguen el recorrido sobre la app real
 * ([TourOverlay]), las historias ([StoriesScreen]) y la tarjeta «Primeros pasos» de Inicio. Mismos pasos y
 * textos que `OnboardingView` en iOS. Se puede volver a ver desde Ajustes › Ayuda y soporte.
 *
 * [privacyOnly]: quien ya usaba la app antes de la 1.0 sólo ve la pantalla de privacidad, una vez.
 */
@Composable
fun OnboardingScreen(privacyOnly: Boolean = false, onDone: () -> Unit) {
    val c = Libre.colors
    val pages = if (privacyOnly) listOf(Page.Privacy) else Page.entries
    var page by rememberSaveable { mutableIntStateOf(0) }
    val termsAccepted by Prefs.termsAccepted.collectAsState()
    var terms by rememberSaveable { mutableStateOf(termsAccepted) }
    val current = pages[page]
    fun finish() {
        if (!termsAccepted) Prefs.acceptTerms()
        onDone()
    }
    Box(Modifier.fillMaxSize().background(c.background)) {
        ThemeBackdrop(false, null)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (page > 0) {
                    Text(L("Atrás"), style = Typo.body, color = c.accent, modifier = Modifier.tactile(label = L("Atrás")) { page-- }.padding(12.dp))
                }
                Spacer(Modifier.weight(1f))
                // Las condiciones no se saltan: «Saltar» sólo aparece después de aceptarlas.
                if (terms && current != Page.Language && current != Page.Welcome && current != Page.Privacy) {
                    Text(L("Saltar"), style = Typo.body, color = c.accent, modifier = Modifier.tactile(label = L("Saltar la guía")) { finish() }.padding(12.dp))
                }
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
                    when (pages[p]) {
                        Page.Language -> {
                            // Primero el idioma (Cierre 1.0): «Elige tu idioma» también en inglés, por si no lee español.
                            StepTitle(L("Elige tu idioma"), L("Choose your language · Tria la llengua · Escolle o idioma · Aukeratu hizkuntza · Elektu vian lingvon · Escolha o idioma"))
                            Box(Modifier.padding(horizontal = 0.dp)) { LanguagePicker() }
                        }
                        Page.Welcome -> WelcomeStep()
                        Page.Privacy -> PrivacyStep(terms, { terms = it }, onAccount = {
                            Prefs.openAccountAfterIntro = true
                            if (privacyOnly) finish() else page++
                        })
                        Page.Theme -> ThemeStep()
                        Page.Colors -> ColorsStep()
                        Page.Downloads -> DownloadsStep()
                    }
                }
            }
            if (pages.size > 1) {
                Row(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalArrangement = Arrangement.Center) {
                    repeat(pages.size) { i ->
                        val w by animateDpAsState(if (i == page) 22.dp else 8.dp, uiEaseOut(250), label = "dot")
                        Box(Modifier.padding(horizontal = 4.dp).size(w, 8.dp).background(if (i == page) c.accent else c.tertiaryLabel, CircleShape))
                    }
                }
            }
            val last = page == pages.lastIndex
            val label = when {
                current == Page.Welcome -> L("Empezar")
                current == Page.Privacy && !terms -> L("Acepta las condiciones para seguir")
                current == Page.Privacy -> if (last) L("Seguir") else L("Ahora no, seguir")
                last -> L("Empezar a escuchar")
                else -> L("Siguiente")
            }
            PillButton(
                label, null, prominent = true, enabled = current != Page.Privacy || terms,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
            ) {
                if (current == Page.Privacy) Prefs.acceptTerms()
                if (last) finish() else page++
            }
        }
    }
}

private enum class Page { Language, Welcome, Privacy, Theme, Colors, Downloads }

@Composable
private fun WelcomeStep() {
    val c = Libre.colors
    Spacer(Modifier.height(36.dp))
    androidx.compose.foundation.Image(
        androidx.compose.ui.res.painterResource(app.libremusic.R.drawable.logo), null,
        Modifier.size(104.dp).shadowSoft(14.dp, androidx.compose.foundation.shape.RoundedCornerShape(24.dp), 0.25f)
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(24.dp)),
    )
    Spacer(Modifier.height(26.dp))
    Text(L("Te damos la bienvenida a Pear Music"), style = Typo.largeTitle, color = c.label)
    Spacer(Modifier.height(10.dp))
    Text(
        L("Toda la música de YouTube Music, gratis y sin anuncios. Con la pantalla apagada, sin conexión y con un Jam para escuchar con tus amigos."),
        style = Typo.body, color = c.secondaryLabel,
    )
    Spacer(Modifier.height(26.dp))
    WelcomePoint(androidx.compose.material.icons.Icons.Rounded.MusicNote, 1, L("Escucha lo que quieras"), L("Sin anuncios, sin límites y sin cuenta obligatoria."))
    WelcomePoint(androidx.compose.material.icons.Icons.Rounded.DownloadForOffline, 2, L("Llévatela sin conexión"), L("Descarga canciones, álbumes y playlists a máxima calidad."))
    WelcomePoint(androidx.compose.material.icons.Icons.Rounded.Shield, 5, L("Tus datos son tuyos"), L("Sin rastreo ni publicidad. Tú decides qué compartes."))
    Spacer(Modifier.height(12.dp))
}

@Composable
private fun WelcomePoint(icon: androidx.compose.ui.graphics.vector.ImageVector, palette: Int, title: String, text: String) {
    val c = Libre.colors
    Row(Modifier.padding(vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
        GradientIcon(icon, palette, 40.dp)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = Typo.headline, color = c.label)
            Text(text, style = Typo.subheadline, color = c.secondaryLabel)
        }
    }
}

/** Condiciones (obligatorias) y telemetría (opcional), por separado y sin marcar; debajo, la cuenta opcional. */
@Composable
private fun PrivacyStep(terms: Boolean, onTerms: (Boolean) -> Unit, onAccount: () -> Unit) {
    val c = Libre.colors
    val context = androidx.compose.ui.platform.LocalContext.current
    val uri = androidx.compose.ui.platform.LocalUriHandler.current
    var telemetry by rememberSaveable { mutableStateOf(app.libremusic.data.Telemetry.enabled(context)) }
    StepTitle(L("Antes de empezar"), L("Dos cosas, por separado. Puedes cambiar la segunda cuando quieras en Ajustes › Ayuda y soporte › Tus datos."))
    ConsentBox(
        terms, onTerms,
        title = L("Acepto las condiciones de uso"),
        text = L("Pear Music es un proyecto personal y gratuito, sin relación con YouTube ni Google. Es necesario para usar la app."),
        link = L("Leer las condiciones") to { uri.openUri("https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev/legal") },
    )
    Spacer(Modifier.height(10.dp))
    ConsentBox(
        telemetry, { on -> telemetry = on; app.libremusic.data.Telemetry.setConsent(context, on) },
        title = L("Enviar datos de rendimiento (opcional)"),
        text = L("Modelo y sistema, versión, cuánto tarda en abrir, fluidez, memoria y minutos de uso, con un identificador aleatorio. ") +
            L("Un resumen a la semana; nada de lo que escuchas ni buscas. Sirve sólo para que la app vaya mejor; se borra a los 90 días."),
        link = L("Qué se envía exactamente") to { uri.openUri("https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev/privacidad") },
    )
    Spacer(Modifier.height(22.dp))
    AccountPitch(inset = 0.dp)
    Spacer(Modifier.height(12.dp))
    PillButton(L("Crear mi cuenta"), null, prominent = false, enabled = terms, modifier = Modifier.fillMaxWidth()) {
        Prefs.acceptTerms()
        onAccount()
    }
    Spacer(Modifier.height(12.dp))
}

@Composable
private fun ConsentBox(checked: Boolean, onChange: (Boolean) -> Unit, title: String, text: String, link: Pair<String, () -> Unit>) {
    val c = Libre.colors
    Row(
        Modifier.fillMaxWidth().themeSurface(app.libremusic.ui.theme.Tokens.Radius.Card.dp, c)
            .toggleable(checked, role = androidx.compose.ui.semantics.Role.Checkbox, onValueChange = onChange)
            .padding(16.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            Modifier.size(24.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(7.dp))
                .background(if (checked) c.accent else androidx.compose.ui.graphics.Color.Transparent)
                .border(1.5.dp, if (checked) c.accent else c.tertiaryLabel, androidx.compose.foundation.shape.RoundedCornerShape(7.dp)),
            contentAlignment = Alignment.Center,
        ) {
            if (checked) androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Rounded.Check, null, tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.size(17.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = Typo.headline, color = c.label)
            Spacer(Modifier.height(3.dp))
            Text(text, style = Typo.subheadline, color = c.secondaryLabel)
            Text(
                link.first, style = Typo.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = c.accent,
                modifier = Modifier.padding(top = 6.dp).tactile(label = link.first) { link.second() },
            )
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
    StepTitle(L("Elige tu tema"), L("Cambia el fondo, las tarjetas, el color y la letra de toda la app. Puedes cambiarlo cuando quieras en Ajustes › Aspecto."))
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        AppTheme.ordered.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                pair.forEach { t -> Box(Modifier.weight(1f).tactile(label = t.title) { Prefs.setTheme(t) }) { ThemeCard(t, t == current) } }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
    Spacer(Modifier.height(18.dp))
    Segmented(listOf("system" to L("Automático"), "light" to L("Claro"), "dark" to L("Oscuro")), appearance, enabled = current.forcedDark == null) { Prefs.setAppearance(it) }
}

@Composable
private fun ColorsStep() {
    val level by Prefs.artworkLevel.collectAsState()
    val on = Prefs.artworkColorsApp.collectAsState().value || Prefs.artworkColorsPlayer.collectAsState().value
    val palette = rememberPalette()
    StepTitle(L("Colores de la portada"), L("Mientras suena una canción, la app toma colores parecidos a los de su portada. Elige cuánto; el texto siempre se lee bien."))
    ArtworkPreview(palette[0], if (on) level else ArtworkLevel.Off)
    Spacer(Modifier.height(18.dp))
    val selected = if (!on || !level.enabled) "off" else ArtworkLevel.presets.firstOrNull { it.first == level.title }?.first ?: ""
    Segmented(listOf("off" to L("No")) + ArtworkLevel.presets.map { it.first to it.first }, selected) { key ->
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
        L("Descargas"),
        L("Descarga una canción con su flecha, o una playlist o un álbum entero con «Descargar todo». Se guardan en este móvil a la máxima calidad y las tienes en Biblioteca › Descargadas, también sin conexión."),
    )
    Text(L("Calidad al escuchar sin descargar"), style = Typo.headline, color = c.label)
    Spacer(Modifier.height(10.dp))
    Segmented(listOf("max" to L("Máxima"), "low" to L("Ahorro de datos")), quality) { Prefs.setQuality(it) }
    Spacer(Modifier.height(8.dp))
    Text(
        if (quality == "low") L("Gasta menos datos móviles (48 kbps).") else L("Mejor sonido (Opus, unos 160 kbps)."),
        style = Typo.footnote, color = c.secondaryLabel, textAlign = TextAlign.Start,
    )
}
