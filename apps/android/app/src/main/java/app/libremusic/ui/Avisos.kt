package app.libremusic.ui


import app.libremusic.L
import androidx.compose.material.icons.rounded.Terminal

import androidx.compose.material.icons.rounded.Celebration

import androidx.compose.material.icons.rounded.ChatBubble

import androidx.compose.material.icons.rounded.CheckCircle

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.Campaign
import androidx.compose.material.icons.rounded.CloudOff
import androidx.compose.material.icons.rounded.NotificationImportant
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.NotificationsNone
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import app.libremusic.avisos.Aviso
import app.libremusic.avisos.AvisosRepo
import app.libremusic.avisos.AvisosWorker
import app.libremusic.avisos.EstadoAvisos
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Campana de la cabecera de Inicio, junto al Jam: abre Avisos y lleva un punto con los no leídos («9+» si pasan de
 * nueve), como la «Notificación» de SimpMusic. Igual que `AvisosBell` en iOS.
 */
@Composable
fun AvisosBell() {
    val env = LocalEnv.current
    val c = Libre.colors
    val sinLeer by AvisosRepo.sinLeer.collectAsState()
    val label = if (sinLeer > 0) L("Avisos, {0} sin leer", sinLeer) else L("Avisos")
    Box {
        ToolbarButton(if (sinLeer > 0) Icons.Rounded.Notifications else Icons.Rounded.NotificationsNone, label, tint = c.label) {
            env.app.push(Route.Avisos)
        }
        if (sinLeer > 0) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = 3.dp, y = (-2).dp)
                    .widthIn(min = 18.dp)
                    .height(18.dp)
                    .background(c.accent, CircleShape)
                    .padding(horizontal = 5.dp)
                    .clearAndSetSemantics { contentDescription = "" },
                contentAlignment = Alignment.Center,
            ) {
                Text(if (sinLeer > 9) "9+" else "$sinLeer", style = Typo.caption2, color = c.onAccent, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }
    }
}

/** Avisos de Pear Music (canal privado de Discord → web → aquí). Tirar hacia abajo recarga. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AvisosScreen() {
    val context = LocalContext.current
    val c = Libre.colors
    val scope = rememberCoroutineScope()
    val estado by AvisosRepo.estado.collectAsState()
    var refrescando by remember { mutableStateOf(false) }
    var notificar by remember { mutableStateOf(AvisosRepo.notificarActivado(context)) }

    fun permisoConcedido() =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    val pedirPermiso = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { concedido ->
        // Sin permiso no hay notificaciones: el interruptor se apaga y se deja de comprobar en segundo plano.
        if (!concedido) {
            notificar = false
            AvisosRepo.fijarNotificar(context, false)
            AvisosWorker.cancelar(context)
        }
    }
    fun cambiarNotificar(activado: Boolean) {
        notificar = activado
        AvisosRepo.fijarNotificar(context, activado)
        if (activado) {
            AvisosWorker.programar(context)
            if (!permisoConcedido()) pedirPermiso.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            AvisosWorker.cancelar(context)
        }
    }
    fun refrescar() {
        scope.launch {
            refrescando = true
            AvisosRepo.refrescar(context)
            refrescando = false
        }
    }

    LaunchedEffect(Unit) { refrescar() }
    // Lo que se ve pasa a leído y la campana se apaga (también lo que llegue mientras está abierta).
    LaunchedEffect(estado) { AvisosRepo.marcarVistos(context) }

    PullToRefreshBox(isRefreshing = refrescando, onRefresh = ::refrescar) {
        SettingsPage(L("Avisos")) {
            FormSection(null, footer = L("Comprueba cada 15 minutos si hay avisos nuevos. Sólo se pide la lista de avisos, sin enviar nada tuyo.")) {
                FormRow(
                    L("Notificar en el móvil"),
                    icon = Icons.Rounded.Notifications,
                    iconPalette = 4,
                    last = true,
                    trailing = { IosToggle(notificar, ::cambiarNotificar, label = L("Notificar en el móvil")) },
                ) { cambiarNotificar(!notificar) }
            }
            when (val e = estado) {
                EstadoAvisos.Cargando ->
                    Box(Modifier.fillMaxWidth().padding(top = 56.dp), contentAlignment = Alignment.Center) { Spinner() }
                EstadoAvisos.Error ->
                    Vacio(Icons.Rounded.CloudOff, L("No se han podido cargar"), L("Comprueba la conexión y vuelve a intentarlo.")) {
                        PillButton(L("Reintentar"), Icons.Rounded.Refresh, prominent = false, modifier = Modifier.widthIn(max = 220.dp)) { refrescar() }
                    }
                is EstadoAvisos.Listo ->
                    if (e.avisos.isEmpty()) {
                        Vacio(Icons.Rounded.NotificationsNone, L("No hay avisos"), L("Cuando haya algo importante saldrá aquí."))
                    } else {
                        FormSection(
                            if (e.sinConexion) L("Sin conexión") else null,
                            footer = if (e.sinConexion) L("Estos son los últimos avisos guardados.") else null,
                        ) {
                            e.avisos.forEachIndexed { i, aviso -> AvisoRow(aviso, last = i == e.avisos.lastIndex) }
                        }
                    }
            }
        }
    }
}

@Composable
private fun AvisoRow(aviso: Aviso, last: Boolean) {
    val c = Libre.colors
    val uri = LocalUriHandler.current
    // Respuestas del soporte sólo para ti (tickets): check al abrirse, bocadillo, confeti si se solucionó y una
    // línea de comandos si «estamos en ello». Lo eligió Toxbox.
    val personalIcon = when (aviso.personal) {
        "abierto" -> Icons.Rounded.CheckCircle
        "mensaje" -> Icons.Rounded.ChatBubble
        "fiesta" -> Icons.Rounded.Celebration
        "en-ello" -> Icons.Rounded.Terminal
        else -> null
    }
    val color = when {
        aviso.personal == "fiesta" -> c.green
        personalIcon != null || aviso.importante -> c.accent
        else -> c.secondaryLabel
    }
    FormCustomRow {
        Column(Modifier.fillMaxWidth()) {
            Row(Modifier.fillMaxWidth().padding(16.dp, 14.dp)) {
                Box(
                    Modifier.size(40.dp).background(color.copy(alpha = if (aviso.importante) 0.16f else 0.12f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        personalIcon ?: if (aviso.importante) Icons.Rounded.NotificationImportant else Icons.Rounded.Campaign,
                        null, tint = color, modifier = Modifier.size(22.dp),
                    )
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            when {
                                aviso.personal != null -> L("Sólo para ti") + (aviso.ticket?.let { L(" · ticket #{0}", it) } ?: "")
                                aviso.importante -> L("Importante")
                                else -> L("Aviso")
                            },
                            style = Typo.footnote, fontWeight = FontWeight.SemiBold, color = color, modifier = Modifier.weight(1f),
                        )
                        Text(haceCuanto(aviso.fecha), style = Typo.footnote, color = c.secondaryLabel)
                    }
                    Spacer(Modifier.height(2.dp))
                    Text(aviso.titulo, style = Typo.headline, color = c.label)
                    if (aviso.texto.isNotBlank()) {
                        Spacer(Modifier.height(3.dp))
                        Text(aviso.texto, style = Typo.subheadline, color = c.secondaryLabel)
                    }
                    aviso.enlace?.let { enlace ->
                        Row(
                            Modifier.padding(top = 8.dp).tactile(label = L("Abrir enlace")) { runCatching { uri.openUri(enlace) } },
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(L("Abrir enlace"), style = Typo.subheadline, fontWeight = FontWeight.SemiBold, color = c.accent)
                            Icon(Icons.AutoMirrored.Rounded.OpenInNew, null, tint = c.accent, modifier = Modifier.size(15.dp))
                        }
                    }
                }
            }
            if (!last) Box(Modifier.fillMaxWidth().padding(start = 68.dp).height(0.5.dp).background(c.separator))
        }
    }
}

@Composable
private fun Vacio(icon: ImageVector, titulo: String, texto: String, accion: (@Composable () -> Unit)? = null) {
    val c = Libre.colors
    Column(Modifier.fillMaxWidth().padding(top = 56.dp, start = 32.dp, end = 32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, null, tint = c.tertiaryLabel, modifier = Modifier.size(40.dp))
        Spacer(Modifier.height(12.dp))
        Text(titulo, style = Typo.headline, color = c.label, textAlign = TextAlign.Center)
        Spacer(Modifier.height(4.dp))
        Text(texto, style = Typo.subheadline, color = c.secondaryLabel, textAlign = TextAlign.Center)
        if (accion != null) {
            Spacer(Modifier.height(16.dp))
            accion()
        }
    }
}

private val formatoFecha = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.forLanguageTag("es-ES"))

/** Igual que la web: «ahora mismo», «hace 5 min», «hace 3 h», «ayer», «hace 3 días» o la fecha. */
fun haceCuanto(fecha: Instant, ahora: Instant = Instant.now()): String {
    val seg = Duration.between(fecha, ahora).seconds.coerceAtLeast(0)
    if (seg < 60) return L("ahora mismo")
    val min = Math.round(seg / 60.0)
    if (min < 60) return L("hace {0} min", min)
    val h = Math.round(min / 60.0)
    if (h < 24) return L("hace {0} h", h)
    val d = Math.round(h / 24.0)
    if (d < 7) return if (d == 1L) L("ayer") else L("hace {0} días", d)
    return formatoFecha.format(fecha.atZone(ZoneId.systemDefault()))
}
