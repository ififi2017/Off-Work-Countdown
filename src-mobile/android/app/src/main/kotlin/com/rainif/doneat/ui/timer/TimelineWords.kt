package com.rainif.doneat.ui.timer

import android.content.res.Resources
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.TimelineCivilCopy
import com.rainif.doneat.core.domain.session.TimelineEvent
import com.rainif.doneat.core.domain.session.TimelineKind
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.l10n.Strings

/**
 * A "coming up" row's title and detail. The timer and the widget word rows
 * the same way; [showsShiftDetail] enables civil-date detail under start and
 * end. A future start's roster status is supplied only by a caller that has
 * confirmed the date's assignment; widgets leave it absent.
 */
fun timelineWords(event: TimelineEvent, res: Resources, text: TimerText, session: ShiftSession, nowMs: Double, showsShiftDetail: Boolean = true, knownRosterStatusKey: String? = null, currentSnapshot: ShiftSnapshot? = null): Pair<String, String?> {
    val extended = session.usesExtendedSchedule(nowMs)
    val breakTitle = res.getString(if (extended) R.string.extendedBreak else R.string.lunchBreak)
    fun detail(key: String?): String? = if (!showsShiftDetail) null else when (key) {
        TimelineCivilCopy.TODAY -> res.getString(R.string.todaysShift)
        TimelineCivilCopy.CURRENT_MONTH -> res.getString(R.string.scheduleCurrentMonthActive)
        TimelineCivilCopy.NEXT_MONTH -> res.getString(R.string.scheduleNextMonthPlanned)
        else -> null
    }
    return when (event.kind) {
        TimelineKind.SHIFT_START -> res.getString(R.string.startTime) to
            detail(TimelineCivilCopy.startDetailKey(event.atMs, nowMs, session.countdownZone, knownRosterStatusKey))
        TimelineKind.LUNCH_START -> breakTitle to
            (event.windowEndAtMs?.let { text.timeRange(event.atMs, it) } ?: res.getString(if (extended) R.string.extendedBreakStart else R.string.lunchStartTime))
        TimelineKind.LUNCH_END -> breakTitle to res.getString(R.string.lunchBackAt)
        TimelineKind.HEALTH -> res.getString(R.string.microBreakReminder) to Strings.minutesShort(res, text.count(session.env.preferences.microBreakIntervalMinutes))
        TimelineKind.MILESTONE -> res.getString(R.string.offWorkReminder) to event.reminderTitle
        TimelineKind.SHIFT_END -> res.getString(R.string.endTime) to if (event.overtime) {
            res.getString(R.string.overtime).takeIf { showsShiftDetail }
        } else {
            val current = currentSnapshot ?: session.snapshot(nowMs)
            detail(current?.let {
                TimelineCivilCopy.endDetailKey(event.atMs, it.startAtMs, it.endAtMs, session.isEndedEarly(it), nowMs, session.countdownZone)
            })
        }
        TimelineKind.FOCUS, TimelineKind.FOCUS_BREAK -> {
            val title = when {
                event.runningFocus -> res.getString(R.string.focusRunning)
                event.kind == TimelineKind.FOCUS_BREAK -> res.getString(R.string.focusBreak)
                else -> event.focusTitle ?: res.getString(R.string.focusTitle)
            }
            title to if (event.runningFocus) Strings.focusEndsAt(res, text.time(event.atMs))
                else Strings.focusPomodoroSummary(res, text.count(event.focusPomodoros), text.count(event.focusMinutes))
        }
    }
}
