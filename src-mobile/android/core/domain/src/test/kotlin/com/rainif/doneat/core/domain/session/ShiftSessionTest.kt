package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.records.DayOverrideKind
import com.rainif.doneat.core.domain.records.RecordEditContext
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.records.WorkObservationKind
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.settings.PreferencesRules
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Base64
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The iOS session behaviour (`OffWorkStoreTests`, `ShiftActionTests`) on the
 * pure Kotlin session. iOS runs these in the device calendar; here the
 * records and device zone are both [ZONE] unless a test says otherwise.
 */
class ShiftSessionTest {
    private class Harness(zone: String = "UTC", scheduleMode: String = "classic", start: Int = 9 * 60, end: Int = 17 * 60) {
        var prefs: SyncedPreferences = PreferencesRules.defaults(zone, 0.0).copy(
            scheduleMode = scheduleMode, workdays = listOf(1, 2, 3, 4, 5), startMinutes = start, endMinutes = end, lunchEnabled = false,
        )
        var state = SessionState()
        var records = RecordState()
        var deviceZone = zone
        private var ids = 0

        fun env() = SessionEnvironment(prefs, onboardingComplete = true, extendedSchedule = null, rosterDays = emptyList(), holidays = HolidayCalendar.EMPTY, deviceZone = deviceZone)
        val session get() = ShiftSession(state, env())
        private fun newId() = "00000000-0000-0000-0000-%012d".format(++ids)
        val commands get() = SessionCommands(env(), ::newId)

        /** Runs a command the way the store does: session state and archive together. */
        fun run(command: SessionCommands.() -> SessionResult): Boolean {
            val result = commands.command()
            if (!result.accepted) return false
            state = result.state
            val context = RecordEditContext(0.0, prefs.recordsTimeZoneIdentifier, canEdit = true, holidays = HolidayCalendar.EMPTY, currentHours = { session.hoursConfiguration(0.0) }, newId = ::newId)
            records = SessionRecords.apply(records, result.effects, context)
            return true
        }

        fun snapshot(at: Double) = requireNotNull(session.snapshot(at))
        fun phase(at: Double) = session.visualPhase(at)
    }

    private fun at(day: Int, hour: Int, minute: Int = 0, month: Int = 8, zone: String = ZONE) =
        LocalDateTime.of(2026, month, day, hour, minute).atZone(ZoneId.of(zone)).toInstant().toEpochMilli().toDouble()

    @Test fun `before clock-in the shared remaining time counts to the start`() {
        val h = Harness()
        val shift = h.snapshot(at(24, 8))
        assertTrue(shift.isBeforeStart(at(24, 8)))
        assertTrue(abs(shift.heroRemainingMs(at(24, 8)) - 3_600_000) < 1)
        assertEquals(TimerPhase.CLOCK_IN, h.phase(at(24, 8)))
    }

    @Test fun `clocking off early lands on completed and undo resumes`() {
        val h = Harness()
        val work = at(24, 11)
        assertTrue(h.run { start(h.state, work) })
        assertTrue(h.run { clockOffEarly(h.state, work) })
        val shift = h.snapshot(work)
        assertTrue(h.session.isEndedEarly(shift))
        assertTrue(h.session.isShiftComplete(shift))
        assertEquals(TimerPhase.COMPLETED, h.phase(work))
        assertTrue(h.state.countdownStarted)
        assertTrue(h.run { undoEarlyClockOff(h.state, work) })
        assertEquals(TimerPhase.RUNNING, h.phase(work))
    }

    @Test fun `overtime after an early clock-off resumes the shift`() {
        val h = Harness()
        val work = at(24, 11)
        h.run { start(h.state, work) }
        h.run { clockOffEarly(h.state, work) }
        assertTrue(h.run { applyOvertime(h.state, at(24, 20), work) })
        assertNull(h.state.earlyOffAtMs)
        assertFalse(h.session.isEndedEarly(h.snapshot(work)))
        assertEquals(TimerPhase.RUNNING, h.phase(work))
    }

    @Test fun `the next workday is not covered by yesterday's early clock-off`() {
        val h = Harness()
        h.run { start(h.state, at(24, 11)) }
        h.run { clockOffEarly(h.state, at(24, 11)) }
        val monday = h.session.clockOffSnapshot(h.snapshot(at(24, 11)))
        val tuesday = h.snapshot(at(25, 11))
        assertFalse(h.session.isEndedEarly(tuesday))
        assertEquals(TimerPhase.RUNNING, h.session.visualPhase(tuesday, at(25, 11)))
        assertTrue(monday.startAtMs != tuesday.startAtMs)
        assertEquals(tuesday.startAtMs, h.session.clockOffSnapshot(tuesday).startAtMs, 0.0)
    }

    @Test fun `an early clock-off snapshot stays frozen after later settings edits`() {
        val h = Harness()
        h.prefs = h.prefs.copy(
            lunchEnabled = true, lunchStartMinutes = 12 * 60, lunchDurationMinutes = 60,
            salaryEnabled = true, salaryType = "monthly", salaryAmount = "22000", monthlyWorkingDays = 22.0,
        )
        val afternoon = at(24, 14)
        h.run { start(h.state, afternoon) }
        h.run { clockOffEarly(h.state, afternoon) }
        val frozen = h.session.clockOffSnapshot(h.snapshot(afternoon))
        assertTrue(abs(frozen.elapsedMs - 4 * 3_600_000) < 1)
        val salary = requireNotNull(frozen.dailySalary)
        assertNotNull(h.session.takenLunchWindow(frozen, afternoon))

        h.prefs = h.prefs.copy(lunchEnabled = false)
        val afterLunchOff = h.snapshot(afternoon)
        val stillFrozen = h.session.clockOffSnapshot(afterLunchOff)
        assertEquals(frozen.segments, stillFrozen.segments)
        assertEquals(frozen.elapsedMs, stillFrozen.elapsedMs, 0.001)
        assertEquals(frozen.payRatio, stillFrozen.payRatio, 0.001)
        assertTrue(frozen.elapsedMs != afterLunchOff.elapsedMs)

        h.prefs = h.prefs.copy(lunchEnabled = true, salaryAmount = "44000")
        val afterSalary = h.snapshot(afternoon)
        assertEquals(salary, h.session.clockOffSnapshot(afterSalary).dailySalary)
        assertTrue(salary != afterSalary.dailySalary)

        h.run { undoEarlyClockOff(h.state, afternoon) }
        val afterUndo = h.snapshot(afternoon)
        assertEquals(afterUndo.elapsedMs, h.session.clockOffSnapshot(afterUndo).elapsedMs, 0.0)
    }

    @Test fun `clocking off during overtime keeps the overtime record`() {
        val h = Harness()
        h.run { start(h.state, at(24, 11)) }
        h.run { applyOvertime(h.state, at(24, 20), at(24, 11)) }
        assertTrue(h.run { clockOffEarly(h.state, at(24, 18)) })
        assertNotNull(h.state.overtimeEndAtMs)
        val shift = h.snapshot(at(24, 18))
        assertTrue(h.session.isEndedEarly(shift))
        assertEquals(TimerPhase.COMPLETED, h.session.visualPhase(shift, at(24, 18)))
        val frozen = h.session.clockOffSnapshot(shift)
        assertTrue(frozen.elapsedMs > frozen.plannedDurationMs)
        assertTrue(frozen.elapsedMs < frozen.durationMs)
    }

    @Test fun `repeated session actions write nothing more`() {
        val h = Harness()
        val actions: List<SessionCommands.() -> SessionResult> = listOf(
            { start(h.state, at(24, 8)) },
            { clockInEarly(h.state, at(24, 8)) },
            { clockOffEarly(h.state, at(24, 10)) },
            { applyOvertime(h.state, at(24, 19), at(24, 10)) },
        )
        for (action in actions) {
            assertTrue(h.run(action))
            val (state, records) = h.state to h.records
            assertFalse(h.run(action))
            assertEquals(state, h.state)
            assertEquals(records, h.records)
        }
        assertTrue(h.run { applyOvertime(h.state, at(24, 20), at(24, 10)) })
    }

    @Test fun `clocking in early moves the start to now and keeps the planned end`() {
        val h = Harness()
        val before = at(24, 8, 0) + 42_000
        h.run { start(h.state, before) }
        assertEquals(TimerPhase.CLOCK_IN, h.phase(before))
        assertTrue(h.run { clockInEarly(h.state, before) })
        assertEquals(at(24, 8), h.state.earlyStartAtMs)
        assertEquals(at(25, 0), h.state.earlyStartUntilMs)
        val running = h.snapshot(before)
        assertFalse(running.isBeforeStart(before))
        assertEquals(8 * 60, h.session.effectiveStartMinutes(before))
        assertEquals(17 * 60, h.session.effectiveEndMinutes(before))
        assertEquals(TimerPhase.RUNNING, h.phase(before))
        assertEquals(at(25, 9), running.nextShiftStartAtMs)

        h.run { undoEarlyClockIn(h.state, before) }
        assertTrue(h.snapshot(before).isBeforeStart(before))
    }

    @Test fun `early clock-in expires at the session's civil midnight`() {
        val h = Harness(zone = "Asia/Tokyo")
        val before = at(7, 8, month = 9, zone = "Asia/Tokyo")
        h.run { start(h.state, before) }
        h.run { clockInEarly(h.state, before) }
        assertEquals(at(8, 0, month = 9, zone = "Asia/Tokyo"), h.state.earlyStartUntilMs)
        assertTrue(h.run { reconcile(h.state, at(8, 0, 1, month = 9, zone = "Asia/Tokyo")) })
        assertNull(h.state.earlyStartAtMs)
    }

    @Test fun `starting in manual mode clears a leftover early clock-off`() {
        val h = Harness()
        h.run { start(h.state, at(24, 11)) }
        h.run { clockOffEarly(h.state, at(24, 11)) }
        h.prefs = h.prefs.copy(scheduleMode = "off")
        assertTrue(h.run { start(h.state, at(24, 11)) })
        assertNull(h.state.earlyOffAtMs)
        assertFalse(h.session.isEndedEarly(h.snapshot(at(24, 11))))
        assertEquals(TimerPhase.RUNNING, h.phase(at(24, 11)))
    }

    @Test fun `a forced overnight shift is still forced after midnight`() {
        val h = Harness(start = 22 * 60, end = 6 * 60)
        h.run { start(h.state, at(29, 23), force = true) }
        val before = h.snapshot(at(29, 23))
        assertFalse(before.isWorkday)
        assertTrue(h.session.isForcedWorkday(before))
        assertEquals(TimerPhase.RUNNING, h.phase(at(29, 23)))
        val after = h.snapshot(at(30, 3))
        assertEquals(before.startAtMs, after.startAtMs, 0.0)
        assertTrue(h.session.isForcedWorkday(after))
        assertEquals(TimerPhase.RUNNING, h.phase(at(30, 3)))
        assertFalse(h.run { reconcile(h.state, at(30, 3)) })
        assertTrue(h.session.isForcedWorkday(after))
    }

    @Test fun `a forced overnight shift settles until the end calendar day is over`() {
        val h = Harness(start = 22 * 60, end = 6 * 60)
        h.run { start(h.state, at(29, 23), force = true) }
        val settled = h.snapshot(at(30, 6, 30))
        assertTrue(h.session.isForcedWorkday(settled))
        assertTrue(settled.remainingMs <= 0)
        h.run { reconcile(h.state, at(30, 6, 30)) }
        assertEquals(TimerPhase.COMPLETED, h.phase(at(30, 6, 30)))
    }

    @Test fun `forcing an overnight shift after midnight marks the run on screen`() {
        val h = Harness(start = 22 * 60, end = 6 * 60)
        h.run { start(h.state, at(30, 1), force = true) }
        assertEquals("2026-08-29", h.state.forcedWorkdayDate)
        assertEquals(TimerPhase.RUNNING, h.phase(at(30, 1)))
    }

    @Test fun `a left-behind early clock-off is cleared on the next shift`() {
        val h = Harness()
        h.run { start(h.state, at(24, 11)) }
        h.run { clockOffEarly(h.state, at(24, 11)) }
        assertTrue(h.run { reconcile(h.state, at(25, 0, 30)) })
        assertNull(h.state.earlyOffAtMs)
        assertNull(h.state.earlyOffShiftEndAtMs)
        assertNull(h.state.earlyOffSnapshot)
    }

    @Test fun `cancelling rest-day manual timing returns to rest`() {
        val h = Harness()
        h.run { start(h.state, at(29, 11), force = true) }
        assertEquals(TimerPhase.RUNNING, h.phase(at(29, 11)))
        assertTrue(h.run { cancelManualTiming(h.state, at(29, 11)) })
        assertFalse(h.session.isForcedWorkday(h.snapshot(at(29, 11))))
        assertNull(h.state.earlyOffAtMs)
        assertEquals(TimerPhase.REST, h.phase(at(29, 11)))
    }

    @Test fun `unscheduled idle is its own phase, then a session, then midnight resets`() {
        val h = Harness(scheduleMode = "off")
        assertEquals(TimerPhase.UNSCHEDULED, h.phase(at(24, 10)))
        assertTrue(h.run { start(h.state, at(24, 10)) })
        assertEquals(TimerPhase.RUNNING, h.phase(at(24, 10)))
        h.run { clockOffEarly(h.state, at(24, 10)) }
        assertEquals(TimerPhase.COMPLETED, h.phase(at(24, 10)))
        assertTrue(h.run { reconcile(h.state, at(25, 10)) })
        assertEquals(TimerPhase.UNSCHEDULED, h.phase(at(25, 10)))
    }

    @Test fun `a manual run keeps its own zone until its civil midnight`() {
        val h = Harness(scheduleMode = "off")
        h.deviceZone = "Asia/Tokyo"
        val start = at(24, 1)
        assertTrue(h.run { start(h.state, start) })
        assertEquals("Asia/Tokyo", h.state.sessionTimeZone)
        val end = h.snapshot(start).endAtMs
        val midnight = ShiftSession.startOfNextDayMs(end, ZoneId.of("Asia/Tokyo"))
        assertFalse(h.run { reconcile(h.state, midnight - 60_000) })
        assertTrue(h.state.countdownStarted)
        assertTrue(h.run { reconcile(h.state, midnight + 60_000) })
        assertFalse(h.state.countdownStarted)
    }

    @Test fun `a schedule has no run to stop`() {
        val h = Harness()
        h.run { start(h.state, at(24, 10)) }
        assertFalse(h.run { stop(h.state, at(24, 10)) })
        val manual = Harness(scheduleMode = "off")
        manual.run { start(manual.state, at(24, 10)) }
        assertTrue(manual.run { stop(manual.state, at(24, 10)) })
        assertEquals(TimerPhase.UNSCHEDULED, manual.phase(at(24, 10)))
    }

    @Test fun `timer marks land in the archive as observations and today's override`() {
        val h = Harness()
        h.run { start(h.state, at(24, 8)) }
        assertEquals("the first observation seeds the career period", 1, h.records.periods.size)
        assertEquals(listOf(WorkObservationKind.COUNTDOWN_STARTED), h.records.observations.map { it.kind })
        assertTrue("arming the schedule marks nothing", h.records.overrides.isEmpty())

        h.run { clockInEarly(h.state, at(24, 8)) }
        h.run { clockOffEarly(h.state, at(24, 15)) }
        val override = h.records.overrides.single()
        assertEquals("2026-08-24", override.dayKey)
        assertEquals(DayOverrideKind.CUSTOM_SEGMENTS, override.kind)
        assertEquals(at(24, 8), override.segments.first().startAtMs, 0.0)
        assertEquals(at(24, 15), override.segments.last().endAtMs, 0.0)
        assertEquals("the clock-off revised the clock-in's row", 2, override.editCount)
        val snapshotId = h.records.snapshots.single().id
        assertTrue(h.records.observations.all { it.scheduleSnapshotID == snapshotId && it.shiftAnchorDate == "2026-08-24" })
    }

    @Test fun `an overtime declaration carries the payload the records read`() {
        val h = Harness()
        h.run { start(h.state, at(24, 10)) }
        h.run { applyOvertime(h.state, at(24, 19), at(24, 16)) }
        val row = h.records.observations.last()
        assertEquals(WorkObservationKind.OVERTIME_DECLARED, row.kind)
        val json = String(Base64.getDecoder().decode(row.valueData))
        assertEquals("{\"overtimeEndAtMs\":${at(24, 19).toLong()},\"plannedEndAtMs\":${at(24, 17).toLong()}}", json)
    }

    @Test fun `the timeline starts with clock-in and ends with clock-off`() {
        val h = Harness()
        h.prefs = h.prefs.copy(lunchEnabled = true, lunchStartMinutes = 12 * 60, lunchDurationMinutes = 60)
        val shift = h.snapshot(at(24, 8))
        val kinds = UpcomingTimeline.events(shift, at(24, 8), emptyList(), microBreakEnabled = false, milestonesEnabled = false).map { it.kind }
        assertEquals(listOf(TimelineKind.SHIFT_START, TimelineKind.LUNCH_START, TimelineKind.LUNCH_END, TimelineKind.SHIFT_END), kinds)
    }

    @Test fun `an overnight shift keeps its after-midnight break`() {
        val h = Harness(start = 22 * 60, end = 6 * 60)
        h.prefs = h.prefs.copy(lunchEnabled = true, lunchStartMinutes = 2 * 60, lunchDurationMinutes = 30)
        val now = at(24, 23)
        val events = UpcomingTimeline.events(h.snapshot(now), now, emptyList(), microBreakEnabled = false, milestonesEnabled = false)
        assertEquals(listOf(TimelineKind.LUNCH_START, TimelineKind.LUNCH_END, TimelineKind.SHIFT_END), events.map { it.kind })
        assertEquals(at(25, 2), events.first().atMs, 0.0)
    }

    @Test fun `clock-in progress starts near zero instead of showing remaining percent`() {
        val h = Harness()
        val progress = h.session.countdownToClockInProgress(h.snapshot(at(24, 0, 8)))
        assertTrue("$progress", progress > 1 && progress < 2)
    }

    private fun inputs() = com.rainif.doneat.core.domain.schedule.ReminderInputs(
        mode = "milestones", fallbackTitle = "Off", breakTitle = "Break",
        milestoneTitles = mapOf(50 to "50", 75 to "25", 90 to "10", 95 to "5", 100 to "Done"),
        milestoneMessages = mapOf(50 to listOf("a"), 75 to listOf("b"), 90 to listOf("c"), 95 to listOf("d"), 100 to listOf("Done")),
        lunchStartEnabled = false, lunchStartBody = "", lunchEndEnabled = false, lunchEndBody = "",
        microBreakEnabled = false, microBreakTitle = "", microBreakIntervalMinutes = 60, microBreakMessages = emptyList(),
        cycleEndSummaryBody = null,
    )

    @Test fun `rest days schedule no reminders for a phantom current shift`() {
        val h = Harness()
        h.run { start(h.state, at(29, 8)) }
        val alarms = ShiftReminderPlan.alarms(h.session, at(29, 8), inputs())
        assertTrue(alarms.isNotEmpty())
        assertTrue("only Monday's shift: ${alarms.map { it.id }}", alarms.all { it.atMs >= at(31, 9).toLong() })
    }

    @Test fun `an early clock-off drops the reminders that still belong to the ended shift`() {
        val h = Harness()
        h.run { start(h.state, at(24, 10)) }
        assertTrue(ShiftReminderPlan.alarms(h.session, at(24, 11), inputs()).any { it.atMs < at(25, 0).toLong() })
        h.run { clockOffEarly(h.state, at(24, 11)) }
        val after = ShiftReminderPlan.alarms(h.session, at(24, 11), inputs())
        assertTrue(after.isNotEmpty())
        assertTrue(after.all { it.atMs >= at(25, 9).toLong() })
    }

    // Share (iOS OffWorkStoreTests share cases)

    @Test fun `share copy before clock-in counts to the start, not the end`() {
        val h = Harness()
        val before = at(24, 8)
        assertTrue(h.run { start(h.state, before) })
        val share = ShareContent.of(h.session, before)
        assertEquals(ShareContent.Message.UNTIL_START, share.message)
        assertTrue(abs(share.messageRemainingMs - 3_600_000) < 1)
        assertFalse(share.isDone)
    }

    @Test fun `share while working counts to the end and reports progress`() {
        val h = Harness()
        h.run { start(h.state, at(24, 9)) }
        val share = ShareContent.of(h.session, at(24, 13))
        assertEquals(ShareContent.Message.COUNTDOWN, share.message)
        assertTrue(abs(share.messageRemainingMs - 4 * 3_600_000) < 1)
        assertEquals(50.0, share.progress, 0.01)
    }

    @Test fun `share after an early clock-off is done at the progress reached`() {
        val h = Harness()
        h.run { start(h.state, at(24, 9)) }
        h.run { clockOffEarly(h.state, at(24, 11)) }
        val share = ShareContent.of(h.session, at(24, 11, 30))
        assertEquals(ShareContent.Message.OFF_WORK, share.message)
        assertTrue(share.isDone)
        assertEquals(25.0, share.progress, 0.01)
    }

    @Test fun `share links stay on the web app and carry only the hours`() {
        val url = ShareContent.url(9 * 60, 18 * 60)
        assertTrue(url.startsWith("https://off.rainif.com/"))
        assertTrue(url.contains("s=0900-1800"))
        assertFalse(url.contains("doneat.app"))
        assertEquals("0000-0830", Regex("s=([0-9-]+)").find(ShareContent.url(24 * 60, 8 * 60 + 30))!!.groupValues[1])
    }

    // Ongoing notification (iOS LiveActivityDecision and the work eligibility in LiveActivityService)

    private fun phase(kind: com.rainif.doneat.core.domain.records.FocusSessionKind, start: Double, end: Double) =
        com.rainif.doneat.core.domain.records.FocusSession(
            "s", null, "2026-08-24", start, end, null, null, start, 0, "t", kind, ZONE, "2026-08-24", null,
            com.rainif.doneat.core.domain.records.FocusEndReason.COMPLETED,
        )

    @Test fun `a focus or break phase keeps the notification, even inside the clock-off window`() {
        val now = at(24, 16, 50)
        val work = OngoingWorkWindow(at(24, 16, 45), at(24, 17))
        val rest = phase(com.rainif.doneat.core.domain.records.FocusSessionKind.SHORT_BREAK, now - 60_000, now + 4 * 60_000)
        assertEquals(OngoingSurface.SHORT_BREAK, OngoingPlan.choose(work, rest, now)?.surface)
        assertEquals(OngoingSurface.SHORT_BREAK, OngoingPlan.choose(OngoingWorkWindow(now + 30 * 60_000, now + 60 * 60_000), rest, now)?.surface)
        // Once it ends, the shift's window takes over.
        assertEquals(OngoingSurface.WORK, OngoingPlan.choose(work, rest.copy(endedAtMs = now), now)?.surface)
    }

    @Test fun `the work countdown shows only inside its window`() {
        val work = OngoingWorkWindow(at(24, 16, 45), at(24, 17))
        assertNull(OngoingPlan.choose(work, null, at(24, 16, 44)))
        assertEquals(OngoingDecision(OngoingSurface.WORK, at(24, 17)), OngoingPlan.choose(work, null, at(24, 16, 45)))
        assertNull(OngoingPlan.choose(work, null, at(24, 17)))
    }

    @Test fun `the window opens before the planned end and runs to the overtime end`() {
        val h = Harness()
        h.run { start(h.state, at(24, 9)) }
        assertEquals(OngoingWorkWindow(at(24, 16, 45), at(24, 17)), OngoingPlan.workWindow(h.session, at(24, 10), 15))
        h.run { applyOvertime(h.state, at(24, 18), at(24, 10)) }
        assertEquals(OngoingWorkWindow(at(24, 16, 30), at(24, 18)), OngoingPlan.workWindow(h.session, at(24, 10), 30))
    }

    @Test fun `no work countdown before clock-in, on a rest day, or after clocking off`() {
        val h = Harness()
        h.run { start(h.state, at(24, 8)) }
        assertNull(OngoingPlan.workWindow(h.session, at(24, 8), 15))
        assertNull(OngoingPlan.workWindow(h.session, at(29, 12), 15))
        h.run { clockOffEarly(h.state, at(24, 12)) }
        assertNull(OngoingPlan.workWindow(h.session, at(24, 12, 5), 15))
    }

    @Test fun `the next change is the nearest window edge or phase end`() {
        val now = at(24, 10)
        val work = OngoingWorkWindow(at(24, 16, 45), at(24, 17))
        assertEquals(at(24, 16, 45), OngoingPlan.nextChangeAtMs(work, null, now))
        val focus = phase(com.rainif.doneat.core.domain.records.FocusSessionKind.FOCUS, now, now + 25 * 60_000)
        assertEquals(now + 25 * 60_000, OngoingPlan.nextChangeAtMs(work, focus, now))
        assertNull(OngoingPlan.nextChangeAtMs(null, null, now))
    }

    private companion object {
        const val ZONE = "UTC"
    }
}
