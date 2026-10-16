package com.rainif.doneat.plus

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import kotlinx.serialization.json.*
import java.io.File
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class ReviewSession(val id: String, val secret: String, val grant: String, val lease: ReviewLease)

/** All state is excluded from backup. Losing either Keystore key requires activation again. */
internal class ReviewDeviceStore(context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "review-access/session"))
    private val blocked = File(context.noBackupFilesDir, "review-access/blocked")
    private val keyStore get() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val signingAlias = "doneat-review-install-v1"
    private val storageAlias = "doneat-review-storage-v1"
    fun publicKey(create: Boolean = false): ByteArray {
        val existing = keyStore.getCertificate(signingAlias)?.publicKey
        if (existing != null) return existing.encoded
        check(create)
        return KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
            initialize(KeyGenParameterSpec.Builder(signingAlias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256).build())
        }.generateKeyPair().public.encoded
    }
    fun sign(message: String): String = Signature.getInstance("SHA256withECDSA").run {
        initSign(keyStore.getKey(signingAlias, null) as java.security.PrivateKey)
        update(message.toByteArray(Charsets.UTF_8))
        Base64.getUrlEncoder().withoutPadding().encodeToString(sign())
    }
    private fun storageKey(create: Boolean): SecretKey {
        val existing = keyStore.getKey(storageAlias, null) as? SecretKey
        if (existing != null) return existing
        check(create)
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(storageAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun load(): ReviewSession? {
        if (blocked.exists() || !file.baseFile.exists()) return null
        publicKey()
        val bytes = file.openRead().use { input -> input.readReviewBytes().also { check(it.size <= 32_768) } }
        check(bytes.size > 12)
        val raw = Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, storageKey(false), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            updateAAD("doneat-review-session-v1".toByteArray())
            doFinal(bytes.copyOfRange(12, bytes.size))
        }
        val p = Json.parseToJsonElement(raw.toString(Charsets.UTF_8)).jsonObject
        fun text(key: String) = p.getValue(key).jsonPrimitive.content
        fun number(key: String) = p.getValue(key).jsonPrimitive.long
        return ReviewSession(text("id"), text("secret"), text("grant"),
            ReviewLease(number("serverTimeMs"), number("elapsedAtRequestMs"), p.getValue("bootCount").jsonPrimitive.int, number("expiresAtMs")))
    }
    fun save(session: ReviewSession) {
        val raw = buildJsonObject {
            put("id", session.id); put("secret", session.secret); put("grant", session.grant)
            put("serverTimeMs", session.lease.serverTimeMs); put("elapsedAtRequestMs", session.lease.elapsedAtRequestMs)
            put("bootCount", session.lease.bootCount); put("expiresAtMs", session.lease.expiresAtMs)
        }.toString().toByteArray()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, storageKey(true)); updateAAD("doneat-review-session-v1".toByteArray())
        }
        val bytes = cipher.iv + cipher.doFinal(raw)
        file.baseFile.parentFile?.let { check(it.isDirectory || it.mkdirs()) }
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) } catch (error: Exception) { file.failWrite(stream); throw error }
        check(!blocked.exists() || blocked.delete())
    }
    fun clear() = eraseReviewStorage(
        block = {
            blocked.parentFile?.let { check(it.isDirectory || it.mkdirs()) }
            java.io.FileOutputStream(blocked).use { it.write(1); it.fd.sync() }
        },
        eraseKey = { keyStore.deleteEntry(storageAlias) },
        eraseFile = { file.delete() },
        blocked = { blocked.exists() },
        fileAbsent = { !file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists() },
        keyAbsent = { !keyStore.containsAlias(storageAlias) },
    )
}

internal fun java.io.InputStream.readReviewBytes(): ByteArray {
    val buffer = ByteArray(32_769)
    var count = 0
    while (count < buffer.size) {
        val read = read(buffer, count, buffer.size - count)
        if (read < 0) break
        count += read
    }
    check(count <= 32_768)
    return buffer.copyOf(count)
}

/** Fault isolation: a Keystore failure must not skip file erasure, or vice versa. */
internal fun eraseReviewStorage(block: () -> Unit, eraseKey: () -> Unit, eraseFile: () -> Unit,
    blocked: () -> Boolean, fileAbsent: () -> Boolean, keyAbsent: () -> Boolean) {
    runCatching(block)
    runCatching(eraseKey)
    runCatching(eraseFile)
    check(runCatching(blocked).getOrDefault(false) || runCatching(fileAbsent).getOrDefault(false) || runCatching(keyAbsent).getOrDefault(false))
}
