package app.libremusic.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.security.KeyPairGenerator
import java.security.Signature

/** Fase 4: la firma se comprueba con BouncyCastle; aquí se firma con el Ed25519 de la JVM (otra implementación). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class IncidentTest {
    private val keys = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
    private val pub = java.util.Base64.getEncoder().encodeToString(keys.public.encoded.takeLast(32).toByteArray())
    private val ctx get() = RuntimeEnvironment.getApplication()
    private val now = 1_800_000_000_000L

    private fun envelope(level: Int, counter: Long, expiresAt: Long = 4_000_000_000, ttl: Int? = null, msg: String = "Mensaje"): String {
        val payload = JSONObject().put("v", 1).put("level", level).put("counter", counter).put("issuedAt", 1)
            .put("expiresAt", expiresAt).put("ttlHours", ttl ?: JSONObject.NULL).put("message", msg).toString()
        val s = Signature.getInstance("Ed25519").apply { initSign(keys.private); update(payload.toByteArray()) }.sign()
        return JSONObject().put("payload", payload).put("sig", java.util.Base64.getEncoder().encodeToString(s)).toString()
    }

    @Test fun firmaBuenaYMala() {
        ctx.getSharedPreferences("incident", 0).edit().clear().commit()
        assertTrue(Incident.accept(ctx, envelope(2, 5), now, pub))
        assertEquals(2, Incident.state.value.level)
        // Contenido cambiado tras firmar: se rechaza y no cambia nada.
        val bad = JSONObject(envelope(1, 9)).let { it.put("payload", it.getString("payload").replace("\"level\":1", "\"level\":0")) }.toString()
        assertFalse(Incident.accept(ctx, bad, now, pub))
        assertEquals(2, Incident.state.value.level)
        // Firmado con otra clave: tampoco.
        assertFalse(Incident.accept(ctx, envelope(0, 10), now, java.util.Base64.getEncoder().encodeToString(ByteArray(32) { 1 })))
    }

    @Test fun antiRollbackYCaducidad() {
        ctx.getSharedPreferences("incident", 0).edit().clear().commit()
        assertTrue(Incident.accept(ctx, envelope(3, 20), now, pub))
        assertFalse("un contador viejo no puede quitar el bloqueo", Incident.accept(ctx, envelope(0, 19), now, pub))
        assertEquals(3, Incident.state.value.level)
        assertTrue(Incident.accept(ctx, envelope(0, 21), now, pub))
        assertEquals(0, Incident.state.value.level)
        // Caducado: falla en abierto.
        assertTrue(Incident.accept(ctx, envelope(2, 22, expiresAt = now / 1000 - 1), now, pub))
        assertEquals(0, Incident.state.value.level)
    }

    @Test fun elAvisoCaducaSolo() {
        ctx.getSharedPreferences("incident", 0).edit().clear().commit()
        assertTrue(Incident.accept(ctx, envelope(1, 30, ttl = 24), now, pub))
        assertEquals(1, Incident.state.value.level)
        Incident.load(ctx, now + 25 * 3_600_000L)
        assertEquals(0, Incident.state.value.level)
    }
}
