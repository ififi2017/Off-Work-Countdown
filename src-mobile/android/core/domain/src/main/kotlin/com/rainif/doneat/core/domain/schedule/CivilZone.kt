package com.rainif.doneat.core.domain.schedule

import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.truncate

/**
 * Civil-time arithmetic in one zone, matching `lib/countdown.ts`'s zoned
 * helpers (and Swift's `CivilZone`) minute for minute, including the DST
 * policy: a reading in a fold resolves to the earlier instant, one in a gap to
 * the first minute after it. `java.time`'s own gap/fold choice is deliberately
 * not used. One instance per rule call; it memoises civil conversions.
 *
 * Day numbers count days since 1970-01-01 in the proleptic Gregorian calendar.
 */
class CivilZone(val zoneId: ZoneId) {
    data class Civil(
        val dayNumber: Int,
        val year: Int,
        val month: Int,
        val day: Int,
        val hour: Int,
        val minute: Int,
        val second: Int,
    ) {
        /** 0 = Sunday, as JavaScript's `getDay`. */
        val weekday get() = Math.floorMod(dayNumber + 4, 7)
    }

    private data class Reading(val dayNumber: Int, val hour: Int, val minute: Int)

    private val rules = zoneId.rules
    private val readingCache = HashMap<Reading, Double>()

    fun civil(ms: Double): Civil {
        // A JavaScript Date truncates to whole milliseconds before formatting.
        val wholeMs = truncate(ms)
        val offsetSeconds = rules.getOffset(Instant.ofEpochMilli(wholeMs.toLong())).totalSeconds
        return utcCivil(wholeMs + offsetSeconds * 1_000.0)
    }

    /** The instant a civil reading names in this zone (`zonedTimeToUtcMs`). */
    fun utcMs(dayNumber: Int, clock: WallClock): Double {
        val reading = Reading(dayNumber, clock.hour, clock.minute)
        readingCache[reading]?.let { return it }
        val civilMs = dayNumber * DAY_MS + clock.hour * 3_600_000.0 + clock.minute * 60_000.0
        val offsets = ArrayList<Double>(7)
        for (hours in PROBE_HOURS) {
            val offset = offsetMs(civilMs + hours * 3_600_000.0)
            if (offset !in offsets) offsets.add(offset)
        }
        fun exact(baseMs: Double, target: Civil): Double? = offsets
            .map { baseMs - it }
            .filter { candidate ->
                val actual = civil(candidate)
                actual.dayNumber == target.dayNumber && actual.hour == target.hour && actual.minute == target.minute
            }
            .minOrNull()

        // The reading as the caller spelled it. An hour past 23 never matches,
        // exactly as in the TypeScript, and falls through to the gap walk.
        val target = Civil(dayNumber, 0, 0, 0, clock.hour, clock.minute, 0)
        var resolved = exact(civilMs, target)
        if (resolved == null) {
            for (delta in 1..24 * 60) {
                val nextMs = civilMs + delta * 60_000.0
                val candidate = exact(nextMs, utcCivil(nextMs))
                if (candidate != null) {
                    resolved = candidate
                    break
                }
            }
        }
        val result = resolved ?: civilMs
        readingCache[reading] = result
        return result
    }

    private fun offsetMs(instantMs: Double): Double {
        val reading = civil(instantMs)
        val civilMs = reading.dayNumber * DAY_MS + reading.hour * 3_600_000.0 +
            reading.minute * 60_000.0 + reading.second * 1_000.0
        return civilMs - instantMs
    }

    fun startOfCivilDayMs(ms: Double) = utcMs(civil(ms).dayNumber, WallClock.MIDNIGHT)

    /** Same wall-clock minute `days` civil days later; seconds are dropped. */
    fun addCivilDaysMs(ms: Double, days: Int): Double {
        val reading = civil(ms)
        return utcMs(reading.dayNumber + days, WallClock(reading.hour, reading.minute))
    }

    fun dayKey(ms: Double): String {
        val reading = civil(ms)
        return "${reading.year}-${pad(reading.month)}-${pad(reading.day)}"
    }

    /** Civil midnight on the Monday of the week containing `ms` (`zonedWeekStartMs`). */
    fun weekStartMs(ms: Double): Double {
        val reading = civil(ms)
        return utcMs(reading.dayNumber - (reading.weekday + 6) % 7, WallClock.MIDNIGHT)
    }

    private fun dayDifference(fromMs: Double, toMs: Double) = civil(toMs).dayNumber - civil(fromMs).dayNumber

    // Work patterns

    /** Manual (`off`) mode has no rest pattern, so every shift counts. */
    fun isScheduledWorkday(shiftStartMs: Double, workdays: List<Int>, schedule: WorkSchedule) =
        schedule.mode == ScheduleMode.OFF || isScheduledWorkdayInZone(shiftStartMs, workdays, schedule)

    /** As [isScheduledWorkday], except manual days are rest, so range expansion paints no seven-day week. */
    fun isScheduledWorkdayInZone(shiftStartMs: Double, workdays: List<Int>, schedule: WorkSchedule): Boolean {
        val weekday = civil(shiftStartMs).weekday
        return when (schedule.mode) {
            ScheduleMode.OFF -> false
            ScheduleMode.CLASSIC -> weekday in workdays
            ScheduleMode.ALTERNATING -> {
                if (weekday in 1..5) return true
                val anchor = weekStartMs(schedule.referenceWeekStartMs ?: shiftStartMs)
                val week = weekStartMs(shiftStartMs)
                val weeksFromAnchor = floor(dayDifference(anchor, week) / 7.0).toInt()
                val anchorIsSingle = schedule.referenceWeekType == "single"
                val isSingleWeek = if (abs(weeksFromAnchor) % 2 == 0) anchorIsSingle else !anchorIsSingle
                isSingleWeek && weekday == (schedule.singleWeekendWorkday ?: 6)
            }
            ScheduleMode.ROTATION -> {
                val workLength = max(1, schedule.rotationWorkDays ?: 1)
                val restLength = max(1, schedule.rotationRestDays ?: 1)
                val offset = dayDifference(schedule.rotationAnchorMs ?: shiftStartMs, shiftStartMs)
                Math.floorMod(offset, workLength + restLength) < workLength
            }
        }
    }

    fun nextRestDayStartMs(afterMs: Double, workdays: List<Int>, schedule: WorkSchedule): Double? {
        if (schedule.mode == ScheduleMode.OFF) return null
        val first = civil(afterMs).dayNumber
        for (offset in 0..366) {
            val dayStartMs = utcMs(first + offset, WallClock.MIDNIGHT)
            if (!isScheduledWorkdayInZone(dayStartMs, workdays, schedule)) return dayStartMs
        }
        return null
    }

    // Shifts

    /**
     * The window of the shift containing or nearest `nowMs`. An overnight shift
     * after midnight still belongs to the previous evening.
     */
    fun shiftBounds(startTime: String, endTime: String, nowMs: Double): Pair<Double, Double> {
        val today = civil(nowMs).dayNumber
        val start = WallClock.parse(startTime)
        val end = WallClock.parse(endTime)
        var startAtMs = utcMs(today, start)
        var endAtMs = utcMs(today, end)
        if (endAtMs <= startAtMs) {
            // A spring-forward gap can legalise two same-day clocks onto one
            // instant. That is not an overnight shift.
            if (end.minutes > start.minutes) return startAtMs to startAtMs
            if (nowMs < endAtMs) {
                startAtMs = utcMs(today - 1, start)
            } else {
                endAtMs = utcMs(today + 1, end)
            }
        }
        return startAtMs to endAtMs
    }

    fun shiftTimeline(startTime: String, endTime: String, nowMs: Double, options: ShiftOptions): ShiftTimeline {
        val (start, end) = shiftBounds(startTime, endTime, nowMs)
        return timeline(start, end, options)
    }

    fun timeline(startAtMs: Double, plannedEndAtMs: Double, options: ShiftOptions): ShiftTimeline {
        var segments = listOf(ShiftSegment(startAtMs, plannedEndAtMs))
        val breakDurationMs = options.breakDurationMinutes * 60_000.0
        val breakStartTime = options.breakStartTime
        if (breakStartTime != null && breakDurationMs > 0) {
            val clock = WallClock.parse(breakStartTime)
            val startDay = civil(startAtMs).dayNumber
            var breakStartAtMs = utcMs(startDay, clock)
            if (breakStartAtMs < startAtMs) breakStartAtMs = utcMs(startDay + 1, clock)
            val breakEndAtMs = breakStartAtMs + breakDurationMs
            if (breakStartAtMs > startAtMs && breakEndAtMs < plannedEndAtMs) {
                segments = listOf(
                    ShiftSegment(startAtMs, breakStartAtMs),
                    ShiftSegment(breakEndAtMs, plannedEndAtMs),
                )
            }
        }
        val overtimeEndAtMs = options.overtimeEndAtMs?.takeIf { it > plannedEndAtMs }
        if (overtimeEndAtMs != null) {
            segments = segments.dropLast(1) + segments.last().copy(endAtMs = overtimeEndAtMs)
        }
        return ShiftTimeline(segments, plannedEndAtMs, overtimeEndAtMs)
    }

    /**
     * The shift that still belongs on `nowMs`'s civil day after the live bounds
     * have moved on: a day shift whose overtime crossed midnight, or an
     * overnight shift after its planned end. Checks today and the two days
     * before, using each candidate's effective end.
     */
    fun endedShiftOnEndCalendarDay(
        input: ScheduleRuleInput,
        options: ShiftOptions,
        forcedWorkdayStartMs: Double?,
    ): ShiftTimeline? {
        val todayMs = startOfCivilDayMs(input.nowMs)
        val forcedDayMs = forcedWorkdayStartMs?.takeIf { it.isFinite() }?.let { startOfCivilDayMs(it) }
        for (offset in 0..2) {
            val dayNumber = civil(addCivilDaysMs(todayMs, -offset)).dayNumber
            val (start, end) = shiftBounds(input.startTime, input.endTime, utcMs(dayNumber, WallClock.NOON))
            if (end <= start) continue
            val counts = isScheduledWorkday(start, input.workdays, input.schedule) ||
                (forcedDayMs != null && startOfCivilDayMs(start) == forcedDayMs)
            if (!counts) continue
            val shift = timeline(start, end, options)
            if (input.nowMs >= shift.startAtMs && input.nowMs < shift.endAtMs) return shift
            if (input.nowMs >= shift.endAtMs && startOfCivilDayMs(shift.endAtMs) == todayMs) return shift
        }
        return null
    }

    fun nextShiftTimeline(hours: ScheduleHours, afterMs: Double, options: ShiftOptions): ShiftTimeline? {
        if (hours.schedule.mode == ScheduleMode.OFF) return null
        if (hours.schedule.mode == ScheduleMode.CLASSIC && hours.workdays.isEmpty()) return null
        val cursorMs = startOfCivilDayMs(afterMs)
        for (offset in 0..366) {
            val dayNumber = civil(addCivilDaysMs(cursorMs, offset)).dayNumber
            val (start, end) = shiftBounds(hours.startTime, hours.endTime, utcMs(dayNumber, WallClock.NOON))
            if (!isScheduledWorkdayInZone(start, hours.workdays, hours.schedule) || start <= afterMs) continue
            return timeline(start, end, options)
        }
        return null
    }

    companion object {
        const val DAY_MS = 86_400_000.0
        private val PROBE_HOURS = doubleArrayOf(0.0, -6.0, 6.0, -24.0, 24.0, -48.0, 48.0)

        private fun pad(value: Int) = if (value < 10) "0$value" else "$value"

        private fun utcCivil(ms: Double): Civil {
            val days = floor(ms / DAY_MS)
            val msOfDay = (ms - days * DAY_MS).toInt()
            val dayNumber = days.toInt()
            val (year, month, day) = civilDate(dayNumber)
            return Civil(
                dayNumber, year, month, day,
                hour = msOfDay / 3_600_000,
                minute = msOfDay / 60_000 % 60,
                second = msOfDay / 1_000 % 60,
            )
        }

        fun dayNumber(year: Int, month: Int, day: Int): Int {
            val shiftedYear = if (month <= 2) year - 1 else year
            val era = (if (shiftedYear >= 0) shiftedYear else shiftedYear - 399) / 400
            val yearOfEra = shiftedYear - era * 400
            val dayOfYear = (153 * (if (month > 2) month - 3 else month + 9) + 2) / 5 + day - 1
            val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
            return era * 146_097 + dayOfEra - 719_468
        }

        fun civilDate(dayNumber: Int): Triple<Int, Int, Int> {
            val shifted = dayNumber + 719_468
            val era = (if (shifted >= 0) shifted else shifted - 146_096) / 146_097
            val dayOfEra = shifted - era * 146_097
            val yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
            val dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
            val monthIndex = (5 * dayOfYear + 2) / 153
            val day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
            val month = if (monthIndex < 10) monthIndex + 3 else monthIndex - 9
            return Triple(yearOfEra + era * 400 + (if (month <= 2) 1 else 0), month, day)
        }
    }
}
