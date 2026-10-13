package app.libremusic.ui

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.libremusic.LibreMusicApplication
import app.libremusic.R
import app.libremusic.data.LibraryData
import app.libremusic.data.Playlist
import app.libremusic.data.Song
import app.libremusic.download.DownloadStatus
import app.libremusic.download.Downloads
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Biblioteca (favoritos, playlists, recientes), descargas e importar/exportar. */
class LibraryViewModel(app: Application) : AndroidViewModel(app) {
    val library = (app as LibreMusicApplication).library

    val data: StateFlow<LibraryData> = library.data
    val coverVersion: StateFlow<Int> = library.coverVersion

    /**
     * «Descargar todo» en curso, por lista (id de la playlist o «favorites»). Antes era un único
     * conjunto para toda la app: una playlist que compartía canciones con la que se estaba
     * descargando también decía «Descargando… · Detener», y «Detener» paraba la otra.
     */
    private val _bulk = MutableStateFlow<Map<String, Set<String>>>(emptyMap())
    val bulk: StateFlow<Map<String, Set<String>>> = _bulk.asStateFlow()
    /** Listas con «Descargar todo» en pausa: lo bajado se queda y «Reanudar» sigue con lo que falta. */
    private val _paused = MutableStateFlow<Set<String>>(emptySet())
    val paused: StateFlow<Set<String>> = _paused.asStateFlow()
    val downloads: StateFlow<Map<String, DownloadStatus>> = Downloads.status
    val downloadedSongs: StateFlow<List<Song>> = Downloads.songs

    /** Avisos breves para la interfaz (importación, errores…). */
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    init {
        // El progreso de las descargas en curso se refresca mientras la pantalla está abierta.
        viewModelScope.launch {
            while (isActive) {
                delay(1_000)
                if (Downloads.hasActive) Downloads.refresh()
            }
        }
    }

    private fun text(id: Int, vararg args: Any): String = getApplication<Application>().getString(id, *args)

    fun toggleFavorite(song: Song) = library.toggleFavorite(song)

    fun toggleDownload(song: Song) {
        val status = downloads.value[song.id]
        if (status != null && (status.isDone || status.isActive)) {
            Downloads.remove(getApplication(), song.id)
        } else {
            Downloads.download(getApplication(), song)
        }
    }

    /** Descarga las que falten de [songs] (sólo esas) y lo apunta a la lista [owner]. */
    fun downloadAll(owner: String, songs: List<Song>) {
        val pending = Downloads.pendingOf(songs, downloads.value)
        _paused.value = _paused.value - owner
        _bulk.value = _bulk.value + (owner to songs.map { it.id }.toSet())
        Downloads.downloadAll(getApplication(), pending)
    }

    /**
     * Detiene «Descargar todo» de [owner]: quita de la cola las suyas que aún no han terminado,
     * salvo las que otra lista también está descargando.
     */
    fun cancelBulk(owner: String) {
        _paused.value = _paused.value - owner
        val mine = _bulk.value[owner] ?: return
        val others = (_bulk.value - owner).values.flatten().toSet()
        val st = downloads.value
        mine.filter { it !in others && st[it]?.isActive == true }.forEach { Downloads.remove(getApplication(), it) }
        _bulk.value = _bulk.value - owner
    }

    /** Para sin olvidar la lista: la pantalla ofrece «Reanudar». */
    fun pauseBulk(owner: String) {
        cancelBulk(owner)
        _paused.value = _paused.value + owner
    }

    fun removeDownload(song: Song) = Downloads.remove(getApplication(), song.id)

    fun isFavorite(song: Song): Boolean = data.value.favorites.any { it.id == song.id }

    fun coverFile(id: String) = library.coverFile(id)

    fun renamePlaylist(id: String, name: String) {
        val n = name.trim()
        if (n.isNotEmpty()) library.updatePlaylist(id) { it.copy(name = n) }
    }

    fun setIcon(id: String, icon: String?) = library.updatePlaylist(id) { it.copy(icon = icon) }
    fun setTint(id: String, tint: Int) = library.updatePlaylist(id) { it.copy(tint = tint) }

    fun setCover(id: String, uri: Uri?) {
        viewModelScope.launch {
            val bytes = if (uri == null) null else withContext(Dispatchers.IO) {
                runCatching { getApplication<Application>().contentResolver.openInputStream(uri)!!.use { it.readBytes() } }.getOrNull()
            }
            withContext(Dispatchers.IO) { library.setCover(id, bytes) }
        }
    }

    /** Guarda un álbum o playlist de YouTube Music en la biblioteca, con su portada. */
    fun saveCollection(
        name: String, songs: List<Song>, coverUrl: String?, album: app.libremusic.data.AlbumInfo? = null,
        onSaved: (Playlist) -> Unit = {},
    ) {
        viewModelScope.launch {
            val cover = coverUrl?.let { url ->
                withContext(Dispatchers.IO) {
                    runCatching {
                        app.libremusic.data.YTClient.http.newCall(okhttp3.Request.Builder().url(url).build()).execute().use { it.body?.bytes() }
                    }.getOrNull()
                }
            }
            onSaved(withContext(Dispatchers.IO) { library.importPlaylist(name, songs, cover, album) })
        }
    }

    fun createPlaylist(name: String, firstSong: Song? = null): Playlist? =
        if (name.isBlank()) null else library.createPlaylist(name, listOfNotNull(firstSong))

    fun deletePlaylist(id: String) = library.deletePlaylist(id)
    fun addToPlaylist(playlistId: String, song: Song) = library.addToPlaylist(playlistId, song)
    fun removeFromPlaylist(playlistId: String, songId: String) = library.removeFromPlaylist(playlistId, songId)

    fun exportTo(uri: Uri) {
        viewModelScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching {
                    getApplication<Application>().contentResolver.openOutputStream(uri, "wt")!!.use {
                        it.write(library.exportJson().toByteArray())
                    }
                }.isSuccess
            }
            _message.value = text(if (ok) R.string.export_done else R.string.export_failed)
        }
    }

    fun importFrom(uri: Uri) {
        viewModelScope.launch {
            val json = withContext(Dispatchers.IO) {
                runCatching {
                    getApplication<Application>().contentResolver.openInputStream(uri)!!.use { it.readBytes().decodeToString() }
                }.getOrNull()
            }
            val result = json?.let { runCatching { library.importJson(it) }.getOrNull() }
            _message.value = if (result == null) {
                text(R.string.import_failed)
            } else {
                text(R.string.import_done, result.first, result.second)
            }
        }
    }

    fun dismissMessage() {
        _message.value = null
    }
}
