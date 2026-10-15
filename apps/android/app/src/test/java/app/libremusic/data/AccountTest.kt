package app.libremusic.data

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountTest {
    @Test fun claveDeRecuperacion() {
        val k = Account.newRecoveryKey()
        assertTrue(k, Regex("([0-9A-Z]{4}-){6}[0-9A-Z]{2}").matches(k))
        assertNotEquals(k, Account.newRecoveryKey())
        // Se perdonan minúsculas, espacios y las letras que se confunden con números.
        assertEquals(k, Account.normalizeKey(k.lowercase().replace("-", " ")))
        assertEquals("0000-1111-0000-0000-0000-0000-00", Account.normalizeKey("OOOO-IIL1-0000-0000-0000-0000-00"))
        assertNull(Account.normalizeKey("demasiado-corta"))
    }

    @Test fun bibliotecaCifradaSóloSeAbreConSuClave() {
        val k = Account.newRecoveryKey()
        val plain = """{"favorites":[],"playlists":[]}""".toByteArray()
        val blob = Account.encrypt(plain, k)
        assertTrue("el blob no puede llevar el JSON en claro", !String(java.util.Base64.getDecoder().decode(blob)).contains("favorites"))
        assertArrayEquals(plain, Account.decrypt(blob, k))
        assertTrue(runCatching { Account.decrypt(blob, Account.newRecoveryKey()) }.isFailure)
    }
}
