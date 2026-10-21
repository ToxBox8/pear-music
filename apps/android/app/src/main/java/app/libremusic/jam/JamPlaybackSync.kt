package app.libremusic.jam

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import app.libremusic.ui.PlayerViewModel
import kotlinx.coroutines.delay

/**
 * «Cada uno en su móvil» (v2.1, 2.6 de x.1.1). El anfitrión cuenta lo que suena (al cambiar de canción o de pausa y
 * cada 5 s, así un salto llega enseguida); cada invitado lo sigue con **su propio audio** y cada 2 s compara dónde va
 * con dónde debería ir: más de 250 ms, salta; entre 60 y 250 ms, acelera o frena un 3 % hasta alcanzarlo. Nunca se
 * transmite sonido. Igual que `JamPlaybackSync` en iOS.
 */
@Composable
fun JamPlaybackSync(player: PlayerViewModel) {
    val jam by JamService.state.collectAsState()
    val st by player.state.collectAsState()
    val everyone = jam.jam?.mode == JamSync.EVERYONE

    if (jam.phase == JamPhase.Hosting && everyone) {
        LaunchedEffect(st.current?.id, st.isPlaying) {
            while (true) {
                JamService.hostPlayback(st.current, player.livePosition() ?: st.positionMs, st.isPlaying)
                delay(HOST_EVERY_MS)
            }
        }
    }

    if (jam.phase == JamPhase.Joined && everyone && jam.listenHere) {
        val remote by JamService.remotePlay.collectAsState()
        LaunchedEffect(remote) {
            val r = remote ?: return@LaunchedEffect
            val song = r.song
            if (song == null) { player.pause(); return@LaunchedEffect }
            if (player.state.value.current?.id != song.id) player.play(listOf(song), 0)
            if (!r.playing) {
                player.pause()
                player.seekTo(r.positionMs)
                return@LaunchedEffect
            }
            while (true) {
                val now = player.state.value
                if (!now.isPlaying && !now.isBuffering) player.resume()
                val actual = player.livePosition()
                // Mientras carga, la posición no avanza: corregir ahí haría saltar una y otra vez.
                if (actual != null && !now.isBuffering) {
                    val expected = JamSync.expected(r, System.currentTimeMillis(), JamService.clockOffset ?: 0L)
                    when (val c = JamSync.correct(expected, actual)) {
                        is JamSync.Correction.Seek -> { player.setRate(1f); player.seekTo(c.toMs) }
                        is JamSync.Correction.Speed -> player.setRate(c.rate)
                        JamSync.Correction.None -> player.setRate(1f)
                    }
                }
                delay(CHECK_EVERY_MS)
            }
        }
        DisposableEffect(Unit) { onDispose { player.setRate(1f) } }
    }
}

private const val HOST_EVERY_MS = 5_000L
private const val CHECK_EVERY_MS = 2_000L
