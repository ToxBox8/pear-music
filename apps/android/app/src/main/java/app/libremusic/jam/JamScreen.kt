package app.libremusic.jam


import app.libremusic.L
import android.content.Context
import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.QrCode
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.libremusic.data.Song
import app.libremusic.data.YTClient
import app.libremusic.ui.AlertButton
import app.libremusic.ui.AlertSpec
import app.libremusic.ui.ContextMenu
import app.libremusic.ui.CoverImage
import app.libremusic.ui.LibraryViewModel
import app.libremusic.ui.LocalEnv
import app.libremusic.ui.MenuEntry
import app.libremusic.ui.PillButton
import app.libremusic.ui.ToolbarCapsule
import app.libremusic.ui.PlayerViewModel
import app.libremusic.ui.SearchField
import app.libremusic.ui.SheetHeader
import app.libremusic.ui.Spinner
import app.libremusic.ui.SwipeToRemove
import app.libremusic.ui.ToolbarButton
import app.libremusic.ui.playlistGradient
import app.libremusic.ui.songCount
import app.libremusic.ui.songMenu
import app.libremusic.ui.tactile
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.LocalReduceMotion
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Tokens
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.bold
import app.libremusic.ui.theme.medium
import app.libremusic.ui.theme.semibold
import app.libremusic.ui.theme.themeSurface
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Hoja del Jam (JamViews.swift): empezar, buscar al anfitrión y la sala con la lista.

private fun savedName(context: Context): String =
    context.getSharedPreferences("jam", Context.MODE_PRIVATE).getString("name", null).orEmpty()

private fun saveName(context: Context, name: String) {
    context.getSharedPreferences("jam", Context.MODE_PRIVATE).edit().putString("name", name.trim()).apply()
}

/** QR con el enlace libremusic://jam/CÓDIGO (el mismo que genera iOS). */
private fun qrCode(text: String, size: Int = 512): ImageBitmap {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
    val pixels = IntArray(size * size) { i -> if (matrix[i % size, i / size]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt() }
    return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888).asImageBitmap()
}

private enum class JamPane { Main, Add, Qr }

@Composable
fun JamScreen(playerVm: PlayerViewModel, libraryVm: LibraryViewModel, initialCode: String?, onClose: () -> Unit) {
    val state by JamService.state.collectAsState()
    val player by playerVm.track.collectAsState()
    var pane by remember { mutableStateOf(JamPane.Main) }
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current)
        AnimatedContent(pane to state.phase, label = "jam", transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(200)) }) { (p, phase) ->
            when {
                p == JamPane.Add -> JamAddSongs(onDone = { pane = JamPane.Main })
                p == JamPane.Qr && state.jam != null -> JamQr(state.jam!!, state.direct, onDone = { pane = JamPane.Main })
                phase == JamPhase.Idle -> JamStart(initialCode, onClose)
                phase == JamPhase.Searching -> JamSearching(state.joiningCode.orEmpty())
                else -> JamRoom(state, playerVm, libraryVm, onClose, onAdd = { pane = JamPane.Add }, onQr = { pane = JamPane.Qr })
            }
        }
    }
}

// MARK: Empezar ---------------------------------------------------------------------------------

@Composable
private fun JamStart(initialCode: String?, onClose: () -> Unit) {
    val c = Libre.colors
    val context = LocalContext.current
    var name by rememberSaveable { mutableStateOf(savedName(context)) }
    var title by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf(initialCode.orEmpty()) }
    val hasName = name.isNotBlank()
    fun join() { saveName(context, name); JamService.join(code, name.trim()) }
    val scan = rememberLauncherForActivityResult(ScanContract()) { result ->
        JamService.rememberLink(result.contents)
        JamLink.codeFrom(result.contents)?.let { code = it; if (name.isNotBlank()) join() }
    }
    // Llegó un código por enlace o QR del sistema: si ya hay nombre, se entra directamente.
    LaunchedEffect(initialCode) { if (initialCode != null && hasName) join() }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(top = 17.dp).height(44.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            ToolbarCapsule("Cerrar", onClick = onClose)
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 14.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(34.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Jam", style = Typo.display(46f, c.theme), color = c.label)
                Text(
                    L("Una playlist que hacéis entre todos. Funciona con gente que está cerca, en la misma WiFi."),
                    style = Typo.body, color = c.secondaryLabel,
                )
            }
            JamTextField(L("Tu nombre"), L("Así te verán los demás"), name) { name = it.take(30) }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(L("Crear uno"), style = Typo.title3.bold, color = c.label)
                JamTextField(L("Nombre del Jam"), L("Opcional, p. ej. Viaje a la playa"), title) { title = it.take(60) }
                PillButton(L("Crear Jam"), app.libremusic.ui.theme.JamIcon(filled = true), prominent = true, modifier = Modifier.fillMaxWidth(), enabled = hasName) {
                    saveName(context, name)
                    JamService.host(title, name.trim())
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(L("Unirme a uno"), style = Typo.title3.bold, color = c.label)
                Text(L("Pide el código a quien lo creó o escanea su QR."), style = Typo.subheadline, color = c.secondaryLabel)
                JamCodeField(code) { code = JamLink.normalize(it) }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    PillButton(L("Escanear QR"), Icons.Rounded.QrCodeScanner, prominent = false, modifier = Modifier.weight(1f)) {
                        scan.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt(L("Apunta al QR del Jam")).setBeepEnabled(false).setOrientationLocked(false))
                    }
                    PillButton("Unirme", Icons.AutoMirrored.Rounded.ArrowForward, prominent = true, modifier = Modifier.weight(1f), enabled = hasName && code.length >= JamLink.CODE_LENGTH) { join() }
                }
            }
            if (!hasName) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Info, null, tint = c.secondaryLabel, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(L("Escribe tu nombre para crear un Jam o unirte."), style = Typo.footnote, color = c.secondaryLabel)
                }
            }
        }
    }
}

/** Campo de texto con la superficie del tema y su etiqueta encima. */
@Composable
private fun JamTextField(label: String, prompt: String, text: String, onChange: (String) -> Unit) {
    val c = Libre.colors
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = Typo.subheadline.semibold, color = c.secondaryLabel)
        Box(Modifier.fillMaxWidth().height(50.dp).themeSurface(14.dp, c).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
            if (text.isEmpty()) Text(prompt, style = Typo.body.medium, color = c.tertiaryLabel)
            BasicTextField(text, onChange, singleLine = true, textStyle = Typo.body.medium.copy(color = c.label), cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth())
        }
    }
}

/** Seis casillas para el código; por debajo hay un único campo de texto invisible. */
@Composable
private fun JamCodeField(code: String, onChange: (String) -> Unit) {
    val c = Libre.colors
    val focus = remember { FocusRequester() }
    var focused by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().height(58.dp).tactile(label = L("Código del Jam, 6 caracteres")) { focus.requestFocus() }) {
        BasicTextField(
            code, onChange, singleLine = true,
            textStyle = Typo.body.copy(color = Color.Transparent), cursorBrush = SolidColor(Color.Transparent),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false),
            modifier = Modifier.fillMaxSize().focusRequester(focus).onFocusChanged { focused = it.isFocused },
        )
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (i in 0 until 6) {
                val caret = focused && i == minOf(code.length, 5)
                val shape = RoundedCornerShape(minOf(14f, c.theme.maxRadius).dp)
                Box(
                    Modifier.weight(1f).height(58.dp).themeSurface(14.dp, c).border(if (caret) 2.dp else 0.dp, if (caret) c.accent else Color.Transparent, shape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(code.getOrNull(i)?.toString().orEmpty(), style = Typo.mono(26f), color = c.label)
                }
            }
        }
    }
}

// MARK: Buscando al anfitrión ----------------------------------------------------------------------

@Composable
private fun JamSearching(code: String) {
    val c = Libre.colors
    var stalled by remember { mutableStateOf(false) }
    LaunchedEffect(code) { stalled = false; delay(12_000); stalled = true }
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        JamRadar(c.accent, Modifier.size(180.dp))
        Spacer(Modifier.height(26.dp))
        Text(L("Buscando el Jam"), style = Typo.display(30f, c.theme), color = c.label)
        if (code.isNotEmpty()) { Spacer(Modifier.height(10.dp)); JamCodeText(code, 24f) }
        Spacer(Modifier.height(26.dp))
        Text(
            if (stalled) L("Todavía no aparece. Comprobad que el código es correcto, que estáis en la misma WiFi y que quien lo creó tiene Pear Music abierta.")
            else L("Mantén Pear Music abierta. Suele tardar unos segundos."),
            style = Typo.subheadline, color = c.secondaryLabel, textAlign = TextAlign.Center,
        )
        Spacer(Modifier.weight(1f))
        PillButton("Cancelar", null, prominent = false, modifier = Modifier.fillMaxWidth()) { JamService.leave() }
    }
}

/** Ondas que salen del icono, como un radar buscando el móvil del anfitrión. */
@Composable
private fun JamRadar(tint: Color, modifier: Modifier) {
    val c = Libre.colors
    val reduce = LocalReduceMotion.current
    val t by rememberInfiniteTransition(label = "radar").animateFloat(0f, 1f, infiniteRepeatable(tween(2400, easing = LinearEasing), RepeatMode.Restart), label = "t")
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            for (i in 0 until 3) {
                val p = if (!reduce) (t + i / 3f) % 1f else 0.35f + i * 0.25f
                val r = size.minDimension / 2 * (0.35f + p * 0.65f)
                drawCircle(tint.copy(alpha = 0.9f * (1 - p)), r - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
            }
        }
        Box(Modifier.size(76.dp).themeSurface(38.dp, c).clip(CircleShape), contentAlignment = Alignment.Center) {
            Icon(app.libremusic.ui.theme.JamIcon(filled = true), null, tint = tint, modifier = Modifier.size(36.dp))
        }
    }
}

/** El código con las letras separadas, como se dicta en voz alta. */
@Composable
private fun JamCodeText(code: String, size: Float) {
    Text(code.toList().joinToString(" "), style = Typo.mono(size), color = Libre.colors.label)
}

// MARK: Sala -----------------------------------------------------------------------------------

@Composable
private fun JamRoom(state: JamUiState, playerVm: PlayerViewModel, libraryVm: LibraryViewModel, onClose: () -> Unit, onAdd: () -> Unit, onQr: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    val jam = state.jam ?: return
    val player by playerVm.track.collectAsState()
    val live = state.phase == JamPhase.Hosting || state.phase == JamPhase.Joined
    var savedName by remember { mutableStateOf<String?>(null) }
    var savedId by remember { mutableStateOf<String?>(null) }
    var menu by remember { mutableStateOf(false) }

    fun save() {
        if (jam.entries.isEmpty()) return
        val songs = jam.entries.map { it.song }
        val existing = savedId?.let { id -> libraryVm.data.value.playlists.firstOrNull { it.id == id } }
        if (existing != null) {
            songs.filter { s -> existing.songs.none { it.id == s.id } }.forEach { libraryVm.addToPlaylist(existing.id, it) }
        } else {
            libraryVm.createPlaylist(jam.name)?.let { p -> savedId = p.id; songs.forEach { libraryVm.addToPlaylist(p.id, it) } }
        }
        savedName = jam.name
    }

    fun leave() {
        if (state.phase == JamPhase.Lost) { JamService.dismiss(); return }
        if (jam.entries.isEmpty() || savedName != null) { JamService.leave(); return }
        env.app.alert = AlertSpec(
            L("¿Guardar la lista antes de salir?"),
            if (state.isHost) L("El Jam se terminará para todos.") else L("Podrás volver a entrar con el código mientras siga abierto."),
            buttons = listOf(
                AlertButton(L("Guardar y salir")) { save(); JamService.leave() },
                AlertButton(if (state.isHost) L("Terminar sin guardar") else L("Salir sin guardar"), AlertButton.Role.Destructive) { JamService.leave() },
                AlertButton("Cancelar", AlertButton.Role.Cancel),
            ),
        )
    }

    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Row(Modifier.fillMaxWidth().padding(top = 17.dp).height(44.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                ToolbarCapsule("Cerrar", onClick = onClose)
                Spacer(Modifier.weight(1f))
                Box {
                    ToolbarButton(Icons.Rounded.MoreHoriz, L("Opciones del Jam")) { menu = true }
                    ContextMenu(menu, { menu = false }, listOf(
                        MenuEntry.Action(if (savedId == null) L("Guardar como playlist") else L("Actualizar playlist guardada"), Icons.Rounded.Download, enabled = jam.entries.isNotEmpty()) { save() },
                        MenuEntry.Divider,
                        MenuEntry.Action(if (state.isHost) L("Terminar Jam") else L("Salir del Jam"), Icons.AutoMirrored.Rounded.Logout, destructive = true) { leave() },
                    ))
                }
            }
        }
        item {
            Column(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 4.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    LiveBadge(live, c.accent)
                    Text(jam.name, style = Typo.display(34f, c.theme), color = c.label, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    val n = songCount(jam.entries.size)
                    Text(if (state.isHost) L("Lo has creado tú · {0}", n) else L("De {0} · {1}", jam.host, n), style = Typo.subheadline, color = c.secondaryLabel)
                }
                Members(jam.members)
                if (live) ListenMode(state)
                if (state.phase == JamPhase.Lost) {
                    Row(Modifier.fillMaxWidth().themeSurface(16.dp, c).padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.WifiOff, null, tint = c.label, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(state.reason ?: L("Se perdió la conexión"), style = Typo.subheadline.semibold, color = c.label)
                    }
                } else {
                    Row(
                        Modifier.fillMaxWidth().themeSurface(20.dp, c).tactile(label = L("Muestra el código QR"), onClick = onQr).padding(horizontal = 18.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(L("Código para unirse"), style = Typo.caption.semibold, color = c.secondaryLabel)
                            Spacer(Modifier.height(4.dp))
                            JamCodeText(jam.code, 26f)
                        }
                        Icon(Icons.Rounded.QrCode, null, tint = c.accent, modifier = Modifier.size(28.dp))
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (live) {
                        PillButton(L("Añadir"), Icons.Rounded.Add, prominent = true, modifier = Modifier.weight(1f), onClick = onAdd)
                    } else if (savedName == null) {
                        PillButton(L("Guardar lista"), Icons.Rounded.Download, prominent = true, modifier = Modifier.weight(1f), enabled = jam.entries.isNotEmpty()) { save() }
                    }
                    PillButton(L("Reproducir"), Icons.Rounded.PlayArrow, prominent = false, modifier = Modifier.weight(1f), enabled = jam.entries.isNotEmpty()) {
                        playerVm.play(jam.entries.map { it.song }, 0)
                    }
                }
                savedName?.let {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.CheckCircle, null, tint = c.accent, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(L("Guardada en Biblioteca como «{0}»", it), style = Typo.footnote.semibold, color = c.accent)
                    }
                }
            }
        }
        items(jam.entries, key = { it.song.id }) { e ->
            val canRemove = live && (state.isHost || e.by == state.myName)
            val row: @Composable () -> Unit = { EntryRow(e, jam.entries.map { it.song }, player.current?.id == e.song.id, playerVm) }
            if (canRemove) SwipeToRemove(onRemove = { JamService.remove(e.song.id) }) { row() } else row()
            Box(Modifier.fillMaxWidth().padding(start = 82.dp).height(0.5.dp).background(c.label.copy(alpha = 0.08f)))
        }
        if (jam.entries.isEmpty()) item {
            Text(
                if (live) L("Aún no hay canciones. Añade la primera y aparecerá en el móvil de todos.") else L("La lista quedó vacía."),
                style = Typo.subheadline, color = c.secondaryLabel, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
            )
        }
        item { Spacer(Modifier.height(40.dp)) }
    }
}

/**
 * Dónde suena (2.6 de x.1.1): el anfitrión elige un altavoz (el suyo) o cada uno en su móvil, a la vez. El invitado,
 * con «cada uno en su móvil», puede quitarlo en el suyo (p. ej. si está al lado del altavoz).
 */
@Composable
private fun ListenMode(state: JamUiState) {
    val c = Libre.colors
    val jam = state.jam ?: return
    val everyone = jam.mode == JamSync.EVERYONE
    if (state.isHost) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(L("Dónde suena"), style = Typo.caption.semibold, color = c.secondaryLabel)
            app.libremusic.ui.Segmented(listOf(JamSync.SPEAKER to L("Un altavoz"), JamSync.EVERYONE to L("Cada uno en su móvil")), jam.mode) { JamService.setMode(it) }
            Text(
                if (everyone) L("Lo que suena aquí suena a la vez en el móvil de cada uno, con su propio audio. Pon algo de la lista.")
                else L("Suena sólo en este móvil; los demás añaden canciones."),
                style = Typo.footnote, color = c.secondaryLabel,
            )
        }
    } else if (everyone) {
        Row(Modifier.fillMaxWidth().themeSurface(16.dp, c).padding(start = 14.dp, end = 8.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(L("Escuchar también aquí"), style = Typo.subheadline.semibold, color = c.label)
                Text(L("Suena lo mismo que en el móvil de {0}, a la vez.", jam.host), style = Typo.footnote, color = c.secondaryLabel)
            }
            app.libremusic.ui.IosToggle(state.listenHere, { JamService.setListenHere(it) }, label = L("Escuchar también aquí"))
        }
    }
}

@Composable
private fun LiveBadge(live: Boolean, tint: Color) {
    val c = Libre.colors
    val reduce = LocalReduceMotion.current
    val pulse by rememberInfiniteTransition(label = "live").animateFloat(1f, 0.35f, infiniteRepeatable(tween(1000), RepeatMode.Reverse), label = "p")
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).background((if (live) tint else c.secondaryLabel).copy(alpha = if (live && !reduce) pulse else 1f), CircleShape))
        Spacer(Modifier.width(6.dp))
        Text(if (live) "EN DIRECTO" else L("SIN CONEXIÓN"), style = Typo.caption.bold, color = if (live) tint else c.secondaryLabel)
    }
}

/** Avatares superpuestos y los nombres de quienes están dentro. */
@Composable
private fun Members(members: List<String>) {
    val c = Libre.colors
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width((36 + (minOf(members.size, 6) - 1).coerceAtLeast(0) * 26).dp).height(36.dp)) {
            members.take(6).forEachIndexed { i, m -> Box(Modifier.offset(x = (i * 26).dp)) { JamAvatar(m, 36.dp) } }
        }
        Spacer(Modifier.width(12.dp))
        val names = when (members.size) {
            0 -> ""
            1 -> L("Sólo {0} por ahora", members[0])
            2 -> L("{0} y {1}", members[0], members[1])
            3 -> L("{0}, {1} y {2}", members[0], members[1], members[2])
            else -> L("{0}, {1} y {2} más", members[0], members[1], members.size - 2)
        }
        Text(names, style = Typo.subheadline.medium, color = c.label, maxLines = 2)
    }
}

/** Círculo con la inicial y un color estable por nombre (el mismo cálculo que iOS). */
@Composable
fun JamAvatar(name: String, size: Dp) {
    val c = Libre.colors
    var hash = 5381L
    name.forEach { ch -> hash = (hash * 33 + ch.code) and 0xFFFFFFFFFFFFL }
    val palette = ((hash and 0x7fffffff) % Tokens.PlaylistPalettes.size).toInt()
    Box(
        Modifier.size(size).clip(CircleShape).background(playlistGradient(palette)).border(2.dp, c.background, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(name.firstOrNull()?.uppercase() ?: "?", fontSize = (size.value * 0.42f).sp, fontWeight = FontWeight.Bold, color = Color.White)
    }
}

@Composable
private fun EntryRow(entry: JamEntry, context: List<Song>, isCurrent: Boolean, playerVm: PlayerViewModel) {
    val c = Libre.colors
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().tactile(label = entry.song.title, onLongClick = { menu = true }) {
                playerVm.play(context, context.indexOfFirst { it.id == entry.song.id }.coerceAtLeast(0))
            }.padding(start = 20.dp, end = 16.dp, top = 6.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CoverImage(entry.song.thumb(200), Modifier.size(50.dp).clip(RoundedCornerShape(10.dp)))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(entry.song.title, style = Typo.callout.copy(fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.SemiBold), color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(L("{0} · añadida por {1}", entry.song.artist, entry.by), style = Typo.footnote, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(8.dp))
            JamAvatar(entry.by, 26.dp)
        }
        ContextMenu(menu, { menu = false }, songMenu(entry.song))
    }
}

// MARK: QR y añadir canciones ---------------------------------------------------------------------

@Composable
private fun JamQr(state: JamState, direct: String?, onDone: () -> Unit) {
    val c = Libre.colors
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        SheetHeader("", trailing = "Listo", onTrailing = onDone)
        Text(state.name, style = Typo.display(26f, c.theme), color = c.label, maxLines = 1, modifier = Modifier.padding(top = 8.dp))
        Spacer(Modifier.height(20.dp))
        // Con la dirección del anfitrión: quien lo escanea entra al momento, sin esperar a buscar en la Wi-Fi.
        val qr = remember(state.code, direct) { qrCode(JamLink.link(state.code, direct)) }
        Box(Modifier.size(256.dp).background(Color.White, RoundedCornerShape(24.dp)).padding(18.dp)) {
            Image(qr, L("Código QR del Jam"), Modifier.fillMaxSize())
        }
        Spacer(Modifier.height(20.dp))
        JamCodeText(state.code, 28f)
        Spacer(Modifier.height(20.dp))
        Text(
            L("Escanead con la cámara del móvil o desde Biblioteca → + → Jam con amigos."),
            style = Typo.subheadline, color = c.secondaryLabel, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp),
        )
    }
}

@Composable
private fun JamAddSongs(onDone: () -> Unit) {
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val jam by JamService.state.collectAsState()
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Song>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    fun search() {
        val q = query.trim()
        if (q.isEmpty()) return
        searching = true; failed = false
        scope.launch {
            val r = withContext(Dispatchers.IO) { runCatching { YTClient.search(q) } }
            results = r.getOrDefault(emptyList()); failed = r.isFailure; searching = false
        }
    }
    Column(Modifier.fillMaxSize()) {
        SheetHeader(L("Añadir al Jam"), trailing = "Listo", onTrailing = onDone)
        SearchField(query, { query = it; if (it.isEmpty()) { results = emptyList(); failed = false } }, ::search, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        LazyColumn(Modifier.fillMaxSize()) {
            val added = jam.jam?.entries?.map { it.song.id }?.toSet().orEmpty()
            val active = jam.phase == JamPhase.Hosting || jam.phase == JamPhase.Joined
            if (query.isEmpty()) {
                if (data.favorites.isNotEmpty()) {
                    item { SectionHead(L("Tus favoritos")) }
                    items(data.favorites.take(40), key = { "f" + it.id }) { PickRow(it, it.id in added, active) }
                }
                if (data.recents.isNotEmpty()) {
                    item { SectionHead(L("Escuchado hace poco")) }
                    items(data.recents.take(20), key = { "r" + it.id }) { PickRow(it, it.id in added, active) }
                }
                if (data.favorites.isEmpty() && data.recents.isEmpty()) item { Note(L("Busca una canción para añadirla")) }
            } else when {
                searching -> item { Box(Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) { Spinner() } }
                failed -> item { Note(L("No se pudo buscar. Revisa tu conexión.")) }
                else -> items(results, key = { "s" + it.id }) { PickRow(it, it.id in added, active) }
            }
            item { Spacer(Modifier.height(40.dp)) }
        }
    }
}

@Composable
private fun SectionHead(text: String) {
    Text(text, style = Typo.headline, color = Libre.colors.label, modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 4.dp))
}

@Composable
private fun Note(text: String) {
    Text(text, style = Typo.body, color = Libre.colors.secondaryLabel, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 40.dp))
}

@Composable
private fun PickRow(song: Song, added: Boolean, active: Boolean) {
    val c = Libre.colors
    Row(
        Modifier.fillMaxWidth().tactile(enabled = !added && active, label = if (added) L("{0}, ya está en el Jam", song.title) else L("Añadir {0} al Jam", song.title)) { JamService.add(song) }
            .padding(horizontal = 20.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CoverImage(song.thumb(160), Modifier.size(46.dp).clip(RoundedCornerShape(9.dp)))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(song.title, style = Typo.body.semibold, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(song.artist, style = Typo.footnote, color = c.secondaryLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(if (added) Icons.Rounded.CheckCircle else Icons.Outlined.AddCircleOutline, null, tint = if (added) c.accent else c.secondaryLabel, modifier = Modifier.size(26.dp))
    }
}
