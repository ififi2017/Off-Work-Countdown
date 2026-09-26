package com.rainif.doneat.core.domain.widget

import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.schedule.WidgetShift
import com.rainif.doneat.core.domain.session.RulesSource
import com.rainif.doneat.core.domain.session.ShiftSession
import java.time.Instant
import java.time.ZoneId

/**
 * Builds the widget snapshot from the real schedule rules (iOS
 * `WidgetSnapshotComposer`). It never resolves a workday or constructs a
 * shift itself: every shift comes from `ShiftSession.snapshot` or
 * `ScheduleRules.widgetShifts`. Calendar days (rest-day copy, "done for
 * today" until midnight) follow the device's zone, as iOS's `Calendar.current`.
 */
object WidgetSnapshotComposer {
    private const val HORIZON_DAYS = 370L
    private const val MAXIMUM_SHIFTS = 400
    private const val DAY_MS = 86_400_000L

    /**
     * The "coming up" rows, worded by the caller: the moment, the current shift (or null),
     * the snapshot's expiry, and the precomputed future shifts.
     */
    fun interface Upcoming {
        fun items(nowMs: Long, current: ShiftSnapshot?, expiresAtMs: Long?, futureShifts: List<WidgetShift>): List<WidgetUpcomingItem>
    }

    /** A year of scheduled shifts after the current one, from the committed hours (the slow part; run off the main thread). */
    fun futureShifts(session: ShiftSession, nowMs: Long): List<WidgetShift> {
        if (!session.followsSchedule(nowMs.toDouble())) return emptyList()
        val horizon = horizon(nowMs, session.deviceZone)
        return ScheduleRules.widgetShifts(session.rulesInput(nowMs.toDouble(), source = RulesSource.BASE), horizon.toDouble(), MAXIMUM_SHIFTS)
    }

    fun compose(session: ShiftSession, nowMs: Long, locale: String, futureShifts: List<WidgetShift>, upcoming: Upcoming): WidgetSnapshot {
        val builder = Builder(session, nowMs, locale, upcoming)
        val now = nowMs.toDouble()
        val shift = session.snapshot(now)
        // On a schedule the schedule is the authority; "active" only matters for manual runs.
        if (session.followsSchedule(now) && shift != null) return builder.recurring(shift, futureShifts)
        if (!session.shouldQuerySnapshot(now)) return builder.inactive(shift)
        if (shift == null) return builder.idle()
        return builder.single(shift)
    }

    private fun horizon(nowMs: Long, zone: ZoneId) =
        Instant.ofEpochMilli(nowMs).atZone(zone).plusDays(HORIZON_DAYS).toInstant().toEpochMilli()

    private fun startOfDay(ms: Long, zone: ZoneId) =
        Instant.ofEpochMilli(ms).atZone(zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()

    private fun nextMidnight(ms: Long, zone: ZoneId) =
        Instant.ofEpochMilli(ms).atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()

    private class Builder(val session: ShiftSession, val nowMs: Long, val locale: String, val upcoming: Upcoming) {
        val zone = session.deviceZone
        val entries = ArrayList<WidgetEntry>()
        var cursor = nowMs
        val breakLabel = if (session.env.isExtendedScheduleEnabled) "extendedBreak" else "lunchInProgress"

        fun snapshot(expiresAtMs: Long, current: ShiftSnapshot?, futureShifts: List<WidgetShift> = emptyList(), upcomingExpiry: Long? = expiresAtMs) = WidgetSnapshot(
            schemaVersion = WIDGET_SNAPSHOT_SCHEMA,
            generatedAtMs = nowMs,
            expiresAtMs = expiresAtMs,
            locale = locale,
            entries = entries.ifEmpty { listOf(idleEntry(nowMs, expiresAtMs)) },
            upcoming = upcoming.items(nowMs, current, upcomingExpiry, futureShifts),
        )

        fun recurring(initial: ShiftSnapshot, futureShifts: List<WidgetShift>): WidgetSnapshot {
            val expiresAtMs = horizon(nowMs, zone)
            val forced = session.isForcedWorkday(initial)
            val earlyOff = if (session.isEndedEarly(initial)) session.state.earlyOffAtMs?.toLong() else null
            // An early clock-off ends that shift only; the rest of the workday is "done for today".
            if (earlyOff != null) {
                cursor = maxOf(cursor, earlyOff)
                appendDone(cursor, initial.endAtMs.toLong(), futureShifts.firstOrNull()?.startAtMs?.toLong(), expiresAtMs)
            } else if (initial.isWorkday || forced) {
                appendShift(projection(initial), futureShifts.firstOrNull()?.startAtMs?.toLong(), expiresAtMs)
            }
            for ((index, next) in futureShifts.withIndex()) {
                val start = next.startAtMs.toLong()
                if (start <= nowMs || !(start > cursor || next.endAtMs.toLong() > cursor)) continue
                appendCountdown(start, next.countdownAnchorAtMs.toLong(), expiresAtMs)
                if (start >= expiresAtMs) break
                appendShift(next, futureShifts.getOrNull(index + 1)?.startAtMs?.toLong(), expiresAtMs)
            }
            if (cursor < expiresAtMs) entries += idleEntry(cursor, expiresAtMs)
            return snapshot(expiresAtMs, initial, futureShifts)
        }

        fun single(shift: ShiftSnapshot): WidgetSnapshot {
            val rollover = nextMidnight(shift.endAtMs.toLong(), zone)
            val expiresAtMs = maxOf(rollover + DAY_MS, nowMs + 3_600_000)
            appendShift(projection(shift), null, expiresAtMs)
            if (cursor < expiresAtMs) entries += idleEntry(cursor, expiresAtMs)
            return snapshot(expiresAtMs, shift)
        }

        fun inactive(shift: ShiftSnapshot?): WidgetSnapshot {
            if (!session.followsSchedule(nowMs.toDouble()) || shift == null) return idle()
            val anchor = (shift.countdownAnchorAtMs ?: shift.startAtMs).toLong()
            val start = shift.startAtMs.toLong()
            if (shift.isWorkday && start > nowMs) return countdownTo(start, anchor)
            shift.nextShiftStartAtMs?.toLong()?.takeIf { it > nowMs }?.let { return countdownTo(it, anchor) }
            return idle()
        }

        fun idle(): WidgetSnapshot {
            val expiresAtMs = nowMs + DAY_MS
            entries += idleEntry(nowMs, expiresAtMs)
            return snapshot(expiresAtMs, null)
        }

        private fun countdownTo(target: Long, anchor: Long): WidgetSnapshot {
            val expiresAtMs = maxOf(nowMs + 60_000, target)
            appendCountdown(target, anchor, expiresAtMs)
            return snapshot(expiresAtMs, session.snapshot(nowMs.toDouble()), upcomingExpiry = null)
        }

        private fun projection(shift: ShiftSnapshot) = WidgetShift(
            segments = shift.segments,
            startAtMs = shift.startAtMs,
            endAtMs = shift.endAtMs,
            plannedEndAtMs = shift.plannedEndAtMs,
            overtimeEndAtMs = shift.overtimeEndAtMs,
            durationMs = shift.durationMs,
            countdownAnchorAtMs = shift.countdownAnchorAtMs ?: shift.startAtMs,
        )

        /** Whole calendar days before the workday read as rest; from its midnight, the pre-work countdown. */
        private fun appendCountdown(target: Long, anchor: Long, expiresAtMs: Long) {
            if (cursor >= target || cursor >= expiresAtMs) return
            val targetDay = startOfDay(target, zone)
            val restEnd = minOf(targetDay, minOf(target, expiresAtMs))
            if (cursor < restEnd) {
                entries += countdownEntry(cursor, restEnd, target, anchor, targetDay, "widgetRestDay")
                cursor = restEnd
            }
            val countdownEnd = minOf(target, expiresAtMs)
            if (cursor < countdownEnd) {
                entries += countdownEntry(cursor, countdownEnd, target, targetDay, target, "nextShiftLabelShort")
                cursor = countdownEnd
            }
        }

        private fun appendShift(shift: WidgetShift, nextShiftStart: Long?, expiresAtMs: Long) {
            val shiftStart = shift.startAtMs.toLong()
            if (cursor < shiftStart) appendCountdown(shiftStart, shift.countdownAnchorAtMs.toLong(), expiresAtMs)
            val segments = shift.segments.map { it.startAtMs.toLong() to it.endAtMs.toLong() }
            val duration = maxOf(1L, shift.durationMs.toLong())
            for ((index, segment) in segments.withIndex()) {
                if (cursor >= expiresAtMs) return
                val (segmentStart, segmentEnd) = segment
                val completedBefore = segments.take(index).sumOf { it.second - it.first }
                if (cursor < segmentStart) {
                    val breakStart = maxOf(cursor, if (index == 0) shiftStart else segments[index - 1].second)
                    val breakEnd = minOf(segmentStart, expiresAtMs)
                    if (breakStart < breakEnd) {
                        entries += entry(
                            breakStart, breakEnd, WidgetPhase.BREAK, breakLabel, WidgetCountdownKind.BREAK_ENDS,
                            maxOf(0, duration - completedBefore), completedBefore.toDouble() / duration * 100, segmentStart, segmentStart,
                        )
                        cursor = breakEnd
                    }
                }
                val workStart = maxOf(cursor, segmentStart)
                val workEnd = minOf(segmentEnd, expiresAtMs)
                if (workStart < workEnd) {
                    // Overtime is still working; only its label changes, on the minute it starts.
                    val overtimeStart = if (shift.overtimeEndAtMs == null) workEnd else minOf(maxOf(shift.plannedEndAtMs.toLong(), workStart), workEnd)
                    for ((start, end, label) in listOf(Triple(workStart, overtimeStart, "widgetWorking"), Triple(overtimeStart, workEnd, "overtime"))) {
                        if (start >= end) continue
                        val elapsed = completedBefore + maxOf(0, start - segmentStart)
                        entries += entry(
                            start, end, WidgetPhase.WORKING, label, WidgetCountdownKind.WORK_REMAINING,
                            maxOf(0, duration - elapsed), elapsed.toDouble() / duration * 100, segmentEnd,
                            // The wall-clock clock-off, not start + remaining: remaining skips lunch.
                            shift.endAtMs.toLong(),
                        )
                    }
                    cursor = workEnd
                }
            }
            val end = shift.endAtMs.toLong()
            appendDone(end, end, nextShiftStart, expiresAtMs)
        }

        /** "Done for today" until midnight after the shift's end, or the next shift, whichever is sooner. */
        private fun appendDone(startingAtMs: Long, shiftEndAtMs: Long, nextShiftStart: Long?, expiresAtMs: Long) {
            val doneStart = maxOf(cursor, startingAtMs)
            val doneEnd = minOf(minOf(nextMidnight(shiftEndAtMs, zone), expiresAtMs), nextShiftStart ?: Long.MAX_VALUE)
            if (doneStart < doneEnd) {
                entries += entry(doneStart, doneEnd, WidgetPhase.DONE, "offWorkToday", WidgetCountdownKind.COMPLETE, 0, 100.0, null, null)
                cursor = doneEnd
            }
        }

        private fun countdownEntry(date: Long, end: Long, target: Long, anchor: Long, progressEnd: Long, label: String): WidgetEntry {
            val duration = maxOf(1L, progressEnd - anchor)
            val elapsed = minOf(duration, maxOf(0, date - anchor))
            return entry(date, end, WidgetPhase.BEFORE, label, WidgetCountdownKind.SHIFT_STARTS, maxOf(0, target - date), elapsed.toDouble() / duration * 100, target, target)
        }

        fun idleEntry(date: Long, end: Long) =
            entry(date, end, WidgetPhase.IDLE, "countdownNotStarted", WidgetCountdownKind.NONE, 0, 0.0, null, null)

        private fun entry(
            date: Long, end: Long, phase: WidgetPhase, label: String, kind: WidgetCountdownKind,
            remaining: Long, progress: Double, boundary: Long?, target: Long?,
        ) = WidgetEntry(date, end, phase, label, kind, remaining, target, remaining, progress.coerceIn(0.0, 100.0), boundary)
    }
}
