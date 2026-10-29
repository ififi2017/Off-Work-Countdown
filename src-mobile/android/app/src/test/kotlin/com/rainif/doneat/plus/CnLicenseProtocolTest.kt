package com.rainif.doneat.plus

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

class CnLicenseProtocolTest {
    private val request = "11111111-1111-4111-8111-111111111111"
    private val nonce = "MDEyMzQ1Njc4OWFiY2RlZg"
    private val hash = "a".repeat(64)
    private val now = 1_800_000_000_000L
    private val pair by lazy { KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair() }
    private val keys get() = mapOf("test" to Base64.getEncoder().encodeToString(pair.public.encoded))
    private fun claims() = buildJsonObject {
        put("iss", CnLicenseProtocol.ISSUER); put("aud", "com.rainif.doneat.cn"); put("channel", "cn"); put("v", 1)
        put("sub", "22222222-2222-4222-8222-222222222222"); put("deviceKeyHash", hash)
        put("bindingVersion", 2); put("licenseRevision", 3); put("source", "license"); put("plan", "annual")
        put("status", "active"); put("reason", "valid"); put("entitlementExpiresAtMs", now + 365 * CnLicenseProtocol.DAY_MS)
        put("serverTimeMs", now); put("leaseUntilMs", now + CnLicenseProtocol.DAY_MS)
        put("requestId", request); put("nonce", nonce); put("iat", now / 1000); put("exp", (now + CnLicenseProtocol.DAY_MS) / 1000)
    }
    private fun signed(body: JsonObject, header: JsonObject = buildJsonObject { put("alg", "RS256"); put("typ", "JWT"); put("kid", "test") }): String {
        val encoded = CnLicenseProtocol.encode(header.toString().toByteArray()) + "." + CnLicenseProtocol.encode(body.toString().toByteArray())
        val signature = Signature.getInstance("SHA256withRSA").run { initSign(pair.private); update(encoded.toByteArray()); sign() }
        return encoded + "." + CnLicenseProtocol.encode(signature)
    }
    private fun read(body: JsonObject = claims(), previous: CnReceipt? = null) = CnReceipt.verify(signed(body), keys, "com.rainif.doneat.cn", hash, request, nonce, previous)
    private fun reject(block: () -> Unit) { assertTrue(runCatching(block).isFailure) }
    @Test fun publicP256VectorVerifiesExactProofAndRejectsOneByteMutation() {
        val fixture = Json.parseToJsonElement(javaClass.getResource("/cn-protocol-vector.json")!!.readText()).jsonObject
        fun str(key: String) = fixture.getValue(key).jsonPrimitive.content
        val payload = str("payloadUtf8").toByteArray()
        assertEquals(str("payloadHash"), CnLicenseProtocol.hash(payload))
        val message = CnLicenseProtocol.proof(str("operation"), str("challengeId"), str("serverNonce"), payload)
        assertEquals(str("message"), message.decodeToString())
        assertFalse(message.last() == 10.toByte())
        val publicKey = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(CnLicenseProtocol.decode(str("publicKey"))))
        fun verifies(bytes: ByteArray) = Signature.getInstance("SHA256withECDSA").run { initVerify(publicKey); update(bytes); verify(CnLicenseProtocol.decode(str("signature"))) }
        assertTrue(verifies(message)); assertFalse(verifies(message.copyOf().also { it[0] = 'C'.code.toByte() }))
    }
    @Test fun commandSerializesOnceAndFreshCommandsNeverReuseRequestOrNonce() {
        val fields = buildJsonObject { put("code", "DA1-a-code") }
        val first = CnLicenseProtocol.command(fields)
        val second = CnLicenseProtocol.command(fields)
        assertFalse(first.contentEquals(second))
        assertTrue(first.contentEquals(CnLicenseProtocol.decode(CnLicenseProtocol.encode(first))))
        reject { CnLicenseProtocol.command(buildJsonObject { put("requestId", request) }) }
    }
    @Test fun canonicalTransportRejectsPaddingAndNonCanonicalLowBits() {
        assertEquals("a", CnLicenseProtocol.decode("YQ").decodeToString())
        reject { CnLicenseProtocol.decode("YQ==") }; reject { CnLicenseProtocol.decode("YR") }; reject { CnLicenseProtocol.decode("a+b/") }
    }
    @Test fun annualLifetimeAndTrialRequireSignedBoundLease() {
        assertTrue(read().active)
        assertEquals("trial", read(JsonObject(claims() + mapOf("source" to JsonPrimitive("trial"), "plan" to JsonPrimitive("trial")))).source)
        assertEquals("lifetime", read(JsonObject(claims() + mapOf("plan" to JsonPrimitive("lifetime"), "entitlementExpiresAtMs" to JsonNull))).plan)
        assertEquals("license", read(JsonObject(claims().filterKeys { it != "source" })).source)
    }
    @Test fun everyTrustBoundaryRejectsSignedMismatches() {
        val bad = mapOf("iss" to JsonPrimitive("https://evil.example"), "aud" to JsonPrimitive("com.rainif.doneat"), "channel" to JsonPrimitive("play"),
            "v" to JsonPrimitive(2), "deviceKeyHash" to JsonPrimitive("b".repeat(64)), "requestId" to JsonPrimitive("wrong"), "nonce" to JsonPrimitive("wrong"),
            "status" to JsonPrimitive("pending"), "reason" to JsonPrimitive("revoked"), "bindingVersion" to JsonPrimitive(0), "licenseRevision" to JsonPrimitive(0),
            "plan" to JsonPrimitive("monthly"), "iat" to JsonPrimitive(now / 1000 - 1), "exp" to JsonPrimitive(now / 1000 + 1),
            "entitlementExpiresAtMs" to JsonNull, "leaseUntilMs" to JsonPrimitive(now + CnLicenseProtocol.DAY_MS + 1000))
        bad.forEach { (key, value) -> reject { read(JsonObject(claims() + (key to value))) } }
        reject { CnReceipt.verify(signed(claims()), emptyMap(), "com.rainif.doneat.cn", hash, request, nonce) }
        reject { CnReceipt.verify(signed(claims()) + "x", keys, "com.rainif.doneat.cn", hash, request, nonce) }
        reject { CnReceipt.verify(signed(claims(), buildJsonObject { put("alg", "none"); put("typ", "JWT"); put("kid", "test") }), keys, "com.rainif.doneat.cn", hash, request, nonce) }
    }
    @Test fun signedInactiveRevokesAndStateCannotRollBack() {
        val before = read()
        val inactive = read(JsonObject(claims() + mapOf("status" to JsonPrimitive("inactive"), "reason" to JsonPrimitive("revoked"),
            "leaseUntilMs" to JsonPrimitive(now + 300_000), "exp" to JsonPrimitive((now + 300_000) / 1000), "licenseRevision" to JsonPrimitive(4))), before)
        assertFalse(inactive.active)
        reject { read(previous = inactive) }
        reject { read(JsonObject(claims() + ("bindingVersion" to JsonPrimitive(1))), before) }
        reject { read(JsonObject(claims() + ("serverTimeMs" to JsonPrimitive(now - 1000))), before) }
    }
    @Test fun anExpiredSignedCommandOutcomeCanBeRecoveredButCannotGrantAccess() {
        val oldOutcome = JsonObject(claims() + mapOf(
            "leaseUntilMs" to JsonPrimitive(now - 1000), "exp" to JsonPrimitive(now / 1000 - 1),
        ))
        reject { read(oldOutcome) }
        val raw = signed(oldOutcome)
        val recovered = CnReceipt.verify(raw, keys, "com.rainif.doneat.cn", hash, request, nonce, allowExpiredLeaseForRecovery = true)
        assertEquals("22222222-2222-4222-8222-222222222222", recovered.id)
        assertFalse(recovered.active)
        assertFalse(CnLeaseAnchor(1000, now, 7).authorized(recovered, 1000, now, 7))
        // Recovery does not waive nonce, device, signature or high-water verification.
        reject { CnReceipt.verify(raw, keys, "com.rainif.doneat.cn", hash, request, "wrong", allowExpiredLeaseForRecovery = true) }
        reject { CnReceipt.verify(raw, keys, "com.rainif.doneat.cn", "b".repeat(64), request, nonce, allowExpiredLeaseForRecovery = true) }
        val fresh = read()
        assertTrue(fresh.active)
        assertTrue(CnLeaseAnchor(1000, now, 7).authorized(fresh, 1000, now, 7))
    }
    @Test fun replayingAnOldCommandResponseCannotReanchorItsOfflineLease() {
        val current = read()
        val network = CnLeaseAnchor(5000, now, 7)
        // Even an otherwise valid signed receipt from a retained nonce is outcome-only.
        assertFalse(network.forNetworkResult(freshNonce = false).authorized(current, 5000, now, 7))
        // A newly signed operation query or refresh with a new bound nonce can anchor.
        assertTrue(network.forNetworkResult(freshNonce = true).authorized(current, 5000, now, 7))
        // A new network proof during the next boot may establish a new anchor; cached proof may not.
        assertFalse(network.authorized(current, 6000, now + 1000, 8))
        assertTrue(CnLeaseAnchor(1000, now + 1000, 8).forNetworkResult(true).authorized(current, 1000, now + 1000, 8))
    }
    @Test fun expiredTrialOutcomeKeepsItsTrialIdWithoutGrantingOrRestartingTrial() {
        val old = JsonObject(claims() + mapOf("source" to JsonPrimitive("trial"), "plan" to JsonPrimitive("trial"),
            "leaseUntilMs" to JsonPrimitive(now - 1000), "exp" to JsonPrimitive(now / 1000 - 1)))
        val r = CnReceipt.verify(signed(old), keys, "com.rainif.doneat.cn", hash, request, nonce, allowExpiredLeaseForRecovery = true)
        assertEquals("trial", r.source); assertFalse(r.active)
        assertEquals(old.getValue("sub").jsonPrimitive.content, r.id)
    }
    @Test fun monotonicLeaseExpiresOfflineAndRebootOrClockRollbackRequiresNetwork() {
        val receipt = read(); val anchor = CnLeaseAnchor(1000, now, 7)
        assertTrue(anchor.authorized(receipt, 2000, now + 1000, 7))
        assertFalse(anchor.authorized(receipt, 1000 + CnLicenseProtocol.DAY_MS, now + CnLicenseProtocol.DAY_MS, 7))
        assertFalse(anchor.authorized(receipt, 100, now + 1000, 8))
        assertFalse(anchor.authorized(receipt, 2000, now - 300_000, 7))
        assertFalse(anchor.authorized(receipt, 2000, now + 300_000, 7))
        assertFalse(anchor.authorized(receipt, 999, now, 7))
        assertFalse(CnLeaseAnchor(1000, now, -1).authorized(receipt, 2000, now + 1000, -1))
    }
}
