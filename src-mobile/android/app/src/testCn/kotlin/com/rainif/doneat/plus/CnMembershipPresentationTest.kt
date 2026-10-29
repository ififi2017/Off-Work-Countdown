package com.rainif.doneat.plus

import org.junit.Assert.*
import org.junit.Test

class CnMembershipPresentationTest {
    @Test fun connectionHelpIsDebugOnlyAndOperationNotFoundKeepsRetryGuidance() {
        assertEquals(CnMembershipNotice.DEBUG_CONNECTION, cnMembershipNotice("connection_unavailable", true, true))
        assertEquals(CnMembershipNotice.CONNECTION, cnMembershipNotice("connection_unavailable", true, false))
        assertEquals(CnMembershipNotice.RETRY_ORIGINAL, cnMembershipNotice("operation_not_found", true, true))
        assertEquals(CnMembershipNotice.PENDING, cnMembershipNotice(null, true, false))
    }
    @Test fun signedInactiveStatesNeverBecomeOfflineOrVerifiedPresentation() {
        for ((reason, expected) in listOf("revoked" to CnAccessPresentation.REVOKED, "replaced" to CnAccessPresentation.REPLACED, "expired" to CnAccessPresentation.EXPIRED)) {
            assertEquals(expected, cnAccessPresentation(reason, false, true, "connection_unavailable", 0))
        }
        assertEquals(CnAccessPresentation.SAVED, cnAccessPresentation("valid", true, false, "connection_unavailable", 14))
        assertEquals(CnAccessPresentation.NEEDS_PROOF, cnAccessPresentation("valid", false, false, "connection_unavailable", null))
    }
    @Test fun trialCountRoundsUpAndShowsZeroAtExpiryWithoutUsingDeviceWallTime() {
        val end = 1_000L + 14 * CnLicenseProtocol.DAY_MS
        assertEquals(14, cnTrialDaysRemaining(end, 1_000, 0))
        assertEquals(1, cnTrialDaysRemaining(end, 1_000, 14 * CnLicenseProtocol.DAY_MS - 1))
        assertEquals(0, cnTrialDaysRemaining(end, 1_000, 14 * CnLicenseProtocol.DAY_MS))
        assertNull(cnTrialDaysRemaining(end, 1_000, null))
        assertEquals(CnAccessPresentation.EXPIRED, cnAccessPresentation("valid", true, false, null, 0))
    }
}
