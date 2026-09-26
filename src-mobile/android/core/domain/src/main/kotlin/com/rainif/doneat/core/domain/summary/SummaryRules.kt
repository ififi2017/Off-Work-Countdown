package com.rainif.doneat.core.domain.summary

import com.rainif.doneat.core.domain.salary.SalaryRules
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.WallClock
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min

/**
 * Period summaries, Records income and forecast, the monthly salary equivalent
 * and lifetime income: the Kotlin port of `lib/summary.ts` and the salary
 * helpers in `lib/countdown.ts` (Swift: `SummaryRules`). The TypeScript is the
 * specification; the timer's "This week" row once disagreed with Records
 * because a second formula existed, so every screen calls these.
 *
 * Two pay figures are deliberately different: the timer's live estimate
 * ([summarize], daily rate × progress) and Records' fixed monthly allocation
 * ([recordsActualForecast], a monthly salary spread over calendar days, never
 * reduced for leave).
 */
object SummaryRules {
    enum class Period { WEEK, YEAR }

    data class SummaryInput(
        val period: Period,
        /** Explicit window start, winning over [period]: Records grids follow the locale's first weekday. */
        val periodStartMs: Double? = null,
        val asOfMs: Double,
        val workdays: List<Int>,
        val schedule: WorkSchedule,
        val currentShiftStartMs: Double,
        val currentShiftEndMs: Double,
        val plannedDailyHours: Double,
        /** 0…100. */
        val todayProgress: Double,
        val dailySalary: Double?,
        val todayEffectiveHours: Double,
        val todayPayRatio: Double,
        val zone: ZoneId,
        /** Decides which days count and how long each is, when switched on. */
        val extended: ExtendedSchedulePlan? = null,
    )

    data class PeriodSummary(val days: Double, val hours: Double, val earnings: Double?)

    /**
     * Work from the period start to `asOfMs`, estimated from the schedule. The
     * current shift counts only when it starts on a scheduled day inside the
     * period, by its progress, matching the timer's "earned today".
     */
    fun summarize(input: SummaryInput): PeriodSummary {
        val zone = CivilZone(input.zone, input.extended?.let(::ExtendedScheduleResolver))
        val periodStartMs = input.periodStartMs?.takeIf { it.isFinite() }
            ?: if (input.period == Period.YEAR) zone.yearStartMs(input.asOfMs) else zone.weekStartMs(input.asOfMs)
        val shiftDayMs = zone.startOfCivilDayMs(input.currentShiftStartMs)
        val shiftEndDayMs = zone.startOfCivilDayMs(input.currentShiftEndMs)
        val periodDayMs = zone.startOfCivilDayMs(periodStartMs)
        val asOfDayMs = zone.startOfCivilDayMs(input.asOfMs)
        // A same-day shift keeps counting by progress after it ends; an overnight
        // one still belongs to its start day on its end day. Past that, the
        // snapshot is stale and must not cut later workdays short.
        val coversAsOfDay = shiftDayMs >= periodDayMs && shiftDayMs <= asOfDayMs && shiftEndDayMs >= asOfDayMs
        val (count, extendedHours) = scheduledWorkdays(periodDayMs, if (coversAsOfDay) shiftDayMs else asOfDayMs, input, zone)
        val completed = count.toDouble()
        // `isScheduledWorkday`, not the in-zone helper: manual mode still counts today.
        val todayCounts = coversAsOfDay && zone.isScheduledWorkday(shiftDayMs, input.workdays, input.schedule)
        val todayFraction = if (todayCounts) min(100.0, max(0.0, input.todayProgress)) / 100 else 0.0
        val todayHours = if (todayCounts) input.todayEffectiveHours * todayFraction else 0.0
        val todayPay = if (todayCounts) max(0.0, input.todayPayRatio) else 0.0
        // An extended roster sums each day's own hours; one daily figure cannot describe it.
        val hours = (extendedHours ?: (completed * input.plannedDailyHours)) + todayHours
        return PeriodSummary(completed + todayFraction, hours, earnings(input.dailySalary, completed + todayPay))
    }

    /** Completed scheduled days in `[fromMs, toMs)`, with their hours under an extended schedule. */
    private fun scheduledWorkdays(fromMs: Double, toMs: Double, input: SummaryInput, zone: CivilZone): Pair<Int, Double?> {
        val usesExtended = input.extended != null
        if (!usesExtended && input.schedule.mode == ScheduleMode.OFF) return 0 to null
        var cursor = zone.startOfCivilDayMs(fromMs)
        val end = zone.startOfCivilDayMs(toMs)
        var count = 0
        var hours = 0.0
        while (cursor < end) {
            if (zone.isScheduledWorkdayInZone(cursor, input.workdays, input.schedule)) {
                count++
                if (usesExtended) hours += zone.plannedHours(zone.civil(cursor).dayNumber) ?: 0.0
            }
            cursor = zone.addCivilDaysMs(cursor, 1)
        }
        return count to if (usesExtended) hours else null
    }

    // Salary

    /** Completed scheduled workdays at the daily pay; today's partial shift belongs to the live summary. */
    fun recordsIncome(completedWorkdays: Int, salary: SalarySettings): Double? =
        earnings(SalaryRules.dailySalary(salary), max(0, completedWorkdays).toDouble())

    /** The monthly gross a daily or monthly setting amounts to, used to seed the life profile. */
    fun salaryMonthlyEquivalent(salary: SalarySettings): Double? {
        val days = salary.monthlyWorkingDays
        if (!days.isFinite() || days <= 0 || days > 31) return null
        return SalaryRules.dailySalary(salary)?.let { it * days }?.takeIf { it.isFinite() }
    }

    private fun earnings(dailySalary: Double?, ratio: Double) = dailySalary?.let { max(0.0, ratio) * it }?.takeIf { it.isFinite() }

    // Lifetime income

    enum class Cadence(val raw: String) {
        MONTHLY("monthly"),
        YEARLY("yearly");

        companion object {
            /** Anything but `monthly` is read as yearly, as the TypeScript does. */
            fun fromRaw(raw: String) = if (raw == MONTHLY.raw) MONTHLY else YEARLY
        }
    }

    data class IncomePeriod(val startsOn: String, val endsOn: String?, val salaryAmount: Double, val cadence: Cadence)
    data class CurrentSalary(val salaryAmount: Double, val cadence: Cadence, val startsOn: String?)
    data class IncomeDecline(val startsOn: String, val retirementRatio: Double)
    data class LifetimeInput(
        val periods: List<IncomePeriod>,
        val currentSalary: CurrentSalary?,
        val futureIncomeDecline: IncomeDecline?,
        val asOf: String,
        val retirementOn: String,
    )
    data class LifetimeIncome(val historicalGross: Double, val projectedGross: Double, val totalGross: Double)

    /**
     * Gross lifetime income from the salary intervals the user entered. Gaps
     * contribute nothing; no raise, inflation or missing salary is inferred.
     * Overlapping history is rejected rather than guessed at.
     */
    fun lifetimeIncome(input: LifetimeInput): LifetimeIncome {
        val none = LifetimeIncome(0.0, 0.0, 0.0)
        val asOf = civilDayNumber(input.asOf) ?: return none
        val retirement = civilDayNumber(input.retirementOn) ?: return none

        val periods = input.periods + listOfNotNull(input.currentSalary?.let {
            IncomePeriod(it.startsOn ?: input.asOf, input.retirementOn, it.salaryAmount, it.cadence)
        })
        data class Interval(val period: IncomePeriod, val start: Int, val end: Int, val isCurrentSalary: Boolean)
        val intervals = periods.mapIndexedNotNull { index, period ->
            val explicitEnd = if (!period.endsOn.isNullOrEmpty()) civilDayNumber(period.endsOn) else retirement
            val start = civilDayNumber(period.startsOn)
            if (start == null || explicitEnd == null || !period.salaryAmount.isFinite() || period.salaryAmount <= 0) return@mapIndexedNotNull null
            val end = min(explicitEnd, retirement)
            if (end <= start) return@mapIndexedNotNull null
            Interval(period, start, end, input.currentSalary != null && index == periods.size - 1)
        }.sortedBy { it.start } // stable, as the TypeScript sort

        if ((1 until intervals.size).any { intervals[it].start < intervals[it - 1].end }) return none

        val decline = input.futureIncomeDecline?.let { d ->
            val start = civilDayNumber(d.startsOn)
            if (start != null && d.retirementRatio.isFinite() && d.retirementRatio in 0.0..1.0) start to d.retirementRatio else null
        }
        var historicalGross = 0.0
        var projectedGross = 0.0
        for (interval in intervals) {
            val amount = interval.period.salaryAmount
            val monthlySalary = if (interval.period.cadence == Cadence.MONTHLY) amount else amount / 12
            val totalForPeriod = monthlySalary * civilMonthsBetween(interval.start, interval.end)
            val historicalForPeriod = monthlySalary * civilMonthsBetween(interval.start, min(interval.end, asOf))
            historicalGross += historicalForPeriod
            val projectedStart = max(interval.start, asOf)
            if (!interval.isCurrentSalary || decline == null || projectedStart >= interval.end) {
                projectedGross += totalForPeriod - historicalForPeriod
                continue
            }
            // A future fixed-ratio change only reshapes the forecast; history never moves.
            val anchor = max(projectedStart, decline.first)
            projectedGross += monthlySalary * civilMonthsBetween(projectedStart, min(anchor, interval.end))
            if (anchor < interval.end) {
                projectedGross += monthlySalary * decline.second * civilMonthsBetween(anchor, interval.end)
            }
        }
        return LifetimeIncome(historicalGross, projectedGross, historicalGross + projectedGross)
    }

    /** Each partial calendar month is prorated by that month's own day count. */
    private fun civilMonthsBetween(start: Int, end: Int): Double {
        if (end <= start) return 0.0
        var cursor = start
        var total = 0.0
        while (cursor < end) {
            val (year, month, _) = CivilZone.civilDate(cursor)
            val monthStart = CivilZone.dayNumber(year, month, 1)
            val nextMonth = nextMonthStart(year, month)
            val segmentEnd = min(end, nextMonth)
            total += (segmentEnd - cursor).toDouble() / (nextMonth - monthStart).toDouble()
            cursor = segmentEnd
        }
        return total
    }

    private fun nextMonthStart(year: Int, month: Int) =
        if (month == 12) CivilZone.dayNumber(year + 1, 1, 1) else CivilZone.dayNumber(year, month + 1, 1)

    private val CIVIL_DATE = Regex("([0-9]{4})-([0-9]{2})-([0-9]{2})")

    /**
     * A `YYYY-MM-DD` Gregorian date as a day number, or null for anything
     * `Date.UTC` would not round-trip — including years before 100, which it
     * reads as 19xx.
     */
    fun civilDayNumber(value: String): Int? {
        val match = CIVIL_DATE.matchEntire(value) ?: return null
        val (year, month, day) = match.destructured.toList().map { it.toInt() }
        if (year < 100 || month !in 1..12) return null
        val dayNumber = CivilZone.dayNumber(year, month, day)
        return if (CivilZone.civilDate(dayNumber) == Triple(year, month, day)) dayNumber else null
    }

    // Records actual and forecast

    enum class ActualKind(val raw: String) {
        CORRECTED("corrected"),
        OBSERVED("observed"),
        SCHEDULED("scheduled");

        companion object {
            /** An unknown kind reads as no actual record, so the day stays forecast. */
            fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw }
        }
    }

    data class Observation(val isStart: Boolean, val occurredAtMs: Double)

    data class RecordsDay(
        val actualKind: ActualKind?,
        val resolvedSegments: List<ShiftSegment>,
        val plannedSegments: List<ShiftSegment>,
        val overtimeSegments: List<ShiftSegment>,
        val observations: List<Observation>,
        /** The day owning the running shift: an unmatched start closes at `asOfMs`. */
        val isActiveAnchor: Boolean,
    )

    data class ActualForecastInput(
        val days: List<RecordsDay>,
        val periodDayKeys: List<String>,
        val dailySalary: Double?,
        val asOfMs: Double,
        /** Present for a monthly salary, which Records spreads over calendar days. */
        val salary: SalarySettings? = null,
        val zone: ZoneId,
    )

    data class Part(val days: Double, val hours: Double, val earnings: Double?)
    data class ActualForecast(val actualOvertimeHours: Double, val actual: Part, val forecast: Part, val total: Part)

    /**
     * Recorded or corrected work against schedule estimates for one visible
     * period. A day enters only one side, and actual always wins.
     */
    fun recordsActualForecast(input: ActualForecastInput): ActualForecast {
        val asOfMs = input.asOfMs
        val usesFixedMonthlyPay = input.salary?.type == SalaryType.MONTHLY
        val fixedMonthlyPay = if (usesFixedMonthlyPay) allocateFixedMonthlyPay(input.periodDayKeys, asOfMs, input.salary!!, input.zone) else null
        var hasSalary = if (usesFixedMonthlyPay) fixedMonthlyPay != null else input.dailySalary != null
        var actualDays = 0.0
        var actualMs = 0.0
        var actualOvertimeMs = 0.0
        var actualPay = 0.0
        var forecastDays = 0.0
        var forecastMs = 0.0
        var forecastPay = 0.0

        for (day in input.days) {
            if (day.resolvedSegments.isEmpty() && day.overtimeSegments.isEmpty()) continue
            val rate = input.dailySalary
            if (!usesFixedMonthlyPay && rate == null) hasSalary = false
            val plannedMs = mergedDuration(day.plannedSegments)
            val kind = day.actualKind
            if (kind == null) {
                val forecastWorkMs = mergedDuration(day.resolvedSegments)
                if (forecastWorkMs <= 0) continue
                forecastDays += 1
                forecastMs += forecastWorkMs
                if (!usesFixedMonthlyPay) forecastPay += rate ?: 0.0
                continue
            }
            val regular = if (kind != ActualKind.OBSERVED) {
                day.resolvedSegments
            } else {
                intersect(observedWorkSegments(day.observations, asOfMs, day.isActiveAnchor), day.resolvedSegments)
            }
            val elapsedRegular = regular.map { ShiftSegment(it.startAtMs, min(it.endAtMs, asOfMs)) }
            val elapsedOvertime = day.overtimeSegments.map { ShiftSegment(it.startAtMs, min(it.endAtMs, asOfMs)) }
            val workedMs = mergedDuration(elapsedRegular + elapsedOvertime)
            actualOvertimeMs += max(0.0, workedMs - mergedDuration(elapsedRegular))
            if (workedMs > 0) {
                actualDays += 1
                actualMs += workedMs
                if (!usesFixedMonthlyPay) actualPay += (rate ?: 0.0) * (if (plannedMs > 0) workedMs / plannedMs else 1.0)
            }
            if (day.isActiveAnchor || kind == ActualKind.SCHEDULED) {
                val futureMs = mergedDuration((day.resolvedSegments + day.overtimeSegments).map { ShiftSegment(max(it.startAtMs, asOfMs), it.endAtMs) })
                if (futureMs > 0) {
                    if (workedMs <= 0) forecastDays += 1
                    forecastMs += futureMs
                    if (!usesFixedMonthlyPay) {
                        forecastPay += (rate ?: 0.0) * (if (plannedMs > 0) futureMs / plannedMs else if (workedMs <= 0) 1.0 else 0.0)
                    }
                }
            }
        }

        if (fixedMonthlyPay != null) {
            actualPay = fixedMonthlyPay.first
            forecastPay = fixedMonthlyPay.second
        }
        val msPerHour = 3_600_000.0
        val actualEarnings = actualPay.takeIf { hasSalary && it.isFinite() }
        val forecastEarnings = forecastPay.takeIf { hasSalary && it.isFinite() }
        val totalEarnings = if (actualEarnings != null && forecastEarnings != null) (actualEarnings + forecastEarnings).takeIf { it.isFinite() } else null
        return ActualForecast(
            actualOvertimeHours = actualOvertimeMs / msPerHour,
            actual = Part(actualDays, actualMs / msPerHour, actualEarnings),
            forecast = Part(forecastDays, forecastMs / msPerHour, forecastEarnings),
            total = Part(actualDays + forecastDays, (actualMs + forecastMs) / msPerHour, totalEarnings),
        )
    }

    /**
     * A monthly salary spread over the visible days, each taking its own
     * month's share (natural days, so leave never reduces it), split at the
     * civil day containing `asOfMs`.
     */
    private fun allocateFixedMonthlyPay(dayKeys: List<String>, asOfMs: Double, salary: SalarySettings, zone: ZoneId): Pair<Double, Double>? {
        if (!asOfMs.isFinite()) return null
        val monthlySalary = salaryMonthlyEquivalent(salary.copy(type = SalaryType.MONTHLY)) ?: return null
        val asOfDay = CivilZone(zone).civil(asOfMs).dayNumber
        var actual = 0.0
        var forecast = 0.0
        for (key in dayKeys.distinct()) {
            val day = civilDayNumber(key) ?: continue
            val (year, month, _) = CivilZone.civilDate(day)
            val daysInMonth = (nextMonthStart(year, month) - CivilZone.dayNumber(year, month, 1)).toDouble()
            if (day <= asOfDay) actual += monthlySalary / daysInMonth else forecast += monthlySalary / daysInMonth
        }
        return actual to forecast
    }

    /** Total length of the union of [segments]; empty and non-finite ones are ignored. */
    private fun mergedDuration(segments: List<ShiftSegment>): Double {
        val sorted = segments
            .filter { it.startAtMs.isFinite() && it.endAtMs.isFinite() && it.endAtMs > it.startAtMs }
            .sortedWith(compareBy<ShiftSegment> { it.startAtMs }.thenBy { it.endAtMs })
        var total = 0.0
        var openStart = 0.0
        var openEnd = 0.0
        var isOpen = false
        for (segment in sorted) {
            if (isOpen && segment.startAtMs <= openEnd) {
                openEnd = max(openEnd, segment.endAtMs)
            } else {
                if (isOpen) total += openEnd - openStart
                openStart = segment.startAtMs
                openEnd = segment.endAtMs
                isOpen = true
            }
        }
        return if (isOpen) total + openEnd - openStart else total
    }

    private fun intersect(left: List<ShiftSegment>, right: List<ShiftSegment>): List<ShiftSegment> =
        left.flatMap { first ->
            right.mapNotNull { second ->
                val start = max(first.startAtMs, second.startAtMs)
                val end = min(first.endAtMs, second.endAtMs)
                if (end > start) ShiftSegment(start, end) else null
            }
        }

    /** Started/stopped pairs as intervals; an unmatched start closes at `asOfMs` only when [closesOpen]. */
    private fun observedWorkSegments(observations: List<Observation>, asOfMs: Double, closesOpen: Boolean): List<ShiftSegment> {
        val result = ArrayList<ShiftSegment>()
        var startedAt: Double? = null
        for (observation in observations.filter { it.occurredAtMs.isFinite() }.sortedBy { it.occurredAtMs }) {
            if (observation.isStart) {
                if (startedAt == null) startedAt = observation.occurredAtMs
            } else if (startedAt != null) {
                if (observation.occurredAtMs > startedAt) result += ShiftSegment(startedAt, observation.occurredAtMs)
                startedAt = null
            }
        }
        if (startedAt != null && closesOpen && asOfMs.isFinite() && asOfMs > startedAt) result += ShiftSegment(startedAt, asOfMs)
        return result
    }
}

/** Civil midnight on 1 January of the year containing `ms` (`zonedYearStartMs`). */
fun CivilZone.yearStartMs(ms: Double): Double = utcMs(CivilZone.dayNumber(civil(ms).year, 1, 1), WallClock.MIDNIGHT)
