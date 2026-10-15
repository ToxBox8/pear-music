package app.libremusic.ui


import app.libremusic.L
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.displayCutoutPadding
import androidx.compose.ui.platform.LocalConfiguration
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bluetooth
import androidx.compose.material.icons.rounded.Cast
import androidx.compose.material.icons.rounded.DirectionsCar
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material.icons.rounded.FastRewind
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Smartphone
import androidx.compose.material.icons.rounded.Speaker
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import app.libremusic.data.Song
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.LocalReduceMotion
import app.libremusic.ui.theme.Tokens
import app.libremusic.ui.theme.Typo
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

// Reproductor «Air» (AirPlayer.swift): papel plateado, grotesco negro, un disco esmerilado con la
// carátula desenfocada rodeado de puntos, el selector holográfico que marca dónde vas y abajo el panel
// con la rueda del iPod, el «x1» y la salida de audio.

data class AirColors(
    val paper: Color, val panel: Color, val wheel: Color, val hub: Color,
    val ink: Color, val muted: Color, val dotOff: Color, val dark: Boolean,
) {
    val panelFill get() = Brush.linearGradient(if (dark) listOf(Color(0xFF26272A), Color(0xFF1B1C1E)) else listOf(Color(0xFFDFE2E6), Color(0xFFCDD1D6)))
    val wheelFill get() = Brush.verticalGradient(if (dark) listOf(Color(0xFF36373B), Color(0xFF26272A)) else listOf(Color.White, Color(0xFFE9EBEE)))
    val hubFill get() = Brush.verticalGradient(if (dark) listOf(Color(0xFF141416), Color(0xFF202124)) else listOf(Color(0xFFBEC2C9), Color(0xFFDADDE1)))

    companion object {
        fun of(dark: Boolean) = if (dark) {
            Tokens.AirDark.run { AirColors(Paper, Panel, Wheel, Hub, Ink, Muted, DotOff, true) }
        } else {
            Tokens.AirLight.run { AirColors(Paper, Panel, Wheel, Hub, Ink, Muted, DotOff, false) }
        }
    }
}

@Composable
fun AirPlayerView(song: Song, onQueue: () -> Unit, onLyrics: () -> Unit, onClose: () -> Unit) {
    val c = AirColors.of(Libre.colors.dark)
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val data by env.library.data.collectAsState()
    val fav = data.favorites.any { it.id == song.id }
    var scrub by remember { mutableStateOf<Double?>(null) }
    val favScale by animateFloatAsState(if (fav) 1.1f else 1f, spring(dampingRatio = 0.5f, stiffness = 400f), label = "fav")
    val header: @Composable () -> Unit = {
        Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 12.dp, top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(L("Música"), style = Typo.air(30f, bold = true), color = c.ink, modifier = Modifier.weight(1f))
            // Los botones del reproductor Normal, en la tinta del Air (Fase 3.4): bucle, temporizador y «⋯» (con la letra).
            RepeatButton(st.repeatMode, ink = c.ink) { env.player.cycleRepeat() }
            SleepTimerButton(ink = c.ink)
            SongMoreButton(song, onLyrics, ink = c.ink)
            Box(Modifier.size(44.dp).tactile(label = if (fav) L("Quitar de favoritos") else L("Añadir a favoritos")) { env.library.toggleFavorite(song) }, contentAlignment = Alignment.Center) {
                Icon(if (fav) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, null, tint = c.ink, modifier = Modifier.size(26.dp).scale(favScale))
            }
            IconTap(Icons.Rounded.KeyboardArrowDown, L("Cerrar reproductor"), tint = c.ink, size = 36.dp, onClick = onClose)
        }
    }
    val title: @Composable () -> Unit = {
        Column(Modifier.fillMaxWidth().padding(top = 14.dp, start = 24.dp, end = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(song.title, style = Typo.air(26f, bold = true), color = c.ink, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(5.dp))
            val sub = scrub?.let { "${timeString(it * st.duration)} / ${timeString(st.duration)}" } ?: st.error ?: song.artist
            Text(sub, style = Typo.air(17f), color = if (scrub == null && st.error != null) Libre.colors.destructive else c.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    val landscape = LocalConfiguration.current.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
    if (landscape) {
        // En horizontal el disco se medía por el ancho y tapaba todo: va a la izquierda, a la altura de la pantalla.
        Row(Modifier.fillMaxSize().navigationBarsPadding().displayCutoutPadding(), verticalAlignment = Alignment.CenterVertically) {
            AirDisc(
                song, st.progress, st.duration, st.isPlaying, c, scrub, { scrub = it },
                Modifier.fillMaxHeight().padding(vertical = 12.dp, horizontal = 8.dp).aspectRatio(1f, matchHeightConstraintsFirst = true),
            ) { env.player.seekSeconds(it) }
            Column(Modifier.weight(1f).fillMaxHeight()) {
                header()
                Spacer(Modifier.weight(1f))
                title()
                Spacer(Modifier.weight(1f))
                AirControlPanel(song, c, onQueue, Modifier.padding(horizontal = 14.dp).padding(bottom = 10.dp))
            }
        }
        return
    }
    Column(Modifier.fillMaxSize().navigationBarsPadding()) {
        header()
        // Los dos Spacer de iOS (mínimo 6 y 14 pt) se reparten el hueco a partes iguales.
        Spacer(Modifier.weight(1f).heightIn(min = 6.dp))
        AirDisc(song, st.progress, st.duration, st.isPlaying, c, scrub, { scrub = it }) { env.player.seekSeconds(it) }
        title()
        Spacer(Modifier.weight(1f).heightIn(min = 14.dp))
        AirControlPanel(song, c, onQueue, Modifier.padding(horizontal = 14.dp).padding(bottom = 10.dp))
    }
}

// MARK: Disco ------------------------------------------------------------------------------------

private const val DOTS = 64

@Composable
private fun AirDisc(
    song: Song, progress: Double, duration: Double, playing: Boolean, colors: AirColors,
    scrub: Double?, setScrub: (Double?) -> Unit,
    modifier: Modifier = Modifier.fillMaxWidth().padding(horizontal = 30.dp).aspectRatio(1f),
    onSeek: (Double) -> Unit,
) {
    val reduce = LocalReduceMotion.current
    val haptics = rememberHaptics()
    var lastDot by remember { mutableIntStateOf(-1) }
    // El progreso llega dos veces por segundo; entre medias se calcula en cada fotograma para que el
    // selector y los puntos avancen sin tirones (antes, una animación de 500 ms por paso).
    val live = rememberSmoothProgress(progress, playing && scrub == null, LocalEnv.current.player.state.collectAsState().value.rate)
    val p = scrub ?: if (duration > 0) min(1.0, live / duration) else 0.0
    val animated = p.toFloat()
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val side = min(maxWidth.value, maxHeight.value)
        val disc = side - 46
        val knob = min(104f, disc * 0.34f)
        // Anillo de puntos
        Canvas(Modifier.size(side.dp)) {
            val r = size.minDimension / 2 - 5.dp.toPx()
            for (i in 0 until DOTS) {
                val on = i.toDouble() / DOTS <= p
                val a = 2 * PI * i / DOTS
                val pt = Offset(center.x + (r * sin(a)).toFloat(), center.y - (r * cos(a)).toFloat())
                drawCircle(if (on) colors.ink else colors.dotOff, (if (on) 5.5f else 3f) / 2 * density, pt)
            }
        }
        // Carátula desenfocada
        Box(
            Modifier.size(disc.dp)
                .dropShadow(CircleShape, Color.Black.copy(alpha = 0.07f), blur = 30.dp, offsetY = 18.dp)
                .clip(CircleShape)
                .border(1.dp, Color.White.copy(0.55f), CircleShape),
        ) {
            // requiredSize: con size() quedaba recortada al disco y el desplazamiento dejaba un borde a la vista.
            CoverImage(song.thumb(500), Modifier.align(Alignment.Center).requiredSize((disc * 1.15f).dp).blur(18.dp))
            Box(Modifier.fillMaxSize().background(colors.paper.copy(alpha = 0.42f)))
        }
        // Selector holográfico
        val radius = disc / 2 - knob / 2 - 10
        HoloKnob(
            song.thumb(300), playing && !reduce,
            Modifier.offset((sin(animated * 2 * PI) * radius).dp, (-cos(animated * 2 * PI) * radius).dp).size(knob.dp),
        )
        // Zona de arrastre: sólo el borde (puntos + selector); el centro deja cerrar la hoja.
        val inner = disc / 2 - knob - 20
        Box(
            Modifier.size(side.dp).pointerInput(duration) {
                val cx = size.width / 2f
                val cy = size.height / 2f
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val d0 = hypot(down.position.x - cx, down.position.y - cy) / density
                    if (d0 < inner || duration <= 0) return@awaitEachGesture
                    var current: Double? = null
                    while (true) {
                        val ev = awaitPointerEvent()
                        val ch = ev.changes.firstOrNull() ?: break
                        if (!ch.pressed) break
                        if (current == null && hypot(ch.position.x - down.position.x, ch.position.y - down.position.y) < 2 * density) continue
                        ch.consume()
                        var a = atan2((ch.position.x - cx).toDouble(), (cy - ch.position.y).toDouble())
                        if (a < 0) a += 2 * PI
                        var next = a / (2 * PI)
                        // Sin saltos de 100 % a 0 % al cruzar las 12.
                        current?.let { s ->
                            if (s > 0.75 && next < 0.25) next = 0.999
                            if (s < 0.25 && next > 0.75) next = 0.0
                        }
                        val dot = (next * DOTS).toInt()
                        if (dot != lastDot) { lastDot = dot; haptics.tick() }
                        current = next
                        setScrub(next)
                    }
                    current?.let { onSeek(it * duration) }
                    setScrub(null)
                    lastDot = -1
                }
            }.semanticsButton(L("Progreso: {0} de {1}", timeString(progress), timeString(duration))) {},
        )
    }
}

/**
 * Progreso (s) que avanza en cada fotograma mientras suena, partiendo del último valor conocido.
 * Al llegar uno nuevo se toma como referencia (el salto es de unas centésimas).
 */
@Composable
fun rememberSmoothProgress(progress: Double, running: Boolean, rate: Float = 1f): Double {
    val anchor = remember { doubleArrayOf(progress, System.nanoTime().toDouble()) }
    val shown = remember { mutableDoubleStateOf(progress) }
    LaunchedEffect(progress) {
        anchor[0] = progress
        anchor[1] = System.nanoTime().toDouble()
        if (!running) shown.doubleValue = progress
    }
    LaunchedEffect(running, rate) {
        if (!running) { shown.doubleValue = progress; return@LaunchedEffect }
        while (true) withFrameNanos { now -> shown.doubleValue = anchor[0] + (now - anchor[1]) / 1e9 * rate }
    }
    return shown.doubleValue
}

/** Selector: la carátula, nítida, gira como un CD; encima, el reflejo holográfico (que no gira). */
@Composable
private fun HoloKnob(art: String?, spinning: Boolean, modifier: Modifier) {
    val clock = rememberClockState(spinning)
    Box(
        modifier
            .shadow(12.dp, CircleShape, ambientColor = Color.Black.copy(0.22f), spotColor = Color.Black.copy(0.22f))
            .clip(CircleShape)
            .border(3.dp, Brush.verticalGradient(listOf(Color.White, Color(0xFFBFC3CA))), CircleShape),
    ) {
        CoverImage(art, Modifier.fillMaxSize().graphicsLayer { rotationZ = ((clock.longValue / 1000.0) * 40 % 360).toFloat() })
        Canvas(Modifier.fillMaxSize().graphicsLayer { alpha = 0.42f }) {
            rotateWedge(35f) {
                drawArc(
                    Brush.sweepGradient(*holoStops, center = center),
                    startAngle = -150f, sweepAngle = 120f, useCenter = true, blendMode = BlendMode.Screen,
                )
            }
        }
        Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color.White.copy(0.35f), Color.Transparent, Color.Black.copy(0.12f)))))
        Box(Modifier.align(Alignment.Center).fillMaxSize(0.16f).background(Color(0xFFE7E9EC), CircleShape).border(1.dp, Color.Black.copy(0.12f), CircleShape))
    }
}

/**
 * El AngularGradient de iOS (arcoíris de −60° a 60°, con los extremos fijos fuera de ese tramo) como
 * paradas de un sweepGradient, que en Compose da la vuelta entera empezando en las 3.
 */
private val holoStops: Array<Pair<Float, Color>> = run {
    val rainbow = Tokens.HoloRainbow
    fun at(t: Float): Color {
        val x = t.coerceIn(0f, 1f) * (rainbow.size - 1)
        val i = x.toInt().coerceAtMost(rainbow.size - 2)
        return androidx.compose.ui.graphics.lerp(rainbow[i], rainbow[i + 1], x - i)
    }
    val stops = mutableListOf<Pair<Float, Color>>()
    for (k in 0..6) stops += (k * 10f / 360f) to at(0.5f + k / 12f)          // 0°…60°
    stops += 0.5f to rainbow.last()                                             // 60°…180°: violeta
    stops += 0.5001f to rainbow.first()                                         // 180°…300°: rojo
    for (k in 0..6) stops += ((300f + k * 10f) / 360f) to at(k / 12f)          // 300°…360°
    stops.toTypedArray()
}

private inline fun androidx.compose.ui.graphics.drawscope.DrawScope.rotateWedge(deg: Float, block: androidx.compose.ui.graphics.drawscope.DrawScope.() -> Unit) {
    drawContext.transform.rotate(deg, center)
    block()
    drawContext.transform.rotate(-deg, center)
}

// MARK: Panel de controles ----------------------------------------------------------------------

@Composable
private fun AirControlPanel(song: Song, colors: AirColors, onQueue: () -> Unit, modifier: Modifier) {
    val shape = RoundedCornerShape(34.dp)
    Box(
        modifier.fillMaxWidth().clip(shape).background(colors.panelFill)
            .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(0.7f), Color.White.copy(0.1f))), shape),
    ) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                AirSpeedKnob(colors)
                AirRouteTile(colors)
            }
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                AirWheel(colors, onQueue, Modifier.widthIn(max = 210.dp))
            }
        }
        AirDownloadDots(song, colors, Modifier.align(Alignment.BottomEnd).padding(12.dp))
    }
}

/** «x1»: cambia la velocidad; el punto gira alrededor como en un dial. */
@Composable
private fun AirSpeedKnob(colors: AirColors) {
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val rates = listOf(1f, 1.25f, 1.5f, 2f, 0.75f)
    val i = rates.indexOfFirst { kotlin.math.abs(it - st.rate) < 0.01f }.coerceAtLeast(0)
    val angle by animateFloatAsState(135f + i * 50f, spring(dampingRatio = 0.7f, stiffness = 250f), label = "rate")
    val label = "x" + if (st.rate % 1f == 0f) "${st.rate.roundToInt()}" else st.rate.toString()
    Box(
        Modifier.size(68.dp).shadow(8.dp, CircleShape, ambientColor = Color.Black.copy(0.05f), spotColor = Color.Black.copy(0.05f))
            .background(colors.wheel.copy(alpha = 0.7f), CircleShape)
            .tactile(label = L("Velocidad {0}", label)) { env.player.setRate(rates[(i + 1) % rates.size]) },
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = Typo.air(15f), color = colors.ink)
        Box(Modifier.fillMaxSize().rotate(angle), contentAlignment = Alignment.TopCenter) {
            Box(Modifier.padding(top = 5.dp).size(6.dp).background(colors.ink, CircleShape))
        }
    }
}

private data class AudioRoute(val name: String, val icon: ImageVector)

private fun currentRoute(am: AudioManager): AudioRoute {
    val outs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
    fun has(vararg types: Int) = outs.firstOrNull { it.type in types }
    has(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER)?.let {
        return AudioRoute(it.productName?.toString()?.ifBlank { null } ?: L("Bluetooth"), Icons.Rounded.Headphones)
    }
    has(AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_USB_HEADSET)?.let {
        return AudioRoute(L("Auriculares"), Icons.Rounded.Headphones)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        has(AudioDeviceInfo.TYPE_REMOTE_SUBMIX)?.let { return AudioRoute(L("Cast"), Icons.Rounded.Cast) }
    }
    has(AudioDeviceInfo.TYPE_BUS)?.let { return AudioRoute(L("Coche"), Icons.Rounded.DirectionsCar) }
    // iOS muestra «iPhone» para el altavoz del propio teléfono.
    return AudioRoute(L("Este móvil"), Icons.Rounded.Smartphone)
}

/** Casilla blanca con el dispositivo de salida; tocarla abre el panel de salida de audio. */
@Composable
private fun AirRouteTile(colors: AirColors) {
    val context = LocalContext.current
    val am = remember { context.getSystemService(AudioManager::class.java) }
    var route by remember { mutableStateOf(currentRoute(am)) }
    DisposableEffect(am) {
        val cb = object : android.media.AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) { route = currentRoute(am) }
            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) { route = currentRoute(am) }
        }
        am.registerAudioDeviceCallback(cb, null)
        onDispose { am.unregisterAudioDeviceCallback(cb) }
    }
    Column(
        Modifier.size(104.dp)
            .shadow(10.dp, RoundedCornerShape(24.dp), ambientColor = Color.Black.copy(0.05f), spotColor = Color.Black.copy(0.05f))
            .background(colors.wheelFill, RoundedCornerShape(24.dp))
            .tactile(label = L("Salida de audio: {0}", route.name)) { openOutputSwitcher(context) },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(route.icon, null, tint = colors.muted, modifier = Modifier.size(42.dp))
        Spacer(Modifier.height(6.dp))
        Text(route.name, style = Typo.air(11f), color = colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 6.dp))
    }
}

private enum class Zone { Menu, Back, Forward, Play, Hub }

/** La rueda del iPod: toca arriba (cola), izquierda, derecha, abajo o el centro; gira por el borde para avanzar. */
@Composable
private fun AirWheel(colors: AirColors, onQueue: () -> Unit, modifier: Modifier) {
    val env = LocalEnv.current
    val st by env.player.state.collectAsState()
    val latest by androidx.compose.runtime.rememberUpdatedState(st)
    val queue by androidx.compose.runtime.rememberUpdatedState(onQueue)
    val haptics = rememberHaptics()
    var pressed by remember { mutableStateOf<Zone?>(null) }
    var preview by remember { mutableStateOf<Double?>(null) }
    BoxWithConstraints(modifier.fillMaxWidth().aspectRatio(1f)) {
        val d = maxWidth.value
        val hub = d * 0.36f
        val inset = d * 0.15f
        fun point(z: Zone): Pair<Float, Float> = when (z) {
            Zone.Menu -> d / 2 to inset
            Zone.Back -> inset to d / 2
            Zone.Forward -> d - inset to d / 2
            Zone.Play -> d / 2 to d - inset
            Zone.Hub -> d / 2 to d / 2
        }
        Box(
            Modifier.fillMaxSize()
                .shadow(16.dp, CircleShape, ambientColor = Color.Black.copy(0.06f), spotColor = Color.Black.copy(0.06f))
                .background(colors.wheelFill, CircleShape)
                .border(1.dp, Color.White.copy(0.8f), CircleShape),
        )
        @Composable
        fun glyph(icon: ImageVector, size: Float, z: Zone) {
            val (x, y) = point(z)
            Icon(icon, null, tint = colors.muted, modifier = Modifier.offset((x - size).dp, (y - size).dp).size((size * 2).dp))
        }
        // Mitad de la caja: los glifos de Material dejan margen, así miden como los SF Symbols de 11 y 13 pt.
        glyph(Icons.Rounded.GridView, 8f, Zone.Menu)
        glyph(Icons.Rounded.FastRewind, 12f, Zone.Back)
        glyph(Icons.Rounded.FastForward, 12f, Zone.Forward)
        glyph(if (st.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, 11f, Zone.Play)
        val hubScale by animateFloatAsState(if (pressed == Zone.Hub) 0.94f else 1f, uiEaseOut(150), label = "hub")
        Box(
            Modifier.align(Alignment.Center).size(hub.dp).scale(hubScale).background(colors.hubFill, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            preview?.let { Text(timeString(it), style = Typo.air(15f, bold = true), color = colors.ink) }
        }
        // Anillo negro sobre lo que se pulsa, como en Air OS.
        val z = pressed
        AnimatedVisibility(z != null, enter = fadeIn(uiEaseOut(150)) + scaleIn(initialScale = 0.6f), exit = fadeOut(uiEaseOut(250))) {
            val zz = z ?: Zone.Hub
            val ring = if (zz == Zone.Hub) hub + 12 else 48f
            val (x, y) = point(zz)
            Box(Modifier.offset((x - ring / 2).dp, (y - ring / 2).dp).size(ring.dp).border(5.dp, colors.ink, CircleShape))
        }
        // Gestos
        Box(
            Modifier.fillMaxSize().pointerInput(Unit) {
                val c = Offset(size.width / 2f, size.height / 2f)
                val hubPx = hub * density
                awaitEachGesture {
                    val down = awaitFirstDown()
                    val dx = down.position.x - c.x
                    val dy = down.position.y - c.y
                    val zone = when {
                        hypot(dx, dy) < hubPx / 2 -> Zone.Hub
                        kotlin.math.abs(dx) > kotlin.math.abs(dy) -> if (dx > 0) Zone.Forward else Zone.Back
                        else -> if (dy > 0) Zone.Play else Zone.Menu
                    }
                    pressed = zone
                    val onRim = hypot(dx, dy) >= hubPx / 2
                    var last = atan2((down.position.y - c.y).toDouble(), (down.position.x - c.x).toDouble())
                    var spun = 0.0
                    val start = latest.progress
                    var tick = 0
                    var moved = false
                    while (true) {
                        val ev = awaitPointerEvent()
                        val ch = ev.changes.firstOrNull() ?: break
                        if (!ch.pressed) break
                        val travel = hypot(ch.position.x - down.position.x, ch.position.y - down.position.y)
                        if (onRim && (travel > 10 * density || moved)) {
                            moved = true
                            pressed = null
                            ch.consume()
                            val a = atan2((ch.position.y - c.y).toDouble(), (ch.position.x - c.x).toDouble())
                            spun += angleDelta(a, last)
                            last = a
                            val t = (start + spun / (2 * PI) * 30).coerceIn(0.0, latest.duration)
                            preview = t
                            val step = (t / 2).toInt()
                            if (step != tick) { tick = step; haptics.tick() }
                        }
                    }
                    val p = preview
                    if (p != null) {
                        env.player.seekSeconds(p)
                    } else when (zone) {
                        Zone.Menu -> queue()
                        Zone.Back -> env.player.previous()
                        Zone.Forward -> env.player.next()
                        Zone.Play, Zone.Hub -> env.player.togglePlay()
                    }
                    preview = null
                    pressed = null
                }
            }.semanticsButton(if (st.isPlaying) L("Pausar") else L("Reproducir")) { env.player.togglePlay() },
        )
    }
}

/** Esquina del panel: corona de puntos que se rellena al descargar; completa = disponible sin conexión. */
@Composable
private fun AirDownloadDots(song: Song, colors: AirColors, modifier: Modifier) {
    val env = LocalEnv.current
    val dl by env.library.downloads.collectAsState()
    val s = dl[song.id]
    val done = s?.isDone == true
    val busy = s?.isActive == true
    val pct = if (done) 1f else (s?.percent ?: 0f) / 100f
    Box(
        modifier.size(44.dp).tactile(enabled = !done && !busy, label = if (done) L("Descargada") else if (busy) L("Descargando") else L("Descargar")) { env.library.toggleDownload(song) },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(28.dp)) {
            val n = 12
            val r = 12.dp.toPx()
            for (i in 0 until n) {
                val on = i.toFloat() / n < pct
                val a = 2 * PI * i / n
                drawCircle(if (on) colors.ink else colors.dotOff, (if (on) 3.5f else 2.5f) / 2 * density, Offset(center.x + (r * sin(a)).toFloat(), center.y - (r * cos(a)).toFloat()))
            }
            if (done) drawCircle(colors.ink, 3.dp.toPx(), center)
        }
    }
}

// MARK: Miniatura -------------------------------------------------------------------------------

@Composable
fun MiniAirDisc(art: String?, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.aspectRatio(1f).background(Color(0xFFE7E9EC)), contentAlignment = Alignment.Center) {
        val s = maxWidth
        Canvas(Modifier.fillMaxSize()) {
            val r = size.width * 0.42f
            for (i in 0 until 20) {
                val a = 2 * PI * i / 20
                drawCircle(if (i < 7) Color(0xFF111214) else Color(0xFFA9AEB5), size.width * 0.025f, Offset(center.x + (r * sin(a)).toFloat(), center.y - (r * cos(a)).toFloat()))
            }
        }
        Box(Modifier.size(s * 0.72f).clip(CircleShape)) {
            CoverImage(art, Modifier.fillMaxSize().blur(s * 0.06f))
            Box(Modifier.fillMaxSize().background(Color(0xFFE7E9EC).copy(alpha = 0.35f)))
        }
        Box(
            Modifier.offset(s * 0.2f, -s * 0.2f).size(s * 0.2f).clip(CircleShape)
                .background(Brush.sweepGradient(Tokens.HoloRainbow)).border(s * 0.03f, Color.White, CircleShape),
        )
    }
}
