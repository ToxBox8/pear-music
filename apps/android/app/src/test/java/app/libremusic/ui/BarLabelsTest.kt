package app.libremusic.ui

import app.libremusic.I18n
import app.libremusic.ui.theme.DeckStyle
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * 1.13 de x.1.1: la barra salía en castellano en euskera. Los títulos de los enums se calculaban una vez, al crearlos,
 * con el idioma que hubiera; ahora se traducen en cada lectura. Se arranca en euskera y se pasa por los ocho idiomas:
 * cada etiqueta tiene que coincidir con su traducción del catálogo y ninguna puede faltar.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BarLabelsTest {
    private val ctx get() = RuntimeEnvironment.getApplication()

    private fun catalog(lang: String): Map<String, String> {
        if (lang == "es") return emptyMap()
        val o = JSONObject(ctx.assets.open("i18n/$lang.json").bufferedReader().use { it.readText() })
        return o.keys().asSequence().associateWith { o.getString(it) }
    }

    @After fun back() = I18n.set(ctx, "es")

    @Test fun etiquetasEnCadaIdioma() {
        // Primero euskera: si los enums se crean ahora, se crean en euskera (el caso del fallo).
        I18n.set(ctx, "eu")
        Tab.entries.forEach { it.title }
        val labels: List<Pair<String, () -> String>> =
            listOf("Inicio" to { Tab.Home.title }, "Descubrir" to { Tab.Discover.title }, "Buscar" to { Tab.Search.title },
                "Biblioteca" to { Tab.Library.title }, "Ajustes" to { Tab.Settings.title },
                "Descargadas" to { SmartList.Downloads.title }, "Favoritos" to { SmartList.Favorites.title },
                "Casete" to { DeckStyle.Cassette.title }, "Vinilo" to { DeckStyle.Vinyl.title })
        for (lang in I18n.LANGS.map { it.code }) {
            I18n.set(ctx, lang)
            val table = catalog(lang)
            for ((es, read) in labels) {
                val expected = if (lang == "es") es else table[es].orEmpty()
                assertTrue("Falta «$es» en $lang", expected.isNotEmpty())
                assertEquals("«$es» en $lang", expected, read())
            }
        }
    }
}
