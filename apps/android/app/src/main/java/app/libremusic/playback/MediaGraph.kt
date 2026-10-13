@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package app.libremusic.playback

import android.content.Context
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.offline.DownloadManager
import java.io.File
import java.util.concurrent.Executors

/**
 * Piezas de Media3 compartidas por el reproductor y las descargas (una sola instancia por proceso:
 * SimpleCache no admite dos instancias sobre la misma carpeta).
 *
 * Las canciones descargadas viven en la caché con la clave = videoId (customCacheKey), porque la
 * URL real de YouTube cambia en cada petición.
 */
object MediaGraph {
    private var database: StandaloneDatabaseProvider? = null
    private var cache: SimpleCache? = null
    private var manager: DownloadManager? = null

    @Synchronized
    private fun database(context: Context): StandaloneDatabaseProvider =
        database ?: StandaloneDatabaseProvider(context.applicationContext).also { database = it }

    @Synchronized
    fun downloadCache(context: Context): SimpleCache =
        cache ?: SimpleCache(
            File(context.applicationContext.filesDir, "downloads"),
            NoOpCacheEvictor(),
            database(context),
        ).also { cache = it }

    /** HTTP + resolución libremusic://track/ID → URL de audio. [streaming]: aplica «Ahorro de datos». */
    fun upstreamFactory(streaming: Boolean = false): DataSource.Factory {
        val http = DefaultHttpDataSource.Factory()
            .setConnectTimeoutMs(20_000)
            .setReadTimeoutMs(20_000)
            .setAllowCrossProtocolRedirects(true)
        val resolving = ResolvingDataSource.Factory(http) { spec ->
            StreamResolver.resolve(spec, lowQuality = streaming && app.libremusic.ui.theme.Prefs.quality.value == "low")
        }
        return DataSource.Factory {
            RetryForbiddenDataSource(resolving.createDataSource()) { id ->
                StreamResolver.invalidate(id)
                app.libremusic.data.YTClient.resetVisitorData()
            }
        }
    }

    /**
     * Si YouTube rechaza la URL con 403 (URL caducada o identificador de visitante viejo), pide un
     * identificador y una URL nuevos y lo intenta una vez más, sin que se note al escuchar ni al
     * descargar.
     */
    internal class RetryForbiddenDataSource(
        private val inner: DataSource,
        private val onForbidden: (videoId: String) -> Unit,
    ) : DataSource by inner {
        override fun open(dataSpec: androidx.media3.datasource.DataSpec): Long = try {
            inner.open(dataSpec)
        } catch (e: androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException) {
            val id = dataSpec.uri.takeIf { it.scheme == "libremusic" }?.lastPathSegment
            if (e.responseCode != 403 || id == null) throw e
            android.util.Log.w("LMStream", "403 en $id: identificador y URL nuevos")
            runCatching { inner.close() }
            onForbidden(id)
            inner.open(dataSpec)
        }
    }

    /**
     * Para el reproductor: lee de las descargas si la canción está, y si no va a la red.
     * No escribe en la caché (el streaming no ocupa espacio).
     */
    fun playbackDataSourceFactory(context: Context): DataSource.Factory =
        CacheDataSource.Factory()
            .setCache(downloadCache(context))
            .setUpstreamDataSourceFactory(upstreamFactory(streaming = true))
            .setCacheWriteDataSinkFactory(null)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

    @Synchronized
    fun downloadManager(context: Context): DownloadManager =
        manager ?: DownloadManager(
            context.applicationContext,
            database(context),
            downloadCache(context),
            upstreamFactory(),
            Executors.newFixedThreadPool(2),
        ).apply { maxParallelDownloads = 2 }.also { manager = it }

    /** Espacio que ocupan las descargas (bytes). */
    fun downloadBytes(context: Context): Long = runCatching { downloadCache(context).cacheSpace }.getOrDefault(0L)
}
