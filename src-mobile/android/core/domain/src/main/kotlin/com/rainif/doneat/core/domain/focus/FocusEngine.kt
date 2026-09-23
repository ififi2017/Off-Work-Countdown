package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.FocusTask
import com.rainif.doneat.core.domain.records.FocusTimerSettings
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import java.time.Instant
import java.util.Locale
import java.util.UUID

/** The shift a focus phase lives in, from the schedule rules' snapshot. */
data class FocusShift(
    val segments: List<ShiftSegment>,
    val startAtMs: Double,
    val endAtMs: Double,
    val remainingMs: Double,
    val nextShiftStartAtMs: Double?,
    /** The app's own workday answer for this shift (scheduled, or forced by manual timing). */
    val isWorkday: Boolean,
)

/**
 * What the focus lifecycle reads from outside the archive. Nothing here reads
 * a clock: every operation takes `nowMs`.
 */
interface FocusEnvironment {
    /** The shift at an instant, or null when the rules have none to show (iOS `snapshot(at:)` gated by `shouldQuerySnapshot`). */
    fun shift(atMs: Double): FocusShift?
    fun scheduleEnabled(atMs: Double): Boolean
    val overtimeEndAtMs: Double?
    val isAuthorized: Boolean
    /** The records zone, a Foundation identifier. */
    val recordsTimeZone: String
    val settings: FocusTimerSettings
    /** Plan-driven sessions queued for later in the shift (T13b); none until planning lands. */
    fun pendingScheduled(): List<FocusSession> = emptyList()
    fun newId(): String = UUID.randomUUID().toString().uppercase(Locale.ROOT)
}

/** The call to action after a phase ends; in-memory, restored from history on launch. */
enum class FocusNextAction { START_SHORT_BREAK, START_LONG_BREAK, START_NEXT_FOCUS, NONE }

sealed interface FocusStartAvailability {
    data object Ready : FocusStartAvailability
    data object Running : FocusStartAvailability
    data object BlockedByOther : FocusStartAvailability
    data object Completed : FocusStartAvailability
    data object NoRoom : FocusStartAvailability
    data class NotYetAvailable(val atMs: Double) : FocusStartAvailability
}

data class FocusStep(val state: RecordState, val nextAction: FocusNextAction, val ok: Boolean = true)

/**
 * The focus session lifecycle (iOS `FocusStore`'s start, stop, natural end,
 * automatic break and reconciliation), as pure transitions over the archive.
 *
 * The invariants it keeps: at most one open session; a block ends at its own
 * planned end however late the app wakes; a completed block counts once and a
 * cut or stopped one never; a task completes only when its estimate is met;
 * an automatic break has an identity derived from the block, so two devices
 * write one break; nothing starts outside work time or with under a minute.
 */
class FocusEngine(private val env: FocusEnvironment) {
    private val settings get() = env.settings.normalized

    fun activeSession(state: RecordState): FocusSession? =
        state.focusSessions.filter { it.endedAtMs == null }.minWithOrNull(compareBy<FocusSession> { it.startedAtMs }.thenBy { it.id })

    /** Finished blocks for a task: completed focus sessions only. */
    fun completedBlocks(state: RecordState, task: FocusTask) =
        state.focusSessions.count { it.taskID == task.id && it.kind == FocusSessionKind.FOCUS && it.endReason == FocusEndReason.COMPLETED }

    // Where a phase may start

    fun isWithinWorkTime(nowMs: Double): Boolean {
        val shift = env.shift(nowMs) ?: return false
        return FocusPlanner.isInsideWork(nowMs, shift.segments, env.overtimeEndAtMs)
    }

    /** The room check `start` uses, so a button can disable before a tap that would be refused. */
    fun hasRoom(nowMs: Double): Boolean {
        val shift = env.shift(nowMs) ?: return false
        if (!shift.isWorkday || !FocusPlanner.isInsideWork(nowMs, shift.segments, env.overtimeEndAtMs)) return false
        if (shift.remainingMs < 60_000) return false
        return FocusPlanner.plannedEnd(nowMs, shift.segments, env.overtimeEndAtMs, settings.focusMinutes) - nowMs >= 60_000
    }

    /** An exact future slot is stronger than its day; a task planned for a later day waits for that day. */
    private fun unavailableUntil(task: FocusTask, nowMs: Double): Double? {
        task.scheduledStartAtMs?.let { if (it > nowMs) return it }
        val planned = task.plannedForDate ?: return null
        return if (planned > dayKey(nowMs)) startOfDayMs(planned) else null
    }

    fun availability(state: RecordState, task: FocusTask, nowMs: Double): FocusStartAvailability {
        if (task.completedAtMs != null || task.deletedAtMs != null) return FocusStartAvailability.Completed
        unavailableUntil(task, nowMs)?.let { return FocusStartAvailability.NotYetAvailable(it) }
        activeSession(state)?.let { return if (it.taskID == task.id) FocusStartAvailability.Running else FocusStartAvailability.BlockedByOther }
        return if (hasRoom(nowMs)) FocusStartAvailability.Ready else FocusStartAvailability.NoRoom
    }

    // Starting

    /**
     * Starts a focus block for [taskID]. A plan-driven start passes the block's
     * own end, which it may not pass; otherwise the phase runs its configured
     * length up to the next boundary.
     */
    fun startFocus(state: RecordState, next: FocusNextAction, taskID: String, nowMs: Double, blockEndMs: Double? = null): FocusStep {
        val refused = FocusStep(state, next, ok = false)
        if (!env.isAuthorized) return refused
        val task = state.focusTasks.firstOrNull { it.id == taskID } ?: return refused
        if (activeSession(state) != null || task.completedAtMs != null || task.deletedAtMs != null) return refused
        if (unavailableUntil(task, nowMs) != null || !hasRoom(nowMs)) return refused
        val freeEnd = FocusPlanner.plannedEnd(nowMs, env.shift(nowMs)?.segments.orEmpty(), env.overtimeEndAtMs, settings.focusMinutes)
        val planned = minOf(blockEndMs ?: freeEnd, freeEnd)
        if (planned - nowMs < 60_000) return refused
        val session = newSession(
            id = env.newId(), taskID = task.id, kind = FocusSessionKind.FOCUS, startMs = nowMs, plannedEndMs = planned,
            plannedEndReason = if (blockEndMs == planned) FocusEndReason.COMPLETED else FocusPlanner.endReason(nowMs, planned, settings.focusMinutes),
        )
        return FocusStep(upsertSession(state, session, nowMs), FocusNextAction.NONE)
    }

    fun breakMinutes(kind: FocusSessionKind) = if (kind == FocusSessionKind.SHORT_BREAK) settings.shortBreakMinutes else settings.longBreakMinutes

    /** Where a recovery phase starting at [atMs] would end, under the same constraints as starting one; null when it cannot run a minute. */
    fun plannedBreakEnd(kind: FocusSessionKind, atMs: Double): Double? {
        if (kind == FocusSessionKind.FOCUS || !env.scheduleEnabled(atMs)) return null
        val shift = env.shift(atMs) ?: return null
        if (!shift.isWorkday || !FocusPlanner.isInsideWork(atMs, shift.segments, env.overtimeEndAtMs)) return null
        val planned = FocusPlanner.plannedEnd(atMs, shift.segments, env.overtimeEndAtMs, breakMinutes(kind))
        val gridBreak = FocusPlanner.workBlocks(shift.segments, settings)
            .firstOrNull { it.breakKind != null && it.startAtMs <= atMs && atMs < it.endAtMs }
        val end = minOf(gridBreak?.endAtMs?.toDouble() ?: planned, planned)
        return if (end - atMs >= 60_000) end else null
    }

    /** The grid's own break after this block, else the day's round count against the long-break cadence. */
    fun nextBreakKind(state: RecordState, session: FocusSession): FocusSessionKind {
        val blocks = env.shift(session.startedAtMs)?.let { FocusPlanner.workBlocks(it.segments, settings) }.orEmpty()
        val index = blocks.indexOfFirst {
            it.breakKind == null && it.startAtMs <= session.startedAtMs && it.endAtMs.toDouble() == session.plannedEndAtMs
        }
        blocks.getOrNull(index + 1)?.takeIf { index >= 0 }?.breakKind?.let { return it }
        val rounds = sessionsOnDay(state, session.anchorDayKey).count {
            it.id != session.id && it.kind == FocusSessionKind.FOCUS && it.endReason == FocusEndReason.COMPLETED
        } + 1
        return if (rounds % settings.longBreakEvery == 0) FocusSessionKind.LONG_BREAK else FocusSessionKind.SHORT_BREAK
    }

    /** Starts the break the last action offered; [id] is the derived identity for an automatic one. */
    fun startBreak(state: RecordState, next: FocusNextAction, kind: FocusSessionKind, nowMs: Double, id: String? = null): FocusStep {
        val required = if (kind == FocusSessionKind.SHORT_BREAK) FocusNextAction.START_SHORT_BREAK else FocusNextAction.START_LONG_BREAK
        val planned = plannedBreakEnd(kind, nowMs)
        if (kind == FocusSessionKind.FOCUS || next != required || activeSession(state) != null || planned == null) return FocusStep(state, next, ok = false)
        val session = newSession(id ?: env.newId(), null, kind, nowMs, planned, FocusPlanner.endReason(nowMs, planned, breakMinutes(kind)))
        return FocusStep(upsertSession(state, session, nowMs), FocusNextAction.NONE)
    }

    // Ending

    /**
     * Ends the open phase. A completed focus block may complete its task (only
     * once its estimate is met) and earns a recovery break, which starts at
     * the block's planned end if that window is still open at [observedAtMs].
     */
    fun stop(state: RecordState, reason: FocusEndReason, nowMs: Double, observedAtMs: Double? = null): FocusStep {
        val open = activeSession(state) ?: return FocusStep(state, FocusNextAction.NONE, ok = false)
        val ended = open.copy(endedAtMs = nowMs, endReason = reason, actualDurationSeconds = maxOf(0, ((nowMs - open.startedAtMs) / 1_000).toInt()))
        var next = upsertSession(state, ended, nowMs)
        if (ended.kind != FocusSessionKind.FOCUS) return FocusStep(next, FocusNextAction.START_NEXT_FOCUS)
        val taskID = ended.taskID
        val task = taskID?.let { id -> next.focusTasks.firstOrNull { it.id == id } }
        if (reason != FocusEndReason.COMPLETED || task == null) return FocusStep(next, FocusNextAction.NONE)
        if (completedBlocks(next, task) >= maxOf(1, task.estimatedPomodoros)) {
            next = upsertTask(next, task.copy(completedAtMs = nowMs), nowMs)
        }
        if (completesDay(next, ended, nowMs)) return FocusStep(next, FocusNextAction.NONE)
        val kind = nextBreakKind(next, ended)
        val observed = observedAtMs ?: nowMs
        val suggested = if (kind == FocusSessionKind.LONG_BREAK) FocusNextAction.START_LONG_BREAK else FocusNextAction.START_SHORT_BREAK
        val action = if (plannedBreakEnd(kind, observed) == null) FocusNextAction.NONE else suggested
        // The break starts where the block ended, where the lock screen has been counting it
        // down; whether it may start at all is judged at the moment the app came back.
        val breakEnd = plannedBreakEnd(kind, ended.plannedEndAtMs)
        if (breakEnd != null && breakEnd > observed) {
            val started = startBreak(next, suggested, kind, ended.plannedEndAtMs, FocusSessionIdentity.recovery(ended.id, kind))
            if (started.ok) return started
        }
        return FocusStep(next, action)
    }

    /**
     * The one place a phase ends by itself: at its own planned end, with the
     * reason it was planned for, however late the app wakes.
     */
    fun finishElapsed(state: RecordState, next: FocusNextAction, nowMs: Double): FocusStep {
        val open = activeSession(state)
        if (open == null || open.plannedEndAtMs > nowMs) return FocusStep(state, next, ok = false)
        return stop(state, open.plannedEndReason, open.plannedEndAtMs, observedAtMs = nowMs)
    }

    /** Stops the running phase by hand; a skipped break returns to focus. */
    fun skipPhase(state: RecordState, next: FocusNextAction, nowMs: Double): FocusStep {
        val open = activeSession(state) ?: return FocusStep(state, next, ok = false)
        val stopped = stop(state, FocusEndReason.STOPPED_BY_USER, nowMs)
        return if (open.kind == FocusSessionKind.FOCUS) stopped else stopped.copy(nextAction = FocusNextAction.START_NEXT_FOCUS)
    }

    /** Declines an offered break without writing an immediately stopped one. */
    fun skipSuggestedBreak(state: RecordState, next: FocusNextAction): FocusStep {
        val offered = next == FocusNextAction.START_SHORT_BREAK || next == FocusNextAction.START_LONG_BREAK
        if (activeSession(state) != null || !offered) return FocusStep(state, next, ok = false)
        return FocusStep(state, FocusNextAction.START_NEXT_FOCUS)
    }

    /**
     * After launch, import or a sync batch: exactly one open session survives
     * (the earliest, then lowest id); the rest end as `supersededBySync` and
     * stay as history. An elapsed survivor finishes at its planned end, and
     * the next action is read back from history.
     */
    fun reconcile(state: RecordState, nowMs: Double): FocusStep {
        val open = state.focusSessions.filter { it.endedAtMs == null }.sortedWith(compareBy<FocusSession> { it.startedAtMs }.thenBy { it.id })
        val winner = open.firstOrNull() ?: return FocusStep(state, restoreNextAction(state, nowMs))
        var next = state
        for (losing in open.drop(1)) {
            next = upsertSession(
                next,
                losing.copy(endedAtMs = nowMs, endReason = FocusEndReason.SUPERSEDED_BY_SYNC, actualDurationSeconds = maxOf(0, ((nowMs - losing.startedAtMs) / 1_000).toInt())),
                nowMs,
            )
        }
        if (winner.plannedEndAtMs > nowMs) return FocusStep(next, FocusNextAction.NONE)
        val finished = finishElapsed(next, FocusNextAction.NONE, nowMs)
        // A break that just started is already the answer; otherwise ask history.
        return if (activeSession(finished.state) != null) finished else FocusStep(finished.state, restoreNextAction(finished.state, nowMs))
    }

    /** The next action a cold launch shows, from the latest ended phase on the current shift's day. */
    fun restoreNextAction(state: RecordState, nowMs: Double): FocusNextAction {
        if (activeSession(state) != null) return FocusNextAction.NONE
        val latest = state.focusSessions.filter { it.endedAtMs != null }.maxByOrNull { it.endedAtMs ?: it.startedAtMs } ?: return FocusNextAction.NONE
        val shift = env.shift(nowMs) ?: return FocusNextAction.NONE
        if (latest.shiftAnchorDate != dayKey(shift.startAtMs)) return FocusNextAction.NONE
        return when {
            latest.kind != FocusSessionKind.FOCUS -> FocusNextAction.START_NEXT_FOCUS
            latest.endReason != FocusEndReason.COMPLETED -> FocusNextAction.NONE
            nextBreakKind(state, latest) == FocusSessionKind.LONG_BREAK -> FocusNextAction.START_LONG_BREAK
            else -> FocusNextAction.START_SHORT_BREAK
        }
    }

    // The day

    /** The day a task list is filed under: a night shift's list stays on its start day. */
    private fun taskDay(nowMs: Double): String {
        val shiftStart = canvasShift(nowMs)?.startAtMs ?: nowMs
        return dayKey(minOf(nowMs, shiftStart))
    }

    /** The shift the Focus page shows; after clock-off it moves to the next one. */
    fun canvasShift(nowMs: Double): FocusShift? {
        if (!env.scheduleEnabled(nowMs)) return null
        val current = env.shift(nowMs) ?: return null
        if (nowMs < current.endAtMs && current.isWorkday) return current
        return current.nextShiftStartAtMs?.let { env.shift(it + 1_000) }
    }

    /** Today's tasks: not deleted, not an unplanned favourite template, planned for today or unplanned. */
    fun tasksForToday(state: RecordState, nowMs: Double): List<FocusTask> {
        val today = taskDay(nowMs)
        return FocusPlanner.sortedTasks(
            state.focusTasks.filter { task ->
                task.deletedAtMs == null && !(task.isFavorite && task.plannedForDate == null) &&
                    (task.plannedForDate == null || task.plannedForDate == today)
            },
        )
    }

    /** Whether this phase finishes every task planned today, counting blocks already committed but not yet recorded. */
    fun completesDay(state: RecordState, session: FocusSession, nowMs: Double): Boolean {
        val pending = env.pendingScheduled()
        return tasksForToday(state, nowMs).all { task ->
            if (task.completedAtMs != null) return@all true
            val committed = pending.count { it.taskID == task.id && it.plannedEndAtMs <= session.plannedEndAtMs }
            val current = if (session.endedAtMs == null && session.kind == FocusSessionKind.FOCUS && session.taskID == task.id &&
                session.plannedEndReason == FocusEndReason.COMPLETED && pending.none { it.id == session.id }
            ) 1 else 0
            val running = state.focusSessions.count { r ->
                r.id != session.id && r.taskID == task.id && r.kind == FocusSessionKind.FOCUS && r.endedAtMs == null &&
                    r.plannedEndReason == FocusEndReason.COMPLETED && r.plannedEndAtMs <= session.plannedEndAtMs && pending.none { it.id == r.id }
            }
            completedBlocks(state, task) + committed + current + running >= maxOf(1, task.estimatedPomodoros)
        }
    }

    fun sessionsOnDay(state: RecordState, dayKey: String) =
        state.focusSessions.filter { it.anchorDayKey == dayKey }.sortedWith(compareBy<FocusSession> { it.startedAtMs }.thenBy { it.id })

    // Stamped writes (the coordinator's upserts)

    private fun <T> sameContent(a: T, b: T, blank: (T) -> T) = blank(a) == blank(b)

    fun upsertSession(state: RecordState, draft: FocusSession, nowMs: Double): RecordState {
        val current = state.focusSessions.firstOrNull { it.id == draft.id }
        val blank = { s: FocusSession -> s.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "") }
        if (current != null && sameContent(current, draft, blank)) return state
        val row = draft.copy(editCount = (current?.editCount ?: maxOf(draft.editCount, 0)) + 1, editTieBreaker = env.newId(), editedAtMs = nowMs)
        return state.copy(focusSessions = if (current != null) state.focusSessions.map { if (it === current) row else it } else state.focusSessions + row)
    }

    fun upsertTask(state: RecordState, draft: FocusTask, nowMs: Double): RecordState {
        val current = state.focusTasks.firstOrNull { it.id == draft.id }
        val blank = { t: FocusTask -> t.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "") }
        if (current != null && sameContent(current, draft, blank)) return state
        val row = draft.copy(editCount = (current?.editCount ?: maxOf(draft.editCount, 0)) + 1, editTieBreaker = env.newId(), editedAtMs = nowMs)
        return state.copy(focusTasks = if (current != null) state.focusTasks.map { if (it === current) row else it } else state.focusTasks + row)
    }

    private fun newSession(id: String, taskID: String?, kind: FocusSessionKind, startMs: Double, plannedEndMs: Double, plannedEndReason: FocusEndReason): FocusSession {
        val day = dayKey(startMs)
        return FocusSession(
            id = id, taskID = taskID, shiftAnchorDate = day, startedAtMs = startMs, plannedEndAtMs = plannedEndMs,
            endedAtMs = null, endReason = null, editedAtMs = startMs, editCount = 0, editTieBreaker = env.newId(), kind = kind,
            timeZoneIdentifier = FoundationCompat.timeZoneIdentifier(env.recordsTimeZone) ?: env.recordsTimeZone,
            anchorDayKey = day, actualDurationSeconds = null, plannedEndReason = plannedEndReason,
        )
    }

    private val zone get() = FoundationCompat.javaZone(env.recordsTimeZone)

    fun dayKey(ms: Double): String = FoundationCompat.dayKey(Instant.ofEpochMilli(ms.toLong()).atZone(zone).toLocalDate())

    private fun startOfDayMs(dayKey: String): Double = java.time.LocalDate.parse(dayKey).atStartOfDay(zone).toInstant().toEpochMilli().toDouble()
}
