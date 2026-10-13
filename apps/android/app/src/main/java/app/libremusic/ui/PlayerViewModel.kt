package app.libremusic.ui

import android.app.Application
import android.content.ComponentName
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import app.libremusic.LibreMusicApplication
import app.libremusic.data.Song
import app.libremusic.data.YTClient
import app.libremusic.playback.PlaybackService
import app.libremusic.playback.toMediaItem
import app.libremusic.playback.toSong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class PlayerUiState(
    val current: Song? = null,
    val isPlaying: Boolean = false,
    val isBuffering: Boolean = false,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val queue: List<Song> = emptyList(),
    val index: Int = 0,
    val error: String? = null,
    val rate: Float = 1f,
    /** Bucle: Player.REPEAT_MODE_OFF / ALL / ONE (lo guarda PlaybackService). */
    val repeatMode: Int = Player.REPEAT_MODE_OFF,
) {
    val progress: Double get() = positionMs / 1000.0
    val duration: Double get() = durationMs / 1000.0
}

/** Conecta la interfaz con [PlaybackService] a través de un MediaController. */
class PlayerViewModel(app: Application) : AndroidViewModel(app) {
    private val library = (app as LibreMusicApplication).library
    private var lastPlayedId: String? = null

    private val _state = MutableStateFlow(PlayerUiState())
    val state: StateFlow<PlayerUiState> = _state.asStateFlow()

    private var controller: MediaController? = null

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) = sync()
        override fun onPlayerError(error: PlaybackException) {
            _state.value = _state.value.copy(
                error = "No se pudo reproducir: ${error.cause?.message ?: error.errorCodeName}",
            )
        }
    }

    init {
        if (connectToService) viewModelScope.launch {
            val token = SessionToken(app, ComponentName(app, PlaybackService::class.java))
            val c = MediaController.Builder(app, token).buildAsync().await()
            controller = c
            c.addListener(listener)
            sync()
            // Progreso de la barra: se lee dos veces por segundo mientras la app está abierta.
            while (isActive) {
                delay(500)
                controller?.let {
                    _state.value = _state.value.copy(
                        positionMs = it.currentPosition.coerceAtLeast(0),
                        durationMs = it.duration.coerceAtLeast(0),
                    )
                }
            }
        }
    }

    private fun sync() {
        val c = controller ?: return
        val queue = (0 until c.mediaItemCount).map { c.getMediaItemAt(it).toSong() }
        val current = c.currentMediaItem?.toSong()
        // Recientes: se apunta cada canción cuando empieza a sonar.
        if (current != null && current.id != lastPlayedId && c.isPlaying) {
            lastPlayedId = current.id
            library.markPlayed(current)
        }
        _state.value = _state.value.copy(
            current = current,
            isPlaying = c.isPlaying,
            isBuffering = c.playbackState == Player.STATE_BUFFERING,
            queue = queue,
            index = c.currentMediaItemIndex,
            positionMs = c.currentPosition.coerceAtLeast(0),
            durationMs = c.duration.coerceAtLeast(0),
            rate = c.playbackParameters.speed,
            repeatMode = c.repeatMode,
        )
    }

    /** Reproduce [songs] empezando en [index]. Con una sola canción, la cola se completa con su radio. */
    fun play(songs: List<Song>, index: Int = 0) {
        val c = controller ?: return
        _state.value = _state.value.copy(error = null)
        c.setMediaItems(songs.map(Song::toMediaItem), index, 0)
        c.prepare()
        c.play()
        // Con la radio infinita activada ya la añade AutoRadio en el servicio (si no, saldría repetida).
        if (songs.size == 1 && !app.libremusic.playback.AutoRadio.enabled) extendWithRadio(songs.first())
    }

    private fun extendWithRadio(seed: Song) {
        viewModelScope.launch {
            val more = withContext(Dispatchers.IO) { runCatching { YTClient.radio(seed.id) }.getOrDefault(emptyList()) }
            val c = controller ?: return@launch
            if (c.currentMediaItem?.mediaId == seed.id && more.isNotEmpty()) {
                c.addMediaItems(more.map(Song::toMediaItem))
            }
        }
    }

    fun addToQueue(song: Song) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) play(listOf(song)) else c.addMediaItem(song.toMediaItem())
    }

    fun playNext(song: Song) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) play(listOf(song)) else c.addMediaItem(c.currentMediaItemIndex + 1, song.toMediaItem())
    }

    fun togglePlay() {
        val c = controller ?: return
        if (c.isPlaying) {
            c.pause()
        } else {
            if (c.playbackState == Player.STATE_IDLE) c.prepare()
            c.play()
        }
    }

    fun pause() { controller?.pause() }
    fun resume() {
        val c = controller ?: return
        if (c.playbackState == Player.STATE_IDLE) c.prepare()
        c.play()
    }

    /** Velocidad x1, x1,25, x1,5, x2, x0,75 (el dial «x1» de Air). */
    fun setRate(r: Float) { controller?.setPlaybackSpeed(r) }
    fun cycleRepeat() { controller?.let { it.repeatMode = app.libremusic.playback.Repeat.next(it.repeatMode) } }

    fun move(from: Int, to: Int) { controller?.moveMediaItem(from, to) }

    /** Vacía lo que queda por sonar después de la canción actual. */
    fun clearUpcoming() {
        val c = controller ?: return
        val after = c.currentMediaItemIndex + 1
        if (after < c.mediaItemCount) c.removeMediaItems(after, c.mediaItemCount)
    }

    fun seekSeconds(s: Double) { controller?.seekTo((s * 1000).toLong().coerceAtLeast(0)) }

    fun next() = controller?.seekToNextMediaItem()
    fun previous() = controller?.seekToPrevious()
    fun seekTo(ms: Long) = controller?.seekTo(ms)
    fun skipTo(index: Int) = controller?.seekToDefaultPosition(index)
    fun removeFromQueue(index: Int) = controller?.removeMediaItem(index)
    fun dismissError() {
        _state.value = _state.value.copy(error = null)
    }

    /** Sólo para las capturas de pantalla: estado fijo sin servicio de reproducción. */
    @androidx.annotation.VisibleForTesting
    fun preview(state: PlayerUiState) {
        _state.value = state
    }

    companion object {
        /** Las capturas de pantalla (Robolectric) no arrancan el servicio de reproducción. */
        @androidx.annotation.VisibleForTesting
        var connectToService = true
    }

    override fun onCleared() {
        controller?.removeListener(listener)
        controller?.release()
        controller = null
    }
}
