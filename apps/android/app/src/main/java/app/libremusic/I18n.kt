package app.libremusic

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

/**
 * Idiomas (Cierre 1.0; lo pidió Toxbox): español, catalán, valenciano, gallego, euskera, inglés y esperanto. Los
 * textos se escriben en español en el código, dentro de `L("…")`; el catálogo común está en `shared/i18n/<idioma>.json`
 * (clave = texto en español) y `tools/i18n/` lo genera y lo copia a `assets/i18n`. Lo que falte se ve en español.
 * Igual que `I18n` en iOS.
 */
object I18n {
    /** Código interno, nombre en su idioma y si va dentro del grupo «España» del selector. */
    data class Lang(val code: String, val name: String, val spain: Boolean)

    val LANGS = listOf(
        Lang("es", "Español", true),
        Lang("ca", "Català", true),
        Lang("va", "Valencià", true),
        Lang("gl", "Galego", true),
        Lang("eu", "Euskara", true),
        Lang("en", "English", false),
        Lang("eo", "Esperanto", false),
    )

    private val _lang = MutableStateFlow("es")
    val lang: StateFlow<String> = _lang.asStateFlow()

    @Volatile private var table: Map<String, String> = emptyMap()

    private fun prefs(c: Context) = c.getSharedPreferences("settings", Context.MODE_PRIVATE)

    /** El del sistema si es uno de los nuestros (valenciano: catalán con la variante «valencia»); si no, español. */
    fun systemDefault(locale: java.util.Locale = java.util.Locale.getDefault()): String = when (locale.language) {
        "ca" -> if (locale.variant.equals("valencia", true) || locale.toLanguageTag().contains("valencia", true)) "va" else "ca"
        "gl", "eu", "en", "eo" -> locale.language
        else -> "es"
    }

    fun init(c: Context) = load(c, prefs(c).getString("language", null) ?: systemDefault())

    /** ¿Ya eligió idioma (en la bienvenida o en Ajustes)? */
    fun chosen(c: Context) = prefs(c).contains("language")

    fun set(c: Context, code: String) {
        prefs(c).edit().putString("language", code).apply()
        load(c, code)
    }

    private fun load(c: Context, code: String) {
        val l = LANGS.firstOrNull { it.code == code }?.code ?: "es"
        table = if (l == "es") emptyMap() else runCatching {
            val o = JSONObject(c.assets.open("i18n/$l.json").bufferedReader().use { it.readText() })
            o.keys().asSequence().associateWith { o.getString(it) }.filterValues { it.isNotEmpty() }
        }.getOrDefault(emptyMap())
        _lang.value = l
    }

    fun t(s: String): String = table[s] ?: s
}

/** Texto en el idioma elegido. `{0}`, `{1}`… se cambian por [args] en orden. */
fun L(s: String, vararg args: Any?): String {
    var r = I18n.t(s)
    args.forEachIndexed { i, v -> r = r.replace("{" + i + "}", v.toString()) }
    return r
}
