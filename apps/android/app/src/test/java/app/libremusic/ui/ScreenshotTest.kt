package app.libremusic.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalView
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import app.libremusic.LibreMusicApplication
import app.libremusic.data.AlbumInfo
import app.libremusic.data.PlayStats
import app.libremusic.data.Song
import app.libremusic.reels.ReelsViewModel
import app.libremusic.ui.theme.AppTheme
import app.libremusic.ui.theme.DeckStyle
import app.libremusic.ui.theme.LibreMusicTheme
import app.libremusic.ui.theme.Prefs
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Capturas de las pantallas principales con el tamaño de un iPhone 15/16 (393×852 pt) para
 * compararlas con la app de iOS. Se guardan en build/shots/ y la CI las publica en la rama «screenshots».
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "es-rES-w393dp-h852dp-xxhdpi")
class ScreenshotTest : ShotBase() {
    @Test fun biblioteca_cristal() = shot("01_biblioteca_cristal") { tab = Tab.Library }
    @Test fun biblioteca_cristal_oscuro() = shot("02_biblioteca_cristal_oscuro", appearance = "dark") { tab = Tab.Library }
    @Test fun biblioteca_aire() = shot("03_biblioteca_aire", AppTheme.Air) { tab = Tab.Library }
    @Test fun biblioteca_neon() = shot("04_biblioteca_neon", AppTheme.Neon) { tab = Tab.Library }
    @Test fun biblioteca_sistema() = shot("05_biblioteca_sistema", AppTheme.Plain) { tab = Tab.Library }
    @Test fun playlist() = shot("06_playlist") { tab = Tab.Library; push(Route.Smart(SmartList.Favorites)) }
    @Test fun ajustes() = shot("07_ajustes") { tab = Tab.Settings }
    @Test fun temas() = shot("08_temas") { tab = Tab.Settings; push(Route.ThemePicker) }
    @Test fun reproductor_normal() = shot("09_reproductor_normal") { showPlayer = true }
    @Test fun reproductor_casete() = shot("10_reproductor_casete", deck = DeckStyle.Cassette) { showPlayer = true }
    @Test fun reproductor_vinilo() = shot("11_reproductor_vinilo", deck = DeckStyle.Vinyl) { showPlayer = true }
    @Test fun reproductor_air() = shot("12_reproductor_air", AppTheme.Air, DeckStyle.Air) { showPlayer = true }
    @Test fun reproductor_neon() = shot("13_reproductor_neon", AppTheme.Neon) { showPlayer = true }
    @Test fun jam() = shot("14_jam", playing = false) { showJam = true }
    @Test fun importar() = shot("15_importar", playing = false) { showImport = true }
    @Test fun tus_albumes() = shot("16_tus_albumes") { tab = Tab.Library; push(Route.Albums) }
    @Test fun aspecto() = shot("17_aspecto") { tab = Tab.Settings; push(Route.Appearance) }
    @Test fun colores_portada() = shot("18_colores_portada", artwork = true) { tab = Tab.Settings; push(Route.ArtworkColors) }
    @Test fun pestanas() = shot("19_pestanas") { tab = Tab.Settings; push(Route.TabOrderR) }
    @Test fun guia_inicial() = shot("20_guia_inicial", playing = false, guide = true) { tab = Tab.Home }
    @Test fun informar_error() = shot("21_informar_error", playing = false) { tab = Tab.Settings; push(Route.Support(null)) }
    @Test fun temporizador() = try {
        app.libremusic.playback.SleepTimer.start(30)
        shot("23_temporizador") { showPlayer = true }
    } finally { app.libremusic.playback.SleepTimer.cancel() }
    @Test fun privacidad() = shot("27_privacidad", playing = false, terms = false) { tab = Tab.Home }
    @Test fun cuenta() = shot("28_cuenta", playing = false) { tab = Tab.Settings; push(Route.AccountR) }
    @Test fun recorrido() = shot("29_recorrido", playing = false, intro = "tour") { tab = Tab.Home }
    @Test fun historias() = shot("30_historias", playing = false, intro = "stories") { tab = Tab.Home }
    @Test fun primeros_pasos() = shot("31_primeros_pasos", playing = false, firstSteps = true) { tab = Tab.Home }
    @Test fun tus_datos() = shot("32_tus_datos", playing = false) { tab = Tab.Settings; push(Route.MyData) }
    @Test fun aviso_version() = shot("33_aviso_version", playing = false) {
        tab = Tab.Home
        alert = AlertSpec(
            "Pear Music 1.0.0: Bienvenida nueva y cuenta opcional",
            "• Bienvenida nueva con recorrido e historias\n• Cuenta opcional cifrada\n\nSe actualiza encima: no pierdes tu biblioteca ni tus canciones descargadas.",
            buttons = listOf(AlertButton("Descargar"), AlertButton("Recordarme mañana", AlertButton.Role.Cancel)),
        )
    }
    @Test fun personalizacion() = shot("34_personalizacion", playing = false) { tab = Tab.Settings; push(Route.Personalization) }
    @Test fun discografia() = shot("35_discografia", playing = false) {
        tab = Tab.Home
        val albums = listOf(
            app.libremusic.data.RemoteCollection("MPREb_a", "Un verano sin ti", "Álbum • Bad Bunny • 2022", null),
            app.libremusic.data.RemoteCollection("MPREb_b", "Nadie sabe lo que va a pasar mañana", "Álbum • Bad Bunny • 2023", null),
        )
        push(Route.Discography("Bad Bunny", "albums", albums, emptyList(), null, null))
    }
    @Test fun reproductor_air_botones() = shot("36_reproductor_air", AppTheme.Air, DeckStyle.Air) { showPlayer = true }
    // x.1.1 (1.5 y 1.3): con Descubrir oculta y Ajustes arriba quedan dos pestañas; tienen que ir centradas.
    @Test fun barra_dos_pestanas() = shot("37_barra_dos_pestanas", playing = false, discover = false) { tab = Tab.Home }
    @Test fun barra_simpmusic_dos() = shot("38_barra_simpmusic_dos", playing = false, bar = "simpmusic", discover = false) { tab = Tab.Home }
    @Test fun reproduccion() = shot("25_reproduccion", playing = false) { tab = Tab.Settings; push(Route.Audio) }
    @Test fun estadisticas() {
        val now = System.currentTimeMillis() / 1000
        val plays = listOf(0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5).mapIndexed { i, k -> PlayStats.Play(songs[k % songs.size].id, now - i * 600L) }
        PlayStats.init(RuntimeEnvironment.getApplication())
        songs.forEach { PlayStats.record(it, now - 99_999_999) } // fuera de «Este mes»
        plays.forEach { p -> PlayStats.record(songs.first { it.id == p.id }, p.at) }
        try { shot("26_estadisticas", playing = false) { tab = Tab.Library; push(Route.Stats) } } finally { PlayStats.clear() }
    }
    @Test fun letra() {
        app.libremusic.data.LyricsClient.seed(songs[0].id, app.libremusic.data.Lyrics(app.libremusic.data.Lyrics.parseLrc(
            "[00:55.00] I've been tryna call\n[01:01.00] I've been on my own for long enough\n[01:08.00] Maybe you can show me how to love, maybe\n" +
                "[01:14.00] I'm going through withdrawals\n[01:19.00] You don't even have to do too much\n[01:24.00] You can turn me on with just a touch, baby\n" +
                "[01:30.00] I look around and Sin City's cold and empty\n[01:36.00] No one's around to judge me",
        ), null))
        shot("24_letra") { showPlayer = true; initialPanel = PlayerPanel.Lyrics }
    }
}

/**
 * El móvil en horizontal (852×393): los reproductores tienen que caber sin desbordarse.
 * Casete y vinilo pasan a pantalla completa; Normal y Air, a dos columnas.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "es-rES-w852dp-h393dp-land-xxhdpi")
class LandscapeShotTest : ShotBase(landscape = true) {
    @Test fun horizontal_normal() = shot("h1_reproductor_normal") { showPlayer = true }
    @Test fun horizontal_air() = shot("h2_reproductor_air", AppTheme.Air, DeckStyle.Air) { showPlayer = true }
    @Test fun horizontal_casete() = shot("h3_reproductor_casete", deck = DeckStyle.Cassette) { showPlayer = true }
    @Test fun horizontal_vinilo() = shot("h4_reproductor_vinilo", deck = DeckStyle.Vinyl) { showPlayer = true }
    @Test fun horizontal_inicio() = shot("h5_inicio") { tab = Tab.Home }
}

/** Letra grande (150 %): lo que más se rompe con «Tamaño de fuente» del sistema. Capturas `t*.png`. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "es-rES-w393dp-h852dp-port-xxhdpi", fontScale = 1.5f)
class LargeTextShotTest : ShotBase() {
    @Test fun biblioteca() = shot("t1_biblioteca") { tab = Tab.Library }
    @Test fun reproductor() = shot("t2_reproductor") { showPlayer = true }
    @Test fun ajustes() = shot("t3_ajustes") { tab = Tab.Settings }
    @Test fun reproduccion() = shot("t4_reproduccion", playing = false) { tab = Tab.Settings; push(Route.Audio) }
}

abstract class ShotBase(private val landscape: Boolean = false) {
    private val app get() = RuntimeEnvironment.getApplication() as LibreMusicApplication

    protected open val songs = listOf(
        Song("a1", "Blinding Lights", "The Weeknd", null),
        Song("a2", "Levitating", "Dua Lipa", null),
        Song("a3", "Quevedo: Bzrp Music Sessions, Vol. 52", "Bizarrap y Quevedo", null),
        Song("a4", "Flowers", "Miley Cyrus", null),
        Song("a5", "As It Was", "Harry Styles", null),
        Song("a6", "Tití Me Preguntó", "Bad Bunny", null),
    )

    protected open val albums = listOf(
        Triple("After Hours", "The Weeknd", "2020"),
        Triple("Un Verano Sin Ti", "Bad Bunny", "2022"),
        Triple("Future Nostalgia", "Dua Lipa", "2020"),
    )

    private fun seed() {
        val lib = app.library
        if (lib.data.value.playlists.isNotEmpty()) return
        songs.take(4).forEach { lib.toggleFavorite(it) }
        songs.forEach { lib.markPlayed(it) }
        val p1 = lib.createPlaylist("Para correr", songs.take(5))
        lib.updatePlaylist(p1.id) { it.copy(icon = "figure.run", tint = 3) }
        val p2 = lib.createPlaylist("Viaje a la playa", songs.drop(1))
        lib.updatePlaylist(p2.id) { it.copy(icon = "beach.umbrella.fill", tint = 4) }
        lib.createPlaylist("Noche", songs.take(2))
        // «Tus álbumes» (Fase 2C): dos álbumes guardados desde su página.
        albums.forEachIndexed { i, (title, artist, year) ->
            lib.importPlaylist(title, songs.drop(i).take(4), album = AlbumInfo("MPREb_$i", artist, year))
        }
    }

    protected fun shot(
        name: String,
        theme: AppTheme = AppTheme.Glass,
        deck: DeckStyle = DeckStyle.Normal,
        appearance: String = "light",
        playing: Boolean = true,
        guide: Boolean = false,
        artwork: Boolean = false,
        terms: Boolean = true,
        intro: String = "",
        firstSteps: Boolean = false,
        bar: String = "classic",
        discover: Boolean = true,
        setup: AppState.() -> Unit = {},
    ) {
        PlayerViewModel.connectToService = false
        HomeViewModel.offline = true
        Prefs.setOnboarded(!guide)
        Prefs.setTermsAccepted(terms)
        Prefs.setIntroStage(intro)
        Prefs.resetFirstSteps(hidden = !firstSteps)
        Prefs.setArtworkColorsApp(artwork); Prefs.setArtworkColorsPlayer(artwork)
        Prefs.setTheme(theme)
        Prefs.setDeck(deck)
        Prefs.setAppearance(appearance)
        Prefs.setBarStyle(bar)
        Prefs.setShowDiscover(discover)
        seed()
        val player = PlayerViewModel(app)
        if (playing) {
            player.preview(PlayerUiState(current = songs[0], isPlaying = false, positionMs = 74_000, durationMs = 200_000, queue = songs, index = 0))
        }
        val state = AppState().apply(setup)
        captureRoboImage("build/shots/$name.png") {
            IPhoneInsets {
                LibreMusicTheme {
                    LibreMusicRoot(state, player, LibraryViewModel(app), HomeViewModel(app), ReelsViewModel(app), forceReduceMotion = true)
                }
            }
        }
    }

    /**
     * Márgenes seguros del iPhone 16 (barra de estado 59 pt, indicador de inicio 34 pt): Robolectric
     * no tiene barras del sistema y, sin esto, todo saldría más arriba que en las capturas de iOS.
     */
    @Composable
    private fun IPhoneInsets(content: @Composable () -> Unit) {
        val view = LocalView.current
        LaunchedEffect(Unit) {
            val d = view.resources.displayMetrics.density
            val insets = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, (if (landscape) 0 else 59 * d).toInt(), 0, 0))
                .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, 0, ((if (landscape) 21 else 34) * d).toInt()))
                .setInsets(WindowInsetsCompat.Type.displayCutout(), Insets.of((if (landscape) 59 * d else 0f).toInt(), 0, 0, 0))
                .build()
            ViewCompat.dispatchApplyWindowInsets(view, insets)
        }
        content()
    }

}
