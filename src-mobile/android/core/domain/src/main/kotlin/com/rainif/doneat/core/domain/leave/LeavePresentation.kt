package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.schedule.LeavePortion
import java.time.DayOfWeek

/** 3.2.2 display projections of an already resolved proposal; never searches or edits a schedule. */
object LeavePresentation {
    enum class DayKind { LEAVE, HALF_LEAVE, HOLIDAY, REST, WORK }

    fun kind(proposal: LeavePlanProposal, day: Int): DayKind {
        proposal.items.firstOrNull { it.dayNumber == day }?.let {
            return if (it.portion == LeavePortion.WHOLE) DayKind.LEAVE else DayKind.HALF_LEAVE
        }
        return when (proposal.dayKinds.getOrNull(day - proposal.firstRestDayNumber)) {
            LeavePlanProposal.DayKind.LEAVE -> DayKind.LEAVE
            LeavePlanProposal.DayKind.HOLIDAY -> DayKind.HOLIDAY
            LeavePlanProposal.DayKind.REST -> DayKind.REST
            null -> DayKind.WORK
        }
    }

    /** The bounding shifts count as one cell each, including early/late half-day requests. */
    fun strip(proposal: LeavePlanProposal): List<DayKind> {
        fun edge(item: LeavePlanItem?): DayKind = when (item?.portion) {
            null -> DayKind.WORK
            LeavePortion.WHOLE -> DayKind.LEAVE
            else -> DayKind.HALF_LEAVE
        }
        val before = proposal.items.firstOrNull { it.dayNumber < proposal.firstRestDayNumber }
        val after = proposal.items.lastOrNull { it.dayNumber > proposal.lastRestDayNumber }
        return listOf(edge(before)) +
            (proposal.firstRestDayNumber..proposal.lastRestDayNumber).map { kind(proposal, it) } + edge(after)
    }

    data class Week(val days: List<Int>, val breakColumns: IntRange?)
    data class Calendar(val weeks: List<Week>, val labelWeek: Int?)

    fun calendar(proposal: LeavePlanProposal, firstWeekday: DayOfWeek): Calendar {
        val coverage = LeavePlanCalendarPage.coverage(proposal)
        val first = coverage.first - 1
        val last = coverage.last + 1
        val lead = Math.floorMod(LeavePlannerSchedule.date(first).dayOfWeek.value - firstWeekday.value, 7)
        val weeks = (first - lead..last).step(7).map { start ->
            val days = (start until start + 7).toList()
            val inside = days.indices.filter { days[it] in proposal.firstRestDayNumber..proposal.lastRestDayNumber }
            Week(days, inside.firstOrNull()?.let { it..inside.last() })
        }
        // maxByOrNull keeps the first widest week, matching iOS even for a Sunday start.
        val label = weeks.indices.maxByOrNull { weeks[it].breakColumns?.count() ?: 0 }
            ?.takeIf { weeks[it].breakColumns != null }
        return Calendar(weeks, label)
    }

    fun sortedGroups(groups: List<LeavePlanGroup>, proposals: List<LeavePlanProposal>, selection: (LeavePlanGroup) -> Int): List<LeavePlanGroup> =
        groups.sortedWith(compareBy<LeavePlanGroup> { proposals[selection(it)].costHalfDays }
            .thenBy { proposals[selection(it)].firstRestDayNumber }.thenBy { it.id })

    data class BalanceBar(val used: Int, val planned: Int, val left: Int) {
        val total: Int get() = used + planned + left
    }

    fun balanceBar(totalHalfDays: Int, usedHalfDays: Int, availableHalfDays: Int): BalanceBar {
        val total = totalHalfDays.coerceAtLeast(0)
        val used = usedHalfDays.coerceIn(0, total)
        val left = availableHalfDays.coerceIn(0, total - used)
        return BalanceBar(used, total - used - left, left)
    }
}
