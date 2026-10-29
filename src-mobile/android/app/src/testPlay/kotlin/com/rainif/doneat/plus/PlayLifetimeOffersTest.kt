package com.rainif.doneat.plus

import org.junit.Assert.*
import org.junit.Test

class PlayLifetimeOffersTest {
    private val now = 1_790_000_000_000L
    private val base = PlayLifetimeOption("buy", null, "base-token", "€100.00", 100_000_000, "EUR")
    private val discount = base.copy(offerId = "eligible-promotion", token = "discount-token",
        price = "€75.00", priceMicros = 75_000_000, fullPriceMicros = 100_000_000)
    private fun select(vararg options: PlayLifetimeOption) = selectLifetimeOffers("buy", options.toList(), now)

    @Test fun eligibleSameOptionDiscountIsSeparateFromRegularPlan() {
        val chosen = select(base, discount)
        assertEquals("base-token", chosen.regular!!.offerToken)
        assertNull(chosen.regular.offerId)
        assertEquals("discount-token", chosen.discounted!!.offerToken)
        assertEquals("eligible-promotion", chosen.discounted.offerId)
        assertEquals("€100.00", chosen.discounted.regularPrice)
        assertEquals(100_000_000L, chosen.discounted.regularPriceMicros)
        assertEquals("EUR", chosen.discounted.currency)
    }

    @Test fun lowestEligibleActualDiscountWinsRegardlessOfOrder() {
        val cheaper = discount.copy(offerId = "another-promotion", token = "cheapest", price = "€70.00", priceMicros = 70_000_000)
        val first = select(base, discount, cheaper)
        assertEquals("cheapest", first.discounted!!.offerToken)
        assertEquals(first, select(cheaper, discount, base))
    }

    @Test fun noBaseOrUnconfiguredOptionCannotInventSavings() {
        assertNull(select(discount).discounted)
        assertNull(select(base).discounted)
        assertNull(selectLifetimeOffers("", listOf(base, discount), now).regular)
        assertNull(selectLifetimeOffers("unknown", listOf(base, discount), now).discounted)
    }

    @Test fun everyDiscountMustBePositiveLowerAndInTheBaseCurrency() {
        val unsupported = listOf(
            discount.copy(currency = "USD"), discount.copy(priceMicros = 0),
            discount.copy(priceMicros = 100_000_000), discount.copy(priceMicros = 101_000_000),
            discount.copy(fullPriceMicros = 200_000_000), discount.copy(token = ""),
            discount.copy(price = ""), discount.copy(purchaseOptionId = "rent"), discount.copy(offerId = ""),
            discount.copy(rental = true), discount.copy(preorder = true), discount.copy(remainingQuantity = 0),
        )
        unsupported.forEach { assertNull(it.toString(), select(base, it).discounted) }
        assertNull(select(base.copy(priceMicros = 0), discount).discounted)
    }

    @Test fun playWindowUsesInclusiveStartAndExclusiveEnd() {
        assertNotNull(select(base, discount.copy(validFromMs = now, validUntilMs = now + 1)).discounted)
        assertNull(select(base, discount.copy(validFromMs = now + 1)).discounted)
        assertNull(select(base, discount.copy(validUntilMs = now)).discounted)
        assertNull(select(base, discount.copy(validFromMs = now + 2, validUntilMs = now + 1)).discounted)
        assertNull(select(base, discount.copy(validFromMs = -1)).discounted)
        assertNotNull(select(base, discount.copy(validFromMs = null, validUntilMs = now + 1)).discounted)
        assertNotNull(select(base, discount.copy(validFromMs = now, validUntilMs = null)).discounted)
        assertNull(select(base.copy(validUntilMs = now), discount).discounted)
    }

    @Test fun changingEligibilityTokenOrTermsRequiresAnotherExplicitTap() {
        val displayed = select(base, discount).discounted!!
        assertNotEquals(displayed, select(base).discounted)
        assertNotEquals(displayed, select(base, discount.copy(token = "fresh-token")).discounted)
        assertNotEquals(displayed, select(base, discount.copy(price = "€80.00", priceMicros = 80_000_000)).discounted)
        assertNotEquals(displayed, select(base, discount.copy(validUntilMs = now + 1_000)).discounted)
        assertEquals(displayed, select(discount, base).discounted)
    }
}
