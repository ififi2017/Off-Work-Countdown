package com.rainif.doneat.plus

import java.util.Locale
import org.junit.Assert.*
import org.junit.Test

class LifetimeOfferTest {
    private val now = 1_790_000_000_000L
    private val discount = PlusOffer(PlusPlan.LIFETIME, "€75.00", "eligible-discount",
        priceMicros = 75_000_000, currency = "EUR", regularPrice = "€100.00", regularPriceMicros = 100_000_000,
        purchaseOptionId = "buy", offerId = "current-promotion")
    private val free = PlusStoreState(PlusStatus.FREE, discountedLifetimeOffer = discount, currentEntitlementsVerified = true)

    @Test fun unopenedInvitationDoesNotStartClock() {
        val offer = LifetimeOffer(LifetimeOfferSource.UPDATE_321, now).observe(now + 1_000_000)
        assertNull(offer.claimedAtMs)
        assertNull(offer.expiresAtMs)
        assertFalse(offer.isActive(now + 1_000_000))
    }

    @Test fun updateGiftLastsAWeekFromOpeningAndCannotRestartAfterExpiryOrRollback() {
        val wrapped = LifetimeOffer.updateGift(null, now)
        assertEquals(LifetimeOfferSource.UPDATE_323, wrapped.source)
        assertNull(wrapped.expiresAtMs)
        val opened = wrapped.claim(now + 1_000)
        val deadline = now + 1_000 + LifetimeOffer.UPDATE_DURATION_MS
        assertEquals(deadline, opened.expiresAtMs)
        assertTrue(opened.isActive(deadline - 1))
        assertTrue(LifetimeOfferPolicy.canPurchase(free, opened, discount, now + 2 * LifetimeOffer.DURATION_MS))
        assertFalse(opened.isActive(deadline))
        val expired = opened.observe(deadline)
        assertEquals(expired, LifetimeOffer.updateGift(expired, deadline + 1))
        assertEquals(expired, LifetimeOffer.updateGift(expired, now - 1))
        assertFalse(expired.claim(now).isActive(now))
        assertEquals(deadline, expired.expiresAtMs)
        assertFalse(LifetimeOfferPolicy.canPurchase(free, expired, discount, now))
    }

    @Test fun updateGiftReplacesUnopenedOrExpiredLegacyOffersButKeepsActiveDeadlines() {
        for (source in listOf(LifetimeOfferSource.ONBOARDING, LifetimeOfferSource.UPDATE_321)) {
            val old = LifetimeOffer(source, now)
            val unopened = LifetimeOffer.updateGift(old, now + 100)
            assertEquals(LifetimeOfferSource.UPDATE_323, unopened.source)
            assertNull(unopened.claimedAtMs)
            val running = old.claim(now)
            assertEquals(running, LifetimeOffer.updateGift(running, now + 100))
            assertEquals(now + LifetimeOffer.DURATION_MS, running.expiresAtMs)
            val ended = running.observe(now + LifetimeOffer.DURATION_MS)
            val newGift = LifetimeOffer.updateGift(ended, now - 100)
            assertEquals(LifetimeOfferSource.UPDATE_323, newGift.source)
            assertEquals(ended.latestObservedAtMs, newGift.latestObservedAtMs)
            assertNull(newGift.claimedAtMs)
        }
    }

    @Test fun storedTimestampValidationUsesSourceDurationAndRejectsOverflowOrInvalidOrdering() {
        val lastValid = Long.MAX_VALUE - LifetimeOffer.UPDATE_DURATION_MS
        assertTrue(LifetimeOffer(LifetimeOfferSource.UPDATE_323, lastValid, lastValid).hasValidTimestamps())
        assertFalse(LifetimeOffer(LifetimeOfferSource.UPDATE_323, lastValid + 1, lastValid + 1).hasValidTimestamps())
        assertTrue(LifetimeOffer(LifetimeOfferSource.UPDATE_321, lastValid + 1, lastValid + 1).hasValidTimestamps())
        assertFalse(LifetimeOffer(LifetimeOfferSource.UPDATE_323, -1).hasValidTimestamps())
        assertFalse(LifetimeOffer(LifetimeOfferSource.UPDATE_323, now, -1).hasValidTimestamps())
        assertFalse(LifetimeOffer(LifetimeOfferSource.UPDATE_323, now, now + 1).hasValidTimestamps())
    }

    @Test fun pricedRevealStartsExactly24HoursAndNeverRestarts() {
        val first = LifetimeOffer(LifetimeOfferSource.ONBOARDING, now).claim(now)
        val reopened = first.claim(now + 120_000)
        assertEquals(now + LifetimeOffer.DURATION_MS, reopened.expiresAtMs)
        assertTrue(reopened.isActive(now + LifetimeOffer.DURATION_MS - 1))
        assertFalse(reopened.isActive(now + LifetimeOffer.DURATION_MS))
        assertEquals(0L, reopened.remainingMs(now + LifetimeOffer.DURATION_MS))
        assertEquals(LifetimeOfferSource.ONBOARDING, reopened.source)
    }

    @Test fun returningClockCannotAddTimeOrReviveExpiredOffer() {
        val active = LifetimeOffer(LifetimeOfferSource.UPDATE_321, now).claim(now).observe(now + 60_000)
        assertEquals(LifetimeOffer.DURATION_MS - 60_000, active.remainingMs(now))
        val expired = active.observe(now + LifetimeOffer.DURATION_MS)
        val reloaded = expired.copy()
        assertFalse(reloaded.isActive(now))
        assertFalse(reloaded.claim(now).isActive(now))
        assertEquals(now + LifetimeOffer.DURATION_MS, reloaded.expiresAtMs)
    }

    @Test fun revealAfterClockRollbackBeginsAtMaximumObservedTime() {
        val invitation = LifetimeOffer(LifetimeOfferSource.UPDATE_321, now).observe(now + 5_000)
        val claimed = invitation.claim(now - 5_000)
        assertEquals(now + 5_000, claimed.claimedAtMs)
        assertTrue(claimed.isActive(now - 5_000))
        assertEquals(LifetimeOffer.DURATION_MS, claimed.remainingMs(now - 5_000))
    }

    @Test fun onlyCurrentlyVerifiedFreeUsersWithoutSubscriptionCanSeePrice() {
        assertTrue(LifetimeOfferPolicy.canOffer(free, now))
        PlusStatus.entries.filter { it != PlusStatus.FREE }.forEach { status ->
            assertFalse(status.name, LifetimeOfferPolicy.canOffer(free.copy(status = status), now))
        }
        assertFalse(LifetimeOfferPolicy.canOffer(free.copy(currentEntitlementsVerified = false), now))
        assertFalse(LifetimeOfferPolicy.canOffer(free.copy(hasActiveSubscription = true), now))
        assertFalse(LifetimeOfferPolicy.canOffer(free.copy(busy = true), now))
        assertFalse(LifetimeOfferPolicy.canOffer(free.copy(operationFailed = true), now))
        assertFalse(LifetimeOfferPolicy.canOffer(free.copy(discountedLifetimeOffer = null), now))
    }

    @Test fun verifiedFreeInvitationSurvivesDelayedOrUnavailableProductQuery() {
        val unavailable = free.copy(discountedLifetimeOffer = null, operationFailed = true)
        assertTrue(LifetimeOfferPolicy.canInvite(unavailable))
        assertFalse(LifetimeOfferPolicy.canOffer(unavailable, now))
        assertTrue(LifetimeOfferPolicy.canInvite(unavailable.copy(busy = true)))
        assertFalse(LifetimeOfferPolicy.canInvite(unavailable.copy(currentEntitlementsVerified = false)))
        assertFalse(LifetimeOfferPolicy.canInvite(unavailable.copy(hasActiveSubscription = true)))
        PlusStatus.entries.filter { it != PlusStatus.FREE }.forEach { status ->
            assertFalse(LifetimeOfferPolicy.canInvite(unavailable.copy(status = status)))
        }
    }

    @Test fun noUnavailableOrGuessedPriceCanQualify() {
        listOf(discount.copy(priceMicros = 0), discount.copy(priceMicros = 100_000_000),
            discount.copy(priceMicros = 101_000_000), discount.copy(regularPriceMicros = 0),
            discount.copy(regularPrice = null), discount.copy(price = ""), discount.copy(currency = ""),
            discount.copy(offerId = null), discount.copy(offerToken = ""), discount.copy(purchaseOptionId = null),
            discount.copy(validFromMs = now + 1), discount.copy(validUntilMs = now),
        ).forEach { assertFalse(it.toString(), LifetimeOfferPolicy.canOffer(free.copy(discountedLifetimeOffer = it), now)) }
    }

    @Test fun localizedSavingsUseRealRatioAndChineseDiscountUnits() {
        assertEquals("25", savingsLabel(discount, Locale.ENGLISH))
        assertEquals("7.5", savingsLabel(discount, Locale.SIMPLIFIED_CHINESE))
        assertEquals("7.5", savingsLabel(discount, Locale.TRADITIONAL_CHINESE))
        val thirtyPercent = discount.copy(priceMicros = 70_000_000)
        assertEquals("30", savingsLabel(thirtyPercent, Locale.ENGLISH))
        assertEquals("7", savingsLabel(thirtyPercent, Locale.SIMPLIFIED_CHINESE))
        assertNull(savingsLabel(discount.copy(priceMicros = 100_000_000), Locale.ENGLISH))
    }

    @Test fun expiryOrChangedPlayTermsDuringFreshQueryMustPreventPurchase() {
        val claimed = LifetimeOffer(LifetimeOfferSource.ONBOARDING, now).claim(now)
        assertTrue(LifetimeOfferPolicy.canPurchase(free.copy(busy = true), claimed, discount, now + 1))
        assertFalse(LifetimeOfferPolicy.canPurchase(free, claimed, discount, now + LifetimeOffer.DURATION_MS))
        assertFalse(LifetimeOfferPolicy.canPurchase(free, null, discount, now))
        assertFalse(LifetimeOfferPolicy.canPurchase(free, claimed.copy(claimedAtMs = null), discount, now))
        assertFalse(LifetimeOfferPolicy.canPurchase(free.copy(discountedLifetimeOffer = null), claimed, discount, now))
        assertFalse(LifetimeOfferPolicy.canPurchase(free.copy(currentEntitlementsVerified = false), claimed, discount, now))
        assertFalse(LifetimeOfferPolicy.canPurchase(free.copy(hasActiveSubscription = true), claimed, discount, now))
        val changed = discount.copy(price = "€80.00", priceMicros = 80_000_000)
        assertFalse(LifetimeOfferPolicy.canPurchase(free.copy(discountedLifetimeOffer = changed), claimed, discount, now))
        // Newly displayed terms may be bought only by another explicit tap with that offer.
        assertTrue(LifetimeOfferPolicy.canPurchase(free.copy(discountedLifetimeOffer = changed), claimed, changed, now))
        val expiredWhileQuerying = discount.copy(validUntilMs = now + 1)
        assertFalse(LifetimeOfferPolicy.canPurchase(free.copy(discountedLifetimeOffer = expiredWhileQuerying), claimed, expiredWhileQuerying, now + 1))
    }
}
