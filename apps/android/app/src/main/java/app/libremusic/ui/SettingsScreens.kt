package app.libremusic.ui

import androidx.compose.material.icons.rounded.Language


import app.libremusic.L
import androidx.compose.material.icons.rounded.Mail

import androidx.compose.material.icons.rounded.MarkunreadMailbox

import androidx.compose.material.icons.rounded.Widgets
import kotlinx.coroutines.launch
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.semantics.customActions

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
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.AdminPanelSettings
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
import androidx.compose.material.icons.rounded.Notifications
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
internal val LocalRowCards = compositionLocalOf { false }

/** Sección de formulario (Form de iOS 26): cabecera en gris y en negrita, grupo y pie. */
@Composable
fun FormSection(header: String?, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val c = Libre.colors
    val native = LocalNativeForm.current || !c.theme.styled
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = if (header != null) 18.dp else 26.dp)
            .then(if (header != null) Modifier.tourTarget(sectionKey(header)) else Modifier),
    ) {
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
            .tourTarget(rowKey(title)) // la guía de Ajustes puede resaltar cualquier fila
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
fun FormTextField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    keyboard: androidx.compose.foundation.text.KeyboardOptions = androidx.compose.foundation.text.KeyboardOptions.Default,
    mono: Boolean = false,
) {
    val c = Libre.colors
    Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
        if (value.isEmpty()) Text(placeholder, style = Typo.body, color = c.tertiaryLabel)
        BasicTextField(
            value, onChange, singleLine = true, keyboardOptions = keyboard,
            textStyle = Typo.body.copy(color = c.label, fontFamily = if (mono) androidx.compose.ui.text.font.FontFamily.Monospace else Typo.body.fontFamily),
            cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth(),
        )
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
    val player by env.player.track.collectAsState()
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

private val settingsIndex get() = listOf(
    SettingEntry(L("Avisos"), L("Ayuda y soporte"), L("notificaciones campana caídas novedades discord"), Route.Avisos),
    SettingEntry(L("Idioma"), L("Ajustes"), L("idioma lengua language català valencià galego euskara english esperanto"), Route.Language),
    SettingEntry(L("Widgets"), L("Ajustes"), L("widgets widget personalización pantalla de inicio escritorio ahora suena recientes accesos rápidos playlist fijada tema"), Route.Personalization),
    SettingEntry(L("Cuenta"), L("Ajustes"), L("cuenta correo nube sincronizar copia cifrada clave recuperación iniciar sesión"), Route.AccountR),
    SettingEntry(L("Telemetría"), L("Ayuda y soporte"), L("telemetría rendimiento datos consentimiento privacidad fps"), Route.MyData),
    SettingEntry(L("Tus datos"), L("Ayuda y soporte"), L("privacidad rgpd exportar borrar datos eliminar zip"), Route.MyData),
    SettingEntry(L("Tema"), L("Aspecto"), L("color fondo cristal neón aire sistema apariencia"), Route.ThemePicker),
    SettingEntry(L("Claro u oscuro"), L("Aspecto"), L("modo noche oscuro claro automático"), Route.ThemePicker),
    SettingEntry(L("Reproductor"), L("Aspecto"), L("casete vinilo air normal"), Route.PlayerPicker),
    SettingEntry(L("Efecto en los títulos"), L("Aspecto"), L("símbolos animación scramble"), Route.PlayerPicker),
    SettingEntry(L("Colores de la portada"), L("Aspecto"), L("carátula color tinte sutil equilibrado intenso"), Route.ArtworkColors),
    SettingEntry(L("Pestañas"), L("Barra"), L("orden barra descubrir inicio biblioteca"), Route.TabOrderR),
    SettingEntry(L("Descubrir"), L("Barra"), L("ocultar quitar desactivar descubrir feed fragmentos reels"), Route.TabOrderR),
    SettingEntry(L("Cristal líquido"), L("Barra"), L("glass transparente ios 26"), Route.BarR),
    SettingEntry(L("Barra inferior"), L("Aspecto"), L("barra simpmusic cápsula pestañas plegar gota"), Route.BarR),
    SettingEntry(L("Buscar vuelve al parar"), L("Barra"), L("barra simpmusic plegar buscar"), Route.BarR),
    SettingEntry(L("Calidad al escuchar"), L("Reproducción"), L("streaming datos ahorro máxima kbps"), Route.Audio),
    SettingEntry(L("Seguir con canciones parecidas"), L("Reproducción"), L("radio infinita autoplay automático cola acabar"), Route.Audio),
    SettingEntry(L("Copia automática"), L("Biblioteca"), L("copia seguridad backup drive nextcloud guardar exportar"), Route.LibraryOptions),
    SettingEntry(L("Ecualizador"), L("Reproducción"), L("graves agudos voces bajos sonido eq altavoz"), Route.Audio),
    SettingEntry(L("Fundido entre canciones"), L("Reproducción"), L("crossfade transición suave volumen cortes"), Route.Audio),
    SettingEntry(L("Salida de audio"), L("Reproducción"), L("bluetooth chromecast altavoz airplay"), Route.Audio),
    SettingEntry(L("Canciones descargadas"), L("Descargas"), L("espacio offline sin conexión borrar"), Route.DownloadsSettings),
    SettingEntry(L("Ordenar playlists"), L("Biblioteca"), L("orden a-z recientes a mano"), Route.LibraryOptions),
    SettingEntry(L("Descargadas y Favoritos"), L("Biblioteca"), L("carrusel tu música"), Route.LibraryOptions),
    SettingEntry(L("Dónde está Buscar"), L("Barra"), L("buscar pestaña inicio barra"), Route.BarR),
    SettingEntry(L("Eliminar playlists"), L("Biblioteca"), L("borrar quitar"), Route.ManagePlaylists),
    SettingEntry(L("Informar de un error"), L("Ayuda y soporte"), L("bug fallo problema soporte reporte escarabajo contacto"), Route.Support(null)),
    SettingEntry(L("Buzón de sugerencias"), L("Ayuda y soporte"), L("sugerencia idea propuesta mejora buzón"), Route.Suggest(null)),
    SettingEntry(L("Guía inicial"), L("Ayuda y soporte"), L("tutorial bienvenida empezar"), null),
    SettingEntry(L("Acerca de"), L("Ayuda y soporte"), L("versión créditos licencia"), Route.About),
    SettingEntry(L("Vaciar caché de carátulas"), L("Avanzado"), L("memoria imágenes portadas"), null),
    SettingEntry(L("Tolerancia de duración"), L("Avanzado"), L("emparejar importar spotify segundos coincidencia"), null),
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
    SettingsPage(L("Ajustes"), large = true, trailing = {
        // Carta junto al escarabajo: el buzón de sugerencias (lo pidió Toxbox).
        Row {
            // Guía de Ajustes (1.1): recorre todas las opciones explicándolas.
            Box(Modifier.tourTarget("settings:guide")) {
                IconTap(Icons.Rounded.School, L("Guía de Ajustes"), tint = c.accent) { env.app.guide = "settings" }
            }
            Box(Modifier.tourTarget("settings:mail")) {
                IconTap(Icons.Rounded.Mail, L("Buzón de sugerencias"), tint = c.accent) { env.app.push(Route.Suggest(null)) }
            }
            IconTap(Icons.Rounded.BugReport, L("Informar de un error"), tint = c.accent) { env.app.push(Route.Support(null)) }
        }
    }) {
        SearchField(query, { query = it }, { keyboard?.hide() }, Modifier.padding(start = 16.dp, end = 16.dp, top = 22.dp).tourTarget("settings:search"), placeholder = L("Buscar en Ajustes"))
        if (query.isNotBlank()) {
            val hits = LocalSearch.filter(settingsIndex, query) { "${it.title} ${it.section} ${it.keywords}" }
            if (hits.isEmpty()) CenterNote(L("Nada coincide con «{0}»", query.trim()), 40.dp)
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
        val account by app.libremusic.data.Account.state.collectAsState()
        FormSection(null) {
            FormRow(
                L("Cuenta"), subtitle = account.email ?: L("Opcional · guarda tu biblioteca cifrada en la nube"),
                icon = Icons.Rounded.AccountCircle, iconPalette = 4, chevron = true, last = true,
            ) { env.app.push(Route.AccountR) }
        }
        FormSection(null) {
            FormRow(
                L("Aspecto"), subtitle = "${theme.title} · ${deck.title}" + if (artworkOn && level.enabled) L(" · Colores {0}", level.title.lowercase()) else "",
                icon = Icons.Rounded.Palette, iconPalette = 1, chevron = true,
            ) { env.app.push(Route.Appearance) }
            // Idioma (Cierre 1.0).
            FormRow(
                L("Idioma"), subtitle = app.libremusic.I18n.LANGS.first { it.code == app.libremusic.I18n.lang.value }.name,
                icon = Icons.Rounded.Language, iconPalette = 3, chevron = true,
            ) { env.app.push(Route.Language) }
            FormRow(
                L("Widgets"), subtitle = L("Para la pantalla de inicio del móvil"),
                icon = Icons.Rounded.Widgets, iconPalette = 2, chevron = true,
            ) { env.app.push(Route.Personalization) }
            FormRow(
                L("Reproducción"), subtitle = if (quality == "low") L("Ahorro de datos") else L("Calidad máxima"),
                icon = Icons.Rounded.GraphicEq, iconPalette = 3, chevron = true,
            ) { env.app.push(Route.Audio) }
            FormRow(
                L("Descargas"), subtitle = if (downloaded.isEmpty()) L("Ninguna canción descargada") else "${songCount(downloaded.size)} · " +
                    android.text.format.Formatter.formatShortFileSize(context, MediaGraph.downloadBytes(context)),
                icon = Icons.Rounded.DownloadForOffline, iconPalette = 2, chevron = true,
            ) { env.app.push(Route.DownloadsSettings) }
            FormRow(
                L("Biblioteca"), subtitle = L("Playlists: ") + sortTitle(sort).lowercase() + L(" · Buscar ") + if (search == "tab") L("en su pestaña") else L("en Inicio"),
                icon = Icons.Rounded.LibraryBooks, iconPalette = 0, chevron = true,
            ) { env.app.push(Route.LibraryOptions) }
            FormRow(
                L("Ayuda y soporte"), subtitle = L("Informar de un error · Guía inicial · Versión {0}", BuildConfig.VERSION_NAME),
                icon = Icons.Rounded.Info, iconPalette = 6, chevron = true, last = true,
            ) { env.app.push(Route.Help) }
        }
        // Lo técnico, plegado: sólo quien lo busca lo ve.
        FormSection(null, footer = if (advanced) L("Las descargas se guardan siempre a la máxima calidad (Opus, unos 160 kbps).") else null) {
            FormRow(
                L("Avanzado"), subtitle = if (advanced) null else L("Calidad de descarga, tolerancia al importar y caché"),
                last = !advanced,
                trailing = {
                    val turn by androidx.compose.animation.core.animateFloatAsState(if (advanced) 90f else 0f, uiEaseOut(200), label = "adv")
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = c.tertiaryLabel, modifier = Modifier.size(20.dp).graphicsLayer { rotationZ = turn })
                },
            ) { advanced = !advanced }
            if (advanced) {
                FormRow(L("Calidad de descarga"), L("Máxima"), subtitle = L("No se puede cambiar: así suenan igual sin conexión"))
                FormRow(L("Tolerancia de duración"), subtitle = L("Al importar de Spotify o Apple Music, cuánto puede durar distinta una canción para darla por buena"))
                FormCustomRow { Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp)) {
                    Segmented(listOf(2, 4, 6, 10).map { "$it" to "±$it s" }, "$tolerance") { Prefs.setMatchTolerance(it.toInt()) }
                } }
                FormRow(
                    if (cleared) L("Caché vaciada") else L("Vaciar caché de carátulas"), subtitle = L("Libera memoria; se vuelven a descargar al verlas"),
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

private fun sortTitle(sort: String) = when (sort) { "name" -> "A-Z"; "nameDesc" -> "Z-A"; "count" -> L("Por tamaño"); "custom" -> L("A mano"); else -> L("Recientes") }

/** «Restablecer» al final de una sección de Ajustes, con confirmación. */
@Composable
private fun ResetSection(section: String, what: String, reset: () -> Unit) {
    val c = Libre.colors
    val env = LocalEnv.current
    FormSection(null, footer = what) {
        FormRow(L("Restablecer {0}", section), tint = c.destructive, icon = Icons.Rounded.RestartAlt, last = true) {
            env.app.alert = AlertSpec(
                L("¿Restablecer {0}?", section), what,
                buttons = listOf(
                    AlertButton(L("Restablecer"), AlertButton.Role.Destructive) { reset() },
                    AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
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
    val showDiscover by Prefs.showDiscover.collectAsState()
    val barStyle by Prefs.barStyle.collectAsState()
    SettingsPage(L("Aspecto")) {
        FormSection(null) {
            FormRow(
                L("Tema"), subtitle = theme.title + " · " + when (theme.forcedDark ?: appearance) { true, "dark" -> "oscuro"; false, "light" -> "claro"; else -> L("claro u oscuro según el móvil") },
                icon = Icons.Rounded.Palette, iconPalette = 1, chevron = true,
            ) { env.app.push(Route.ThemePicker) }
            FormRow(
                L("Reproductor"), subtitle = deck.title + if (scramble) L(" · títulos con efecto") else "",
                icon = Icons.Rounded.PlayCircle, iconPalette = 0, chevron = true,
            ) { env.app.push(Route.PlayerPicker) }
            FormRow(
                L("Colores de la portada"),
                subtitle = if (!(artworkPlayer || artworkApp) || !level.enabled) L("Desactivado") else level.title + " · " +
                    listOfNotNull("reproductor".takeIf { artworkPlayer }, L("resto de la app").takeIf { artworkApp }).joinToString(" y "),
                icon = Icons.Rounded.AutoAwesome, iconPalette = 5, chevron = true,
            ) { env.app.push(Route.ArtworkColors) }
            // Barra (2.11 de x.1.1): estilo, dónde va Buscar, si vuelve al parar, cristal líquido y pestañas.
            FormRow(
                L("Barra"),
                subtitle = (if (barStyle == "simpmusic") L("Estilo SimpMusic") else L("Clásica")) + " · " +
                    app.libremusic.data.TabOrder.visible(tabOrder, false, showDiscover).filter { it != app.libremusic.data.TabOrder.SETTINGS }.joinToString(", ") { Tab.of(it).title } +
                    if (liquidGlass && glassSupported) L(" · cristal líquido") else "",
                icon = Icons.Rounded.SwapHoriz, iconPalette = 7, chevron = true, last = true,
            ) { env.app.push(Route.BarR) }
        }
        ResetSection(L("Aspecto"), L("Vuelven el tema Cristal, el reproductor Normal, los colores de la portada apagados y el orden de pestañas de fábrica.")) { Prefs.resetAppearance() }
    }
}

/**
 * Barra (2.11 de x.1.1): todo lo de la barra de abajo junto. Sólo se ven las opciones del estilo elegido. El cristal
 * líquido y las pestañas van aquí porque son parte de la barra; en iOS no hay cristal propio (lo pone el sistema).
 */
@Composable
fun BarScreen() {
    val env = LocalEnv.current
    val barStyle by Prefs.barStyle.collectAsState()
    val search by Prefs.searchPlacement.collectAsState()
    val restoreIdle by Prefs.barRestoreIdle.collectAsState()
    val liquidGlass by Prefs.liquidGlass.collectAsState()
    val tabOrder by Prefs.tabOrder.collectAsState()
    SettingsPage(L("Barra")) {
        FormSection(
            L("Barra inferior"),
            footer = if (barStyle == "simpmusic") L("Cápsula con tus pestañas y Buscar aparte, como SimpMusic. Arrastra la gota para cambiar de pestaña; al bajar por una lista se pliega junto al mini reproductor.")
            else L("Las pestañas de siempre, como en el iPhone."),
        ) {
            Box(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                Segmented(listOf("classic" to L("Clásica"), "simpmusic" to L("Estilo SimpMusic")), barStyle) { Prefs.setBarStyle(it) }
            }
        }
        if (barStyle == "simpmusic") {
            FormSection(
                L("Dónde está Buscar"),
                footer = L("Buscar es el círculo de la derecha. Al bajar por Inicio la barra se pliega; si dejas de moverte 1,5 segundos, vuelve entera."),
            ) {
                FormRow(L("Buscar vuelve al parar"), last = true, trailing = { IosToggle(restoreIdle, Prefs::setBarRestoreIdle, label = L("Buscar vuelve al parar")) })
            }
        } else {
            FormSection(
                L("Dónde está Buscar"),
                footer = if (search == "tab") L("Buscar tiene su propia pestaña en la barra de abajo, justo después de Inicio.")
                else L("La barra de búsqueda está siempre arriba en Inicio."),
            ) {
                FormRow(L("Barra arriba en Inicio"), checked = search != "tab") { Prefs.setSearchPlacement("home") }
                FormRow(L("Pestaña aparte"), checked = search == "tab", last = true) { Prefs.setSearchPlacement("tab") }
            }
        }
        // Sólo en Android: iOS 26 ya dibuja así sus barras y menús. Pestañas va dentro, porque es parte de la barra.
        FormSection(null) {
            FormRow(
                L("Cristal líquido"),
                subtitle = if (glassSupported) L("Barras, botones y menús de cristal que refractan lo de detrás, como iOS 26") else L("Necesita Android 12 o posterior"),
                icon = Icons.Rounded.BlurOn, iconPalette = 4,
                trailing = { IosToggle(liquidGlass && glassSupported, Prefs::setLiquidGlass, enabled = glassSupported, label = L("Cristal líquido")) },
            )
            FormRow(
                L("Pestañas"), subtitle = tabOrder.filter { it != app.libremusic.data.TabOrder.SETTINGS }.joinToString(", ") { Tab.of(it).title },
                icon = Icons.Rounded.SwapHoriz, iconPalette = 7, chevron = true, last = true,
            ) { env.app.push(Route.TabOrderR) }
        }
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
    SettingsPage(L("Colores de la portada")) {
        // Previsualización fija: el tema actual teñido con la portada que suena (o una de ejemplo).
        SettingPreview(Modifier.padding(start = 16.dp, end = 16.dp, top = 18.dp)) { ArtworkPreview(palette[0], level) }
        FormSection(L("Dónde"), footer = L("Al sonar una canción, la app y los menús toman colores parecidos a los de su portada, como Descubrir.")) {
            FormRow(L("En el reproductor"), subtitle = L("Fondo con la carátula desenfocada y controles de su color"), icon = Icons.Rounded.PlayCircle, iconPalette = 5, trailing = { IosToggle(artworkPlayer, Prefs::setArtworkColorsPlayer, label = L("Colores de la portada en el reproductor")) })
            FormRow(L("En el resto de la app"), subtitle = L("Botones del color de la canción y fondos y menús con un toque"), icon = Icons.Rounded.Palette, iconPalette = 6, last = true, trailing = { IosToggle(artworkApp, Prefs::setArtworkColorsApp, label = L("Colores de la portada en el resto de la app")) })
        }
        FormSection(L("Cuánto"), footer = L("El texto y los iconos mantienen siempre un contraste legible, aunque la portada sea muy clara o muy viva.")) {
            FormCustomRow { Box(Modifier.padding(horizontal = 12.dp, vertical = 15.dp)) {
                val presets = listOf("off" to L("No")) + ArtworkLevel.presets.map { it.first to it.first }
                val selected = if (!level.enabled) "off" else ArtworkLevel.presets.firstOrNull { it.first == level.title }?.first ?: ""
                Segmented(presets, selected) { key ->
                    Prefs.setArtworkLevel(if (key == "off") ArtworkLevel.Off else ArtworkLevel.presets.first { it.first == key }.second)
                }
            } }
            FormRow(
                L("Ajuste fino"), subtitle = if (level.title == "Personalizado") L("Personalizado") else null, last = !custom,
                trailing = {
                    val turn by androidx.compose.animation.core.animateFloatAsState(if (custom) 90f else 0f, uiEaseOut(200), label = "fine")
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = c.tertiaryLabel, modifier = Modifier.size(20.dp).graphicsLayer { rotationZ = turn })
                },
            ) { custom = !custom }
            if (custom) {
                LevelSlider(L("Exageración del color"), L("Cuánto se parecen los botones al color de la portada"), level.intensity) { Prefs.setArtworkLevel(level.copy(intensity = it)) }
                LevelSlider(L("Opacidad"), L("Cuánto se tiñen los fondos y los menús"), level.opacity, last = true) { Prefs.setArtworkLevel(level.copy(opacity = it)) }
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
                    Text(L("Canción que suena"), style = Typo.callout.semibold, color = c.label)
                    Text(L("Artista"), style = Typo.footnote, color = c.secondaryLabel)
                }
                Icon(Icons.Rounded.Favorite, null, tint = c.accent, modifier = Modifier.size(22.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f).height(36.dp).background(c.accent, CircleShape), contentAlignment = Alignment.Center) {
                    Text(L("Reproducir"), style = Typo.subheadline.semibold, color = c.onAccent)
                }
                Box(Modifier.weight(1f).height(36.dp).background(c.secondaryGrouped, CircleShape), contentAlignment = Alignment.Center) {
                    Text(L("Menú"), style = Typo.subheadline.semibold, color = c.label)
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
    val showDiscover by Prefs.showDiscover.collectAsState()
    SettingsPage(L("Pestañas")) {
        FormSection(
            L("Orden de la barra"),
            footer = L("Arrastra ≡ para cambiar el orden; deslizar a los lados sigue el mismo orden. Desliza Descubrir a la izquierda para ocultarla (y a la derecha para volver a ponerla). La app se abre en la última pestaña que usaste.") +
                L(" Ajustes está arriba en Inicio y no entra en el orden."),
        ) {
            items.forEachIndexed { i, key -> androidx.compose.runtime.key(key) {
                val isDragging = dragging == key
                val tab = Tab.of(key)
                // Ajustes está arriba en Inicio: se ve apagado y sin asa, porque no está en la barra.
                val fixedTop = tab == Tab.Settings
                // Descubrir se oculta deslizándola a la izquierda (lo pidió Toxbox): queda difuminada y fuera de la barra.
                val swipeable = tab == Tab.Discover
                val hidden = swipeable && !showDiscover
                val swipe = remember { androidx.compose.animation.core.Animatable(0f) }
                val scope = rememberCoroutineScope()
                Box(
                    Modifier.zIndex(if (isDragging) 1f else 0f).graphicsLayer {
                        translationY = if (isDragging) dragOffset else 0f
                        translationX = swipe.value
                        alpha = if (hidden) 0.45f else 1f
                        if (isDragging) { scaleX = 1.02f; scaleY = 1.02f; shadowElevation = 12.dp.toPx() }
                    }.then(
                        if (!swipeable) Modifier else Modifier
                            .semantics {
                                customActions = listOf(
                                    androidx.compose.ui.semantics.CustomAccessibilityAction(if (hidden) L("Mostrar Descubrir") else L("Ocultar Descubrir")) {
                                        Prefs.setShowDiscover(hidden); true
                                    },
                                )
                            }
                            .pointerInput(hidden) {
                                val limit = 120.dp.toPx()
                                detectHorizontalDragGestures(
                                    onDragEnd = {
                                        val v = swipe.value
                                        if (!hidden && v < -limit * 0.6f) Prefs.setShowDiscover(false)
                                        if (hidden && v > limit * 0.6f) Prefs.setShowDiscover(true)
                                        scope.launch { swipe.animateTo(0f, androidx.compose.animation.core.spring(dampingRatio = 0.8f)) }
                                    },
                                    onDragCancel = { scope.launch { swipe.animateTo(0f) } },
                                    onHorizontalDrag = { change, amount ->
                                        change.consume()
                                        val next = (swipe.value + amount).coerceIn(if (hidden) 0f else -limit, if (hidden) limit else 0f)
                                        scope.launch { swipe.snapTo(next) }
                                    },
                                )
                            },
                    ),
                ) {
                    FormRow(
                        tab.title,
                        subtitle = when {
                            fixedTop -> L("Arriba en Inicio")
                            hidden -> L("Oculta · desliza a la derecha para ponerla")
                            else -> null
                        },
                        icon = tab.settingsIcon(), tint = c.label,
                        last = i == items.lastIndex, enabled = !fixedTop,
                        trailing = if (fixedTop) null else { {
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
                        } },
                    )
                }
            } }
        }
        FormSection(null) {
            FormRow(L("Orden de fábrica"), subtitle = L("Descubrir, Inicio, Biblioteca, Ajustes"), tint = c.accent, last = true, enabled = order != TabOrder.DEFAULT) {
                Prefs.setTabOrder(TabOrder.DEFAULT)
            }
        }
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
    SettingsPage(L("Buscar")) {
        FormSection(
            L("Dónde buscar"),
            footer = if (search == "tab") L("Buscar tiene su propia pestaña en la barra de abajo.")
            else L("La barra de búsqueda está siempre arriba en Inicio y la pestaña Buscar desaparece."),
        ) {
            FormRow(L("Barra arriba en Inicio"), icon = Icons.Rounded.Home, tint = Libre.colors.label, checked = search != "tab") { Prefs.setSearchPlacement("home") }
            FormRow(L("Pestaña aparte"), icon = Icons.Rounded.Search, tint = Libre.colors.label, checked = search == "tab", last = true) { Prefs.setSearchPlacement("tab") }
        }
    }
}

@Composable
fun ThemePickerScreen() {
    val c = Libre.colors
    val current by Prefs.theme.collectAsState()
    val appearance by Prefs.appearance.collectAsState()
    SettingsPage(L("Tema")) {
        Text(L("Tema"), style = Typo.headline, color = c.secondaryLabel, modifier = Modifier.padding(start = 32.dp, top = 19.dp, bottom = 22.dp))
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
            L("El tema cambia el fondo, las tarjetas, el color y la letra. Los fondos toman los colores de la carátula y se animan más mientras suena música."),
            style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(start = 32.dp, end = 32.dp, top = 17.dp),
        )
        FormSection(L("Claro u oscuro"), footer = current.forcedDark?.let { if (it) L("«{0}» usa siempre el modo oscuro.", current.title) else L("«{0}» usa siempre el modo claro.", current.title) }) {
            FormCustomRow { Box(Modifier.padding(horizontal = 12.dp, vertical = 15.dp)) {
                Segmented(listOf("system" to L("Automático"), "light" to L("Claro"), "dark" to L("Oscuro")), appearance, enabled = current.forcedDark == null) {
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
                    Text(L("Aa"), style = Typo.subheadline.semibold, color = tc.label)
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
    SettingsPage(L("Reproductor")) {
        Text("REPRODUCTOR MULTIMEDIA", style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(start = 32.dp, top = 22.dp, bottom = 7.dp))
        DeckPicker(Modifier.padding(horizontal = 16.dp))
        Text(
            L("Casete: gira una bobina o arrastra la cinta para avanzar o rebobinar. Vinilo: gira el disco con el dedo o mueve el brazo. Con el móvil en horizontal, el casete o el vinilo ocupan toda la pantalla. También puedes cambiarlo manteniendo pulsado el mini reproductor."),
            style = Typo.footnote, color = c.secondaryLabel, modifier = Modifier.padding(start = 32.dp, end = 32.dp, top = 7.dp),
        )
        FormSection(null) {
            FormRow(
                L("Efecto en los títulos"), subtitle = L("Al cambiar de canción, el título aparece entre símbolos que se ordenan"),
                last = true, trailing = { IosToggle(scramble, Prefs::setScramble, label = L("Efecto en los títulos")) },
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
                .onSuccess { env.app.toast = L("Copia guardada") }
                .onFailure { env.app.toast = L("No se pudo usar esa carpeta") }
        }
    }
    FormSection(
        L("Copia automática"),
        footer = st.error ?: if (st.folder == null) L("Una copia al día de tus favoritos, playlists y álbumes en la carpeta que elijas. Elige una que se sincronice (Google Drive, Nextcloud…) para no perder nada al cambiar de móvil.")
        else L("Se guarda una al día y se dejan las {0} últimas. Para recuperarla: Biblioteca › Importar › Importar copia.", app.libremusic.data.AutoBackup.KEEP),
    ) {
        if (st.folder == null) {
            FormRow(L("Elegir carpeta"), icon = Icons.Rounded.CreateNewFolder, tint = Libre.colors.accent, last = true) { pick.launch(null) }
        } else {
            FormRow(L("Carpeta"), st.folderName ?: L("Elegida"), subtitle = st.lastDay?.let { L("Última copia: {0}", it) } ?: L("Aún sin copia"), chevron = true) { pick.launch(st.folder) }
            FormRow(L("Hacer copia ahora"), icon = Icons.Rounded.Backup, tint = Libre.colors.accent) {
                scope.launch { env.app.toast = if (app.libremusic.data.AutoBackup.backup(context, env.library.library, force = true)) L("Copia guardada") else L("No se pudo guardar la copia") }
            }
            FormRow(L("Desactivar"), tint = Libre.colors.destructive, last = true) { app.libremusic.data.AutoBackup.disable(context) }
        }
    }
}

/** Ajustes: elegir reproductor (DeckPicker en iOS). */
@Composable
fun DeckPicker(modifier: Modifier = Modifier) {
    val c = Libre.colors
    val env = LocalEnv.current
    val deck by Prefs.deck.collectAsState()
    val player by env.player.track.collectAsState()
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
    SettingsPage(L("Biblioteca")) {
        FormSection(L("Ordenar playlists por")) {
            FormRow(L("Añadidas recientemente"), checked = sort == "recent") { Prefs.setPlaylistSort("recent") }
            FormRow(L("Nombre (A-Z)"), checked = sort == "name") { Prefs.setPlaylistSort("name") }
            FormRow(L("Nombre (Z-A)"), checked = sort == "nameDesc") { Prefs.setPlaylistSort("nameDesc") }
            FormRow(L("Nº de canciones"), checked = sort == "count") { Prefs.setPlaylistSort("count") }
            FormRow(L("A mano"), checked = sort == "custom", last = true) { Prefs.setPlaylistSort("custom") }
        }
        FormSection(null, footer = L("Arrastra las playlists, Descargadas y Favoritos para colocarlas donde quieras.")) {
            FormRow(L("Editar playlists"), icon = Icons.Rounded.DragHandle, tint = Libre.colors.accent, chevron = true, last = true) { env.app.push(Route.ReorderPlaylists) }
        }
        FormSection(
            L("Descargadas y Favoritos"),
            footer = if (placement == "music") L("Aparecen como filas en «Tu música», encima de Canciones.") else L("Aparecen con su portada al principio de la carpeta Playlists, en «Tu música»."),
        ) {
            FormRow(L("En Playlists (portada grande)"), checked = placement != "music") { Prefs.setSmartPlacement("playlists") }
            FormRow(L("En «Tu música» (fila)"), checked = placement == "music", last = true) { Prefs.setSmartPlacement("music") }
        }
        // «No me interesa» de Descubrir (2.7 de x.1.1): cuántas hay y vaciarlas.
        val skipped by app.libremusic.data.ReelsSkip.entries.collectAsState()
        FormSection(L("Descubrir"), footer = L("Las canciones que marcaste con «No me interesa» no vuelven a salir, y un artista con tres en un mes deja de salir durante 30 días. Sólo se guarda en este móvil.")) {
            FormRow(
                L("Lo que no te interesa"), subtitle = songCount(skipped.size), last = true,
                trailing = {
                    if (skipped.isNotEmpty()) Text(
                        L("Vaciar"), style = Typo.body, color = Libre.colors.accent,
                        modifier = Modifier.tactile(label = L("Vaciar lo que no te interesa")) { app.libremusic.data.ReelsSkip.clear() }.padding(8.dp),
                    )
                },
            )
        }
        BackupSection()
        FormSection(null, footer = L("Antes de borrar se pide confirmación.")) {
            FormRow(L("Eliminar playlists"), icon = Icons.Rounded.Delete, tint = Libre.colors.destructive, chevron = true, last = true) { env.app.push(Route.ManagePlaylists) }
        }
        ResetSection(L("Biblioteca"), L("Las playlists vuelven a ordenarse por recientes, Descargadas y Favoritos al carrusel y Buscar a Inicio. No se borra ninguna playlist.")) { Prefs.resetLibrary() }
    }
}

@Composable
fun AudioScreen() {
    val quality by Prefs.quality.collectAsState()
    val crossfade by Prefs.crossfade.collectAsState()
    val equalizer by Prefs.equalizer.collectAsState()
    val autoplay by Prefs.autoplay.collectAsState()
    val normalize by Prefs.normalize.collectAsState()
    val context = LocalContext.current
    SettingsPage(L("Reproducción")) {
        FormSection(L("Calidad al escuchar"), footer = L("«Máxima» usa Opus a unos 160 kbps; «Ahorro de datos», unos 50 kbps. Se aplica desde la siguiente canción.")) {
            FormRow(L("Máxima"), subtitle = L("Mejor sonido; gasta más datos"), checked = quality == "max") { Prefs.setQuality("max") }
            FormRow(L("Ahorro de datos"), subtitle = L("Para escuchar con datos móviles"), checked = quality == "low", last = true) { Prefs.setQuality("low") }
        }
        FormSection(null, footer = L("Usa la sonoridad que YouTube mide de cada canción: las que suenan más fuerte bajan y las más flojas suben un poco, para no tocar el volumen entre canción y canción.")) {
            FormRow(L("Igualar el volumen"), last = true, trailing = { IosToggle(normalize, { Prefs.setNormalize(it) }, label = L("Igualar el volumen")) })
        }
        FormSection(null, footer = L("Cuando se acaba lo que estás escuchando y el bucle está apagado, se añaden canciones parecidas a la última.")) {
            FormRow(L("Seguir con canciones parecidas"), last = true, trailing = { IosToggle(autoplay, { Prefs.setAutoplay(it) }, label = L("Seguir con canciones parecidas")) })
        }
        FormSection(L("Ecualizador"), footer = L("Se aplica al momento, también a lo que suena por Bluetooth.")) {
            Eq.Preset.entries.forEachIndexed { i, p ->
                FormRow(p.title, subtitle = p.subtitle, checked = equalizer == p, last = i == Eq.Preset.entries.lastIndex) { Prefs.setEqualizer(p) }
            }
        }
        FormSection(L("Fundido entre canciones"), footer = if (crossfade == 0) L("Cada canción empieza y acaba a su volumen.") else L("La canción baja de volumen en sus últimos {0} s y la siguiente entra suavemente. Útil para listas variadas; en álbumes que van seguidos, mejor «No».", crossfade)) {
            FormCustomRow {
                Box(Modifier.padding(16.dp, 12.dp)) {
                    Segmented(Fade.options.map { "$it" to if (it == 0) L("No") else "$it s" }, "$crossfade") { Prefs.setCrossfade(it.toInt()) }
                }
            }
        }
        FormSection(null, footer = L("El bucle (no repetir, repetir lista o canción) se cambia en el reproductor.")) {
            FormRow(
                L("Salida de audio"), subtitle = L("Altavoces, auriculares y televisores con Bluetooth o Chromecast"),
                icon = Icons.Rounded.Cast, iconPalette = 7, chevron = true, last = true,
            ) { openOutputSwitcher(context) }
        }
        ResetSection(L("Reproducción"), L("La calidad al escuchar vuelve a «Máxima» y se quitan el ecualizador y el fundido; se vuelve a seguir con canciones parecidas.")) { Prefs.resetPlayback() }
    }
}

@Composable
fun DownloadsSettingsScreen() {
    val env = LocalEnv.current
    val downloaded by env.library.downloadedSongs.collectAsState()
    val context = LocalContext.current
    SettingsPage(L("Descargas")) {
        FormSection(null, footer = L("Las descargas se guardan en este móvil a la máxima calidad y se ven en Biblioteca › Descargadas. Para bajar una lista o un álbum entero, usa «Descargar todo» en su página.")) {
            FormRow(L("Canciones"), "${downloaded.size}")
            FormRow(
                L("Espacio usado"), android.text.format.Formatter.formatShortFileSize(context, MediaGraph.downloadBytes(context)),
                last = true,
            )
        }
        if (downloaded.isNotEmpty()) {
            FormSection(null, footer = L("Dejarán de estar disponibles sin conexión. Las playlists y los favoritos no se tocan.")) {
                FormCustomRow {
                    Box(Modifier.padding(16.dp, 8.dp)) {
                        HoldToConfirmButton(L("Mantén para borrar las descargas")) { downloaded.forEach { env.library.removeDownload(it) } }
                    }
                }
            }
        }
    }
}

@Composable
fun HelpScreen() {
    val env = LocalEnv.current
    SettingsPage(L("Ayuda y soporte")) {
        FormSection(null) {
            FormRow(L("Avisos"), subtitle = L("Caídas, versiones nuevas y novedades de Pear Music"), icon = Icons.Rounded.Notifications, iconPalette = 4, chevron = true) {
                env.app.push(Route.Avisos)
            }
            FormRow(L("Informar de un error"), subtitle = L("Cuéntanos qué ha fallado; puedes añadir capturas"), icon = Icons.Rounded.BugReport, iconPalette = 0, chevron = true) {
                env.app.push(Route.Support(null))
            }
            // Buzón de sugerencias (Cierre 1.0, lo pidió Toxbox): como el soporte, pero para ideas.
            FormRow(L("Buzón de sugerencias"), subtitle = L("Cuéntanos qué te gustaría que hiciera Pear Music"), icon = Icons.Rounded.MarkunreadMailbox, iconPalette = 5, chevron = true) {
                env.app.push(Route.Suggest(null))
            }
            FormRow(L("Guía inicial"), subtitle = L("Vuelve a ver la bienvenida, el recorrido y las historias"), icon = Icons.Rounded.School, iconPalette = 2, chevron = true) {
                Prefs.setOnboarded(false)
            }
            FormRow(L("Tus datos"), subtitle = L("Exporta o borra todo lo que la app guarda de ti"), icon = Icons.Rounded.Lock, iconPalette = 5, chevron = true) {
                env.app.push(Route.MyData)
            }
            FormRow(L("Acerca de"), subtitle = L("Versión {0} y créditos", BuildConfig.VERSION_NAME), icon = Icons.Rounded.Info, iconPalette = 6, chevron = true, last = true) {
                env.app.push(Route.About)
            }
        }
        if (BuildConfig.ADMIN_TOOLS) {
            FormSection(L("Pear Dev")) {
                FormRow(L("Administración"), subtitle = L("Canal, registro y botón de pánico"), icon = Icons.Rounded.AdminPanelSettings, iconPalette = 1, chevron = true, last = true) {
                    env.app.push(Route.Admin)
                }
            }
        }
    }
}

@Composable
fun AboutScreen() {
    val c = Libre.colors
    val uri = LocalUriHandler.current
    SettingsPage(L("Acerca de")) {
        Column(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Image(
                painterResource(R.drawable.logo), null,
                Modifier.size(96.dp).shadowSoft(10.dp, RoundedCornerShape(22.dp), 0.2f).clip(RoundedCornerShape(22.dp)),
            )
            Spacer(Modifier.height(10.dp))
            Text(L("Pear Music"), style = Typo.title2, color = c.label)
            Text(L("Versión {0}", BuildConfig.VERSION_NAME), style = Typo.subheadline, color = c.secondaryLabel)
        }
        FormSection(null) {
            Text(
                L("Cliente no oficial de YouTube Music. Usa una API no oficial de YouTube, así que puede dejar de funcionar si YouTube la cambia. Las descargas se guardan en este móvil."),
                style = Typo.subheadline, color = c.label, modifier = Modifier.padding(16.dp, 12.dp),
            )
        }
        FormSection(L("Créditos")) {
            FormRow(L("Componentes inspirados en The Kitchen de dqnamo"), icon = Icons.Rounded.Restaurant, tint = c.accent) { uri.openUri("https://www.dqnamo.com/kitchen") }
            // SimpMusic (GPL-3.0): la barra inferior de cristal está adaptada de su código. Lo pidió Toxbox.
            FormRow(L("Barra inferior de SimpMusic, de maxrave-dev (GPL-3.0)"), icon = Icons.Rounded.LibraryMusic, tint = c.accent) { uri.openUri("https://github.com/maxrave-dev/SimpMusic") }
            FormRow(L("Letra Inter, de Rasmus Andersson (OFL)"), icon = Icons.Rounded.Album, tint = c.accent, last = true) { uri.openUri("https://rsms.me/inter/") }
        }
    }
}

@Composable
fun ManagePlaylistsScreen() {
    val c = Libre.colors
    val env = LocalEnv.current
    val data by env.library.data.collectAsState()
    val ver by env.library.coverVersion.collectAsState()
    SettingsPage(L("Eliminar playlists")) {
        if (data.playlists.isEmpty()) {
            CenterNote(L("No hay playlists"), 60.dp)
        } else {
            FormSection(null, footer = L("Eliminar una playlist no borra sus canciones de Favoritos ni de Descargas.")) {
                data.playlists.forEachIndexed { i, p ->
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        PlaylistCover(p, 44.dp, coverFile = env.library.coverFile(p.id), coverVersion = ver)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(p.name, style = Typo.body, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(songCount(p.songs.size), style = Typo.caption, color = c.secondaryLabel)
                        }
                            IconTap(Icons.Rounded.Delete, L("Eliminar {0}", p.name), tint = c.destructive) {
                                env.app.alert = AlertSpec(
                                    L("¿Eliminar «{0}»?", p.name), L("Se borrará la playlist y su portada. No se puede deshacer."),
                                    buttons = listOf(
                                        AlertButton(L("Eliminar playlist"), AlertButton.Role.Destructive) { env.library.deletePlaylist(p.id) },
                                        AlertButton(L("Cancelar"), AlertButton.Role.Cancel),
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
