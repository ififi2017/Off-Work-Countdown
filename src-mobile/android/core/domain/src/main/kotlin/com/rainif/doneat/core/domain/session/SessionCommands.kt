package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.records.DayOverride
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.SnapshotHours
import com.rainif.doneat.core.domain.records.WorkObservationKind
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import kotlin.math.floor

/** A records write a session command asks for; the store applies it in the same archive write. */
sealed interface SessionRecordEffect {
    /**
     * A use event. [hours] seeds the first career period if the archive has
     * none; the store looks up the snapshot covering [anchorDayKey].
     */
    data class Observation(
        val kind: WorkObservationKind,
        val eventId: String,
        val occurredAtMs: Double,
        val anchorDayKey: String,
        val timeZoneIdentifier: String,
        /** Base64 JSON, as iOS `valueData`. */
        val valueData: String?,
        val hours: SnapshotHours,
    ) : SessionRecordEffect

    /** The timer's marks on today's row (iOS `persistProjectedDayOverride`). */
    data class UpsertOverride(val override: DayOverride) : SessionRecordEffect
}

/**
 * One command's outcome. A rejected command changes nothing.
 * [revokedCompletion] says a completion was taken back (undo, overtime), so
 * the next one celebrates again.
 */
data class SessionResult(
    val accepted: Boolean,
    val state: SessionState,
    val effects: List<SessionRecordEffect> = emptyList(),
    val revokedCompletion: Boolean = false,
)

/**
 * The session commands (iOS `ShiftSessionStore`) as pure transitions. Each
 * reads the session and an instant and returns the next state with the
 * records writes it implies; the store runs both under one lock, so a
 * rejected or blocked command leaves the device state and the archive as
 * they were.
 */
class SessionCommands(private val env: SessionEnvironment, private val newId: () -> String) {
    private fun session(state: SessionState) = ShiftSession(state, env)

    private fun rejected(state: SessionState) = SessionResult(false, state)

    /** `countdownStarted`'s setter: a run that starts gets a new identity. */
    private fun started(state: SessionState) = if (state.countdownStarted) state else state.copy(countdownStarted = true, sessionId = newId())

    private fun withActiveBoundary(state: SessionState, nowMs: Double) =
        state.copy(activeCountdownEndAtMs = session(state).snapshot(nowMs)?.endAtMs)

    private fun lockingSessionZone(state: SessionState, zone: String, nowMs: Double): SessionState {
        val locked = state.copy(sessionTimeZone = zone)
        return locked.copy(sessionTimeZoneUntilMs = session(locked).snapshot(nowMs)?.endAtMs)
    }

    private fun observation(state: SessionState, kind: WorkObservationKind, atMs: Double, valueData: String? = null): SessionRecordEffect? {
        if (!env.collectsObservations) return null
        val s = session(state)
        val anchor = s.snapshot(atMs)?.startAtMs ?: atMs
        val zone = s.timeZoneIdentifierForWriting()
        return SessionRecordEffect.Observation(
            kind, newId(), atMs, ShiftSession.dayKey(anchor, FoundationCompat.javaZone(zone)), zone, valueData, s.hoursConfiguration(atMs),
        )
    }

    private fun projectedOverride(state: SessionState, nowMs: Double): SessionRecordEffect? =
        session(state).projectedDayOverride(nowMs)?.let(SessionRecordEffect::UpsertOverride)

    /**
     * Starts the countdown: arms the schedule, starts a manual run, or with
     * [force] works a rest day. Repeating an accepted start is a no-op.
     */
    fun start(state: SessionState, nowMs: Double, force: Boolean = false): SessionResult {
        val current = session(state)
        val mode = current.scheduleMode
        val startsManualSession = mode == ScheduleMode.OFF && (state.sessionTimeZone == null || state.earlyOffAtMs != null)
        if (!startsManualSession && state.countdownStarted) {
            val shift = current.snapshot(nowMs)
            if (shift != null && state.activeCountdownEndAtMs == shift.endAtMs && force == current.isForcedWorkday(shift)) return rejected(state)
        }
        var s = state
        // A manual start is a new run; a leftover early clock-off would pin it to settlement.
        if (mode == ScheduleMode.OFF) s = s.clearingEarlyClockOff().clearingEarlyClockIn()
        val wasRunning = s.countdownStarted
        s = s.copy(countdownStarted = true, sessionId = newId())
        if ((force || mode == ScheduleMode.OFF) && (!wasRunning || s.sessionTimeZone == null)) {
            s = lockingSessionZone(s, current.timeZoneIdentifierForWriting(startingNewSession = true), nowMs)
        }
        val shift = session(s).snapshot(nowMs)
        // The day the shift starts, not the day the button was pressed: they differ after midnight.
        s = s.copy(forcedWorkdayDate = if (force) ShiftSession.dayKey(shift?.startAtMs ?: nowMs, session(s).countdownZone) else null)
        // The same shift with nudged hours keeps its early clock-off, so settlement stays on this run.
        if (shift == null || !session(s).isEndedEarly(shift)) s = s.clearingEarlyClockOff()
        s = withActiveBoundary(s, nowMs)
        return SessionResult(true, s, listOfNotNull(observation(s, WorkObservationKind.COUNTDOWN_STARTED, nowMs), projectedOverride(s, nowMs)))
    }

    /** Ends the current shift now. Overtime and a forced rest-day run stay until settlement. */
    fun clockOffEarly(state: SessionState, nowMs: Double): SessionResult {
        val current = session(state)
        val shift = current.snapshot(nowMs) ?: return rejected(state)
        if (shift.isBeforeStart(nowMs) || current.isEndedEarly(shift)) return rejected(state)
        val s = state.copy(
            earlyOffAtMs = nowMs,
            earlyOffShiftEndAtMs = shift.endAtMs,
            earlyOffSnapshot = shift,
            forcedWorkdayDate = if (current.isForcedWorkday(shift)) state.forcedWorkdayDate else null,
        )
        return SessionResult(true, s, listOfNotNull(observation(s, WorkObservationKind.COUNTDOWN_STOPPED, nowMs), projectedOverride(s, nowMs)))
    }

    /** Its own action: editing the schedule never quietly resurrects today. */
    fun undoEarlyClockOff(state: SessionState, nowMs: Double): SessionResult {
        if (state.earlyOffAtMs == null) return rejected(state)
        return SessionResult(true, withActiveBoundary(state.clearingEarlyClockOff(), nowMs), revokedCompletion = true)
    }

    /** Moves the start to now (floored to the minute) and keeps the planned end. */
    fun clockInEarly(state: SessionState, nowMs: Double): SessionResult {
        val current = session(state)
        val shift = current.snapshot(nowMs) ?: return rejected(state)
        if (!shift.isBeforeStart(nowMs)) return rejected(state)
        val zone = current.countdownZone
        val s = state.copy(
            earlyStartAtMs = ShiftSession.floorToMinute(nowMs, zone),
            earlyStartUntilMs = ShiftSession.startOfNextDayMs(shift.endAtMs, zone),
        )
        return SessionResult(true, s, listOfNotNull(observation(s, WorkObservationKind.COUNTDOWN_STARTED, nowMs), projectedOverride(s, nowMs)))
    }

    fun undoEarlyClockIn(state: SessionState, nowMs: Double): SessionResult {
        if (state.earlyStartAtMs == null) return rejected(state)
        return SessionResult(true, withActiveBoundary(state.clearingEarlyClockIn(), nowMs))
    }

    /** Rest-day manual timing only; leaves no "I worked" record. */
    fun cancelManualTiming(state: SessionState, nowMs: Double): SessionResult {
        if (state.forcedWorkdayDate == null) return rejected(state)
        val s = state.copy(forcedWorkdayDate = null, overtimeEndAtMs = null).clearingEarlyClockOff().clearingEarlyClockIn()
        return SessionResult(true, withActiveBoundary(s, nowMs))
    }

    /** Stops a manual run. A followed schedule has no run to stop. */
    fun stop(state: SessionState, nowMs: Double, recordObservation: Boolean = true): SessionResult {
        if (!state.countdownStarted || session(state).followsSchedule(nowMs)) return rejected(state)
        val s = stoppedUnscheduled(state)
        val effects = if (recordObservation) listOfNotNull(observation(s, WorkObservationKind.COUNTDOWN_STOPPED, nowMs)) else emptyList()
        return SessionResult(true, s, effects)
    }

    private fun stoppedUnscheduled(state: SessionState) = state.copy(
        countdownStarted = false, forcedWorkdayDate = null, activeCountdownEndAtMs = null, overtimeEndAtMs = null,
    ).clearingEarlyClockIn().clearingEarlyClockOff().clearingSessionTimeZone()

    /**
     * Sets or moves the overtime end. After an early clock-off it means "I
     * wasn't done", so the clock-off is taken back.
     */
    fun applyOvertime(state: SessionState, endAtMs: Double, declaredAtMs: Double): SessionResult {
        if (!endAtMs.isFinite() || (state.overtimeEndAtMs == endAtMs && state.earlyOffAtMs == null)) return rejected(state)
        var s = started(state).copy(overtimeEndAtMs = endAtMs, activeCountdownEndAtMs = endAtMs)
        if (s.sessionTimeZone != null) s = s.copy(sessionTimeZoneUntilMs = endAtMs)
        s = s.clearingEarlyClockOff()
        val planned = session(s).snapshot(declaredAtMs)?.plannedEndAtMs
        val payload = FoundationCompat.base64(overtimePayload(endAtMs, planned).toByteArray(Charsets.UTF_8))
        return SessionResult(
            true, s, listOfNotNull(observation(s, WorkObservationKind.OVERTIME_DECLARED, declaredAtMs, payload)), revokedCompletion = true,
        )
    }

    fun clearOvertime(state: SessionState, nowMs: Double): SessionResult {
        if (state.overtimeEndAtMs == null) return rejected(state)
        val s = state.copy(overtimeEndAtMs = null)
        return SessionResult(true, if (s.countdownStarted) withActiveBoundary(s, nowMs) else s)
    }

    /** Arms a scheduled countdown once setup is done. */
    fun finishSetup(state: SessionState, nowMs: Double): SessionResult =
        if (session(state).scheduleMode != ScheduleMode.OFF && !state.countdownStarted) start(state, nowMs) else rejected(state)

    /**
     * Housekeeping on launch, resume and each shift boundary. A scheduled
     * countdown stays armed across days, but one-off state (overtime, a forced
     * rest day, an early clock-off, kept hours) is scoped to the shift that
     * made it. A manual run resets after its end day. Returns whether anything changed.
     */
    fun reconcile(state: SessionState, nowMs: Double): SessionResult {
        var s = state
        // A finished manual run stays on its own civil day until the midnight reset.
        if (session(s).followsSchedule(nowMs)) {
            s.sessionTimeZoneUntilMs?.let { until -> if (nowMs >= until) s = s.clearingSessionTimeZone() }
        }
        s.todayOverride?.let { kept ->
            if (nowMs >= kept.untilMs) {
                s = s.copy(todayOverride = null)
                if (session(s).scheduleMode == ScheduleMode.OFF) s = stoppedUnscheduled(s)
            }
        }
        s.earlyStartUntilMs?.let { until -> if (nowMs >= until) s = s.clearingEarlyClockIn() }

        val current = session(s)
        if (!s.countdownStarted && !current.followsSchedule(nowMs)) return changed(state, s.copy(activeCountdownEndAtMs = null))

        val zone = current.countdownZone
        if (current.followsSchedule(nowMs)) {
            s.overtimeEndAtMs?.let { end -> if (nowMs >= ShiftSession.startOfNextDayMs(end, zone)) s = s.copy(overtimeEndAtMs = null) }
            // Everything below compares against a shift; without one nothing is deleted.
            val shift = session(s).snapshot(nowMs) ?: return changed(state, s)
            if (s.forcedWorkdayDate != null && !session(s).isForcedWorkday(shift)) s = s.copy(forcedWorkdayDate = null)
            if (s.earlyOffAtMs != null && !session(s).isEndedEarly(shift)) s = s.clearingEarlyClockOff()
            return changed(state, s.copy(activeCountdownEndAtMs = shift.endAtMs))
        }

        val active = s.activeCountdownEndAtMs
        if (active == null) {
            // An early clock-off that lost its boundary still waits for its end day's midnight.
            (s.earlyOffShiftEndAtMs ?: s.earlyOffAtMs)?.let { end ->
                return if (nowMs >= ShiftSession.startOfNextDayMs(end, zone)) changed(state, stoppedUnscheduled(s)) else changed(state, s)
            }
            val shift = current.snapshot(nowMs)
            if (shift == null || shift.remainingMs <= 0 || shift.startAtMs > nowMs) return changed(state, stoppedUnscheduled(s))
            return changed(state, s.copy(activeCountdownEndAtMs = shift.endAtMs))
        }
        if (nowMs < ShiftSession.startOfNextDayMs(active, zone)) return changed(state, s)
        return changed(state, stoppedUnscheduled(s))
    }

    private fun changed(before: SessionState, after: SessionState) = SessionResult(after != before, after)

    companion object {
        /** iOS `OvertimeDeclarationPayload`; integral instants are written without a fraction, as `JSONEncoder` does. */
        fun overtimePayload(overtimeEndAtMs: Double, plannedEndAtMs: Double?): String {
            fun number(v: Double) = if (v == floor(v) && kotlin.math.abs(v) < 1e15) v.toLong().toString() else v.toString()
            val planned = plannedEndAtMs?.let { ",\"plannedEndAtMs\":${number(it)}" } ?: ""
            return "{\"overtimeEndAtMs\":${number(overtimeEndAtMs)}$planned}"
        }
    }
}
