package com.rainif.doneat.plus

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device-bound signing and encrypted recovery commands. All files live outside Android backups. */
internal class CnDeviceIdentity(context: Context) {
    private val signingAlias = "doneat-cn-license-p256-v1"
    private val storageAlias = "doneat-cn-storage-v1"
    private val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val file = AtomicFile(File(context.noBackupFilesDir, "cn-license-v1.enc"))
    init {
        if (!keys.containsAlias(signingAlias)) KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
            initialize(KeyGenParameterSpec.Builder(signingAlias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_SHA256).build())
            generateKeyPair()
        }
        if (!keys.containsAlias(storageAlias)) KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(storageAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }
    val publicKey: ByteArray get() = keys.getCertificate(signingAlias).publicKey.encoded
    val deviceHash: String get() = CnLicenseProtocol.hash(publicKey)
    fun sign(message: ByteArray): ByteArray = Signature.getInstance("SHA256withECDSA").run {
        initSign(keys.getKey(signingAlias, null) as PrivateKey); update(message); sign()
    }
    fun read(): String? {
        if (!file.baseFile.exists()) return null
        val packed = file.readFully(); require(packed.size > 28)
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, keys.getKey(storageAlias, null) as SecretKey, GCMParameterSpec(128, packed.copyOfRange(0, 12)))
            updateAAD("cn-license-v1".toByteArray()); doFinal(packed.copyOfRange(12, packed.size)).decodeToString(throwOnInvalidSequence = true)
        }
    }
    fun write(value: String) {
        val encrypted = Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.ENCRYPT_MODE, keys.getKey(storageAlias, null) as SecretKey)
            updateAAD("cn-license-v1".toByteArray()); val body = doFinal(value.toByteArray()); iv + body
        }
        val stream = file.startWrite()
        try { stream.write(encrypted); file.finishWrite(stream) } catch (e: Exception) { file.failWrite(stream); throw e }
    }
}
