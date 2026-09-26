package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.schedule.Reminder
import com.rainif.doneat.core.domain.schedule.ReminderKind
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot

enum class TimelineKind { SHIFT_START, LUNCH_START, LUNCH_END, HEALTH, MILESTONE, SHIFT_END, FOCUS, FOCUS_BREAK }

/**
 * One row of the timer's "coming up" list. The screen supplies the words;
 * [reminderTitle] is the milestone's own push title, and [overtime] marks a
 * shift end that is the overtime end.
 */
data class TimelineEvent(
    val id: String,
    val kind: TimelineKind,
    val atMs: Double,
    val reminderTitle: String? = null,
    val overtime: Boolean = false,
    /** A lunch row that shows its whole window rather than one boundary. */
    val windowEndAtMs: Double? = null,
    val focusTitle: String? = null,
    val focusMinutes: Int = 0,
    val focusPomodoros: Int = 1,
    val runningFocus: Boolean = false,
)

/**
 * The presentation timeline built from shared absolute boundaries (iOS
 * `ShiftSessionStore.upcomingTimelineEvents`). Rows are bounded by the shift,
 * not the calendar day, so an overnight shift keeps its after-midnight break.
 */
object UpcomingTimeline {
    /**
     * @param reminders the rules' reminder list for the current input, so the
     *   rows are exactly what the notifications will say.
     */
    fun events(
        snapshot: ShiftSnapshot,
        nowMs: Double,
        reminders: List<Reminder>,
        microBreakEnabled: Boolean,
        milestonesEnabled: Boolean,
    ): List<TimelineEvent> {
        fun duringShift(atMs: Double) = atMs > nowMs && atMs <= snapshot.endAtMs
        val events = ArrayList<TimelineEvent>()
        if (snapshot.startAtMs > nowMs) {
            events += TimelineEvent("shift-start-${snapshot.startAtMs.toLong()}", TimelineKind.SHIFT_START, snapshot.startAtMs)
        }
        snapshot.segments.zipWithNext().forEach { (segment, next) ->
            if (next.startAtMs <= segment.endAtMs) return@forEach
            if (duringShift(segment.endAtMs)) {
                events += TimelineEvent("lunch-start-${segment.endAtMs.toLong()}", TimelineKind.LUNCH_START, segment.endAtMs)
            }
            if (duringShift(next.startAtMs)) {
                events += TimelineEvent("lunch-end-${next.startAtMs.toLong()}", TimelineKind.LUNCH_END, next.startAtMs)
            }
        }
        // One micro-break row carrying its interval, not one per firing.
        if (microBreakEnabled) {
            reminders.filter { it.kind == ReminderKind.MICRO_BREAK && duringShift(it.atMs) }.minByOrNull { it.atMs }?.let {
                events += TimelineEvent(it.id, TimelineKind.HEALTH, it.atMs)
            }
        }
        // One row per push; a silent tick has no title, and 100% is the end row itself.
        if (milestonesEnabled) {
            reminders.filter {
                it.kind == ReminderKind.MILESTONE && !it.id.endsWith(":milestone:100") && it.title != null && duringShift(it.atMs)
            }.forEach { events += TimelineEvent(it.id, TimelineKind.MILESTONE, it.atMs, reminderTitle = it.title) }
        }
        if (snapshot.endAtMs > nowMs) {
            events += TimelineEvent(
                "shift-end-${snapshot.endAtMs.toLong()}", TimelineKind.SHIFT_END, snapshot.endAtMs, overtime = snapshot.overtimeEndAtMs != null,
            )
        }
        fun order(kind: TimelineKind) = when (kind) {
            TimelineKind.SHIFT_START -> 0
            TimelineKind.SHIFT_END -> 2
            else -> 1
        }
        return events.sortedWith(compareBy<TimelineEvent> { it.atMs }.thenBy { order(it.kind) }.thenBy { it.id })
    }

    /**
     * A rest day's preview of the next working day: its start, its break as
     * one window, and its end (iOS `RestDayUpcomingView`, three rows at most).
     */
    fun nextShiftPreview(next: ShiftSnapshot): List<TimelineEvent> {
        val events = ArrayList<TimelineEvent>()
        events += TimelineEvent("shift-start", TimelineKind.SHIFT_START, next.startAtMs)
        next.segments.zipWithNext().firstOrNull { (a, b) -> b.startAtMs > a.endAtMs }?.let { (a, b) ->
            events += TimelineEvent("lunch", TimelineKind.LUNCH_START, a.endAtMs, windowEndAtMs = b.startAtMs)
        }
        events += TimelineEvent("shift-end", TimelineKind.SHIFT_END, next.endAtMs)
        return events
    }
}
