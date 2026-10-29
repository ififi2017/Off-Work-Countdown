package com.rainif.doneat.plus

import com.rainif.doneat.core.domain.reminders.ReminderChannel
import com.rainif.doneat.reminders.paidReminderDeliveryAllowed
import com.rainif.doneat.reminders.reportRegistrationAllowed
import com.rainif.doneat.ongoing.paidOngoingDeadline
import com.rainif.doneat.core.domain.session.OngoingSurface
import org.junit.Assert.*
import org.junit.Test

class CnPaidSurfaceAccessTest {
    @Test fun reportAndFocusDeliveryStopsAtTheLeaseBoundaryIncludingLifetime() {
        for (plan in listOf(PlusStatus.SUBSCRIBED, PlusStatus.LIFETIME)) {
            val store = PlusStoreState(plan, verifiedAuthorizationUntilMs = 2_000)
            for (channel in listOf(ReminderChannel.REPORT, ReminderChannel.FOCUS)) {
                assertTrue(paidReminderDeliveryAllowed(channel, store, true, 1_999))
                assertFalse(paidReminderDeliveryAllowed(channel, store, true, 2_000))
                assertFalse(paidReminderDeliveryAllowed(channel, store, true, 2_001))
                // A reboot/clock rollback or verified revocation cannot reuse a still-future wall deadline.
                assertFalse(paidReminderDeliveryAllowed(channel, store, false, 1_000))
                assertFalse(paidReminderDeliveryAllowed(channel, store.copy(status = PlusStatus.FREE), true, 1_000))
            }
        }
    }

    @Test fun reportsCannotBeRegisteredAtOrBeyondVerifiedLease() {
        val store = PlusStoreState(PlusStatus.LIFETIME, verifiedAuthorizationUntilMs = 2_000)
        assertTrue(reportRegistrationAllowed(store, 1_999))
        assertFalse(reportRegistrationAllowed(store, 2_000))
        assertFalse(reportRegistrationAllowed(store, 2_001))
        assertFalse(reportRegistrationAllowed(store.copy(verifiedAuthorizationUntilMs = null), 1_000))
        assertFalse(reportRegistrationAllowed(store.copy(status = PlusStatus.FREE), 1_000))
    }

    @Test fun unexpiredSubscriptionDateDoesNotReplaceAnExpiredSignedLease() {
        val store = PlusStoreState(PlusStatus.SUBSCRIBED, verifiedSubscriptionExpiresAtMs = 999_999,
            verifiedAuthorizationUntilMs = 2_000)
        assertFalse(paidReminderDeliveryAllowed(ReminderChannel.FOCUS, store, true, 2_000))
        assertFalse(reportRegistrationAllowed(store, 2_000))
    }

    @Test fun freeShiftRemindersRemainUsableWithoutMembership() {
        for (channel in ReminderChannel.entries.filter { it !in setOf(ReminderChannel.REPORT, ReminderChannel.FOCUS) }) {
            assertTrue(paidReminderDeliveryAllowed(channel, PlusStoreState(PlusStatus.FREE), false, 2_000))
        }
    }

    @Test fun focusOngoingTimeoutUsesTheCnLeaseAndUpdatesAfterRenewal() {
        val store = PlusStoreState(PlusStatus.LIFETIME, verifiedAuthorizationUntilMs = 2_000)
        for (surface in listOf(OngoingSurface.FOCUS, OngoingSurface.SHORT_BREAK, OngoingSurface.LONG_BREAK)) {
            assertEquals(2_000L, paidOngoingDeadline(surface, store, 99_999))
            assertEquals(3_000L, paidOngoingDeadline(surface, store.copy(verifiedAuthorizationUntilMs = 3_000), null))
        }
        assertNull(paidOngoingDeadline(OngoingSurface.WORK, store, 99_999))
        assertNull(paidOngoingDeadline(null, store, 99_999))
    }
}
