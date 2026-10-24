package com.rainif.doneat.review

import com.rainif.doneat.ui.Route

/**
 * What used to discard the offer on main, now a deferral. The timer home is
 * the only clear page. Anywhere else — an editor, the schedule, focus, or
 * another screen — waits for the next qualifying return. A confirmation, the
 * overtime sheet, the invalid-lunch alert or the landscape clock does too.
 */
internal fun reviewSurfaceBlocker(
    onTimerTab: Boolean,
    onFocusTab: Boolean,
    route: Route?,
    timerDialog: Boolean,
    landscapeClock: Boolean,
): ReviewBlocker {
    if (timerDialog || landscapeClock) return ReviewBlocker.DIALOG
    if (onTimerTab && route == Route.TimerHome) return ReviewBlocker.NONE
    return when (route) {
        Route.Schedule, Route.ShiftTypes, is Route.ShiftTypeEdit -> ReviewBlocker.SCHEDULE
        Route.FocusHome, is Route.FocusCreate, is Route.FocusTaskEdit, Route.FocusTimerSettings,
        is Route.FocusTemplateEdit, is Route.FocusTemplateTask -> ReviewBlocker.FOCUS
        is Route.RecordsDayEdit, Route.RecordsLifeEdit, is Route.LeaveBalanceEdit, Route.Salary -> ReviewBlocker.EDITOR
        else -> if (onFocusTab) ReviewBlocker.FOCUS else ReviewBlocker.DIALOG
    }
}
