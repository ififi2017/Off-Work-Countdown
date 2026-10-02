package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.records.LeaveBalance
import com.rainif.doneat.core.domain.records.LeaveBudget
import com.rainif.doneat.core.domain.records.LeaveDay
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.adoptedHalfDays

/** Why a proposal can no longer be adopted as it stands (plan 020 §2). */
sealed interface LeaveAdoptionError {
    /** The records archive is damaged and blocks writes. */
    data object ArchiveUnavailable : LeaveAdoptionError

    /** The break needs no leave, so there is nothing to write. */
    data object NothingToAdopt : LeaveAdoptionError

    /** Another plan or the user already took leave on this day. */
    data class DayAlreadyOnLeave(val dayKey: String) : LeaveAdoptionError

    /** Time passed since the plan was made and this shift has begun. */
    data class AlreadyStarted(val dayKey: String) : LeaveAdoptionError

    /** The balance was removed or is no longer valid. */
    data class UnknownBalance(val balanceID: String) : LeaveAdoptionError

    /** The balance cannot be spent on this day any more. */
    data class BalanceOutsideValidity(val balanceID: String, val dayKey: String) : LeaveAdoptionError

    /** Other leave or an edit left too little of this balance. */
    data class InsufficientBalance(val balanceID: String) : LeaveAdoptionError
}

/**
 * Turning a proposal into leave days, and the balances left after adopted
 * plans (iOS `LeaveAdoption` and the coordinator's leave writes). Pure, so the
 * planner and adoption read the same figures.
 *
 * A plan is adopted whole or not at all: every check runs before anything is
 * written. Balances are never decremented; what adopted plans spent is the sum
 * of their days, so undoing a plan (erasing its days) gives the half days back.
 * No Plus gate: a free user's trial plans adopt fully, and adopted plans stay
 * manageable after the trial ends.
 */
object LeaveAdoption {
    sealed interface Outcome {
        data class Adopted(val rows: List<LeaveDay>) : Outcome
        data class Rejected(val error: LeaveAdoptionError) : Outcome
    }

    /** What the planner may spend from each valid balance, after the leave already adopted. */
    fun budgets(balances: List<LeaveBalance>, leaveDays: List<LeaveDay>): List<LeaveBudget> {
        val adopted = leaveDays.adoptedHalfDays()
        return balances.mapNotNull { it.budget(adopted[it.id] ?: 0) }
    }

    /** The rows adopting [proposal] under [planID], or the first reason it no longer fits the archive. Unstamped. */
    fun rows(
        proposal: LeavePlanProposal,
        planID: String,
        timeZoneIdentifier: String,
        nowMs: Double,
        balances: List<LeaveBalance>,
        existing: List<LeaveDay>,
    ): Outcome {
        if (proposal.items.isEmpty()) return Outcome.Rejected(LeaveAdoptionError.NothingToAdopt)
        val taken = existing.map { it.dayKey }.toSet()
        val valid = LinkedHashMap<String, LeaveBalance>()
        for (balance in balances) if (balance.isValid && balance.id !in valid) valid[balance.id] = balance
        val spending = LinkedHashMap<String, Int>()
        for (item in proposal.items) {
            if (item.dayKey in taken) return Outcome.Rejected(LeaveAdoptionError.DayAlreadyOnLeave(item.dayKey))
            val freed = item.segments.firstOrNull()
            if (freed == null || freed.startAtMs < nowMs) return Outcome.Rejected(LeaveAdoptionError.AlreadyStarted(item.dayKey))
            for (use in item.uses) {
                val budget = valid[use.balanceID]?.budget() ?: return Outcome.Rejected(LeaveAdoptionError.UnknownBalance(use.balanceID))
                if (!budget.covers(item.dayNumber)) return Outcome.Rejected(LeaveAdoptionError.BalanceOutsideValidity(use.balanceID, item.dayKey))
                spending.merge(use.balanceID, use.halfDays, Int::plus)
            }
        }
        val adopted = existing.adoptedHalfDays()
        for ((id, halfDays) in spending) {
            if ((adopted[id] ?: 0) + halfDays > valid.getValue(id).remainingHalfDays) {
                return Outcome.Rejected(LeaveAdoptionError.InsufficientBalance(id))
            }
        }
        return Outcome.Adopted(
            proposal.items.map { item ->
                LeaveDay(
                    dayKey = item.dayKey,
                    portion = item.portion.raw,
                    uses = item.uses,
                    planID = planID,
                    timeZoneIdentifier = timeZoneIdentifier,
                    editedAtMs = 0.0,
                    editCount = 0,
                    editTieBreaker = ZERO_UUID,
                )
            },
        )
    }

    /** One adopted plan: its id and the days it wrote, by date. */
    data class AdoptedPlan(val id: String, val days: List<LeaveDay>)

    /** Adopted plans, newest first by their first day. */
    fun adoptedPlans(leaveDays: List<LeaveDay>): List<AdoptedPlan> = leaveDays
        .filter { it.planID != null }
        .groupBy { it.planID!! }
        .map { (id, days) -> AdoptedPlan(id, days.sortedBy { it.dayKey }) }
        .sortedByDescending { it.days.firstOrNull()?.dayKey.orEmpty() }

    // Archive writes. Each returns the next archive; the store saves it in one write.

    /** Writes an adopted plan's days, each stamped one above the row or tombstone it replaces. */
    fun adopt(state: RecordState, rows: List<LeaveDay>, nowMs: Double, newId: () -> String): RecordState =
        rows.fold(state) { next, row -> upsertLeaveDay(next, row, nowMs, newId) }

    /** Erases the days a plan wrote. A day the user set separately no longer carries its id and stays. */
    fun undoPlan(state: RecordState, planID: String, nowMs: Double): RecordState =
        state.leaveDays.filter { it.planID == planID }.map { it.dayKey }
            .fold(state) { next, key -> RecordJson.erase(next, RecordEntityType.LEAVE_DAY, key, nowMs) }

    /** Gives back one day of leave, whichever plan wrote it. The rest of the plan keeps its id. */
    fun cancelDay(state: RecordState, dayKey: String, nowMs: Double): RecordState {
        if (state.leaveDays.none { it.dayKey == dayKey }) return state
        return RecordJson.erase(state, RecordEntityType.LEAVE_DAY, dayKey, nowMs)
    }

    /** Saves a balance; identical business content writes nothing. Invalid drafts are refused. */
    fun upsertBalance(state: RecordState, draft: LeaveBalance, nowMs: Double, newId: () -> String): RecordState {
        if (!draft.isValid) return state
        val current = state.leaveBalances.firstOrNull { it.id == draft.id }
        if (!state.isErased(RecordEntityType.LEAVE_BALANCE, draft.id) && current != null && sameContent(current, draft)) return state
        val tombstone = state.erased.firstOrNull { it.entityType == RecordEntityType.LEAVE_BALANCE && it.logicalKey == draft.id }
        val cleared = if (tombstone == null) state else state.copy(erased = state.erased - tombstone)
        var count = (current?.editCount ?: maxOf(draft.editCount, 0)) + 1
        if (tombstone != null && count <= tombstone.editCount) count = tombstone.editCount + 1
        val row = draft.copy(editCount = count, editTieBreaker = newId(), editedAtMs = nowMs)
        val list = if (current != null) cleared.leaveBalances.map { if (it === current) row else it } else cleared.leaveBalances + row
        return cleared.copy(leaveBalances = list)
    }

    /** Whether adopted leave still draws on [balanceID]; such a balance cannot be removed. */
    fun isInUse(state: RecordState, balanceID: String) = state.leaveDays.any { day -> day.uses.any { it.balanceID == balanceID } }

    /** Removes a balance no adopted leave uses. */
    fun deleteBalance(state: RecordState, balanceID: String, nowMs: Double): RecordState {
        if (isInUse(state, balanceID) || state.leaveBalances.none { it.id == balanceID }) return state
        return RecordJson.erase(state, RecordEntityType.LEAVE_BALANCE, balanceID, nowMs)
    }

    private fun upsertLeaveDay(state: RecordState, draft: LeaveDay, nowMs: Double, newId: () -> String): RecordState {
        if (!draft.isValid) return state
        val current = state.leaveDays.firstOrNull { it.dayKey == draft.dayKey }
        if (!state.isErased(RecordEntityType.LEAVE_DAY, draft.dayKey) && current != null && sameContent(current, draft)) return state
        val tombstone = state.erased.firstOrNull { it.entityType == RecordEntityType.LEAVE_DAY && it.logicalKey == draft.dayKey }
        val cleared = if (tombstone == null) state else state.copy(erased = state.erased - tombstone)
        var count = (current?.editCount ?: maxOf(draft.editCount, 0)) + 1
        if (tombstone != null && count <= tombstone.editCount) count = tombstone.editCount + 1
        val row = draft.copy(editCount = count, editTieBreaker = newId(), editedAtMs = nowMs)
        val list = if (current != null) cleared.leaveDays.map { if (it === current) row else it } else cleared.leaveDays + row
        return cleared.copy(leaveDays = list)
    }

    private fun sameContent(a: LeaveBalance, b: LeaveBalance) =
        a.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "") == b.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "")

    private fun sameContent(a: LeaveDay, b: LeaveDay) =
        a.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "") == b.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "")

    private const val ZERO_UUID = "00000000-0000-0000-0000-000000000000"
}
