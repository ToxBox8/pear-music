package app.libremusic.data

import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519KeyGenerationParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.junit.Assert.assertEquals
import org.junit.Test
import java.security.SecureRandom
import java.util.Base64

/** Fase de seguridad S4: un version.json alterado no se ofrece; sin firma, x.1.1 aún lo acepta. */
class UpdatesSignatureTest {
    private val pair = Ed25519KeyPairGenerator().apply { init(Ed25519KeyGenerationParameters(SecureRandom())) }.generateKeyPair()
    private val pub = Base64.getEncoder().encodeToString((pair.public as Ed25519PublicKeyParameters).encoded)
    private val body = """{"android":{"version":"9.9.9","apk":"https://x/y.apk","sha256":"${"a".repeat(64)}"}}""".toByteArray()
    private fun sign(b: ByteArray) = Ed25519Signer().run {
        init(true, pair.private as Ed25519PrivateKeyParameters); update(b, 0, b.size); Base64.getEncoder().encodeToString(generateSignature())
    }

    @Test fun firmaBuenaMalaYQueFalta() {
        val sig = sign(body)
        assertEquals(Updates.Signature.Good, Updates.signature(body, sig, pub))
        assertEquals(Updates.Signature.Good, Updates.signature(body, "$sig\n", pub))
        val altered = String(body).replace("9.9.9", "9.9.8").toByteArray()
        assertEquals(Updates.Signature.Bad, Updates.signature(altered, sig, pub))
        assertEquals(Updates.Signature.Bad, Updates.signature(body, "basura", pub))
        assertEquals(Updates.Signature.Missing, Updates.signature(body, null, pub))
        assertEquals(Updates.Signature.NoKey, Updates.signature(body, sig, ""))
    }
}
