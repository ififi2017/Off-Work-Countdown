package com.rainif.doneat.ui.leave

import com.rainif.doneat.core.domain.leave.LeavePlanning
import com.rainif.doneat.core.domain.leave.LeavePlanner
import com.rainif.doneat.core.domain.records.LeaveBalance
import com.rainif.doneat.core.domain.records.LeaveBalanceUse
import com.rainif.doneat.core.domain.records.LeaveDay
import com.rainif.doneat.core.domain.records.RecordState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LeaveQuerySnapshotTest {
    @Test fun `submitted budget excludes unselected balances and adopted leave and survives later edits`() {
        val selected = mutableSetOf("annual")
        val query = LeavePlanning.Request(LeavePlanner.Goal.RestAtLeast(13), 100, 465, selected)
        fun balance(id: String, halfDays: Int) = LeaveBalance(id, "annual", null, halfDays, 2, null, null, 0.0, 0, "tie")
        val state = RecordState(
            leaveBalances = listOf(balance("annual", 12), balance("unused", 60)),
            leaveDays = listOf(LeaveDay("2026-10-01", "whole", listOf(LeaveBalanceUse("annual", 2)), "plan", "UTC", 0.0, 0, "tie")),
        )
        val snapshot = LeaveQuerySnapshot.capture(query, state)
        selected.clear()
        val laterState = state.copy(leaveBalances = listOf(balance("annual", 30)))
        assertEquals(8, snapshot.availableHalfDays)
        assertEquals(setOf("annual"), snapshot.request.budgetIDs)
        assertEquals(LeavePlanner.Goal.RestAtLeast(13), snapshot.request.goal)
        assertEquals(100, snapshot.request.fromDayNumber)
        assertEquals(465, snapshot.request.throughDayNumber)
        assertEquals(26, LeaveQuerySnapshot.capture(snapshot.request, laterState).availableHalfDays)
        assertEquals(8, snapshot.availableHalfDays)
    }

    @Test fun `only first empty results may be published while every adjustment retains its old context`() {
        assertTrue(shouldPublishLeaveResults(false, false, false))
        assertFalse(shouldPublishLeaveResults(true, false, false))
        assertFalse(shouldPublishLeaveResults(true, false, true))
        assertFalse(shouldPublishLeaveResults(false, false, true))
        assertTrue(shouldPublishLeaveResults(true, true, true))
    }
}
