package com.rainif.doneat.ui.leave

import com.rainif.doneat.core.domain.leave.LeaveAdoption
import com.rainif.doneat.core.domain.leave.LeavePlanning
import com.rainif.doneat.core.domain.records.RecordState

/** Ephemeral submitted inputs, including the budgets from the exact archive the search used. */
internal data class LeaveQuerySnapshot(val request: LeavePlanning.Request, val availableHalfDays: Int) {
    companion object {
        fun capture(request: LeavePlanning.Request, state: RecordState): LeaveQuerySnapshot = LeaveQuerySnapshot(
            request.copy(budgetIDs = request.budgetIDs.toSet()),
            LeaveAdoption.budgets(state.leaveBalances, state.leaveDays)
                .filter { it.id in request.budgetIDs && it.availableHalfDays > 0 }.sumOf { it.availableHalfDays },
        )
    }
}

/** An adjustment cannot replace an opened set with no results; the first search may show its empty page. */
internal fun shouldPublishLeaveResults(existingHasResults: Boolean, incomingHasResults: Boolean, adjusting: Boolean): Boolean =
    incomingHasResults || (!existingHasResults && !adjusting)
