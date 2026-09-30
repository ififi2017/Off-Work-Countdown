package com.rainif.doneat.plus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EntitlementEngineTest {
    private val now = 1_000_000_000L
    private fun purchase(subscription: Boolean = true, pending: Boolean = false, suspended: Boolean = false,
        acknowledged: Boolean = false, firstSeen: Long = now) = VerifiedPurchase(
        "configured-product", "token", subscription, !pending, pending, suspended, acknowledged, firstSeen,
    )

    @Test fun purchaseLifecycle() {
        assertEquals(PlusStatus.FREE, EntitlementEngine.status(emptyList(), now, now, false))
        assertEquals(PlusStatus.PENDING, EntitlementEngine.status(listOf(purchase(pending = true)), now, now, false))
        assertEquals(PlusStatus.SUBSCRIBED, EntitlementEngine.status(listOf(purchase()), now, now, false))
        assertEquals(PlusStatus.FREE, EntitlementEngine.status(listOf(purchase(suspended = true)), now, now, false))
        assertEquals(PlusStatus.LIFETIME, EntitlementEngine.status(listOf(purchase(subscription = false)), now, now, false))
        assertEquals(PlusStatus.OFFLINE, EntitlementEngine.status(emptyList(), now, now, true))
    }

    @Test fun offlineSubscriptionExpiresButLifetimeSurvives() {
        assertEquals(PlusStatus.SUBSCRIBED,
            EntitlementEngine.status(listOf(purchase()), now, now - EntitlementEngine.OFFLINE_SUBSCRIPTION_MS, true))
        assertEquals(PlusStatus.OFFLINE,
            EntitlementEngine.status(listOf(purchase()), now, now - EntitlementEngine.OFFLINE_SUBSCRIPTION_MS - 1, true))
        assertEquals(PlusStatus.LIFETIME,
            EntitlementEngine.status(listOf(purchase(subscription = false)), now, 0, true))
    }

    @Test fun acknowledgementOnlyDuringPurchasedWindow() {
        assertFalse(EntitlementEngine.shouldAcknowledge(purchase(pending = true), now))
        assertFalse(EntitlementEngine.shouldAcknowledge(purchase(acknowledged = true), now))
        assertTrue(EntitlementEngine.shouldAcknowledge(purchase(firstSeen = now - EntitlementEngine.ACK_WINDOW_MS + 1), now))
        assertFalse(EntitlementEngine.shouldAcknowledge(purchase(firstSeen = now - EntitlementEngine.ACK_WINDOW_MS), now))
    }

    @Test fun lifetimeDoesNotHideASeparateSubscription() {
        val purchases = listOf(purchase(subscription = false), purchase())
        assertEquals(PlusStatus.LIFETIME, EntitlementEngine.status(purchases, now, now, false))
        assertTrue(EntitlementEngine.hasActiveSubscription(purchases, now, now, false))
        assertFalse(EntitlementEngine.hasActiveSubscription(listOf(purchase(subscription = false)), now, now, false))
    }

    @Test fun subscriptionNoticeRequiresCurrentVerifiedEntitlement() {
        assertFalse(EntitlementEngine.hasActiveSubscription(listOf(purchase(pending = true)), now, now, false))
        assertFalse(EntitlementEngine.hasActiveSubscription(listOf(purchase(suspended = true)), now, now, false))
        assertTrue(EntitlementEngine.hasActiveSubscription(listOf(purchase()), now,
            now - EntitlementEngine.OFFLINE_SUBSCRIPTION_MS, true))
        assertFalse(EntitlementEngine.hasActiveSubscription(listOf(purchase()), now,
            now - EntitlementEngine.OFFLINE_SUBSCRIPTION_MS - 1, true))
    }
}
