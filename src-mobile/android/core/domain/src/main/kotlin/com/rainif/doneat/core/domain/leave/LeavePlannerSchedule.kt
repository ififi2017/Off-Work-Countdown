package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleDay
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.WallClock
import java.time.LocalDate
import java.time.ZoneId

/**
 * Feeds [LeavePlanner] from the schedule the rest of the app already uses,
 * and owns the rolling planning year (iOS `LeavePlannerSchedule`, plan 020 §2).
 *
 * Days come from `ScheduleRules.expandScheduleRange`, so the planner sees the
 * same shifts as the countdown, reminders and widget: the cycle rule, days set
 * by hand, bundled holidays and makeup workdays. No second schedule or holiday
 * algorithm lives here; this only labels where each day came from.
 */
object LeavePlannerSchedule {
    /** Days resolved either side of a search range, for the overnight shift running into its first day and the shifts that bound a break. */
    const val CONTEXT_DAYS = 31

    /**
     * Today through the day before the same date a calendar year later: the
     * half-open "today to today plus one year" window. 2026-09-27 gives
     * 2026-09-27…2027-09-26; 2028-02-29 ends on 2029-02-27, since a calendar
     * year from it lands on 2029-02-28.
     */
    fun rollingYear(today: LocalDate): IntRange? {
        val first = dayNumber(today)
        val limit = dayNumber(today.plusYears(1))
        return if (limit > first) first..(limit - 1) else null
    }

    fun dayNumber(date: LocalDate) = CivilZone.dayNumber(date.year, date.monthValue, date.dayOfMonth)

    fun date(dayNumber: Int): LocalDate = CivilZone.civilDate(dayNumber).let { (y, m, d) -> LocalDate.of(y, m, d) }

    /**
     * [range] plus [CONTEXT_DAYS] either side, resolved under [hours]. Attach
     * the live extended schedule first: without it the days follow the fixed
     * hours alone.
     */
    fun days(
        hours: ScheduleHours,
        range: IntRange,
        zoneId: ZoneId,
        holidayEstimated: (year: Int, region: String) -> Boolean = { _, _ -> false },
        holidayCoverage: (year: Int, region: String) -> Boolean,
    ): List<LeavePlannerDay> {
        val zone = CivilZone(zoneId)
        val firstDay = range.first - CONTEXT_DAYS
        val lastDay = range.last + CONTEXT_DAYS
        fun noon(dayNumber: Int) = zone.utcMs(dayNumber, WallClock.NOON)
        val expanded = ScheduleRules.expandScheduleRange(hours, noon(firstDay), noon(lastDay), zoneId)
        if (expanded.size != lastDay - firstDay + 1) return emptyList()

        val plan = hours.extended
        val resolver = plan?.let(::ExtendedScheduleResolver)
        val region = plan?.takeUnless { it.fallsBackToBaseSchedule }?.holidayRegionIdentifier?.takeIf { it.isNotEmpty() }

        return expanded.mapIndexed { offset, expansion ->
            val dayNumber = firstDay + offset
            val source = resolver?.day(dayNumber)?.source
            val caveats = HashSet<LeavePlannerCaveat>()
            when (source) {
                ExtendedScheduleDay.Source.CARRIED_OVER -> caveats += LeavePlannerCaveat.CarriedOverRoster
                // A fallback plan (leave over fixed hours) leaves such a day to the fixed schedule: known, not unassigned.
                ExtendedScheduleDay.Source.UNASSIGNED -> if (plan?.fallsBackToBaseSchedule != true) caveats += LeavePlannerCaveat.Unassigned
                else -> Unit
            }
            if (region != null) {
                val year = CivilZone.civilDate(dayNumber).first
                // Keep the year-level warning even on manually assigned days within a predicted range.
                if (holidayEstimated(year, region)) caveats += LeavePlannerCaveat.HolidaysEstimated(year)
                else if (source != ExtendedScheduleDay.Source.HAND_SET && !holidayCoverage(year, region)) {
                    caveats += LeavePlannerCaveat.HolidaysNotIncluded(year)
                }
            }
            LeavePlannerDay(
                dayNumber = dayNumber,
                dayKey = expansion.dayKey,
                startAtMs = zone.utcMs(dayNumber, WallClock.MIDNIGHT),
                endAtMs = zone.utcMs(dayNumber + 1, WallClock.MIDNIGHT),
                segments = if (expansion.isWorkday) expansion.segments else emptyList(),
                isHoliday = source == ExtendedScheduleDay.Source.HOLIDAY && !expansion.isWorkday,
                caveats = caveats,
            )
        }
    }

    /** [days] covering with [calendar]'s bundled data. */
    fun days(hours: ScheduleHours, range: IntRange, zoneId: ZoneId, calendar: HolidayCalendar) =
        days(hours, range, zoneId, holidayEstimated = calendar::isEstimated, holidayCoverage = calendar::covers)
}
