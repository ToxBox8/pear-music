package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Test

/** El buscador local ignora mayúsculas y acentos y acepta las palabras en cualquier orden. */
class LocalSearchTest {
    private val names = listOf("Beyoncé", "Rosalía", "The Strokes", "Viaje 12/13", "Álvaro Soler")

    @Test fun accentsAndCase() {
        assertEquals(listOf("Beyoncé"), LocalSearch.filter(names, "beyonce") { it })
        assertEquals(listOf("Rosalía"), LocalSearch.filter(names, "ROSALIA") { it })
        assertEquals(listOf("Álvaro Soler"), LocalSearch.filter(names, "alvaro") { it })
    }

    @Test fun wordsInAnyOrder() {
        assertEquals(listOf("The Strokes"), LocalSearch.filter(names, "strokes the") { it })
    }

    @Test fun emptyQueryKeepsAll() {
        assertEquals(names, LocalSearch.filter(names, "   ") { it })
    }

    @Test fun noMatch() {
        assertEquals(emptyList<String>(), LocalSearch.filter(names, "zzz") { it })
    }

    @Test fun bigListIsFast() {
        val big = (0 until 20_000).map { "Artista número $it Ñandú" }
        val folded = big.map(LocalSearch::fold)
        val t = System.nanoTime()
        val r = LocalSearch.filter(big, folded, "nandu 1999")
        val ms = (System.nanoTime() - t) / 1_000_000
        assert(r.isNotEmpty())
        assert(ms < 200) { "filtrar 20 000 tardó $ms ms" }
    }
}
