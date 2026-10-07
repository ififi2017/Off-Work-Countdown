package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.schedule.LeavePortion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS LeavePlanGroupTests: display grouping must not replace original proposals. */
class LeavePlanGroupTest {
    private fun proposal(role: LeavePlanItem.Role, first: Int = 100, holiday: Boolean = false) = LeavePlanProposal(
        first, first + 6, "", "",
        listOf(LeavePlanItem(if (role == LeavePlanItem.Role.EARLY_DEPARTURE) first - 1 else first + 7,
            "", LeavePortion.SECOND_HALF, emptyList(), emptyList(), role)),
        emptyList(), null, null,
        List(7) { if (holiday) LeavePlanProposal.DayKind.HOLIDAY else LeavePlanProposal.DayKind.REST }, emptySet(),
    )

    @Test fun `early departure and late return are distinct patterns`() {
        val groups = LeavePlanGroup.make(listOf(
            proposal(LeavePlanItem.Role.EARLY_DEPARTURE), proposal(LeavePlanItem.Role.LATE_RETURN),
            proposal(LeavePlanItem.Role.EARLY_DEPARTURE), proposal(LeavePlanItem.Role.BRIDGE),
        ))
        assertEquals(listOf(listOf(0, 2), listOf(1), listOf(3)), groups.map { it.proposalIndices })
        assertTrue(LeavePlanGroup.make(emptyList()).isEmpty())
    }

    @Test fun `holiday options stay independent and regular dates sort chronologically`() {
        val groups = LeavePlanGroup.make(listOf(
            proposal(LeavePlanItem.Role.BRIDGE, first = 120), proposal(LeavePlanItem.Role.BRIDGE, holiday = true),
            proposal(LeavePlanItem.Role.BRIDGE, first = 90), proposal(LeavePlanItem.Role.BRIDGE, holiday = true),
        ))
        assertEquals(listOf(listOf(2, 0), listOf(1), listOf(3)), groups.map { it.proposalIndices })
        assertEquals(listOf(0, 1, 3), groups.map { it.id })
        assertEquals(listOf(LeavePlanGroup.Category.REGULAR, LeavePlanGroup.Category.HOLIDAY, LeavePlanGroup.Category.HOLIDAY), groups.map { it.category })
    }
}
