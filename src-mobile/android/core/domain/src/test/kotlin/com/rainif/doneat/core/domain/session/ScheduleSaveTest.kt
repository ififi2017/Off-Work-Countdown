package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.records.RecordEditContext
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordHistory
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.schedule.ExtendedSchedule
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.RosterDay
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ShiftCycleRule
import com.rainif.doneat.core.domain.schedule.ShiftType
import com.rainif.doneat.core.domain.settings.PreferencesRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

/**
 * Saving the schedule page: iOS `OffWorkStoreTests` (apply to today / from
 * the next shift) and `ExtendedScheduleWiringTests` on the Kotlin save.
 */
class ScheduleSaveTest {
    private class Harness(zone: String = "Asia/Shanghai") {
        var records: RecordState = PreferencesRules.commit(
            RecordState(),
            PreferencesRules.defaults(zone, 0.0).copy(scheduleMode = "classic", workdays = listOf(1, 2, 3, 4, 5), startMinutes = 9 * 60, endMinutes = 17 * 60, lunchEnabled = false),
            0.0, "00000000-0000-0000-0000-00000000AAAA",
        )
        var state = SessionState()
        private var ids = 0
        fun newId() = "00000000-0000-0000-0000-%012d".format(++ids)
        val prefs: SyncedPreferences get() = records.syncedPreferences!!
        fun edit(change: (SyncedPreferences) -> SyncedPreferences) { records = records.copy(syncedPreferences = change(prefs)) }
        fun env() = SessionEnvironment(prefs, true, records.extendedSchedule, records.rosterDays, HolidayCalendar.EMPTY, prefs.recordsTimeZoneIdentifier)
        val session get() = ShiftSession(state, env())

        fun run(command: SessionCommands.() -> SessionResult): Boolean {
            val result = SessionCommands(env(), ::newId).command()
            if (!result.accepted) return false
            state = result.state
            records = SessionRecords.apply(records, result.effects, RecordEditContext(0.0, prefs.recordsTimeZoneIdentifier, true, HolidayCalendar.EMPTY, { session.hoursConfiguration(0.0) }, ::newId))
            return true
        }

        fun save(change: ScheduleFieldChange, decision: ScheduleDecision, at: Double): Boolean {
            val result = ScheduleSave.apply(records, state, env(), change, decision, at, ::newId) ?: return false
            records = result.records
            state = result.state
            return true
        }
    }

    private fun at(day: Int, hour: Int, minute: Int = 0, month: Int = 8) =
        LocalDateTime.of(2026, month, day, hour, minute).atZone(ZoneId.of("Asia/Shanghai")).toInstant().toEpochMilli().toDouble()

    private val early = UUID.fromString("00000000-0000-0000-0000-0000000000C1")
    private val night = UUID.fromString("00000000-0000-0000-0000-0000000000C2")
    private val rest = UUID.fromString("00000000-0000-0000-0000-0000000000C3")
    private val types = listOf(
        ShiftType(early, "Early", ShiftType.Kind.WORK, 8 * 60, 16 * 60, true, 12 * 60, 30, "#F28C28", false),
        ShiftType(night, "Night", ShiftType.Kind.WORK, 20 * 60, 6 * 60, false, 0, 0, "#3A6EA5", false),
        ShiftType(rest, "Rest", ShiftType.Kind.REST, 0, 0, false, 0, 0, "#9E9E9E", false),
    )

    /** Monday 2026-10-05 early, Tuesday night, Wednesday rest, Thursday early. */
    private fun Harness.install(enabled: Boolean) {
        records = records.copy(
            extendedSchedule = ExtendedSchedule(enabled, ExtendedScheduleContent(types, null), "Asia/Shanghai"),
            rosterDays = mapOf("2026-10-05" to early, "2026-10-06" to night, "2026-10-07" to rest, "2026-10-08" to early)
                .map { (key, id) -> RosterDay(key, id, timeZoneIdentifier = "Asia/Shanghai") },
        )
    }

    @Test fun `changing today also clears an early clock-off`() {
        val h = Harness()
        h.run { start(h.state, at(24, 11)) }
        h.run { clockOffEarly(h.state, at(24, 11)) }
        assertEquals(TimerPhase.COMPLETED, h.session.visualPhase(at(24, 11)))
        assertTrue(h.save(ScheduleFieldChange(endMinutes = 18 * 60), ScheduleDecision.APPLY_TO_TODAY, at(24, 11)))
        assertEquals(18 * 60, h.prefs.endMinutes)
        assertNull(h.state.earlyOffAtMs)
        assertEquals(TimerPhase.RUNNING, h.session.visualPhase(at(24, 11)))
    }

    @Test fun `next-shift-only on a rest day does not make today a workday`() {
        val h = Harness()
        h.run { start(h.state, at(29, 11)) }
        assertTrue(h.save(ScheduleFieldChange(workdays = setOf(1, 2, 3, 4, 5, 6)), ScheduleDecision.NEXT_SHIFT_ONLY, at(29, 11)))
        assertTrue(6 in h.prefs.workdays)
        assertFalse(6 in h.session.effectiveWorkdays(at(29, 11)))
        assertEquals(TimerPhase.REST, h.session.visualPhase(at(29, 11)))
    }

    @Test fun `next-shift-only leaving off keeps today unscheduled`() {
        val h = Harness()
        h.edit { it.copy(scheduleMode = "off") }
        assertTrue(h.save(ScheduleFieldChange(scheduleMode = ScheduleMode.CLASSIC), ScheduleDecision.NEXT_SHIFT_ONLY, at(24, 11)))
        assertEquals("classic", h.prefs.scheduleMode)
        assertEquals(ScheduleMode.OFF, h.session.effectiveScheduleMode(at(24, 11)))
        assertEquals(TimerPhase.UNSCHEDULED, h.session.visualPhase(at(24, 11)))
    }

    @Test fun `apply-to-today hours keep rest-day manual timing`() {
        val h = Harness()
        h.run { start(h.state, at(29, 11), force = true) }
        assertTrue(h.save(ScheduleFieldChange(endMinutes = 18 * 60), ScheduleDecision.APPLY_TO_TODAY, at(29, 11)))
        val shift = h.session.snapshot(at(29, 11))!!
        assertTrue(h.session.isForcedWorkday(shift))
        assertEquals(TimerPhase.RUNNING, h.session.visualPhase(shift, at(29, 11)))
        assertEquals(18 * 60, h.session.effectiveEndMinutes(at(29, 11)))
    }

    @Test fun `an unchanged draft saves nothing`() {
        val h = Harness()
        val before = h.records
        assertFalse(h.save(ScheduleFieldChange(endMinutes = 17 * 60), ScheduleDecision.APPLY_TO_TODAY, at(24, 11)))
        assertEquals(before, h.records)
    }

    @Test fun `applying hours to today replaces the timer's projection and today's snapshot`() {
        val h = Harness()
        h.run { start(h.state, at(1, 8, 30, month = 9)) }
        h.run { clockInEarly(h.state, at(1, 8, 30, month = 9)) }
        assertTrue(h.records.overrides.any { it.dayKey == "2026-09-01" })
        val change = ScheduleFieldChange(startMinutes = 10 * 60, endMinutes = 19 * 60, lunchEnabled = true, lunchStartMinutes = 12 * 60 + 30, lunchDurationMinutes = 90)
        assertTrue(h.save(change, ScheduleDecision.APPLY_TO_TODAY, at(1, 14, month = 9)))
        assertFalse(h.records.overrides.any { it.dayKey == "2026-09-01" })
        val day = RecordHistory.resolveDay(h.records, "2026-09-01", HolidayCalendar.EMPTY)
        val work = day.segments.sumOf { it.endAtMs - it.startAtMs }
        assertEquals(7.5 * 3_600_000, work, 0.0)
    }

    @Test fun `switching it on through the draft moves the countdown onto the roster`() {
        val h = Harness()
        h.install(enabled = false)
        val monday = at(5, 10, month = 10)
        assertEquals(at(5, 9, month = 10), h.session.snapshot(monday)!!.startAtMs, 0.0)
        // "Start by hand" is not a schedule; a roster is.
        h.edit { it.copy(scheduleMode = "off") }
        assertTrue(h.save(ScheduleFieldChange(extendedScheduleEnabled = true), ScheduleDecision.APPLY_TO_TODAY, monday))
        assertTrue(h.records.extendedSchedule!!.isEnabled)
        assertEquals("classic", h.prefs.scheduleMode)
        val shift = h.session.snapshot(monday)!!
        assertEquals(at(5, 8, month = 10), shift.startAtMs, 0.0)
        assertEquals(at(5, 16, month = 10), shift.plannedEndAtMs, 0.0)
        assertEquals(2, shift.segments.size)
        assertEquals(at(6, 20, month = 10), shift.nextShiftStartAtMs!!, 0.0)

        assertTrue(h.save(ScheduleFieldChange(extendedScheduleEnabled = false), ScheduleDecision.APPLY_TO_TODAY, monday))
        assertEquals(at(5, 9, month = 10), h.session.snapshot(monday)!!.startAtMs, 0.0)
    }

    @Test fun `there is nothing to switch on before a schedule exists`() {
        val h = Harness()
        assertFalse(h.save(ScheduleFieldChange(extendedScheduleEnabled = true), ScheduleDecision.APPLY_TO_TODAY, at(5, 10, month = 10)))
        assertNull(h.records.extendedSchedule)
    }

    @Test fun `switching it on from the next shift keeps today on the fixed hours`() {
        val h = Harness()
        h.install(enabled = false)
        val monday = at(5, 10, month = 10)
        assertTrue(h.save(ScheduleFieldChange(extendedScheduleEnabled = true), ScheduleDecision.NEXT_SHIFT_ONLY, monday))
        val today = h.session.snapshot(monday)!!
        assertEquals(at(5, 9, month = 10), today.startAtMs, 0.0)
        assertEquals(at(5, 17, month = 10), today.plannedEndAtMs, 0.0)
        assertEquals(at(6, 20, month = 10), today.nextShiftStartAtMs!!, 0.0)
    }

    @Test fun `a seeded schedule works exactly the days the fixed one did`() {
        val h = Harness()
        val now = at(5, 10, month = 10)
        var n = 0
        val content = h.session.seededExtendedContent(ScheduleFieldChange(), now, "Work", "Rest") { UUID(0, (++n).toLong()) }
        assertEquals(ShiftCycleRule.Preset.WEEKLY, content.rule!!.preset)
        assertEquals("2026-10-05", content.rule!!.anchorDayKey)
        val work = content.shiftTypes.first { it.kind == ShiftType.Kind.WORK }.id
        assertEquals(List(5) { work } + List(2) { content.shiftTypes.first { it.kind == ShiftType.Kind.REST }.id }, content.rule!!.days)
        assertTrue(h.save(ScheduleFieldChange(extendedScheduleEnabled = true, extendedContent = content), ScheduleDecision.APPLY_TO_TODAY, now))
        val shift = h.session.snapshot(now)!!
        assertEquals(at(5, 9, month = 10), shift.startAtMs, 0.0)
        assertEquals(at(6, 9, month = 10), shift.nextShiftStartAtMs!!, 0.0)
        assertEquals(TimerPhase.REST, h.session.visualPhase(at(10, 10, month = 10)))
    }

    @Test fun `a hand-set day is stamped, and following the pattern leaves a tombstone`() {
        val h = Harness()
        h.install(enabled = true)
        val now = at(1, 10, month = 10)
        assertTrue(h.save(ScheduleFieldChange(rosterEdits = mapOf("2026-10-09" to RosterDayEdit.Shift(night))), ScheduleDecision.NEXT_SHIFT_ONLY, now))
        val row = h.records.rosterDays.single { it.dayKey == "2026-10-09" }
        assertEquals(1, row.editCount)
        assertNull("a future day keeps following its type's live hours", row.assignedShiftType)
        assertTrue(h.save(ScheduleFieldChange(rosterEdits = mapOf("2026-10-09" to RosterDayEdit.FollowPattern)), ScheduleDecision.NEXT_SHIFT_ONLY, now))
        assertTrue(h.records.rosterDays.none { it.dayKey == "2026-10-09" })
        assertTrue(h.records.isErased(RecordEntityType.ROSTER_DAY, "2026-10-09"))
        assertTrue(h.save(ScheduleFieldChange(rosterEdits = mapOf("2026-10-09" to RosterDayEdit.Shift(early))), ScheduleDecision.NEXT_SHIFT_ONLY, now))
        assertTrue("revived above its tombstone", h.records.rosterDays.single { it.dayKey == "2026-10-09" }.editCount >= 2)
        assertFalse(h.records.isErased(RecordEntityType.ROSTER_DAY, "2026-10-09"))
    }

    @Test fun `a day may only name a type the schedule knows`() {
        val h = Harness()
        h.install(enabled = true)
        assertFalse(h.save(ScheduleFieldChange(rosterEdits = mapOf("2026-10-09" to RosterDayEdit.Shift(UUID.randomUUID()))), ScheduleDecision.NEXT_SHIFT_ONLY, at(1, 10, month = 10)))
    }

    @Test fun `clearing expected days keeps a day already worked`() {
        val h = Harness()
        val now = at(5, 10, month = 10)
        val content = h.session.seededExtendedContent(ScheduleFieldChange(), now, "Work", "Rest")
        val work = content.shiftTypes.first { it.kind == ShiftType.Kind.WORK }.id
        // The pattern written out as generated rows, as a free-calendar preview leaves them.
        h.records = h.records.copy(
            extendedSchedule = ExtendedSchedule(true, content, "Asia/Shanghai"),
            rosterDays = listOf("2026-10-05", "2026-10-06", "2026-10-07").map { RosterDay(it, work, generatedFromPattern = true, timeZoneIdentifier = "Asia/Shanghai") },
        )
        h.run { start(h.state, now) }
        val draft = ScheduleFieldChange(clearExpectedFromDayKey = "2026-10-05")
        assertTrue(h.save(draft, ScheduleDecision.APPLY_TO_TODAY, now))
        assertNull(h.records.extendedSchedule!!.content.rule)
        assertNotNull("today has started: its row stays", h.records.rosterDays.firstOrNull { it.dayKey == "2026-10-05" })
        assertTrue(h.records.rosterDays.none { it.dayKey == "2026-10-06" || it.dayKey == "2026-10-07" })
        assertEquals("the shift in progress is untouched", at(5, 9, month = 10), h.session.snapshot(now)!!.startAtMs, 0.0)
    }
}
