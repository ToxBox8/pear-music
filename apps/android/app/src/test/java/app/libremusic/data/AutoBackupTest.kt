package app.libremusic.data

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

/** Copia automática: nombre del archivo y qué copias antiguas se borran (sólo las suyas). */
class AutoBackupTest {
    @Test fun name() = assertEquals("PearMusic-copia-2026-10-13.json", AutoBackup.fileName(LocalDate.of(2026, 10, 13)))

    @Test fun prunesOnlyOldBackups() {
        val names = (1..9).map { AutoBackup.fileName(LocalDate.of(2026, 10, it)) } + listOf("fotos.jpg", "PearMusic-copia-notas.txt")
        assertEquals(listOf("PearMusic-copia-2026-10-02.json", "PearMusic-copia-2026-10-01.json"), AutoBackup.toPrune(names))
        assertEquals(emptyList<String>(), AutoBackup.toPrune(names.take(3)))
    }
}
