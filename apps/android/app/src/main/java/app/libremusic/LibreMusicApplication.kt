package app.libremusic

import android.app.Application
import app.libremusic.data.Library
import app.libremusic.data.YTClient
import app.libremusic.download.Downloads
import app.libremusic.jam.JamService
import app.libremusic.ui.theme.Prefs

class LibreMusicApplication : Application() {
    lateinit var library: Library
        private set

    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        YTClient.init(this)
        library = Library(this)
        app.libremusic.data.PlayStats.init(this)
        app.libremusic.data.AutoBackup.init(this)
        app.libremusic.data.PendingImports.init(this)
        Downloads.init(this)
        JamService.init(this)
    }
}
