package com.rainif.doneat.plus

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

class ReviewGrantTest {
    private val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
    private val keys = mapOf("review-test" to Base64.getEncoder().encodeToString(pair.public.encoded))
    private val now = 1_800_000_000_123L
    private fun token(typ: String = "doneat-review-access+jwt", change: MutableMap<String, JsonElement>.() -> Unit = {}): String {
        val header = buildJsonObject { put("alg", "RS256"); put("typ", typ); put("kid", "review-test") }
        val payload = buildJsonObject {
            put("iss", ReviewGrant.ISSUER); put("aud", ReviewGrant.AUDIENCE); put("sub", "install"); put("v", 1)
            put("purpose", "app-review"); put("scope", "plus"); put("credentialRevision", 2)
            put("installationKeyHash", "fingerprint"); put("nonce", "nonce"); put("serverTimeMs", now)
            put("iat", now / 1000); put("exp", now / 1000 + 86400)
        }.toMutableMap().apply(change)
        val encoder = Base64.getUrlEncoder().withoutPadding()
        val content = encoder.encodeToString(header.toString().toByteArray()) + "." + encoder.encodeToString(JsonObject(payload).toString().toByteArray())
        return content + "." + encoder.encodeToString(Signature.getInstance("SHA256withRSA").run { initSign(pair.private); update(content.toByteArray()); sign() })
    }
    private fun read(raw: String) = ReviewGrant.read(raw, keys, "install", "fingerprint", "nonce")
    @Test fun strictReviewIdentityAndPurchaseIsolation() {
        assertNotNull(read(token()))
        assertNull(read(token("JWT")))
        for ((key, value) in listOf("aud" to "com.rainif.doneat", "purpose" to "purchase", "scope" to "lifetime", "sub" to "other", "installationKeyHash" to "copied", "nonce" to "replay")) {
            assertNull(key, read(token { this[key] = JsonPrimitive(value) }))
        }
        assertNull(read(token { this["exp"] = JsonPrimitive(now / 1000 + 86401) }))
        assertNull(read(token { this["credentialRevision"] = JsonPrimitive(0) }))
        assertNull(ReviewGrant.read(token(), emptyMap(), "install", "fingerprint"))
        assertNull(read(token().dropLast(8) + "tampered"))
        assertNull(BillingReceipt.read(token(), keys, "com.rainif.doneat", "doneat_plus", "token", true, now))
    }
    @Test fun offlineLeaseCannotBeExtendedByWallClockOrReboot() {
        val lease = ReviewLease(now, 1000, 5, now + 86400000)
        assertEquals(86400000L, lease.remainingMs(1000, 5))
        assertEquals(0L, lease.remainingMs(999, 5))
        assertEquals(0L, lease.remainingMs(1000, 6))
        assertEquals(0L, lease.remainingMs(86401000, 5))
        assertEquals(0L, lease.remainingMs(100000000, 5))
        val earlierWall = now - 100000000
        assertEquals(earlierWall + 86399000, lease.effectiveExpiryMs(earlierWall, 2000, 5))
        assertEquals(0L, ReviewLease(now,1000,-1,now+86400000).remainingMs(1000,-1))
    }

    @Test fun verifiesRealJoseServerFixture() {
        val fixture = Json.parseToJsonElement(javaClass.getResource("/review-jose-grant.json")!!.readText()).jsonObject
        val raw = fixture.getValue("grant").jsonPrimitive.content
        val keys = fixture.getValue("publicKeys").jsonObject.mapValues { it.value.jsonPrimitive.content }
        val grant = ReviewGrant.read(raw, keys, fixture.getValue("installationId").jsonPrimitive.content,
            fixture.getValue("installationKeyHash").jsonPrimitive.content, fixture.getValue("nonce").jsonPrimitive.content)
        assertNotNull(grant)
        assertEquals(now, grant!!.issuedAtMs)
    }

    @Test fun erasureSurvivesIndependentStorageFailures() {
        var removed = false
        eraseReviewStorage({ error("unavailable") }, { error("keystore unavailable") }, { removed = true }, { false }, { removed }, { false })
        assertTrue(removed)
        var keyRemoved = false
        eraseReviewStorage({ error("disk") }, { keyRemoved = true }, { error("disk") }, { false }, { false }, { keyRemoved })
        assertTrue(keyRemoved)
        eraseReviewStorage({}, { error("key") }, { error("file") }, { true }, { false }, { false })
        assertThrows(IllegalStateException::class.java) {
            eraseReviewStorage({ error("disk") }, { error("key") }, { error("disk") }, { false }, { false }, { false })
        }
    }
}
