@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package app.libremusic.download

import android.content.Context
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.offline.DownloadService
import app.libremusic.data.Song
import app.libremusic.playback.MediaGraph
import app.libremusic.playback.trackUri
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

/** Estado de una descarga para la interfaz. */
data class DownloadStatus(val state: Int, val percent: Float) {
    val isDone get() = state == Download.STATE_COMPLETED
    val isActive get() = state == Download.STATE_QUEUED || state == Download.STATE_DOWNLOADING || state == Download.STATE_RESTARTING
    val isFailed get() = state == Download.STATE_FAILED
}

/**
 * Descargas de canciones para escuchar sin conexión (equivalente a DownloadStore en iOS).
 * Todas las llamadas desde el hilo principal.
 */
object Downloads {
    private val _status = MutableStateFlow<Map<String, DownloadStatus>>(emptyMap())
    val status: StateFlow<Map<String, DownloadStatus>> = _status.asStateFlow()

    /** Canciones descargadas por completo, la más reciente primero. */
    private val _songs = MutableStateFlow<List<Song>>(emptyList())
    val songs: StateFlow<List<Song>> = _songs.asStateFlow()

    private var manager: DownloadManager? = null

    fun init(context: Context) {
        val dm = MediaGraph.downloadManager(context)
        manager = dm
        val appContext = context.applicationContext
        dm.addListener(object : DownloadManager.Listener {
            override fun onInitialized(downloadManager: DownloadManager) {
                refresh()
                resumePending(appContext)
            }
            override fun onDownloadChanged(downloadManager: DownloadManager, download: Download, finalException: Exception?) = refresh()
            override fun onDownloadRemoved(downloadManager: DownloadManager, download: Download) = refresh()
        })
        refresh()
    }

    /**
     * Media3 deja las descargas en pausa hasta que arranca [LibreDownloadService], y el servicio sólo
     * arrancaba al pedir una descarga nueva: si Android cerraba la app a medias, la cola se quedaba
     * parada. Al abrir la app se reanuda lo que quedara pendiente.
     */
    private fun resumePending(context: Context) {
        if (!hasActive) return
        runCatching { DownloadService.start(context, LibreDownloadService::class.java) }
    }

    /** Relee el índice de descargas (y el progreso de las que están en curso). */
    fun refresh() {
        val dm = manager ?: return
        val status = HashMap<String, DownloadStatus>()
        val done = mutableListOf<Pair<Long, Song>>()
        runCatching {
            dm.downloadIndex.getDownloads().use { cursor ->
                while (cursor.moveToNext()) {
                    val d = cursor.download
                    status[d.request.id] = DownloadStatus(d.state, d.percentDownloaded)
                    if (d.state == Download.STATE_COMPLETED) songOf(d)?.let { done += d.updateTimeMs to it }
                }
            }
        }
        // El índice guarda el progreso con retraso; las descargas en curso se leen en directo.
        dm.currentDownloads.forEach { d -> status[d.request.id] = DownloadStatus(d.state, d.percentDownloaded) }
        _status.value = status
        _songs.value = done.sortedByDescending { it.first }.map { it.second }
    }

    val hasActive: Boolean get() = _status.value.values.any { it.isActive }

    fun download(context: Context, song: Song) {
        val request = DownloadRequest.Builder(song.id, trackUri(song.id, song.title, song.artist))
            .setCustomCacheKey(song.id)
            .setData(song.toJson().toString().toByteArray())
            .build()
        DownloadService.sendAddDownload(context, LibreDownloadService::class.java, request, false)
    }

    /** Las de [songs] que no están descargadas ni en cola (y nada que no esté en [songs]). */
    fun pendingOf(songs: List<Song>, status: Map<String, DownloadStatus>): List<Song> =
        songs.distinctBy { it.id }.filter { status[it.id]?.let { s -> s.isDone || s.isActive } != true }

    fun downloadAll(context: Context, songs: List<Song>) {
        pendingOf(songs, _status.value).forEach { download(context, it) }
    }

    fun remove(context: Context, id: String) {
        DownloadService.sendRemoveDownload(context, LibreDownloadService::class.java, id, false)
    }

    private fun songOf(d: Download): Song? =
        runCatching { Song.fromJson(JSONObject(String(d.request.data))) }.getOrNull()
}
