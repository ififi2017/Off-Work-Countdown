package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.focus.FocusAlertText
import com.rainif.doneat.core.domain.focus.FocusReminders
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.RecordsFocusHistory
import com.rainif.doneat.core.domain.reminders.*
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
import org.junit.Assert.assertNotNull
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

    private suspend fun TestScope.records(name: String = "records") =
        RecordStore(folder.root.toPath().resolve("$name.json"), { at(9, 0) }, { "UTC" }, UnconfinedTestDispatcher(testScheduler)).also { it.load() }

    private fun TestScope.store(records: RecordStore, plus: Boolean = true, name: String = "focus-queue") = FocusStore(
        records, session, MutableStateFlow(plus), folder.root.toPath().resolve("device/$name.json"), ::newId,
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

    @Test fun twoDevicesImportingTheSameAutomaticBlockKeepOneCompletionAndBreak() = runTest {
        val phoneRecords = records("phone")
        val phone = store(phoneRecords, name = "phone")
        phone.plan { state, planning -> planning.createInBlock(state, "Write", at(9, 30).toLong(), at(9, 10), pomodoros = 2) }
        val tabletRecords = records("tablet")
        assertNotNull(RecordsTransfer.commit(tabletRecords, RecordsTransfer.export(phoneRecords.state.value, true, at(9, 10), "UTC").toByteArray()))
        val tablet = store(tabletRecords, name = "tablet")
        phone.refreshScheduled(at(9, 10))
        tablet.refreshScheduled(at(9, 10))
        phone.reconcile(at(9, 40))
        tablet.reconcile(at(9, 41))
        assertEquals(phone.activeSession()!!.id, tablet.activeSession()!!.id)
        phone.finishElapsed(at(9, 56))
        tablet.finishElapsed(at(9, 57))
        assertEquals(phone.activeSession()!!.id, tablet.activeSession()!!.id)
        val backup = RecordsTransfer.export(tabletRecords.state.value, true, at(9, 57), "UTC").toByteArray()
        repeat(2) { assertNotNull(RecordsTransfer.commit(phoneRecords, backup)) }
        phone.reconcile(at(9, 58))
        val merged = phoneRecords.state.value
        assertEquals(2, merged.focusSessions.size)
        assertEquals(1, phone.engine().completedBlocks(merged, merged.focusTasks.single()))
        assertEquals(FocusSessionKind.SHORT_BREAK, phone.activeSession()!!.kind)
        // v6 keeps differing edit stamps for review, while the logical sessions remain unique.
        assertTrue(merged.importConflicts.all { it.entityType == com.rainif.doneat.core.domain.records.RecordEntityType.FOCUS_SESSION })
        assertEquals(merged, records("phone").state.value)
    }

    @Test fun importedCompetingSessionsKeepSupersededHistoryWithoutCountingIt() = runTest {
        val phoneRecords = records("phone")
        val phone = store(phoneRecords, name = "phone")
        phone.plan { state, planning -> planning.addTask(state, "Write", 2, at(9, 0)) }
        val tabletRecords = records("tablet")
        assertNotNull(RecordsTransfer.commit(tabletRecords, RecordsTransfer.export(phoneRecords.state.value, true, at(9, 0), "UTC").toByteArray()))
        val tablet = store(tabletRecords, name = "tablet")
        val task = phoneRecords.state.value.focusTasks.single()
        assertTrue(phone.start(task.id, at(9, 5)))
        assertTrue(tablet.start(task.id, at(9, 5) + 1_000))
        val winner = phone.activeSession()!!.id
        val loser = tablet.activeSession()!!.id
        assertTrue(winner != loser)
        val backup = RecordsTransfer.export(tabletRecords.state.value, true, at(9, 6), "UTC").toByteArray()
        assertNotNull(RecordsTransfer.commit(phoneRecords, backup))
        phone.reconcile(at(9, 7))
        val merged = phoneRecords.state.value
        assertEquals(winner, phone.activeSession()!!.id)
        assertEquals(FocusEndReason.SUPERSEDED_BY_SYNC, merged.focusSessions.single { it.id == loser }.endReason)
        assertEquals(0, phone.engine().completedBlocks(merged, task))
        assertEquals(listOf(winner), RecordsFocusHistory.visible(merged.focusSessions).map { it.id })
        val restored = records("restored")
        assertNotNull(RecordsTransfer.commit(restored, RecordsTransfer.export(merged, true, at(9, 7), "UTC").toByteArray()))
        assertEquals(merged.focusSessions, restored.state.value.focusSessions)
        assertEquals(2, records("phone").state.value.focusSessions.size)
    }

    private object AlertText : FocusAlertText {
        override val focusTitle = "Focus"
        override val breakOver = "Break over"
        override val dayDone = "Done"
        override val endedNaturally = "Ended"
        override val endedAtBoundary = "Boundary"
        override val nextFocus = "Next"
        override val breakReminderTitle = "Break"
        override fun pomodoro(index: Int, total: Int) = "$index/$total"
        override fun breakUntil(minutes: Int, endAtMs: Double) = "Break until $endAtMs"
        override fun nextUp(task: String, startAtMs: Long) = task
        override fun focusBreakBody(minutes: Int) = "$minutes"
    }

    @Test fun lunchAndClockOffRebuildAlarmsWithoutCreditingAnIncompleteBlock() = runTest {
        session.value = ShiftSession(session.value.state, SessionEnvironment(preferences = session.value.env.preferences.copy(
            lunchEnabled = true, lunchStartMinutes = 12 * 60, lunchDurationMinutes = 60,
        ), onboardingComplete = true, extendedSchedule = null, rosterDays = emptyList(), holidays = HolidayCalendar.EMPTY, deviceZone = "UTC"))
        for ((start, boundary, resume) in listOf(Triple(at(11, 50), at(12, 0), at(13, 0)), Triple(at(16, 50), at(17, 0), at(17, 1)))) {
            val records = records("boundary-${start.toLong()}")
            val focus = store(records, name = "boundary-${start.toLong()}")
            val held = linkedMapOf<String, PlannedReminder>()
            val port = object : AlarmPort {
                override fun canScheduleExact() = true
                override fun schedule(reminder: PlannedReminder, timing: AlarmTiming) { held[reminder.id] = reminder }
                override fun cancel(id: String) { held.remove(id) }
            }
            val sync = ReminderSync(folder.root.toPath().resolve("alarms-${start.toLong()}.json"), port)
            suspend fun rebuild(now: Double) {
                val state = records.state.value
                val active = focus.activeSession()
                val desired = active?.let {
                    ReminderPlanner.focusAlarms(it.id, FocusReminders(focus.environment(), focus.planning(), AlertText).alerts(state, it), now)
                }.orEmpty()
                sync.sync(desired, ReminderPlanner.FOCUS_PREFIX)
            }
            assertTrue(focus.addAndStart("Write", 2, FocusTaskIcon.WRITING, false, start))
            val running = focus.activeSession()!!
            assertEquals(boundary, running.plannedEndAtMs, 0.0)
            rebuild(start)
            assertEquals(listOf(boundary.toLong()), held.values.map { it.atMs })
            focus.reconcile(boundary + 1_000)
            rebuild(boundary + 1_000)
            assertTrue(held.isEmpty())
            assertNull(focus.activeSession())
            assertEquals(FocusEndReason.STOPPED_AT_BOUNDARY, records.state.value.focusSessions.single().endReason)
            assertEquals(0, focus.engine().completedBlocks(records.state.value, records.state.value.focusTasks.single()))
            assertNull(sync.take(running.id.let { "owc.focus.$it.end" }, boundary.toLong() + 1_000))
            val task = records.state.value.focusTasks.single()
            if (resume == at(13, 0)) {
                assertTrue(focus.start(task.id, resume))
                rebuild(resume)
                assertTrue(held.isNotEmpty())
                assertTrue(held.values.all { it.atMs > resume })
            } else {
                assertFalse(focus.start(task.id, resume))
                rebuild(resume)
                assertTrue(held.isEmpty())
            }
        }
    }
}
