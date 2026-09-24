package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.reminders.PlannedReminder
import com.rainif.doneat.core.domain.reminders.ReminderPlanner
import com.rainif.doneat.core.domain.schedule.Reminder
import com.rainif.doneat.core.domain.schedule.ReminderInputs
import com.rainif.doneat.core.domain.schedule.ScheduleRules

/**
 * The shift alarms the device should hold now (iOS
 * `ShiftSessionStore.shiftReminders` fed to `NotificationService`): the
 * current shift's reminders only while the user is actually in it, plus the
 * next shift's, read from the committed schedule when today keeps other hours.
 */
object ShiftReminderPlan {
    fun reminders(session: ShiftSession, nowMs: Double, inputs: ReminderInputs): List<Reminder> {
        val current = session.snapshot(nowMs)
        val effective = ScheduleRules.reminders(session.rulesInput(nowMs), inputs)
        val nextSource = if (session.projectsFutureFromBase(nowMs)) RulesSource.BASE else RulesSource.EFFECTIVE
        val next = ScheduleRules.reminders(session.rulesInput(nowMs, source = nextSource), inputs)
        // Rest days and settlement still yield a `current:` window from the rules; neither is a shift to remind about.
        val includeCurrent = current == null ||
            ((current.isWorkday || session.isForcedWorkday(current)) && !session.isShiftComplete(current))
        return ReminderPlanner.shiftReminders(effective, next, includeCurrent)
    }

    /** Nothing before setup, or while neither a schedule nor a run is live. */
    fun alarms(session: ShiftSession, nowMs: Double, inputs: ReminderInputs): List<PlannedReminder> {
        if (!session.env.onboardingComplete || !session.shouldQuerySnapshot(nowMs)) return emptyList()
        val current = session.snapshot(nowMs)
        // After an early clock-off only the next shift remains; with no next shift, nothing does.
        val endedEarlyNext = current?.takeIf(session::isEndedEarly)?.let { it.nextShiftStartAtMs ?: Double.POSITIVE_INFINITY }
        return ReminderPlanner.shiftAlarms(reminders(session, nowMs, inputs), nowMs, endedEarlyNext)
    }
}
