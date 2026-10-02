package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.RulesSource
import com.rainif.doneat.core.domain.session.ShiftSession

/**
 * What the leave pages read (iOS `ShiftSessionStore+Leave`): the schedule the
 * planner searches and the request it answers. Pure, so the screen only
 * collects the inputs and runs [find] off the main thread.
 */
object LeavePlanning {
    data class Request(
        val goal: LeavePlanner.Goal,
        val fromDayNumber: Int,
        val throughDayNumber: Int,
        val budgetIDs: Set<String>,
    )

    /**
     * Proposals for [request] over the schedule the countdown follows, with
     * the leave already adopted laid over it, so planned days are never
     * planned twice. A year of days takes tens of milliseconds.
     */
    fun find(session: ShiftSession, state: RecordState, request: Request, nowMs: Double, holidays: HolidayCalendar): List<LeavePlanProposal> {
        // The base settings, not today's kept ones; the rules input carries adopted leave.
        val hours = session.rulesInput(nowMs, source = RulesSource.BASE).hours
        val budgets = LeaveAdoption.budgets(state.leaveBalances, state.leaveDays)
            .filter { it.id in request.budgetIDs && it.availableHalfDays > 0 }
        val range = request.fromDayNumber..request.throughDayNumber
        val days = LeavePlannerSchedule.days(hours, range, session.recordsZone, holidays)
        return LeavePlanner.proposals(
            days,
            LeavePlanner.Query(request.goal, request.fromDayNumber, request.throughDayNumber, nowMs, budgets),
        )
    }

    /**
     * Years inside [range] whose mainland China holidays this build does not
     * carry yet, when the schedule follows that calendar. Those years are
     * planned on the ordinary schedule and the page says so.
     */
    fun missingMainlandHolidayYears(session: ShiftSession, range: IntRange, holidays: HolidayCalendar): List<Int> {
        val schedule = session.env.extendedSchedule
        if (!session.env.isExtendedScheduleEnabled || schedule?.content?.holidayRegionIdentifier != "CN") return emptyList()
        val first = CivilZone.civilDate(range.first).first
        val last = CivilZone.civilDate(range.last).first
        return (first..last).filter { !holidays.covers(it, "CN") }
    }
}
