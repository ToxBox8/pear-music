package app.libremusic.ui


import app.libremusic.L
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Construction
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.libremusic.data.Incident
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Typo

/**
 * Lo que se ve según el estado de incidencias (Fase 4): nivel 1, un aviso arriba que se puede cerrar; nivel 2, el
 * aviso de modo seguro (no se cierra mientras dure); nivel 3, mantenimiento a pantalla completa, con la opción de
 * escuchar lo descargado. Igual que `IncidentOverlay` en iOS.
 */
@Composable
fun IncidentOverlay() {
    val st by Incident.state.collectAsState()
    var dismissed by rememberSaveable { mutableLongStateOf(-1L) }
    AnimatedVisibility(st.level in 1..2 && dismissed != st.counter, enter = fadeIn(uiEaseOut(250)), exit = fadeOut(uiEaseOut(200))) {
        IncidentBanner(st, onClose = if (st.level == 1) ({ dismissed = st.counter }) else null)
    }
    AnimatedVisibility(st.level == 3, enter = fadeIn(uiEaseOut(300)), exit = fadeOut(uiEaseOut(250))) { MaintenanceScreen(st) }
}

@Composable
private fun IncidentBanner(st: Incident.State, onClose: (() -> Unit)?) {
    val c = Libre.colors
    val safe = st.level == 2
    Box(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 6.dp)) {
        Row(
            Modifier.fillMaxWidth()
                .shadowSoft(12.dp, RoundedCornerShape(18.dp), 0.25f)
                .background(if (safe) c.orange else c.background, RoundedCornerShape(18.dp))
                .padding(start = 14.dp, end = 6.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(if (safe) Icons.Rounded.Shield else Icons.Rounded.Info, null, tint = if (safe) androidx.compose.ui.graphics.Color.White else c.accent, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(if (safe) L("Modo seguro") else L("Aviso"), style = Typo.subheadline.copy(fontWeight = FontWeight.SemiBold), color = if (safe) androidx.compose.ui.graphics.Color.White else c.label)
                Text(st.message, style = Typo.footnote, color = if (safe) androidx.compose.ui.graphics.Color.White.copy(alpha = 0.9f) else c.secondaryLabel)
            }
            if (onClose != null) IconTap(Icons.Rounded.Close, L("Cerrar el aviso"), tint = c.secondaryLabel, onClick = onClose)
        }
    }
}

@Composable
private fun MaintenanceScreen(st: Incident.State) {
    val c = Libre.colors
    val env = LocalEnv.current
    val downloaded by env.library.downloadedSongs.collectAsState()
    Box(Modifier.fillMaxSize().background(c.background)) {
        ThemeBackdrop(false, null)
        Column(
            Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = 28.dp),
            verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            GradientIcon(Icons.Rounded.Construction, 3, 72.dp)
            Spacer(Modifier.height(24.dp))
            Text(L("En mantenimiento"), style = Typo.largeTitle, color = c.label, textAlign = TextAlign.Center)
            Spacer(Modifier.height(10.dp))
            Text(st.message, style = Typo.body, color = c.secondaryLabel, textAlign = TextAlign.Center)
            Spacer(Modifier.height(10.dp))
            Text(
                L("Mientras tanto no se puede buscar, actualizar ni enviar nada. Tu música descargada sigue aquí."),
                style = Typo.footnote, color = c.tertiaryLabel, textAlign = TextAlign.Center,
            )
            if (downloaded.isNotEmpty()) {
                Spacer(Modifier.height(28.dp))
                PillButton(L("Escuchar mis descargas"), null, prominent = true, modifier = Modifier.fillMaxWidth()) {
                    env.player.play(downloaded.shuffled(), 0)
                }
            }
        }
    }
}
