package com.rainif.doneat.core.domain.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `OvertimeStartTests.sheetPlan` and `durationChoices`, restated for the Kotlin port. */
class OvertimeSheetPlanTest {
    private val planned = 1_000_000_000.0
    private val minute = 60_000.0

    @Test fun startsOvertimeAfterTheRestAndCountsFromThere() {
        var plan = OvertimeSheetPlan(plannedEndMs = planned, nowMs = planned - 60 * minute, untilMs = planned + 60 * minute)
        assertNull(plan.overtimeStartMs)
        assertEquals(planned, plan.startMs, 0.0)
        assertEquals(3_600_000.0, plan.countedMs, 0.0)
        assertTrue(plan.isValid)

        plan = plan.copy(restMinutes = 30)
        assertEquals(planned + 30 * minute, plan.overtimeStartMs!!, 0.0)
        assertEquals(1_800_000.0, plan.countedMs, 0.0)

        // Switching to a duration keeps the end; the end follows the rest.
        plan = plan.selecting(OvertimeSheetPlan.Entry.DURATION)
        assertEquals(30, plan.durationMinutes)
        assertEquals(planned + 60 * minute, plan.endMs, 0.0)
        plan = plan.copy(durationMinutes = 150, restMinutes = 60)
        assertEquals(planned + 60 * minute + 150 * minute, plan.endMs, 0.0)
        assertEquals(9_000_000.0, plan.countedMs, 0.0)

        // Back to a clock time keeps the end it showed.
        plan = plan.selecting(OvertimeSheetPlan.Entry.UNTIL)
        assertEquals(planned + 210 * minute, plan.untilMs, 0.0)

        // A rest that swallows the whole overtime is not savable until settled.
        var short = OvertimeSheetPlan(plannedEndMs = planned, nowMs = planned - minute, untilMs = planned + 10 * minute)
        short = short.copy(restMinutes = 15)
        assertFalse(short.isValid)
        assertTrue(short.settled().isValid)
    }

    @Test fun offersDurationsThatStillEndNowOrLater() {
        val retrospective = OvertimeSheetPlan(plannedEndMs = planned, nowMs = planned + 50 * minute, untilMs = planned)
        assertEquals(60, retrospective.durationChoices.first())
        assertEquals(720, retrospective.durationChoices.last())
        val early = OvertimeSheetPlan(plannedEndMs = planned, nowMs = planned - 10 * minute, untilMs = planned)
        assertEquals(15, early.durationChoices.first())
        assertEquals(30, OvertimeRestChoices.nearest(28.0))
        assertEquals(0, OvertimeRestChoices.nearest(0.0))
    }

    @Test fun payChoicesStepInTenths() {
        assertTrue(OvertimePayChoices.isPreset(1.5))
        assertFalse(OvertimePayChoices.isPreset(1.2))
        assertEquals(12, OvertimePayChoices.tenths(1.2))
        assertEquals(1.2, OvertimePayChoices.multiplier(12), 0.0)
    }
}
