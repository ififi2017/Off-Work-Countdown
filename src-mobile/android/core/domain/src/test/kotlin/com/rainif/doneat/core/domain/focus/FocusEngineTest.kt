package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.FocusTask
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.FocusTimerSettings
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.WallClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

/** The lifecycle behaviours named by iOS `FocusStoreTests` and the review regressions, against [FocusEngine]. */
class FocusEngineTest {
    private val zone = "Asia/Shanghai"
    private val civil = CivilZone(ZoneId.of(zone))
    private fun at(day: String, hour: Int, minute: Int = 0) = civil.utcMs(ExtendedScheduleResolver.dayNumber(day)!!, WallClock(hour, minute))
    private val minute = 60_000.0

    /** Monday 2026-08-24 and Tuesday 2026-08-25: 09:00–12:00 and 13:00–18:00. */
    private inner class Env(var authorized: Boolean = true, var settings0: FocusTimerSettings = DEFAULT_TIMER_SETTINGS) : FocusEnvironment {
        private var ids = 0
        private fun shiftOn(day: String) = FocusShift(
            listOf(ShiftSegment(at(day, 9), at(day, 12)), ShiftSegment(at(day, 13), at(day, 18))),
            at(day, 9), at(day, 18), 0.0, if (day == "2026-08-24") at("2026-08-25", 9) else null, true,
        )
        override fun shift(atMs: Double): FocusShift? {
            val day = listOf("2026-08-24", "2026-08-25").firstOrNull { atMs >= at(it, 0) && atMs < at(it, 0) + 86_400_000 } ?: return null
            return shiftOn(day).let { it.copy(remainingMs = maxOf(0.0, it.endAtMs - atMs)) }
        }
        override fun scheduleEnabled(atMs: Double) = true
        override val overtimeEndAtMs: Double? = null
        override val isAuthorized get() = authorized
        override val recordsTimeZone = zone
        override val settings get() = settings0
        override fun newId() = "00000000-0000-4000-8000-%012d".format(++ids)
    }

    private val env = Env()
    private val engine = FocusEngine(env)

    private fun task(pomodoros: Int, id: String = "00000000-0000-0000-0000-0000000000A1", planned: String? = null, slot: Double? = null) =
        FocusTask(id, 0.0, planned, slot, "Write", pomodoros, FocusTaskIcon.WRITING, false, null, null, 0, 0.0, 1, id, null, null)

    private fun open(taskID: String?, startMs: Double, minutes: Int = 25, id: String = "00000000-0000-0000-0000-0000000000B1", kind: FocusSessionKind = FocusSessionKind.FOCUS) = FocusSession(
        id, taskID, engine.dayKey(startMs), startMs, startMs + minutes * minute, null, null, startMs, 1, id, kind, zone, engine.dayKey(startMs), null,
        FocusPlanner.endReason(startMs, startMs + minutes * minute, 25),
    )

    private fun state(vararg tasks: FocusTask, sessions: List<FocusSession> = emptyList()) = RecordState(focusTasks = tasks.toList(), focusSessions = sessions)

    @Test fun aOneBlockTaskCompletesAfterANaturalEnd() {
        val t = task(1)
        val step = engine.finishElapsed(state(t, sessions = listOf(open(t.id, at("2026-08-24", 14)))), FocusNextAction.NONE, at("2026-08-24", 14, 25))
        assertTrue(step.ok)
        assertEquals(1, engine.completedBlocks(step.state, t))
        assertNotNull(step.state.focusTasks.single().completedAtMs)
    }

    @Test fun theFirstBlockOfATwoPomodoroTaskStaysOpenThenTheSecondCompletesIt() {
        val t = task(2)
        var s = engine.finishElapsed(state(t, sessions = listOf(open(t.id, at("2026-08-24", 14)))), FocusNextAction.NONE, at("2026-08-24", 14, 25)).state
        assertNull("1 / 2 stays open", s.focusTasks.single().completedAtMs)
        s = engine.skipPhase(s, FocusNextAction.NONE, at("2026-08-24", 14, 26)).state // end the automatic break
        s = s.copy(focusSessions = s.focusSessions + open(t.id, at("2026-08-24", 14, 30), id = "00000000-0000-0000-0000-0000000000B2"))
        s = engine.finishElapsed(s, FocusNextAction.NONE, at("2026-08-24", 14, 55)).state
        assertNotNull(s.focusTasks.single().completedAtMs)
    }

    @Test fun aTwelvePomodoroTaskDoesNotCompleteOnTheFirstBlock() {
        val t = task(12)
        val s = engine.finishElapsed(state(t, sessions = listOf(open(t.id, at("2026-08-24", 14)))), FocusNextAction.NONE, at("2026-08-24", 14, 25)).state
        assertNull(s.focusTasks.single().completedAtMs)
        assertEquals(1, engine.completedBlocks(s, t))
    }

    @Test fun aNaturalEndAfterBackgroundingCountsOneBlockAtItsOwnEnd() {
        val t = task(3)
        val s = engine.finishElapsed(state(t, sessions = listOf(open(t.id, at("2026-08-24", 14)))), FocusNextAction.NONE, at("2026-08-24", 16)).state
        val block = s.focusSessions.first { it.kind == FocusSessionKind.FOCUS }
        assertEquals(at("2026-08-24", 14, 25), block.endedAtMs!!, 0.0)
        assertEquals(1, engine.completedBlocks(s, t))
        assertNull("the break window has passed: nothing is backfilled", engine.activeSession(s))
    }

    @Test fun aBoundaryCutAndAUserStopDoNotCount() {
        val t = task(1)
        val cut = open(t.id, at("2026-08-24", 11, 50), minutes = 10) // stops at lunch
        val s1 = engine.finishElapsed(state(t, sessions = listOf(cut)), FocusNextAction.NONE, at("2026-08-24", 12, 1)).state
        assertEquals(FocusEndReason.STOPPED_AT_BOUNDARY, s1.focusSessions.single().endReason)
        val s2 = engine.stop(state(t, sessions = listOf(open(t.id, at("2026-08-24", 14)))), FocusEndReason.STOPPED_BY_USER, at("2026-08-24", 14, 10)).state
        assertEquals(FocusEndReason.STOPPED_BY_USER, s2.focusSessions.single().endReason)
        assertEquals(0, engine.completedBlocks(s1, t) + engine.completedBlocks(s2, t))
        assertNull(s2.focusTasks.single().completedAtMs)

        val abandoned = engine.stop(state(t, sessions = listOf(open(t.id, at("2026-08-24", 15)))), FocusEndReason.ABANDONED, at("2026-08-24", 15, 10)).state
        assertEquals(FocusEndReason.ABANDONED, abandoned.focusSessions.single().endReason)
        assertEquals(0, engine.completedBlocks(abandoned, t))
        val completed = engine.finishElapsed(state(t, sessions = listOf(open(t.id, at("2026-08-24", 16)))), FocusNextAction.NONE, at("2026-08-24", 16, 25)).state
        assertEquals(FocusEndReason.COMPLETED, completed.focusSessions.first { it.kind == FocusSessionKind.FOCUS }.endReason)
    }

    @Test fun startIsRefusedWithoutRoomOutsideWorkOrWithoutAccess() {
        val t = task(1)
        for (now in listOf(at("2026-08-24", 8), at("2026-08-24", 12, 30), at("2026-08-24", 17, 59) + 30_000, at("2026-08-26", 10))) {
            val step = engine.startFocus(state(t), FocusNextAction.NONE, t.id, now)
            assertFalse("start at $now", step.ok)
            assertTrue(step.state.focusSessions.isEmpty())
        }
        env.authorized = false
        assertFalse(engine.startFocus(state(t), FocusNextAction.NONE, t.id, at("2026-08-24", 10)).ok)
    }

    @Test fun startRunsToTheNextBoundaryAndOnlyOneSessionIsOpen() {
        val t = task(2)
        val started = engine.startFocus(state(t), FocusNextAction.NONE, t.id, at("2026-08-24", 11, 50))
        assertTrue(started.ok)
        val session = started.state.focusSessions.single()
        assertEquals("lunch cuts it", at("2026-08-24", 12), session.plannedEndAtMs, 0.0)
        assertEquals(FocusEndReason.STOPPED_AT_BOUNDARY, session.plannedEndReason)
        assertFalse("a double tap does not start a second block", engine.startFocus(started.state, FocusNextAction.NONE, t.id, at("2026-08-24", 11, 50)).ok)
        assertEquals(FocusStartAvailability.Running, engine.availability(started.state, t, at("2026-08-24", 11, 51)))
        assertEquals(FocusStartAvailability.BlockedByOther, engine.availability(started.state, task(1, id = "00000000-0000-0000-0000-0000000000A2"), at("2026-08-24", 11, 51)))
    }

    @Test fun changingDurationLeavesTheRunningEndAndAppliesToTheNextSession() {
        val t = task(2)
        val start = at("2026-08-24", 14)
        val running = engine.startFocus(state(t), FocusNextAction.NONE, t.id, start).state
        val originalEnd = running.focusSessions.single().plannedEndAtMs
        assertEquals(start + 25 * minute, originalEnd, 0.0)

        env.settings0 = FocusTimerSettings(40, 5, 15, 4)
        assertEquals(originalEnd, engine.activeSession(running)!!.plannedEndAtMs, 0.0)
        val stopped = engine.stop(running, FocusEndReason.STOPPED_BY_USER, start + minute).state
        val nextStart = start + 5 * minute
        val next = engine.startFocus(stopped, FocusNextAction.NONE, t.id, nextStart).state
        assertEquals(2, next.focusSessions.size)
        assertEquals(nextStart + 40 * minute, engine.activeSession(next)!!.plannedEndAtMs, 0.0)
        assertEquals(originalEnd, next.focusSessions.first().plannedEndAtMs, 0.0)
    }

    @Test fun aPlanDrivenStartNeverPassesItsBlockEnd() {
        val t = task(1)
        val blockEnd = at("2026-08-24", 10, 25)
        val step = engine.startFocus(state(t), FocusNextAction.NONE, t.id, at("2026-08-24", 10, 5), blockEndMs = blockEnd)
        assertEquals(blockEnd, step.state.focusSessions.single().plannedEndAtMs, 0.0)
        assertEquals("the rest of a planned block completes it", FocusEndReason.COMPLETED, step.state.focusSessions.single().plannedEndReason)
    }

    @Test fun futureScheduledOrPlannedTasksCannotStartEarly() {
        val slotted = task(1, slot = at("2026-08-24", 15))
        assertEquals(FocusStartAvailability.NotYetAvailable(at("2026-08-24", 15)), engine.availability(state(slotted), slotted, at("2026-08-24", 10)))
        assertFalse(engine.startFocus(state(slotted), FocusNextAction.NONE, slotted.id, at("2026-08-24", 10)).ok)
        val tomorrow = task(1, planned = "2026-08-25")
        assertEquals(FocusStartAvailability.NotYetAvailable(at("2026-08-25", 0)), engine.availability(state(tomorrow), tomorrow, at("2026-08-24", 10)))
        val exactTomorrow = task(1, planned = "2026-08-25", slot = at("2026-08-25", 9))
        assertEquals("an exact slot beats its day", FocusStartAvailability.NotYetAvailable(at("2026-08-25", 9)), engine.availability(state(exactTomorrow), exactTomorrow, at("2026-08-25", 0, 30)))
    }

    @Test fun anExpiredSessionFromAnotherDayResolvesFromItsPersistedOutcome() {
        val t = task(1)
        val yesterday = open(t.id, at("2026-08-24", 17, 30)).copy(shiftAnchorDate = "2026-08-23")
        val step = engine.finishElapsed(state(t, sessions = listOf(yesterday)), FocusNextAction.NONE, at("2026-08-25", 9))
        assertTrue(step.ok)
        assertEquals(FocusEndReason.COMPLETED, step.state.focusSessions.first().endReason)
        assertEquals(1, engine.completedBlocks(step.state, t))
    }

    @Test fun multipleOpenSessionsConvergeAndLosersDoNotCount() {
        val t = task(2)
        val first = open(t.id, at("2026-08-24", 14))
        val second = open(t.id, at("2026-08-24", 14) + 1_000, id = "00000000-0000-0000-0000-0000000000B2")
        val step = engine.reconcile(state(t, sessions = listOf(second, first)), at("2026-08-24", 14) + 2_000)
        assertEquals(1, step.state.focusSessions.count { it.endedAtMs == null })
        assertEquals(first.id, engine.activeSession(step.state)!!.id)
        assertEquals(FocusEndReason.SUPERSEDED_BY_SYNC, step.state.focusSessions.first { it.id == second.id }.endReason)
        assertEquals(0, engine.completedBlocks(step.state, t))
    }

    @Test fun naturalPhasesRollIntoShortBreaksUntilTheFourthRound() {
        val t = task(6)
        var s = state(t)
        for (round in 1..4) {
            val start = at("2026-08-24", 13, 2) + round * 30 * minute
            s = s.copy(focusSessions = s.focusSessions + open(t.id, start, id = "00000000-0000-0000-0000-00000000000$round"))
            val step = engine.finishElapsed(s, FocusNextAction.NONE, start + 25 * minute)
            val recovery = engine.activeSession(step.state)!!
            assertEquals(if (round == 4) FocusSessionKind.LONG_BREAK else FocusSessionKind.SHORT_BREAK, recovery.kind)
            assertEquals(start + 25 * minute, recovery.startedAtMs, 0.0)
            assertEquals(FocusNextAction.NONE, step.nextAction)
            s = engine.stop(step.state, FocusEndReason.STOPPED_BY_USER, start + 26 * minute).state
        }
    }

    @Test fun aFocusEndingAtABoundaryLeavesNoUnusableBreakAction() {
        val t = task(3)
        val step = engine.finishElapsed(state(t, sessions = listOf(open(t.id, at("2026-08-24", 17, 35)))), FocusNextAction.NONE, at("2026-08-24", 18))
        assertNull(engine.activeSession(step.state))
        assertEquals(FocusNextAction.NONE, step.nextAction)
    }

    @Test fun skippingAnOfferedBreakAdvancesWithoutWritingASession() {
        val t = task(3)
        val finished = engine.finishElapsed(state(t, sessions = listOf(open(t.id, at("2026-08-24", 14, 2)))), FocusNextAction.NONE, at("2026-08-24", 14, 28))
        assertEquals("the break window is still open, so it runs", FocusSessionKind.SHORT_BREAK, engine.activeSession(finished.state)!!.kind)
        val skipped = engine.skipPhase(finished.state, finished.nextAction, at("2026-08-24", 14, 28))
        assertEquals(FocusNextAction.START_NEXT_FOCUS, skipped.nextAction)
        assertEquals("a break never counts toward the task", 1, engine.completedBlocks(skipped.state, t))
        val offer = engine.skipSuggestedBreak(finished.state.copy(focusSessions = finished.state.focusSessions.filter { it.kind == FocusSessionKind.FOCUS }), FocusNextAction.START_SHORT_BREAK)
        assertEquals(FocusNextAction.START_NEXT_FOCUS, offer.nextAction)
        assertEquals(1, offer.state.focusSessions.size)
    }

    @Test fun twoDevicesFinishingTheSameBlockStartOneSharedBreak() {
        val t = task(2)
        val block = open(t.id, at("2026-08-24", 14, 2))
        val phone = engine.finishElapsed(state(t, sessions = listOf(block)), FocusNextAction.NONE, at("2026-08-24", 14, 27) + 10_000).state
        val tablet = FocusEngine(Env()).finishElapsed(state(t, sessions = listOf(block)), FocusNextAction.NONE, at("2026-08-24", 14, 27) + 90_000).state
        val a = engine.activeSession(phone)!!
        val b = engine.activeSession(tablet)!!
        assertEquals(FocusSessionKind.SHORT_BREAK, a.kind)
        assertEquals(a.id, b.id)
        assertEquals(FocusSessionIdentity.recovery(block.id, FocusSessionKind.SHORT_BREAK), a.id)
        assertEquals(a.startedAtMs, b.startedAtMs, 0.0)
        assertEquals(a.plannedEndAtMs, b.plannedEndAtMs, 0.0)
        assertNotEquals(FocusSessionIdentity.recovery(block.id, FocusSessionKind.LONG_BREAK), a.id)
    }

    @Test fun sessionHistoryRestoresTheBreakCadenceOnAColdLaunch() {
        val t = task(8)
        var s = state(t)
        for (round in 0 until 4) {
            val start = at("2026-08-24", 13, 2) + round * 30 * minute
            s = s.copy(focusSessions = s.focusSessions + open(t.id, start, id = "00000000-0000-0000-0000-00000000001$round"))
            // Closed after every break window has passed (a long one runs 15 minutes), so
            // history holds four focus blocks and no recovery: what a cold launch reads back.
            s = engine.finishElapsed(s, FocusNextAction.NONE, start + 41 * minute).state
        }
        assertNull(engine.activeSession(s))
        assertEquals(FocusNextAction.START_LONG_BREAK, engine.reconcile(s, at("2026-08-24", 15, 20)).nextAction)
        assertEquals("a new shift does not restore yesterday's prompt", FocusNextAction.NONE, engine.restoreNextAction(s, at("2026-08-25", 10)))
    }

    @Test fun reconcileFinishesAnElapsedSurvivorAndKeepsARunningOne() {
        val t = task(2)
        val running = open(t.id, at("2026-08-24", 14, 2))
        assertEquals(running, engine.activeSession(engine.reconcile(state(t, sessions = listOf(running)), at("2026-08-24", 14, 10)).state))
        val restarted = engine.reconcile(state(t, sessions = listOf(running)), at("2026-08-24", 14, 28))
        assertEquals(FocusSessionKind.SHORT_BREAK, engine.activeSession(restarted.state)!!.kind)
        assertEquals(1, engine.completedBlocks(restarted.state, t))
        val again = engine.reconcile(restarted.state, at("2026-08-24", 14, 29))
        assertEquals("reconciling twice changes nothing", restarted.state, again.state)
    }

    @Test fun aBlockOnTheGridTakesTheGridsOwnBreak() {
        // Rounds run across the whole shift: five before lunch, so 14:00 is the eighth and earns a long break.
        val t = task(3)
        val step = engine.finishElapsed(state(t, sessions = listOf(open(t.id, at("2026-08-24", 14)))), FocusNextAction.NONE, at("2026-08-24", 14, 25))
        val recovery = engine.activeSession(step.state)!!
        assertEquals(FocusSessionKind.LONG_BREAK, recovery.kind)
        assertEquals("the grid's break slot bounds it", at("2026-08-24", 14, 40), recovery.plannedEndAtMs, 0.0)
    }
}
