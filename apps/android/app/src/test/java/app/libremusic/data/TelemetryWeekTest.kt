package app.libremusic.data

import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519KeyGenerationParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.time.LocalDate

/** Fase 4b: informe semanal (semana ISO, medianas, lo de la semana anterior queda pendiente) y llave del panel. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TelemetryWeekTest {
    private val ctx get() = RuntimeEnvironment.getApplication()

    @Test fun semanaIso() {
        assertEquals("2026-W42", Telemetry.isoWeek(LocalDate.of(2026, 10, 14)))
        assertEquals("2026-W53", Telemetry.isoWeek(LocalDate.of(2027, 1, 1))) // el 1-1-2027 es de la semana 53 de 2026
        assertEquals("2025-W01", Telemetry.isoWeek(LocalDate.of(2024, 12, 30)))
    }

    @Test fun resumenConMedianasYCamposElegidos() {
        listOf(30.0 to 2, 60.0 to 10, 58.0 to 4).forEach { (fps, min) ->
            Telemetry.record(ctx, JSONObject().put("fps_median", fps).put("session_minutes", min).put("memory_mb", 200), "2026-W42")
        }
        val b = JSONObject(ctx.getSharedPreferences("telemetry", 0).getString("week", null)!!)
        val all = Telemetry.summarize(ctx, b, "semanal")
        assertEquals("2026-W42", all.getString("week"))
        assertEquals(3, all.getInt("sessions"))
        assertEquals(58.0, all.getDouble("fps_median"), 0.01)
        assertEquals(4, all.getInt("session_minutes"))
        assertFalse(all.has("startup_ms"))
        val some = Telemetry.summarize(ctx, b, "manual", setOf("fps_median"))
        assertTrue(some.has("fps_median") && some.has("install") && some.has("week"))
        assertFalse(some.has("device_model") || some.has("memory_mb") || some.has("sessions"))
        // Semana nueva: la anterior pasa a pendiente.
        Telemetry.record(ctx, JSONObject().put("fps_median", 60.0), "2026-W43")
        assertEquals("2026-W42", JSONObject(ctx.getSharedPreferences("telemetry", 0).getString("pending", null)!!).getString("week"))
    }

    @Test fun llaveDelPanelFirmadaYCorta() {
        val key = Ed25519KeyPairGenerator().apply { init(Ed25519KeyGenerationParameters(java.security.SecureRandom())) }
            .generateKeyPair().private as Ed25519PrivateKeyParameters
        val now = 1_800_000_000_000L
        val (payload, sig) = PanelKey.token(key, now).removePrefix("Panel ").split(".")
        val dec = java.util.Base64.getUrlDecoder()
        val p = JSONObject(String(dec.decode(payload)))
        assertEquals(now + 5 * 60_000, p.getLong("exp"))
        // Se comprueba con el Ed25519 de la JVM, como hará el Worker con Web Crypto.
        val spki = byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00) + key.generatePublicKey().encoded
        val pub = KeyFactory.getInstance("Ed25519").generatePublic(X509EncodedKeySpec(spki))
        assertTrue(Signature.getInstance("Ed25519").apply { initVerify(pub); update(dec.decode(payload)) }.verify(dec.decode(sig)))
    }
}
