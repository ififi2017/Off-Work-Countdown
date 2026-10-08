package com.rainif.doneat.ui.leave

import com.rainif.doneat.core.domain.leave.LeavePlanGroup
import com.rainif.doneat.core.domain.leave.LeavePlanProposal
import com.rainif.doneat.core.domain.leave.LeavePlannerCaveat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LeaveRecommendationFilterTest {
    @Test fun `both result list pages go back to the same preview before leaving the route`() {
        assertEquals(LeaveResultsPage.SUMMARY, leaveResultsBackPage(LeaveResultsPage.ALL_PLANS))
        assertEquals(LeaveResultsPage.SUMMARY, leaveResultsBackPage(LeaveResultsPage.DATES))
        assertNull(leaveResultsBackPage(LeaveResultsPage.SUMMARY))
    }

    @Test fun `full prediction notice belongs to the selected plan rather than the searched years`() {
        fun proposal(caveats: Set<LeavePlannerCaveat>) = LeavePlanProposal(
            100, 112, "", "", emptyList(), emptyList(), null, null,
            List(13) { LeavePlanProposal.DayKind.REST }, caveats,
        )
        assertEquals(emptyList<Int>(), leaveSelectedEstimatedYears(proposal(emptySet())))
        assertEquals(emptyList<Int>(), leaveSelectedEstimatedYears(proposal(setOf(LeavePlannerCaveat.Unassigned))))
        assertEquals(listOf(2027), leaveSelectedEstimatedYears(proposal(setOf(LeavePlannerCaveat.HolidaysEstimated(2027)))))
    }

    @Test fun `recommendations retain the global ranking when a regular break is cheapest`() {
        val groups = listOf(
            LeavePlanGroup(0, LeavePlanGroup.Category.REGULAR, listOf(2, 0)),
            LeavePlanGroup(1, LeavePlanGroup.Category.HOLIDAY, listOf(1)),
            LeavePlanGroup(3, LeavePlanGroup.Category.HOLIDAY, listOf(3)),
            LeavePlanGroup(4, LeavePlanGroup.Category.REGULAR, listOf(4)),
        )
        val recommended = leaveGroupsForFilter(groups, LeaveResultFilter.RECOMMENDED)
        assertEquals(listOf(0, 1, 3, 4), recommended.map { it.id })
        assertEquals(listOf(2, 0), recommended.first().proposalIndices)
        assertEquals(0, leaveGroupSelection(recommended.first(), null))
        assertEquals(2, leaveGroupSelection(recommended.first(), 2))
        assertEquals(0, leaveGroupSelection(recommended.first(), 99))
        assertEquals(listOf(1, 3), leaveGroupsForFilter(groups, LeaveResultFilter.HOLIDAY).map { it.id })
        assertEquals(listOf(0, 4), leaveGroupsForFilter(groups, LeaveResultFilter.REGULAR).map { it.id })
    }
}
