package com.rainif.doneat.plus

import com.rainif.doneat.R
import com.rainif.doneat.ui.PlusPendingAction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlusPresentation322Test {
    private fun offer(plan: PlusPlan, trial: Boolean = false) =
        PlusOffer(plan, "€29.99", "play-token", sevenDayTrial = trial)

    @Test fun timelineRequiresTheSelectedEligibleAnnualOffer() {
        assertTrue(showsPlusTrialTimeline(offer(PlusPlan.YEARLY, trial = true)))
        assertFalse(showsPlusTrialTimeline(offer(PlusPlan.YEARLY)))
        assertFalse(showsPlusTrialTimeline(offer(PlusPlan.MONTHLY, trial = true)))
        assertFalse(showsPlusTrialTimeline(offer(PlusPlan.LIFETIME, trial = true)))
    }

    @Test fun aMissingSelectionFallsBackToAnAvailableAnnualPlanThenARealOffer() {
        val monthly = offer(PlusPlan.MONTHLY)
        val annual = offer(PlusPlan.YEARLY, trial = true)
        val lifetime = offer(PlusPlan.LIFETIME)
        assertEquals(annual, selectVisiblePlusOffer(listOf(monthly, annual), PlusPlan.LIFETIME))
        assertEquals(monthly, selectVisiblePlusOffer(listOf(monthly), PlusPlan.YEARLY))
        assertEquals(lifetime, selectVisiblePlusOffer(listOf(monthly, annual, lifetime), PlusPlan.LIFETIME))
        assertNull(selectVisiblePlusOffer(emptyList(), PlusPlan.YEARLY))
    }

    @Test fun aRefreshedPlayOfferSuppliesTheTimelinePriceAndEligibility() {
        val displayed = offer(PlusPlan.YEARLY, trial = true)
        val updated = displayed.copy(price = "€39.99", sevenDayTrial = false, offerToken = "base-plan")
        val selected = selectVisiblePlusOffer(listOf(updated), displayed.plan)!!
        assertEquals("€39.99", selected.price)
        assertFalse(showsPlusTrialTimeline(selected))
    }

    @Test fun theTitleKeepsTheContextThatOpenedThePaywall() {
        assertEquals(R.string.plusFocusLocked, plusPaywallTitle(PlusPendingAction.FocusHome))
        assertEquals(R.string.plusFocusLocked, plusPaywallTitle(PlusPendingAction.FocusCreate(null, false)))
        assertEquals(R.string.plusEditLocked, plusPaywallTitle(PlusPendingAction.RecordsDay("2026-10-16")))
        assertEquals(R.string.plusLifeLocked, plusPaywallTitle(PlusPendingAction.RecordsLifeEdit))
        assertEquals(R.string.plusChartsLocked, plusPaywallTitle(PlusPendingAction.RecordsCharts))
        assertEquals(R.string.plusReportsLocked, plusPaywallTitle(PlusPendingAction.CycleSummary))
        assertEquals(R.string.plusShiftAlarmsLocked, plusPaywallTitle(PlusPendingAction.ShiftAlarms))
        assertEquals(R.string.plusLeaveLocked, plusPaywallTitle(PlusPendingAction.LeavePlan(0)))
        assertEquals(R.string.onboardingPlusShowcaseTitle, plusPaywallTitle(null))
    }
}
