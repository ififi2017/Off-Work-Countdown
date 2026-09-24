package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.focus.DEFAULT_TIMER_SETTINGS
import com.rainif.doneat.core.domain.focus.FocusEnvironment
import com.rainif.doneat.core.domain.focus.FocusShift
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusTimerSettings
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.ScheduleMode

/**
 * What focus reads from the running countdown (iOS `AppRuntime.focus`
 * sources): the shift at an instant, whether a schedule or a run is live, and
 * whether the day counts as a workday, which an early clock-off ends and a
 * forced rest-day run or a manual run begins.
 */
class SessionFocusEnvironment(
    private val session: ShiftSession,
    private val state: RecordState,
    override val isAuthorized: Boolean,
    private val queued: List<FocusSession> = emptyList(),
    private val id: () -> String,
) : FocusEnvironment {
    override fun shift(atMs: Double): FocusShift? {
        if (!session.shouldQuerySnapshot(atMs)) return null
        val snapshot = session.snapshot(atMs) ?: return null
        val manualRun = session.effectiveScheduleMode(atMs) == ScheduleMode.OFF && session.state.countdownStarted
        return FocusShift(
            segments = snapshot.segments,
            startAtMs = snapshot.startAtMs,
            endAtMs = snapshot.endAtMs,
            remainingMs = snapshot.remainingMs,
            nextShiftStartAtMs = snapshot.nextShiftStartAtMs,
            isWorkday = !session.isEndedEarly(snapshot) && (snapshot.isWorkday || session.isForcedWorkday(snapshot) || manualRun),
        )
    }

    override fun scheduleEnabled(atMs: Double) =
        session.effectiveScheduleMode(atMs) != ScheduleMode.OFF || session.state.countdownStarted

    override val overtimeEndAtMs get() = session.state.overtimeEndAtMs
    override val recordsTimeZone get() = session.env.preferences.recordsTimeZoneIdentifier
    override val settings: FocusTimerSettings
        get() = state.focusPlanningConfiguration?.timerSettings?.normalized ?: DEFAULT_TIMER_SETTINGS

    override fun pendingScheduled() = queued
    override fun newId() = id()
}
