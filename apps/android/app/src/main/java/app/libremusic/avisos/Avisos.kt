package app.libremusic.avisos


import app.libremusic.L
import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant

/**
 * Avisos de Pear Music. Salen del canal privado de Discord, la web los sirve en /api/avisos y aquí se leen.
 * Contrato (versión 1): ver README de libremusic-landing, sección «Avisos». Probado antes en Open Menus;
 * es lo mismo que `Avisos.swift` en iOS. Sólo se hace un GET sin datos del usuario ni identificadores.
 */
data class Aviso(
    val id: String,
    val importante: Boolean,
    val titulo: String,
    val texto: String,
    val enlace: String?,
    val fecha: Instant,
    /**
     * Respuesta del soporte SÓLO para esta instalación (tickets, Cierre 1.0): «abierto» (check), «mensaje»
     * (bocadillo), «fiesta» (confeti, solucionado) o «en-ello» (línea de comandos). null = aviso para todos.
     */
    val personal: String? = null,
    val ticket: Int? = null,
)

sealed interface EstadoAvisos {
    /** Primera carga sin copia guardada. */
    data object Cargando : EstadoAvisos

    data class Listo(
        val avisos: List<Aviso>,
        /** true si la última descarga falló y se muestra la copia guardada. */
        val sinConexion: Boolean,
    ) : EstadoAvisos

    /** Falló la descarga y no hay copia guardada. */
    data object Error : EstadoAvisos
}

const val URL_AVISOS = "https://libremusic-landing.8toxbox8-69a.workers.dev/api/avisos"

/** Solo se notifica en el móvil lo publicado en las últimas 48 h (como hace SimpMusic con su blog). */
const val VENTANA_NOTIFICAR_MS = 48L * 60 * 60 * 1000

object AvisosRepo {
    private const val PREFS = "avisos"
    private const val CLAVE_JSON = "ultima_respuesta"
    private const val CLAVE_VISTOS = "vistos"
    private const val CLAVE_NOTIFICADOS = "notificados"
    private const val CLAVE_PERSONALES = "personales"
    const val URL_MENSAJES = "https://libremusic-soporte.8toxbox8-69a.workers.dev/mensajes"
    const val CLAVE_NOTIFICAR = "notificar_en_movil"

    private val _estado = MutableStateFlow<EstadoAvisos>(EstadoAvisos.Cargando)
    val estado: StateFlow<EstadoAvisos> = _estado.asStateFlow()

    /** true cuando se pulsa una notificación de aviso: la interfaz abre la pantalla Avisos y lo pone a false. */
    val abrir = MutableStateFlow(false)

    private val _sinLeer = MutableStateFlow(0)
    val sinLeer: StateFlow<Int> = _sinLeer.asStateFlow()

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Pinta la copia guardada al instante; luego llama a [refrescar]. */
    fun cargarCopia(context: Context) {
        val guardado = prefs(context).getString(CLAVE_JSON, null) ?: return
        runCatching { parsear(guardado) }.onSuccess { generales ->
            val avisos = juntar(generales, prefs(context).getString(CLAVE_PERSONALES, null)?.let { runCatching { parsearPersonales(it) }.getOrNull() }.orEmpty())
            _estado.value = EstadoAvisos.Listo(avisos, sinConexion = false)
            recalcularSinLeer(context, avisos)
        }
    }

    /** Descarga los avisos. Devuelve la lista nueva, o null si no se pudo. */
    suspend fun refrescar(context: Context): List<Aviso>? {
        val json = withContext(Dispatchers.IO) { runCatching { descargar(url(context)) }.getOrNull() }
        val generales = json?.let { runCatching { parsear(it) }.getOrNull() }
        val avisos = generales?.let { juntar(it, personales(context)) }
        if (avisos == null) {
            _estado.value =
                when (val actual = _estado.value) {
                    is EstadoAvisos.Listo -> actual.copy(sinConexion = true)
                    else -> EstadoAvisos.Error
                }
            return null
        }
        prefs(context).edit().putString(CLAVE_JSON, json).apply()
        _estado.value = EstadoAvisos.Listo(avisos, sinConexion = false)
        recalcularSinLeer(context, avisos)
        return avisos
    }

    /** Avisos generales y respuestas del soporte para esta instalación, de más nuevo a más viejo. */
    private fun juntar(generales: List<Aviso>, personales: List<Aviso>) = (generales + personales).sortedByDescending { it.fecha }

    /**
     * Las respuestas del soporte a los tickets de esta instalación. Sólo se piden si desde aquí se ha enviado algún
     * reporte o sugerencia (así nadie más manda su identificador). Sin red, la copia guardada.
     */
    private suspend fun personales(context: Context): List<Aviso> = withContext(Dispatchers.IO) {
        val device = app.libremusic.data.SupportClient.sentDeviceId(context) ?: return@withContext emptyList()
        val guardado = prefs(context).getString(CLAVE_PERSONALES, null)
        val json = runCatching { descargar("$URL_MENSAJES?device=${java.net.URLEncoder.encode(device, "UTF-8")}") }.getOrNull()
        val lista = json?.let { runCatching { parsearPersonales(it) }.getOrNull() }
        if (lista != null) prefs(context).edit().putString(CLAVE_PERSONALES, json).apply()
        lista ?: guardado?.let { runCatching { parsearPersonales(it) }.getOrNull() }.orEmpty()
    }

    fun parsearPersonales(json: String): List<Aviso> {
        val lista = JSONObject(json).getJSONArray("mensajes")
        return (0 until lista.length()).map { i ->
            val m = lista.getJSONObject(i)
            val n = m.optInt("ticket")
            Aviso(
                id = "ticket-" + m.getString("id"),
                importante = false,
                titulo = m.optString("title").ifEmpty { L("Respuesta de Pear Music") },
                texto = m.optString("text"),
                enlace = null,
                fecha = Instant.parse(m.getString("at")),
                personal = m.optString("tipo").takeIf { it in setOf("abierto", "mensaje", "fiesta", "en-ello") } ?: "mensaje",
                ticket = n.takeIf { it > 0 },
            )
        }
    }

    /**
     * Al pasar la app a primer plano. Los avisos recibidos así ya se ven en la campana, así que se apuntan como
     * notificados y la comprobación de fondo no los vuelve a sacar como notificación.
     */
    suspend fun refrescarAlAbrir(context: Context) {
        val avisos = refrescar(context) ?: return
        pendientesDeNotificar(context, avisos)
    }

    /** Al abrir la pantalla de avisos: todo lo que hay pasa a visto y la campana se apaga. */
    fun marcarVistos(context: Context) {
        val avisos = (_estado.value as? EstadoAvisos.Listo)?.avisos ?: return
        val vistos = prefs(context).getStringSet(CLAVE_VISTOS, emptySet()).orEmpty() + avisos.map { it.id }
        // Solo se guardan ids que siguen existiendo, para que el conjunto no crezca para siempre.
        prefs(context).edit().putStringSet(CLAVE_VISTOS, vistos.intersect(avisos.map { it.id }.toSet())).apply()
        _sinLeer.value = 0
    }

    fun notificarActivado(context: Context) = prefs(context).getBoolean(CLAVE_NOTIFICAR, true)

    fun fijarNotificar(
        context: Context,
        activado: Boolean,
    ) = prefs(context).edit().putBoolean(CLAVE_NOTIFICAR, activado).apply()

    /**
     * Avisos que aún no se han notificado en el móvil y son de las últimas 48 h. Todos los recibidos quedan
     * apuntados como notificados, así un aviso viejo nunca salta y uno nuevo salta una sola vez.
     */
    fun pendientesDeNotificar(
        context: Context,
        avisos: List<Aviso>,
        ahora: Instant = Instant.now(),
    ): List<Aviso> {
        val ya = prefs(context).getStringSet(CLAVE_NOTIFICADOS, emptySet()).orEmpty()
        val nuevos =
            avisos.filter { it.id !in ya && ahora.toEpochMilli() - it.fecha.toEpochMilli() <= VENTANA_NOTIFICAR_MS }
        prefs(context).edit().putStringSet(CLAVE_NOTIFICADOS, avisos.map { it.id }.toSet()).apply()
        return nuevos
    }

    private fun recalcularSinLeer(
        context: Context,
        avisos: List<Aviso>,
    ) {
        val vistos = prefs(context).getStringSet(CLAVE_VISTOS, emptySet()).orEmpty()
        _sinLeer.value = avisos.count { it.id !in vistos }
    }

    /**
     * Sólo en la versión debug se puede apuntar a otra web para probar (clave `url_pruebas` en las preferencias
     * «avisos», p. ej. la web en local con un Discord falso). La versión publicada usa siempre [URL_AVISOS].
     */
    private fun url(context: Context): String =
        if (app.libremusic.BuildConfig.DEBUG) prefs(context).getString("url_pruebas", null) ?: URL_AVISOS else URL_AVISOS

    private fun descargar(url: String): String {
        val conexion = URL(url).openConnection() as HttpURLConnection
        try {
            conexion.connectTimeout = 10_000
            conexion.readTimeout = 10_000
            conexion.setRequestProperty("Accept", "application/json")
            val codigo = conexion.responseCode
            check(codigo == 200) { "HTTP $codigo" }
            // Como mucho 256 KB (30 avisos de texto caben de sobra): una respuesta enorme no llena la memoria.
            val max = 256 * 1024
            val out = java.io.ByteArrayOutputStream()
            conexion.inputStream.use { input ->
                val buf = ByteArray(8 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    check(out.size() <= max) { "respuesta demasiado grande" }
                }
            }
            return out.toString(Charsets.UTF_8.name())
        } finally {
            conexion.disconnect()
        }
    }

    /** Lanza si el JSON no es la versión 1 o el estado no es «ok» ni «sin_configurar». */
    fun parsear(json: String): List<Aviso> {
        val raiz = JSONObject(json)
        check(raiz.optInt("version") == 1) { "versión de avisos desconocida" }
        check(raiz.optString("estado") in setOf("ok", "sin_configurar")) { "estado ${raiz.optString("estado")}" }
        val lista = raiz.getJSONArray("avisos")
        return (0 until lista.length()).map { i ->
            val a = lista.getJSONObject(i)
            Aviso(
                id = a.getString("id"),
                importante = a.optString("tipo") == "importante",
                titulo = a.getString("titulo"),
                texto = a.optString("texto"),
                // Sólo http(s): se abre con un toque y un `intent:` o `javascript:` no debe llegar ahí.
                enlace = a.optString("enlace").takeIf { !a.isNull("enlace") && Regex("^https?://", RegexOption.IGNORE_CASE).containsMatchIn(it) },
                fecha = Instant.parse(a.getString("fecha")),
            )
        }
    }
}
