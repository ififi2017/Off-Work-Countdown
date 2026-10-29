package com.rainif.doneat.plus

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class CnLicenseCacheTest {
    private val f = CnReceiptTestFixtures
    private val pending = """{ "requestId":"33333333-3333-4333-8333-333333333333", "clientNonce":"${CnLicenseProtocol.encode(ByteArray(24) { (it + 10).toByte() })}", "confirmationId":"44444444-4444-4444-8444-444444444444", "expectedRevision":3 }""".toByteArray()
    private fun stamp(keys: Map<String, String> = f.testKeys, app: String = "com.rainif.doneat.cn.debug", audience: String = f.AUDIENCE) =
        CnLicenseCache.trustFingerprint(app, audience, keys)
    private fun data(receipt: Boolean = true, fingerprint: String? = stamp()): JsonObject = buildJsonObject {
        fingerprint?.let { put("trustFingerprint", it) }
        put("paidSeen", true); put("pendingOperation", "activate"); put("pendingPayload", CnLicenseProtocol.encode(pending))
        put("highWater", buildJsonObject { put("license:" + f.LICENSE, buildJsonObject { put("revision", 3); put("binding", 2); put("server", f.NOW) }) })
        if (receipt) {
            put("receipt", f.token()); put("requestId", f.REQUEST); put("nonce", f.NONCE)
            put("anchor", buildJsonObject { put("elapsed", 1000); put("wall", f.NOW); put("boot", 7) })
        }
    }
    private fun read(data: JsonObject, keys: Map<String, String> = f.testKeys, currentStamp: String = stamp(keys)) =
        CnLicenseCache.read(data, currentStamp) { jwt, request, nonce ->
            CnReceipt.verify(jwt, keys, f.AUDIENCE, f.DEVICE, request, nonce, allowExpiredLeaseForRecovery = true)
        }
    private fun rejected(block: () -> Unit) { assertTrue(runCatching(block).isFailure) }

    @Test fun legacySignedCacheRetainsTheExactPendingCommandAndCurrentIdentity() {
        val loaded = read(data(fingerprint = null))
        assertTrue(loaded.paidSeen); assertEquals(f.LICENSE, loaded.receipt!!.id)
        assertEquals("activate", loaded.pendingOperation); assertArrayEquals(pending, loaded.pendingPayload)
        val proof = CnLicenseProtocol.proof("activate", "66666666-6666-4666-8666-666666666666",
            CnLicenseProtocol.encode(ByteArray(32) { it.toByte() }), loaded.pendingPayload!!).decodeToString()
        assertTrue(proof.endsWith(CnLicenseProtocol.hash(pending)))
        assertEquals(CnLeaseAnchor(1000, f.NOW, 7), loaded.anchor)
    }
    @Test fun independentProductionTrustCannotLoadTestReceiptOrItsPendingContext() {
        val old = data()
        val production = mapOf("cn-production-fixture" to f.publicKey(f.productionKey))
        var published: CnLoadedLicenseCache? = null
        rejected { published = read(old, production) }
        assertNull(published)
        // Reusing a kid and audience cannot substitute for possessing the correct signing key.
        rejected { read(old, mapOf(f.TEST_KID to f.publicKey(f.productionKey))) }
    }
    @Test fun pendingOnlyRequiresItsOriginalTrustStampBeforeItCanBeRetried() {
        val original = data(receipt = false)
        assertArrayEquals(pending, read(original).pendingPayload)
        val production = mapOf("cn-production-fixture" to f.publicKey(f.productionKey))
        rejected { read(original, production) }
        rejected { read(original, currentStamp = stamp(app = "com.rainif.doneat.cn")) }
        rejected { read(original, currentStamp = stamp(audience = "another-audience")) }
    }
    @Test fun legacyPendingWithoutAnyReceiptOrTrustProofCannotAutoReplay() {
        rejected { read(data(receipt = false, fingerprint = null)) }
    }
    @Test fun keyAdditionAcceptsTheStillVerifiableReceiptAndItsOriginalPending() {
        val rotated = f.testKeys + ("cn-next-fixture" to f.publicKey(f.productionKey))
        assertNotEquals(stamp(), stamp(rotated))
        val loaded = read(data(), rotated)
        assertEquals(f.LICENSE, loaded.receipt!!.id); assertArrayEquals(pending, loaded.pendingPayload)
    }
    @Test fun deletingTheOldKeyRejectsTheEntirePreviouslyValidContext() {
        val replacement = mapOf("cn-next-fixture" to f.publicKey(f.productionKey))
        rejected { read(data(), replacement) }
    }
    @Test fun matchingStampNeverBypassesCurrentReceiptSignatureVerification() {
        val replacement = mapOf(f.TEST_KID to f.publicKey(f.productionKey))
        // A current stamp plus a receipt signed by a removed key must still fail closed.
        rejected { read(data(fingerprint = stamp(replacement)), replacement) }
    }
    @Test fun fingerprintDoesNotChangeWhenTheSameTrustMapIsReordered() {
        val a = f.testKeys + ("next" to f.publicKey(f.productionKey))
        val b = a.entries.reversed().associate { it.key to it.value }
        assertEquals(stamp(a), stamp(b))
    }
}
