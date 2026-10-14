package app.libremusic

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import app.libremusic.jam.JamLink
import app.libremusic.ui.LibreMusicApp
import app.libremusic.ui.theme.LibreMusicTheme

class AppActivity : ComponentActivity() {

    /** Código recibido por libremusic://jam/CÓDIGO (QR, enlace compartido…). */
    private var jamCode by mutableStateOf<String?>(null)

    private val notificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* opcional */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        jamCode = JamLink.codeFrom(intent?.dataString)
        app.libremusic.data.AppShortcuts.handle(intent)
        app.libremusic.data.AppShortcuts.publish(this)
        abrirAvisosSi(intent)
        askForNotifications()
        setContent {
            LibreMusicTheme {
                LibreMusicApp(
                    jamCode = jamCode,
                    onDismissJam = { jamCode = null },
                    // Iconos de la barra de estado claros u oscuros según lo que se ve (tema, Descubrir…).
                    onBarsDark = { dark ->
                        val style = if (dark) SystemBarStyle.dark(Color.TRANSPARENT) else SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                        enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
                    },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        JamLink.codeFrom(intent.dataString)?.let { jamCode = it }
        app.libremusic.data.AppShortcuts.handle(intent)
        abrirAvisosSi(intent)
    }

    private fun abrirAvisosSi(intent: Intent?) {
        if (intent?.getBooleanExtra(app.libremusic.avisos.AvisosWorker.EXTRA_ABRIR_AVISOS, false) == true) {
            app.libremusic.avisos.AvisosRepo.abrir.value = true
        }
    }

    /** Android 13+: sin este permiso no se ve la notificación con los controles de la música. */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // Copia automática de la biblioteca (una al día) al abrir y al salir de la app.
    override fun onStart() {
        super.onStart()
        app.libremusic.data.AutoBackup.backupSoon(this, (application as LibreMusicApplication).library)
    }

    override fun onStop() {
        super.onStop()
        app.libremusic.data.AutoBackup.backupSoon(this, (application as LibreMusicApplication).library)
    }
}
