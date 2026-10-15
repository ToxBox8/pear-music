package app.libremusic.data

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Cifra datos que se guardan en el móvil. */
interface Box {
    fun seal(plain: ByteArray): ByteArray
    fun open(sealed: ByteArray): ByteArray
}

/**
 * AES-256-GCM con una clave del **Android Keystore**, que nunca sale del almacén del sistema (ni a la copia de
 * seguridad: lo cifrado con ella sólo se puede abrir en este móvil). Se usa para lo sensible que se guarda en
 * disco: los borradores de soporte (correo y texto) y, desde la 1.0, las credenciales de la cuenta y la clave de
 * administración de Pear Dev. Mismo esquema que `SecureBox` en iOS (Keychain + CryptoKit).
 *
 * Formato: `[1][IV de 12 bytes][cifrado + etiqueta de 16 bytes]`. El primer byte es la versión del formato.
 * No se usa `EncryptedSharedPreferences`: Google la dejó obsoleta en 2025.
 */
object SecureBox : Box {
    private const val ALIAS = "pear_music_local_v1"
    private const val VERSION: Byte = 1

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    override fun seal(plain: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        return byteArrayOf(VERSION) + c.iv + c.doFinal(plain)
    }

    override fun open(sealed: ByteArray): ByteArray {
        require(sealed.size > 29 && sealed[0] == VERSION) { "Formato cifrado desconocido" }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 1, 12))
        return c.doFinal(sealed, 13, sealed.size - 13)
    }
}
