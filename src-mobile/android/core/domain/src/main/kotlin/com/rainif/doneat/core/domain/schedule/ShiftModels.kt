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
) {
    fun withoutOvertime() = copy(overtimeEndAtMs = null)

    companion object {
        // `|| null` in the TypeScript: an empty break or a 0 instant means none.
        fun of(input: ScheduleRuleInput) = ShiftOptions(
            breakStartTime = input.hours.breakStartTime?.takeIf { it.isNotEmpty() },
            breakDurationMinutes = input.hours.breakDurationMinutes,
            overtimeEndAtMs = input.overtimeEndAtMs?.takeIf { it != 0.0 },
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
            return plannedEndAtMs > startAtMs &&
                plannedEndAtMs > last.startAtMs &&
                plannedEndAtMs <= last.endAtMs &&
                endAtMs == last.endAtMs
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

    /** Linear: 1 at the planned end, above 1 in overtime at the original rate. */
    fun payRatio(nowMs: Double): Double {
        val planned = plannedDurationMs
        if (planned <= 0) return 0.0
        return max(0.0, elapsedMs(nowMs) / planned)
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
