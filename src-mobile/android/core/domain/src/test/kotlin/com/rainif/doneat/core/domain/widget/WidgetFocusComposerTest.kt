package com.rainif.doneat.core.domain.widget

import com.rainif.doneat.core.domain.focus.*
import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class WidgetFocusComposerTest {
    private fun at(hour: Int, minute: Int = 0) = Instant.parse("2026-10-28T%02d:%02d:00Z".format(hour, minute)).toEpochMilli().toDouble()
    private val now = at(9, 10).toLong()
    private class Env : FocusEnvironment {
        var authorized = true
        var pending = emptyList<FocusSession>()
        override val recordsTimeZone = "UTC"
        override val overtimeEndAtMs: Double? = null
        override val isAuthorized get() = authorized
        override val settings = FocusTimerSettings(25, 5, 15, 4)
        override fun pendingScheduled() = pending
        override fun scheduleEnabled(atMs: Double) = true
        override fun shift(atMs: Double): FocusShift {
            val start = Instant.parse("2026-10-28T09:00:00Z").toEpochMilli().toDouble()
            val lunch = start + 3 * 3_600_000
            val end = start + 8 * 3_600_000
            return FocusShift(listOf(ShiftSegment(start, lunch), ShiftSegment(lunch + 3_600_000, end)), start, end, maxOf(0.0, end - atMs), null, true)
        }
    }
    private val env = Env()
    private fun task(id: String = "task", estimate: Int = 2) = FocusTask(id, at(8), "2026-10-28", at(9), "Write", estimate,
        FocusTaskIcon.WRITING, false, null, null, 0, at(8), 1, id, null, null)
    private fun session(task: String = "task", start: Double = at(9), end: Double = at(9, 25), id: String = "running", reason: FocusEndReason = FocusEndReason.COMPLETED,
                        kind: FocusSessionKind = FocusSessionKind.FOCUS) = FocusSession(id, task, "2026-10-28", start, end, null, null, start, 1, id, kind, "UTC", "2026-10-28", null, reason)
    private fun block(start: Double, end: Double, task: String = "task", userBreak: Boolean = false) = FocusDayCanvas.Block(0, start.toLong(), end.toLong(),
        FocusPlanBlockKind.TASK, FocusDayCanvas.State.FUTURE, taskID = task, taskTitle = "Write", taskIcon = FocusTaskIcon.WRITING, isUserBreak = userBreak)
    private fun canvas(blocks: List<FocusDayCanvas.Block>, locked: Boolean = false) = FocusDayCanvas(at(9).toLong(), at(17).toLong(), "2026-10-28", false, now,
        blocks, emptyList(), emptyList(), emptyList(), 1.0, locked)
    private fun compose(state: RecordState, blocks: List<FocusDayCanvas.Block>, atMs: Long = now) =
        WidgetFocusComposer.compose(state, env, canvas(blocks), atMs, "Focus", "Break")

    @Test fun runningTaskProjectsItsEarnedBreakButNeverStartsTheQueuedTask() {
        val state = RecordState(focusTasks = listOf(task()), focusSessions = listOf(session()))
        val result = compose(state, listOf(block(at(9, 30), at(9, 55))))
        assertEquals(3, result.size)
        assertEquals("Write", result[0].title)
        assertTrue(result[0].isRunning)
        assertEquals(1, result[0].round)
        assertEquals(2, result[0].rounds)
        assertTrue(result[1].isBreak)
        assertTrue(result[1].isRunning)
        assertEquals(at(9, 25).toLong(), result[1].startMs)
        assertEquals(at(9, 30).toLong(), result[1].endMs)
        assertEquals(2, result[2].round)
        assertFalse(result[2].isRunning)
        val payload = WidgetFocusPayload(WidgetAccess(true), result)
        assertEquals(result[1], payload.current(at(9, 27).toLong()))
        assertNull(payload.current(at(9, 35).toLong()))
    }

    @Test fun completingTheDayOrHittingLunchDoesNotInventAnExtraBreak() {
        val complete = compose(RecordState(focusTasks = listOf(task(estimate = 1)), focusSessions = listOf(session())), emptyList())
        assertEquals(1, complete.size)
        val cut = compose(RecordState(focusTasks = listOf(task()), focusSessions = listOf(session(start = at(11, 50), end = at(12), reason = FocusEndReason.STOPPED_AT_BOUNDARY))),
            listOf(block(at(13), at(13, 25))), at(11, 55).toLong())
        assertTrue(cut.none { it.isBreak })
        assertFalse(cut.last().isRunning)
    }

    @Test fun longRecoveryAndRunningRoundUseExistingEngineAndCommittedQueue() {
        val t = task(estimate = 8)
        val finished = session(start = at(9), end = at(9, 25), id = "done").copy(endedAtMs = at(9, 25), endReason = FocusEndReason.COMPLETED)
        env.pending = listOf(session(start = at(9, 30), end = at(9, 55), id = "queued-before"))
        val current = session(start = at(10, 30), end = at(10, 55))
        val result = compose(RecordState(focusTasks = listOf(t), focusSessions = listOf(finished, current)), listOf(block(at(11, 10), at(11, 35))), at(10, 40).toLong())
        assertEquals(3, result.first().round)
        assertEquals(at(11, 10).toLong(), result.first { it.isBreak }.endMs)
    }

    @Test fun plannedSlotsStayPlansAndUserBreaksDeletedTasksAndLockedAccessStayOut() {
        val t = task()
        val c = canvas(listOf(block(at(9), at(9, 25)), block(at(9, 30), at(9, 55), userBreak = true)))
        val planned = WidgetFocusComposer.compose(RecordState(focusTasks = listOf(t)), env, c, at(8).toLong(), "Focus", "Break")
        assertEquals(1, planned.size)
        assertFalse(planned.single().isRunning)
        assertNull(WidgetFocusPayload(WidgetAccess(true), planned).current(now))
        assertTrue(WidgetFocusComposer.compose(RecordState(focusTasks = listOf(t.copy(deletedAtMs = at(8)))), env, c, at(8).toLong(), "Focus", "Break").isEmpty())
        env.authorized = false
        assertTrue(WidgetFocusComposer.compose(RecordState(focusTasks = listOf(t)), env, c, now, "Focus", "Break").isEmpty())
    }
}
