package org.caminoseguro.watch.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Log
import org.caminoseguro.watch.core.CredentialStore
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Token opaco cifrado con AES-256/GCM; la clave vive en Android Keystore y nunca sale de él.
 * El fichero cifrado está en `noBackupFilesDir` (y además `allowBackup=false`).
 * V1: nada escribe aquí — la vinculación del reloj está BLOQUEADA por contrato.
 */
class KeystoreCredentialStore(context: Context) : CredentialStore {

    private val file = AtomicFile(File(context.noBackupFilesDir, FILE_NAME))

    @Synchronized
    override fun read(): String? {
        if (!file.baseFile.exists()) return null
        return try {
            val blob = file.readFully()
            if (blob.size <= IV_BYTES) return null
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, existingKey() ?: return null, GCMParameterSpec(TAG_BITS, blob, 0, IV_BYTES))
            String(cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES), Charsets.UTF_8)
        } catch (e: Exception) {
            // Nunca se registra el token ni su contenido.
            Log.w(TAG, "No se pudo leer la credencial: ${e.javaClass.simpleName}")
            null
        }
    }

    @Synchronized
    override fun write(token: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, existingKey() ?: createKey())
        val iv = cipher.iv
        check(iv.size == IV_BYTES) { "IV inesperado" }
        val sealed = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        var out: FileOutputStream? = null
        try {
            out = file.startWrite()
            out.write(iv)
            out.write(sealed)
            file.finishWrite(out)
        } catch (e: Exception) {
            if (out != null) file.failWrite(out)
            throw e
        }
    }

    @Synchronized
    override fun clear() {
        file.delete()
        try {
            keyStore().deleteEntry(KEY_ALIAS)
        } catch (e: Exception) {
            Log.w(TAG, "No se pudo borrar la clave: ${e.javaClass.simpleName}")
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun existingKey(): SecretKey? =
        (keyStore().getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.secretKey

    private fun createKey(): SecretKey {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val TAG = "CaminoCredential"
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "camino_credential_key"
        const val FILE_NAME = "credential.bin"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}
