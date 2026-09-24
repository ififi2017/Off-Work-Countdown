package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ShiftSegment
import java.time.LocalDate
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

/**
 * What the Records page draws (iOS `RecordsScale.swift` and
 * `RecordsDayCanvasModel.swift`). Views receive these finished: they never
 * intersect shifts, clip overtime, derive a lunch gap or decide a source.
 */
enum class RecordsScale(val raw: String) {
    WEEK("week"),
    MONTH("month"),
    YEAR("year"),
    LIFE("life");

    val requiresPlus get() = this == YEAR || this == LIFE

    val zoomedIn get() = when (this) {
        WEEK, MONTH -> WEEK
        YEAR -> MONTH
        LIFE -> YEAR
    }

    val zoomedOut get() = when (this) {
        WEEK -> MONTH
        MONTH -> YEAR
        YEAR, LIFE -> LIFE
    }

    companion object {
        fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw }
    }
}

enum class RecordsDayAppearance { UNRECORDED, RECORDED, CORRECTED, PLANNED, REST, LOCKED }

data class RecordsDayCell(
    val dayKey: String,
    val date: LocalDate,
    val appearance: RecordsDayAppearance,
    val workMs: Long,
    val overtimeMs: Long,
    val breakMs: Long,
    val freeMs: Long,
    val observationCount: Int,
    val isToday: Boolean,
    val isFuture: Boolean,
    val isProjection: Boolean,
    val hasConflict: Boolean,
    val isFromSavedSchedule: Boolean = false,
)

/** The six categories every records surface divides time into. */
enum class TimeAllocationKind { WORK, OVERTIME, WORK_BREAK, SLEEP, FREE, UNCLASSIFIED }

data class TimeAllocationShare(
    val workMs: Long = 0,
    val overtimeMs: Long = 0,
    val breakMs: Long = 0,
    val sleepMs: Long = 0,
    val freeMs: Long = 0,
    val unclassifiedMs: Long = 0,
    val dayLengthMs: Long = 0,
) {
    val totalMs get() = workMs + overtimeMs + breakMs + sleepMs + freeMs + unclassifiedMs

    /** Breaks at work plus the rest of your own waking time. */
    val wakingFreeMs get() = breakMs + freeMs

    fun duration(kind: TimeAllocationKind) = when (kind) {
        TimeAllocationKind.WORK -> workMs
        TimeAllocationKind.OVERTIME -> overtimeMs
        TimeAllocationKind.WORK_BREAK -> breakMs
        TimeAllocationKind.SLEEP -> sleepMs
        TimeAllocationKind.FREE -> freeMs
        TimeAllocationKind.UNCLASSIFIED -> unclassifiedMs
    }

    operator fun plus(other: TimeAllocationShare) = TimeAllocationShare(
        workMs + other.workMs, overtimeMs + other.overtimeMs, breakMs + other.breakMs,
        sleepMs + other.sleepMs, freeMs + other.freeMs, unclassifiedMs + other.unclassifiedMs,
        dayLengthMs + other.dayLengthMs,
    )

    companion object {
        val ZERO = TimeAllocationShare()

        fun combining(shares: List<TimeAllocationShare>) = shares.fold(ZERO, TimeAllocationShare::plus)

        /** Gaps inside one shift: a lunch break is the space its schedule left between segments. */
        fun gaps(segments: List<ShiftSegment>): List<ShiftSegment> =
            segments.sortedBy { it.startAtMs }.zipWithNext().mapNotNull { (current, next) ->
                if (next.startAtMs > current.endAtMs) ShiftSegment(current.endAtMs, next.startAtMs) else null
            }
    }
}

/**
 * Recorded hours, their civil-day coverage and a separate salary basis. A
 * locked summary is never built, so these values cannot reach a locked view.
 */
data class RecordsHeadlineSummary(
    val workdays: Int,
    val regularWorkMs: Long,
    val overtimeMs: Long,
    val wakingFreeMs: Long,
    val estimatedIncome: Double?,
    val completedScheduledWorkdays: Int,
    val allocationDays: Int,
    val allocation: TimeAllocationShare,
    val sleepFromHealth: Boolean,
    val actualForecast: com.rainif.doneat.core.domain.summary.SummaryRules.ActualForecast?,
)

/**
 * Where one fact on a records surface came from. Hatching, correction marks
 * and locks are shorthand for a source, never a substitute for the words.
 */
enum class RecordsDaySource {
    /** The user's own timer wrote this day. */
    RECORDED,

    /** The saved schedule applies unless the user supplies an exception. */
    SCHEDULED,

    /** The user edited this day in Records. */
    CORRECTED,

    /** A holiday or makeup day from the calendar. */
    EXCEPTION,

    /** Expanded from the schedule that governed that date. */
    SCHEDULE_ESTIMATE,

    /** Today past the now line: the rest of today's schedule, not a fact yet. */
    AFTER_NOW,

    /** Before Records began, or after today, from the life profile. */
    LIFE_PROJECTION,

    /** A future day the schedule plans. */
    PLANNED,

    /** The sleep budget from the life profile, placed for reading. */
    SLEEP_ESTIMATE,

    /** A workday with nothing written on it. */
    UNRECORDED,

    /** Not a workday. */
    REST,

    /** Outside the free window and without Plus. */
    LOCKED;

    /** Drawn hatched: an estimate is not less important, so it is never just fainter. */
    val isEstimated get() = this == SCHEDULE_ESTIMATE || this == AFTER_NOW || this == LIFE_PROJECTION || this == PLANNED || this == SLEEP_ESTIMATE

    val isCorrection get() = this == CORRECTED
}

/** One classified, attributed stretch of a civil day. */
data class RecordsDayInterval(
    val kind: TimeAllocationKind,
    val startAtMs: Double,
    val endAtMs: Double,
    val source: RecordsDaySource,
    /** The shift this stretch belongs to; null for sleep, own time and unclassified time. */
    val anchorDayKey: String?,
    /** For the "no rules" remainder, which names no source. */
    val unexplained: Boolean = false,
) {
    val durationMs get() = max(0L, (endAtMs - startAtMs).roundToLong())
}

/** A shift that reaches into the civil day being drawn. A 20:00–04:00 shift is one for two days. */
data class RecordsDayShift(
    val anchorDayKey: String,
    val segments: List<ShiftSegment>,
    val overtimeSegments: List<ShiftSegment> = emptyList(),
    val source: RecordsDaySource,
    /** Only a shift with an editable original input offers an edit entry. */
    val isEditable: Boolean = false,
)

/** A shift the day's edit entry can open, labelled by its own real hours. */
data class RecordsDayEditableShift(val anchorDayKey: String, val startAtMs: Double, val endAtMs: Double, val hasHours: Boolean)

/**
 * One civil day, ready to draw and ready to read aloud. This is the only place
 * a day is cut out of the shifts that cross it, and the allocation is summed
 * from what was placed, so the band and the numbers under it cannot disagree.
 */
data class RecordsDayCanvasModel(
    val dayKey: String,
    val dayStartMs: Double,
    val dayEndMs: Double,
    /** What the day as a whole is; single stretches can differ. */
    val source: RecordsDaySource,
    val intervals: List<RecordsDayInterval>,
    val allocation: TimeAllocationShare,
    val isToday: Boolean,
    /** Today only, on a minute boundary: a retrospective page needs no per-second refresh. */
    val nowAtMs: Double?,
    val projectionStartsAtMs: Double?,
    val editableShifts: List<RecordsDayEditableShift>,
    val isLocked: Boolean,
    val sleepFromHealth: Boolean,
    /** The rules could not expand this day, so part of it is unaccounted for rather than padded. */
    val hasIncompleteRules: Boolean,
) {
    val wakingFreeMs get() = allocation.wakingFreeMs

    /** Share of the day's real length, 23 or 25 hours across a DST change. */
    val wakingFreeShare get() = if (allocation.dayLengthMs <= 0) 0.0 else (wakingFreeMs.toDouble() / allocation.dayLengthMs).coerceIn(0.0, 1.0)

    val workIntervals get() = intervals.filter { it.kind == TimeAllocationKind.WORK || it.kind == TimeAllocationKind.OVERTIME }

    data class Input(
        val dayKey: String,
        val dayStartMs: Double,
        val dayEndMs: Double,
        val source: RecordsDaySource,
        /** Every shift that can reach this day, the day's own included. */
        val shifts: List<RecordsDayShift>,
        val sleepHours: Double,
        val sleepFromHealth: Boolean = false,
        val isToday: Boolean = false,
        val nowMs: Double = 0.0,
        val rulesFailed: Boolean = false,
    )

    companion object {
        /** A locked day carries no interval, duration, source or anchor: nothing real was built. */
        fun locked(dayKey: String, dayStartMs: Double, dayEndMs: Double) = RecordsDayCanvasModel(
            dayKey, dayStartMs, dayEndMs, RecordsDaySource.LOCKED, emptyList(), TimeAllocationShare.ZERO,
            isToday = false, nowAtMs = null, projectionStartsAtMs = null, editableShifts = emptyList(),
            isLocked = true, sleepFromHealth = false, hasIncompleteRules = false,
        )

        fun build(input: Input): RecordsDayCanvasModel {
            val lower = input.dayStartMs
            val upper = input.dayEndMs
            val dayLength = max(0L, (upper - lower).roundToLong())
            if (upper <= lower) {
                return RecordsDayCanvasModel(
                    input.dayKey, lower, upper, input.source, emptyList(), TimeAllocationShare.ZERO, input.isToday,
                    null, null, emptyList(), false, input.sleepFromHealth, input.rulesFailed,
                )
            }
            // Oldest first, so an overlap between a corrected day and the night before resolves the same way every time.
            val shifts = input.shifts.sortedBy { it.anchorDayKey }
            val intervals = mutableListOf<RecordsDayInterval>()
            var occupied = listOf<Span>()
            fun place(kind: TimeAllocationKind, pick: (RecordsDayShift) -> List<ShiftSegment>) {
                for (shift in shifts) {
                    val spans = subtract(occupied, clip(pick(shift), lower, upper))
                    occupied = merge(occupied + spans)
                    spans.mapTo(intervals) { RecordsDayInterval(kind, it.start, it.end, shift.source, shift.anchorDayKey) }
                }
            }
            place(TimeAllocationKind.WORK) { it.segments }
            place(TimeAllocationKind.OVERTIME) { it.overtimeSegments }
            // Only the gaps inside one shift are breaks; the hours between two night shifts are not lunch.
            place(TimeAllocationKind.WORK_BREAK) { TimeAllocationShare.gaps(it.segments) }

            val openBlocks = subtract(merge(occupied), listOf(Span(lower, upper)))
            val (sleep, remainder) = placeSleep(max(0.0, input.sleepHours) * 3_600_000, openBlocks)
            sleep.mapTo(intervals) { RecordsDayInterval(TimeAllocationKind.SLEEP, it.start, it.end, RecordsDaySource.SLEEP_ESTIMATE, null) }
            val ownKind = if (input.rulesFailed) TimeAllocationKind.UNCLASSIFIED else TimeAllocationKind.FREE
            remainder.mapTo(intervals) {
                RecordsDayInterval(
                    ownKind, it.start, it.end,
                    if (input.rulesFailed) RecordsDaySource.SCHEDULE_ESTIMATE else input.source,
                    null, unexplained = input.rulesFailed,
                )
            }
            val nowMs = if (input.isToday) kotlin.math.floor(input.nowMs / 60_000) * 60_000 else null
            val projectionStart = nowMs?.takeIf { it >= lower && it < upper }
            val placed = (projectionStart?.let { splitAtNow(intervals, it) } ?: intervals).sortedBy { it.startAtMs }

            // A recorded overnight tail is what this day shows, even when the day anchored here is a rest day.
            val resolvedSource = if (input.source == RecordsDaySource.REST || input.source == RecordsDaySource.UNRECORDED) {
                placed.firstOrNull { it.kind == TimeAllocationKind.WORK || it.kind == TimeAllocationKind.OVERTIME }?.source ?: input.source
            } else {
                input.source
            }
            val editable = shifts.mapNotNull { shift ->
                if (!shift.isEditable) return@mapNotNull null
                val hours = clip(shift.segments, lower, upper).isNotEmpty()
                // The day on screen always answers "which shift?", even without hours: a rest day can become a makeup day.
                if (!hours && shift.anchorDayKey != input.dayKey) return@mapNotNull null
                RecordsDayEditableShift(
                    shift.anchorDayKey,
                    shift.segments.minOfOrNull { it.startAtMs } ?: lower,
                    shift.segments.maxOfOrNull { it.endAtMs } ?: upper,
                    hours,
                )
            }
            fun total(kind: TimeAllocationKind) = placed.filter { it.kind == kind }.sumOf { it.durationMs }
            val allocation = TimeAllocationShare(
                total(TimeAllocationKind.WORK), total(TimeAllocationKind.OVERTIME), total(TimeAllocationKind.WORK_BREAK),
                total(TimeAllocationKind.SLEEP), total(TimeAllocationKind.FREE), total(TimeAllocationKind.UNCLASSIFIED), dayLength,
            )
            return RecordsDayCanvasModel(
                input.dayKey, lower, upper, resolvedSource, placed, allocation, input.isToday, nowMs, projectionStart,
                editable, false, input.sleepFromHealth, input.rulesFailed,
            )
        }

        private data class Span(val start: Double, val end: Double)

        private fun clip(segments: List<ShiftSegment>, lower: Double, upper: Double) = merge(
            segments.mapNotNull { s ->
                val start = max(lower, s.startAtMs)
                val end = min(upper, s.endAtMs)
                if (end > start) Span(start, end) else null
            },
        )

        private fun merge(spans: List<Span>): List<Span> {
            val merged = mutableListOf<Span>()
            for (span in spans.sortedBy { it.start }) {
                val last = merged.lastOrNull()
                if (last != null && span.start <= last.end) merged[merged.lastIndex] = Span(last.start, max(last.end, span.end)) else merged += span
            }
            return merged
        }

        private fun subtract(taken: List<Span>, spans: List<Span>): List<Span> {
            if (taken.isEmpty()) return spans
            val result = mutableListOf<Span>()
            for (span in spans) {
                var cursor = span.start
                for (block in taken) {
                    if (block.end <= span.start || block.start >= span.end) continue
                    if (block.start > cursor) result += Span(cursor, min(block.start, span.end))
                    cursor = max(cursor, block.end)
                    if (cursor >= span.end) break
                }
                if (cursor < span.end) result += Span(cursor, span.end)
            }
            return result.filter { it.end > it.start }
        }

        /**
         * Sleep is a budget, not a record: it goes at the start of the longest
         * unbroken non-work stretch, the one place a night's sleep can have been.
         */
        private fun placeSleep(budgetMs: Double, blocks: List<Span>): Pair<List<Span>, List<Span>> {
            if (budgetMs <= 0) return emptyList<Span>() to blocks
            var remaining = budgetMs
            val order = blocks.indices.sortedWith(compareByDescending<Int> { blocks[it].end - blocks[it].start }.thenBy { it })
            val filled = mutableMapOf<Int, Double>()
            for (index in order) {
                if (remaining <= 0) break
                val taken = min(remaining, blocks[index].end - blocks[index].start)
                if (taken <= 0) continue
                filled[index] = taken
                remaining -= taken
            }
            val sleep = mutableListOf<Span>()
            val remainder = mutableListOf<Span>()
            blocks.forEachIndexed { index, block ->
                val taken = filled[index]
                if (taken == null) {
                    remainder += block
                } else {
                    sleep += Span(block.start, block.start + taken)
                    if (block.start + taken < block.end) remainder += Span(block.start + taken, block.end)
                }
            }
            return sleep to remainder
        }

        /** Past the now line, what was drawn as fact is the schedule's estimate; estimates keep their own source. */
        private fun splitAtNow(intervals: List<RecordsDayInterval>, nowAtMs: Double) = intervals.flatMap { interval ->
            if (interval.source.isEstimated || interval.endAtMs <= nowAtMs) return@flatMap listOf(interval)
            val future = interval.copy(source = RecordsDaySource.AFTER_NOW)
            if (interval.startAtMs >= nowAtMs) listOf(future) else listOf(interval.copy(endAtMs = nowAtMs), future.copy(startAtMs = nowAtMs))
        }
    }
}

/** A fixed overtime scale, never shift length or the busiest visible day; eight extra hours saturate it. */
object RecordsWorkIntensity {
    fun opacity(overtimeMs: Long, estimated: Boolean): Double =
        if (estimated) 0.18 else 0.45 + min(1.0, max(0L, overtimeMs) / 28_800_000.0) * 0.5
}

/** One shared week axis keeps days comparable without clipping a long shift. */
object RecordsWeekAxis {
    fun ceiling(cells: List<RecordsDayCell>): Long = max(12 * 3_600_000L, cells.maxOfOrNull { it.workMs + it.overtimeMs } ?: 0L)
}

/** One vocabulary for a day's marks, shared by every grid. */
object RecordsDayMarks {
    /** Hatching says "these hours are an estimate"; a rest day has no hours to hatch. */
    fun isEstimated(cell: RecordsDayCell) =
        (cell.isFuture || cell.isProjection || cell.appearance == RecordsDayAppearance.PLANNED) && cell.workMs + cell.overtimeMs > 0
}

/** The free window: today and the six days before it, in the records zone (iOS `RecordsAccess`). */
object RecordsAccess {
    const val FREE_LOOKBACK_DAYS = 6L

    fun freeWindowContains(day: LocalDate, today: LocalDate) = !day.isBefore(today.minusDays(FREE_LOOKBACK_DAYS)) && !day.isAfter(today)

    fun canRevealDay(day: LocalDate, today: LocalDate, authorized: Boolean) = authorized || freeWindowContains(day, today)
}
