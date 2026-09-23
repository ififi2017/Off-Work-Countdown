package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.reminders.ReminderPlanner
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.ReminderKind
import com.rainif.doneat.core.domain.schedule.ReminderInputs
import com.rainif.doneat.core.domain.schedule.ReminderRules
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.ShiftTimeline
import com.rainif.doneat.core.domain.schedule.WallClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

/** iOS `FocusStore.focusAlerts` and the break-takeover cases in `FocusCanvasTests`. */
class FocusRemindersTest {
    private val zone = "Asia/Shanghai"
    private val civil = CivilZone(ZoneId.of(zone))
    private fun at(hour: Int, minute: Int = 0) = civil.utcMs(ExtendedScheduleResolver.dayNumber(monday)!!, WallClock(hour, minute))
    private val monday = "2026-08-31"
    private val segments = listOf(ShiftSegment(at(9), at(12)), ShiftSegment(at(13), at(17)))

    private inner class Env : FocusEnvironment {
        var authorized = true
        private var ids = 0
        override fun shift(atMs: Double) =
            if (atMs < at(0) || atMs >= at(0) + 86_400_000) null else FocusShift(segments, at(9), at(17), maxOf(0.0, at(17) - atMs), null, true)
        override fun scheduleEnabled(atMs: Double) = true
        override val overtimeEndAtMs: Double? = null
        override val isAuthorized get() = authorized
        override val recordsTimeZone = zone
        override val settings = DEFAULT_TIMER_SETTINGS
        override fun newId() = "00000000-0000-4000-8000-%012d".format(++ids)
    }

    private object Text : FocusAlertText {
        override val focusTitle = "Focus"
        override val breakOver = "Break over"
        override val dayDone = "Day done"
        override val endedNaturally = "Ended"
        override val endedAtBoundary = "Stopped at boundary"
        override val nextFocus = "Next focus"
        override val breakReminderTitle = "Stretch"
        override fun pomodoro(index: Int, total: Int) = "$index / $total"
        override fun breakUntil(minutes: Int, endAtMs: Double) = "$minutes min break"
        override fun nextUp(task: String, startAtMs: Long) = "Next: $task"
        override fun focusBreakBody(minutes: Int) = "Long break $minutes"
    }

    private val env = Env()
    private val planning = FocusPlanning(env)
    private val engine = FocusEngine(env)
    private val reminders = FocusReminders(env, planning, Text)
    private val nine05 = at(9, 5)

    private fun running(s: RecordState, taskID: String?, startMs: Double, endMs: Double, reason: FocusEndReason = FocusEndReason.COMPLETED, kind: FocusSessionKind = FocusSessionKind.FOCUS) =
        FocusSession("00000000-0000-0000-0000-0000000000C1", taskID, monday, startMs, endMs, null, null, startMs, 0, "T", kind, zone, monday, null, reason)

    @Test fun aCompletedBlockOwesItsEndAndTheFollowingBreaksEnd() {
        var s = planning.createInNextEmptyBlock(RecordState(), "Write", nine05, pomodoros = 2, scheduleAllPomodoros = true).state
        val blocks = planning.canvas(s, nine05).blocks.filter { it.taskID != null }
        val session = running(s, blocks[0].taskID, blocks[0].startAtMs.toDouble(), blocks[0].endAtMs.toDouble())
        s = engine.upsertSession(s, session, nine05)
        val alerts = reminders.alerts(s, session)
        assertEquals(listOf(FocusAlertSlot.END, FocusAlertSlot.BREAK_END), alerts.map { it.slot })
        assertEquals("Write", alerts[0].title)
        assertEquals("1 / 2 · 5 min break", alerts[0].body)
        assertEquals(blocks[0].endAtMs + 5 * 60_000.0, alerts[1].atMs, 0.0)
        assertEquals("Next: Write", alerts[1].body)
        assertEquals("owc.focus.${session.id}.end", alerts[0].id(session.id))
    }

    @Test fun theLastBlockOfTheDayOwesNoBreak() {
        var s = planning.createInNextEmptyBlock(RecordState(), "Only", nine05).state
        val block = planning.canvas(s, nine05).blocks.first { it.taskID != null }
        val session = running(s, block.taskID, block.startAtMs.toDouble(), block.endAtMs.toDouble())
        s = engine.upsertSession(s, session, nine05)
        val alerts = reminders.alerts(s, session)
        assertEquals(listOf(FocusAlertSlot.END), alerts.map { it.slot })
        assertEquals("1 / 1 · Day done", alerts.single().body)
    }

    @Test fun aBlockCutAtABoundarySaysSoAndOwesNoBreak() {
        val s = planning.createInNextEmptyBlock(RecordState(), "Write", nine05, pomodoros = 3).state
        val session = running(s, s.focusTasks.single().id, at(11, 50), at(12), FocusEndReason.STOPPED_AT_BOUNDARY)
        val alerts = reminders.alerts(engine.upsertSession(s, session, at(11, 50)), session)
        assertEquals(1, alerts.size)
        assertTrue(alerts.single().body.endsWith("Stopped at boundary"))
    }

    @Test fun onlyAlertsStillAheadBecomeAlarms() {
        val s = planning.createInNextEmptyBlock(RecordState(), "Write", nine05, pomodoros = 2, scheduleAllPomodoros = true).state
        val block = planning.canvas(s, nine05).blocks.first { it.taskID != null }
        val session = running(s, block.taskID, block.startAtMs.toDouble(), block.endAtMs.toDouble())
        val alerts = reminders.alerts(engine.upsertSession(s, session, nine05), session)
        assertEquals(2, ReminderPlanner.focusAlarms(session.id, alerts, nine05).size)
        assertEquals(listOf("owc.focus.${session.id}.breakEnd"), ReminderPlanner.focusAlarms(session.id, alerts, block.endAtMs + 1.0).map { it.id })
    }

    // Break takeover

    private val health = ReminderInputs(
        "off", "Reminder", "Break", emptyMap(), emptyMap(), false, "", false, "", true, "Stretch", 60, listOf("Move"), null,
    )
    private val fixed = ReminderRules.buildShiftReminders(ShiftTimeline(segments, at(17)), health)

    @Test fun aPlannedShiftHandsItsBreakRhythmToThePomodoro() {
        val s = planning.createInNextEmptyBlock(RecordState(), "Plan", nine05).state
        assertTrue(reminders.ownsBreaks(s, nine05, microBreakEnabled = true))
        val swapped = reminders.applyingBreakTakeover(fixed, s, nine05, microBreakEnabled = true)
        val breaks = swapped.filter { it.kind == ReminderKind.MICRO_BREAK }
        assertTrue(breaks.isNotEmpty())
        assertTrue("only the plan's long breaks", breaks.all { it.id.startsWith("focusBreak:") && it.body!!.startsWith("Long break") })
        val longBreaks = planning.blocks(env.shift(nine05)!!, s).filter { it.breakKind == FocusSessionKind.LONG_BREAK && it.startAtMs > nine05 }
        assertEquals(longBreaks.map { it.startAtMs.toDouble() }, breaks.map { it.atMs })
        // The next shift has no plan yet: its fixed-interval reminders stay.
        val tomorrow = fixed.map { it.copy(id = "next:${it.id}", atMs = it.atMs + 86_400_000) }
        val kept = reminders.applyingBreakTakeover(fixed + tomorrow, s, nine05, microBreakEnabled = true)
        assertEquals(tomorrow.filter { it.kind == ReminderKind.MICRO_BREAK }, kept.filter { it.id.startsWith("next:") && it.kind == ReminderKind.MICRO_BREAK })
    }

    @Test fun withoutAPlanOrWithTheReminderOffOrWithoutAccessTheFixedIntervalStays() {
        assertSame(fixed, reminders.applyingBreakTakeover(fixed, RecordState(), nine05, microBreakEnabled = true))
        val s = planning.createInNextEmptyBlock(RecordState(), "Plan", nine05).state
        assertSame(fixed, reminders.applyingBreakTakeover(fixed, s, nine05, microBreakEnabled = false))
        val breakOnly = planning.markBlockAsBreak(RecordState(), planning.canvas(RecordState(), nine05).nextEmptyBlock!!.startAtMs, nine05)
        assertFalse("a user break is not a plan", reminders.ownsBreaks(breakOnly, nine05, microBreakEnabled = true))
        env.authorized = false
        assertSame(fixed, reminders.applyingBreakTakeover(fixed, s, nine05, microBreakEnabled = true))
    }

    @Test fun clearingThePlanGivesTheFixedIntervalBack() {
        val s = planning.createInNextEmptyBlock(RecordState(), "Plan", nine05).state
        val cleared = planning.clearDay(s, nine05)
        assertSame(fixed, reminders.applyingBreakTakeover(fixed, cleared, nine05, microBreakEnabled = true))
        assertTrue(planning.planning(cleared).plans.values.all { p -> p.assignments.none { it.kind == FocusPlanBlockKind.TASK } })
    }
}
