package com.rainif.doneat.core.domain.schedule

import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min

/**
 * Instants are Unix epoch milliseconds as `Double`, like `lib/countdown.ts` and
 * the Swift port: overtime can end mid-millisecond, and every figure has to
 * match the TypeScript oracle bit for bit (shared-rule-fixtures.json).
 */
data class ShiftSegment(val startAtMs: Double, val endAtMs: Double)

enum class ScheduleMode(val raw: String) {
    CLASSIC("classic"),
    ALTERNATING("alternating"),
    ROTATION("rotation"),

    /** Manual: shifts are started by hand, so there is no rest pattern. */
    OFF("off");

    companion object {
        fun fromRaw(raw: String): ScheduleMode? = entries.firstOrNull { it.raw == raw }
    }
}

data class WorkSchedule(
    val mode: ScheduleMode,
    val referenceWeekStartMs: Double? = null,
    val referenceWeekType: String? = null,
    val singleWeekendWorkday: Int? = null,
    val rotationAnchorMs: Double? = null,
    val rotationWorkDays: Int? = null,
    val rotationRestDays: Int? = null,
)

/** The fixed working hours and pattern, without an instant or overrides. */
data class ScheduleHours(
    val startTime: String,
    val endTime: String,
    val workdays: List<Int>,
    val schedule: WorkSchedule,
    val breakStartTime: String?,
    val breakDurationMinutes: Int,
    /** Plan 018 P8's per-day assignments, when switched on; null keeps the fixed-hours path. */
    val extended: ExtendedSchedulePlan? = null,
)

/**
 * Everything one rule call reads. The zone is explicit: callers pass the
 * records or device zone rather than the rules reading a default.
 */
data class ScheduleRuleInput(
    val hours: ScheduleHours,
    val nowMs: Double,
    val zone: ZoneId,
    val overtimeEndAtMs: Double? = null,
    val forcedWorkdayStartMs: Double? = null,
    /** Plan 024: when the overtime starts; null (or at/before the planned end) stretches the last segment. */
    val overtimeStartAtMs: Double? = null,
) {
    val startTime get() = hours.startTime
    val endTime get() = hours.endTime
    val workdays get() = hours.workdays
    val schedule get() = hours.schedule
}

data class ShiftOptions(
    val breakStartTime: String?,
    val breakDurationMinutes: Int,
    val overtimeEndAtMs: Double? = null,
    val overtimeStartAtMs: Double? = null,
) {
    fun withoutOvertime() = copy(overtimeEndAtMs = null, overtimeStartAtMs = null)

    companion object {
        // `|| null` in the TypeScript: an empty break or a 0 instant means none.
        fun of(input: ScheduleRuleInput) = ShiftOptions(
            breakStartTime = input.hours.breakStartTime?.takeIf { it.isNotEmpty() },
            breakDurationMinutes = input.hours.breakDurationMinutes,
            overtimeEndAtMs = input.overtimeEndAtMs?.takeIf { it != 0.0 },
            overtimeStartAtMs = input.overtimeStartAtMs?.takeIf { it != 0.0 },
        )
    }
}

/** An `HH:mm` reading. Malformed parts read as 0, as `Number` does in the TS. */
data class WallClock(val hour: Int, val minute: Int) {
    val minutes get() = hour * 60 + minute

    companion object {
        val MIDNIGHT = WallClock(0, 0)
        val NOON = WallClock(12, 0)

        fun parse(text: String): WallClock {
            val parts = text.split(":")
            return WallClock(parts[0].toIntOrNull() ?: 0, parts.getOrNull(1)?.toIntOrNull() ?: 0)
        }
    }
}

/**
 * A running shift: effective segments, the planned end, and overtime extending
 * the last segment. Figures come from the segments, never `end - now`.
 */
data class ShiftTimeline(
    val segments: List<ShiftSegment>,
    val plannedEndAtMs: Double,
    val overtimeEndAtMs: Double? = null,
) {
    val startAtMs get() = segments.firstOrNull()?.startAtMs ?: 0.0
    val endAtMs get() = overtimeEndAtMs ?: plannedEndAtMs

    /** Rejects a malformed timeline rather than repairing it. */
    val isValid: Boolean
        get() {
            val last = segments.lastOrNull() ?: return false
            if (!plannedEndAtMs.isFinite()) return false
            overtimeEndAtMs?.let { if (!it.isFinite() || it <= plannedEndAtMs) return false }
            var previousEnd = Double.NEGATIVE_INFINITY
            for (segment in segments) {
                if (!segment.startAtMs.isFinite() || !segment.endAtMs.isFinite() ||
                    segment.endAtMs <= segment.startAtMs || segment.startAtMs < previousEnd
                ) return false
                previousEnd = segment.endAtMs
            }
            if (plannedEndAtMs <= startAtMs || endAtMs != last.endAtMs) return false
            if (plannedEndAtMs > last.startAtMs && plannedEndAtMs <= last.endAtMs) return true
            // Plan 024: overtime appended after a gap. The planned end closes the
            // second-to-last segment and the last one starts after it.
            if (overtimeEndAtMs == null || segments.size < 2) return false
            val before = segments[segments.size - 2]
            return plannedEndAtMs > before.startAtMs && plannedEndAtMs == before.endAtMs && last.startAtMs > plannedEndAtMs
        }

    val durationMs: Double
        get() = if (!isValid) 0.0 else segments.fold(0.0) { total, s -> total + s.endAtMs - s.startAtMs }

    val plannedDurationMs: Double
        get() = if (!isValid) 0.0 else segments.fold(0.0) { total, s ->
            total + max(0.0, min(s.endAtMs, plannedEndAtMs) - s.startAtMs)
        }

    fun elapsedMs(nowMs: Double): Double =
        if (!isValid) 0.0 else segments.fold(0.0) { total, s ->
            total + min(s.endAtMs - s.startAtMs, max(0.0, nowMs - s.startAtMs))
        }

    fun remainingMs(nowMs: Double) = max(0.0, durationMs - elapsedMs(nowMs))

    /** 0…100, as the TypeScript `progress`. */
    fun progress(nowMs: Double): Double {
        val duration = durationMs
        if (duration <= 0) return 0.0
        return max(0.0, min(100.0, elapsedMs(nowMs) / duration * 100))
    }

    /**
     * Linear: 1 at the planned end, above 1 in overtime. [overtimeMultiplier]
     * (plan 024) scales the effective time beyond the planned end; 1 is exactly
     * `elapsed / planned` (`calculateTimelinePayRatio` in `lib/countdown.ts`).
     */
    fun payRatio(nowMs: Double, overtimeMultiplier: Double = OvertimePay.DEFAULT_MULTIPLIER): Double {
        val planned = plannedDurationMs
        if (planned <= 0) return 0.0
        val elapsed = elapsedMs(nowMs)
        val multiplier = OvertimePay.normalized(overtimeMultiplier)
        if (multiplier == 1.0) return max(0.0, elapsed / planned)
        val regular = min(elapsed, planned)
        return max(0.0, (regular + multiplier * (elapsed - regular)) / planned)
    }

    /** Effective time worked beyond the planned end (`overtimeElapsedMs`). */
    fun overtimeElapsedMs(nowMs: Double): Double {
        if (overtimeEndAtMs == null || !nowMs.isFinite()) return 0.0
        val planned = plannedDurationMs
        if (!planned.isFinite() || planned <= 0) return 0.0
        val elapsed = elapsedMs(nowMs)
        if (!elapsed.isFinite()) return 0.0
        return max(0.0, elapsed - planned)
    }

    /**
     * The "if overtime is unpaid" comparison (`overtimeRateComparison`): daily
     * pay over every effective hour so far, and how far below the usual hourly
     * rate that is. Null outside overtime.
     */
    fun overtimeRateComparison(dailySalary: Double?, nowMs: Double): OvertimeRateComparison? {
        if (overtimeEndAtMs == null || !nowMs.isFinite()) return null
        val planned = plannedDurationMs
        if (!planned.isFinite() || planned <= 0) return null
        val elapsed = elapsedMs(nowMs)
        if (!elapsed.isFinite()) return null
        val overtime = max(0.0, elapsed - planned)
        val none = OvertimeRateComparison(overtime, null, null)
        if (overtime <= 0 || dailySalary == null || !dailySalary.isFinite() || dailySalary <= 0) return none
        val rate = dailySalary / (elapsed / 3_600_000)
        val decrease = (1 - 1 / payRatio(nowMs)) * 100
        if (!rate.isFinite() || !decrease.isFinite()) return none
        return OvertimeRateComparison(overtime, rate, decrease)
    }

    /** The end of the gap between segments that `nowMs` falls in, if any. */
    fun activeBreakEndAtMs(nowMs: Double): Double? {
        for (index in 0 until segments.size - 1) {
            val gapStart = segments[index].endAtMs
            val gapEnd = segments[index + 1].startAtMs
            if (gapEnd > gapStart && nowMs >= gapStart && nowMs < gapEnd) return gapEnd
        }
        return null
    }
}

data class OvertimeRateComparison(
    val elapsedOvertimeMs: Double,
    val unpaidHourlyRate: Double?,
    val unpaidRateDecreasePercent: Double?,
)

/**
 * Plan 024: the hours a declaration counts, replacing the measured overtime
 * length in statistics and pay (`normalizeCountedOvertimeMs` and
 * `overtimeCountScale` in `lib/summary.ts`).
 */
object CountedOvertime {
    const val MAXIMUM_MS = 24.0 * 3_600_000

    /** Null unless finite and 0 to 24 hours. */
    fun normalized(value: Double?): Double? =
        value?.takeIf { it.isFinite() && it >= 0 && it <= MAXIMUM_MS }

    /** counted / full measured length; 1 without a valid counted value or any measured overtime to scale. */
    fun scale(fullMeasuredMs: Double, countedMs: Double?): Double {
        val counted = normalized(countedMs) ?: return 1.0
        if (!fullMeasuredMs.isFinite() || fullMeasuredMs <= 0) return 1.0
        return counted / fullMeasuredMs
    }
}

/** Plan 024: the pay multiplier for effective time beyond the planned end. */
object OvertimePay {
    const val DEFAULT_MULTIPLIER = 1.0

    /**
     * 0 (unpaid) or 0.5 to 5 in 0.1 steps; anything else is 1
     * (`normalizeOvertimePayMultiplier` in `lib/countdown.ts`).
     */
    fun normalized(value: Double?): Double {
        if (value == null || !value.isFinite()) return DEFAULT_MULTIPLIER
        val tenths = Math.round(value * 10).toDouble()
        if (kotlin.math.abs(value * 10 - tenths) > 1e-9) return DEFAULT_MULTIPLIER
        if (tenths == 0.0) return 0.0
        if (tenths < 5 || tenths > 50) return DEFAULT_MULTIPLIER
        return tenths / 10
    }
}

data class ShiftSnapshot(
    val segments: List<ShiftSegment>,
    val startAtMs: Double,
    val endAtMs: Double,
    val plannedEndAtMs: Double,
    val overtimeEndAtMs: Double?,
    val durationMs: Double,
    val plannedDurationMs: Double,
    val elapsedMs: Double,
    val remainingMs: Double,
    val progress: Double,
    val payRatio: Double,
    val activeBreakEndAtMs: Double?,
    val isWorkday: Boolean,
    val nextRestAtMs: Double?,
    val dailySalary: Double?,
    val earnedSoFar: Double?,
    val nextShiftStartAtMs: Double?,
    val nextShiftEndAtMs: Double?,
    val countdownTargetAtMs: Double?,
    val countdownAnchorAtMs: Double?,
    val countdownProgress: Double,
)

data class WidgetShift(
    val segments: List<ShiftSegment>,
    val startAtMs: Double,
    val endAtMs: Double,
    val plannedEndAtMs: Double,
    val overtimeEndAtMs: Double?,
    val durationMs: Double,
    val countdownAnchorAtMs: Double,
)

data class ScheduleDayExpansion(
    val dayKey: String,
    val shiftAnchorStartAtMs: Double,
    val isWorkday: Boolean,
    val segments: List<ShiftSegment>,
)
