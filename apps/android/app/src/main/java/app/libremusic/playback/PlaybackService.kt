@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package app.libremusic.playback


import app.libremusic.L
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import app.libremusic.LibreMusicApplication
import app.libremusic.AppActivity
import app.libremusic.R
import app.libremusic.data.Song
import app.libremusic.download.Downloads
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * Reproducción en segundo plano (equivalente a AVPlayer + AVAudioSession + MPNowPlaying en iOS).
 * Media3 publica la notificación multimedia y gestiona el servicio en primer plano.
 * Al ser un MediaLibraryService, Android Auto puede navegar la biblioteca ([BrowseTree]).
 */
class PlaybackService : MediaLibraryService() {

    private var mediaSession: MediaLibrarySession? = null

    override fun onCreate() {
        super.onCreate()
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()
        // Descargas primero (sin conexión), y si no, la red.
        val dataSource = MediaGraph.playbackDataSourceFactory(this)
        val player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSource))
            .setAudioAttributes(audioAttributes, /* handleAudioFocus = */ true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setLoadControl(audioLoadControl())
            .build()
        // Bucle (no / lista / canción): lo guarda el servicio para que valga también desde la
        // notificación, la pantalla de bloqueo o Android Auto con la app cerrada. Mismo ajuste que iOS.
        val prefs = getSharedPreferences("player", MODE_PRIVATE)
        player.repeatMode = Repeat.fromKey(prefs.getString("repeatMode", null))
        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                // URL caducada o rechazada: se pide otra al reintentar.
                player.currentMediaItem?.mediaId?.let(StreamResolver::invalidate)
            }
            override fun onRepeatModeChanged(repeatMode: Int) {
                prefs.edit().putString("repeatMode", Repeat.key(repeatMode)).apply()
                mediaSession?.setCustomLayout(ImmutableList.of(Repeat.button(repeatMode)))
            }
        })

        SleepTimer.attach(player)
        Fade.attach(player)
        Prefetch.attach(player)
        Normalizer.attach(player)
        AutoRadio.attach(player)
        PlayCounter.attach(player)
        LastQueue.attach(this, player)
        NowPlayingWidget.attach(this, player)
        Eq.attach(player.audioSessionId)
        player.addAnalyticsListener(object : androidx.media3.exoplayer.analytics.AnalyticsListener {
            override fun onAudioSessionIdChanged(eventTime: androidx.media3.exoplayer.analytics.AnalyticsListener.EventTime, audioSessionId: Int) {
                Eq.attach(audioSessionId)
            }
        })

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, AppActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        mediaSession = MediaLibrarySession.Builder(this, player, LibraryCallback())
            .setSessionActivity(openApp)
            .setCustomLayout(ImmutableList.of(Repeat.button(player.repeatMode)))
            .build()
    }

    private inner class LibraryCallback : MediaLibrarySession.Callback {
        private val library get() = (application as LibreMusicApplication).library.data.value
        private val downloads get() = Downloads.songs.value

        // El botón de bucle de la notificación es una orden propia que hay que permitir a cada mando.
        override fun onConnect(session: MediaSession, controller: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
            val base = super.onConnect(session, controller)
            return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                .setAvailableSessionCommands(base.availableSessionCommands.buildUpon().add(Repeat.command).build())
                .setAvailablePlayerCommands(base.availablePlayerCommands)
                .build()
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            if (customCommand.customAction == Repeat.ACTION) {
                session.player.repeatMode = Repeat.next(session.player.repeatMode)
                return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
            return super.onCustomCommand(session, controller, customCommand, args)
        }

        private fun folderItem(id: String, title: String, type: Int): MediaItem = MediaItem.Builder()
            .setMediaId(id)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(title)
                    .setIsBrowsable(true)
                    .setIsPlayable(false)
                    .setMediaType(type)
                    .build(),
            )
            .build()

        private fun songItem(folder: String, song: Song): MediaItem = MediaItem.Builder()
            .setMediaId(BrowseTree.leafId(folder, song.id))
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(song.title)
                    .setArtist(song.artist)
                    .setArtworkUri(song.thumb(544)?.let(Uri::parse))
                    .setIsBrowsable(false)
                    .setIsPlayable(true)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
                    .build(),
            )
            .build()

        private fun children(parentId: String): List<MediaItem>? = when (parentId) {
            BrowseTree.ROOT -> listOf(
                folderItem(BrowseTree.FAVORITES, getString(R.string.section_favorites), MediaMetadata.MEDIA_TYPE_PLAYLIST),
                folderItem(BrowseTree.DOWNLOADS, getString(R.string.section_downloads), MediaMetadata.MEDIA_TYPE_PLAYLIST),
                folderItem(BrowseTree.RECENTS, getString(R.string.section_recents), MediaMetadata.MEDIA_TYPE_PLAYLIST),
                folderItem(BrowseTree.PLAYLISTS, getString(R.string.section_playlists), MediaMetadata.MEDIA_TYPE_FOLDER_PLAYLISTS),
            )
            BrowseTree.PLAYLISTS -> library.playlists.map {
                folderItem(BrowseTree.playlistFolder(it.id), it.name, MediaMetadata.MEDIA_TYPE_PLAYLIST)
            }
            else -> BrowseTree.songsIn(parentId, library, downloads)?.map { songItem(parentId, it) }
        }

        /**
         * ¿Puede este mando recorrer la biblioteca (favoritas, playlists, recientes)? Sólo la propia app, el sistema
         * y los de confianza (Android Auto, el coche, Wear OS). Cualquier otra app instalada puede controlar la
         * reproducción, pero no leer qué escuchas.
         */
        private fun canBrowse(c: MediaSession.ControllerInfo): Boolean =
            c.packageName == packageName || c.isTrusted || c.packageName in TRUSTED_BROWSERS

        private fun <T : Any> denied(): ListenableFuture<LibraryResult<T>> =
            Futures.immediateFuture(LibraryResult.ofError<T>(LibraryResult.RESULT_ERROR_PERMISSION_DENIED))

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> = if (!canBrowse(browser)) denied() else Futures.immediateFuture(
            LibraryResult.ofItem(folderItem(BrowseTree.ROOT, getString(R.string.app_name), MediaMetadata.MEDIA_TYPE_FOLDER_MIXED), params),
        )

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            if (!canBrowse(browser)) return denied()
            val items = children(parentId)
                ?: return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE))
            val from = (page * pageSize).coerceAtMost(items.size)
            val to = (from + pageSize).coerceAtMost(items.size)
            return Futures.immediateFuture(LibraryResult.ofItemList(ImmutableList.copyOf(items.subList(from, to)), params))
        }

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> {
            if (!canBrowse(browser)) return denied()
            val leaf = BrowseTree.parseLeaf(mediaId)
            val song = leaf?.let { (folder, id) -> BrowseTree.songsIn(folder, library, downloads)?.firstOrNull { it.id == id } }
            return Futures.immediateFuture(
                if (song != null && leaf != null) {
                    LibraryResult.ofItem(songItem(leaf.first, song), null)
                } else {
                    LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE)
                },
            )
        }

        /**
         * «Reproducir» con el reproductor vacío (widget, auriculares, pantalla de bloqueo con la app cerrada):
         * se retoma la última cola donde se quedó.
         */
        override fun onPlaybackResumption(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            val saved = LastQueue.load(this@PlaybackService)
                ?: return Futures.immediateFailedFuture(UnsupportedOperationException(L("No hay nada que retomar")))
            return Futures.immediateFuture(
                MediaSession.MediaItemsWithStartPosition(LastQueue.mediaItems(saved), saved.index, saved.positionMs),
            )
        }

        /**
         * Desde Android Auto llega una sola canción "<carpeta>/<videoId>": se reproduce la carpeta
         * entera empezando por ella. Desde la app llegan videoIds sueltos (onAddMediaItems).
         */
        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            val leaf = mediaItems.singleOrNull()?.let { BrowseTree.parseLeaf(it.mediaId) }
            val songs = leaf?.let { (folder, _) -> BrowseTree.songsIn(folder, library, downloads) }
            if (leaf != null && songs != null) {
                val index = songs.indexOfFirst { it.id == leaf.second }.coerceAtLeast(0)
                return Futures.immediateFuture(
                    MediaSession.MediaItemsWithStartPosition(songs.map(Song::toMediaItem), index, C.TIME_UNSET),
                )
            }
            return super.onSetMediaItems(mediaSession, controller, mediaItems, startIndex, startPositionMs)
        }

        /**
         * Los MediaItem que llegan desde un controlador pierden la URI por seguridad;
         * se reconstruye a partir del mediaId (videoId).
         */
        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> = Futures.immediateFuture(
            mediaItems.map {
                val videoId = BrowseTree.parseLeaf(it.mediaId)?.second ?: it.mediaId
                it.buildUpon().setMediaId(videoId)
                    .setUri(trackUri(videoId, it.mediaMetadata.title?.toString(), it.mediaMetadata.artist?.toString()))
                    .setCustomCacheKey(videoId).build()
            }.toMutableList(),
        )
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? =
        mediaSession

    /**
     * Tecla multimedia con el servicio recién arrancado (widget o auriculares con la app cerrada): se carga antes la
     * última cola, para que «reproducir» la retome. Media3 no llama a onPlaybackResumption con estas teclas.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == Intent.ACTION_MEDIA_BUTTON) {
            val player = mediaSession?.player
            val saved = LastQueue.load(this)
            if (player != null && player.mediaItemCount == 0 && saved != null) {
                player.setMediaItems(LastQueue.mediaItems(saved), saved.index, saved.positionMs)
                player.prepare()
            }
        }
        return super.onStartCommand(intent, flags, startId)
    }

    /** Si el usuario cierra la app sin música sonando, se para el servicio. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = mediaSession?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        mediaSession?.player?.let(LastQueue::save)
        SleepTimer.detach()
        Fade.detach()
        AutoRadio.detach()
        PlayCounter.detach()
        NowPlayingWidget.detach(this)
        Eq.release()
        mediaSession?.run {
            player.release()
            release()
        }
        mediaSession = null
        super.onDestroy()
    }
}

/** Mandos que pueden recorrer la biblioteca además de la app y del sistema. */
private val TRUSTED_BROWSERS = setOf(
    "com.google.android.projection.gearhead", // Android Auto
    "com.android.car.media", // Android Automotive
    "com.google.android.carassistant",
    "com.google.android.wearable.app", // Wear OS
    "com.google.android.apps.wearable.phone",
)
