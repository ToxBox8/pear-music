package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Test

class TabOrderTest {
    @Test fun defaultPutsDiscoverFirst() = assertEquals(listOf("discover", "home", "library", "settings"), TabOrder.decode(null))

    @Test fun keepsAValidOrder() =
        assertEquals(listOf("settings", "library", "home", "discover"), TabOrder.decode("settings,library,home,discover"))

    /** Ajustes no se puede quitar: un orden sin él (o con basura) vuelve al de por defecto. */
    @Test fun rejectsMissingOrUnknownTabs() {
        assertEquals(TabOrder.DEFAULT, TabOrder.decode("discover,home,library"))
        assertEquals(TabOrder.DEFAULT, TabOrder.decode("discover,home,home,library"))
    }

    @Test fun searchGoesAfterHome() =
        assertEquals(listOf("library", "home", "search", "discover", "settings"), TabOrder.visible(listOf("library", "home", "discover", "settings"), true))

    @Test fun startsOnLastUsedIfVisible() {
        assertEquals("library", TabOrder.start("library", TabOrder.DEFAULT))
        assertEquals("home", TabOrder.start("search", TabOrder.DEFAULT))
        assertEquals("home", TabOrder.start(null, TabOrder.DEFAULT))
    }
}
