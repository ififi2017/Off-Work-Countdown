package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.LeavePortion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek

class LeavePresentationTest {
    private fun day(key: String) = ExtendedScheduleResolver.dayNumber(key)!!
    private fun proposal(from: String, through: String, cost: Int = 0): LeavePlanProposal {
        val first = day(from)
        val last = day(through)
        return LeavePlanProposal(first, last, from, through,
            List(cost) { i -> LeavePlanItem(first + i, "", LeavePortion.FIRST_HALF, emptyList(), emptyList(), LeavePlanItem.Role.BRIDGE) },
            emptyList(), null, null, List(last - first + 1) { LeavePlanProposal.DayKind.REST }, emptySet())
    }

    @Test fun `break starting Sunday writes length on the widest week instead of the opening sliver`() {
        val result = LeavePresentation.calendar(proposal("2026-10-04", "2026-10-12"), DayOfWeek.MONDAY)
        assertEquals(1, result.labelWeek)
        assertEquals(1, result.weeks.first().breakColumns!!.count())
        assertEquals(7, result.weeks[1].breakColumns!!.count())
    }

    @Test fun `first widest week wins ties and calendar includes both edge requests across a year`() {
        val base = proposal("2026-12-27", "2027-01-10")
        val option = base.copy(items = listOf(
            LeavePlanItem(day("2026-12-26"), "2026-12-26", LeavePortion.SECOND_HALF, emptyList(), emptyList(), LeavePlanItem.Role.EARLY_DEPARTURE),
            LeavePlanItem(day("2027-01-11"), "2027-01-11", LeavePortion.FIRST_HALF, emptyList(), emptyList(), LeavePlanItem.Role.LATE_RETURN)))
        for (start in DayOfWeek.entries) {
            val result = LeavePresentation.calendar(option, start)
            val dates = result.weeks.flatMap { it.days }
            assertEquals(start, LeavePlannerSchedule.date(dates.first()).dayOfWeek)
            assertTrue(day("2026-12-25") in dates)
            assertTrue(day("2027-01-12") in dates)
            assertEquals(result.weeks.indexOfFirst { it.breakColumns?.count() == 7 }, result.labelWeek)
        }
    }

    @Test fun `strips preserve whole and half leave and ordinary or holiday rest`() {
        val option = proposal("2026-10-03", "2026-10-05").copy(
            items = listOf(LeavePlanItem(day("2026-10-02"), "", LeavePortion.SECOND_HALF, emptyList(), emptyList(), LeavePlanItem.Role.EARLY_DEPARTURE)),
            dayKinds = listOf(LeavePlanProposal.DayKind.HOLIDAY, LeavePlanProposal.DayKind.REST, LeavePlanProposal.DayKind.LEAVE))
        assertEquals(listOf(LeavePresentation.DayKind.HALF_LEAVE, LeavePresentation.DayKind.HOLIDAY,
            LeavePresentation.DayKind.REST, LeavePresentation.DayKind.LEAVE, LeavePresentation.DayKind.WORK), LeavePresentation.strip(option))
    }

    @Test fun `plan list sorts by cost then selected date without changing original recommendation indices`() {
        val proposals = listOf(proposal("2026-10-10", "2026-10-12", 4), proposal("2026-11-10", "2026-11-12", 2), proposal("2026-10-10", "2026-10-12", 2))
        val groups = proposals.indices.map { LeavePlanGroup(it, LeavePlanGroup.Category.HOLIDAY, listOf(it)) }
        assertEquals(listOf(2, 1, 0), LeavePresentation.sortedGroups(groups, proposals) { it.id }.map { it.id })
        assertEquals(listOf(0, 1, 2), groups.map { it.id })
    }

    @Test fun `overdrawn balances never create negative bar sections and planned days remain distinct`() {
        assertEquals(LeavePresentation.BalanceBar(4, 6, 10), LeavePresentation.balanceBar(20, 4, 10))
        assertEquals(LeavePresentation.BalanceBar(10, 0, 0), LeavePresentation.balanceBar(10, 12, 0))
        assertEquals(LeavePresentation.BalanceBar(0, 0, 0), LeavePresentation.balanceBar(0, 4, 8))
    }
}
