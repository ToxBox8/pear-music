package app.libremusic.ui

import app.libremusic.data.Lyrics
import app.libremusic.data.LyricsClient
import app.libremusic.data.PlayStats
import app.libremusic.data.Song
import app.libremusic.playback.SleepTimer
import app.libremusic.ui.theme.AppTheme
import app.libremusic.ui.theme.DeckStyle
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * Capturas para la web de descarga (`build/shots/web/`): las mismas pantallas, con portadas abstractas propias
 * (`src/test/resources/web-covers`, sin derechos de terceros) y canciones y artistas inventados.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w393dp-h852dp-port-xxhdpi")
class WebShotTest : ShotBase() {
    private fun cover(i: Int): String {
        val url = javaClass.getResource("/web-covers/cover$i.jpg") ?: error("Falta web-covers/cover$i.jpg")
        return "file://" + File(url.toURI()).absolutePath
    }

    override val songs = listOf(
        Song("w1", "Luz de neón", "Aurora Vela", cover(1)),
        Song("w2", "Marea alta", "Los Faros", cover2()),
        Song("w3", "Verano en Cádiz", "Sol de Poniente", cover(3)),
        Song("w4", "Norte", "Bosque Interior", cover(4)),
        Song("w5", "Calma", "Nube Rosa", cover(5)),
        Song("w6", "Medianoche", "Aurora Vela", cover(6)),
    )
    private fun cover2() = cover(2)

    override val albums = listOf(
        Triple("Ciudad dormida", "Aurora Vela", "2026"),
        Triple("Rompeolas", "Los Faros", "2025"),
        Triple("Brújula", "Bosque Interior", "2026"),
    )

    private fun web(name: String, theme: AppTheme = AppTheme.Glass, deck: DeckStyle = DeckStyle.Normal, appearance: String = "light", playing: Boolean = true, artwork: Boolean = false, setup: AppState.() -> Unit) =
        shot("web/$name", theme, deck, appearance, playing, artwork = artwork, setup = setup)

    @Test fun biblioteca() = web("biblioteca") { tab = Tab.Library }
    @Test fun bibliotecaOscura() = web("biblioteca-oscura", appearance = "dark") { tab = Tab.Library }
    @Test fun reproductor() = web("reproductor", artwork = true) { showPlayer = true }
    @Test fun reproductorOscuro() = web("reproductor-oscuro", appearance = "dark", artwork = true) { showPlayer = true }
    @Test fun casete() = web("casete", deck = DeckStyle.Cassette) { showPlayer = true }
    @Test fun vinilo() = web("vinilo", deck = DeckStyle.Vinyl, appearance = "dark") { showPlayer = true }
    @Test fun air() = web("air", AppTheme.Air, DeckStyle.Air) { showPlayer = true }
    @Test fun neon() = web("neon", AppTheme.Neon) { tab = Tab.Library }
    @Test fun albumes() = web("albumes") { tab = Tab.Library; push(Route.Albums) }
    @Test fun ajustes() = web("ajustes", playing = false) { tab = Tab.Settings }
    @Test fun colores() = web("colores", artwork = true) { tab = Tab.Settings; push(Route.ArtworkColors) }

    @Test fun letra() {
        LyricsClient.seed(songs[0].id, Lyrics(Lyrics.parseLrc(
            "[00:55.00] Las calles brillan cuando tú no estás\n[01:01.00] y la ciudad se queda sin hablar\n" +
                "[01:08.00] Enciendo una luz de neón\n[01:14.00] para encontrarte en la canción\n" +
                "[01:19.00] Medianoche en la avenida\n[01:24.00] todo suena a despedida\n[01:30.00] Luz de neón, luz de neón",
        ), null))
        web("letra", artwork = true) { showPlayer = true; initialPanel = PlayerPanel.Lyrics }
    }

    @Test fun temporizador() = try {
        SleepTimer.start(30)
        web("temporizador", appearance = "dark", artwork = true) { showPlayer = true }
    } finally { SleepTimer.cancel() }

    @Test fun estadisticas() {
        val now = System.currentTimeMillis() / 1000
        PlayStats.init(RuntimeEnvironment.getApplication())
        listOf(0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5, 0, 1, 3).forEachIndexed { i, k -> PlayStats.record(songs[k], now - i * 900L) }
        try { web("estadisticas", playing = false) { tab = Tab.Library; push(Route.Stats) } } finally { PlayStats.clear() }
    }
}
