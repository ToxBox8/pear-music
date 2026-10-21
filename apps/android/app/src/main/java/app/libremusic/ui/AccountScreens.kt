package app.libremusic.ui


import app.libremusic.L
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CloudDownload
import androidx.compose.material.icons.rounded.CloudUpload
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.Logout
import androidx.compose.material.icons.rounded.PersonRemove
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.PhoneIphone
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.ui.draw.clip
import app.libremusic.ui.theme.themeSurface
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.libremusic.data.Account
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/**
 * Ajustes › Cuenta (opcional). Entrar con un código al correo; la biblioteca se guarda en la nube cifrada con la
 * clave de recuperación, que sólo tiene el usuario. Mismos pasos y textos que `AccountView` en iOS.
 */
@Composable
fun AccountScreen() {
    val state by Account.state.collectAsState()
    SettingsPage(L("Cuenta")) {
        when {
            state.email == null -> AccountSignIn()
            !state.hasKey -> AccountKeyStep(state.cloudHasLibrary)
            else -> AccountSignedIn(state)
        }
    }
}

private enum class Step { Email, Code }

@Composable
private fun AccountSignIn() {
    val c = Libre.colors
    val env = LocalEnv.current
    val scope = rememberCoroutineScope()
    var available by remember { mutableStateOf<Boolean?>(null) }
    var step by remember { mutableStateOf(Step.Email) }
    var email by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { available = Account.available() }

    AccountPitch(Modifier.padding(top = 18.dp))
    FormSection(null) {
        when (available) {
            null -> FormRow(L("Comprobando…"), tint = c.secondaryLabel, last = true)
            false -> FormRow(L("Las cuentas estarán disponibles muy pronto"), subtitle = L("Mientras tanto, todo funciona sin cuenta."), tint = c.secondaryLabel, last = true)
            true -> if (step == Step.Email) {
                FormTextField(email, { email = it; error = null }, "tu@correo.com", KeyboardOptions(keyboardType = KeyboardType.Email))
            } else {
                FormTextField(code, { code = it.filter(Char::isDigit).take(6); error = null }, L("Código de 6 cifras"), KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
            }
        }
    }
    if (available == true) {
        error?.let { Text(it, style = Typo.footnote, color = c.destructive, modifier = Modifier.padding(horizontal = 32.dp, vertical = 8.dp)) }
        FormSection(null, footer = if (step == Step.Code) L("Te lo hemos mandado a {0}. Caduca en 10 minutos.", email) else null) {
            if (step == Step.Email) {
                FormRow(L("Mandarme un código"), tint = c.accent, enabled = !busy && email.contains('@'), last = true) {
                    busy = true
                    scope.launch {
                        runCatching { Account.requestCode(email) }
                            .onSuccess { step = Step.Code }
                            .onFailure { error = it.message }
                        busy = false
                    }
                }
            } else {
                FormRow(L("Entrar"), tint = c.accent, enabled = !busy && code.length == 6) {
                    busy = true
                    scope.launch {
                        runCatching { Account.signIn(email, code) }
                            .onSuccess { hadLibrary -> env.app.toast = if (hadLibrary) L("Escribe tu clave de recuperación") else L("Cuenta creada") }
                            .onFailure { error = it.message }
                        busy = false
                    }
                }
                FormRow(L("Cambiar el correo"), tint = c.accent, last = true) { step = Step.Email; code = "" }
            }
        }
    }
}

/** Tras entrar: cuenta nueva → se crea y enseña la clave; cuenta con biblioteca → se escribe la clave. */
@Composable
private fun AccountKeyStep(cloudHasLibrary: Boolean) {
    val c = Libre.colors
    val env = LocalEnv.current
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    val fresh = remember { Account.newRecoveryKey() }
    // Si la cuenta ya tiene una copia en la nube, lo normal es escribir la clave de entonces.
    var typing by remember { mutableStateOf(cloudHasLibrary) }
    var fromScratch by remember { mutableStateOf(false) }
    var typed by remember { mutableStateOf("") }
    var saved by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    if (!typing) {
        FormSection(
            L("Tu clave de recuperación"),
            footer = L("Guárdala en tu gestor de contraseñas o apúntala. Es lo que cifra tu biblioteca: sin ella no se puede ") +
                L("recuperar la copia de la nube en otro móvil. Pear Music no la guarda y no la puede recuperar."),
        ) {
            SelectionContainer {
                Text(
                    fresh, style = Typo.title3, fontFamily = FontFamily.Monospace, color = c.label, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(16.dp, 18.dp),
                )
            }
            FormRow(L("Copiar"), icon = Icons.Rounded.ContentCopy, tint = c.accent) {
                clipboard.setText(AnnotatedString(fresh))
                env.app.toast = L("Clave copiada")
            }
            FormRow(L("La he guardado"), checked = saved, last = true) { saved = !saved }
        }
        FormSection(null) {
            FormRow(L("Continuar"), tint = c.accent, enabled = saved && !busy) {
                busy = true
                Account.setRecoveryKey(fresh)
                scope.launch {
                    runCatching { Account.upload(env.library.library, overwrite = fromScratch || !cloudHasLibrary) }
                        .onSuccess { env.app.toast = L("Biblioteca guardada en la nube") }
                        .onFailure { env.app.toast = it.message }
                    busy = false
                }
            }
            FormRow(L("Ya tengo una clave (de otro móvil)"), tint = c.accent, last = true) { typing = true }
        }
    } else {
        FormSection(L("Escribe tu clave de recuperación"), footer = L("La que guardaste al crear la cuenta. 26 letras y números; da igual mayúsculas o guiones.")) {
            FormTextField(typed, { typed = it; error = null }, "XXXX-XXXX-XXXX-…", KeyboardOptions(keyboardType = KeyboardType.Ascii), mono = true)
        }
        error?.let { Text(it, style = Typo.footnote, color = c.destructive, modifier = Modifier.padding(horizontal = 32.dp, vertical = 8.dp)) }
        FormSection(null) {
            FormRow(L("Traer mi biblioteca"), tint = c.accent, enabled = !busy && typed.isNotBlank()) {
                val key = Account.normalizeKey(typed) ?: run { error = L("Esa clave no tiene el formato correcto."); return@FormRow }
                busy = true
                Account.setRecoveryKey(key)
                scope.launch {
                    runCatching { Account.download(env.library.library) }
                        .onSuccess { (fav, lists) -> env.app.toast = L("Traídas {0} favoritas y {1} playlists", fav, lists) }
                        .onFailure {
                            error = it.message
                            Account.setRecoveryKeyCleared()
                        }
                    busy = false
                }
            }
            FormRow(L("No tengo la clave: empezar de cero"), tint = c.destructive, last = true) {
                env.app.alert = AlertSpec(
                    L("¿Empezar de cero?"), L("Se borrará la copia de la nube que no puedes abrir y se creará una clave nueva. La biblioteca de este móvil no se toca."),
                    buttons = listOf(
                        AlertButton(L("Empezar de cero"), AlertButton.Role.Destructive) { fromScratch = true; typing = false },
                        AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
                    ),
                )
            }
        }
    }
}

@Composable
private fun AccountSignedIn(state: Account.State) {
    val c = Libre.colors
    val env = LocalEnv.current
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    var busy by remember { mutableStateOf(false) }
    val last = if (state.lastSync > 0) DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(state.lastSync)) else L("Nunca")

    FormSection(null, footer = L("Tu biblioteca viaja cifrada con tu clave de recuperación: el servidor no puede leerla.")) {
        FormRow(L("Correo"), value = state.email)
        FormRow(L("Última copia en la nube"), value = last, last = true)
    }
    FormSection(null) {
        FormRow(L("Guardar ahora en la nube"), icon = Icons.Rounded.CloudUpload, tint = c.accent, enabled = !busy) {
            busy = true
            scope.launch {
                runCatching { Account.upload(env.library.library) }.onSuccess { env.app.toast = L("Biblioteca guardada") }.onFailure { env.app.toast = it.message }
                busy = false
            }
        }
        FormRow(L("Traer de la nube"), subtitle = L("Une la copia con lo de este móvil, sin borrar nada"), icon = Icons.Rounded.CloudDownload, tint = c.accent, enabled = !busy) {
            busy = true
            scope.launch {
                runCatching { Account.download(env.library.library) }
                    .onSuccess { (fav, lists) -> env.app.toast = L("Traídas {0} favoritas y {1} playlists", fav, lists) }
                    .onFailure { env.app.toast = it.message }
                busy = false
            }
        }
        FormRow(L("Ver clave de recuperación"), icon = Icons.Rounded.Key, tint = c.accent, last = true) {
            val key = Account.recoveryKey().orEmpty()
            env.app.alert = AlertSpec(
                L("Clave de recuperación"), key,
                buttons = listOf(
                    AlertButton(L("Copiar")) { clipboard.setText(AnnotatedString(key)); env.app.toast = L("Clave copiada") },
                    AlertButton(L("Cerrar"), AlertButton.Role.Cancel),
                ),
            )
        }
    }
    FormSection(null, footer = L("Borrar la cuenta elimina al momento tu correo y la copia de la nube. La biblioteca de este móvil se queda.")) {
        FormRow(L("Cerrar sesión"), icon = Icons.Rounded.Logout, tint = c.accent, enabled = !busy) {
            scope.launch { Account.signOut(); env.app.toast = L("Sesión cerrada") }
        }
        FormRow(L("Borrar la cuenta"), icon = Icons.Rounded.PersonRemove, tint = c.destructive, enabled = !busy, last = true) {
            env.app.alert = AlertSpec(
                L("¿Borrar tu cuenta?"), L("Se borran tu correo y la copia de la nube. No se puede deshacer."),
                buttons = listOf(
                    AlertButton(L("Borrar la cuenta"), AlertButton.Role.Destructive) {
                        scope.launch {
                            runCatching { Account.delete() }.onSuccess { env.app.toast = L("Cuenta borrada") }.onFailure { env.app.toast = it.message }
                        }
                    },
                    AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
                ),
            )
        }
    }
}

/**
 * Por qué crear una cuenta: opcional, ayuda a mejorar la app y pronto tendrá ventajas (lo pidió Toxbox). Se usa
 * en Ajustes › Cuenta y en la guía inicial. Mismo texto que `AccountPitch` en iOS.
 */
@Composable
fun AccountPitch(modifier: Modifier = Modifier, inset: androidx.compose.ui.unit.Dp = 16.dp) {
    val c = Libre.colors
    androidx.compose.foundation.layout.Column(
        modifier.fillMaxWidth().padding(horizontal = inset)
            .then(Modifier.themeSurface(app.libremusic.ui.theme.Tokens.Radius.Card.dp * 1.5f, c))
            .padding(horizontal = 20.dp, vertical = 22.dp),
    ) {
        androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.foundation.Image(
                androidx.compose.ui.res.painterResource(app.libremusic.R.drawable.logo), null,
                Modifier.size(52.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(13.dp)),
            )
            androidx.compose.foundation.layout.Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(L("Tu cuenta de Pear Music"), style = Typo.title3.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = c.label)
                Text(
                    L("Opcional · gratis"), style = Typo.caption.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = c.accent,
                    modifier = Modifier.padding(top = 4.dp).background(c.accent.copy(alpha = 0.12f), androidx.compose.foundation.shape.RoundedCornerShape(50))
                        .padding(horizontal = 10.dp, vertical = 3.dp),
                )
            }
        }
        Text(
            L("No la necesitas para nada: Pear Music funciona igual sin ella. Pero si te la creas nos ayudas muchísimo a mejorar la app, y tú te llevas tu música allá donde vayas."),
            style = Typo.callout, color = c.secondaryLabel, modifier = Modifier.padding(top = 14.dp, bottom = 6.dp),
        )
        PitchPoint(Icons.Rounded.Lock, 5, L("Tu biblioteca, cifrada en la nube"), L("Sólo tú tienes la clave. Ni siquiera nosotros podemos leerla."))
        PitchPoint(Icons.Rounded.PhoneIphone, 2, L("Pásala a otro móvil"), L("Playlists y favoritos en un minuto, también entre iPhone y Android."))
        PitchPoint(Icons.Rounded.Favorite, 0, L("Ayudas a mejorar Pear Music"), L("Saber cuántos sois nos dice dónde poner el esfuerzo."))
        PitchPoint(Icons.Rounded.AutoAwesome, 4, L("Muy pronto, ventajas"), L("Estamos preparando cosas solo para quien tenga cuenta. Te avisaremos en Avisos."))
    }
}

@Composable
private fun PitchPoint(icon: androidx.compose.ui.graphics.vector.ImageVector, palette: Int, title: String, text: String) {
    val c = Libre.colors
    androidx.compose.foundation.layout.Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.Top) {
        GradientIcon(icon, palette, 30.dp)
        androidx.compose.foundation.layout.Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = Typo.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = c.label)
            Text(text, style = Typo.footnote, color = c.secondaryLabel)
        }
    }
}
