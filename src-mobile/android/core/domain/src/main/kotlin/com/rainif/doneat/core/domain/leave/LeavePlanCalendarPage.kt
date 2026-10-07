package com.rainif.doneat.core.domain.leave

import java.time.DayOfWeek
import java.time.YearMonth

/** Month geometry only; day kinds come from the planner's resolved schedule. */
class LeavePlanCalendarPage(containing: Int, firstWeekday: DayOfWeek) {
    private val date = LeavePlannerSchedule.date(containing)
    val year = date.year
    val month = date.monthValue
    val firstDayNumber = LeavePlannerSchedule.dayNumber(date.withDayOfMonth(1))
    private val leading = Math.floorMod(date.withDayOfMonth(1).dayOfWeek.value - firstWeekday.value, 7)
    /** Six stable rows keep the controls still when paging between months. */
    val days = (firstDayNumber - leading until firstDayNumber - leading + 42).toList()

    fun contains(day: Int): Boolean = LeavePlannerSchedule.date(day).let { it.year == year && it.monthValue == month }

    companion object {
        fun coverage(proposal: LeavePlanProposal): IntRange =
            minOf(proposal.firstRestDayNumber, proposal.items.minOfOrNull { it.dayNumber } ?: proposal.firstRestDayNumber)..
                maxOf(proposal.lastRestDayNumber, proposal.items.maxOfOrNull { it.dayNumber } ?: proposal.lastRestDayNumber)

        fun months(proposal: LeavePlanProposal): List<Int> {
            val range = coverage(proposal)
            val first = YearMonth.from(LeavePlannerSchedule.date(range.first))
            val last = YearMonth.from(LeavePlannerSchedule.date(range.last))
            return generateSequence(first) { it.plusMonths(1) }.takeWhile { it <= last }
                .map { LeavePlannerSchedule.dayNumber(it.atDay(1)) }.toList()
        }
    }
}
