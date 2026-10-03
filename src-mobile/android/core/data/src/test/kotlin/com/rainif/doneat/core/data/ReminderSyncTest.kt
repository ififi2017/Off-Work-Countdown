package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.reminders.AlarmTiming
import com.rainif.doneat.core.domain.reminders.PlannedReminder
import com.rainif.doneat.core.domain.reminders.ReminderChannel
import com.rainif.doneat.core.domain.reminders.ReminderPlanner.FOCUS_PREFIX
import com.rainif.doneat.core.domain.reminders.ReminderPlanner.SHIFT_PREFIX
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.file.Files

class ReminderSyncTest {
    @get:Rule val folder = TemporaryFolder()

    /** Records what the "system" holds, and can refuse or revoke like AlarmManager. */
    private inner class FakeAlarms : AlarmPort {
        var exact = true
        val refuse = HashSet<String>()
        val held = LinkedHashMap<String, Pair<PlannedReminder, AlarmTiming>>()
        var calls = 0
        var sawRegistryBeforeSchedule = true
        override fun canScheduleExact() = exact
        override fun schedule(reminder: PlannedReminder, timing: AlarmTiming) {
            calls++
            if (!Files.readString(file).contains(reminder.id)) sawRegistryBeforeSchedule = false
            if (reminder.id in refuse) throw SecurityException("refused")
            held[reminder.id] = reminder to timing
        }
        override fun cancel(id: String) {
            calls++
            held.remove(id)
        }
    }

    private val file by lazy { folder.root.toPath().resolve("reminders/registry.json") }
    private val alarms = FakeAlarms()
    private val sync by lazy { ReminderSync(file, alarms) }

    private fun shift(id: String, at: Long, body: String = "b", channel: ReminderChannel = ReminderChannel.SHIFT, expires: Long? = null) =
        PlannedReminder("$SHIFT_PREFIX$id", at, channel, "t", body, expires)

    private fun report(date: String): PlannedReminder {
        val period = com.rainif.doneat.core.domain.records.CycleReportPeriod.containing(java.time.LocalDate.parse(date),
            com.rainif.doneat.core.domain.records.CycleReportKind.MONTH, java.time.ZoneId.of("UTC"))
        return PlannedReminder(period.notificationIdentifier, period.notificationAtMs, ReminderChannel.REPORT, "month", "ready", reportUrl = period.url)
    }
    private val reportKinds get() = setOf(com.rainif.doneat.core.domain.records.CycleReportKind.MONTH)
    private val reportPrefix get() = com.rainif.doneat.core.domain.records.CycleReportPeriod.PREFIX

    @Test fun coldReportReconcileBeforeReceiverKeepsDeliveryAndDoesNotRearmDue() = runTest {
        val due = report("2026-09-01")
        val next = report("2026-10-01")
        sync.sync(listOf(due), reportPrefix)
        alarms.calls = 0
        val freshProcess = ReminderSync(file, alarms)
        val result = freshProcess.syncReports(listOf(next), reportKinds, due.atMs, rearmFuture = true)
        assertEquals(1, result.scheduled)
        assertEquals(0, result.cancelled)
        assertEquals(due, freshProcess.take(due.id, due.atMs))
        assertNull(freshProcess.take(due.id, due.atMs))
        assertEquals(listOf(next), freshProcess.registered())
    }

    @Test fun receiverBeforeColdReportReconcileSchedulesSuccessorOnce() = runTest {
        val due = report("2026-09-01")
        val next = report("2026-10-01")
        sync.sync(listOf(due), reportPrefix)
        assertEquals(due, sync.take(due.id, due.atMs))
        val freshProcess = ReminderSync(file, alarms)
        freshProcess.syncReports(listOf(next), reportKinds, due.atMs, rearmFuture = true)
        alarms.calls = 0
        freshProcess.syncReports(listOf(next), reportKinds, due.atMs, rearmFuture = false)
        assertEquals(0, alarms.calls)
        assertEquals(listOf(next), freshProcess.registered())
    }

    @Test fun coldReopenAfterForceStopRearmsIdenticalFutureReport() = runTest {
        val future = report("2026-10-01")
        sync.sync(listOf(future), reportPrefix)
        alarms.held.clear() // Force-stop clears AlarmManager while the no-backup registry remains.
        val freshProcess = ReminderSync(file, alarms)
        val result = freshProcess.syncReports(listOf(future), reportKinds, future.atMs - 1, rearmFuture = true)
        assertEquals(1, result.scheduled)
        assertTrue(future.id in alarms.held)
    }

    @Test fun reportGrantChangeNeverArmsPastDeliveryTokensAndTurningOffCancelsThem() = runTest {
        val due = report("2026-09-01")
        val next = report("2026-10-01")
        sync.sync(listOf(due), reportPrefix)
        alarms.held.clear()
        alarms.exact = false
        val result = sync.syncReports(listOf(next), reportKinds, due.atMs, rearmFuture = true)
        assertEquals(1, result.scheduled)
        assertEquals(setOf(next.id), alarms.held.keys)
        sync.syncReports(emptyList(), emptySet(), due.atMs, rearmFuture = false)
        assertNull(sync.take(due.id, due.atMs))
        assertTrue(sync.registered().isEmpty())
    }

    @Test fun unrelatedPrefixPermissionRefreshCannotRearmDueReportToken() = runTest {
        val due = report("2026-09-01")
        val next = report("2026-10-01")
        sync.sync(listOf(due), reportPrefix)
        sync.syncReports(listOf(next), reportKinds, due.atMs, rearmFuture = true)
        alarms.held.clear()
        alarms.exact = false
        sync.sync(listOf(shift("ordinary", next.atMs)), SHIFT_PREFIX, due.atMs)
        assertTrue(due.id !in alarms.held)
        assertTrue(next.id in alarms.held)
        assertEquals(due, sync.take(due.id, due.atMs))
        // A report permission refresh then explicitly arms the surviving future report.
        sync.syncReports(listOf(next), reportKinds, due.atMs, rearmFuture = false)
    }

    @Test fun uncertainAccessAllowsDisabledKindsToCancelWithoutRearmingOthers() = runTest {
        val due = report("2026-09-01")
        val next = report("2026-10-01")
        val yearPeriod = com.rainif.doneat.core.domain.records.CycleReportPeriod.containing(java.time.LocalDate.parse("2026-10-01"),
            com.rainif.doneat.core.domain.records.CycleReportKind.YEAR, java.time.ZoneId.of("UTC"))
        val year = PlannedReminder(yearPeriod.notificationIdentifier, yearPeriod.notificationAtMs, ReminderChannel.REPORT, "year", "ready", reportUrl = yearPeriod.url)
        sync.sync(listOf(due, next, year), reportPrefix)
        alarms.held.clear()
        alarms.exact = false
        val result = sync.syncReports(listOf(year), setOf(com.rainif.doneat.core.domain.records.CycleReportKind.YEAR),
            due.atMs, rearmFuture = false, permitFutureRegistration = false)
        assertEquals(0, result.scheduled)
        assertEquals(2, result.cancelled)
        assertEquals(listOf(year), sync.registered())
        assertNull(sync.take(due.id, due.atMs))
        assertTrue(alarms.held.isEmpty())
    }

    @Test fun missedReportReceiversRetainOnlyLatestDeliveryTokenPerKind() = runTest {
        val stale = report("2026-08-01")
        val latest = report("2026-09-01")
        val next = report("2026-10-01")
        sync.sync(listOf(stale, latest), reportPrefix)
        val result = sync.syncReports(listOf(next), reportKinds, latest.atMs, rearmFuture = true)
        assertEquals(1, result.scheduled)
        assertEquals(1, result.cancelled)
        assertNull(sync.take(stale.id, latest.atMs))
        assertEquals(latest, sync.take(latest.id, latest.atMs))
    }

    @Test fun frozenReportRouteSurvivesProcessRestartAndDelayedTap() = runTest {
        val period = com.rainif.doneat.core.domain.records.CycleReportPeriod.containing(java.time.LocalDate.parse("2024-02-29"),
            com.rainif.doneat.core.domain.records.CycleReportKind.YEAR, java.time.ZoneId.of("America/New_York"))
        val reminder = PlannedReminder(period.notificationIdentifier, period.notificationAtMs, ReminderChannel.REPORT, "year", "ready", reportUrl = period.url)
        sync.sync(listOf(reminder), com.rainif.doneat.core.domain.records.CycleReportPeriod.PREFIX)
        val restarted = ReminderSync(file, alarms)
        val delivered = restarted.take(reminder.id, reminder.atMs + 3 * 86_400_000L)!!
        assertEquals(period, com.rainif.doneat.core.domain.records.CycleReportPeriod.fromUrl(delivered.reportUrl!!))
        assertNull(restarted.take(reminder.id, reminder.atMs + 3 * 86_400_000L))
    }

    @Test fun syncRegistersOnlyWhatChangedAndCancelsWhatIsNoLongerWanted() = runTest {
        val first = sync.sync(listOf(shift("a", 10), shift("b", 20), shift("c", 30)), SHIFT_PREFIX)
        assertEquals(3, first.scheduled)
        assertTrue("the registry is written before the system is asked", alarms.sawRegistryBeforeSchedule)
        alarms.calls = 0
        val same = sync.sync(listOf(shift("a", 10), shift("b", 20), shift("c", 30)), SHIFT_PREFIX)
        assertEquals("an unchanged plan touches nothing", 0, alarms.calls)
        assertEquals(0, same.scheduled + same.cancelled)
        val changed = sync.sync(listOf(shift("a", 10), shift("b", 25), shift("d", 40)), SHIFT_PREFIX)
        assertEquals(2, changed.scheduled)
        assertEquals(1, changed.cancelled)
        assertEquals(setOf("${SHIFT_PREFIX}a", "${SHIFT_PREFIX}b", "${SHIFT_PREFIX}d"), alarms.held.keys)
        assertEquals(25L, alarms.held.getValue("${SHIFT_PREFIX}b").first.atMs)
    }

    @Test fun eachPrefixOwnsItsAlarms() = runTest {
        sync.sync(listOf(shift("a", 10)), SHIFT_PREFIX)
        sync.sync(listOf(PlannedReminder("${FOCUS_PREFIX}S.end", 15, ReminderChannel.FOCUS, "t", "b")), FOCUS_PREFIX)
        sync.clear(FOCUS_PREFIX)
        assertEquals(setOf("${SHIFT_PREFIX}a"), alarms.held.keys)
        assertEquals(listOf("${SHIFT_PREFIX}a"), sync.registered().map { it.id })
    }

    @Test fun healthRemindersNeverUseExactAlarmsAndARevokedGrantReRegistersEverything() = runTest {
        sync.sync(listOf(shift("a", 10), shift("h", 20, channel = ReminderChannel.HEALTH)), SHIFT_PREFIX)
        assertEquals(AlarmTiming.EXACT, alarms.held.getValue("${SHIFT_PREFIX}a").second)
        assertEquals(AlarmTiming.WINDOW, alarms.held.getValue("${SHIFT_PREFIX}h").second)
        alarms.exact = false
        val result = sync.sync(listOf(shift("a", 10), shift("h", 20, channel = ReminderChannel.HEALTH)), SHIFT_PREFIX)
        assertEquals("the same plan is re-registered under the new grant", 2, result.scheduled)
        assertEquals(false, result.exact)
        assertEquals(AlarmTiming.INEXACT, alarms.held.getValue("${SHIFT_PREFIX}a").second)
    }

    @Test fun aRefusedRegistrationIsRetriedOnTheNextSync() = runTest {
        alarms.refuse += "${SHIFT_PREFIX}b"
        val result = sync.sync(listOf(shift("a", 10), shift("b", 20)), SHIFT_PREFIX)
        assertEquals(1, result.failed)
        assertTrue(!result.isComplete)
        assertEquals(listOf("${SHIFT_PREFIX}a"), sync.registered().map { it.id })
        alarms.refuse.clear()
        assertEquals(1, sync.sync(listOf(shift("a", 10), shift("b", 20)), SHIFT_PREFIX).scheduled)
        assertEquals(setOf("${SHIFT_PREFIX}a", "${SHIFT_PREFIX}b"), alarms.held.keys)
    }

    @Test fun afterARebootMissedAlarmsAreDroppedAndTheRestReRegistered() = runTest {
        sync.sync(listOf(shift("a", 10), shift("b", 20), shift("c", 30)), SHIFT_PREFIX)
        alarms.held.clear() // the reboot
        val restored = sync.restore(nowMs = 20)
        assertEquals(1, restored.scheduled)
        assertEquals(setOf("${SHIFT_PREFIX}c"), alarms.held.keys)
        assertEquals(listOf("${SHIFT_PREFIX}c"), sync.registered().map { it.id })
    }

    @Test fun returningToTheAppRestoresOnlyWhenTheGrantChanged() = runTest {
        sync.sync(listOf(shift("a", 10), shift("b", 30)), SHIFT_PREFIX)
        assertNull("same grant: nothing to do", sync.revalidate(nowMs = 20))
        alarms.exact = false
        alarms.held.clear() // revoking drops the exact alarms without telling the app
        val result = sync.revalidate(nowMs = 20)!!
        assertEquals(setOf("${SHIFT_PREFIX}b"), alarms.held.keys)
        assertEquals(AlarmTiming.INEXACT, alarms.held.getValue("${SHIFT_PREFIX}b").second)
        assertEquals(false, result.exact)
        assertNull(sync.revalidate(nowMs = 21))
    }

    @Test fun aFiredAlarmIsPostedOnceAndOnlyWhileFresh() = runTest {
        sync.sync(listOf(shift("a", 10), shift("lunch", 20, expires = 140)), SHIFT_PREFIX)
        assertNull("not yet due", sync.take("${SHIFT_PREFIX}a", nowMs = 9))
        assertEquals("b", sync.take("${SHIFT_PREFIX}a", nowMs = 10)?.body)
        assertNull("a second delivery posts nothing", sync.take("${SHIFT_PREFIX}a", nowMs = 11))
        assertNull("a late break notice has lost its context", sync.take("${SHIFT_PREFIX}lunch", nowMs = 140))
        assertNull("an alarm the app no longer wants", sync.take("${SHIFT_PREFIX}gone", nowMs = 50))
        assertTrue(sync.registered().isEmpty())
    }

    @Test fun aDamagedRegistryReadsAsEmptyAndIsRewritten() = runTest {
        Files.createDirectories(file.parent)
        Files.writeString(file, "{not json")
        assertTrue(sync.registered().isEmpty())
        sync.sync(listOf(shift("a", 10)), SHIFT_PREFIX)
        assertEquals(listOf("${SHIFT_PREFIX}a"), sync.registered().map { it.id })
    }

    @Test fun theRegistryRoundTripsEveryField() = runTest {
        val reminder = shift("a", 10, body = "Lunch · 午休", channel = ReminderChannel.HEALTH, expires = 130)
        sync.sync(listOf(reminder), SHIFT_PREFIX)
        assertEquals(listOf(reminder), ReminderSync(file, alarms).registered())
    }
}
