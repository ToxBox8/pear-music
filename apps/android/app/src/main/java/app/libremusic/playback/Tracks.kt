package app.libremusic.playback

import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.datasource.DataSpec
import app.libremusic.data.Song
import app.libremusic.data.YTClient
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap

/**
 * URI interna de una canción: se resuelve a la URL real de audio justo antes de reproducirla.
 * Lleva el título y el artista para buscar otra subida si YouTube no deja reproducir esta.
 */
fun trackUri(videoId: String, title: String? = null, artist: String? = null): Uri =
    Uri.parse("libremusic://track/$videoId").buildUpon().apply {
        if (!title.isNullOrBlank()) appendQueryParameter("t", title)
        if (!artist.isNullOrBlank()) appendQueryParameter("a", artist)
    }.build()

fun Song.toMediaItem(): MediaItem = MediaItem.Builder()
    .setMediaId(id)
    .setUri(trackUri(id, title, artist))
    .setCustomCacheKey(id) // las descargas se guardan con esta clave
    .setMediaMetadata(
        MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setArtworkUri(thumb(544)?.let(Uri::parse))
            .build(),
    )
    .build()

fun MediaItem.toSong(): Song = Song(
    id = mediaId,
    title = mediaMetadata.title?.toString().orEmpty(),
    artist = mediaMetadata.artist?.toString().orEmpty(),
    thumbnail = mediaMetadata.artworkUri?.toString(),
)

/**
 * Resuelve libremusic://track/ID → URL de audio de YouTube con el User-Agent de su cliente.
 * Las URLs caducan a las ~6 h; se guardan 3 h para no pedirlas en cada salto o reintento.
 */
object StreamResolver {
    private const val TTL_MS = 3 * 60 * 60 * 1000L
    private class Entry(val info: YTClient.StreamInfo, val at: Long)
    private val cache = ConcurrentHashMap<String, Entry>()

    /**
     * [lowQuality]: «Ahorro de datos» en Ajustes (sólo al escuchar en streaming).
     * Las descargas piden siempre la máxima, como en iOS.
     */
    fun resolve(spec: DataSpec, lowQuality: Boolean = false): DataSpec {
        if (spec.uri.scheme != "libremusic") return spec
        val id = spec.uri.lastPathSegment ?: throw IOException("Canción sin identificador")
        val now = System.currentTimeMillis()
        val key = if (lowQuality) "$id|low" else id
        val info = cache[key]?.takeIf { now - it.at < TTL_MS }?.info
            ?: YTClient.playableStream(id, spec.uri.getQueryParameter("t"), spec.uri.getQueryParameter("a"), lowQuality)
                .also { cache[key] = Entry(it, now) }
        val headers = mutableMapOf("User-Agent" to info.userAgent)
        // Sin «Range», Media3 pide el archivo entero y YouTube lo sirve a ~30 KB/s (casi a la
        // velocidad de reproducción): las descargas tardaban minutos y cada canción tardaba en
        // empezar. Con «Range: bytes=0-» va a la velocidad de la conexión. Si la posición no es 0,
        // Media3 ya pone su propio Range.
        if (spec.position == 0L && spec.length == androidx.media3.common.C.LENGTH_UNSET.toLong()) headers["Range"] = "bytes=0-"
        return spec.withUri(Uri.parse(info.url)).withAdditionalHeaders(headers)
    }

    /** Pide ya la URL (Descubrir: las dos siguientes) para que el fragmento empiece sin esperar. */
    fun prefetch(song: Song, lowQuality: Boolean) {
        val key = if (lowQuality) "${song.id}|low" else song.id
        if (cache[key]?.let { System.currentTimeMillis() - it.at < TTL_MS } == true) return
        runCatching { YTClient.playableStream(song.id, song.title, song.artist, lowQuality) }
            .onSuccess { cache[key] = Entry(it, System.currentTimeMillis()) }
    }

    /** Duración ya conocida (de una URL pedida antes), o null. */
    fun knownDurationMs(id: String): Long? = (cache[id] ?: cache["$id|low"])?.info?.durationMs

    /** Sonoridad de la canción si ya se resolvió (ver [YTClient.StreamInfo.loudnessDb]). */
    fun loudnessDb(id: String): Double? = (cache[id] ?: cache["$id|low"])?.info?.loudnessDb

    /** Tras un error de reproducción, se pide una URL nueva la próxima vez. */
    fun invalidate(id: String) {
        cache.remove(id)
        cache.remove("$id|low")
    }
}
