package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.FocusTask
import com.rainif.doneat.core.domain.records.FocusTimerSettings
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import java.security.MessageDigest
import java.util.Locale

val DEFAULT_TIMER_SETTINGS = FocusTimerSettings(25, 5, 15, 4)

/**
 * Session identities derived rather than random, so two devices that start
 * the same automatic block or break write one row (iOS `FocusSessionIdentity`):
 * the first 16 bytes of SHA-256 over a versioned seed, with UUID version and
 * variant bits set. Not `nameUUIDFromBytes` (MD5) and not UUIDv5 (SHA-1).
 */
object FocusSessionIdentity {
    fun block(taskID: String, startAtMs: Long, endAtMs: Long) =
        derive("owc.focus.block.v1|${taskID.lowercase(Locale.ROOT)}|$startAtMs|$endAtMs")

    fun recovery(afterSessionID: String, kind: FocusSessionKind) =
        derive("owc.focus.recovery.v1|${afterSessionID.lowercase(Locale.ROOT)}|${kind.raw}")

    private fun derive(seed: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(seed.toByteArray(Charsets.UTF_8)).copyOf(16)
        bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x50).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte()
        val hex = bytes.joinToString("") { "%02X".format(Locale.ROOT, it) }
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}"
    }
}

/** One cell of the shift's focus/recovery grid; `startAtMs` is the key plan assignments are stored under. */
data class FocusWorkBlock(
    val index: Int,
    val startAtMs: Long,
    val endAtMs: Long,
    val kind: FocusPlanBlockKind = FocusPlanBlockKind.TASK,
    val breakKind: FocusSessionKind? = null,
) {
    val durationMinutes get() = maxOf(1, ((endAtMs - startAtMs) / 60_000).toInt())
}

data class FocusBoundary(val atMs: Double, val reason: FocusEndReason)

/** iOS `FocusPlanner`: the grid, where a phase may start, and where it must stop. */
object FocusPlanner {
    const val POMODORO_MINUTES = 25

    /**
     * The grid for a whole shift, a pure function of the segments and the
     * cadence: focus, then its break, with a long break every Nth round. The
     * first phase that cannot fit ends that segment rather than stretching a
     * break or crossing lunch or clock-off.
     */
    fun workBlocks(segments: List<ShiftSegment>, settings: FocusTimerSettings = DEFAULT_TIMER_SETTINGS): List<FocusWorkBlock> {
        val c = settings.normalized
        val result = ArrayList<FocusWorkBlock>()
        var rounds = 0
        for (segment in segments.sortedBy { it.startAtMs }) {
            val endMs = FoundationCompat.roundedHalfAwayFromZero(segment.endAtMs).toLong()
            var cursor = FoundationCompat.roundedHalfAwayFromZero(segment.startAtMs).toLong()
            while (cursor < endMs) {
                val focusMs = c.focusMinutes * 60_000L
                if (cursor + focusMs > endMs) break
                result += FocusWorkBlock(result.size, cursor, cursor + focusMs)
                cursor += focusMs
                rounds++
                val long = rounds % c.longBreakEvery == 0
                val breakMs = (if (long) c.longBreakMinutes else c.shortBreakMinutes) * 60_000L
                if (cursor + breakMs > endMs) break
                result += FocusWorkBlock(result.size, cursor, cursor + breakMs, FocusPlanBlockKind.BREAK_TIME, if (long) FocusSessionKind.LONG_BREAK else FocusSessionKind.SHORT_BREAK)
                cursor += breakMs
            }
        }
        return result
    }

    /** Inside a current work segment, or the declared overtime that continues the last one. A future segment is not a window. */
    fun isInsideWork(nowMs: Double, segments: List<ShiftSegment>, overtimeEndAtMs: Double?): Boolean {
        if (segments.any { nowMs >= it.startAtMs && nowMs < it.endAtMs }) return true
        val last = segments.maxByOrNull { it.endAtMs } ?: return false
        if (overtimeEndAtMs == null || overtimeEndAtMs <= last.endAtMs) return false
        return nowMs >= last.endAtMs && nowMs < overtimeEndAtMs
    }

    /** The next hard stop: a lunch gap, clock-off, or the end of declared overtime. */
    fun nextBoundary(startMs: Double, segments: List<ShiftSegment>, overtimeEndAtMs: Double?, durationMinutes: Int = POMODORO_MINUTES): FocusBoundary? {
        val sorted = segments.sortedBy { it.startAtMs }
        for ((index, segment) in sorted.withIndex()) {
            if (startMs < segment.startAtMs) return FocusBoundary(segment.startAtMs, FocusEndReason.STOPPED_AT_BOUNDARY)
            if (startMs >= segment.startAtMs && startMs < segment.endAtMs) {
                val plannedMs = startMs + durationMinutes * 60_000.0
                var endMs = segment.endAtMs
                if (overtimeEndAtMs != null && overtimeEndAtMs > endMs) endMs = overtimeEndAtMs
                val hasNext = index + 1 < sorted.size
                if (plannedMs <= endMs) {
                    return if (hasNext && plannedMs > segment.endAtMs) FocusBoundary(segment.endAtMs, FocusEndReason.STOPPED_AT_BOUNDARY) else null
                }
                // Declared overtime extends only the last segment; a segment followed by lunch still stops at its own end.
                return FocusBoundary(if (hasNext) segment.endAtMs else endMs, FocusEndReason.STOPPED_AT_BOUNDARY)
            }
        }
        if (overtimeEndAtMs != null && overtimeEndAtMs > startMs) return FocusBoundary(overtimeEndAtMs, FocusEndReason.STOPPED_AT_BOUNDARY)
        return null
    }

    fun plannedEnd(startMs: Double, segments: List<ShiftSegment>, overtimeEndAtMs: Double?, durationMinutes: Int = POMODORO_MINUTES): Double {
        val natural = startMs + durationMinutes * 60_000.0
        val boundary = nextBoundary(startMs, segments, overtimeEndAtMs, durationMinutes)
        return if (boundary != null && boundary.atMs < natural) boundary.atMs else natural
    }

    /** A phase that ran its whole planned length completed; anything shorter was cut by a boundary. One second of slack. */
    fun endReason(startedAtMs: Double, plannedEndAtMs: Double, expectedDurationMinutes: Int = POMODORO_MINUTES): FocusEndReason =
        if (plannedEndAtMs / 1_000 - startedAtMs / 1_000 >= expectedDurationMinutes * 60 - 1) FocusEndReason.COMPLETED else FocusEndReason.STOPPED_AT_BOUNDARY

    /** Which unfinished tasks the remaining work can hold, by remaining blocks rather than the original estimate. */
    fun remainingPomodoros(
        tasks: List<FocusTask>,
        remainingWorkMs: Long,
        completedBlocks: (FocusTask) -> Int = { 0 },
        settings: FocusTimerSettings = DEFAULT_TIMER_SETTINGS,
    ): Pair<List<FocusTask>, List<FocusTask>> {
        var budget = remainingWorkMs
        val fits = ArrayList<FocusTask>()
        val overflow = ArrayList<FocusTask>()
        val slice = settings.normalized.focusMinutes * 60_000L
        for (task in sortedTasks(tasks).filter { it.completedAtMs == null }) {
            val remaining = maxOf(0, maxOf(1, task.estimatedPomodoros) - completedBlocks(task))
            if (remaining == 0) continue
            val need = remaining * slice
            if (need <= budget) {
                fits += task
                budget -= need
            } else {
                overflow += task
            }
        }
        return fits to overflow
    }

    /** Task order: `sortIndex`, then id. */
    fun sortedTasks(tasks: List<FocusTask>) = tasks.sortedWith(compareBy<FocusTask> { it.sortIndex }.thenBy { it.id })
}
