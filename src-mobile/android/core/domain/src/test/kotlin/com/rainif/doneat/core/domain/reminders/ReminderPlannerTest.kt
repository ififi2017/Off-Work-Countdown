package com.rainif.doneat.core.domain.reminders

import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.RecordTestFixtures
import com.rainif.doneat.core.domain.records.ScheduleHoursCodec
import com.rainif.doneat.core.domain.records.SnapshotHours
import com.rainif.doneat.core.domain.records.WorkObservation
import com.rainif.doneat.core.domain.records.WorkObservationKind
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ReminderInputs
import com.rainif.doneat.core.domain.schedule.ReminderKind
import com.rainif.doneat.core.domain.schedule.ReminderRules
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.ShiftTimeline
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderPlannerTest {
    private val ms = RecordTestFixtures::ms
    private val monday = "2026-08-31"
    private val shift = ShiftTimeline(listOf(ShiftSegment(ms(monday, 9, 0), ms(monday, 12, 0)), ShiftSegment(ms(monday, 13, 0), ms(monday, 18, 0))), ms(monday, 18, 0))

    private fun inputs(mode: String = "milestones", summary: String? = null, interval: Int = 60, microBreak: Boolean = true) = ReminderInputs(
        mode = mode, fallbackTitle = "Off work reminder", breakTitle = "Break",
        milestoneTitles = mapOf(50 to "50%", 75 to "25% left", 90 to "10% left", 95 to "5% left", 100 to "Off work time"),
        milestoneMessages = emptyMap(),
        lunchStartEnabled = true, lunchStartBody = "Lunch", lunchEndEnabled = true, lunchEndBody = "Back",
        microBreakEnabled = microBreak, microBreakTitle = "Stretch", microBreakIntervalMinutes = interval, microBreakMessages = listOf("{{minutes}} min in"),
        cycleEndSummaryBody = summary,
    )

    private fun scoped(scope: String, i: ReminderInputs) = ReminderRules.buildShiftReminders(shift, i).map { it.copy(id = "$scope:${it.id}") }

    // Cycle-end summary

    @Test fun theSummaryUsesTheContiguousWorkRunBeforeRest() {
        val days = listOf(
            ScheduleCycleDay("2026-08-30", false, 0, 0),
            ScheduleCycleDay("2026-08-31", true, 8, 1),
            ScheduleCycleDay("2026-09-01", true, 7, 2),
            ScheduleCycleDay("2026-09-02", false, 0, 0),
        )
        assertEquals(ScheduleCycleSummary(2, 15, 3), ScheduleCycleSummaryCalculator.summary("2026-09-01", days))
        assertNull("mid-cycle", ScheduleCycleSummaryCalculator.summary("2026-08-31", days))
    }

    @Test fun anUnresolvedFollowingDayIsNeverReadAsRest() {
        val days = listOf(ScheduleCycleDay("2026-09-01", true, 8, 0), ScheduleCycleDay("2026-09-02", false, 0, 0, isComplete = false))
        assertNull(ScheduleCycleSummaryCalculator.summary("2026-09-01", days))
        assertNull("no following day at all", ScheduleCycleSummaryCalculator.summary("2026-09-01", days.take(1)))
    }

    @Test fun cycleDaysResolveFromTheArchiveWithDeclaredOvertime() {
        val hours = SnapshotHours("09:00", "18:00", listOf(1, 2, 3, 4, 5), "classic", breakStartTime = "12:00", breakDurationMinutes = 60)
        val data = FoundationCompat.base64(ScheduleHoursCodec.encode(hours).data)
        val thursday = "2026-09-03"
        val payload = FoundationCompat.base64("""{"overtimeEndAtMs":${ms(thursday, 19, 30).toLong()},"plannedEndAtMs":${ms(thursday, 18, 0).toLong()}}""".toByteArray())
        val overtime = WorkObservation(RecordTestFixtures.id(9), thursday, ms(thursday, 19, 30), WorkObservationKind.OVERTIME_DECLARED, payload, RecordTestFixtures.id(2), 2, RecordTestFixtures.ZONE, 0.0, 0, "T")
        val state = RecordState(
            periods = listOf(RecordTestFixtures.period(RecordTestFixtures.id(1), "2026-07-01")),
            snapshots = listOf(RecordTestFixtures.snapshot(RecordTestFixtures.id(2), RecordTestFixtures.id(1), "2026-07-01", "f", data = data)),
            observations = listOf(overtime),
        )
        val friday = "2026-09-04"
        val days = ScheduleCycleSummaryCalculator.days(state, friday, HolidayCalendar.EMPTY)
        assertEquals(33, days.size)
        assertEquals(ScheduleCycleSummary(5, 5 * 8 * 3_600_000L, 90 * 60_000L), ScheduleCycleSummaryCalculator.summary(friday, days))
        assertNull("Thursday is followed by a workday", ScheduleCycleSummaryCalculator.summary(thursday, days))
        val prefs = com.rainif.doneat.core.domain.settings.PreferencesRules.defaults(RecordTestFixtures.ZONE, 0.0).copy(
            scheduleMode = "classic", startMinutes = 9 * 60, endMinutes = 18 * 60,
            workdays = listOf(1, 2, 3, 4, 5), lunchEnabled = true, lunchStartMinutes = 12 * 60,
            lunchDurationMinutes = 60, cycleEndSummaryNotificationEnabled = true,
        )
        val session = com.rainif.doneat.core.domain.session.ShiftSession(
            com.rainif.doneat.core.domain.session.SessionState(countdownStarted = true),
            com.rainif.doneat.core.domain.session.SessionEnvironment(prefs, true, null, emptyList(), HolidayCalendar.EMPTY, RecordTestFixtures.ZONE),
        )
        val lastShift = session.snapshot(ms(friday, 10, 0))!!
        assertEquals(ScheduleCycleSummary(5, 5 * 8 * 3_600_000L, 90 * 60_000L), ScheduleCycleSummaryCalculator.forShift(state, session, lastShift, true))
        assertNull(ScheduleCycleSummaryCalculator.forShift(state, session, lastShift, false))
        assertNull(ScheduleCycleSummaryCalculator.forShift(state, session, session.snapshot(ms(thursday, 10, 0))!!, true))
    }

    @Test fun theLatestDeclarationWinsAndOvertimeNeverOverlapsRegularWork() {
        val thursday = "2026-09-03"
        val day = com.rainif.doneat.core.domain.records.DayResolution(
            thursday, com.rainif.doneat.core.domain.records.DayResolutionLayer.OVERRIDE, null, null, true,
            listOf(ShiftSegment(ms(thursday, 9, 0), ms(thursday, 19, 0))),
            baseScheduleIsWorkday = true, baseScheduleSegments = listOf(ShiftSegment(ms(thursday, 9, 0), ms(thursday, 18, 0))),
        )
        fun declared(n: Int, occurred: Double, end: Double) = WorkObservation(
            RecordTestFixtures.id(n), thursday, occurred, WorkObservationKind.OVERTIME_DECLARED,
            FoundationCompat.base64("""{"overtimeEndAtMs":${end.toLong()},"plannedEndAtMs":${ms(thursday, 18, 0).toLong()}}""".toByteArray()),
            RecordTestFixtures.id(2), 2, RecordTestFixtures.ZONE, 0.0, 0, "T",
        )
        val segments = ScheduleCycleSummaryCalculator.overtimeSegments(day, listOf(
            declared(1, ms(thursday, 20, 0), ms(thursday, 20, 0)),
            declared(2, ms(thursday, 19, 0), ms(thursday, 21, 0)),
        ))
        // The later declaration (20:00) wins, and the day edited to end at 19:00 moves its start.
        assertEquals(listOf(ShiftSegment(ms(thursday, 19, 0), ms(thursday, 20, 0))), segments)
    }

    @Test fun aBreakShorterThanTheFreshnessWindowExpiresWhenItEnds() {
        val short = ShiftTimeline(listOf(ShiftSegment(ms(monday, 9, 0), ms(monday, 12, 0)), ShiftSegment(ms(monday, 12, 1), ms(monday, 18, 0))), ms(monday, 18, 0))
        val start = ReminderRules.buildShiftReminders(short, inputs()).single { it.kind == ReminderKind.BREAK_START }
        assertEquals(ms(monday, 12, 1), start.expiresAtMs!!, 0.0)
    }

    // Planning

    @Test fun withProgressOffTheCycleSummaryStillRingsOnceAtClockOff() {
        val list = ReminderRules.buildShiftReminders(shift, inputs(mode = "off", summary = "  5 days, 40 h  ", microBreak = false))
        val alarms = ReminderPlanner.shiftAlarms(list.map { it.copy(id = "current:${it.id}") }, ms(monday, 8, 0))
        val end = alarms.filter { it.atMs == ms(monday, 18, 0).toLong() }
        assertEquals(1, end.size)
        assertEquals("5 days, 40 h", end.single().body)
        assertTrue("no other progress alarm", alarms.none { it.id.contains("milestone:") && it.atMs != ms(monday, 18, 0).toLong() })
    }

    @Test fun simpleModeRingsOnlyAtClockOffAndMilestonesModeRingsEachStep() {
        val simple = ReminderPlanner.shiftAlarms(ReminderRules.buildShiftReminders(shift, inputs(mode = "simple", microBreak = false)), ms(monday, 8, 0))
        assertEquals(listOf("milestone:100"), simple.filter { it.channel == ReminderChannel.SHIFT && it.id.contains("milestone") }.map { it.id.substringAfter("owc.shift.") })
        val all = ReminderPlanner.shiftAlarms(ReminderRules.buildShiftReminders(shift, inputs(microBreak = false)), ms(monday, 8, 0))
        assertEquals(5, all.count { it.id.contains("milestone") })
    }

    @Test fun aRestDayWindowIsNotRemindedButTheNextShiftIs() {
        val list = ReminderPlanner.shiftReminders(scoped("current", inputs()), scoped("next", inputs()), includeCurrent = false)
        assertTrue(list.isNotEmpty() && list.all { it.id.startsWith("next:") })
        assertEquals(list.size * 2, ReminderPlanner.shiftReminders(scoped("current", inputs()), scoped("next", inputs()), includeCurrent = true).size)
    }

    @Test fun onlyFutureAudibleRemindersBecomeAlarms() {
        val alarms = ReminderPlanner.shiftAlarms(ReminderRules.buildShiftReminders(shift, inputs(microBreak = false)), ms(monday, 14, 0))
        assertTrue(alarms.all { it.atMs > ms(monday, 14, 0) })
        assertTrue("disabled health reminders are listed by the rules but never scheduled", alarms.none { it.channel == ReminderChannel.HEALTH })
    }

    @Test fun frequentHealthRemindersNeverCrowdOutClockOff() {
        val alarms = ReminderPlanner.shiftAlarms(ReminderRules.buildShiftReminders(shift, inputs(interval = 1)), ms(monday, 8, 0))
        assertEquals(ReminderPlanner.MAX_SHIFT_ALARMS, alarms.size)
        assertTrue(alarms.any { it.id == "owc.shift.milestone:100" })
        assertEquals("essential first", ReminderChannel.SHIFT, alarms.first().channel)
    }

    @Test fun afterAnEarlyClockOffOnlyTheNextShiftRemains() {
        val list = scoped("current", inputs()) + scoped("next", inputs()).map { it.copy(atMs = it.atMs + 86_400_000) }
        val nextStart = ms(monday, 9, 0) + 86_400_000
        val alarms = ReminderPlanner.shiftAlarms(list, ms(monday, 10, 0), endedEarlyNextShiftStartMs = nextStart)
        assertTrue(alarms.isNotEmpty() && alarms.all { it.atMs >= nextStart })
        assertTrue("no next shift: nothing", ReminderPlanner.shiftAlarms(list, ms(monday, 10, 0), Double.POSITIVE_INFINITY).isEmpty())
    }

    @Test fun alarmTimesAreWholeMillisecondsNeverEarly() {
        val r = ReminderRules.buildShiftReminders(shift, inputs()).first().copy(atMs = 1_000.25)
        assertEquals(1_001L, ReminderPlanner.shiftAlarms(listOf(r), 0.0).single().atMs)
    }

    // Diff and restore

    private fun planned(id: String, at: Long, body: String = "b") = PlannedReminder(id, at, ReminderChannel.SHIFT, "t", body)

    @Test fun theDiffKeepsUnchangedAlarmsReplacesChangedOnesAndCancelsStaleOnes() {
        val registered = listOf(planned("owc.shift.a", 10), planned("owc.shift.b", 20), planned("owc.shift.c", 30), planned("owc.focus.x.end", 40))
        val desired = listOf(planned("owc.shift.a", 10), planned("owc.shift.b", 25), planned("owc.shift.c", 30, body = "new"), planned("owc.shift.d", 50))
        val diff = ReminderPlanner.diff(registered, desired, ReminderPlanner.SHIFT_PREFIX)
        assertEquals(listOf("owc.shift.b", "owc.shift.c", "owc.shift.d"), diff.schedule.map { it.id })
        assertTrue("focus alarms belong to their own channel", diff.cancel.isEmpty())
        assertEquals(setOf("owc.shift.b", "owc.shift.c"), ReminderPlanner.diff(registered, listOf(planned("owc.shift.a", 10)), ReminderPlanner.SHIFT_PREFIX).cancel.toSet())
        assertTrue(ReminderPlanner.diff(registered, registered.filter { it.id.startsWith("owc.shift.") }, ReminderPlanner.SHIFT_PREFIX).isEmpty)
    }

    @Test fun restoringAfterRebootDropsMissedAlarmsInsteadOfFiringABurst() {
        val restored = ReminderPlanner.restore(listOf(planned("owc.shift.a", 10), planned("owc.shift.b", 20), planned("owc.shift.c", 30)), 20.0)
        assertEquals(listOf("owc.shift.c"), restored.schedule.map { it.id })
        assertEquals(listOf("owc.shift.a", "owc.shift.b"), restored.cancel)
    }

    @Test fun aBreakNoticeExpiresWithItsFreshnessWindowAndHealthNeverUsesExactAlarms() {
        val alarms = ReminderPlanner.shiftAlarms(ReminderRules.buildShiftReminders(shift, inputs()), ms(monday, 8, 0))
        val lunch = alarms.single { it.id.contains("breakStart") }
        assertEquals(ms(monday, 12, 2).toLong(), lunch.expiresAtMs)
        assertTrue(lunch.isDeliverable(ms(monday, 12, 1).toLong()))
        assertTrue(!lunch.isDeliverable(ms(monday, 12, 2).toLong()))
        assertNull("progress never expires", alarms.single { it.id.endsWith("milestone:100") }.expiresAtMs)
        assertEquals(AlarmTiming.WINDOW, ReminderPlanner.timing(ReminderChannel.HEALTH, exactAllowed = true))
        assertEquals(AlarmTiming.EXACT, ReminderPlanner.timing(ReminderChannel.SHIFT, exactAllowed = true))
        assertEquals(AlarmTiming.INEXACT, ReminderPlanner.timing(ReminderChannel.FOCUS, exactAllowed = false))
    }

    @Test fun reminderKindsMapToChannels() {
        val alarms = ReminderPlanner.shiftAlarms(ReminderRules.buildShiftReminders(shift, inputs()), ms(monday, 8, 0))
        assertTrue(alarms.filter { it.id.contains("microBreak") }.all { it.channel == ReminderChannel.HEALTH })
        assertTrue(alarms.filterNot { it.id.contains("microBreak") }.all { it.channel == ReminderChannel.SHIFT })
        assertTrue(ReminderRules.buildShiftReminders(shift, inputs()).any { it.kind == ReminderKind.BREAK_START })
    }
}
