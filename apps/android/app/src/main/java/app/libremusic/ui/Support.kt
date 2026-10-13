package app.libremusic.ui

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
fun SupportScreen(draftId: String?) {
    val c = Libre.colors
    val env = LocalEnv.current
    val context = LocalContext.current
    val store = remember { SupportStore.get(context) }
    val drafts by store.drafts.collectAsState()
    val initial = remember(draftId) { drafts.firstOrNull { it.id == draftId } ?: SupportDraft() }
    var email by remember(draftId) { mutableStateOf(initial.email) }
    var text by remember(draftId) { mutableStateOf(initial.text) }
    var photos by remember(draftId) { mutableStateOf(initial.photos) }
    var emailTouched by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var sent by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val draft = SupportDraft(initial.id, email, text, photos)
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
            if (added.size < uris.take(room).size) env.app.toast = "Alguna foto no se pudo añadir"
            photos = photos + added
        }
    }

    fun send() {
        if (sending) return
        sending = true
        scope.launch {
            val error = SupportClient.send(context, current, BuildConfig.VERSION_NAME)
            sending = false
            if (error == null) {
                sent = true
                store.delete(initial.id)
                env.app.toast = "Reporte enviado. ¡Gracias!"
                env.app.pop()
            } else {
                store.save(current)
                env.app.alert = AlertSpec(
                    "No se pudo enviar", "$error\n\nLo hemos guardado en Borradores para que lo envíes más tarde.",
                    buttons = listOf(AlertButton("Vale", AlertButton.Role.Cancel)),
                )
            }
        }
    }

    SettingsPage("Informar de un error") {
        val others = drafts.count { it.id != initial.id }
        if (others > 0) {
            FormSection(null) {
                FormRow("Borradores", "$others", icon = Icons.Rounded.EditNote, tint = c.accent, chevron = true, last = true) {
                    env.app.push(Route.SupportDrafts)
                }
            }
        }
        FormSection("Tu correo", footer = if (emailTouched && email.isNotBlank() && !emailOk) "Revisa el correo: falta algo (por ejemplo, la @ o el dominio)." else "Para poder contestarte. No se usa para nada más.") {
            FormCustomRow {
                SupportField(email, { email = it; emailTouched = true }, "nombre@correo.com", singleLine = true, keyboard = KeyboardType.Email)
            }
        }
        FormSection("Qué ha pasado", footer = "Cuenta qué hacías y qué esperabas que pasara. Cuanto más concreto, mejor (mínimo ${SupportLimits.MIN_TEXT} caracteres).") {
            FormCustomRow {
                SupportField(text, { if (it.length <= SupportLimits.MAX_TEXT) text = it }, "Por ejemplo: al pulsar «Descargar todo» en un álbum, la app se cierra.", minHeight = 140)
            }
        }
        FormSection("Capturas", footer = "Hasta ${SupportLimits.MAX_PHOTOS}. Se reducen y se les quitan la ubicación y los demás datos de la foto antes de enviarlas.") {
            FormCustomRow {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    photos.forEach { path ->
                        Box(Modifier.size(84.dp)) {
                            AsyncImage(File(path), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
                            Box(
                                Modifier.align(Alignment.TopEnd).size(44.dp).tactile(label = "Quitar foto") {
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
                                .tactile(label = "Añadir capturas") { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                            contentAlignment = Alignment.Center,
                        ) { Icon(Icons.Rounded.AddPhotoAlternate, null, tint = c.accent, modifier = Modifier.size(28.dp)) }
                    }
                }
            }
        }
        Box(Modifier.padding(horizontal = 16.dp, vertical = 22.dp)) {
            PillButton(
                if (sending) "Enviando…" else "Enviar", null, prominent = true, modifier = Modifier.fillMaxWidth(), enabled = canSend,
                leading = if (sending) ({ Spinner(16.dp, c.onAccent) }) else null,
            ) {
                env.app.alert = AlertSpec(
                    "¿Enviar el reporte?",
                    "Se enviarán tu correo, el texto${if (photos.isEmpty()) "" else ", ${photos.size} ${if (photos.size == 1) "foto" else "fotos"}"} y datos del móvil (modelo, versión de Android y de la app) al canal privado de soporte de Pear Music.",
                    buttons = listOf(
                        AlertButton("Enviar") { send() },
                        AlertButton("Cancelar", AlertButton.Role.Cancel),
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
    SettingsPage("Borradores") {
        if (drafts.isEmpty()) {
            CenterNote("No hay borradores", 60.dp)
        } else {
            FormSection(null, footer = "Se guardan en este móvil hasta que los envías o los eliminas.") {
                drafts.forEachIndexed { i, d ->
                    FormRow(
                        d.text.trim().lineSequence().firstOrNull()?.take(60)?.ifEmpty { null } ?: "Sin descripción",
                        subtitle = listOfNotNull(fmt.format(Date(d.updated)), d.photos.size.takeIf { it > 0 }?.let { "$it ${if (it == 1) "foto" else "fotos"}" }).joinToString(" · "),
                        last = i == drafts.lastIndex,
                        trailing = {
                            IconTap(Icons.Rounded.Delete, "Eliminar borrador", tint = c.destructive) {
                                env.app.alert = AlertSpec(
                                    "¿Eliminar el borrador?", "Se borran el texto y sus fotos. No se puede deshacer.",
                                    buttons = listOf(
                                        AlertButton("Eliminar", AlertButton.Role.Destructive) { store.delete(d.id) },
                                        AlertButton("Cancelar", AlertButton.Role.Cancel),
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
