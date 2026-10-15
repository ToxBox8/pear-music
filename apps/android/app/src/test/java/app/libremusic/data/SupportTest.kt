package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SupportTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun emailAndText() {
        assertTrue(SupportLimits.validEmail("ana@example.com"))
        assertFalse(SupportLimits.validEmail("ana@example"))
        assertFalse(SupportLimits.validEmail("ana example.com"))
        assertFalse(SupportLimits.validText("mal"))
        assertTrue(SupportLimits.validText("La cola se vacía sola"))
    }

    /** Un borrador sobrevive a cerrar la app; uno vacío no se guarda; al enviarlo se borra con sus fotos. */
    @Test fun draftsPersistAndDelete() {
        val dir = tmp.newFolder("support")
        val store = SupportStore(dir, FakeBox)
        val d = SupportDraft(email = "ana@example.com", text = "Falla al descargar")
        store.save(d)
        store.save(SupportDraft())
        java.io.File(store.photoDir(d.id), "x.jpg").writeText("foto")
        val reopened = SupportStore(dir, FakeBox)
        assertEquals(listOf(d.id), reopened.drafts.value.map { it.id })
        assertEquals("Falla al descargar", reopened.drafts.value.single().text)
        reopened.delete(d.id)
        assertTrue(SupportStore(dir, FakeBox).drafts.value.isEmpty())
        assertFalse(java.io.File(dir, d.id).exists())
    }
}

/** En la JVM de los tests no hay Android Keystore: una «caja» que sólo invierte los bytes, para comprobar que
 *  lo guardado no queda en claro y que se lee bien. */
private object FakeBox : Box {
    override fun seal(plain: ByteArray) = byteArrayOf(1) + plain.reversedArray()
    override fun open(sealed: ByteArray) = sealed.copyOfRange(1, sealed.size).reversedArray()
}
