package app.libremusic.avisos


import app.libremusic.L
import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.libremusic.AppActivity
import app.libremusic.R
import java.util.concurrent.TimeUnit

/**
 * Comprueba los avisos en segundo plano y notifica los nuevos, como el RssFeedNotifyWork de SimpMusic
 * (que lee su blog cada 24 h): aquí cada 15 min, el mínimo que permite WorkManager, porque un aviso
 * («la app no suena») pierde sentido si llega al día siguiente.
 */
class AvisosWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        // Estado de incidencias firmado (Fase 4): también en segundo plano, para que un modo seguro llegue antes.
        app.libremusic.data.Incident.refresh(applicationContext)
        // Telemetría (Fase 4b, sólo con consentimiento): el resumen de la semana que acabó, aunque no se abra la app.
        app.libremusic.data.Telemetry.flushIfDue(applicationContext)
        val avisos = AvisosRepo.refrescar(applicationContext) ?: return Result.retry()
        if (!AvisosRepo.notificarActivado(applicationContext)) return Result.success()
        AvisosRepo.pendientesDeNotificar(applicationContext, avisos).forEach { notificar(applicationContext, it) }
        return Result.success()
    }

    companion object {
        private const val NOMBRE = "avisos"
        private const val CANAL = "avisos"
        private const val CANAL_IMPORTANTES = "avisos_importantes"
        const val EXTRA_ABRIR_AVISOS = "abrir_avisos"

        fun programar(context: Context) {
            val peticion =
                PeriodicWorkRequestBuilder<AvisosWorker>(15, TimeUnit.MINUTES)
                    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                    .build()
            // Se llama al arrancar la app: si WorkManager no está (pruebas con Robolectric) no debe tumbarla.
            runCatching {
                WorkManager
                    .getInstance(context)
                    .enqueueUniquePeriodicWork(NOMBRE, ExistingPeriodicWorkPolicy.KEEP, peticion)
            }
        }

        fun cancelar(context: Context) {
            runCatching { WorkManager.getInstance(context).cancelUniqueWork(NOMBRE) }
        }

        private fun crearCanales(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val gestor = context.getSystemService(NotificationManager::class.java)
            gestor.createNotificationChannel(
                NotificationChannel(CANAL, "Avisos", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = L("Avisos de Pear Music publicados en la web")
                },
            )
            gestor.createNotificationChannel(
                NotificationChannel(CANAL_IMPORTANTES, L("Avisos importantes"), NotificationManager.IMPORTANCE_HIGH).apply {
                    description = L("Caídas y versiones urgentes")
                },
            )
        }

        fun notificar(
            context: Context,
            aviso: Aviso,
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                return
            }
            crearCanales(context)
            val abrir =
                PendingIntent.getActivity(
                    context,
                    aviso.id.hashCode(),
                    Intent(context, AppActivity::class.java)
                        .putExtra(EXTRA_ABRIR_AVISOS, true)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            val notificacion =
                NotificationCompat
                    .Builder(context, if (aviso.importante) CANAL_IMPORTANTES else CANAL)
                    .setSmallIcon(R.drawable.ic_stat_aviso)
                    .setContentTitle(aviso.titulo)
                    .setContentText(aviso.texto.ifBlank { null })
                    .setStyle(NotificationCompat.BigTextStyle().bigText(aviso.texto))
                    .setWhen(aviso.fecha.toEpochMilli())
                    .setShowWhen(true)
                    .setContentIntent(abrir)
                    .setAutoCancel(true)
                    .setPriority(
                        if (aviso.importante) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT,
                    ).build()
            NotificationManagerCompat.from(context).notify(aviso.id.hashCode(), notificacion)
        }
    }
}
