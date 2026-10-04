package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.alarms.PlannedShiftAlarm
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.file.Files
import java.util.UUID

class ShiftAlarmSyncTest {
    @get:Rule val folder = TemporaryFolder()
    private val file get() = folder.root.toPath().resolve("alarms.json")
    private val until = 100_000_000L
    private val now = 1_000_000L
    private fun entry(n: Int, at: Long = now + n * 86_400L) = ShiftAlarmEntry(
        PlannedShiftAlarm(UUID(0, n.toLong()), at, at + 3_600_000, "2026-10-0$n", null, null), "Work", until)
    private inner class Port : ShiftAlarmPort {
        var allowed = true
        var refresh: Long? = null
        var calls = 0
        var journalBeforeRegistration = true
        val held = mutableMapOf<UUID, ShiftAlarmEntry>()
        val refuse = mutableSetOf<UUID>()
        override fun permitted() = allowed
        override fun schedule(entry: ShiftAlarmEntry) {
            calls++
            journalBeforeRegistration = journalBeforeRegistration && Files.readString(file).contains(entry.alarm.id.toString())
            if (entry.alarm.id in refuse) error("system limit")
            held[entry.alarm.id] = entry
        }
        override fun cancel(id: UUID) { held.remove(id) }
        override fun scheduleRefresh(atMs: Long) { refresh = atMs }
        override fun cancelRefresh() { refresh = null }
    }

    @Test fun `journal precedes registration and identical plan has no system churn`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port)
        val wanted = listOf(entry(1), entry(2))
        sync.reconcile(true, until, true, wanted, now)
        sync.reconcile(true, until, true, wanted, now)
        assertTrue(port.journalBeforeRegistration)
        assertEquals(2, port.calls)
        assertEquals(wanted, sync.state.value.entries)
        assertEquals(wanted.last().alarm.fireAtMs + 600_000, port.refresh)
        assertEquals(sync.state.value, ShiftAlarmSync(file, port).state.value)
    }

    @Test fun `verified renewal updates delivery deadline without reregistering identical alarms`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
        sync.reconcile(true, until, false, listOf(e), now)
        sync.reconcile(true, until + 1_000, false, listOf(e), now)
        assertEquals(1, port.calls)
        assertEquals(until + 1_000, sync.state.value.entries.single().untilMs)
    }

    @Test fun `unlock broadcast preserves a currently ringing alarm`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
        sync.reconcile(true, until, true, listOf(e, entry(2)), now)
        sync.take(e.alarm.id, e.alarm.fireAtMs)
        sync.restore(e.alarm.fireAtMs + 1, afterReboot = false)
        assertEquals(ShiftAlarmEntry.Phase.RINGING, sync.state.value.entries.first { it.alarm.id == e.alarm.id }.phase)
    }

    @Test fun `actual coverage ends at first rejection and refresh follows last success`() = runTest {
        val port = Port(); port.refuse.add(entry(2).alarm.id)
        val sync = ShiftAlarmSync(file, port)
        sync.reconcile(true, until, false, (1..3).map { entry(it) }, now)
        assertEquals(listOf(entry(1), entry(3)), sync.state.value.entries)
        assertEquals(entry(1).alarm.fireAtMs, sync.state.value.coveredThroughMs)
        assertEquals(entry(3).alarm.fireAtMs + 600_000, port.refresh)
        assertEquals(1, sync.state.value.failed)
        port.refuse.clear()
        sync.reconcile(true, until, false, (1..3).map { entry(it) }, now)
        assertEquals(4, port.calls)
        assertEquals(0, sync.state.value.failed)
    }

    @Test fun `schedule edits replace alarms and revoke stale pending intents`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port)
        sync.reconcile(true, until, true, listOf(entry(1), entry(2)), now)
        sync.reconcile(true, until, true, listOf(entry(2), entry(3)), now)
        assertEquals(setOf(entry(2).alarm.id, entry(3).alarm.id), port.held.keys)
        assertNull(sync.take(entry(1).alarm.id, entry(1).alarm.fireAtMs))
    }

    @Test fun `delivery is once only and cold reconcile retains the due token`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
        sync.reconcile(true, until, true, listOf(e), now)
        sync.reconcile(true, until, true, listOf(e), e.alarm.fireAtMs + 100, rearm = true)
        assertNotNull(sync.take(e.alarm.id, e.alarm.fireAtMs + 100))
        assertNull(sync.take(e.alarm.id, e.alarm.fireAtMs + 200))
        sync.stop(e.alarm.id)
        assertTrue(sync.state.value.entries.isEmpty())
        assertTrue(port.held.isEmpty())
    }

    @Test fun `snooze is nine minutes and survives a plan update and process restart`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
        sync.reconcile(true, until, true, listOf(e), now)
        sync.take(e.alarm.id, e.alarm.fireAtMs)
        assertTrue(sync.snooze(e.alarm.id, e.alarm.fireAtMs))
        val expected = e.alarm.fireAtMs + 540_000
        assertEquals(expected + 600_000, port.refresh)
        sync.reconcile(true, until, true, emptyList(), e.alarm.fireAtMs + 1)
        assertEquals(expected + 600_000, port.refresh)
        val restarted = ShiftAlarmSync(file, port)
        assertEquals(expected, restarted.state.value.entries.single().alarm.fireAtMs)
        assertNull(restarted.take(e.alarm.id, expected - 1))
        assertNotNull(restarted.take(e.alarm.id, expected))
    }

    @Test fun `snooze at exact paid boundary is refused without creating an alarm`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
        val expiry = e.alarm.fireAtMs + 540_000
        sync.reconcile(true, expiry, false, listOf(e), now)
        sync.take(e.alarm.id, e.alarm.fireAtMs)
        assertFalse(sync.snooze(e.alarm.id, e.alarm.fireAtMs))
        assertEquals(1, port.calls)
    }

    @Test fun `disable expiry and permission loss clear ringing scheduled and refresh`() = runTest {
        for (condition in 0..2) {
            val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
            sync.reconcile(true, until, true, listOf(e, entry(2)), now)
            sync.take(e.alarm.id, e.alarm.fireAtMs)
            if (condition == 2) port.allowed = false
            sync.reconcile(condition != 0, if (condition == 1) now else until, true, listOf(e), now)
            assertTrue(sync.state.value.entries.isEmpty()); assertTrue(port.held.isEmpty()); assertNull(port.refresh)
        }
    }

    @Test fun `reboot restores future only and never backfills a missed or ringing alarm`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port)
        sync.reconcile(true, until, true, (1..3).map { entry(it) }, now)
        sync.take(entry(1).alarm.id, entry(1).alarm.fireAtMs)
        port.held.clear()
        val restarted = ShiftAlarmSync(file, port)
        restarted.restore(entry(2).alarm.fireAtMs + 1)
        assertEquals(setOf(entry(3).alarm.id), port.held.keys)
        assertEquals(listOf(entry(3)), restarted.state.value.entries)
    }

    @Test fun `late delivery and expired paid evidence cannot ring`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
        sync.reconcile(true, until, false, listOf(e), now)
        assertNull(sync.take(e.alarm.id, e.alarm.fireAtMs + ShiftAlarmSync.DELIVERY_GRACE_MS))
        sync.reconcile(true, e.alarm.fireAtMs + 10, false, listOf(e), now)
        assertNull(sync.take(e.alarm.id, e.alarm.fireAtMs + 10))
    }

    @Test fun `crash during registration is retried but never claimed as accepted`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
        sync.reconcile(true, until, true, listOf(e), now)
        Files.writeString(file, Files.readString(file).replace("WAITING", "REGISTERING"))
        val restarted = ShiftAlarmSync(file, port)
        assertTrue(restarted.state.value.waiting(now).isEmpty())
        assertNull(restarted.take(e.alarm.id, e.alarm.fireAtMs))
        restarted.restore(now)
        assertEquals(listOf(e), restarted.state.value.waiting(now))
    }

    @Test fun `refresh survives reboot after the last alarm has been stopped`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
        sync.reconcile(true, until, true, listOf(e), now)
        sync.take(e.alarm.id, e.alarm.fireAtMs)
        sync.stop(e.alarm.id)
        val restarted = ShiftAlarmSync(file, port)
        restarted.restore(e.alarm.fireAtMs + 100)
        assertEquals(e.alarm.fireAtMs + 600_000, port.refresh)
    }

    @Test fun `alarm settings are local and survive an atomic settings write`() = runTest {
        val settings = DeviceSettingsStore(folder.root.toPath().resolve("settings.json"))
        val type = UUID.randomUUID()
        settings.update { it.copy(shiftAlarms = com.rainif.doneat.core.domain.alarms.ShiftAlarmSettings(true, 90, mapOf(type to 30), setOf(type))) }
        assertEquals(settings.settings.value, DeviceSettingsStore(folder.root.toPath().resolve("settings.json")).settings.value)
    }

    @Test fun `corrupt journal fails closed and refresh consumes once`() = runTest {
        val port = Port(); val sync = ShiftAlarmSync(file, port); val e = entry(1)
        sync.reconcile(true, until, true, listOf(e), now)
        val at = port.refresh!!
        assertFalse(sync.takeRefresh(at - 1)); assertTrue(sync.takeRefresh(at)); assertFalse(sync.takeRefresh(at))
        Files.writeString(file, "{broken")
        val restarted = ShiftAlarmSync(file, port)
        assertNull(restarted.take(e.alarm.id, e.alarm.fireAtMs)); assertFalse(restarted.state.value.enabled)
    }
}
