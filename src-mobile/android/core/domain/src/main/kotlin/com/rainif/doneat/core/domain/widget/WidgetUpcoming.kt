package com.rainif.doneat.core.domain.widget

import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.schedule.WidgetShift
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.TimelineEvent
import com.rainif.doneat.core.domain.session.TimelineKind

/**
 * The widget's "coming up" rows (iOS `upcomingItems`): the timer's own list
 * for the current shift, then start, breaks and clock-off of every later
 * shift in the snapshot, so a large widget still has rows long after the app
 * last ran. Salary-free by construction: rows are times and titles.
 */
class WidgetUpcoming(
    private val session: ShiftSession,
    /** The timer's "coming up" rows for a shift at a moment (reminders included). */
    private val events: (ShiftSnapshot, Double) -> List<TimelineEvent>,
    /** Title and detail for a row, worded as the timer words it. */
    private val words: (TimelineEvent) -> Pair<String, String>,
    private val focusEvents: List<TimelineEvent> = emptyList(),
    private val futureFocus: (WidgetShift) -> List<TimelineEvent> = { emptyList() },
) : WidgetSnapshotComposer.Upcoming {
    override fun items(nowMs: Long, current: ShiftSnapshot?, expiresAtMs: Long?, futureShifts: List<WidgetShift>): List<WidgetUpcomingItem> {
        val items = ArrayList<WidgetUpcomingItem>()
        val seen = HashSet<String>()
        fun add(event: TimelineEvent) {
            val at = event.atMs.toLong()
            if (at <= nowMs || (expiresAtMs != null && at >= expiresAtMs) || !seen.add(event.id)) return
            val (title, detail) = words(event)
            items += WidgetUpcomingItem(event.id, kindKey(event.kind), title, detail, at)
        }
        // A rest day still resolves to a nominal range; it is not a shift anyone is in.
        if (current != null && (current.isWorkday || session.isForcedWorkday(current))) {
            events(current, nowMs.toDouble()).forEach(::add)
        }
        focusEvents.forEach(::add)
        if (futureShifts.isEmpty()) {
            // Manual runs: preview the next shift's own rows.
            val next = current?.nextShiftStartAtMs
            if (next != null && next > nowMs) {
                session.snapshot(next - 1)?.let { preview -> events(preview, next - 1).forEach(::add) }
            }
        } else {
            futureShifts.forEach { shift ->
                boundaries(shift).forEach(::add)
                futureFocus(shift).forEach(::add)
            }
        }
        return items.sortedBy { it.dateMs }
    }

    /** Start, break gaps and clock-off of a precomputed future shift. */
    private fun boundaries(shift: WidgetShift): List<TimelineEvent> = buildList {
        add(TimelineEvent("shift-start-${shift.startAtMs.toLong()}", TimelineKind.SHIFT_START, shift.startAtMs))
        shift.segments.zipWithNext().forEach { (segment, next) ->
            if (next.startAtMs <= segment.endAtMs) return@forEach
            add(TimelineEvent("lunch-start-${segment.endAtMs.toLong()}", TimelineKind.LUNCH_START, segment.endAtMs))
            add(TimelineEvent("lunch-end-${next.startAtMs.toLong()}", TimelineKind.LUNCH_END, next.startAtMs))
        }
        add(TimelineEvent("shift-end-${shift.endAtMs.toLong()}", TimelineKind.SHIFT_END, shift.endAtMs, overtime = shift.overtimeEndAtMs != null))
    }

    companion object {
        /** The contract's kind names (iOS `TimelineEvent.Kind` raw values). */
        fun kindKey(kind: TimelineKind) = when (kind) {
            TimelineKind.SHIFT_START -> "shiftStart"
            TimelineKind.LUNCH_START -> "lunchStart"
            TimelineKind.LUNCH_END -> "lunchEnd"
            TimelineKind.HEALTH -> "microBreak"
            TimelineKind.MILESTONE -> "milestone"
            TimelineKind.SHIFT_END -> "shiftEnd"
            TimelineKind.FOCUS -> "focus"
            TimelineKind.FOCUS_BREAK -> "focusBreak"
        }
    }
}
