package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.focus.FocusNextAction
import com.rainif.doneat.core.domain.focus.FocusPlacement
import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.SessionEnvironment
import com.rainif.doneat.core.domain.session.SessionState
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.settings.PreferencesRules
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.LocalDateTime
import java.time.ZoneOffset

/**
 * The focus runtime over a real archive: a block that ends while the app is
 * away completes and earns its break, a queued plan start survives the
 * process dying, and nothing runs without Plus.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FocusStoreTest {
    @get:Rule val folder = TemporaryFolder()
    private var ids = 0
    private fun newId() = "00000000-0000-4000-8000-%012d".format(++ids)

    /** Wednesday 16 September 2026, UTC, a Monday-to-Friday nine-to-five without lunch. */
    private fun at(hour: Int, minute: Int) = LocalDateTime.of(2026, 9, 16, hour, minute).toInstant(ZoneOffset.UTC).toEpochMilli().toDouble()

    private val session = MutableStateFlow(
        ShiftSession(
            SessionState(),
            SessionEnvironment(
                PreferencesRules.defaults("UTC", 0.0).copy(scheduleMode = "classic", workdays = listOf(1, 2, 3, 4, 5), startMinutes = 9 * 60, endMinutes = 17 * 60, lunchEnabled = false),
                onboardingComplete = true, extendedSchedule = null, rosterDays = emptyList(), holidays = HolidayCalendar.EMPTY, deviceZone = "UTC",
            ),
        ),
    )

    private suspend fun TestScope.records() =
        RecordStore(folder.root.toPath().resolve("records.json"), { at(9, 0) }, { "UTC" }, UnconfinedTestDispatcher(testScheduler)).also { it.load() }

    private fun TestScope.store(records: RecordStore, plus: Boolean = true) = FocusStore(
        records, session, MutableStateFlow(plus), folder.root.toPath().resolve("device/focus-queue.json"), ::newId,
        io = UnconfinedTestDispatcher(testScheduler),
    )

    @Test fun aBlockThatEndsWhileAwayCompletesAndStartsItsBreak() = runTest {
        val records = records()
        val focus = store(records)
        // Two pomodoros: finishing the only block of the day's only task completes the day, and a completed day earns no break.
        val placement = focus.plan { state, planning -> planning.createInBlock(state, "Write", at(9, 0).toLong(), at(9, 5), pomodoros = 2) }
        val taskID = (placement as FocusPlacement.Placed).taskID
        assertTrue(focus.start(taskID, at(9, 5), blockStartAtMs = at(9, 0).toLong()))
        assertEquals(at(9, 25), focus.activeSession()!!.plannedEndAtMs, 0.0)

        // The app comes back at 9:27: the block ended at 9:25, and the break it earned runs to 9:30.
        assertTrue(focus.finishElapsed(at(9, 27)))
        val ended = records.state.value.focusSessions.first { it.kind == FocusSessionKind.FOCUS }
        assertEquals(FocusEndReason.COMPLETED, ended.endReason)
        assertEquals(at(9, 25), ended.endedAtMs!!, 0.0)
        val breakSession = focus.activeSession()!!
        assertEquals(FocusSessionKind.SHORT_BREAK, breakSession.kind)
        assertEquals(at(9, 25), breakSession.startedAtMs, 0.0)
        assertEquals(at(9, 30), breakSession.plannedEndAtMs, 0.0)
        assertNull("one of two pomodoros leaves the task open", records.state.value.focusTasks.single().completedAtMs)
    }

    @Test fun stoppingByHandEndsTheBlockWithoutCompletingIt() = runTest {
        val records = records()
        val focus = store(records)
        val taskID = (focus.plan { state, planning -> planning.createInBlock(state, "Write", at(9, 0).toLong(), at(9, 5), pomodoros = 2) } as FocusPlacement.Placed).taskID
        assertTrue(focus.start(taskID, at(9, 5)))
        focus.stop(FocusEndReason.STOPPED_BY_USER, at(9, 12))
        assertNull(focus.activeSession())
        assertEquals(FocusEndReason.STOPPED_BY_USER, records.state.value.focusSessions.single().endReason)
        assertNull(records.state.value.focusTasks.single().completedAtMs)
        assertEquals(FocusNextAction.NONE, focus.nextAction.value)
    }

    @Test fun aQueuedPlanStartSurvivesTheProcessDying() = runTest {
        val records = records()
        val first = store(records)
        first.plan { state, planning -> planning.createInBlock(state, "Review", at(9, 30).toLong(), at(9, 10)) }
        val queue = first.refreshScheduled(at(9, 10))
        assertEquals(1, queue.size)
        assertEquals(at(9, 30), queue.single().startedAtMs, 0.0)
        assertNull("nothing runs before its block", first.activeSession())

        // A new process at 9:40 reads the queue back and records the block from 9:30, not from now.
        val second = store(records)
        second.reconcile(at(9, 40))
        val started = second.activeSession()!!
        assertEquals(at(9, 30), started.startedAtMs, 0.0)
        assertEquals(at(9, 55), started.plannedEndAtMs, 0.0)
        assertTrue(second.queue.value.isEmpty())
    }

    @Test fun withoutPlusNothingStartsOrQueues() = runTest {
        val records = records()
        val plus = store(records)
        val taskID = (plus.plan { state, planning -> planning.createInBlock(state, "Write", at(9, 0).toLong(), at(9, 5)) } as FocusPlacement.Placed).taskID
        val free = store(records, plus = false)
        assertFalse(free.start(taskID, at(9, 5)))
        assertTrue(free.refreshScheduled(at(9, 5)).isEmpty())
        assertEquals(RecordState().focusSessions, records.state.value.focusSessions)
    }

    @Test fun theQueueCodecRoundTrips() {
        val session = com.rainif.doneat.core.domain.records.FocusSession(
            "S", "T", "2026-09-16", at(9, 30), at(9, 55), null, null, at(9, 10), 0, "X",
            FocusSessionKind.FOCUS, "UTC", "2026-09-16", null, FocusEndReason.COMPLETED,
        )
        assertEquals(listOf(session), FocusStore.decodeQueue(FocusStore.encodeQueue(listOf(session))))
        assertTrue(FocusStore.decodeQueue("[{\"id\":\"only\"}]").isEmpty())
    }

    @Test fun concurrentStartsAndRepeatedCallbacksRecordOneLogicalBlock() = runTest {
        val records = records()
        val focus = store(records)
        val taskID = (focus.plan { state, planning -> planning.createInBlock(state, "Write", at(9, 0).toLong(), at(9, 5)) } as FocusPlacement.Placed).taskID
        val starts = (1..20).map { async(Dispatchers.Default) { focus.start(taskID, at(9, 5)) } }.awaitAll()
        assertEquals(1, starts.count { it })
        assertEquals(1, records.state.value.focusSessions.count { it.endedAtMs == null })
        val finishes = (1..20).map { async(Dispatchers.Default) { focus.finishElapsed(at(9, 30)) } }.awaitAll()
        assertEquals(1, finishes.count { it })
        assertEquals(1, records.state.value.focusSessions.size)
        assertEquals(FocusEndReason.COMPLETED, records.state.value.focusSessions.single().endReason)
    }
}
