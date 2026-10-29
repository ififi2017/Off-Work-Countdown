package com.rainif.doneat.plus

import com.android.billingclient.api.ProductDetails.RecurrenceMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayOffersTest {
    private val renewal = PlayPricePhase("P1Y", "€29.99", 29_990_000, "EUR", RecurrenceMode.INFINITE_RECURRING, 0)
    private val free = PlayPricePhase("P7D", "€0.00", 0, "EUR", RecurrenceMode.FINITE_RECURRING, 1)
    private val base = PlaySubscriptionOption("yearly", null, "base-token", listOf(renewal))
    private val trial = PlaySubscriptionOption("yearly", "yearly-trial-7d", "trial-token", listOf(free, renewal))
    private fun yearly(vararg options: PlaySubscriptionOption) =
        selectSubscriptionOffer(PlusPlan.YEARLY, "yearly", "yearly-trial-7d", options.toList())

    @Test fun eligibleTrialUsesItsTokenAndRecurringPriceRegardlessOfOrder() {
        for (options in listOf(arrayOf(base, trial), arrayOf(trial, base))) {
            val selected = yearly(*options)!!
            assertTrue(selected.sevenDayTrial)
            assertEquals("trial-token", selected.offerToken)
            assertEquals("€29.99", selected.price)
        }
        assertTrue(yearly(trial.copy(phases = listOf(free.copy(period = "P1W"), renewal)))!!.sevenDayTrial)
        assertTrue(yearly(trial.copy(phases = listOf(free.copy(recurrence = RecurrenceMode.NON_RECURRING, cycles = 0), renewal)))!!.sevenDayTrial)
    }

    @Test fun ineligibleUserGetsBasePlanWithoutATrialClaim() {
        val selected = yearly(base)!!
        assertFalse(selected.sevenDayTrial)
        assertEquals("base-token", selected.offerToken)
        assertNull(yearly())
    }

    @Test fun unconfiguredAndUnrelatedOffersDoNotIntroduceTrials() {
        assertFalse(selectSubscriptionOffer(PlusPlan.YEARLY, "yearly", "", listOf(trial, base))!!.sevenDayTrial)
        assertEquals("base-token", yearly(trial.copy(offerId = "other-promotion"), base)!!.offerToken)
        assertEquals("base-token", yearly(trial.copy(basePlanId = "other-plan"), base)!!.offerToken)
        assertNull(yearly(trial.copy(offerId = "other-promotion")))
    }

    @Test fun onlySevenFreeDaysFollowedByAnnualRenewalAreAdvertised() {
        val unsupported = listOf(
            trial.copy(phases = listOf(free.copy(period = "P14D"), renewal)),
            trial.copy(phases = listOf(free.copy(priceMicros = 1_000_000), renewal)),
            trial.copy(phases = listOf(free.copy(cycles = 2), renewal)),
            trial.copy(phases = listOf(free.copy(recurrence = RecurrenceMode.INFINITE_RECURRING), renewal)),
            trial.copy(phases = listOf(free.copy(currency = "USD"), renewal)),
            trial.copy(phases = listOf(free, renewal.copy(period = "P1M"))),
            trial.copy(phases = listOf(free, renewal.copy(recurrence = RecurrenceMode.FINITE_RECURRING))),
            trial.copy(phases = listOf(free, renewal.copy(priceMicros = 0))),
            trial.copy(phases = listOf(free, renewal, renewal)),
            trial.copy(phases = emptyList()),
            trial.copy(token = ""),
        )
        unsupported.forEach {
            assertNull(yearly(it))
            assertEquals("base-token", yearly(it, base)!!.offerToken)
        }
    }

    @Test fun ordinaryMonthlyPlanStillUsesPlayPriceAndToken() {
        val monthly = base.copy(basePlanId = "monthly", token = "month-token",
            phases = listOf(renewal.copy(period = "P1M", price = "¥6.00", priceMicros = 6_000_000, currency = "CNY")))
        val selected = selectSubscriptionOffer(PlusPlan.MONTHLY, "monthly", "yearly-trial-7d", listOf(trial, monthly))!!
        assertEquals("month-token", selected.offerToken)
        assertEquals("¥6.00", selected.price)
        assertFalse(selected.sevenDayTrial)
    }

    @Test fun refreshedTermsRequireANewSelection() {
        val displayed = yearly(base, trial)!!
        assertFalse(displayed == yearly(base)) // Eligibility disappeared; cannot silently charge the base price.
        assertFalse(displayed == yearly(trial.copy(phases = listOf(free, renewal.copy(price = "€39.99", priceMicros = 39_990_000)))))
        assertEquals(displayed, yearly(base, trial))
    }
}
