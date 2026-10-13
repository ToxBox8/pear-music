package app.libremusic.ui

import kotlinx.coroutines.launch

import androidx.compose.runtime.rememberCoroutineScope

import androidx.activity.result.contract.ActivityResultContracts

import androidx.activity.compose.rememberLauncherForActivityResult

import androidx.compose.material.icons.rounded.Backup

import androidx.compose.material.icons.rounded.CreateNewFolder

import app.libremusic.playback.Eq
import app.libremusic.playback.Fade

import androidx.compose.material.icons.rounded.Apps
import androidx.compose.ui.draw.scale
import androidx.compose.ui.layout.ContentScale
import androidx.compose.foundation.layout.imePadding
import androidx.compose.material.icons.rounded.BugReport
import app.libremusic.data.TabOrder
import app.libremusic.data.LocalSearch
import app.libremusic.ui.theme.rememberPalette
import app.libremusic.playback.MediaGraph
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material.icons.rounded.DownloadForOffline
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.BlurOn
import app.libremusic.ui.theme.ArtworkLevel
import app.libremusic.ui.theme.withArtwork
import kotlin.math.roundToInt
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Subscriptions
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.ui.zIndex
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.material.icons.rounded.DragHandle
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.Cast
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.LibraryBooks
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PlayCircle
import androidx.compose.material.icons.rounded.Restaurant
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import app.libremusic.ui.theme.material
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.libremusic.BuildConfig
import app.libremusic.R
import app.libremusic.ui.theme.AppTheme
import app.libremusic.ui.theme.BackdropPreview
import app.libremusic.ui.theme.DeckStyle
import app.libremusic.ui.theme.Libre
import app.libremusic.ui.theme.LibreColors
import app.libremusic.ui.theme.Prefs
import app.libremusic.ui.theme.ProvideLibre
import app.libremusic.ui.theme.ThemeBackdrop
import app.libremusic.ui.theme.Tokens
import app.libremusic.ui.theme.Typo
import app.libremusic.ui.theme.semibold
import app.libremusic.ui.theme.themeSurface

// Ajustes (Settings.swift): formularios agrupados como los de iOS sobre el fondo del tema.

// MARK: Piezas de formulario ----------------------------------------------------------------------

/**
 * Formulario con el aspecto nativo de iOS 26 (grupo blanco de esquinas grandes sobre gris) en vez de
 * tarjetas del tema: lo usan Sistema y las hojas que en iOS no llevan `.glassRow()` (Importar).
 */
val LocalNativeForm = compositionLocalOf { false }

/** Las filas dibujan su propia tarjeta (`.glassRow()` de iOS: una tarjeta por fila con los temas con estilo). */
private val LocalRowCards = compositionLocalOf { false }

/** Sección de formulario (Form de iOS 26): cabecera en gris y en negrita, grupo y pie. */
@Composable
fun FormSection(header: String?, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val c = Libre.colors
    val native = LocalNativeForm.current || !c.theme.styled
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = if (header != null) 18.dp else 26.dp)) {
        if (header != null) {
            Text(header, style = Typo.headline, color = c.secondaryLabel, modifier = Modifier.padding(start = 16.dp, bottom = 10.dp))
        }
        if (native) {
            val shape = RoundedCornerShape(Tokens.Radius.FormGroup.dp)
            Column(Modifier.fillMaxWidth().background(c.secondaryGrouped, shape).clip(shape), content = content)
        } else {
            CompositionLocalProvider(LocalRowCards provides true) { Column(Modifier.fillMaxWidth(), content = content) }
        }
        if (footer != null) {
            Text(footer, style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 10.dp))
        }
    }
}

/** Fila con contenido propio (un segmentado, un progreso…): lleva la tarjeta de fila igual que FormRow. */
@Composable
fun FormCustomRow(content: @Composable () -> Unit) {
    val c = Libre.colors
    val card = LocalRowCards.current
    Box(Modifier.fillMaxWidth().then(if (card) Modifier.themeSurface(Tokens.Radius.Row.dp, c) else Modifier)) { content() }
}

/**
 * Fila de formulario: icono opcional, título, valor y chevron (o check). Mide como en iOS 26:
 * 52 pt, o 58 con el icono de color de 30 pt.
 */
@Composable
fun FormRow(
    title: String,
    value: String? = null,
    /** Debajo del nombre: el valor actual o una frase que explica la opción. */
    subtitle: String? = null,
    icon: ImageVector? = null,
    iconPalette: Int? = null,
    tint: Color = Libre.colors.label,
    chevron: Boolean = false,
    checked: Boolean = false,
    last: Boolean = false,
    enabled: Boolean = true,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val c = Libre.colors
    val indent = if (iconPalette != null) 58.dp else if (icon != null) 56.dp else 16.dp
    val card = LocalRowCards.current
    Column(
        Modifier.fillMaxWidth()
            .then(if (card) Modifier.themeSurface(Tokens.Radius.Row.dp, c).clip(RoundedCornerShape(Tokens.Radius.Row.dp)) else Modifier)
            .then(if (onClick != null && enabled) Modifier.rowHighlight(onClick = onClick) else Modifier),
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = if (iconPalette != null) 58.dp else 52.dp).padding(horizontal = 16.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (iconPalette != null && icon != null) {
                GradientIcon(icon, iconPalette, 30.dp)
                Spacer(Modifier.width(12.dp))
            } else if (icon != null) {
                Icon(icon, null, tint = if (enabled) tint else c.tertiaryLabel, modifier = Modifier.size(26.dp))
                Spacer(Modifier.width(14.dp))
            }
            Column(Modifier.weight(1f).padding(vertical = if (subtitle != null) 4.dp else 0.dp)) {
                Text(title, style = Typo.body, color = if (enabled) (if (icon != null && iconPalette == null) tint else c.label) else c.tertiaryLabel)
                if (subtitle != null) Text(subtitle, style = Typo.footnote, color = c.secondaryLabel)
            }
            if (value != null) Text(value, style = Typo.body, color = c.secondaryLabel, maxLines = 1)
            if (trailing != null) trailing()
            if (checked) Icon(Icons.Rounded.Check, null, tint = c.accent, modifier = Modifier.size(20.dp))
            if (chevron) {
                Spacer(Modifier.width(6.dp))
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = c.tertiaryLabel, modifier = Modifier.size(20.dp))
            }
        }
        if (!last) Box(Modifier.fillMaxWidth().padding(start = indent).height(0.5.dp).background(c.separator))
    }
}

@Composable
fun FormTextField(value: String, onChange: (String) -> Unit, placeholder: String) {
    val c = Libre.colors
    Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
        if (value.isEmpty()) Text(placeholder, style = Typo.body, color = c.tertiaryLabel)
        BasicTextField(value, onChange, singleLine = true, textStyle = Typo.body.copy(color = c.label), cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth())
    }
}

/**
 * Cabecera de una hoja: título en línea y botón a la derecha («Listo», «Cerrar») en una cápsula de cristal,
 * como la barra de herramientas de iOS 26.
 */
@Composable
fun SheetHeader(title: String, trailing: String? = null, trailingEnabled: Boolean = true, onTrailing: () -> Unit = {}) {
    val c = Libre.colors
    Box(Modifier.fillMaxWidth().padding(top = 17.dp).height(44.dp).padding(horizontal = 16.dp)) {
        Text(title, style = Typo.headline, color = c.label, modifier = Modifier.align(Alignment.Center))
        if (trailing != null) ToolbarCapsule(trailing, Modifier.align(Alignment.CenterEnd), trailingEnabled, onTrailing)
    }
}

/** Botón de texto de la barra de herramientas de iOS 26: cápsula de cristal de 44 pt. */
@Composable
fun ToolbarCapsule(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val c = Libre.colors
    Box(
        modifier.height(44.dp).background(material(c.dark, thick = true), CircleShape)
            .tactile(enabled, text, onClick = onClick).padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = Typo.body, color = if (enabled) c.accent else c.tertiaryLabel)
    }
}

/** Pantalla de ajustes con fondo del tema y barra con «atrás». */
@Composable
internal fun SettingsPage(
    title: String,
    large: Boolean = false,
    /** Botón arriba a la derecha (el escarabajo de «Informar de un error» en Ajustes). */
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val env = LocalEnv.current
    val player by env.player.state.collectAsState()
    Box(Modifier.fillMaxSize()) {
        ThemeBackdrop(player.isPlaying, player.current, grouped = true)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding()) {
            if (large) {
                Box(Modifier.fillMaxWidth()) {
                    Column {
                        Spacer(Modifier.statusBarsPadding().height(37.5.dp))
                        LargeTitle(title, Modifier.offset(y = 19.5.dp))
                    }
                    if (trailing != null) Box(Modifier.align(Alignment.BottomEnd).padding(end = 12.dp).offset(y = 14.dp)) { trailing() }
                }
            } else {
                NavBar(title, onBack = { env.app.pop() }, trailing = trailing ?: {})
            }
            content()
            BottomSpacer(16.dp)
        }
    }
}

// MARK: Ajustes --------------------------------------------------------------------------------

/** Una entrada del buscador de Ajustes: dónde está cada opción. */
private data class SettingEntry(val title: String, val section: String, val keywords: String, val route: Route?)

private val settingsIndex = listOf(
    SettingEntry("Tema", "Aspecto", "color fondo cristal neón aire sistema apariencia", Route.ThemePicker),
    SettingEntry("Claro u oscuro", "Aspecto", "modo noche oscuro claro automático", Route.ThemePicker),
    SettingEntry("Reproductor", "Aspecto", "casete vinilo air normal", Route.PlayerPicker),
    SettingEntry("Efecto en los títulos", "Aspecto", "símbolos animación scramble", Route.PlayerPicker),
    SettingEntry("Colores de la portada", "Aspecto", "carátula color tinte sutil equilibrado intenso", Route.ArtworkColors),
    SettingEntry("Pestañas", "Aspecto", "orden barra descubrir inicio biblioteca", Route.TabOrderR),
    SettingEntry("Cristal líquido", "Aspecto", "glass transparente ios 26", Route.Appearance),
    SettingEntry("Icono de la app", "Aspecto", "logo encendido violeta lanzador", Route.AppIconR),
    SettingEntry("Calidad al escuchar", "Reproducción", "streaming datos ahorro máxima kbps", Route.Audio),
    SettingEntry("Seguir con canciones parecidas", "Reproducción", "radio infinita autoplay automático cola acabar", Route.Audio),
    SettingEntry("Copia automática", "Biblioteca", "copia seguridad backup drive nextcloud guardar exportar", Route.LibraryOptions),
    SettingEntry("Ecualizador", "Reproducción", "graves agudos voces bajos sonido eq altavoz", Route.Audio),
    SettingEntry("Fundido entre canciones", "Reproducción", "crossfade transición suave volumen cortes", Route.Audio),
    SettingEntry("Salida de audio", "Reproducción", "bluetooth chromecast altavoz airplay", Route.Audio),
    SettingEntry("Canciones descargadas", "Descargas", "espacio offline sin conexión borrar", Route.DownloadsSettings),
    SettingEntry("Ordenar playlists", "Biblioteca", "orden a-z recientes a mano", Route.LibraryOptions),
    SettingEntry("Descargadas y Favoritos", "Biblioteca", "carrusel tu música", Route.LibraryOptions),
    SettingEntry("Dónde está Buscar", "Biblioteca", "buscar pestaña inicio barra", Route.LibraryOptions),
    SettingEntry("Eliminar playlists", "Biblioteca", "borrar quitar", Route.ManagePlaylists),
    SettingEntry("Informar de un error", "Ayuda y soporte", "bug fallo problema soporte reporte escarabajo contacto", Route.Support(null)),
    SettingEntry("Guía inicial", "Ayuda y soporte", "tutorial bienvenida empezar", null),
    SettingEntry("Acerca de", "Ayuda y soporte", "versión créditos licencia", Route.About),
    SettingEntry("Vaciar caché de carátulas", "Avanzado", "memoria imágenes portadas", null),
    SettingEntry("Tolerancia de duración", "Avanzado", "emparejar importar spotify segundos coincidencia", null),
)

@Composable
fun SettingsScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val context = LocalContext.current
    val theme by Prefs.theme.collectAsState()
    val deck by Prefs.deck.collectAsState()
    val quality by Prefs.quality.collectAsState()
    val level by Prefs.artworkLevel.collectAsState()
    val artworkOn = Prefs.artworkColorsPlayer.collectAsState().value || Prefs.artworkColorsApp.collectAsState().value
    val sort by Prefs.playlistSort.collectAsState()
    val search by Prefs.searchPlacement.collectAsState()
    val downloaded by env.library.downloadedSongs.collectAsState()
    var query by rememberSaveable { mutableStateOf("") }
    var advanced by rememberSaveable { mutableStateOf(false) }
    val tolerance by Prefs.matchTolerance.collectAsState()
    var cleared by remember { mutableStateOf(false) }
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    SettingsPage("Ajustes", large = true, trailing = {
        IconTap(Icons.Rounded.BugReport, "Informar de un error", tint = c.accent) { env.app.push(Route.Support(null)) }
    }) {
        SearchField(query, { query = it }, { keyboard?.hide() }, Modifier.padding(start = 16.dp, end = 16.dp, top = 22.dp), placeholder = "Buscar en Ajustes")
        if (query.isNotBlank()) {
            val hits = LocalSearch.filter(settingsIndex, query) { "${it.title} ${it.section} ${it.keywords}" }
            if (hits.isEmpty()) CenterNote("Nada coincide con «${query.trim()}»", 40.dp)
            else FormSection(null) {
                hits.forEachIndexed { i, e ->
                    FormRow(e.title, subtitle = e.section, chevron = true, last = i == hits.lastIndex) {
                        keyboard?.hide()
                        when {
                            e.route != null -> env.app.push(e.route)
                            e.title == "Guía inicial" -> Prefs.setOnboarded(false)
                            else -> { advanced = true; query = "" }
                        }
                    }
                }
            }
            return@SettingsPage
        }
        FormSection(null) {
            FormRow(
                "Aspecto", subtitle = "${theme.title} · ${deck.title}" + if (artworkOn && level.enabled) " · Colores ${level.title.lowercase()}" else "",
                icon = Icons.Rounded.Palette, iconPalette = 1, chevron = true,
            ) { env.app.push(Route.Appearance) }
            FormRow(
                "Reproducción", subtitle = if (quality == "low") "Ahorro de datos" else "Calidad máxima",
                icon = Icons.Rounded.GraphicEq, iconPalette = 3, chevron = true,
            ) { env.app.push(Route.Audio) }
            FormRow(
                "Descargas", subtitle = if (downloaded.isEmpty()) "Ninguna canción descargada" else "${songCount(downloaded.size)} · " +
                    android.text.format.Formatter.formatShortFileSize(context, MediaGraph.downloadBytes(context)),
                icon = Icons.Rounded.DownloadForOffline, iconPalette = 2, chevron = true,
            ) { env.app.push(Route.DownloadsSettings) }
            FormRow(
                "Biblioteca", subtitle = "Playlists: " + sortTitle(sort).lowercase() + " · Buscar " + if (search == "tab") "en su pestaña" else "en Inicio",
                icon = Icons.Rounded.LibraryBooks, iconPalette = 0, chevron = true,
            ) { env.app.push(Route.LibraryOptions) }
            FormRow(
                "Ayuda y soporte", subtitle = "Informar de un error · Guía inicial · Versión ${BuildConfig.VERSION_NAME}",
                icon = Icons.Rounded.Info, iconPalette = 6, chevron = true, last = true,
            ) { env.app.push(Route.Help) }
        }
        // Lo técnico, plegado: sólo quien lo busca lo ve.
        FormSection(null, footer = if (advanced) "Las descargas se guardan siempre a la máxima calidad (AAC 128 kbps)." else null) {
            FormRow(
                "Avanzado", subtitle = if (advanced) null else "Calidad de descarga, tolerancia al importar y caché",
                last = !advanced,
                trailing = {
                    val turn by androidx.compose.animation.core.animateFloatAsState(if (advanced) 90f else 0f, uiEaseOut(200), label = "adv")
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = c.tertiaryLabel, modifier = Modifier.size(20.dp).graphicsLayer { rotationZ = turn })
                },
            ) { advanced = !advanced }
            if (advanced) {
                FormRow("Calidad de descarga", "Máxima", subtitle = "No se puede cambiar: así suenan igual sin conexión")
                FormRow("Tolerancia de duración", subtitle = "Al importar de Spotify o Apple Music, cuánto puede durar distinta una canción para darla por buena")
                FormCustomRow { Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp)) {
                    Segmented(listOf(2, 4, 6, 10).map { "$it" to "±$it s" }, "$tolerance") { Prefs.setMatchTolerance(it.toInt()) }
                } }
                FormRow(
                    if (cleared) "Caché vaciada" else "Vaciar caché de carátulas", subtitle = "Libera memoria; se vuelven a descargar al verlas",
                    tint = c.accent, last = true, enabled = !cleared,
                ) {
                    coil.Coil.imageLoader(context).memoryCache?.clear()
                    coil.Coil.imageLoader(context).diskCache?.clear()
                    cleared = true
                }
            }
        }
    }
}

private fun sortTitle(sort: String) = when (sort) { "name" -> "A-Z"; "nameDesc" -> "Z-A"; "count" -> "Por tamaño"; "custom" -> "A mano"; else -> "Recientes" }

/** «Restablecer» al final de una sección de Ajustes, con confirmación. */
@Composable
private fun ResetSection(section: String, what: String, reset: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    FormSection(null, footer = what) {
        FormRow("Restablecer $section", tint = c.destructive, icon = Icons.Rounded.RestartAlt, last = true) {
            env.app.alert = AlertSpec(
                "¿Restablecer $section?", what,
                buttons = listOf(
                    AlertButton("Restablecer", AlertButton.Role.Destructive) { reset() },
                    AlertButton("Cancelar", AlertButton.Role.Cancel),
                ),
            )
        }
    }
}

/**
 * Hueco para las previsualizaciones animadas de cada opción (Fase 4). Hoy enseña una imagen fija o nada;
 * cuando se hagan las animaciones, se cambian aquí y valen para todos los ajustes.
 */
@Composable
fun SettingPreview(modifier: Modifier = Modifier, content: @Composable () -> Unit = {}) {
    Box(modifier) { content() }
}

/** El panel de salida de audio de Android (equivale al selector de AirPlay). */
fun openOutputSwitcher(context: android.content.Context) {
    val intents = listOf(
        android.content.Intent("com.android.settings.panel.action.MEDIA_OUTPUT").putExtra("com.android.settings.panel.extra.PACKAGE_NAME", context.packageName),
        android.content.Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS),
    )
    for (i in intents) {
        if (runCatching { context.startActivity(i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) }.isSuccess) return
    }
}

@Composable
fun AppearanceScreen() {
    val env = LocalEnv.current
    val theme by Prefs.theme.collectAsState()
    val appearance by Prefs.appearance.collectAsState()
    val deck by Prefs.deck.collectAsState()
    val scramble by Prefs.scramble.collectAsState()
    val liquidGlass by Prefs.liquidGlass.collectAsState()
    val artworkPlayer by Prefs.artworkColorsPlayer.collectAsState()
    val artworkApp by Prefs.artworkColorsApp.collectAsState()
    val level by Prefs.artworkLevel.collectAsState()
    val tabOrder by Prefs.tabOrder.collectAsState()
    SettingsPage("Aspecto") {
        FormSection(null) {
            FormRow(
                "Tema", subtitle = theme.title + " · " + when (theme.forcedDark ?: appearance) { true, "dark" -> "oscuro"; false, "light" -> "claro"; else -> "claro u oscuro según el móvil" },
                icon = Icons.Rounded.Palette, iconPalette = 1, chevron = true,
            ) { env.app.push(Route.ThemePicker) }
            FormRow(
                "Reproductor", subtitle = deck.title + if (scramble) " · títulos con efecto" else "",
                icon = Icons.Rounded.PlayCircle, iconPalette = 0, chevron = true,
            ) { env.app.push(Route.PlayerPicker) }
            FormRow(
                "Colores de la portada",
                subtitle = if (!(artworkPlayer || artworkApp) || !level.enabled) "Desactivado" else level.title + " · " +
                    listOfNotNull("reproductor".takeIf { artworkPlayer }, "resto de la app".takeIf { artworkApp }).joinToString(" y "),
                icon = Icons.Rounded.AutoAwesome, iconPalette = 5, chevron = true,
            ) { env.app.push(Route.ArtworkColors) }
            FormRow(
                "Pestañas", subtitle = tabOrder.joinToString(", ") { Tab.of(it).title },
                icon = Icons.Rounded.SwapHoriz, iconPalette = 7, chevron = true,
            ) { env.app.push(Route.TabOrderR) }
            val context = LocalContext.current
            FormRow(
                "Icono de la app", subtitle = remember { app.libremusic.data.AppIcon.current(context) }.title,
                icon = Icons.Rounded.Apps, iconPalette = 3, chevron = true, last = true,
            ) { env.app.push(Route.AppIconR) }
        }
        // Sólo en Android: iOS 26 ya dibuja así sus barras y menús.
        FormSection(null) {
            FormRow(
                "Cristal líquido",
                subtitle = if (glassSupported) "Barras, botones y menús de cristal que refractan lo de detrás, como iOS 26" else "Necesita Android 12 o posterior",
                icon = Icons.Rounded.BlurOn, iconPalette = 4, last = true,
                trailing = { IosToggle(liquidGlass && glassSupported, Prefs::setLiquidGlass, enabled = glassSupported, label = "Cristal líquido") },
            )
        }
        ResetSection("Aspecto", "Vuelven el tema Cristal, el reproductor Normal, los colores de la portada apagados y el orden de pestañas de fábrica.") { Prefs.resetAppearance() }
    }
}

/** Colores de la portada (Fase 4B): dónde (reproductor y/o resto de la app) y cuánto (presets y barras). */
@Composable
fun ArtworkColorsScreen() {
    val c = Libre.colors
    val artworkPlayer by Prefs.artworkColorsPlayer.collectAsState()
    val artworkApp by Prefs.artworkColorsApp.collectAsState()
    val level by Prefs.artworkLevel.collectAsState()
    var custom by rememberSaveable { mutableStateOf(false) }
    val palette = rememberPalette()
    SettingsPage("Colores de la portada") {
        // Previsualización fija: el tema actual teñido con la portada que suena (o una de ejemplo).
        SettingPreview(Modifier.padding(start = 16.dp, end = 16.dp, top = 18.dp)) { ArtworkPreview(palette[0], level) }
        FormSection("Dónde", footer = "Al sonar una canción, la app y los menús toman colores parecidos a los de su portada, como Descubrir.") {
            FormRow("En el reproductor", subtitle = "Fondo con la carátula desenfocada y controles de su color", icon = Icons.Rounded.PlayCircle, iconPalette = 5, trailing = { IosToggle(artworkPlayer, Prefs::setArtworkColorsPlayer, label = "Colores de la portada en el reproductor") })
            FormRow("En el resto de la app", subtitle = "Botones del color de la canción y fondos y menús con un toque", icon = Icons.Rounded.Palette, iconPalette = 6, last = true, trailing = { IosToggle(artworkApp, Prefs::setArtworkColorsApp, label = "Colores de la portada en el resto de la app") })
        }
        FormSection("Cuánto", footer = "El texto y los iconos mantienen siempre un contraste legible, aunque la portada sea muy clara o muy viva.") {
            FormCustomRow { Box(Modifier.padding(horizontal = 12.dp, vertical = 15.dp)) {
                val presets = listOf("off" to "No") + ArtworkLevel.presets.map { it.first to it.first }
                val selected = if (!level.enabled) "off" else ArtworkLevel.presets.firstOrNull { it.first == level.title }?.first ?: ""
                Segmented(presets, selected) { key ->
                    Prefs.setArtworkLevel(if (key == "off") ArtworkLevel.Off else ArtworkLevel.presets.first { it.first == key }.second)
                }
            } }
            FormRow(
                "Ajuste fino", subtitle = if (level.title == "Personalizado") "Personalizado" else null, last = !custom,
                trailing = {
                    val turn by androidx.compose.animation.core.animateFloatAsState(if (custom) 90f else 0f, uiEaseOut(200), label = "fine")
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = c.tertiaryLabel, modifier = Modifier.size(20.dp).graphicsLayer { rotationZ = turn })
                },
            ) { custom = !custom }
            if (custom) {
                LevelSlider("Exageración del color", "Cuánto se parecen los botones al color de la portada", level.intensity) { Prefs.setArtworkLevel(level.copy(intensity = it)) }
                LevelSlider("Opacidad", "Cuánto se tiñen los fondos y los menús", level.opacity, last = true) { Prefs.setArtworkLevel(level.copy(opacity = it)) }
            }
        }
    }
}

@Composable
private fun LevelSlider(title: String, help: String, value: Float, last: Boolean = false, onChange: (Float) -> Unit) {
    val c = Libre.colors
    FormCustomRow {
        Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = if (last) 6.dp else 0.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, style = Typo.body, color = c.label, modifier = Modifier.weight(1f))
                Text("${(value * 100).roundToInt()} %", style = Typo.body, color = c.secondaryLabel)
            }
            Text(help, style = Typo.footnote, color = c.secondaryLabel)
            androidx.compose.material3.Slider(
                value, onChange, valueRange = 0f..1f,
                colors = androidx.compose.material3.SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = c.accent, inactiveTrackColor = c.fill),
                modifier = Modifier.semantics { contentDescription = title },
            )
            if (!last) Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.separator))
        }
    }
}

/** Una fila, un botón y un menú del tema actual, teñidos como quedarían con este nivel. */
@Composable
internal fun ArtworkPreview(art: Color, level: ArtworkLevel) {
    val base = Libre.colors
    val tinted = base.withArtwork(art, level)
    val shape = RoundedCornerShape(18.dp)
    ProvideLibre(tinted) {
        val c = Libre.colors
        Column(
            Modifier.fillMaxWidth().clip(shape).background(c.background).border(0.5.dp, c.separator, shape).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(44.dp).background(art, RoundedCornerShape(8.dp)))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("Canción que suena", style = Typo.callout.semibold, color = c.label)
                    Text("Artista", style = Typo.footnote, color = c.secondaryLabel)
                }
                Icon(Icons.Rounded.Favorite, null, tint = c.accent, modifier = Modifier.size(22.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f).height(36.dp).background(c.accent, CircleShape), contentAlignment = Alignment.Center) {
                    Text("Reproducir", style = Typo.subheadline.semibold, color = c.onAccent)
                }
                Box(Modifier.weight(1f).height(36.dp).background(c.secondaryGrouped, CircleShape), contentAlignment = Alignment.Center) {
                    Text("Menú", style = Typo.subheadline.semibold, color = c.label)
                }
            }
        }
    }
}

/** Orden de las pestañas (Fase 3): se arrastran; Ajustes se puede mover pero no quitar. */
@Composable
fun TabOrderScreen() {
    val c = Libre.colors
    val order by Prefs.tabOrder.collectAsState()
    val items = remember { androidx.compose.runtime.mutableStateListOf<String>() }
    LaunchedEffect(order) { if (items.toList() != order) { items.clear(); items.addAll(order) } }
    val rowPx = with(androidx.compose.ui.platform.LocalDensity.current) { 56.dp.toPx() }
    var dragging by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableStateOf(0f) }
    SettingsPage("Pestañas") {
        FormSection(
            "Orden de la barra",
            footer = "Arrastra ≡ para cambiar el orden; deslizar a los lados sigue el mismo orden. La app se abre en la última pestaña que usaste. Ajustes siempre está en la barra.",
        ) {
            items.forEachIndexed { i, key -> androidx.compose.runtime.key(key) {
                val isDragging = dragging == key
                val tab = Tab.of(key)
                Box(
                    Modifier.zIndex(if (isDragging) 1f else 0f).graphicsLayer {
                        translationY = if (isDragging) dragOffset else 0f
                        if (isDragging) { scaleX = 1.02f; scaleY = 1.02f; shadowElevation = 12.dp.toPx() }
                    },
                ) {
                    FormRow(
                        tab.title, icon = tab.settingsIcon(), tint = c.label, last = i == items.lastIndex,
                        trailing = {
                            Box(
                                Modifier.size(44.dp).semanticsButton("Mover ${tab.title}") {}.pointerInput(key) {
                                    detectDragGestures(
                                        onDragStart = { dragging = key; dragOffset = 0f },
                                        onDragEnd = { dragging = null; dragOffset = 0f; Prefs.setTabOrder(items.toList()) },
                                        onDragCancel = { dragging = null; dragOffset = 0f },
                                        onDrag = { change, amount ->
                                            change.consume()
                                            dragOffset += amount.y
                                            val from = items.indexOf(key)
                                            val to = (from + (dragOffset / rowPx).roundToInt()).coerceIn(0, items.lastIndex)
                                            if (to != from) { items.add(to, items.removeAt(from)); dragOffset -= (to - from) * rowPx }
                                        },
                                    )
                                },
                                contentAlignment = Alignment.Center,
                            ) { Icon(Icons.Rounded.DragHandle, null, tint = c.tertiaryLabel, modifier = Modifier.size(24.dp)) }
                        },
                    )
                }
            } }
        }
        FormSection(null) {
            FormRow("Orden de fábrica", subtitle = "Descubrir, Inicio, Biblioteca, Ajustes", tint = c.accent, last = true, enabled = order != TabOrder.DEFAULT) {
                Prefs.setTabOrder(TabOrder.DEFAULT)
            }
        }
    }
}

/** Icono de la app (Fase 5): el original de encendido (por defecto) o el violeta. */
@Composable
fun AppIconScreen() {
    val c = Libre.colors
    val context = LocalContext.current
    var current by remember { mutableStateOf(app.libremusic.data.AppIcon.current(context)) }
    SettingsPage("Icono de la app") {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 22.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            app.libremusic.data.AppIcon.entries.forEach { icon ->
                val on = icon == current
                Column(
                    Modifier.weight(1f).tactile(label = "Icono ${icon.title}") { app.libremusic.data.AppIcon.set(context, icon); current = icon },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    val shape = RoundedCornerShape(26.dp)
                    Box(
                        Modifier.size(112.dp).clip(shape).border(if (on) 3.dp else 1.dp, if (on) c.accent else c.separator, shape),
                        contentAlignment = Alignment.Center,
                    ) {
                        when (icon) {
                            app.libremusic.data.AppIcon.Power -> Box(Modifier.fillMaxSize().background(Color(0xFF07070A))) {
                                Image(painterResource(R.drawable.ic_launcher_power), null, Modifier.fillMaxSize().scale(1.5f))
                            }
                            app.libremusic.data.AppIcon.Violet -> Image(painterResource(R.mipmap.ic_launcher_full), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                    Text(icon.title + if (icon == app.libremusic.data.AppIcon.Power) " (original)" else "", style = Typo.subheadline.copy(fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal), color = c.label)
                    if (on) Icon(Icons.Rounded.CheckCircle, null, tint = c.accent, modifier = Modifier.padding(top = 6.dp).size(22.dp))
                }
            }
        }
        Text(
            "Android puede tardar unos segundos en cambiar el icono y, según el lanzador, quitar el acceso directo de la pantalla de inicio: vuelve a ponerlo desde el cajón de apps.",
            style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(start = 32.dp, end = 32.dp, top = 22.dp),
        )
    }
}

private fun Tab.settingsIcon(): ImageVector = when (this) {
    Tab.Home -> Icons.Rounded.Home
    Tab.Discover -> Icons.Rounded.Subscriptions
    Tab.Search -> Icons.Rounded.Search
    Tab.Library -> Icons.Rounded.LibraryMusic
    Tab.Settings -> Icons.Rounded.Settings
}

@Composable
fun SearchOptionsScreen() {
    val search by Prefs.searchPlacement.collectAsState()
    SettingsPage("Buscar") {
        FormSection(
            "Dónde buscar",
            footer = if (search == "tab") "Buscar tiene su propia pestaña en la barra de abajo."
            else "La barra de búsqueda está siempre arriba en Inicio y la pestaña Buscar desaparece.",
        ) {
            FormRow("Barra arriba en Inicio", icon = Icons.Rounded.Home, tint = Libre.colors.label, checked = search != "tab") { Prefs.setSearchPlacement("home") }
            FormRow("Pestaña aparte", icon = Icons.Rounded.Search, tint = Libre.colors.label, checked = search == "tab", last = true) { Prefs.setSearchPlacement("tab") }
        }
    }
}

@Composable
fun ThemePickerScreen() {
    val c = Libre.colors
    val current by Prefs.theme.collectAsState()
    val appearance by Prefs.appearance.collectAsState()
    SettingsPage("Tema") {
        Text("Tema", style = Typo.headline, color = c.secondaryLabel, modifier = Modifier.padding(start = 32.dp, top = 19.dp, bottom = 22.dp))
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            AppTheme.ordered.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    pair.forEach { t ->
                        Box(Modifier.weight(1f).tactile(label = t.title) { Prefs.setTheme(t) }) { ThemeCard(t, t == current) }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
        Text(
            "El tema cambia el fondo, las tarjetas, el color y la letra. Los fondos toman los colores de la carátula y se animan más mientras suena música.",
            style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(start = 32.dp, end = 32.dp, top = 17.dp),
        )
        FormSection("Claro u oscuro", footer = current.forcedDark?.let { "«${current.title}» usa siempre el modo ${if (it) "oscuro" else "claro"}." }) {
            FormCustomRow { Box(Modifier.padding(horizontal = 12.dp, vertical = 15.dp)) {
                Segmented(listOf("system" to "Automático", "light" to "Claro", "dark" to "Oscuro"), appearance, enabled = current.forcedDark == null) {
                    Prefs.setAppearance(it)
                }
            } }
        }
    }
}

/** Muestra de un tema: su fondo (fotograma fijo), una tarjeta con su letra y su acento. */
@Composable
internal fun ThemeCard(theme: AppTheme, selected: Boolean) {
    val c = Libre.colors
    val dark = theme.forcedDark ?: c.dark
    val shape = RoundedCornerShape(14.dp)
    Column {
        ProvideLibre(LibreColors.of(theme, dark)) {
            val tc = Libre.colors
            Box(
                Modifier.fillMaxWidth().height(118.dp).clip(shape)
                    .border(if (selected) 2.5.dp else 1.dp, if (selected) theme.accent else c.label.copy(alpha = 0.12f), shape),
            ) {
                BackdropPreview(theme, Modifier.fillMaxSize())
                Row(
                    Modifier.align(Alignment.BottomStart).padding(8.dp).themeSurface(10.dp, tc, theme).padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(8.dp).background(theme.accent, CircleShape))
                    Spacer(Modifier.width(6.dp))
                    Text("Aa", style = Typo.subheadline.semibold, color = tc.label)
                }
                if (selected) {
                    Icon(Icons.Rounded.CheckCircle, null, tint = theme.accent, modifier = Modifier.align(Alignment.TopEnd).padding(8.dp).size(22.dp).background(Color.White, CircleShape))
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(theme.title, style = Typo.subheadline.semibold, color = c.label)
        Text(theme.blurb, style = Typo.caption, color = c.secondaryLabel, maxLines = 2, minLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun PlayerPickerScreen() {
    val c = Libre.colors
    val scramble by Prefs.scramble.collectAsState()
    SettingsPage("Reproductor") {
        Text("REPRODUCTOR MULTIMEDIA", style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(start = 32.dp, top = 22.dp, bottom = 7.dp))
        DeckPicker(Modifier.padding(horizontal = 16.dp))
        Text(
            "Casete: gira una bobina o arrastra la cinta para avanzar o rebobinar. Vinilo: gira el disco con el dedo o mueve el brazo. Con el móvil en horizontal, el casete o el vinilo ocupan toda la pantalla. También puedes cambiarlo manteniendo pulsado el mini reproductor.",
            style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(start = 32.dp, end = 32.dp, top = 7.dp),
        )
        FormSection(null) {
            FormRow(
                "Efecto en los títulos", subtitle = "Al cambiar de canción, el título aparece entre símbolos que se ordenan",
                last = true, trailing = { IosToggle(scramble, Prefs::setScramble, label = "Efecto en los títulos") },
            )
        }
    }
}

/** Copia automática de la biblioteca en una carpeta (Google Drive, Nextcloud…), una al día. */
@Composable
private fun BackupSection() {
    val env = LocalEnv.current
    val context = LocalContext.current
    val st by app.libremusic.data.AutoBackup.state.collectAsState()
    val scope = rememberCoroutineScope()
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) scope.launch {
            runCatching { app.libremusic.data.AutoBackup.setFolder(context, env.library.library, uri) }
                .onSuccess { env.app.toast = "Copia guardada" }
                .onFailure { env.app.toast = "No se pudo usar esa carpeta" }
        }
    }
    FormSection(
        "Copia automática",
        footer = st.error ?: if (st.folder == null) "Una copia al día de tus favoritos, playlists y álbumes en la carpeta que elijas. Elige una que se sincronice (Google Drive, Nextcloud…) para no perder nada al cambiar de móvil."
        else "Se guarda una al día y se dejan las ${app.libremusic.data.AutoBackup.KEEP} últimas. Para recuperarla: Biblioteca › Importar › Importar copia.",
    ) {
        if (st.folder == null) {
            FormRow("Elegir carpeta", icon = Icons.Rounded.CreateNewFolder, tint = Libre.colors.accent, last = true) { pick.launch(null) }
        } else {
            FormRow("Carpeta", st.folderName ?: "Elegida", subtitle = st.lastDay?.let { "Última copia: $it" } ?: "Aún sin copia", chevron = true) { pick.launch(st.folder) }
            FormRow("Hacer copia ahora", icon = Icons.Rounded.Backup, tint = Libre.colors.accent) {
                scope.launch { env.app.toast = if (app.libremusic.data.AutoBackup.backup(context, env.library.library, force = true)) "Copia guardada" else "No se pudo guardar la copia" }
            }
            FormRow("Desactivar", tint = Libre.colors.destructive, last = true) { app.libremusic.data.AutoBackup.disable(context) }
        }
    }
}

/** Ajustes: elegir reproductor (DeckPicker en iOS). */
@Composable
fun DeckPicker(modifier: Modifier = Modifier) {
    val c = Libre.colors
    val env = LocalEnv.current
    val deck by Prefs.deck.collectAsState()
    val player by env.player.state.collectAsState()
    Row(modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        DeckStyle.entries.forEach { d ->
            val on = d == deck
            Column(Modifier.weight(1f).tactile(label = d.title) { Prefs.setDeck(d) }, horizontalAlignment = Alignment.CenterHorizontally) {
                val shape = RoundedCornerShape(14.dp)
                Box(
                    Modifier.size(76.dp).themeSurface(14.dp, c).border(2.5.dp, if (on) c.accent else Color.Transparent, shape).clip(shape),
                    contentAlignment = Alignment.Center,
                ) {
                    when (d) {
                        DeckStyle.Normal -> Icon(Icons.Rounded.PlayArrow, null, tint = c.accent, modifier = Modifier.size(30.dp))
                        DeckStyle.Cassette -> MiniCassette(false, Modifier.size(76.dp).clip(RoundedCornerShape(10.dp)))
                        DeckStyle.Vinyl -> MiniVinyl(false, player.current?.thumb(240), Modifier.size(76.dp).clip(RoundedCornerShape(10.dp)))
                        DeckStyle.Air -> MiniAirDisc(player.current?.thumb(240), Modifier.size(76.dp).clip(RoundedCornerShape(10.dp)))
                    }
                }
                Spacer(Modifier.height(8.dp))
                Text(d.title, style = Typo.subheadline.copy(fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal), color = c.label)
            }
        }
    }
}

@Composable
fun LibraryOptionsScreen() {
    val env = LocalEnv.current
    val sort by Prefs.playlistSort.collectAsState()
    val placement by Prefs.smartPlacement.collectAsState()
    val search by Prefs.searchPlacement.collectAsState()
    SettingsPage("Biblioteca") {
        FormSection("Ordenar playlists por") {
            FormRow("Añadidas recientemente", checked = sort == "recent") { Prefs.setPlaylistSort("recent") }
            FormRow("Nombre (A-Z)", checked = sort == "name") { Prefs.setPlaylistSort("name") }
            FormRow("Nombre (Z-A)", checked = sort == "nameDesc") { Prefs.setPlaylistSort("nameDesc") }
            FormRow("Nº de canciones", checked = sort == "count") { Prefs.setPlaylistSort("count") }
            FormRow("A mano", checked = sort == "custom", last = true) { Prefs.setPlaylistSort("custom") }
        }
        FormSection(null, footer = "Arrastra las playlists, Descargadas y Favoritos para colocarlas donde quieras.") {
            FormRow("Ordenar a mano", icon = Icons.Rounded.DragHandle, tint = Libre.colors.accent, chevron = true, last = true) { env.app.push(Route.ReorderPlaylists) }
        }
        FormSection(
            "Descargadas y Favoritos",
            footer = if (placement == "music") "Aparecen como filas en «Tu música», encima de Canciones." else "Aparecen con su portada grande en el carrusel de Playlists.",
        ) {
            FormRow("En Playlists (portada grande)", checked = placement != "music") { Prefs.setSmartPlacement("playlists") }
            FormRow("En «Tu música» (fila)", checked = placement == "music", last = true) { Prefs.setSmartPlacement("music") }
        }
        FormSection(
            "Dónde está Buscar",
            footer = if (search == "tab") "Buscar tiene su propia pestaña en la barra de abajo, justo después de Inicio."
            else "La barra de búsqueda está siempre arriba en Inicio.",
        ) {
            FormRow("Barra arriba en Inicio", checked = search != "tab") { Prefs.setSearchPlacement("home") }
            FormRow("Pestaña aparte", checked = search == "tab", last = true) { Prefs.setSearchPlacement("tab") }
        }
        BackupSection()
        FormSection(null, footer = "Antes de borrar se pide confirmación.") {
            FormRow("Eliminar playlists", icon = Icons.Rounded.Delete, tint = Libre.colors.destructive, chevron = true, last = true) { env.app.push(Route.ManagePlaylists) }
        }
        ResetSection("Biblioteca", "Las playlists vuelven a ordenarse por recientes, Descargadas y Favoritos al carrusel y Buscar a Inicio. No se borra ninguna playlist.") { Prefs.resetLibrary() }
    }
}

@Composable
fun AudioScreen() {
    val quality by Prefs.quality.collectAsState()
    val crossfade by Prefs.crossfade.collectAsState()
    val equalizer by Prefs.equalizer.collectAsState()
    val autoplay by Prefs.autoplay.collectAsState()
    val context = LocalContext.current
    SettingsPage("Reproducción") {
        FormSection("Calidad al escuchar", footer = "«Máxima» usa AAC a 128 kbps; «Ahorro de datos», 48 kbps. Se aplica desde la siguiente canción.") {
            FormRow("Máxima", subtitle = "Mejor sonido; gasta más datos", checked = quality == "max") { Prefs.setQuality("max") }
            FormRow("Ahorro de datos", subtitle = "Para escuchar con datos móviles", checked = quality == "low", last = true) { Prefs.setQuality("low") }
        }
        FormSection(null, footer = "Cuando se acaba lo que estás escuchando y el bucle está apagado, se añaden canciones parecidas a la última.") {
            FormRow("Seguir con canciones parecidas", last = true, trailing = { IosToggle(autoplay, { Prefs.setAutoplay(it) }, label = "Seguir con canciones parecidas") })
        }
        FormSection("Ecualizador", footer = "Se aplica al momento, también a lo que suena por Bluetooth.") {
            Eq.Preset.entries.forEachIndexed { i, p ->
                FormRow(p.title, subtitle = p.subtitle, checked = equalizer == p, last = i == Eq.Preset.entries.lastIndex) { Prefs.setEqualizer(p) }
            }
        }
        FormSection("Fundido entre canciones", footer = if (crossfade == 0) "Cada canción empieza y acaba a su volumen." else "La canción baja de volumen en sus últimos $crossfade s y la siguiente entra suavemente. Útil para listas variadas; en álbumes que van seguidos, mejor «No».") {
            FormCustomRow {
                Box(Modifier.padding(16.dp, 12.dp)) {
                    Segmented(Fade.options.map { "$it" to if (it == 0) "No" else "$it s" }, "$crossfade") { Prefs.setCrossfade(it.toInt()) }
                }
            }
        }
        FormSection(null, footer = "El bucle (no repetir, repetir lista o canción) se cambia en el reproductor.") {
            FormRow(
                "Salida de audio", subtitle = "Altavoces, auriculares y televisores con Bluetooth o Chromecast",
                icon = Icons.Rounded.Cast, iconPalette = 7, chevron = true, last = true,
            ) { openOutputSwitcher(context) }
        }
        ResetSection("Reproducción", "La calidad al escuchar vuelve a «Máxima» y se quitan el ecualizador y el fundido; se vuelve a seguir con canciones parecidas.") { Prefs.resetPlayback() }
    }
}

@Composable
fun DownloadsSettingsScreen() {
    val env = LocalEnv.current
    val downloaded by env.library.downloadedSongs.collectAsState()
    val context = LocalContext.current
    SettingsPage("Descargas") {
        FormSection(null, footer = "Las descargas se guardan en este móvil a la máxima calidad y se ven en Biblioteca › Descargadas. Para bajar una lista o un álbum entero, usa «Descargar todo» en su página.") {
            FormRow("Canciones", "${downloaded.size}")
            FormRow(
                "Espacio usado", android.text.format.Formatter.formatShortFileSize(context, MediaGraph.downloadBytes(context)),
                last = true,
            )
        }
        if (downloaded.isNotEmpty()) {
            FormSection(null, footer = "Dejarán de estar disponibles sin conexión. Las playlists y los favoritos no se tocan.") {
                FormCustomRow {
                    Box(Modifier.padding(16.dp, 8.dp)) {
                        HoldToConfirmButton("Mantén para borrar las descargas") { downloaded.forEach { env.library.removeDownload(it) } }
                    }
                }
            }
        }
    }
}

@Composable
fun HelpScreen() {
    val env = LocalEnv.current
    SettingsPage("Ayuda y soporte") {
        FormSection(null) {
            FormRow("Informar de un error", subtitle = "Cuéntanos qué ha fallado; puedes añadir capturas", icon = Icons.Rounded.BugReport, iconPalette = 0, chevron = true) {
                env.app.push(Route.Support(null))
            }
            FormRow("Guía inicial", subtitle = "Vuelve a ver los tres pasos del principio: tema, colores y descargas", icon = Icons.Rounded.School, iconPalette = 2, chevron = true) {
                Prefs.setOnboarded(false)
            }
            FormRow("Acerca de", subtitle = "Versión ${BuildConfig.VERSION_NAME} y créditos", icon = Icons.Rounded.Info, iconPalette = 6, chevron = true, last = true) {
                env.app.push(Route.About)
            }
        }
    }
}

@Composable
fun AboutScreen() {
    val c = Libre.colors
    val uri = LocalUriHandler.current
    SettingsPage("Acerca de") {
        Column(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Image(
                painterResource(R.drawable.logo), null,
                Modifier.size(96.dp).shadowSoft(10.dp, RoundedCornerShape(22.dp), 0.2f).clip(RoundedCornerShape(22.dp)),
            )
            Spacer(Modifier.height(10.dp))
            Text("LibreMusic", style = Typo.title2, color = c.label)
            Text("Versión ${BuildConfig.VERSION_NAME}", style = Typo.subheadline, color = c.secondaryLabel)
        }
        FormSection(null) {
            Text(
                "Cliente no oficial de YouTube Music. Usa una API no oficial de YouTube, así que puede dejar de funcionar si YouTube la cambia. Las descargas se guardan en este móvil.",
                style = Typo.subheadline, color = c.label, modifier = Modifier.padding(16.dp, 12.dp),
            )
        }
        FormSection("Créditos") {
            FormRow("Componentes inspirados en The Kitchen de dqnamo", icon = Icons.Rounded.Restaurant, tint = c.accent) { uri.openUri("https://www.dqnamo.com/kitchen") }
            FormRow("Letra Inter, de Rasmus Andersson (OFL)", icon = Icons.Rounded.Album, tint = c.accent, last = true) { uri.openUri("https://rsms.me/inter/") }
        }
    }
}

@Composable
fun ManagePlaylistsScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    SettingsPage("Eliminar playlists") {
        if (data.playlists.isEmpty()) {
            CenterNote("No hay playlists", 60.dp)
        } else {
            FormSection(null, footer = "Eliminar una playlist no borra sus canciones de Favoritos ni de Descargas.") {
                data.playlists.forEachIndexed { i, p ->
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        PlaylistCover(p, 44.dp, coverFile = env.library.coverFile(p.id), coverVersion = ver)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(p.name, style = Typo.body, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(songCount(p.songs.size), style = Typo.caption, color = c.secondaryLabel)
                        }
                            IconTap(Icons.Rounded.Delete, "Eliminar ${p.name}", tint = c.destructive) {
                                env.app.alert = AlertSpec(
                                    "¿Eliminar «${p.name}»?", "Se borrará la playlist y su portada. No se puede deshacer.",
                                    buttons = listOf(
                                        AlertButton("Eliminar playlist", AlertButton.Role.Destructive) { env.library.deletePlaylist(p.id) },
                                        AlertButton("Cancelar", AlertButton.Role.Cancel),
                                    ),
                                )
                            }
                    }
                    if (i < data.playlists.lastIndex) Box(Modifier.fillMaxWidth().padding(start = 72.dp).height(0.5.dp).background(c.separator))
                }
            }
        }
    }
}
