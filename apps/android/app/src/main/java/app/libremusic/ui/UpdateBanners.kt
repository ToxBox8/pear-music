package app.libremusic.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.SportsSoccer
import androidx.compose.material.icons.rounded.SystemUpdate
import androidx.compose.runtime.setValue
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.libremusic.L
import app.libremusic.data.Updates
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.semibold
import app.libremusic.ui.theme.themeSurface

/**
 * «Esta versión es antigua» en Inicio (0.5 de x.1.1): por debajo de la mínima recomendada, 2 versiones menores por
 * detrás o 21 días sin actualizar. «Actualizar» abre el aviso de siempre; «Ahora no» lo quita 24 h (por debajo de la
 * mínima) o 3 días. Igual que `OldVersionBanner` en iOS.
 */
@Composable
fun OldVersionBanner() {
    val c = Libre.colors
    val env = LocalEnv.current
    val context = LocalContext.current
    val stale by Updates.stale.collectAsState()
    if (stale == null) return
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).themeSurface(22.dp, c).padding(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.SystemUpdate, null, tint = c.accent, modifier = Modifier.size(26.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(L("Esta versión es antigua"), style = Typo.headline, color = c.label)
                Text(L("Puede fallar. Actualiza para tener los arreglos."), style = Typo.footnote, color = c.secondaryLabel)
            }
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PillButton(L("Actualizar"), null, prominent = true, modifier = Modifier.weight(1f)) { env.app.updateTick++ }
            PillButton(L("Ahora no"), null, prominent = false, modifier = Modifier.weight(1f)) { Updates.dismissStale(context.applicationContext) }
        }
    }
}

/**
 * Los servidores de Pear no responden pero YouTube sí (2.5 de x.1.1), casi siempre por los bloqueos de LaLiga durante
 * el fútbol. Se puede quitar; vuelve a salir si en la siguiente apertura sigue igual. Igual que en iOS.
 */
@Composable
fun ServersBlockedBanner() {
    val c = Libre.colors
    val blocked by app.libremusic.data.Incident.unreachable.collectAsState()
    var closed by androidx.compose.runtime.saveable.rememberSaveable { androidx.compose.runtime.mutableStateOf(false) }
    if (!blocked || closed) return
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).themeSurface(22.dp, c).padding(start = 18.dp, top = 14.dp, bottom = 14.dp, end = 8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(Icons.Rounded.SportsSoccer, null, tint = c.accent, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(L("Los servidores de Pear no responden"), style = Typo.headline, color = c.label)
            Text(
                L("La música sigue funcionando. Si hay fútbol, puede ser por los bloqueos de LaLiga: los avisos y el soporte vuelven al acabar el partido."),
                style = Typo.footnote, color = c.secondaryLabel,
            )
        }
        IconTap(Icons.Rounded.Close, L("Cerrar el aviso"), tint = c.secondaryLabel) { closed = true }
    }
}

/** Pear Dev con una versión simulada (2.2 de x.1.1): cinta fija arriba para no olvidarlo. */
@Composable
fun SimulatedVersionRibbon() {
    if (!app.libremusic.BuildConfig.ADMIN_TOOLS) return
    val simulated by Updates.simulated.collectAsState()
    val v = simulated ?: return
    Box(Modifier.fillMaxWidth().background(Libre.colors.orange).statusBarsPadding().padding(vertical = 3.dp), contentAlignment = Alignment.Center) {
        Text(L("VERSIÓN SIMULADA: {0}", v), style = Typo.footnote.semibold, color = Color.White)
    }
}
