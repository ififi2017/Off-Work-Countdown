package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind

/** What the ongoing notification shows (iOS `LiveActivitySurface`). */
enum class OngoingSurface { WORK, FOCUS, SHORT_BREAK, LONG_BREAK }

data class OngoingDecision(val surface: OngoingSurface, val endAtMs: Double)

/** When the shift's countdown may show: from [displayStartAtMs] until [endAtMs], the (overtime-aware) clock-off. */
data class OngoingWorkWindow(val displayStartAtMs: Double, val endAtMs: Double)

/**
 * Which countdown the ongoing notification carries (iOS `LiveActivityDecision`
 * and the eligibility in `LiveActivityService.performReschedule`). Pure: the
 * notification itself is the app's.
 */
object OngoingPlan {
    /**
     * A running focus or break phase wins, even near clock-off; otherwise the
     * shift's countdown, only inside its window.
     */
    fun choose(work: OngoingWorkWindow?, focus: FocusSession?, nowMs: Double): OngoingDecision? {
        if (focus != null && focus.endedAtMs == null && focus.plannedEndAtMs > nowMs) {
            val surface = when (focus.kind) {
                FocusSessionKind.FOCUS -> OngoingSurface.FOCUS
                FocusSessionKind.SHORT_BREAK -> OngoingSurface.SHORT_BREAK
                FocusSessionKind.LONG_BREAK -> OngoingSurface.LONG_BREAK
            }
            return OngoingDecision(surface, focus.plannedEndAtMs)
        }
        if (work != null && nowMs >= work.displayStartAtMs && nowMs < work.endAtMs) return OngoingDecision(OngoingSurface.WORK, work.endAtMs)
        return null
    }

    /**
     * The shift's countdown window, [leadMinutes] before the planned clock-off,
     * or null when this shift shows none: not set up or not running, a rest
     * day, before clock-in, already clocked off (early or on time).
     */
    fun workWindow(session: ShiftSession, nowMs: Double, leadMinutes: Int): OngoingWorkWindow? {
        if (!session.env.onboardingComplete || !(session.followsSchedule(nowMs) || session.state.countdownStarted)) return null
        val shift = session.snapshot(nowMs) ?: return null
        val eligible = !session.isEndedEarly(shift) &&
            (shift.isWorkday || session.isForcedWorkday(shift)) &&
            !shift.isBeforeStart(nowMs) &&
            shift.remainingMs > 0
        if (!eligible) return null
        return OngoingWorkWindow(shift.plannedEndAtMs - leadMinutes * 60_000.0, shift.endAtMs)
    }

    /** The next moment the choice can change by itself: a window opening, a phase or the shift ending. */
    fun nextChangeAtMs(work: OngoingWorkWindow?, focus: FocusSession?, nowMs: Double): Double? =
        listOfNotNull(
            focus?.takeIf { it.endedAtMs == null }?.plannedEndAtMs,
            work?.displayStartAtMs,
            work?.endAtMs,
        ).filter { it > nowMs }.minOrNull()
}
