package com.rainif.doneat.ui.timer

import android.content.res.Resources
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.TimelineEvent
import com.rainif.doneat.core.domain.session.TimelineKind
import com.rainif.doneat.l10n.Strings

/**
 * A "coming up" row's title and detail. The timer and the widget word rows
 * the same way; [showsShiftDetail] adds "today's shift" under start and end,
 * which the timer's collapsed list leaves out.
 */
fun timelineWords(event: TimelineEvent, res: Resources, text: TimerText, session: ShiftSession, nowMs: Double, showsShiftDetail: Boolean = true): Pair<String, String?> {
    val extended = session.usesExtendedSchedule(nowMs)
    val breakTitle = res.getString(if (extended) R.string.extendedBreak else R.string.lunchBreak)
    return when (event.kind) {
        TimelineKind.SHIFT_START -> res.getString(R.string.startTime) to res.getString(R.string.todaysShift).takeIf { showsShiftDetail }
        TimelineKind.LUNCH_START -> breakTitle to
            (event.windowEndAtMs?.let { text.timeRange(event.atMs, it) } ?: res.getString(if (extended) R.string.extendedBreakStart else R.string.lunchStartTime))
        TimelineKind.LUNCH_END -> breakTitle to res.getString(R.string.lunchBackAt)
        TimelineKind.HEALTH -> res.getString(R.string.microBreakReminder) to Strings.minutesShort(res, text.count(session.env.preferences.microBreakIntervalMinutes))
        TimelineKind.MILESTONE -> res.getString(R.string.offWorkReminder) to event.reminderTitle
        TimelineKind.SHIFT_END -> res.getString(R.string.endTime) to res.getString(if (event.overtime) R.string.overtime else R.string.todaysShift).takeIf { showsShiftDetail }
    }
}
