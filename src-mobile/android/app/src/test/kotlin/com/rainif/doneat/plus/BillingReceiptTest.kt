package com.rainif.doneat.plus

import com.rainif.doneat.core.domain.alarms.ShiftAlarmAuthorization
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

class BillingReceiptTest {
    private val now = 1_800_000_000_000L
    private val expiry = now + 3_600_123L
    private val token = "a-test-purchase-token"
    private val product = "doneat_plus"
    private val packageName = "com.rainif.doneat"
    private val nonce = "a_test_nonce_1234567890"
    private val keys = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
    private val publicKeys = mapOf("test-key" to Base64.getEncoder().encodeToString(keys.public.encoded))
    private fun payload(edit: JsonObjectBuilder.() -> Unit = {}) = buildJsonObject {
        put("v", 1); put("iss", BillingReceipt.ISSUER); put("aud", packageName)
        put("sub", BillingReceipt.tokenHash(token)); put("productId", product); put("kind", "subscription")
        put("status", "active"); put("expiresAtMs", expiry); put("verifiedAtMs", now)
        put("cacheUntilMs", expiry); put("revision", 1); put("nonce", nonce); put("testPurchase", false)
        put("iat", now / 1000); put("exp", (expiry + 999) / 1000); edit()
    }
    private fun sign(payload: JsonObject = payload(), header: String = """{"alg":"RS256","typ":"JWT","kid":"test-key"}"""): String {
        val encoder = Base64.getUrlEncoder().withoutPadding()
        val body = listOf(header, payload.toString()).joinToString(".") { encoder.encodeToString(it.toByteArray()) }
        val signature = Signature.getInstance("SHA256withRSA").run {
            initSign(keys.private); update(body.toByteArray()); encoder.encodeToString(sign())
        }
        return "$body.$signature"
    }
    private fun read(raw: String = sign(), at: Long = now, expectedNonce: String? = nonce, subscription: Boolean = true) =
        BillingReceipt.read(raw, publicKeys, packageName, product, token, subscription, at, expectedNonce)
    private fun purchase(subscription: Boolean = true, token: String = this.token) =
        VerifiedPurchase(if (subscription) product else "lifetime", token, subscription, true, false, false, true, now)

    @Test fun preciseExpirySurvivesSigningAndStopsAtTheExactMillisecond() {
        val receipt = read()!!
        assertEquals(expiry, receipt.expiresAtMs)
        assertTrue(receipt.activeAt(expiry - 1)); assertFalse(receipt.activeAt(expiry))
        assertNotNull(read(sign(), at = expiry + 1)) // Keep signed evidence without granting from it.
        assertFalse(receipt.activeAt(now - 30_001))
        assertEquals(ShiftAlarmAuthorization.VerifiedUntil(expiry),
            PlusStoreState(PlusStatus.SUBSCRIBED, verifiedSubscriptionExpiresAtMs = expiry).shiftAlarmAuthorization(now))
        assertEquals(ShiftAlarmAuthorization.Unavailable,
            PlusStoreState(PlusStatus.SUBSCRIBED, verifiedSubscriptionExpiresAtMs = expiry).shiftAlarmAuthorization(expiry))
        assertEquals(ShiftAlarmAuthorization.Unavailable, PlusStoreState(PlusStatus.SUBSCRIBED).shiftAlarmAuthorization(now))
    }
    @Test fun verifiesSignatureInsteadOfTrustingDecodedJson() {
        val raw = sign()
        val parts = raw.split('.')
        val replacement = Base64.getUrlEncoder().withoutPadding().encodeToString(payload { put("expiresAtMs", expiry + 1) }.toString().toByteArray())
        assertNull(read("${parts[0]}.$replacement.${parts[2]}"))
        assertNull(read("${parts[0]}.${parts[1]}.AAAA"))
        assertNull(read("x".repeat(16_385)))
        assertNull(read("${parts[0]}.${parts[1]}"))
    }
    @Test fun bindsEveryReceiptToTheRequestAndConfiguredSigningKey() {
        for ((name, value) in mapOf("iss" to "https://elsewhere.test", "aud" to "another.app", "sub" to "another-token",
            "productId" to "another-product", "kind" to "lifetime", "nonce" to "another-nonce")) {
            assertNull(name, read(sign(payload { put(name, value) })))
        }
        assertNull(read(sign(header = """{"alg":"HS256","typ":"JWT","kid":"test-key"}""")))
        assertNull(read(sign(header = """{"alg":"RS256","typ":"JWT","kid":"unknown"}""")))
        assertNull(read(sign(header = """{"alg":"RS256","typ":"JWT","kid":"test-key","crit":[]}""")))
        assertNotNull(read(expectedNonce = null)) // Cached receipts have no fresh network nonce.
    }
    @Test fun rejectsInconsistentTimesStatesAndVersions() {
        val invalid: List<JsonObjectBuilder.() -> Unit> = listOf(
            { put("v", 2) }, { put("revision", 0) }, { put("status", "unknown") },
            { put("verifiedAtMs", now + 1000) }, { put("iat", now / 1000 + 31) },
            { put("cacheUntilMs", expiry + 1) }, { put("exp", expiry / 1000) },
            { put("expiresAtMs", JsonNull) }, { put("expiresAtMs", now) },
        )
        invalid.forEach { assertNull(read(sign(payload(it)))) }
    }
    @Test fun lifetimeUsesCacheValidityWithoutInventingASubscriptionExpiry() {
        val until = now + 366L * 86_400_000
        val receipt = read(sign(payload {
            put("kind", "lifetime"); put("expiresAtMs", JsonNull); put("cacheUntilMs", until); put("exp", until / 1000)
        }), subscription = false)!!
        assertNull(receipt.expiresAtMs); assertTrue(receipt.activeAt(until - 1)); assertFalse(receipt.activeAt(until))
        assertNull(read(sign(payload { put("kind", "lifetime") }), subscription = false))
    }
    @Test fun missingOrExpiredEvidenceNeverFallsBackToTheLocalPurchaseBoolean() {
        val purchased = listOf(purchase())
        assertEquals(PlusStatus.OFFLINE, ServerEntitlementPolicy.status(purchased, emptyMap(), now, false))
        assertEquals(PlusStatus.SUBSCRIBED, ServerEntitlementPolicy.status(purchased, mapOf(token to read()!!), now, true))
        assertEquals(PlusStatus.OFFLINE, ServerEntitlementPolicy.status(purchased, mapOf(token to read()!!), expiry, true))
        assertEquals(PlusStatus.FREE, ServerEntitlementPolicy.status(emptyList(), mapOf(token to read()!!), now, false))
        assertEquals(PlusStatus.FREE, ServerEntitlementPolicy.status(listOf(purchase().copy(suspended = true)), mapOf(token to read()!!), now, false))
    }
    @Test fun confirmedRevocationWinsOverCachedPlayOwnershipAndPendingNeverGrants() {
        val active = read()!!
        assertEquals(PlusStatus.FREE, ServerEntitlementPolicy.status(listOf(purchase()), mapOf(token to active.copy(status = "inactive")), now, true))
        assertEquals(PlusStatus.PENDING, ServerEntitlementPolicy.status(listOf(purchase()), mapOf(token to active.copy(status = "pending")), now, false))
        assertEquals(PlusStatus.PENDING, ServerEntitlementPolicy.status(listOf(purchase().copy(purchased = false, pending = true)), emptyMap(), now, false))
        val lifetime = active.copy(subscription = false, expiresAtMs = null)
        assertEquals(PlusStatus.LIFETIME, ServerEntitlementPolicy.status(listOf(purchase(), purchase(false, "life")), mapOf(token to active, "life" to lifetime), now, false))
    }
}
