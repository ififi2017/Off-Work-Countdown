package com.rainif.doneat.plus

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

/** Real signed sequences; network and Android Keystore behavior still require device evidence. */
class CnLicenseLifecycleTest {
    private val f = CnReceiptTestFixtures
    private fun inactive(reason: String) = f.claims {
        put("status", "inactive"); put("reason", reason); put("licenseRevision", 4)
        put("serverTimeMs", f.NOW + 60_000); put("iat", (f.NOW + 60_000) / 1000)
        put("leaseUntilMs", f.NOW + 360_000); put("exp", (f.NOW + 360_000) / 1000)
    }
    private fun rejected(block: () -> Unit) { assertTrue(runCatching(block).isFailure) }

    @Test fun replacedOldDeviceStopsBeforeItsCachedLeaseAndCannotAcceptTheNewDevicesReceipt() {
        val original = f.read(); val replaced = f.read(f.token(inactive("replaced")), previous = original)
        val before = CnLeaseAnchor(1000, f.NOW, 7)
        assertTrue(before.authorized(original, 61_000, f.NOW + 60_000, 7))
        assertFalse(CnLeaseAnchor(61_000, f.NOW + 60_000, 7).authorized(replaced, 61_000, f.NOW + 60_000, 7))
        rejected { f.read(f.token(), previous = replaced) }
        val newDevice = "b".repeat(64)
        val current = f.token(f.claims { put("deviceKeyHash", newDevice); put("bindingVersion", 3); put("licenseRevision", 4) })
        assertTrue(f.read(current, device = newDevice).active)
        rejected { f.read(current, device = f.DEVICE) }
    }
    @Test fun signedRefundRevocationStopsAccessImmediatelyAndOldActiveEvidenceCannotReviveIt() {
        val original = f.read(); val revoked = f.read(f.token(inactive("revoked")), previous = original)
        assertFalse(revoked.active)
        assertTrue(revoked.expiresAtMs!! > f.NOW + 60_000) // Revocation, rather than annual expiry, stopped access.
        assertFalse(CnLeaseAnchor(2000, f.NOW + 60_000, 7).authorized(revoked, 2000, f.NOW + 60_000, 7))
        rejected { f.read(f.token(), previous = revoked) }
        val invalidProof = f.token(inactive("revoked").let { JsonObject(it + ("nonce" to JsonPrimitive("wrong_nonce"))) })
        rejected { f.read(invalidProof, previous = original) }
        // Failure to verify an alleged revocation is not evidence that can replace the valid old lease.
        assertTrue(CnLeaseAnchor(1000, f.NOW, 7).authorized(original, 2000, f.NOW + 1000, 7))
    }
    @Test fun annualLifetimeAndTrialAllStopAtTheExactOfflineLeaseBoundary() {
        for (plan in listOf("annual", "lifetime", "trial")) {
            val r = f.read(f.token(f.claims {
                put("plan", plan); put("source", if (plan == "trial") "trial" else "license")
                if (plan == "lifetime") put("entitlementExpiresAtMs", JsonNull)
                if (plan == "trial") put("entitlementExpiresAtMs", f.NOW + 14 * CnLicenseProtocol.DAY_MS)
            }))
            val a = CnLeaseAnchor(1000, f.NOW, 7)
            assertTrue(plan, a.authorized(r, 1000 + CnLicenseProtocol.DAY_MS - 1, f.NOW + CnLicenseProtocol.DAY_MS - 1, 7))
            assertFalse(plan, a.authorized(r, 1000 + CnLicenseProtocol.DAY_MS, f.NOW + CnLicenseProtocol.DAY_MS, 7))
        }
    }
    @Test fun annualExpiryCanShortenTheLeaseAndDisconnectDoesNotExtendIt() {
        val r = f.read(f.token(f.claims {
            put("entitlementExpiresAtMs", f.NOW + 10_000); put("leaseUntilMs", f.NOW + 10_000); put("exp", (f.NOW + 10_000) / 1000)
        }))
        val a = CnLeaseAnchor(1000, f.NOW, 7)
        assertTrue(a.authorized(r, 10_999, f.NOW + 9999, 7))
        assertFalse(a.authorized(r, 11_000, f.NOW + 10_000, 7))
        assertFalse(a.forNetworkResult(false).authorized(r, 1000, f.NOW, 7))
    }
    @Test fun reconnectAfterOfflineExpiryOrRebootRequiresANewBoundSignedReceipt() {
        val old = f.read(); val oldAnchor = CnLeaseAnchor(1000, f.NOW, 7)
        val server = f.NOW + CnLicenseProtocol.DAY_MS + 1000
        val request = "55555555-5555-4555-8555-555555555555"
        val nonce = CnLicenseProtocol.encode(ByteArray(24) { (it + 30).toByte() })
        assertFalse(oldAnchor.authorized(old, 1000 + CnLicenseProtocol.DAY_MS, f.NOW + CnLicenseProtocol.DAY_MS, 7))
        assertFalse(oldAnchor.authorized(old, 2000, f.NOW + 1000, 8))
        rejected { f.read(f.token(), request = request, nonce = nonce, previous = old) }
        val fresh = f.read(f.token(f.claims {
            put("requestId", request); put("nonce", nonce); put("serverTimeMs", server); put("iat", server / 1000)
            put("leaseUntilMs", server + CnLicenseProtocol.DAY_MS); put("exp", (server + CnLicenseProtocol.DAY_MS) / 1000)
        }), request = request, nonce = nonce, previous = old)
        assertTrue(CnLeaseAnchor(5000, server, 8).forNetworkResult(true).authorized(fresh, 5000, server, 8))
    }
}
