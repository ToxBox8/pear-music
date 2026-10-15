package app.libremusic.ui


import app.libremusic.L
import androidx.compose.ui.semantics.selected

import androidx.compose.ui.semantics.toggleableState

import androidx.compose.runtime.collectAsState
import app.libremusic.ui.theme.Prefs
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import app.libremusic.data.Playlist
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.LocalReduceMotion
import app.libremusic.ui.theme.SfIcons
import app.libremusic.ui.theme.Tokens
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.material
import app.libremusic.ui.theme.semibold
import app.libremusic.ui.theme.themeSurface
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

// Piezas comunes. Son las mismas que Kitchen.swift / Images.swift en iOS (inspiradas en
// «The Kitchen» de dqnamo): botón táctil, texto que se descifra, mantener para confirmar…

/** Curva «ui ease out» de todos los componentes: cubic-bezier(0.23, 1, 0.32, 1). */
val UiEaseOut = CubicBezierEasing(Tokens.Motion.EaseOut[0], Tokens.Motion.EaseOut[1], Tokens.Motion.EaseOut[2], Tokens.Motion.EaseOut[3])

fun <T> uiEaseOut(ms: Int = 180) = tween<T>(ms, easing = UiEaseOut)

/** «1 canción», «12 canciones». */
fun songCount(n: Int): String = if (n == 1) L("1 canción") else "$n canciones"

/** "3:08" a partir de segundos. */
fun timeString(seconds: Double): String {
    if (!seconds.isFinite() || seconds < 0) return "0:00"
    val s = seconds.toInt()
    return "%d:%02d".format(s / 60, s % 60)
}

/** "3:08" a partir de milisegundos. */
fun formatTime(ms: Long): String = timeString(ms / 1000.0)

// MARK: Hápticos --------------------------------------------------------------------------------

@Composable
fun rememberHaptics(): Haptics {
    val view = LocalView.current
    return remember(view) { Haptics(view) }
}

class Haptics(private val view: android.view.View) {
    /** Impacto ligero (UIImpactFeedbackGenerator .light). */
    fun light() { view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY) }
    /** Clic de selección (UISelectionFeedbackGenerator). */
    fun tick() { view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
    /** Éxito (UINotificationFeedbackGenerator .success). */
    fun success() { view.performHapticFeedback(HapticFeedbackConstants.CONFIRM) }
    fun medium() { view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK) }
}

// MARK: Tactile Button --------------------------------------------------------------------------

/**
 * Se hunde al pulsar (escala 0,97), como TactileButtonStyle en iOS. Sin vibración: lo decidió Toxbox.
 * Con [onLongClick] abre además el menú contextual.
 */
fun Modifier.tactile(
    enabled: Boolean = true,
    label: String? = null,
    onLongClick: (() -> Unit)? = null,
    /** false si el que llama ya atenúa todo el control (fondo incluido) al desactivarlo. */
    dimWhenDisabled: Boolean = true,
    onClick: () -> Unit,
): Modifier = composed {
    val click = onClick
    // Las acciones se leen al disparar y el detector sólo se reinicia si cambia si hay pulsación
    // larga. Antes usaba las lambdas como claves: cada recomposición (con música sonando, varias
    // por segundo) reiniciaba el gesto a medias y la pulsación larga no abría el menú.
    val currentClick by rememberUpdatedState(onClick)
    val currentLong by rememberUpdatedState(onLongClick)
    val hasLong = onLongClick != null
    var pressed by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, uiEaseOut(150), label = "tactile")
    this
        .graphicsLayer { scaleX = scale; scaleY = scale; alpha = if (enabled || !dimWhenDisabled) 1f else 0.45f }
        .semantics {
            role = Role.Button
            if (label != null) contentDescription = label
            if (enabled) this.onClick(label = null, action = { click(); true })
        }
        .then(
            if (!enabled) Modifier else Modifier.pointerInput(hasLong) {
                detectTapGestures(
                    onPress = {
                        pressed = true
                        tryAwaitRelease()
                        pressed = false
                    },
                    onLongPress = if (hasLong) { _: Offset -> currentLong?.invoke() } else null,
                    onTap = { currentClick() },
                )
            },
        )
}

/** Fila que se resalta al pulsar (RowHighlightStyle en iOS). */
fun Modifier.rowHighlight(onLongClick: (() -> Unit)? = null, onClick: () -> Unit): Modifier = composed {
    val click = onClick
    val c = Libre.colors
    val currentClick by rememberUpdatedState(onClick)
    val currentLong by rememberUpdatedState(onLongClick)
    val hasLong = onLongClick != null
    var pressed by remember { mutableStateOf(false) }
    val a by animateFloatAsState(if (pressed) 0.08f else 0f, uiEaseOut(150), label = "row")
    this
        .background(c.label.copy(alpha = a))
        .semantics { role = Role.Button; this.onClick(label = null, action = { click(); true }) }
        .pointerInput(hasLong) {
            detectTapGestures(
                onPress = { pressed = true; tryAwaitRelease(); pressed = false },
                onLongPress = if (hasLong) { _: Offset -> currentLong?.invoke() } else null,
                onTap = { currentClick() },
            )
        }
}

// MARK: Iconos ---------------------------------------------------------------------------------

@Composable
fun Glyph(icon: ImageVector, size: Dp = 22.dp, tint: Color = Libre.colors.label, label: String? = null, modifier: Modifier = Modifier) {
    Icon(icon, contentDescription = label, tint = tint, modifier = modifier.size(size))
}

/** Botón de icono de 44 dp (tamaño mínimo de toque de iOS). */
@Composable
fun IconTap(
    icon: ImageVector,
    label: String,
    modifier: Modifier = Modifier,
    size: Dp = 22.dp,
    tint: Color = Libre.colors.label,
    enabled: Boolean = true,
    box: Dp = 44.dp,
    onClick: () -> Unit,
) {
    Box(modifier.size(box).tactile(enabled, label, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(size))
    }
}

// MARK: Carátulas --------------------------------------------------------------------------------

/** Carátula con caché (Coil) y una nota mientras carga. */
@Composable
fun CoverImage(url: String?, modifier: Modifier = Modifier, placeholder: Boolean = true) {
    val c = Libre.colors
    Box(modifier.then(if (placeholder) Modifier.background(Color.Gray.copy(alpha = 0.25f)) else Modifier), contentAlignment = Alignment.Center) {
        if (placeholder) Icon(Icons.Rounded.MusicNote, null, tint = c.secondaryLabel, modifier = Modifier.size(20.dp))
        if (url != null) {
            AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
    }
}

/** Degradado de una playlist (PlaylistStyle.gradient en iOS); sin color elegido, violeta. */
fun playlistGradient(index: Int?): Brush {
    val p = Tokens.PlaylistPalettes[(index ?: 1).mod(Tokens.PlaylistPalettes.size)]
    return Brush.linearGradient(p)
}

/** Icono en un cuadrado redondeado con degradado, estilo Ajustes de iOS. */
@Composable
fun GradientIcon(icon: ImageVector, palette: Int?, size: Dp = 44.dp) {
    val shape = RoundedCornerShape(size * 0.27f)
    Box(
        Modifier.size(size).clip(shape).background(playlistGradient(palette)).border(1.dp, Color.White.copy(0.25f), shape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(size * 0.5f))
    }
}

/** Portada de una playlist: foto propia › icono elegido › mosaico de carátulas › icono por defecto. */
@Composable
fun PlaylistCover(playlist: Playlist, size: Dp, radius: Dp? = null, coverFile: File?, coverVersion: Int) {
    val shape = RoundedCornerShape(radius ?: size * 0.2f)
    Box(
        Modifier.size(size).clip(shape).border(1.dp, Color.White.copy(0.15f), shape),
    ) {
        when {
            coverFile != null && coverFile.exists() -> AsyncImage(
                model = coil.request.ImageRequest.Builder(androidx.compose.ui.platform.LocalContext.current)
                    .data(coverFile).memoryCacheKey("${coverFile.path}#$coverVersion").diskCacheKey("${coverFile.path}#$coverVersion").build(),
                contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(),
            )
            playlist.icon != null -> Box(Modifier.fillMaxSize().background(playlistGradient(playlist.tint)), contentAlignment = Alignment.Center) {
                Icon(SfIcons.of(playlist.icon), null, tint = Color.White, modifier = Modifier.size(size * 0.45f))
            }
            playlist.songs.size >= 4 -> Column(Modifier.fillMaxSize()) {
                val px = (size.value * 2).toInt()
                Row(Modifier.weight(1f)) {
                    CoverImage(playlist.songs[0].thumb(px), Modifier.weight(1f).fillMaxHeight())
                    CoverImage(playlist.songs[1].thumb(px), Modifier.weight(1f).fillMaxHeight())
                }
                Row(Modifier.weight(1f)) {
                    CoverImage(playlist.songs[2].thumb(px), Modifier.weight(1f).fillMaxHeight())
                    CoverImage(playlist.songs[3].thumb(px), Modifier.weight(1f).fillMaxHeight())
                }
            }
            playlist.songs.isNotEmpty() -> CoverImage(playlist.songs[0].thumb((size.value * 3).toInt()), Modifier.fillMaxSize())
            else -> Box(Modifier.fillMaxSize().background(playlistGradient(playlist.tint)), contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Rounded.QueueMusic, null, tint = Color.White, modifier = Modifier.size(size * 0.45f))
            }
        }
    }
}

// MARK: Scramble Text --------------------------------------------------------------------------

private val scrambleSymbols = "-_~`!@#$%^&*()+=[]{}|;:,.<>?".toCharArray()
private val revealedTitles = HashSet<String>()

/** Revela el texto de izquierda a derecha sobre símbolos aleatorios (32 ms por paso, máx. ~1,5 s). */
@Composable
fun ScrambleText(text: String, style: TextStyle, color: Color = Libre.colors.label, maxLines: Int = 1, textAlign: TextAlign? = null, enabled: Boolean = true) {
    val reduce = LocalReduceMotion.current
    var shown by remember(text) { mutableStateOf(if (!enabled || reduce || text in revealedTitles) text else " ".repeat(text.length)) }
    LaunchedEffect(text, enabled) {
        if (!enabled || reduce || text.isEmpty() || text in revealedTitles) { shown = text; return@LaunchedEffect }
        revealedTitles += text
        val step = maxOf(1, (text.length + 47) / 48)
        var revealed = 0
        while (revealed < text.length) {
            shown = String(CharArray(text.length) { i -> if (i < revealed || text[i].isWhitespace()) text[i] else scrambleSymbols.random() })
            delay(32)
            revealed += step
        }
        shown = text
    }
    Text(
        shown, style = style, color = color, maxLines = maxLines, overflow = TextOverflow.Ellipsis, textAlign = textAlign,
        modifier = Modifier.semantics { contentDescription = text },
    )
}

// MARK: Botones de cabecera (Reproducir / Aleatorio) -----------------------------------------------

/** Botón de 48 dp, ancho completo: relleno de acento o superficie del tema (PillButtonStyle). */
@Composable
fun PillButton(
    text: String,
    icon: ImageVector?,
    prominent: Boolean,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    leading: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    val c = Libre.colors
    val radius = minOf(Tokens.Radius.Pill, c.theme.maxRadius).dp
    val fg = if (prominent) c.onAccent else c.accent
    Row(
        modifier
            .graphicsLayer { alpha = if (enabled) 1f else 0.45f }
            .heightIn(min = 48.dp)
            .then(if (prominent) Modifier.background(c.accent, RoundedCornerShape(radius)) else Modifier.themeSurface(radius.value.dp, c))
            .tactile(enabled, text, dimWhenDisabled = false, onClick = onClick)
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leading != null) { leading(); Spacer(Modifier.width(8.dp)) }
        else if (icon != null) { Icon(icon, null, tint = fg, modifier = Modifier.size(26.dp)); Spacer(Modifier.width(10.dp)) }
        Text(text, style = Typo.body.semibold, color = fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** `.buttonStyle(.bordered)` y `.borderedProminent` de iOS 26: cápsula de 34 pt con texto normal. */
@Composable
fun CapsuleButton(text: String, icon: ImageVector?, prominent: Boolean, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val c = Libre.colors
    val bg = when {
        !enabled -> c.label.copy(alpha = 0.08f)
        prominent -> c.accent
        else -> c.accent.copy(alpha = 0.15f)
    }
    val fg = when {
        !enabled -> c.label.copy(alpha = 0.6f)
        prominent -> c.onAccent
        else -> c.accent
    }
    Row(
        // Desactivado como en iOS 26: fondo gris y texto gris oscuro (no se atenúa todo el botón).
        modifier.height(34.dp).background(bg, CircleShape).tactile(enabled, text, dimWhenDisabled = false, onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = if (enabled) fg else c.accent.copy(alpha = 0.6f), modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, style = Typo.body, color = fg, maxLines = 1)
    }
}

@Composable
fun PlayShuffleBar(songs: List<app.libremusic.data.Song>, onPlay: (List<app.libremusic.data.Song>, Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        PillButton(L("Reproducir"), Icons.Rounded.PlayArrow, prominent = true, modifier = Modifier.weight(1f), enabled = songs.isNotEmpty()) {
            onPlay(songs, 0)
        }
        PillButton(L("Aleatorio"), Icons.Rounded.Shuffle, prominent = false, modifier = Modifier.weight(1f), enabled = songs.isNotEmpty()) {
            onPlay(songs.shuffled(), 0)
        }
    }
}

// MARK: Hold to Confirm --------------------------------------------------------------------------

/** Acción destructiva que se rellena mientras se mantiene pulsada (1,6 s). Soltar antes la rebobina. */
@Composable
fun HoldToConfirmButton(title: String, icon: ImageVector = Icons.Rounded.Delete, durationMs: Int = 1600, action: () -> Unit) {
    val c = Libre.colors
    val red = c.destructive
    val progress = remember { Animatable(0f) }
    var confirmed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val shape = RoundedCornerShape(12.dp)
    val label = if (confirmed) L("Hecho") else title
    Box(
        Modifier
            .fillMaxWidth()
            .height(44.dp)
            .clip(shape)
            .background(red.copy(alpha = 0.14f))
            .border(1.dp, red.copy(alpha = 0.7f), shape)
            .semantics { contentDescription = L("{0}. Mantén pulsado para confirmar", title); this.onClick(label = null, action = { action(); true }) }
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown()
                    if (confirmed) return@awaitEachGesture
                    val job = scope.launch {
                        progress.animateTo(1f, tween(durationMs, easing = LinearEasing))
                        confirmed = true
                        haptics.success()
                        action()
                        delay(1800)
                        confirmed = false
                        progress.animateTo(0f, tween(180))
                    }
                    waitForUpOrCancellation()
                    if (!confirmed) {
                        job.cancel()
                        scope.launch { progress.animateTo(0f, tween(180)) }
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = red, modifier = Modifier.size(17.dp))
            Spacer(Modifier.width(6.dp))
            Text(label, style = Typo.subheadline.semibold, color = red)
        }
        // Capa roja que se rellena: el texto pasa a blanco por encima.
        Box(
            Modifier.fillMaxSize().drawWithContent {
                val w = size.width * progress.value
                clipRect(right = w) { this@drawWithContent.drawContent() }
            },
        ) {
            Box(Modifier.fillMaxSize().background(red), contentAlignment = Alignment.Center) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(icon, null, tint = Color.White, modifier = Modifier.size(17.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(label, style = Typo.subheadline.semibold, color = Color.White)
                }
            }
        }
    }
}


// MARK: Spinner, interruptor, segmentos -------------------------------------------------------------

/** UIActivityIndicatorView: 8 radios que giran. */
@Composable
fun Spinner(size: Dp = 20.dp, color: Color = Libre.colors.secondaryLabel) {
    val t by rememberInfiniteTransition(label = "spin").animateFloat(0f, 8f, infiniteRepeatable(tween(800, easing = LinearEasing)), label = "s")
    Canvas(Modifier.size(size)) {
        val step = t.toInt()
        for (i in 0 until 8) {
            val alpha = 0.25f + 0.75f * (((i - step + 8) % 8) / 7f)
            rotate(i * 45f) {
                drawLine(
                    color.copy(alpha = alpha),
                    Offset(center.x, this.size.height * 0.08f), Offset(center.x, this.size.height * 0.3f),
                    strokeWidth = this.size.width * 0.09f, cap = StrokeCap.Round,
                )
            }
        }
    }
}

/** UISwitch: 51×31, verde al activar. */
@Composable
fun IosToggle(checked: Boolean, onChange: (Boolean) -> Unit, enabled: Boolean = true, label: String? = null) {
    val c = Libre.colors
    val x by animateFloatAsState(if (checked) 1f else 0f, uiEaseOut(250), label = "toggle")
    Box(
        Modifier
            .size(51.dp, 31.dp)
            .clip(CircleShape)
            .background(androidx.compose.ui.graphics.lerp(c.fill, c.green, x))
            // TalkBack: «interruptor, activado/desactivado» con el nombre de la fila (antes decía sólo «botón»).
            .semantics {
                role = Role.Switch
                toggleableState = androidx.compose.ui.state.ToggleableState(checked)
                if (label != null) contentDescription = label
            }
            .tactile(enabled, onClick = { onChange(!checked) })
            .padding(2.dp),
    ) {
        Box(
            Modifier
                .offset(x = (20 * x).dp)
                .size(27.dp)
                .background(Color.White, CircleShape),
        )
    }
}

/** UISegmentedControl. */
@Composable
fun Segmented(options: List<Pair<String, String>>, selected: String, enabled: Boolean = true, onSelect: (String) -> Unit) {
    val c = Libre.colors
    Row(
        Modifier
            .fillMaxWidth()
            .height(32.dp)
            .graphicsLayer { alpha = if (enabled) 1f else 0.45f }
            .background(if (c.dark) Color(0x3D767680) else Color(0x1F767680), CircleShape)
            .padding(2.dp),
    ) {
        options.forEach { (key, label) ->
            val on = key == selected
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .then(if (on) Modifier.background(if (c.dark) Color(0xFF636366) else Color.White, CircleShape) else Modifier)
                    .semantics { this.selected = on } // TalkBack dice cuál está elegida
                    .tactile(enabled, label) { onSelect(key) },
                contentAlignment = Alignment.Center,
            ) {
                Text(label, style = Typo.footnote.copy(fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium), color = c.label)
            }
        }
    }
}

// MARK: Campo de búsqueda ----------------------------------------------------------------------

@Composable
fun SearchField(
    query: String,
    onQuery: (String) -> Unit,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = L("Canciones, artistas…"),
    focusRequester: FocusRequester? = null,
) {
    val c = Libre.colors
    Row(
        modifier
            .fillMaxWidth()
            .height(36.dp)
            .background(c.fill.copy(alpha = if (c.dark) 0.6f else 0.45f), RoundedCornerShape(10.dp))
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.Search, null, tint = c.secondaryLabel, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) Text(placeholder, style = Typo.body, color = c.secondaryLabel, maxLines = 1)
            BasicTextField(
                value = query,
                onValueChange = onQuery,
                singleLine = true,
                textStyle = Typo.body.copy(color = c.label),
                cursorBrush = SolidColor(c.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
                modifier = Modifier.fillMaxWidth().then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier),
            )
        }
        if (query.isNotEmpty()) {
            Icon(
                Icons.Rounded.Cancel, L("Borrar"), tint = c.tertiaryLabel,
                modifier = Modifier.size(18.dp).tactile(label = L("Borrar")) { onQuery("") },
            )
        }
    }
}

// MARK: Menú contextual (como el de iOS) ---------------------------------------------------------------

sealed interface MenuEntry {
    data class Action(
        val label: String,
        val icon: ImageVector? = null,
        val destructive: Boolean = false,
        val enabled: Boolean = true,
        val checked: Boolean = false,
        /** Imagen propia a la derecha en vez de [icon] (portada de una playlist…). */
        val image: (@Composable () -> Unit)? = null,
        val onClick: () -> Unit,
    ) : MenuEntry

    data class Sub(val label: String, val icon: ImageVector?, val children: List<MenuEntry>) : MenuEntry
    data object Divider : MenuEntry
    data class Note(val text: String) : MenuEntry
}

/** Ocupa toda la ventana y apunta dónde estaba el elemento pulsado. */
private class FullScreenPosition(private val onAnchor: (IntRect, IntSize) -> Unit) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        onAnchor(anchorBounds, windowSize)
        return IntOffset.Zero
    }
}

/**
 * Menú contextual de iOS: el fondo se desenfoca y oscurece, lo pulsado se eleva como vista
 * previa ([preview]) y el menú sale de ahí con rebote, debajo (o encima si no cabe). Los
 * submenús se abren en el sitio con su título arriba, como en iOS 16+.
 */
@Composable
fun ContextMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    entries: List<MenuEntry>,
    preview: (@Composable () -> Unit)? = null,
) {
    if (!expanded) return
    val c = Libre.colors
    val glass = LocalGlass.current != null
    val reduce = LocalReduceMotion.current
    val density = androidx.compose.ui.platform.LocalDensity.current
    var sub by remember { mutableStateOf<MenuEntry.Sub?>(null) }
    var anchor by remember { mutableStateOf<IntRect?>(null) }
    var window by remember { mutableStateOf(IntSize.Zero) }
    var menuSize by remember { mutableStateOf(IntSize.Zero) }
    val appear = remember { Animatable(0f) }
    var closing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        appear.animateTo(1f, if (reduce) tween(150) else androidx.compose.animation.core.spring(dampingRatio = 0.74f, stiffness = 380f))
    }
    fun close(after: () -> Unit = {}) {
        if (closing) return
        closing = true
        scope.launch {
            appear.animateTo(0f, tween(if (reduce) 1 else 170, easing = UiEaseOut))
            onDismiss()
            after()
        }
    }
    val menuShape = RoundedCornerShape(if (glass) 26.dp else 14.dp)
    val artworkTint = Prefs.artworkColorsApp.collectAsState().value && Prefs.artworkLevel.collectAsState().value.enabled &&
        app.libremusic.ui.theme.ThemeEngine.active.collectAsState().value
    val provider = remember { FullScreenPosition { a, w -> if (anchor != a) anchor = a; if (window != w) window = w } }

    Popup(popupPositionProvider = provider, onDismissRequest = { close() }, properties = PopupProperties(focusable = true, clippingEnabled = false)) {
        // Desenfoque del fondo con la ventana (Android 12+); en versiones anteriores, sólo se oscurece.
        val view = LocalView.current
        LaunchedEffect(view) {
            val root = view.rootView
            val lp = root.layoutParams as? android.view.WindowManager.LayoutParams ?: return@LaunchedEffect
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                lp.flags = lp.flags or android.view.WindowManager.LayoutParams.FLAG_BLUR_BEHIND
                lp.blurBehindRadius = with(density) { 22.dp.roundToPx() }
            }
            runCatching {
                (view.context.getSystemService(android.content.Context.WINDOW_SERVICE) as android.view.WindowManager).updateViewLayout(root, lp)
            }
        }
        CompositionLocalProvider(LocalInsideGlassSource provides false) {
            val a = appear.value
            Box(
                Modifier
                    .size(with(density) { window.width.toDp() }, with(density) { window.height.toDp() })
                    .background(Color.Black.copy(alpha = (if (c.dark) 0.32f else 0.16f) * a.coerceIn(0f, 1f)))
                    .pointerInput(Unit) { detectTapGestures { close() } },
            ) {
                val box = anchor
                if (box != null) {
                    val margin = with(density) { 12.dp.roundToPx() }
                    // Vista previa elevada en el sitio del elemento pulsado.
                    if (preview != null) {
                        Box(
                            Modifier
                                .offset { IntOffset(box.left, box.top) }
                                .size(with(density) { box.width.toDp() }, with(density) { box.height.toDp() })
                                .graphicsLayer {
                                    val s = 1f + 0.035f * a
                                    scaleX = s; scaleY = s
                                    shadowElevation = 18.dp.toPx() * a.coerceIn(0f, 1f)
                                    shape = RoundedCornerShape(14.dp)
                                    clip = true
                                },
                        ) { preview() }
                    }
                    // Menú: debajo del elemento (o encima si no cabe), alineado con su borde más cercano.
                    val below = box.bottom + margin
                    val fitsBelow = below + menuSize.height < window.height - margin
                    val y = if (fitsBelow) below else maxOf(margin, box.top - menuSize.height - margin)
                    val alignRight = box.center.x > window.width / 2
                    val x = (if (alignRight) box.right - menuSize.width else box.left)
                        .coerceIn(margin, maxOf(margin, window.width - menuSize.width - margin))
                    Column(
                        Modifier
                            .offset { IntOffset(x, y) }
                            .onSizeChanged { menuSize = it }
                            .graphicsLayer {
                                val s = 0.4f + 0.6f * a
                                scaleX = s; scaleY = s
                                alpha = a.coerceIn(0f, 1f)
                                transformOrigin = androidx.compose.ui.graphics.TransformOrigin(if (alignRight) 1f else 0f, if (fitsBelow) 0f else 1f)
                            }
                            .widthIn(min = 250.dp, max = 280.dp)
                            .then(
                                if (glass) Modifier.liquidGlass(menuShape, c.dark, GlassStyle.Menu).clip(menuShape)
                                else Modifier.shadow(24.dp, menuShape, ambientColor = Color.Black.copy(0.25f), spotColor = Color.Black.copy(0.25f))
                                    .clip(menuShape).background(material(c.dark, thick = true))
                                    // «Colores de la carátula»: el menú toma un toque del color de la canción.
                                    .background(if (artworkTint) c.accent.copy(alpha = 0.08f) else Color.Transparent),
                            )
                            .heightIn(max = 460.dp)
                            .verticalScroll(rememberScrollState())
                            .pointerInput(Unit) { detectTapGestures { } },
                    ) {
                        val open = sub
                        if (open != null) {
                            // Submenú abierto en el sitio: su título arriba; tocarlo vuelve atrás.
                            MenuRow(open.label, Icons.Rounded.KeyboardArrowDown, c.label, bold = true) { sub = null }
                            Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.separator))
                            MenuEntries(open.children, c, onSub = { sub = it }) { action -> close(action.onClick) }
                        } else {
                            MenuEntries(entries, c, onSub = { sub = it }) { action -> close(action.onClick) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MenuEntries(level: List<MenuEntry>, c: app.libremusic.ui.theme.LibreColors, onSub: (MenuEntry.Sub) -> Unit, onAction: (MenuEntry.Action) -> Unit) {
    level.forEachIndexed { i, e ->
        if (i > 0 && e !is MenuEntry.Divider && level[i - 1] !is MenuEntry.Divider) {
            Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.separator))
        }
        when (e) {
            is MenuEntry.Action -> MenuRow(
                e.label, if (e.checked) Icons.Rounded.Check else e.icon,
                if (e.destructive) c.destructive else c.label, e.enabled, image = e.image,
            ) { onAction(e) }
            is MenuEntry.Sub -> MenuRow(e.label, e.icon, c.label, trailingChevron = true) { onSub(e) }
            MenuEntry.Divider -> Box(Modifier.fillMaxWidth().height(8.dp).background(c.separator.copy(alpha = 0.3f)))
            is MenuEntry.Note -> Text(e.text, style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(16.dp, 11.dp))
        }
    }
}

@Composable
private fun MenuRow(
    label: String,
    icon: ImageVector?,
    color: Color,
    enabled: Boolean = true,
    bold: Boolean = false,
    trailingChevron: Boolean = false,
    image: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .graphicsLayer { alpha = if (enabled) 1f else 0.4f }
            .then(if (enabled) Modifier.rowHighlight(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = if (bold) Typo.body.semibold else Typo.body, color = color, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
        when {
            image != null -> Box(Modifier.size(28.dp)) { image() }
            icon != null -> Icon(icon, null, tint = color, modifier = Modifier.size(19.dp))
        }
        if (trailingChevron) {
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Rounded.ChevronRight, null, tint = Libre.colors.tertiaryLabel, modifier = Modifier.size(18.dp))
        }
    }
}

// MARK: Desvanecer bordes -----------------------------------------------------------------------

/** Difumina los bordes superior e inferior de una lista que desborda (edgeFade en iOS). */
fun Modifier.edgeFade(size: Dp = 32.dp): Modifier = this
    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
    .drawWithContent {
        drawContent()
        val f = size.toPx() / this.size.height
        drawRect(
            Brush.verticalGradient(0f to Color.Transparent, f to Color.Black, 1 - f to Color.Black, 1f to Color.Transparent),
            blendMode = BlendMode.DstIn,
        )
    }

// MARK: Anillo de puntos -------------------------------------------------------------------------

/** Un punto por cada 1/[dots] de la lista: los iluminados son la parte descargada (DotRing). */
@Composable
fun DotRing(lit: Double, diameter: Dp, tint: Color, dots: Int = 72) {
    val off = Libre.colors.label.copy(alpha = 0.2f)
    Canvas(Modifier.size(diameter)) {
        val r = size.minDimension / 2
        for (i in 0 until dots) {
            val on = i.toDouble() / dots < lit
            val a = Math.toRadians(i * 360.0 / dots - 90)
            val p = Offset(center.x + r * kotlin.math.cos(a).toFloat(), center.y + r * kotlin.math.sin(a).toFloat())
            drawCircle(if (on) tint else off, radius = (if (on) 5f else 3.5f) / 2 * density, center = p)
        }
    }
}

// MARK: Deslizar para quitar ---------------------------------------------------------------------

/** Acción al deslizar la fila hacia la izquierda («Quitar» en rojo), como swipeActions sin deslizamiento completo. */
@Composable
fun SwipeToRemove(label: String = L("Quitar"), onRemove: () -> Unit, content: @Composable () -> Unit) {
    val c = Libre.colors
    val density = androidx.compose.ui.platform.LocalDensity.current
    val action = with(density) { 84.dp.toPx() }
    val offset = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxWidth()) {
        if (offset.value < 0f) {
            Box(
                Modifier.matchParentSize().background(c.destructive),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Box(
                    Modifier.width(84.dp).fillMaxHeight().tactile(label = label) {
                        scope.launch { offset.animateTo(0f, tween(200)) }
                        onRemove()
                    },
                    contentAlignment = Alignment.Center,
                ) { Text(label, style = Typo.subheadline.semibold, color = Color.White) }
            }
        }
        Box(
            Modifier
                .offset { IntOffset(offset.value.toInt(), 0) }
                .background(if (offset.value < 0f) c.background else Color.Transparent)
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onHorizontalDrag = { change, dx ->
                            val next = (offset.value + dx).coerceIn(-action * 1.3f, 0f)
                            if (next != offset.value) change.consume()
                            scope.launch { offset.snapTo(next) }
                        },
                        onDragEnd = { scope.launch { offset.animateTo(if (offset.value < -action / 2) -action else 0f, tween(220, easing = UiEaseOut)) } },
                    )
                },
        ) { content() }
    }
}

/** Botón para lectores de pantalla en elementos con gestos propios. */
fun Modifier.semanticsButton(label: String, onClick: () -> Unit): Modifier = this.semantics {
    role = Role.Button
    contentDescription = label
    this.onClick(label = null, action = { onClick(); true })
}
