package com.rainif.doneat.plus

import kotlinx.serialization.json.*
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import java.util.UUID

/** Versioned CN protocol. No Android dependency: exact bytes and receipt policy are JVM-testable. */
internal object CnLicenseProtocol {
    const val ISSUER = "https://api.doneat.com.cn"
    const val DAY_MS = 86_400_000L
    fun encode(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    fun decode(value: String): ByteArray {
        require(value.matches(Regex("[A-Za-z0-9_-]+")))
        return Base64.getUrlDecoder().decode(value).also { require(encode(it) == value) }
    }
    fun hash(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    fun proof(operation: String, challengeId: String, serverNonce: String, payload: ByteArray): ByteArray {
        require(operation in setOf("preview", "activate", "refresh", "redeem-preview", "redeem", "operation", "trial-start", "trial-refresh"))
        require(UUID.fromString(challengeId).toString() == challengeId)
        require(decode(serverNonce).size == 32)
        val p = Json.parseToJsonElement(payload.decodeToString(throwOnInvalidSequence = true)).jsonObject
        val requestId = p.getValue("requestId").jsonPrimitive.content
        val nonce = p.getValue("clientNonce").jsonPrimitive.content
        require(UUID.fromString(requestId).toString() == requestId && nonce.length in 22..128 && decode(nonce).size >= 16)
        return listOf("cn-license-v1", "POST", "/v1/licenses/$operation", challengeId, serverNonce,
            p.getValue("clientNonce").jsonPrimitive.content, p.getValue("requestId").jsonPrimitive.content, hash(payload))
            .joinToString("\n").toByteArray(Charsets.UTF_8)
    }
    fun command(fields: JsonObject): ByteArray {
        require(fields.keys.none { it in setOf("requestId", "clientNonce") })
        return buildJsonObject {
            put("requestId", UUID.randomUUID().toString())
            put("clientNonce", encode(ByteArray(32).also(java.security.SecureRandom()::nextBytes)))
            fields.forEach { (key, value) -> put(key, value) }
        }.toString().toByteArray(Charsets.UTF_8)
    }
}

internal data class CnReceipt(
    val compact: String, val id: String, val source: String, val plan: String, val active: Boolean, val reason: String,
    val expiresAtMs: Long?, val serverTimeMs: Long, val leaseUntilMs: Long, val revision: Long, val binding: Long,
) {
    companion object {
        fun verify(compact: String, keys: Map<String, String>, audience: String, deviceHash: String,
            requestId: String, nonce: String, previous: CnReceipt? = null,
            allowExpiredLeaseForRecovery: Boolean = false): CnReceipt = run {
            require(audience.isNotBlank() && compact.length <= 16_384)
            val parts = compact.split('.'); require(parts.size == 3)
            val h = Json.parseToJsonElement(CnLicenseProtocol.decode(parts[0]).decodeToString(throwOnInvalidSequence = true)).jsonObject
            require(h.keys == setOf("alg", "typ", "kid"))
            require(h.getValue("alg").jsonPrimitive.content == "RS256" && h.getValue("typ").jsonPrimitive.content == "JWT")
            val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(keys.getValue(h.getValue("kid").jsonPrimitive.content))))
            require((key as java.security.interfaces.RSAPublicKey).modulus.bitLength() >= 2048)
            require(Signature.getInstance("SHA256withRSA").run {
                initVerify(key); update("${parts[0]}.${parts[1]}".toByteArray(Charsets.US_ASCII)); verify(CnLicenseProtocol.decode(parts[2]))
            })
            val p = Json.parseToJsonElement(CnLicenseProtocol.decode(parts[1]).decodeToString(throwOnInvalidSequence = true)).jsonObject
            fun text(k: String): String = p.getValue(k).jsonPrimitive.let { require(it.isString); it.content }
            fun long(k: String): Long = p.getValue(k).jsonPrimitive.let { require(!it.isString); it.long }
            require(text("iss") == CnLicenseProtocol.ISSUER && text("aud") == audience && text("channel") == "cn" && long("v") == 1L)
            require(text("deviceKeyHash") == deviceHash && text("requestId") == requestId && text("nonce") == nonce)
            val id = text("sub"); require(UUID.fromString(id).toString() == id)
            val source = p["source"]?.jsonPrimitive?.content ?: "license"
            val plan = text("plan"); require((source == "license" && plan in setOf("annual", "lifetime")) || (source == "trial" && plan == "trial"))
            val active = text("status") == "active"; require(text("status") in setOf("active", "inactive"))
            val reason = text("reason"); require(reason in setOf("valid", "expired", "replaced", "revoked"))
            require(active == (reason == "valid"))
            val server = long("serverTimeMs"); val lease = long("leaseUntilMs")
            val iat = long("iat"); val exp = long("exp")
            require(server > 0 && server % 1000 == 0L && iat == server / 1000 && exp > 0 && exp <= Long.MAX_VALUE / 1000 && exp * 1000 == lease)
            // Old committed command retries keep their original lease origin. They may prove
            // the command result after that lease ended, but must never grant offline access.
            require(lease > 0 && (lease > server || allowExpiredLeaseForRecovery) &&
                lease - server <= if (active) CnLicenseProtocol.DAY_MS else 300_000L)
            val expiry = p.getValue("entitlementExpiresAtMs").takeUnless { it == JsonNull }?.jsonPrimitive?.let { require(!it.isString); it.long }
            require(if (plan == "lifetime") expiry == null else expiry != null && expiry > 0)
            if (active && expiry != null) require(lease <= expiry && expiry > server)
            val revision = long("licenseRevision"); val binding = long("bindingVersion"); require(revision > 0 && binding > 0)
            if (previous != null && previous.id == id && previous.source == source) {
                require(revision >= previous.revision && binding >= previous.binding && server >= previous.serverTimeMs)
                if (revision == previous.revision) require(binding == previous.binding)
            }
            CnReceipt(compact, id, source, plan, active && lease > server, reason, expiry, server, lease, revision, binding)
        }
    }
}

/** Persisted anchor is accepted only during the same OS boot and without wall-clock jumps. */
internal data class CnLeaseAnchor(val elapsedMs: Long, val wallMs: Long, val bootCount: Int) {
    /** A retained command's nonce may have an old signed response: it proves outcome only. */
    fun forNetworkResult(freshNonce: Boolean): CnLeaseAnchor = if (freshNonce) this else copy(bootCount = -1)
    fun authorized(receipt: CnReceipt, nowElapsedMs: Long, nowWallMs: Long, currentBoot: Int): Boolean {
        val age = nowElapsedMs - elapsedMs
        if (bootCount < 0 || currentBoot != bootCount || age < 0) return false
        if (kotlin.math.abs((nowWallMs - wallMs) - age) > 120_000L) return false
        return receipt.active && age < receipt.leaseUntilMs - receipt.serverTimeMs
    }
    fun remaining(receipt: CnReceipt, nowElapsedMs: Long): Long = (receipt.leaseUntilMs - receipt.serverTimeMs - (nowElapsedMs - elapsedMs)).coerceAtLeast(0)
}
