package com.rainif.doneat.core.domain.summary

import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.WallClock
import java.time.ZoneId
import java.util.Locale

/**
 * The figures behind the "Daily pay by month" page (plan 024; iOS `MonthlyDailyPay`).
 *
 * Nothing here is a formula of its own: each month's count and daily pay come
 * from [SummaryRules.scheduledWorkdaysInMonth] and [SummaryRules.dailySalaryInMonth],
 * the same calls the timer's snapshot and the Records summary make, and each
 * calendar day asks [SummaryRules.scheduledWorkdayCount] about itself.
 */
data class MonthlyDailyPay(
    val zone: ZoneId,
    val current: Month,
    /** The days of [current], in order. */
    val days: List<Day>,
    /** Empty cells before day 1 so the grid starts on the first weekday. */
    val leadingBlanks: Int,
    /** The three months after [current]. */
    val upcoming: List<Month>,
    /** The monthly gross [Month.dailyPay] divides: nominal pay plus its bonus share. */
    val monthlyAmount: Double?,
) {
    data class Day(
        /** Day of the month, 1-based. */
        val day: Int,
        val isWorkday: Boolean,
        val isToday: Boolean,
    )

    data class Month(
        /** `YYYY-MM`. */
        val id: String,
        val startMs: Double,
        val workdayCount: Int,
        /** Null when the salary settings give no daily pay. */
        val dailyPay: Double?,
    )

    companion object {
        private fun zoneFor(input: ScheduleRuleInput) = CivilZone(input.zone, input.hours.extended?.let(::ExtendedScheduleResolver))

        /**
         * Scheduled workdays in the civil month containing the input's now, whatever
         * the basis is set to: the count the "by monthly schedule" option offers.
         */
        fun scheduledWorkdaysThisMonth(input: ScheduleRuleInput): Int =
            SummaryRules.scheduledWorkdaysInMonth(input.nowMs, input.workdays, input.schedule, input.hours.extended != null, zoneFor(input))

        /**
         * Null unless the salary is monthly and set to the scheduled-month basis.
         * [firstWeekday] is 0 for Sunday … 6 for Saturday.
         */
        fun make(input: ScheduleRuleInput, salary: SalarySettings, firstWeekday: Int): MonthlyDailyPay? {
            if (!salary.usesScheduledMonthBasis) return null
            val zone = zoneFor(input)
            val usesExtended = input.hours.extended != null
            val nowMs = input.nowMs

            fun month(offset: Int): Month {
                val startMs = zone.monthStartMs(nowMs, offset)
                val start = zone.civil(startMs)
                return Month(
                    id = String.format(Locale.ROOT, "%04d-%02d", start.year, start.month),
                    startMs = startMs,
                    workdayCount = SummaryRules.scheduledWorkdaysInMonth(startMs, input.workdays, input.schedule, usesExtended, zone),
                    dailyPay = SummaryRules.dailySalaryInMonth(salary, startMs, input.workdays, input.schedule, usesExtended, zone),
                )
            }

            val current = month(0)
            val first = zone.civil(current.startMs)
            val next = zone.civil(zone.monthStartMs(nowMs, 1))
            val today = zone.civil(nowMs).dayNumber
            val days = (0 until maxOf(0, next.dayNumber - first.dayNumber)).map { index ->
                val dayNumber = first.dayNumber + index
                val startMs = zone.utcMs(dayNumber, WallClock.MIDNIGHT)
                val endMs = zone.utcMs(dayNumber + 1, WallClock.MIDNIGHT)
                Day(
                    day = index + 1,
                    isWorkday = SummaryRules.scheduledWorkdayCount(startMs, endMs, input.workdays, input.schedule, usesExtended, zone) > 0,
                    isToday = dayNumber == today,
                )
            }
            return MonthlyDailyPay(
                zone = input.zone,
                current = current,
                days = days,
                leadingBlanks = Math.floorMod(first.weekday - firstWeekday, 7),
                upcoming = (1..3).map(::month),
                monthlyAmount = SummaryRules.salaryMonthlyEquivalent(salary),
            )
        }
    }
}
