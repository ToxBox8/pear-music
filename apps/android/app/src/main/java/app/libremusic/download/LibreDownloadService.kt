@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package app.libremusic.download

import android.app.Notification
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadNotificationHelper
import androidx.media3.exoplayer.offline.DownloadService
import androidx.media3.exoplayer.scheduler.Scheduler
import app.libremusic.R
import app.libremusic.playback.MediaGraph

/** Servicio en primer plano que descarga canciones aunque se cierre la app. */
class LibreDownloadService : DownloadService(
    NOTIFICATION_ID,
    DownloadService.DEFAULT_FOREGROUND_NOTIFICATION_UPDATE_INTERVAL,
    CHANNEL_ID,
    R.string.downloads_channel,
    0,
) {
    override fun getDownloadManager(): DownloadManager = MediaGraph.downloadManager(this)

    override fun getScheduler(): Scheduler? = null

    override fun getForegroundNotification(downloads: MutableList<Download>, notMetRequirements: Int): Notification =
        DownloadNotificationHelper(this, CHANNEL_ID).buildProgressNotification(
            this,
            R.drawable.ic_stat_download,
            null,
            null,
            downloads,
            notMetRequirements,
        )

    companion object {
        const val CHANNEL_ID = "downloads"
        const val NOTIFICATION_ID = 2
    }
}
