package app.libremusic.ui


import app.libremusic.L
import app.libremusic.data.SupportFilter

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AddPhotoAlternate
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.libremusic.BuildConfig
import app.libremusic.data.SupportClient
import app.libremusic.data.SupportDraft
import app.libremusic.data.SupportLimits
import app.libremusic.data.SupportStore
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo
import coil.compose.AsyncImage
import kotlinx.coroutines.launch
import java.io.File
import java.text.DateFormat
import java.util.Date

/**
 * «Informar de un error» (Fase 4C): correo, descripción y hasta 4 capturas. Se guarda solo como borrador al
 * salir; enviar pide confirmación de privacidad, evita el doble envío y, si falla, lo deja en Borradores.
 * Mismo aspecto y textos que `SupportView` en iOS.
 */
@Composable
fun SupportScreen(draftId: String?, suggestion: Boolean = false) {
    val c = Libre.colors
    val env = LocalEnv.current
    val context = LocalContext.current
    val store = remember { SupportStore.get(context) }
    val drafts by store.drafts.collectAsState()
    val kind = if (suggestion) "sugerencia" else "error"
    val initial = remember(draftId) { drafts.firstOrNull { it.id == draftId } ?: SupportDraft(kind = kind) }
    var email by remember(draftId) { mutableStateOf(initial.email) }
    var text by remember(draftId) { mutableStateOf(initial.text) }
    var photos by remember(draftId) { mutableStateOf(initial.photos) }
    var emailTouched by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var sent by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val draft = SupportDraft(initial.id, email, text, photos, kind = initial.kind)
    val current by rememberUpdatedState(draft)
    val emailOk = SupportLimits.validEmail(email)
    val canSend = emailOk && SupportLimits.validText(text) && !sending

    // Al salir de la pantalla, lo escrito queda como borrador (salvo si se ha enviado).
    DisposableEffect(initial.id) { onDispose { if (!sent) store.save(current) } }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(SupportLimits.MAX_PHOTOS)) { uris ->
        val room = SupportLimits.MAX_PHOTOS - photos.size
        if (uris.isEmpty() || room <= 0) return@rememberLauncherForActivityResult
        scope.launch {
            val dir = store.photoDir(initial.id)
            val added = uris.take(room).mapNotNull { SupportClient.importPhoto(context, it, dir)?.path }
            if (added.size < uris.take(room).size) env.app.toast = L("Alguna foto no se pudo añadir")
            photos = photos + added
        }
    }

    fun appeal(denialId: String) {
        env.app.alert = AlertSpec(
            L("Apelar"), L("Explica por qué es un reporte de verdad. Lo leerá una persona y te contestará al correo."),
            field = L("Por qué es un reporte de verdad"),
            buttons = listOf(
                AlertButton(L("Enviar apelación")) { why ->
                    scope.launch {
                        val error = SupportClient.appeal(context, denialId, current.email, why)
                        env.app.toast = error ?: L("Apelación enviada. Te contestaremos al correo.")
                    }
                },
                AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
            ),
        )
    }

    fun send() {
        if (sending) return
        // Primera capa: las mismas reglas que el servidor, sin gastar el envío.
        SupportFilter.problem(current.text)?.let { problem ->
            env.app.alert = AlertSpec(L("Revisa el mensaje"), problem, buttons = listOf(AlertButton(L("Reformular"), AlertButton.Role.Cancel)))
            return
        }
        sending = true
        scope.launch {
            val result = SupportClient.send(context, current, BuildConfig.VERSION_NAME)
            sending = false
            if (result.error == null) {
                sent = true
                store.delete(initial.id)
                env.app.toast = (if (suggestion) L("Sugerencia enviada") else L("Reporte enviado")) +
                    (result.ticket?.let { L(" (ticket #{0}). Te contestaremos en Avisos.", it) } ?: L(". ¡Gracias!"))
                env.app.pop()
            } else if (result.denialId != null) {
                // Rechazado por el contenido: se puede reformular (sigue en el formulario) o apelar.
                store.save(current)
                env.app.alert = AlertSpec(
                    L("No se pudo enviar"), L("{0}\n\nPuedes reformularlo o, si crees que es un error, apelar.", result.error),
                    buttons = listOf(
                        AlertButton(L("Reformular"), AlertButton.Role.Cancel),
                        AlertButton(L("Apelar")) { appeal(result.denialId) },
                    ),
                )
            } else {
                store.save(current)
                env.app.alert = AlertSpec(
                    L("No se pudo enviar"), L("{0}\n\nLo hemos guardado en Borradores para que lo envíes más tarde.", result.error),
                    buttons = listOf(AlertButton(L("Vale"), AlertButton.Role.Cancel)),
                )
            }
        }
    }

    SettingsPage(if (suggestion) L("Buzón de sugerencias") else L("Informar de un error")) {
        val others = drafts.count { it.id != initial.id }
        if (others > 0) {
            FormSection(null) {
                FormRow(L("Borradores"), "$others", icon = Icons.Rounded.EditNote, tint = c.accent, chevron = true, last = true) {
                    env.app.push(Route.SupportDrafts)
                }
            }
        }
        FormSection(L("Tu correo"), footer = if (emailTouched && email.isNotBlank() && !emailOk) L("Revisa el correo: falta algo (por ejemplo, la @ o el dominio).") else L("Para poder contestarte. No se usa para nada más. La respuesta también te llega a Avisos, sólo a ti.")) {
            FormCustomRow {
                SupportField(email, { email = it; emailTouched = true }, "nombre@correo.com", singleLine = true, keyboard = KeyboardType.Email)
            }
        }
        FormSection(
            if (suggestion) L("Tu idea") else L("Qué ha pasado"),
            footer = if (suggestion) L("Qué te gustaría que hiciera Pear Music y para qué te serviría (mínimo {0} caracteres).", SupportLimits.MIN_TEXT)
            else L("Cuenta qué hacías y qué esperabas que pasara. Cuanto más concreto, mejor (mínimo {0} caracteres).", SupportLimits.MIN_TEXT),
        ) {
            FormCustomRow {
                SupportField(
                    text, { if (it.length <= SupportLimits.MAX_TEXT) text = it },
                    if (suggestion) L("Por ejemplo: poder ordenar mis playlists por artista.") else L("Por ejemplo: al pulsar «Descargar todo» en un álbum, la app se cierra."),
                    minHeight = 140,
                )
            }
        }
        FormSection(L("Capturas"), footer = L("Hasta {0}. Se reducen y se les quitan la ubicación y los demás datos de la foto antes de enviarlas.", SupportLimits.MAX_PHOTOS)) {
            FormCustomRow {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    photos.forEach { path ->
                        Box(Modifier.size(84.dp)) {
                            AsyncImage(File(path), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
                            Box(
                                Modifier.align(Alignment.TopEnd).size(44.dp).tactile(label = L("Quitar foto")) {
                                    photos = photos - path
                                    File(path).delete()
                                },
                                contentAlignment = Alignment.TopEnd,
                            ) {
                                Box(Modifier.padding(4.dp).size(22.dp).background(c.label.copy(alpha = 0.7f), CircleShape), contentAlignment = Alignment.Center) {
                                    Icon(Icons.Rounded.Close, null, tint = c.background, modifier = Modifier.size(14.dp))
                                }
                            }
                        }
                    }
                    if (photos.size < SupportLimits.MAX_PHOTOS) {
                        Box(
                            Modifier.size(84.dp).clip(RoundedCornerShape(12.dp)).border(1.dp, c.separator, RoundedCornerShape(12.dp))
                                .tactile(label = L("Añadir capturas")) { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                            contentAlignment = Alignment.Center,
                        ) { Icon(Icons.Rounded.AddPhotoAlternate, null, tint = c.accent, modifier = Modifier.size(28.dp)) }
                    }
                }
            }
        }
        Box(Modifier.padding(horizontal = 16.dp, vertical = 22.dp)) {
            PillButton(
                if (sending) "Enviando…" else L("Enviar"), null, prominent = true, modifier = Modifier.fillMaxWidth(), enabled = canSend,
                leading = if (sending) ({ Spinner(16.dp, c.onAccent) }) else null,
            ) {
                env.app.alert = AlertSpec(
                    if (suggestion) L("¿Enviar la sugerencia?") else L("¿Enviar el reporte?"),
                    if (photos.isEmpty()) L("Se enviarán tu correo, el texto y la ficha de este móvil (modelo, versión de Android y de la app y, si tienes la telemetría activada, su rendimiento) al soporte privado de Pear Music.")
                    else L("Se enviarán tu correo, el texto, {0} foto(s) y la ficha de este móvil (modelo, versión de Android y de la app y, si tienes la telemetría activada, su rendimiento) al soporte privado de Pear Music.", photos.size),
                    buttons = listOf(
                        AlertButton(L("Enviar")) { send() },
                        AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
                    ),
                )
            }
        }
    }
}

@Composable
private fun SupportField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    singleLine: Boolean = false,
    minHeight: Int = 52,
    keyboard: KeyboardType = KeyboardType.Text,
) {
    val c = Libre.colors
    Box(Modifier.fillMaxWidth().heightIn(min = minHeight.dp).padding(horizontal = 16.dp, vertical = 14.dp)) {
        if (value.isEmpty()) Text(placeholder, style = Typo.body, color = c.tertiaryLabel)
        BasicTextField(
            value, onChange, singleLine = singleLine, textStyle = Typo.body.copy(color = c.label), cursorBrush = SolidColor(c.accent),
            keyboardOptions = KeyboardOptions(keyboardType = keyboard), modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Reportes guardados: abrir para seguir o enviar, o eliminarlos. */
@Composable
fun SupportDraftsScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val context = LocalContext.current
    val store = remember { SupportStore.get(context) }
    val drafts by store.drafts.collectAsState()
    val fmt = remember { DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT) }
    SettingsPage(L("Borradores")) {
        if (drafts.isEmpty()) {
            CenterNote(L("No hay borradores"), 60.dp)
        } else {
            FormSection(null, footer = L("Se guardan en este móvil hasta que los envías o los eliminas.")) {
                drafts.forEachIndexed { i, d ->
                    FormRow(
                        d.text.trim().lineSequence().firstOrNull()?.take(60)?.ifEmpty { null } ?: L("Sin descripción"),
                        subtitle = listOfNotNull(fmt.format(Date(d.updated)), d.photos.size.takeIf { it > 0 }?.let { "$it ${if (it == 1) "foto" else "fotos"}" }).joinToString(" · "),
                        last = i == drafts.lastIndex,
                        trailing = {
                            IconTap(Icons.Rounded.Delete, L("Eliminar borrador"), tint = c.destructive) {
                                env.app.alert = AlertSpec(
                                    L("¿Eliminar el borrador?"), L("Se borran el texto y sus fotos. No se puede deshacer."),
                                    buttons = listOf(
                                        AlertButton(L("Eliminar"), AlertButton.Role.Destructive) { store.delete(d.id) },
                                        AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
                                    ),
                                )
                            }
                        },
                    ) { env.app.push(Route.Support(d.id)) }
                }
            }
        }
    }
}
