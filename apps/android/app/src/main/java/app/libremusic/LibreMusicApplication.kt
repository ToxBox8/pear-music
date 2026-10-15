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
        app.libremusic.data.Telemetry.processStart = android.os.SystemClock.elapsedRealtime()
        Prefs.init(this)
        I18n.init(this)
        app.libremusic.data.Account.init(this)
        app.libremusic.data.Incident.load(this)
        app.libremusic.data.AppIcon.migrateLegacy(this)
        YTClient.init(this)
        library = Library(this)
        app.libremusic.data.PlayStats.init(this)
        app.libremusic.data.AutoBackup.init(this)
        app.libremusic.data.PendingImports.init(this)
        Downloads.init(this)
        JamService.init(this)
        // Avisos: la copia guardada pinta la campana al instante y, si se quiere, se comprueban cada 15 min.
        app.libremusic.avisos.AvisosRepo.cargarCopia(this)
        if (app.libremusic.avisos.AvisosRepo.notificarActivado(this)) app.libremusic.avisos.AvisosWorker.programar(this)
    }
}
