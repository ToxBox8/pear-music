package app.libremusic.data

import android.content.Intent
import android.provider.Settings
import org.robolectric.RuntimeEnvironment
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.net.InetSocketAddress
import java.security.MessageDigest
import kotlin.random.Random

/**
 * El camino completo de «Descargar» sin móvil: baja el APK de un servidor local, comprueba el SHA-256, lo reutiliza
 * si ya estaba bajado y abre el instalador del sistema (o los ajustes del permiso si falta).
 */
@RunWith(RobolectricTestRunner::class)
class UpdatesFlowTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private val apk = Random(7).nextBytes(300_000)
    private val sha = MessageDigest.getInstance("SHA-256").digest(apk).joinToString("") { "%02x".format(it) }
    private var hits = 0
    private lateinit var server: HttpServer

    @Before fun up() {
        server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply {
            createContext("/PearMusic.apk") { ex ->
                hits++
                ex.sendResponseHeaders(200, apk.size.toLong())
                ex.responseBody.use { it.write(apk) }
            }
            start()
        }
    }

    @After fun down() = server.stop(0)

    private fun release(hash: String = sha) = Updates.Release(
        "9.9.9", "t", listOf("a"), "http://127.0.0.1:${server.address.port}/PearMusic.apk?v=9.9.9", hash,
    )

    @Test fun descargaVerificaYReutiliza() = runBlocking {
        val progress = mutableListOf<Int>()
        val (file, error) = Updates.download(context, release()) { progress += it }
        assertNull(error)
        assertArrayEquals(apk, file!!.readBytes())
        assertEquals(100, progress.last())
        // Tras dar el permiso de instalar se vuelve a pulsar: no se baja otra vez.
        val (again, _) = Updates.download(context, release()) {}
        assertEquals(file, again)
        assertEquals(1, hits)
    }

    @Test fun hashQueNoCuadraNoSeInstala() = runBlocking {
        val (file, error) = Updates.download(context, release("0".repeat(64))) {}
        assertNull(file)
        assertNotNull(error)
        assertFalse(context.cacheDir.resolve("updates/pear-music-9.9.9.apk").exists())
    }

    @Test fun abreElInstaladorOElPermiso() = runBlocking {
        val (file, _) = Updates.download(context, release()) {}
        val pm = shadowOf(context.packageManager)
        val app = shadowOf(context)

        pm.setCanRequestPackageInstalls(false)
        assertFalse(Updates.install(context, file!!))
        assertEquals(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, app.nextStartedActivity.action)

        pm.setCanRequestPackageInstalls(true)
        assertTrue(Updates.install(context, file))
        val intent = app.nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals("application/vnd.android.package-archive", intent.type)
        assertEquals("content", intent.data!!.scheme)
        assertTrue(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
    }
}
