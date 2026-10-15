package app.libremusic.data

import android.app.ActivityManager
import android.content.Context
import android.net.Uri
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Derechos sobre los datos (RGPD, Fase 1 de la 1.0). Pear Music no tiene cuentas ni servidor propio con datos
 * del usuario: todo vive en el móvil. Aquí se exporta y se borra.
 *
 * - [export]: un .zip con todo lo que la app guarda de ti (biblioteca, favoritos, estadísticas, letras,
 *   portadas propias, borradores de soporte, avisos leídos y ajustes). No lleva las canciones descargadas: son
 *   audio de YouTube, no datos tuyos, y pesarían gigas.
 * - [eraseAll]: borra todos los datos de la app con la API del sistema (lo mismo que «Borrar almacenamiento»
 *   en los ajustes de Android) y la cierra.
 *
 * Cuando haya telemetría, su identificador y su consentimiento tienen que entrar en las dos cosas.
 */
object UserData {
    /** Nombres de archivo y carpetas de `filesDir` que no se exportan: audio descargado, cachés y la sesión de la
     *  cuenta (un secreto, aunque vaya cifrado con la clave del móvil). */
    private val skip = setOf("downloads", "datastore", "account")

    fun export(context: Context, target: Uri) {
        val files = context.filesDir
        val prefs = File(context.applicationInfo.dataDir, "shared_prefs")
        context.contentResolver.openOutputStream(target)?.use { out ->
            ZipOutputStream(out).use { zip ->
                zip.putNextEntry(ZipEntry("LEEME.txt"))
                zip.write(README.toByteArray())
                zip.closeEntry()
                files.listFiles()?.filter { it.name !in skip }?.forEach { add(zip, it, "app/") }
                prefs.listFiles()?.forEach { add(zip, it, "ajustes/") }
            }
        } ?: error("No se pudo abrir el archivo de destino")
    }

    fun eraseAll(context: Context) {
        val app = context.applicationContext
        Thread {
            // Primero lo que hay fuera del móvil (telemetría de esta instalación); luego todo lo local.
            Telemetry.deleteRemoteBlocking(app)
            (app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).clearApplicationUserData()
        }.start()
    }

    private fun add(zip: ZipOutputStream, file: File, prefix: String) {
        if (file.isDirectory) {
            file.listFiles()?.forEach { add(zip, it, "$prefix${file.name}/") }
            return
        }
        zip.putNextEntry(ZipEntry(prefix + file.name))
        file.inputStream().use { it.copyTo(zip) }
        zip.closeEntry()
    }

    private const val README = """Datos de Pear Music en este móvil.

app/library.json      Biblioteca: playlists, canciones guardadas y álbumes (formato de docs/LIBRARY_FORMAT.md).
app/stats.json        Estadísticas de escucha (sólo existen en el móvil).
app/lyrics/, covers/  Letras guardadas y fotos de tus playlists.
app/support/          Borradores de «Informar de un error» (con tu correo, si lo escribiste).
ajustes/              Ajustes de la app (tema, reproductor, avisos leídos, nombre en el Jam…).

Pear Music no tiene cuentas ni guarda estos datos en ningún servidor.
"""
}
