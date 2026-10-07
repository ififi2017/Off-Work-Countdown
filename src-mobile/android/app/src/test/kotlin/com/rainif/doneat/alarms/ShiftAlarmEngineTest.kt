package com.rainif.doneat.alarms

import com.rainif.doneat.core.domain.alarms.PlannedShiftAlarm
import com.rainif.doneat.core.domain.alarms.ShiftAlarmAuthorization
import com.rainif.doneat.plus.PlusStoreState
import com.rainif.doneat.plus.PlusStatus
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class ShiftAlarmEngineTest {
    private val now = 1_800_000_000_000L
    private fun alarm(offset: Long, number: Long = offset) = PlannedShiftAlarm(UUID(0, number), now + offset,
        now + offset + 3_600_000L, "2026-10-07", null, "Office")
    private fun plan(vararg alarms: PlannedShiftAlarm, end: Long? = now + 86_400_000L, enabled: Boolean = true, lifetime: Boolean = false) =
        AlarmPlan(enabled, end, lifetime, alarms.toList(), { "Work at ${it.shiftStartAtMs}" }, "Refresh", "Open DoneAt")
    private class FakePlatform : ShiftAlarmPlatform {
        var exact = true
        var notifications = true
        var held = mutableListOf<AlarmRegistration>()
        var failIDs = setOf<UUID>()
        var capacity = Int.MAX_VALUE
        var durableFailure = false
        var reminder: Long? = null
        val canceled = mutableListOf<UUID>()
        val scheduled = mutableListOf<AlarmRegistration>()
        val systemQueue = mutableSetOf<UUID>()
        override fun exactAllowed() = exact
        override fun notificationsAllowed() = notifications
        override fun registrations() = held.toList()
        override fun schedule(registration: AlarmRegistration): AlarmScheduleOutcome {
            if (registration.alarm.id in failIDs) { if (durableFailure) exact = false; return AlarmScheduleOutcome.FAILED }
            if (held.count { it.accepted } >= capacity && held.none { it.alarm.id == registration.alarm.id }) return AlarmScheduleOutcome.LIMIT
            held.removeAll { it.alarm.id == registration.alarm.id }
            held += registration.copy(accepted = true)
            scheduled += registration
            systemQueue += registration.alarm.id
            return AlarmScheduleOutcome.ACCEPTED
        }
        override fun markRinging(registration: AlarmRegistration): Boolean {
            held.removeAll { it.alarm.id == registration.alarm.id }; held += registration; return true
        }
        override fun cancel(id: UUID) { canceled += id; systemQueue -= id; held.removeAll { it.alarm.id == id } }
        override fun invalidateRegistrations() { held = held.map { it.copy(accepted = false, ringing = false) }.toMutableList() }
        override fun refreshReminder(atMs: Long?, title: String, body: String): Boolean { reminder = atMs; return atMs != null && notifications }
    }

    @Test fun disablingCancelsWaitingRingingSnoozingAndRefreshOnlyOurIDs() {
        val fake = FakePlatform()
        fake.held += AlarmRegistration(alarm(1_000), "work", accepted = true)
        fake.held += AlarmRegistration(alarm(2_000), "work", accepted = true, ringing = true)
        fake.held += AlarmRegistration(alarm(3_000), "work", accepted = true, snoozed = true)
        val status = ShiftAlarmEngine(fake).reconcile(plan(enabled = false), now)
        assertEquals(3, fake.canceled.size)
        assertTrue(fake.held.isEmpty()); assertTrue(fake.scheduled.isEmpty())
        assertTrue(status.accepted.isEmpty()); assertNull(fake.reminder)
    }

    @Test fun unverifiedAndExactExpiryCannotScheduleOrKeepAnAlarm() {
        for (end in listOf(null, now - 1, now)) {
            val fake = FakePlatform(); val due = alarm(1_000)
            fake.held += AlarmRegistration(due, "work", accepted = true)
            val status = ShiftAlarmEngine(fake).reconcile(plan(due, end = end), now)
            assertFalse(status.entitlementAllowed); assertTrue(fake.held.isEmpty()); assertTrue(fake.scheduled.isEmpty())
        }
    }

    @Test fun permissionRevocationOrHiddenNotificationsCancelsRingingToo() {
        for (notificationDenied in listOf(false, true)) {
            val fake = FakePlatform().apply { exact = notificationDenied; notifications = !notificationDenied }
            fake.held += AlarmRegistration(alarm(-1_000), "work", accepted = true, ringing = true)
            val status = ShiftAlarmEngine(fake).reconcile(plan(alarm(10_000)), now)
            assertTrue(status.accepted.isEmpty()); assertTrue(fake.held.isEmpty())
        }
    }

    @Test fun coverageReportsOnlyAcceptedAlarmsAndStopsAtFirstGap() {
        val fake = FakePlatform(); val first = alarm(10_000); val middle = alarm(20_000); val last = alarm(30_000)
        fake.failIDs = setOf(middle.id)
        val status = ShiftAlarmEngine(fake).reconcile(plan(last, middle, first, lifetime = true), now)
        assertEquals(listOf(first, last), status.accepted)
        assertEquals(first.fireAtMs, status.coveredThroughMs)
        assertEquals(1, status.failedCount)
    }

    @Test fun nearestAlarmReplacesLaterRegistrationAtActualPlatformLimit() {
        val fake = FakePlatform(); fake.capacity = 1
        val early = alarm(10_000); val late = alarm(30_000)
        fake.held += AlarmRegistration(late, "Work at ${late.shiftStartAtMs}", accepted = true)
        val status = ShiftAlarmEngine(fake).reconcile(plan(early, late), now)
        assertEquals(listOf(early), status.accepted)
        assertTrue(status.reachedSystemLimit)
        assertTrue(late.id in fake.canceled)
    }

    @Test fun coldStartupPreservesDueDeliveryWithoutSchedulingOrRingingItAgain() {
        val fake = FakePlatform(); val due = alarm(-1_000)
        val registration = AlarmRegistration(due, "Work at ${due.shiftStartAtMs}", token = "real-token", accepted = true)
        fake.held += registration
        val engine = ShiftAlarmEngine(fake); val plan = plan(due)
        val status = engine.reconcile(plan, now)
        assertTrue(fake.scheduled.isEmpty()); assertFalse(fake.held.single().ringing); assertTrue(status.accepted.isEmpty())
        assertNull(engine.receive(due.id, "forged", plan, now))
        assertNotNull(engine.receive(due.id, "real-token", plan, now))
        assertNull(engine.receive(due.id, "real-token", plan, now))
    }

    @Test fun scheduleChangesOrEarlyReplayCannotStartAudio() {
        val fake = FakePlatform(); val future = alarm(10_000)
        fake.held += AlarmRegistration(future, "work", token = "t", accepted = true)
        val engine = ShiftAlarmEngine(fake)
        assertNull(engine.receive(future.id, "t", plan(future), now))
        assertNull(engine.receive(UUID.randomUUID(), "t", plan(future), now + 10_000))
        assertNull(engine.receive(future.id, "t", plan(), now + 10_000))
        assertTrue(fake.held.isEmpty())
    }

    @Test fun snoozeUsesNineMinutesFreshTokenAndExactVerifiedBoundary() {
        val fake = FakePlatform(); val due = alarm(-1_000)
        fake.held += AlarmRegistration(due, "work", token = "t", accepted = true, ringing = true)
        val engine = ShiftAlarmEngine(fake)
        assertTrue(engine.snooze(due.id, "t", plan(due), now))
        val snoozed = fake.held.single()
        assertEquals(now + 9 * 60_000, snoozed.scheduledAtMs)
        assertNotEquals("t", snoozed.token)
        assertNull(engine.receive(due.id, "t", plan(due), snoozed.scheduledAtMs))
        assertNotNull(engine.receive(due.id, snoozed.token, plan(due), snoozed.scheduledAtMs))
        assertFalse(engine.snooze(due.id, snoozed.token, plan(due, end = snoozed.scheduledAtMs + 9 * 60_000), snoozed.scheduledAtMs))
        assertTrue(fake.held.isEmpty())
    }

    @Test fun expiryWhileRingingPreventsBothCurrentAccessAndSnooze() {
        val fake = FakePlatform(); val due = alarm(-1_000)
        fake.held += AlarmRegistration(due, "work", token = "t", accepted = true, ringing = true)
        val engine = ShiftAlarmEngine(fake)
        assertNull(engine.current(due.id, "t", plan(end = now), now))
        assertFalse(engine.snooze(due.id, "t", plan(end = now), now))
        assertTrue(fake.held.isEmpty())
    }

    @Test fun bootInvalidatesAcceptanceAndOnlyReschedulesFuture() {
        val fake = FakePlatform(); val past = alarm(-1_000); val next = alarm(10_000)
        fake.held += AlarmRegistration(past, "Work at ${past.shiftStartAtMs}", accepted = true)
        fake.held += AlarmRegistration(next, "Work at ${next.shiftStartAtMs}", accepted = true)
        fake.invalidateRegistrations()
        val engine = ShiftAlarmEngine(fake)
        val status = engine.reconcile(plan(past, next), now)
        assertEquals(listOf(next), status.accepted)
        assertEquals(listOf(next), fake.scheduled.map { it.alarm })
        assertNull(engine.receive(past.id, fake.held.first { it.alarm.id == past.id }.token, plan(past, next), now))
    }
    @Test fun signedCachedOfflineExpiryAuthorizesButClientCacheWithoutExpiryDoesNot() {
        val cached = PlusStoreState(PlusStatus.SUBSCRIBED, verifiedSubscriptionExpiresAtMs = now + 60_000,
            currentEntitlementsVerified = false)
        assertEquals(ShiftAlarmAuthorization.VerifiedUntil(now + 60_000), cached.shiftAlarmAuthorization(now))
        assertEquals(ShiftAlarmAuthorization.Unavailable, cached.shiftAlarmAuthorization(now + 60_000))
        assertEquals(ShiftAlarmAuthorization.Unavailable, cached.copy(verifiedSubscriptionExpiresAtMs = null).shiftAlarmAuthorization(now))
    }

    @Test fun scheduleFailureNeverReportsOrDeliversAnUnconfirmedRegistration() {
        val fake = FakePlatform(); val next = alarm(10_000)
        fake.failIDs = setOf(next.id)
        fake.held += AlarmRegistration(next, "Work at ${next.shiftStartAtMs}", token = "unconfirmed", accepted = false)
        val engine = ShiftAlarmEngine(fake)
        val status = engine.reconcile(plan(next, lifetime = true), now)
        assertTrue(status.accepted.isEmpty()); assertNull(status.coveredThroughMs); assertNull(status.refreshReminderAtMs)
        assertEquals(1, status.failedCount)
        assertNull(engine.receive(next.id, "unconfirmed", plan(next), next.fireAtMs))
    }

    @Test fun adoptedLeaveOrChangedShiftCancelsRingingAndSnoozedOriginalShift() {
        for (snoozed in listOf(false, true)) {
            val fake = FakePlatform(); val old = alarm(-30 * 60_000)
            fake.held += AlarmRegistration(old, "Work at ${old.shiftStartAtMs}", scheduledAtMs = now + 5_000,
                accepted = true, ringing = !snoozed, snoozed = snoozed)
            ShiftAlarmEngine(fake).reconcile(plan(), now)
            assertTrue(fake.held.isEmpty()); assertEquals(listOf(old.id), fake.canceled)
        }
    }

    @Test fun rebootRestoresFutureSnoozeWithoutReplayingOriginalAlarm() {
        val fake = FakePlatform(); val original = alarm(-10 * 60_000)
        fake.held += AlarmRegistration(original, "Work at ${original.shiftStartAtMs}", scheduledAtMs = now + 60_000,
            token = "old", accepted = true, snoozed = true)
        fake.invalidateRegistrations()
        val engine = ShiftAlarmEngine(fake)
        engine.reconcile(plan(original), now)
        val restored = fake.held.single()
        assertEquals(now + 60_000, restored.scheduledAtMs)
        assertTrue(restored.accepted); assertTrue(restored.snoozed); assertFalse(restored.ringing)
        assertNotEquals("old", restored.token)
        assertNull(engine.receive(original.id, restored.token, plan(original), now))
    }

    @Test fun permissionRegrantRebuildsClearedSystemQueueDespiteAcceptedDiskLedger() {
        val fake = FakePlatform(); val next = alarm(10_000); val later = alarm(20_000)
        val engine = ShiftAlarmEngine(fake)
        engine.reconcile(plan(next, later), now)
        val oldTokens = fake.held.map { it.token }.toSet()
        // Exact permission revocation kills the process and clears Android's queue, leaving disk untouched.
        fake.systemQueue.clear()
        assertTrue(fake.held.all { it.accepted })
        fake.invalidateRegistrations()
        val status = engine.reconcile(plan(next, later), now)
        assertEquals(setOf(next.id, later.id), fake.systemQueue)
        assertEquals(listOf(next, later), status.accepted)
        assertTrue(fake.held.all { !it.ringing && it.token !in oldTokens })
    }

    @Test fun durableLedgerFailureRevokesPreviousCoverageAndCancelsRemainingOwnedQueue() {
        val fake = FakePlatform(); val first = alarm(10_000); val later = alarm(20_000)
        val engine = ShiftAlarmEngine(fake)
        engine.reconcile(plan(first), now)
        fake.failIDs = setOf(later.id); fake.durableFailure = true
        val status = engine.reconcile(plan(first, later), now)
        assertFalse(status.exactAllowed)
        assertTrue(status.accepted.isEmpty()); assertNull(status.coveredThroughMs)
        assertTrue(fake.systemQueue.isEmpty()); assertTrue(fake.held.isEmpty())
    }

}
