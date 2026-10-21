@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package app.libremusic.reels


import app.libremusic.L
import app.libremusic.data.Logs
import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import app.libremusic.data.Song
import app.libremusic.data.YTClient
import app.libremusic.playback.MediaGraph
import app.libremusic.playback.toMediaItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class ReelsState(
    val items: List<Song> = emptyList(),
    val index: Int = 0,
    val loading: Boolean = false,
    val failed: Boolean = false,
    val isPlaying: Boolean = false,
    val buffering: Boolean = false,
    val userPaused: Boolean = false,
    /** Avance dentro del fragmento de 30 s (0‥1). */
    val clipProgress: Float = 0f,
    val broken: Set<String> = emptySet(),
    /** «No me interesa» recién pulsado (canción y su sitio), para «Deshacer» durante 4 s. */
    val undo: Pair<Song, Int>? = null,
) {
    val current: Song? get() = items.getOrNull(index)
}

/**
 * Descubrir: feed vertical en el que cada canción suena 30 s desde la zona del estribillo, en bucle.
 * Port de `ReelsFeed` (apps/ios/Sources/Reels.swift). Usa un reproductor propio de vista previa;
 * al pedir el foco de audio, el reproductor principal se pausa solo (y al revés).
 */
class ReelsViewModel(app: Application) : AndroidViewModel(app) {
    private val _state = MutableStateFlow(ReelsState())
    val state: StateFlow<ReelsState> = _state.asStateFlow()

    private val known = HashSet<String>()
    private var visible = false
    private var loadingMore = false
    private var needsClipSetup = false
    private var clipStartMs = 0L
    private var clipEndMs = ReelClip.CLIP_MS
    private var activatedAt = 0L
    private var visibleAt = 0L

    private val player: ExoPlayer = ExoPlayer.Builder(app)
        // Empieza con medio segundo de audio (por defecto 2,5 s): el fragmento suena antes.
        .setLoadControl(
            androidx.media3.exoplayer.DefaultLoadControl.Builder()
                .setBufferDurationsMs(4_000, 20_000, 500, 1_000)
                .build(),
        )
        .setMediaSourceFactory(DefaultMediaSourceFactory(MediaGraph.playbackDataSourceFactory(app)))
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
            /* handleAudioFocus = */ true,
        )
        .build()

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY && needsClipSetup) {
                    needsClipSetup = false
                    val duration = player.duration.takeIf { it != C.TIME_UNSET } ?: 0L
                    clipStartMs = ReelClip.start(duration)
                    clipEndMs = ReelClip.end(clipStartMs, duration)
                    player.seekTo(clipStartMs)
                    if (visible && !_state.value.userPaused) player.play()
                }
                update()
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                // Medición (adb logcat -s LMPerf): desde que se elige el fragmento hasta que suena.
                if (isPlaying && activatedAt > 0L) {
                    // Desde que se elige el fragmento o se entra en Descubrir (lo que ocurra después).
                    val from = maxOf(activatedAt, visibleAt)
                    Logs.i("LMPerf", "reel_start_ms=${android.os.SystemClock.elapsedRealtime() - from}")
                    activatedAt = 0L
                }
                update()
            }

            override fun onPlayerError(error: PlaybackException) {
                val id = _state.value.current?.id ?: return
                _state.value = _state.value.copy(broken = _state.value.broken + id, buffering = false)
            }
        })
        // Bucle del fragmento y barra de progreso.
        viewModelScope.launch {
            while (isActive) {
                delay(200)
                if (player.isPlaying) {
                    val pos = player.currentPosition
                    if (pos >= clipEndMs) player.seekTo(clipStartMs)
                    val span = (clipEndMs - clipStartMs).coerceAtLeast(1)
                    _state.value = _state.value.copy(clipProgress = ((pos - clipStartMs).toFloat() / span).coerceIn(0f, 1f))
                }
            }
        }
    }

    private fun update() {
        _state.value = _state.value.copy(
            isPlaying = player.isPlaying,
            buffering = player.playbackState == Player.STATE_BUFFERING || needsClipSetup,
        )
    }

    /** Mezcla las radios de tres canciones que te gustan (o de una búsqueda si aún no hay ninguna). */
    fun load(seeds: List<Song>, exclude: Set<String>, force: Boolean = false) {
        val s = _state.value
        if (s.loading || (s.items.isNotEmpty() && !force)) return
        player.stop()
        _state.value = ReelsState(loading = true)
        viewModelScope.launch {
            val merged = withContext(Dispatchers.IO) {
                val pool = seeds.ifEmpty { runCatching { YTClient.search(L("éxitos del momento")) }.getOrDefault(emptyList()) }
                val radios = pool.shuffled().take(3)
                    .map { seed -> async { runCatching { YTClient.radio(seed.id) }.getOrDefault(emptyList()) } }
                    .awaitAll()
                // Intercaladas para que no salgan diez seguidas del mismo artista.
                buildList {
                    for (i in 0 until (radios.maxOfOrNull { it.size } ?: 0)) {
                        radios.forEach { r -> r.getOrNull(i)?.let(::add) }
                    }
                }
            }
            known.clear()
            known += exclude
            val items = app.libremusic.data.ReelsSkip.filter(merged).filter { known.add(it.id) }
            _state.value = ReelsState(items = items, failed = items.isEmpty())
            if (items.isNotEmpty()) activate()
        }
    }

    private fun loadMoreIfNeeded() {
        val s = _state.value
        val seed = s.items.lastOrNull() ?: return
        if (loadingMore || s.index < s.items.size - 4) return
        loadingMore = true
        viewModelScope.launch {
            val more = withContext(Dispatchers.IO) { runCatching { YTClient.radio(seed.id) }.getOrDefault(emptyList()) }
            _state.value = _state.value.copy(items = _state.value.items + app.libremusic.data.ReelsSkip.filter(more).filter { known.add(it.id) })
            loadingMore = false
        }
    }

    /** «No me interesa» (2.7 de x.1.1): se guarda, sale del feed y el siguiente ocupa su sitio. */
    fun notInterested(song: Song) {
        app.libremusic.data.ReelsSkip.add(song)
        val s = _state.value
        val i = s.items.indexOfFirst { it.id == song.id }
        if (i < 0) return
        val items = s.items.toMutableList().apply { removeAt(i) }
        _state.value = s.copy(items = items, index = s.index.coerceAtMost(items.lastIndex).coerceAtLeast(0), undo = song to i, clipProgress = 0f)
        if (items.isEmpty()) { player.stop(); return }
        activate()
        loadMoreIfNeeded()
    }

    fun undoNotInterested() {
        val (song, i) = _state.value.undo ?: return
        app.libremusic.data.ReelsSkip.remove(song.id)
        val items = _state.value.items.toMutableList().apply { add(i.coerceAtMost(size), song) }
        _state.value = _state.value.copy(items = items, index = i.coerceAtMost(items.lastIndex), undo = null, clipProgress = 0f)
        activate()
    }

    fun clearUndo() { _state.value = _state.value.copy(undo = null) }

    fun go(index: Int) {
        if (index == _state.value.index && player.mediaItemCount > 0) return
        _state.value = _state.value.copy(index = index, clipProgress = 0f)
        activate()
        loadMoreIfNeeded()
    }

    private fun activate() {
        val song = _state.value.current ?: return
        activatedAt = android.os.SystemClock.elapsedRealtime()
        val known = app.libremusic.playback.StreamResolver.knownDurationMs(song.id)
        if (known != null && known > 0) {
            // Duración ya conocida (URL pedida por adelantado): se carga directamente desde el
            // estribillo, sin cargar el principio y saltar después.
            needsClipSetup = false
            clipStartMs = ReelClip.start(known)
            clipEndMs = ReelClip.end(clipStartMs, known)
            player.setMediaItem(song.toMediaItem(), clipStartMs)
            player.playWhenReady = visible && !_state.value.userPaused
        } else {
            needsClipSetup = true
            player.setMediaItem(song.toMediaItem())
            player.playWhenReady = false
        }
        player.prepare()
        update()
        prefetchAfter(_state.value.index)
    }

    /** Pide ya las URLs de los dos fragmentos siguientes. */
    private fun prefetchAfter(index: Int) {
        val next = _state.value.items.drop(index + 1).take(2)
        if (next.isEmpty()) return
        val low = app.libremusic.ui.theme.Prefs.quality.value == "low"
        viewModelScope.launch(Dispatchers.IO) { next.forEach { app.libremusic.playback.StreamResolver.prefetch(it, low) } }
    }

    fun setVisible(value: Boolean) {
        if (value && !visible) visibleAt = android.os.SystemClock.elapsedRealtime()
        visible = value
        if (!value) {
            player.pause()
        } else if (!_state.value.userPaused && !needsClipSetup && player.mediaItemCount > 0) {
            // play() también sirve si aún carga: empezará en cuanto esté listo.
            player.play()
        }
    }

    fun toggle() {
        val paused = !_state.value.userPaused
        _state.value = _state.value.copy(userPaused = paused)
        if (paused) player.pause() else if (player.playbackState == Player.STATE_READY) player.play()
    }

    /** «Escuchar completa»: deja de sonar aquí para que suene en el reproductor principal. */
    fun yieldToMainPlayer() {
        player.pause()
        _state.value = _state.value.copy(userPaused = true)
    }

    override fun onCleared() {
        player.release()
    }
}
