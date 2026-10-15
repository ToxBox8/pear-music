package app.libremusic.data

import android.util.Log
import app.libremusic.BuildConfig

/**
 * Registro de la app. Nunca se escriben datos personales (correo, texto de reportes, nombre del Jam, búsquedas):
 * como mucho identificadores de canciones y errores técnicos.
 *
 * - **usr** y **pref**: sólo avisos y errores al logcat del sistema; nada de depuración.
 * - **dev** (`VERBOSE_LOGS`): todo al logcat y además las últimas [CAPACITY] líneas en memoria, que se ven en
 *   Ajustes › Avanzado › Administración. No se guardan en disco ni salen del móvil.
 * - La variante `perf` (de cualquier canal) también escribe las medidas de `LMPerf` que lee `scripts/bench.sh`.
 */
object Logs {
    private const val CAPACITY = 300
    private val recent = ArrayDeque<String>()
    private val verbose = BuildConfig.VERBOSE_LOGS
    private val perfBuild = BuildConfig.BUILD_TYPE == "perf"

    fun d(tag: String, msg: String) {
        if (!verbose) return
        Log.d(tag, msg)
        keep("D", tag, msg)
    }

    fun i(tag: String, msg: String) {
        if (!verbose && !(perfBuild && tag == "LMPerf")) return
        Log.i(tag, msg)
        keep("I", tag, msg)
    }

    fun w(tag: String, msg: String) {
        Log.w(tag, msg)
        keep("W", tag, msg)
    }

    fun e(tag: String, msg: String, error: Throwable? = null) {
        Log.e(tag, msg, error)
        keep("E", tag, msg + (error?.let { " · ${it.javaClass.simpleName}: ${it.message}" } ?: ""))
    }

    /** Las últimas líneas (sólo en dev; vacío en las demás). */
    fun recent(): List<String> = synchronized(recent) { recent.toList() }

    fun clear() = synchronized(recent) { recent.clear() }

    private fun keep(level: String, tag: String, msg: String) {
        if (!verbose) return
        val time = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date())
        synchronized(recent) {
            if (recent.size == CAPACITY) recent.removeFirst()
            recent.addLast("$time $level/$tag: $msg")
        }
    }
}
