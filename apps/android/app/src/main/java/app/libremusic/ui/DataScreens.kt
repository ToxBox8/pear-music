package app.libremusic.ui


import app.libremusic.L
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.DeleteForever
import androidx.compose.material.icons.rounded.DeleteSweep
import androidx.compose.material.icons.rounded.IosShare
import androidx.compose.material.icons.rounded.Report
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Usb
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import app.libremusic.BuildConfig
import app.libremusic.data.Logs
import app.libremusic.data.UserData
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.Typo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

/** Ajustes › Ayuda y soporte › Tus datos: exportar y borrar todo lo que la app guarda (RGPD). Igual en iOS. */
@Composable
fun MyDataScreen() {
    val env = LocalEnv.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        busy = true
        scope.launch {
            val ok = withContext(Dispatchers.IO) { runCatching { UserData.export(context, uri) }.isSuccess }
            busy = false
            env.app.toast = if (ok) L("Datos exportados") else L("No se pudieron exportar los datos")
        }
    }
    var telemetry by remember { mutableStateOf(app.libremusic.data.Telemetry.enabled(context)) }
    SettingsPage(L("Tus datos")) {
        FormSection(
            null,
            footer = L("Si la activas, una vez a la semana se envía un resumen de rendimiento: modelo y sistema, versión, cuánto ") +
                L("tarda en abrir, fluidez (FPS y tirones), memoria y minutos de uso, con un identificador aleatorio que no es ") +
                L("el de tu cuenta. Nada de lo que escuchas ni buscas. Se borra a los 90 días; al apagarla se borra al momento."),
        ) {
            FormRow(L("Telemetría de rendimiento"), subtitle = if (telemetry) L("Activada") else L("Desactivada"), icon = Icons.Rounded.Speed, iconPalette = 3, last = true, trailing = {
                IosToggle(telemetry, onChange = { on ->
                    app.libremusic.data.Telemetry.setConsent(context, on)
                    telemetry = on
                }, label = L("Telemetría de rendimiento"))
            })
        }
        FormSection(
            null,
            footer = L("Pear Music no tiene cuentas ni servidor con tus datos: todo está en este móvil. ") +
                L("El archivo lleva tu biblioteca, estadísticas, letras, borradores de soporte y ajustes; no las canciones descargadas."),
        ) {
            FormRow(
                L("Exportar mis datos"), subtitle = L("Un archivo .zip con todo lo que la app guarda de ti"),
                icon = Icons.Rounded.IosShare, iconPalette = 2, enabled = !busy, last = true,
            ) { export.launch("pear-music-datos-${LocalDate.now()}.zip") }
        }
        FormSection(null, footer = L("Borra la biblioteca, las descargas, las estadísticas y los ajustes, y cierra la app. No se puede deshacer.")) {
            FormRow(L("Borrar todos mis datos"), icon = Icons.Rounded.DeleteForever, tint = Libre.colors.destructive, last = true) {
                env.app.alert = AlertSpec(
                    L("¿Borrar todos tus datos?"),
                    L("Se borrarán tus playlists, favoritos, descargas, estadísticas y ajustes de este móvil, y la app se cerrará. ") +
                        L("Si quieres conservar algo, exporta antes tus datos."),
                    buttons = listOf(
                        AlertButton(L("Borrar todo"), AlertButton.Role.Destructive) { UserData.eraseAll(context) },
                        AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
                    ),
                )
            }
        }
    }
}

/** Ajustes › Ayuda y soporte › Administración: sólo existe en la variante dev (`BuildConfig.ADMIN_TOOLS`). */
@Composable
fun AdminScreen() {
    if (!BuildConfig.ADMIN_TOOLS) return
    val c = Libre.colors
    val env = LocalEnv.current
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    var lines by remember { mutableStateOf(Logs.recent()) }
    SettingsPage(L("Administración")) {
        FormSection(L("Esta app")) {
            FormRow(L("Canal"), value = BuildConfig.CHANNEL)
            FormRow(L("Versión"), value = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            FormRow(L("Paquete"), value = context.packageName, last = true)
        }
        FormSection(L("Registro"), footer = L("Las últimas {0} líneas, sólo en memoria. Nunca llevan datos personales.", lines.size)) {
            if (lines.isEmpty()) {
                FormRow(L("Sin líneas todavía"), tint = c.secondaryLabel)
            } else {
                SelectionContainer {
                    Column(Modifier.fillMaxWidth().padding(16.dp, 12.dp)) {
                        lines.takeLast(80).forEach { androidx.compose.material3.Text(it, style = Typo.caption, fontFamily = FontFamily.Monospace, color = c.label) }
                    }
                }
            }
            FormRow(L("Copiar registro"), icon = Icons.Rounded.ContentCopy, tint = c.accent, enabled = lines.isNotEmpty()) {
                clipboard.setText(AnnotatedString(lines.joinToString("\n")))
                env.app.toast = L("Registro copiado")
            }
            FormRow(L("Vaciar registro"), icon = Icons.Rounded.DeleteSweep, tint = c.accent, last = true) {
                Logs.clear()
                lines = Logs.recent()
            }
        }
        TelemetryAdmin()
        PanicPanel()
    }
}

/**
 * Telemetría en Pear Dev (Fase 4b): «Enviar ahora» con los campos elegidos y la llave del panel de la web por USB
 * (`PanelKey`). Lo pidió Toxbox.
 */
@Composable
private fun TelemetryAdmin() {
    val c = Libre.colors
    val env = LocalEnv.current
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var chosen by remember { mutableStateOf(app.libremusic.data.Telemetry.CHOOSABLE.map { it.first }.toSet()) }
    var busy by remember { mutableStateOf(false) }
    var keyOn by remember { mutableStateOf(app.libremusic.data.PanelKey.running) }
    FormSection(L("Telemetría"), footer = L("Manda ya el resumen de esta semana con los campos marcados (los obligatorios siempre van: identificador, plataforma, variante, versión y semana). El resumen semanal sigue saliendo solo si la telemetría está activada.")) {
        app.libremusic.data.Telemetry.CHOOSABLE.forEach { (key, label) ->
            FormRow(label, trailing = {
                IosToggle(key in chosen, onChange = { on -> chosen = if (on) chosen + key else chosen - key }, label = label)
            })
        }
        FormRow(L("Enviar ahora"), icon = Icons.AutoMirrored.Rounded.Send, iconPalette = 3, enabled = !busy, last = true) {
            busy = true
            scope.launch {
                val sent = app.libremusic.data.Telemetry.sendNow(context.applicationContext, chosen)
                busy = false
                env.app.toast = if (sent != null) L("Enviado ({0} campos)", sent.length()) else L("No se pudo enviar")
            }
        }
    }
    FormSection(
        "Panel de la web",
        footer = L("Con esto encendido y el móvil por cable (adb forward tcp:8765 tcp:8765), la página escondida de la web pide aquí una llave de 5 minutos. Sólo escucha dentro del móvil y se apaga sola a los 10 minutos. La clave pública va una vez en PANEL_PUBLIC_KEY del Worker."),
    ) {
        FormRow(L("Llave del panel por USB"), subtitle = if (keyOn) L("Encendida") else L("Apagada"), icon = Icons.Rounded.Usb, iconPalette = 2, trailing = {
            IosToggle(keyOn, onChange = { on ->
                scope.launch {
                    keyOn = withContext(Dispatchers.IO) {
                        if (on) runCatching { app.libremusic.data.PanelKey.start(context) } else app.libremusic.data.PanelKey.stop()
                        app.libremusic.data.PanelKey.running
                    }
                    if (on && !keyOn) env.app.toast = L("No se pudo abrir el puerto 8765")
                }
            }, label = L("Llave del panel por USB"))
        })
        FormRow(L("Copiar clave pública"), icon = Icons.Rounded.ContentCopy, tint = c.accent, last = true) {
            scope.launch {
                val key = withContext(Dispatchers.IO) { app.libremusic.data.PanelKey.publicKey(context) }
                clipboard.setText(AnnotatedString(key))
                env.app.toast = L("Clave pública copiada")
            }
        }
    }
}

/**
 * Botón de pánico remoto (Fase 4, sólo Pear Dev): publica un estado prefirmado en el PC (aviso, modo seguro,
 * bloqueo o normal) con contraseña y código TOTP. El bloqueo total se pide aquí y se confirma a los 10 minutos con
 * otro código. Runbook: docs/RUNBOOK-INCIDENTES.md.
 */
@Composable
private fun PanicPanel() {
    val c = Libre.colors
    val env = LocalEnv.current
    val scope = rememberCoroutineScope()
    var level by remember { mutableStateOf("2") }
    var password by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    fun send(path: String, extra: (org.json.JSONObject) -> Unit = {}) {
        busy = true
        scope.launch {
            val body = org.json.JSONObject().put("password", password).put("totp", code.trim()).also(extra)
            val (status, json) = app.libremusic.data.Panic.call(path, body)
            result = when {
                json.has("error") -> "❌ " + json.optString("error")
                json.optBoolean("pending") -> "⏳ Bloqueo pedido. Confírmalo a partir de ${json.optString("confirmAfter")} con un código nuevo."
                path == "/info" -> "Nivel publicado: ${json.optInt("level")} · cambios que quedan en el lote: ${json.optInt("left")} · lote hasta ${json.optLong("batchExpiresAt").let { if (it > 0) java.text.DateFormat.getDateInstance().format(java.util.Date(it * 1000)) else "—" }}" +
                    (json.optJSONObject("pending")?.let { "\nBloqueo pendiente desde ${java.util.Date(it.optLong("requestedAt"))}" } ?: "") +
                    "\n\n" + (0 until (json.optJSONArray("audit")?.length() ?: 0)).joinToString("\n") { i ->
                        json.getJSONArray("audit").getJSONObject(i).let { a -> "${a.optString("at").take(16)} · ${a.optString("action")} ${if (a.has("level")) a.optInt("level") else ""} · ${a.optString("via")}" }
                    }
                status in 200..299 -> "✅ Hecho. Quedan ${json.optInt("left")} cambios en el lote."
                else -> L("❌ Error {0}", status)
            }
            code = ""
            busy = false
        }
    }
    FormSection(
        L("Botón de pánico"),
        footer = L("Publica uno de los estados firmados en el PC. Aviso: banner que caduca solo. Modo seguro: apaga actualizaciones, búsqueda, soporte, telemetría y cuenta. Bloqueo: pantalla de mantenimiento; se confirma a los 10 min con otro código. Normal: todo vuelve a funcionar."),
    ) {
        Box(Modifier.padding(16.dp)) {
            Segmented(listOf("1" to L("Aviso"), "2" to L("Seguro"), "3" to L("Bloqueo"), "0" to L("Normal")), level) { level = it }
        }
        FormTextField(password, { password = it }, L("Contraseña"), androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Password))
        FormTextField(code, { code = it.filter(Char::isDigit).take(6) }, L("Código de 6 cifras"), androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.NumberPassword))
        val ready = !busy && password.length >= 8 && code.length == 6
        FormRow(if (level == "3") L("Pedir bloqueo total") else L("Publicar este nivel"), tint = c.destructive, enabled = ready) {
            env.app.alert = AlertSpec(
                "¿Publicar el nivel ${mapOf("0" to "Normal", "1" to "Aviso", "2" to "Modo seguro", "3" to "Bloqueo total")[level]}?",
                L("Afecta a todas las personas que usan Pear Music en cuanto abran la app."),
                buttons = listOf(AlertButton(L("Publicar"), AlertButton.Role.Destructive) { send("", { it.put("level", level.toInt()) }) }, AlertButton(L("Cancelar"), AlertButton.Role.Cancel)),
            )
        }
        FormRow(L("Confirmar bloqueo pendiente"), tint = c.destructive, enabled = ready) { send("/confirmar") }
        FormRow(L("Cancelar bloqueo pendiente"), tint = c.accent, enabled = ready) { send("/cancelar") }
        FormRow(L("Ver estado y auditoría"), tint = c.accent, enabled = ready, last = true) { send("/info") }
    }
    val shown = result
    if (shown != null) {
        androidx.compose.material3.Text(shown, style = Typo.footnote, color = c.label, modifier = Modifier.padding(horizontal = 32.dp, vertical = 8.dp))
    }
}
