package app.libremusic.ui.theme

import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// Temas y ajustes visuales. Es la misma lógica que Theme.swift en iOS: cada tema cambia
// el fondo animado, las superficies, el acento, la letra y (si su estética lo pide) el modo.

enum class AppTheme(val key: String) {
    Glass("glass"), Air("air"), Neon("neon"), Plain("plain");

    val spec: Tokens.ThemeSpec get() = Tokens.Themes.getValue(key)
    val title: String get() = spec.name
    val blurb: String get() = spec.blurb
    val accent: Color get() = spec.accent
    val onAccent: Color get() = spec.onAccent
    /** Modo impuesto por el tema (null = el que elija el usuario). */
    val forcedDark: Boolean? get() = spec.scheme?.let { it == "dark" }
    val maxRadius: Float get() = spec.maxRadius
    /** Con fondo animado y superficies propias (todos menos Sistema). */
    val styled: Boolean get() = this != Plain

    companion object {
        fun of(key: String?): AppTheme = entries.firstOrNull { it.key == key } ?: Glass
        val ordered: List<AppTheme> get() = Tokens.ThemeOrder.map(::of)
    }
}

enum class DeckStyle(val key: String, val title: String) {
    Normal("normal", "Normal"), Cassette("cassette", "Casete"), Vinyl("vinyl", "Vinilo"), Air("air", "Air");

    /** Objeto físico que llena la pantalla en horizontal. */
    val isObject: Boolean get() = this == Cassette || this == Vinyl

    companion object {
        fun of(key: String?): DeckStyle = entries.firstOrNull { it.key == key } ?: Normal
    }
}

/**
 * Ajustes guardados. Mismas claves y valores que UserDefaults en iOS
 * (theme, appearance, deck, searchPlacement, playlistSort, scramble, quality).
 */
object Prefs {
    private lateinit var sp: SharedPreferences

    private val _theme = MutableStateFlow(AppTheme.Glass)
    val theme: StateFlow<AppTheme> = _theme.asStateFlow()
    private val _appearance = MutableStateFlow("system")
    val appearance: StateFlow<String> = _appearance.asStateFlow()
    private val _deck = MutableStateFlow(DeckStyle.Normal)
    val deck: StateFlow<DeckStyle> = _deck.asStateFlow()
    private val _searchPlacement = MutableStateFlow("home")
    val searchPlacement: StateFlow<String> = _searchPlacement.asStateFlow()
    private val _playlistSort = MutableStateFlow("recent")
    val playlistSort: StateFlow<String> = _playlistSort.asStateFlow()
    private val _scramble = MutableStateFlow(true)
    val scramble: StateFlow<Boolean> = _scramble.asStateFlow()
    private val _quality = MutableStateFlow("max")
    val quality: StateFlow<String> = _quality.asStateFlow()
    /** Cristal líquido de iOS 26 en barras, botones y menús (sólo Android; iOS 26 ya lo tiene). */
    /** Orden a mano del carrusel de Playlists (claves de `LibraryOrder`). */
    private val _playlistOrder = MutableStateFlow<List<String>>(emptyList())
    val playlistOrder: StateFlow<List<String>> = _playlistOrder.asStateFlow()
    /** Dónde van Descargadas y Favoritos: "playlists" (portada grande) o "music" (fila en «Tu música»). */
    private val _smartPlacement = MutableStateFlow("playlists")
    val smartPlacement: StateFlow<String> = _smartPlacement.asStateFlow()
    /** Colores de la carátula al sonar una canción: en el reproductor y/o en el resto de la app. */
    private val _artworkColorsPlayer = MutableStateFlow(false)
    val artworkColorsPlayer: StateFlow<Boolean> = _artworkColorsPlayer.asStateFlow()
    private val _artworkColorsApp = MutableStateFlow(false)
    val artworkColorsApp: StateFlow<Boolean> = _artworkColorsApp.asStateFlow()
    /** Cuánto: exageración del color y opacidad del tinte (0…1). Las dos a 0 = desactivado. */
    private val _artworkLevel = MutableStateFlow(ArtworkLevel.Balanced)
    val artworkLevel: StateFlow<ArtworkLevel> = _artworkLevel.asStateFlow()
    private val _liquidGlass = MutableStateFlow(false)
    val liquidGlass: StateFlow<Boolean> = _liquidGlass.asStateFlow()
    /** Barra inferior: «classic» (pestañas como iOS 26) o «simpmusic» (cápsula + Buscar aparte, se pliega). */
    private val _barStyle = MutableStateFlow("classic")
    val barStyle: StateFlow<String> = _barStyle.asStateFlow()
    /**
     * Ajustes arriba en Inicio (junto al Jam) en vez de en la barra, guardado aparte para cada barra: por defecto en
     * la barra con la clásica y arriba con la estilo SimpMusic (lo pidió Toxbox). Arriba, sale del orden de pestañas.
     */
    private val _settingsTopClassic = MutableStateFlow(false)
    val settingsTopClassic: StateFlow<Boolean> = _settingsTopClassic.asStateFlow()
    private val _settingsTopSimp = MutableStateFlow(true)
    val settingsTopSimp: StateFlow<Boolean> = _settingsTopSimp.asStateFlow()
    /** Orden de las pestañas (`TabOrder`) y la última abierta, para volver a ella al abrir la app. */
    private val _tabOrder = MutableStateFlow(app.libremusic.data.TabOrder.DEFAULT)
    val tabOrder: StateFlow<List<String>> = _tabOrder.asStateFlow()
    var lastTab: String? = null
        private set
    /** Segundos de diferencia de duración que se aceptan al emparejar canciones (Ajustes › Avanzado). */
    /** Ecualizador (`Eq.Preset.key`); sólo Android. */
    private val _equalizer = MutableStateFlow(app.libremusic.playback.Eq.Preset.Off)
    val equalizer: StateFlow<app.libremusic.playback.Eq.Preset> = _equalizer.asStateFlow()
    /** Al acabar la cola, seguir con canciones parecidas. */
    private val _autoplay = MutableStateFlow(true)
    val autoplay: StateFlow<Boolean> = _autoplay.asStateFlow()
    /** Fundido entre canciones en segundos (0 = no). */
    /** Igualar el volumen entre canciones con la sonoridad que da YouTube (sólo Android por ahora). */
    private val _normalize = MutableStateFlow(true)
    val normalize: StateFlow<Boolean> = _normalize.asStateFlow()
    private val _crossfade = MutableStateFlow(0)
    val crossfade: StateFlow<Int> = _crossfade.asStateFlow()
    private val _matchTolerance = MutableStateFlow(4)
    val matchTolerance: StateFlow<Int> = _matchTolerance.asStateFlow()
    /** La guía inicial (tema, colores y descargas) ya se ha visto. */
    private val _onboarded = MutableStateFlow(true)
    val onboarded: StateFlow<Boolean> = _onboarded.asStateFlow()

    fun init(context: Context) {
        sp = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        // Instalación nueva (aún no hay tema guardado): se enseña la guía inicial.
        val fresh = !sp.contains("theme")
        // Instalación nueva: Cristal (respeta claro/oscuro). Un tema desconocido pasa a Cristal.
        val stored = sp.getString("theme", null)
        if (stored == null || Tokens.Themes[stored] == null) sp.edit().putString("theme", Tokens.DefaultTheme).apply()
        if (sp.getString("deck", null) == null) {
            val air = sp.getString("theme", null) == AppTheme.Air.key
            sp.edit().putString("deck", if (air) DeckStyle.Air.key else DeckStyle.Normal.key).apply()
        }
        _theme.value = AppTheme.of(sp.getString("theme", null))
        _appearance.value = sp.getString("appearance", "system") ?: "system"
        _deck.value = DeckStyle.of(sp.getString("deck", null))
        _searchPlacement.value = sp.getString("searchPlacement", "home") ?: "home"
        _playlistSort.value = sp.getString("playlistSort", "recent") ?: "recent"
        _scramble.value = sp.getBoolean("scramble", true)
        _quality.value = sp.getString("quality", "max") ?: "max"
        _normalize.value = sp.getBoolean("normalize", true)
        _liquidGlass.value = sp.getBoolean("liquidGlass", false)
        _barStyle.value = sp.getString("barStyle", "classic") ?: "classic"
        _settingsTopClassic.value = sp.getBoolean("settingsTop.classic", false)
        _settingsTopSimp.value = sp.getBoolean("settingsTop.simpmusic", true)
        _artworkColorsPlayer.value = sp.getBoolean("artworkColorsPlayer", false)
        _artworkColorsApp.value = sp.getBoolean("artworkColorsApp", false)
        _playlistOrder.value = sp.getString("playlistOrder", "").orEmpty().split("\n").filter { it.isNotEmpty() }
        _smartPlacement.value = sp.getString("smartPlacement", "playlists") ?: "playlists"
        _tabOrder.value = app.libremusic.data.TabOrder.decode(sp.getString("tabOrder", null))
        lastTab = sp.getString("lastTab", null)
        _onboarded.value = sp.getBoolean("onboarded", !fresh)
        setMatchTolerance(sp.getInt("matchTolerance", 4), save = false)
        setCrossfade(sp.getInt("crossfade", 0), save = false)
        setAutoplay(sp.getBoolean("autoplay", true), save = false)
        setEqualizer(app.libremusic.playback.Eq.Preset.of(sp.getString("equalizer", null)), save = false)
        _artworkLevel.value = ArtworkLevel(
            sp.getFloat("artworkIntensity", ArtworkLevel.Balanced.intensity),
            sp.getFloat("artworkOpacity", ArtworkLevel.Balanced.opacity),
        )
    }

    fun setMatchTolerance(v: Int, save: Boolean = true) {
        _matchTolerance.value = v
        app.libremusic.data.Matcher.tolerance = v
        if (save) sp.edit().putInt("matchTolerance", v).apply()
    }

    fun setEqualizer(v: app.libremusic.playback.Eq.Preset, save: Boolean = true) {
        _equalizer.value = v
        app.libremusic.playback.Eq.preset = v
        if (save) sp.edit().putString("equalizer", v.key).apply()
    }

    fun setAutoplay(v: Boolean, save: Boolean = true) {
        _autoplay.value = v
        app.libremusic.playback.AutoRadio.enabled = v
        if (save) sp.edit().putBoolean("autoplay", v).apply()
    }

    fun setCrossfade(v: Int, save: Boolean = true) {
        _crossfade.value = v
        app.libremusic.playback.Fade.seconds = v
        if (save) sp.edit().putInt("crossfade", v).apply()
    }

    fun setArtworkLevel(v: ArtworkLevel) {
        _artworkLevel.value = v
        sp.edit().putFloat("artworkIntensity", v.intensity).putFloat("artworkOpacity", v.opacity).apply()
    }

    // «Restablecer» de cada sección de Ajustes: vuelve a los valores de una instalación nueva.
    fun resetAppearance() {
        setTheme(AppTheme.of(Tokens.DefaultTheme)); setAppearance("system"); setDeck(DeckStyle.Normal); setScramble(true)
        setArtworkColorsPlayer(false); setArtworkColorsApp(false); setArtworkLevel(ArtworkLevel.Balanced)
        setTabOrder(app.libremusic.data.TabOrder.DEFAULT); setLiquidGlass(false)
    }
    fun resetPlayback() { setQuality("max"); setCrossfade(0); setEqualizer(app.libremusic.playback.Eq.Preset.Off); setAutoplay(true) }
    fun resetLibrary() { setPlaylistSort("recent"); setPlaylistOrder(emptyList()); setSmartPlacement("playlists"); setSearchPlacement("home") }

    fun setTabOrder(v: List<String>) { _tabOrder.value = v; sp.edit().putString("tabOrder", app.libremusic.data.TabOrder.encode(v)).apply() }
    fun setLastTab(v: String) { if (v != lastTab) { lastTab = v; sp.edit().putString("lastTab", v).apply() } }
    fun setOnboarded(v: Boolean) { _onboarded.value = v; sp.edit().putBoolean("onboarded", v).apply() }

    fun setTheme(t: AppTheme) { _theme.value = t; sp.edit().putString("theme", t.key).apply() }
    fun setAppearance(v: String) { _appearance.value = v; sp.edit().putString("appearance", v).apply() }
    fun setDeck(d: DeckStyle) { _deck.value = d; sp.edit().putString("deck", d.key).apply() }
    fun setSearchPlacement(v: String) { _searchPlacement.value = v; sp.edit().putString("searchPlacement", v).apply() }
    fun setPlaylistSort(v: String) { _playlistSort.value = v; sp.edit().putString("playlistSort", v).apply() }
    fun setScramble(v: Boolean) { _scramble.value = v; sp.edit().putBoolean("scramble", v).apply() }
    fun setQuality(v: String) { _quality.value = v; sp.edit().putString("quality", v).apply() }
    fun setNormalize(v: Boolean) { _normalize.value = v; sp.edit().putBoolean("normalize", v).apply(); app.libremusic.playback.Normalizer.apply() }
    fun setPlaylistOrder(v: List<String>) { _playlistOrder.value = v; sp.edit().putString("playlistOrder", v.joinToString("\n")).apply() }
    fun setSmartPlacement(v: String) { _smartPlacement.value = v; sp.edit().putString("smartPlacement", v).apply() }
    fun setArtworkColorsPlayer(v: Boolean) { _artworkColorsPlayer.value = v; sp.edit().putBoolean("artworkColorsPlayer", v).apply() }
    fun setArtworkColorsApp(v: Boolean) { _artworkColorsApp.value = v; sp.edit().putBoolean("artworkColorsApp", v).apply() }
    fun setLiquidGlass(v: Boolean) { _liquidGlass.value = v; sp.edit().putBoolean("liquidGlass", v).apply() }
    fun setBarStyle(v: String) { _barStyle.value = v; sp.edit().putString("barStyle", v).apply() }
    /** Ajustes arriba ([top]) o en la barra, para la barra [style] («classic» o «simpmusic»). */
    fun setSettingsTop(style: String, top: Boolean) {
        if (style == "simpmusic") _settingsTopSimp.value = top else _settingsTopClassic.value = top
        sp.edit().putBoolean("settingsTop.$style", top).apply()
    }
}

/** Colores del sistema de iOS (label, secondaryLabel…) para el modo activo, más el acento del tema. */
@Immutable
data class LibreColors(
    val dark: Boolean,
    val theme: AppTheme,
    val accent: Color,
    val onAccent: Color,
    val background: Color,
    val grouped: Color,
    val secondaryGrouped: Color,
    val label: Color,
    val secondaryLabel: Color,
    val tertiaryLabel: Color,
    val separator: Color,
    val fill: Color,
) {
    val destructive: Color get() = if (dark) Color(0xFFFF453A) else Color(0xFFFF3B30)
    val green: Color get() = if (dark) Color(0xFF30D158) else Color(0xFF34C759)
    val orange: Color get() = if (dark) Color(0xFFFF9F0A) else Color(0xFFFF9500)

    companion object {
        fun of(theme: AppTheme, dark: Boolean): LibreColors =
            if (dark) {
                LibreColors(
                    true, theme, theme.accent, theme.onAccent,
                    Tokens.SysDark.Background, Tokens.SysDark.GroupedBackground, Tokens.SysDark.SecondaryGroupedBackground,
                    Tokens.SysDark.Label, Tokens.SysDark.SecondaryLabel, Tokens.SysDark.TertiaryLabel,
                    Tokens.SysDark.Separator, Tokens.SysDark.Fill,
                )
            } else {
                LibreColors(
                    false, theme, theme.accent, theme.onAccent,
                    Tokens.SysLight.Background, Tokens.SysLight.GroupedBackground, Tokens.SysLight.SecondaryGroupedBackground,
                    Tokens.SysLight.Label, Tokens.SysLight.SecondaryLabel, Tokens.SysLight.TertiaryLabel,
                    Tokens.SysLight.Separator, Tokens.SysLight.Fill,
                )
            }
    }
}

val LocalLibre = staticCompositionLocalOf { LibreColors.of(AppTheme.Glass, false) }

/** Atajo: `Libre.colors.label`. */
object Libre {
    val colors: LibreColors
        @Composable get() = LocalLibre.current
}

/** Aplica acento, modo y colores del tema a toda la app (equivale a ThemeAppearance en iOS). */
@Composable
fun LibreMusicTheme(forceDark: Boolean? = null, content: @Composable () -> Unit) {
    val theme by Prefs.theme.collectAsState()
    val appearance by Prefs.appearance.collectAsState()
    val system = isSystemInDarkTheme()
    val user = when (appearance) {
        "light" -> false
        "dark" -> true
        else -> system
    }
    val dark = forceDark ?: theme.forcedDark ?: user
    val artworkApp by Prefs.artworkColorsApp.collectAsState()
    val artworkLevel by Prefs.artworkLevel.collectAsState()
    val active by ThemeEngine.active.collectAsState()
    val palette = rememberPalette()
    val base = LibreColors.of(theme, dark)
    // «Colores de la carátula» en el resto de la app: el acento y un tinte suave del fondo salen de
    // la canción que suena, encima del tema elegido.
    ProvideLibre(if (artworkApp && active) base.withArtwork(palette[0], artworkLevel) else base, content)
}

/**
 * «Colores de la portada»: exageración del color ([intensity]) y opacidad del tinte de los fondos
 * ([opacity]), de 0 a 1. Mismos valores y presets que `ArtworkLevel` en iOS.
 */
data class ArtworkLevel(val intensity: Float, val opacity: Float) {
    val enabled: Boolean get() = intensity > 0.005f || opacity > 0.005f

    /** «Sutil», «Equilibrado», «Intenso», «Desactivado» o «Personalizado» (barras movidas a mano). */
    val title: String get() = when {
        !enabled -> "Desactivado"
        else -> presets.firstOrNull { (_, l) -> l.near(this) }?.first ?: "Personalizado"
    }

    private fun near(o: ArtworkLevel) = kotlin.math.abs(intensity - o.intensity) < 0.02f && kotlin.math.abs(opacity - o.opacity) < 0.02f

    companion object {
        val Off = ArtworkLevel(0f, 0f)
        val Subtle = ArtworkLevel(0.25f, 0.2f)
        /** Equilibrado = cómo se veía antes de las barras (acento de la portada y fondos con un 8–13 %). */
        val Balanced = ArtworkLevel(0.5f, 0.45f)
        val Intense = ArtworkLevel(1f, 1f)
        val presets = listOf("Sutil" to Subtle, "Equilibrado" to Balanced, "Intenso" to Intense)
    }
}

/** Contraste WCAG entre dos colores (1…21). */
fun contrast(a: Color, b: Color): Float {
    val (hi, lo) = listOf(a.luminance(), b.luminance()).sortedDescending()
    return (hi + 0.05f) / (lo + 0.05f)
}

/**
 * Los colores del tema teñidos con el color de una carátula. El texto y los iconos mantienen siempre un
 * contraste mínimo (acento ≥ 3:1 y texto ≥ 4,5:1 sobre el fondo teñido), aunque las barras estén al
 * máximo y la portada sea muy clara o muy saturada.
 */
fun LibreColors.withArtwork(art: Color, level: ArtworkLevel = ArtworkLevel.Balanced): LibreColors {
    if (!level.enabled) return this
    val hsv = FloatArray(3)
    android.graphics.Color.colorToHSV(art.toArgb(), hsv)
    hsv[1] = hsv[1].coerceAtLeast(0.9f * level.intensity)
    // En claro, el acento no puede ser demasiado claro; en oscuro, no demasiado oscuro.
    hsv[2] = if (dark) hsv[2].coerceAtLeast(0.82f) else hsv[2].coerceAtMost(0.62f)
    var tint = level.opacity * (if (dark) 0.29f else 0.18f)
    var bg = androidx.compose.ui.graphics.lerp(background, art, tint)
    // El texto sigue legible: si el tinte lo deja por debajo de 4,5:1, se rebaja el tinte.
    while (tint > 0.01f && contrast(label, bg) < 4.5f) { tint *= 0.8f; bg = androidx.compose.ui.graphics.lerp(background, art, tint) }
    var artAccent = Color(android.graphics.Color.HSVToColor(hsv))
    // Acento (iconos y botones) a 3:1 como mínimo sobre el fondo teñido.
    var guard = 0
    while (contrast(artAccent, bg) < 3f && guard++ < 20) {
        hsv[2] = if (dark) (hsv[2] + 0.04f).coerceAtMost(1f) else (hsv[2] - 0.04f).coerceAtLeast(0f)
        if (dark && hsv[2] >= 1f) hsv[1] = (hsv[1] - 0.06f).coerceAtLeast(0f)
        artAccent = Color(android.graphics.Color.HSVToColor(hsv))
    }
    val accent = androidx.compose.ui.graphics.lerp(this.accent, artAccent, (level.intensity * 2f).coerceAtMost(1f))
    val onAccent = if (accent.luminance() > 0.55f) Color.Black else Color.White
    return copy(
        accent = accent, onAccent = onAccent,
        background = bg,
        grouped = androidx.compose.ui.graphics.lerp(grouped, art, tint),
        secondaryGrouped = androidx.compose.ui.graphics.lerp(secondaryGrouped, art, tint * 0.8f),
    )
}

/** Fuerza claro u oscuro en una parte de la pantalla (los reels y el casete son siempre oscuros). */
@Composable
fun ProvideLibre(colors: LibreColors, content: @Composable () -> Unit) {
    val scheme = if (colors.dark) {
        darkColorScheme(
            primary = colors.accent, onPrimary = colors.onAccent, background = colors.background,
            surface = colors.secondaryGrouped, onSurface = colors.label, onBackground = colors.label,
            onSurfaceVariant = colors.secondaryLabel, outline = colors.separator,
        )
    } else {
        lightColorScheme(
            primary = colors.accent, onPrimary = colors.onAccent, background = colors.background,
            surface = colors.secondaryGrouped, onSurface = colors.label, onBackground = colors.label,
            onSurfaceVariant = colors.secondaryLabel, outline = colors.separator,
        )
    }
    MaterialTheme(colorScheme = scheme, typography = LibreTypography) {
        CompositionLocalProvider(LocalLibre provides colors, content = content)
    }
}

@Composable
fun DarkSection(content: @Composable () -> Unit) {
    val c = Libre.colors
    ProvideLibre(LibreColors.of(c.theme, true).copy(accent = c.accent, onAccent = c.onAccent), content)
}

/** Si Ajustes va arriba en Inicio con la barra que está puesta ahora. */
@androidx.compose.runtime.Composable
fun rememberSettingsTop(): Boolean {
    val style by Prefs.barStyle.collectAsState()
    val classic by Prefs.settingsTopClassic.collectAsState()
    val simp by Prefs.settingsTopSimp.collectAsState()
    return if (style == "simpmusic") simp else classic
}
