package com.rainif.doneat.alarms

import com.rainif.doneat.core.domain.alarms.ShiftAlarmAuthorization
import com.rainif.doneat.plus.PlusStoreState
import com.rainif.doneat.plus.PlusStatus
import org.junit.Assert.*
import org.junit.Test

class ShiftAlarmPlayAccessTest {
    @Test fun signedCachedOfflineExpiryAuthorizesButClientCacheWithoutExpiryDoesNot() {
        val now = 1_800_000_000_000L
        val cached = PlusStoreState(PlusStatus.SUBSCRIBED, verifiedSubscriptionExpiresAtMs = now + 60_000,
            currentEntitlementsVerified = false)
        assertEquals(ShiftAlarmAuthorization.VerifiedUntil(now + 60_000), cached.shiftAlarmAuthorization(now))
        assertEquals(ShiftAlarmAuthorization.Unavailable, cached.shiftAlarmAuthorization(now + 60_000))
        assertEquals(ShiftAlarmAuthorization.Unavailable, cached.copy(verifiedSubscriptionExpiresAtMs = null).shiftAlarmAuthorization(now))
    }
}
