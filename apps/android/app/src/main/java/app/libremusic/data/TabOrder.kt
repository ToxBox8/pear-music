package app.libremusic.data

/**
 * Orden de las pestañas (Ajustes › Aspecto › Pestañas). Mismas claves y reglas que `TabOrder` en iOS:
 * las cuatro pestañas fijas, cada una una vez; Ajustes se puede mover pero nunca ocultar. Buscar, si va
 * como pestaña aparte, se coloca justo después de Inicio.
 */
object TabOrder {
    const val DISCOVER = "discover"
    const val HOME = "home"
    const val SEARCH = "search"
    const val LIBRARY = "library"
    const val SETTINGS = "settings"

    /** Por defecto Descubrir va a la izquierda del todo. */
    val DEFAULT = listOf(DISCOVER, HOME, LIBRARY, SETTINGS)

    /** Lo guardado («discover,home,…»); si falta alguna o sobra algo, el orden por defecto. */
    fun decode(raw: String?): List<String> {
        val keys = raw.orEmpty().split(",").map { it.trim() }.filter { it in DEFAULT }.distinct()
        return if (keys.size == DEFAULT.size) keys else DEFAULT
    }

    fun encode(order: List<String>): String = order.joinToString(",")

    /** Las pestañas que se ven, con Buscar detrás de Inicio si va aparte. */
    fun visible(order: List<String>, searchTab: Boolean): List<String> =
        if (!searchTab) order else order.flatMap { if (it == HOME) listOf(HOME, SEARCH) else listOf(it) }

    /**
     * Pestaña al abrir: la última usada, si sigue visible. La primera vez, Inicio: abrir en Descubrir pondría
     * música sola nada más instalar.
     */
    fun start(last: String?, visible: List<String>): String = last?.takeIf { it in visible } ?: HOME
}
