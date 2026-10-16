package com.rainif.doneat.plus

import kotlinx.serialization.json.*
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/** A review lease is never a Play receipt or a subscription. */
internal data class ReviewGrant(val installationId: String, val revision: Long, val issuedAtMs: Long, val expiresAtMs: Long) {
    companion object {
        const val ISSUER = "https://api.doneat.app"
        const val AUDIENCE = "com.rainif.doneat:review-access"
        const val MAX_LEASE_MS = 86_400_000L
        fun keyHash(spki: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(spki).joinToString("") { "%02x".format(it) }
        fun read(raw: String, keys: Map<String, String>, installationId: String, keyHash: String, nonce: String? = null): ReviewGrant? = runCatching {
            require(raw.length <= 16_384)
            val parts = raw.split('.')
            require(parts.size == 3 && parts.all { it.matches(Regex("[A-Za-z0-9_-]+")) })
            val decoder = Base64.getUrlDecoder()
            val header = Json.parseToJsonElement(decoder.decode(parts[0]).toString(Charsets.UTF_8)).jsonObject
            require(header["alg"]?.jsonPrimitive?.content == "RS256" && header["typ"]?.jsonPrimitive?.content == "doneat-review-access+jwt")
            require(header.keys == setOf("alg", "typ", "kid"))
            val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(keys.getValue(header.getValue("kid").jsonPrimitive.content))))
            require(Signature.getInstance("SHA256withRSA").run { initVerify(key); update("${parts[0]}.${parts[1]}".toByteArray(Charsets.US_ASCII)); verify(decoder.decode(parts[2])) })
            val p = Json.parseToJsonElement(decoder.decode(parts[1]).toString(Charsets.UTF_8)).jsonObject
            fun text(key: String) = p.getValue(key).jsonPrimitive.content
            fun number(key: String) = p.getValue(key).jsonPrimitive.long
            require(text("iss") == ISSUER && text("aud") == AUDIENCE && text("sub") == installationId && number("v") == 1L)
            require(text("purpose") == "app-review" && text("scope") == "plus" && text("installationKeyHash") == keyHash)
            require(nonce == null || text("nonce") == nonce)
            val server = number("serverTimeMs")
            val issued = number("iat")
            val expiry = number("exp")
            val revision = number("credentialRevision")
            require(server > 0 && issued == server / 1000 && expiry == issued + MAX_LEASE_MS / 1000 && revision > 0)
            ReviewGrant(installationId, revision, server, expiry * 1000)
        }.getOrNull()
    }
}

/** Persisted monotonic anchor: wall-clock edits cannot extend a lease; a reboot requires online renewal. */
internal data class ReviewLease(val serverTimeMs: Long, val elapsedAtRequestMs: Long, val bootCount: Int, val expiresAtMs: Long) {
    fun remainingMs(elapsedMs: Long, currentBootCount: Int): Long {
        if (bootCount < 0 || bootCount != currentBootCount || elapsedMs < elapsedAtRequestMs) return 0
        val elapsed = elapsedMs - elapsedAtRequestMs
        if (elapsed > ReviewGrant.MAX_LEASE_MS) return 0
        return (expiresAtMs - serverTimeMs - elapsed).coerceIn(0, ReviewGrant.MAX_LEASE_MS)
    }
    fun effectiveExpiryMs(wallNowMs: Long, elapsedMs: Long, currentBootCount: Int): Long? =
        remainingMs(elapsedMs, currentBootCount).takeIf { it > 0 }?.let { wallNowMs + it }
}
