package com.rainif.doneat.plus

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/** The signature proves an observation of Google state, not that an offline device knows future renewals/refunds. */
internal data class BillingReceipt(
    val productId: String,
    val subscription: Boolean,
    val status: String,
    val expiresAtMs: Long?,
    val verifiedAtMs: Long,
    val cacheUntilMs: Long,
    val revision: Long,
) {
    fun usableAt(nowMs: Long): Boolean = nowMs >= verifiedAtMs - CLOCK_TOLERANCE_MS && nowMs < cacheUntilMs
    fun activeAt(nowMs: Long): Boolean = status == "active" && usableAt(nowMs) &&
        (!subscription || (expiresAtMs != null && nowMs < expiresAtMs))

    companion object {
        const val ISSUER = "https://api.doneat.app"
        const val CLOCK_TOLERANCE_MS = 30_000L
        private const val YEAR_CACHE_MS = 366L * 86_400_000

        fun tokenHash(token: String): String = MessageDigest.getInstance("SHA-256")
            .digest(token.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

        fun read(
            compact: String, publicKeys: Map<String, String>, packageName: String,
            productId: String, token: String, subscription: Boolean, nowMs: Long, nonce: String? = null,
        ): BillingReceipt? = runCatching {
            if (compact.length > 16_384) return null
            val parts = compact.split('.')
            if (parts.size != 3 || parts.any { !it.matches(Regex("[A-Za-z0-9_-]+")) }) return null
            val decoder = Base64.getUrlDecoder()
            val header = Json.parseToJsonElement(decoder.decode(parts[0]).toString(Charsets.UTF_8)).jsonObject
            if (header["alg"]?.jsonPrimitive?.content != "RS256" || header["typ"]?.jsonPrimitive?.content != "JWT" ||
                header.containsKey("crit") || header.containsKey("b64")) return null
            val encodedKey = publicKeys[header["kid"]?.jsonPrimitive?.content] ?: return null
            val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(encodedKey)))
            val verified = Signature.getInstance("SHA256withRSA").run {
                initVerify(key)
                update("${parts[0]}.${parts[1]}".toByteArray(Charsets.US_ASCII))
                verify(decoder.decode(parts[2]))
            }
            if (!verified) return null
            val payload = Json.parseToJsonElement(decoder.decode(parts[1]).toString(Charsets.UTF_8)).jsonObject
            fun text(name: String) = payload.getValue(name).jsonPrimitive.content
            fun number(name: String) = payload.getValue(name).jsonPrimitive.long
            if (text("iss") != ISSUER || text("aud") != packageName || text("sub") != tokenHash(token) ||
                text("productId") != productId || payload.getValue("v").jsonPrimitive.int != 1 ||
                text("kind") != (if (subscription) "subscription" else "lifetime")) return null
            if (nonce != null && text("nonce") != nonce) return null
            payload.getValue("testPurchase").jsonPrimitive.boolean // Require the versioned contract, including test marker.
            val issuedSeconds = number("iat")
            val verifiedAt = number("verifiedAtMs")
            val cacheUntil = number("cacheUntilMs")
            val revision = number("revision")
            if (issuedSeconds <= 0 || issuedSeconds > (nowMs + CLOCK_TOLERANCE_MS) / 1000 ||
                verifiedAt <= 0 || verifiedAt > issuedSeconds * 1000 + 999 || revision <= 0 ||
                cacheUntil <= verifiedAt || number("exp") != (cacheUntil + 999) / 1000) return null
            val status = text("status")
            if (status !in setOf("active", "inactive", "pending")) return null
            val expiry = payload.getValue("expiresAtMs").takeUnless { it == JsonNull }?.jsonPrimitive?.long
            if (!subscription && expiry != null) return null
            if (status == "active") {
                if (subscription && (expiry == null || expiry <= verifiedAt || cacheUntil != expiry)) return null
                if (!subscription && cacheUntil > verifiedAt + YEAR_CACHE_MS) return null
            } else if (cacheUntil > issuedSeconds * 1000 + 86_400_999) return null
            BillingReceipt(productId, subscription, status, expiry, verifiedAt, cacheUntil, revision)
        }.getOrNull()
    }
}

internal object ServerEntitlementPolicy {
    fun status(purchases: List<VerifiedPurchase>, receipts: Map<String, BillingReceipt>, nowMs: Long, offline: Boolean): PlusStatus {
        val purchased = purchases.filter { it.purchased && !it.suspended }
        val known = purchased.map { receipts[it.token] }
        if (known.any { it?.activeAt(nowMs) == true && !it.subscription }) return PlusStatus.LIFETIME
        if (known.any { it?.activeAt(nowMs) == true && it.subscription }) return PlusStatus.SUBSCRIBED
        if (purchases.any { it.pending } || known.any { it?.status == "pending" && it.usableAt(nowMs) }) return PlusStatus.PENDING
        if (known.any { it == null || !it.usableAt(nowMs) }) return PlusStatus.OFFLINE
        return if (purchased.isEmpty() && offline) PlusStatus.OFFLINE else PlusStatus.FREE
    }
}
