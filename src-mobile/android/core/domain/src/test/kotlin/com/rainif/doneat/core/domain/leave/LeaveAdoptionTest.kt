package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.records.LeaveBalance
import com.rainif.doneat.core.domain.records.LeaveBalanceUse
import com.rainif.doneat.core.domain.records.LeaveDay
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.portionsByDay
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleDayHours
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.LeavePortion
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.util.UUID

/**
 * One-to-one with the pure parts of iOS `LeaveAdoptionTests`. The iOS actions
 * (`RecordsActions.adoptLeavePlan` etc.) are the pure archive writes here.
 */
class LeaveAdoptionTest {
    private companion object {
        val annual = "00000000-0000-0000-0000-00000000C001"
        val inLieu = "00000000-0000-0000-0000-00000000C002"
        const val ZONE = "UTC"

        fun ms(key: String, hour: Int): Double {
            val (y, m, d) = key.split("-").map { it.toInt() }
            return LocalDateTime.of(y, m, d, hour, 0).toInstant(ZoneOffset.UTC).toEpochMilli().toDouble()
        }

        fun balance(id: String = annual, entitled: Int = 20, through: String? = null) =
            LeaveBalance(id, "annual", null, entitled, 0, null, through, 0.0, 0, "")

        fun item(dayKey: String, portion: LeavePortion = LeavePortion.WHOLE, uses: List<LeaveBalanceUse>? = null) = LeavePlanItem(
            dayNumber = ExtendedScheduleResolver.dayNumber(dayKey)!!,
            dayKey = dayKey,
            portion = portion,
            segments = listOf(ShiftSegment(ms(dayKey, if (portion == LeavePortion.FIRST_HALF) 9 else 13), ms(dayKey, 18))),
            uses = uses ?: listOf(LeaveBalanceUse(annual, portion.halfDays)),
            role = LeavePlanItem.Role.BRIDGE,
        )

        /** Monday through Wednesday off, bridging two weekends. */
        fun proposal(items: List<LeavePlanItem> = listOf(item("2026-10-19"), item("2026-10-20"), item("2026-10-21", LeavePortion.FIRST_HALF))) =
            LeavePlanProposal(
                firstRestDayNumber = ExtendedScheduleResolver.dayNumber("2026-10-17")!!,
                lastRestDayNumber = ExtendedScheduleResolver.dayNumber("2026-10-20")!!,
                firstRestDayKey = "2026-10-17",
                lastRestDayKey = "2026-10-20",
                items = items,
                uses = if (items.isEmpty()) emptyList() else listOf(LeaveBalanceUse(annual, 5)),
                lastShiftEndAtMs = null,
                nextShiftStartAtMs = null,
                dayKinds = if (items.isEmpty()) emptyList() else listOf(
                    LeavePlanProposal.DayKind.REST, LeavePlanProposal.DayKind.REST,
                    LeavePlanProposal.DayKind.LEAVE, LeavePlanProposal.DayKind.LEAVE,
                ),
                caveats = emptySet(),
            )

        fun rows(
            proposal: LeavePlanProposal,
            now: String = "2026-10-10",
            balances: List<LeaveBalance> = listOf(balance()),
            leaveDays: List<LeaveDay> = emptyList(),
            planID: String = UUID.randomUUID().toString(),
        ) = LeaveAdoption.rows(proposal, planID, ZONE, ms(now, 12), balances, leaveDays)

        fun rejected(outcome: LeaveAdoption.Outcome) = (outcome as LeaveAdoption.Outcome.Rejected).error

        fun leaveDay(dayKey: String, portion: LeavePortion = LeavePortion.WHOLE, uses: List<LeaveBalanceUse> = emptyList(), planID: String? = null) =
            LeaveDay(dayKey, portion.raw, uses, planID, ZONE, 0.0, 0, "00000000-0000-0000-0000-000000000000")
    }

    private var ids = 0
    private fun newId() = "00000000-0000-0000-0000-%012d".format(++ids)

    private fun adopt(state: RecordState, proposal: LeavePlanProposal, now: Double): Pair<RecordState, Result<String>> {
        val planID = newId()
        val outcome = LeaveAdoption.rows(proposal, planID, ZONE, now, state.leaveBalances, state.leaveDays)
        return when (outcome) {
            is LeaveAdoption.Outcome.Adopted -> LeaveAdoption.adopt(state, outcome.rows, now, ::newId) to Result.success(planID)
            is LeaveAdoption.Outcome.Rejected -> state to Result.failure(IllegalStateException(outcome.error.toString()))
        }
    }

    @Test fun `a proposal that still fits becomes one leave day per item under one plan`() {
        val rows = (rows(proposal()) as LeaveAdoption.Outcome.Adopted).rows
        assertEquals(listOf("2026-10-19", "2026-10-20", "2026-10-21"), rows.map { it.dayKey })
        assertEquals(listOf("whole", "whole", "firstHalf"), rows.map { it.portion })
        assertEquals(1, rows.mapNotNull { it.planID }.toSet().size)
        assertTrue(rows.all { it.isValid })
    }

    @Test fun `a proposal that no longer fits is refused whole, with its reason`() {
        val proposal = proposal()
        val otherLeave = leaveDay("2026-10-20")
        assertEquals(LeaveAdoptionError.DayAlreadyOnLeave("2026-10-20"), rejected(rows(proposal, leaveDays = listOf(otherLeave))))
        assertEquals(LeaveAdoptionError.AlreadyStarted("2026-10-19"), rejected(rows(proposal, now = "2026-10-20")))
        assertEquals(LeaveAdoptionError.UnknownBalance(annual), rejected(rows(proposal, balances = emptyList())))
        assertEquals(
            LeaveAdoptionError.BalanceOutsideValidity(annual, "2026-10-21"),
            rejected(rows(proposal, balances = listOf(balance(through = "2026-10-20")))),
        )
        assertEquals(LeaveAdoptionError.InsufficientBalance(annual), rejected(rows(proposal, balances = listOf(balance(entitled = 4)))))
        // Leave adopted elsewhere counts against the same balance.
        val spent = leaveDay("2026-11-02", uses = listOf(LeaveBalanceUse(annual, 2)), planID = UUID.randomUUID().toString())
        assertEquals(
            LeaveAdoptionError.InsufficientBalance(annual),
            rejected(rows(proposal, balances = listOf(balance(entitled = 6)), leaveDays = listOf(spent))),
        )
        assertEquals(LeaveAdoptionError.NothingToAdopt, rejected(rows(proposal(items = emptyList()))))
    }

    @Test fun `adopting writes the days, spends the balance and reaches the live plan, and undo gives it back`() {
        var state = RecordState()
        state = LeaveAdoption.upsertBalance(state, balance(), 1.0, ::newId)
        state = LeaveAdoption.upsertBalance(state, balance(inLieu, entitled = 4), 1.0, ::newId)
        // A day the user took by hand, outside any plan.
        state = LeaveAdoption.adopt(state, listOf(leaveDay("2026-11-02", uses = listOf(LeaveBalanceUse(inLieu, 2)))), 1.0, ::newId)

        val now = ms("2026-10-10", 12)
        val (adopted, planResult) = adopt(state, proposal(), now)
        state = adopted
        val planID = planResult.getOrThrow()
        assertEquals(listOf("2026-10-19", "2026-10-20", "2026-10-21"), state.leaveDays.filter { it.planID == planID }.map { it.dayKey })
        assertEquals(listOf(15, 2), LeaveAdoption.budgets(state.leaveBalances, state.leaveDays).map { it.availableHalfDays })

        val hours = ExtendedScheduleDayHours("09:00", "18:00", "12:00", 60)
        val live = ExtendedSchedulePlan.applying(state.leaveDays.portionsByDay(), null, hours)!!
        assertEquals(
            mapOf(
                "2026-10-19" to LeavePortion.WHOLE, "2026-10-20" to LeavePortion.WHOLE,
                "2026-10-21" to LeavePortion.FIRST_HALF, "2026-11-02" to LeavePortion.WHOLE,
            ),
            live.leaveDays,
        )

        // Adopting the same plan again finds its own days taken.
        val (_, again) = adopt(state, proposal(), now)
        assertTrue(again.isFailure)
        assertEquals(
            LeaveAdoptionError.DayAlreadyOnLeave("2026-10-19"),
            rejected(LeaveAdoption.rows(proposal(), newId(), ZONE, now, state.leaveBalances, state.leaveDays)),
        )

        val before = state.leaveDays.size
        state = LeaveAdoption.undoPlan(state, planID, now)
        assertEquals(3, before - state.leaveDays.size)
        assertEquals(listOf("2026-11-02"), state.leaveDays.map { it.dayKey })
        assertTrue(state.isErased(RecordEntityType.LEAVE_DAY, "2026-10-20"))
        assertEquals(listOf(20, 2), LeaveAdoption.budgets(state.leaveBalances, state.leaveDays).map { it.availableHalfDays })
        assertEquals(
            mapOf("2026-11-02" to LeavePortion.WHOLE),
            ExtendedSchedulePlan.applying(state.leaveDays.portionsByDay(), null, hours)?.leaveDays,
        )

        // The same days can be adopted again, above their tombstones.
        val (restored, second) = adopt(state, proposal(), now)
        assertNotEquals(planID, second.getOrThrow())
        assertFalse(restored.isErased(RecordEntityType.LEAVE_DAY, "2026-10-20"))
    }

    @Test fun `cancelling one day gives back only that day, and the rest of the plan still undoes as one`() {
        var state = LeaveAdoption.upsertBalance(RecordState(), balance(), 1.0, ::newId)
        val now = ms("2026-10-10", 12)
        val (adopted, planResult) = adopt(state, proposal(), now)
        state = adopted
        val planID = planResult.getOrThrow()

        state = LeaveAdoption.cancelDay(state, "2026-10-20", now)
        assertTrue(state.isErased(RecordEntityType.LEAVE_DAY, "2026-10-20"))
        assertEquals(listOf("2026-10-19", "2026-10-21"), state.leaveDays.map { it.dayKey })
        assertTrue(state.leaveDays.all { it.planID == planID })
        assertEquals(listOf(17), LeaveAdoption.budgets(state.leaveBalances, state.leaveDays).map { it.availableHalfDays })
        // Nothing there to cancel any more.
        assertEquals(state, LeaveAdoption.cancelDay(state, "2026-10-20", now))

        val before = state.leaveDays.size
        state = LeaveAdoption.undoPlan(state, planID, now)
        assertEquals(2, before - state.leaveDays.size)
        assertTrue(state.leaveDays.isEmpty())
    }
}
