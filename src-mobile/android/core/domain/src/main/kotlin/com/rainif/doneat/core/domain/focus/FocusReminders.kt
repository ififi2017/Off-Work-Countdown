package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.Reminder
import com.rainif.doneat.core.domain.schedule.ReminderKind

/** Localized copy for focus alerts; the caller formats counts and clock times for its locale. */
interface FocusAlertText {
    val focusTitle: String
    val breakOver: String
    val dayDone: String
    val endedNaturally: String
    val endedAtBoundary: String
    val nextFocus: String
    val breakReminderTitle: String
    fun pomodoro(index: Int, total: Int): String
    fun breakUntil(minutes: Int, endAtMs: Double): String
    fun nextUp(task: String, startAtMs: Long): String
    fun focusBreakBody(minutes: Int): String
}

/** One of the two fixed alert slots a phase owns; fixed slots keep cancellation exact. */
enum class FocusAlertSlot(val raw: String) { END("end"), BREAK_END("breakEnd") }

data class FocusAlert(val slot: FocusAlertSlot, val atMs: Double, val title: String, val body: String) {
    /** Scoped to the session, so a newer phase's alerts never collide with an older phase's. */
    fun id(sessionID: String) = "owc.focus.$sessionID.${slot.raw}"
}

/**
 * The reminders focus owes the user (iOS `FocusStore.focusAlerts` and
 * `FocusStore+BreakTakeover`), as pure reads over the archive.
 */
class FocusReminders(private val env: FocusEnvironment, private val planning: FocusPlanning, private val text: FocusAlertText) {
    private val engine = FocusEngine(env)

    /**
     * Every alert this phase owes, written when it starts: the block's end and,
     * for a completed focus block, the end of the break that follows. A
     * sleeping phone cannot compose the second when the first fires.
     */
    fun alerts(state: RecordState, session: FocusSession): List<FocusAlert> = when (session.kind) {
        FocusSessionKind.FOCUS -> buildList {
            add(blockEndAlert(state, session))
            if (session.plannedEndReason == FocusEndReason.COMPLETED && !engine.completesDay(state, session, session.startedAtMs)) {
                engine.plannedBreakEnd(engine.nextBreakKind(state, session), session.plannedEndAtMs)?.let { add(breakEndAlert(state, it)) }
            }
        }
        FocusSessionKind.SHORT_BREAK, FocusSessionKind.LONG_BREAK -> listOf(breakEndAlert(state, session.plannedEndAtMs))
    }

    private fun blockEndAlert(state: RecordState, session: FocusSession): FocusAlert {
        val task = session.taskID?.let { id -> state.focusTasks.firstOrNull { it.id == id } }
        val parts = ArrayList<String>()
        if (task != null) {
            val index = engine.completedBlocks(state, task) + 1
            parts += text.pomodoro(index, maxOf(index, maxOf(1, task.estimatedPomodoros)))
        }
        parts += when {
            engine.completesDay(state, session, session.startedAtMs) -> text.dayDone
            session.plannedEndReason == FocusEndReason.COMPLETED -> {
                val kind = engine.nextBreakKind(state, session)
                engine.plannedBreakEnd(kind, session.plannedEndAtMs)?.let { text.breakUntil(engine.breakMinutes(kind), it) } ?: text.endedNaturally
            }
            else -> text.endedAtBoundary
        }
        return FocusAlert(FocusAlertSlot.END, session.plannedEndAtMs, task?.title ?: text.focusTitle, parts.joinToString(" · "))
    }

    private fun breakEndAlert(state: RecordState, endAtMs: Double): FocusAlert {
        val next = FocusChain.nextPlannedBlock(planning.canvas(state, endAtMs).blocks, endAtMs.toLong())
        val title = next?.taskTitle
        val body = if (next != null && title != null) {
            text.nextUp(title, next.startAtMs)
        } else {
            val done = engine.activeSession(state)?.let { engine.completesDay(state, it, endAtMs) } ?: dayComplete(state, endAtMs)
            if (done) text.dayDone else text.nextFocus
        }
        return FocusAlert(FocusAlertSlot.BREAK_END, endAtMs, text.breakOver, body)
    }

    /** With nothing running, whether the day's last recorded phase finished every planned task. */
    private fun dayComplete(state: RecordState, nowMs: Double): Boolean {
        if (engine.activeSession(state) != null) return false
        val last = engine.sessionsOnDay(state, engine.dayKey(nowMs)).filter { it.endedAtMs != null }.maxByOrNull { it.startedAtMs } ?: return false
        return engine.completesDay(state, last, nowMs)
    }

    /**
     * Whether the pomodoro owns the break rhythm for the shift being drawn.
     * Keyed on the plan, not a running session: reminders are scheduled up
     * front, and someone who plans a day but never presses start is still reminded.
     */
    fun ownsBreaks(state: RecordState, nowMs: Double, microBreakEnabled: Boolean): Boolean {
        if (!microBreakEnabled || !env.isAuthorized) return false
        val shift = planning.canvasShift(nowMs)?.first ?: return false
        return planning.planning(state).plans[engine.dayKey(shift.startAtMs)]?.assignments
            ?.any { it.kind == FocusPlanBlockKind.TASK && it.taskID != null } ?: false
    }

    /**
     * The plan's long breaks, standing in for the fixed-interval health
     * reminder. Short breaks are already announced by the block's own end alert.
     */
    fun breakReminders(state: RecordState, nowMs: Double, microBreakEnabled: Boolean): List<Reminder> {
        if (!ownsBreaks(state, nowMs, microBreakEnabled)) return emptyList()
        val shift = planning.canvasShift(nowMs)?.first ?: return emptyList()
        return planning.blocks(shift, state)
            .filter { it.breakKind == FocusSessionKind.LONG_BREAK && it.startAtMs > nowMs }
            .map { block ->
                Reminder(
                    id = "focusBreak:${block.startAtMs}",
                    kind = ReminderKind.MICRO_BREAK,
                    atMs = block.startAtMs.toDouble(),
                    expiresAtMs = block.endAtMs.toDouble(),
                    maxTickGapMs = null,
                    collapseGroup = "microBreak:focus",
                    title = text.breakReminderTitle,
                    body = text.focusBreakBody(block.durationMinutes),
                )
            }
    }

    /**
     * Swaps fixed-interval health reminders for the plan's breaks over the
     * stretch the plan covers. The next shift is left alone: it rarely has a plan yet.
     */
    fun applyingBreakTakeover(reminders: List<Reminder>, state: RecordState, nowMs: Double, microBreakEnabled: Boolean): List<Reminder> {
        if (!ownsBreaks(state, nowMs, microBreakEnabled)) return reminders
        val shift = planning.canvasShift(nowMs)?.first ?: return reminders
        val start = shift.startAtMs
        val end = shift.segments.maxOfOrNull { it.endAtMs } ?: shift.startAtMs
        val kept = reminders.filter { it.kind != ReminderKind.MICRO_BREAK || it.atMs < start || it.atMs > end }
        return (kept + breakReminders(state, nowMs, microBreakEnabled)).sortedBy { it.atMs }
    }
}

