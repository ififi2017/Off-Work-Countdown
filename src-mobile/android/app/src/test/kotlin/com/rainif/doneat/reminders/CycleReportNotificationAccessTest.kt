package com.rainif.doneat.reminders

import com.rainif.doneat.plus.PlusStatus
import com.rainif.doneat.plus.PlusStoreState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CycleReportNotificationAccessTest {
    @Test fun incompletePurchaseQueriesCannotClearVerifiedRegistrations() {
        listOf(PlusStatus.LOADING, PlusStatus.OFFLINE, PlusStatus.ERROR, PlusStatus.PENDING).forEach { status ->
            assertNull(reportNotificationAccess(false, PlusStoreState(status)))
        }
    }
    @Test fun confirmedFreeClearsAndVerifiedPurchaseOrDebugAccessSchedules() {
        assertEquals(false, reportNotificationAccess(false, PlusStoreState(PlusStatus.FREE)))
        assertEquals(false, reportNotificationAccess(false, PlusStoreState(PlusStatus.UNCONFIGURED)))
        assertEquals(true, reportNotificationAccess(false, PlusStoreState(PlusStatus.SUBSCRIBED)))
        assertEquals(true, reportNotificationAccess(false, PlusStoreState(PlusStatus.LIFETIME)))
        assertEquals(true, reportNotificationAccess(true, PlusStoreState(PlusStatus.UNCONFIGURED)))
    }
}
