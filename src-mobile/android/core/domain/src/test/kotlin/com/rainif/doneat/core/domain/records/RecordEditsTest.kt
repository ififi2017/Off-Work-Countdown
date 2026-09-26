package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.records.RecordTestFixtures.ms
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.RosterDay
import com.rainif.doneat.core.domain.schedule.ShiftCycleRule
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.ShiftType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The records edit commands and history overlay: iOS `RecordsActionTests`,
 * the relevant `RecordCoordinatorTests` and `ExtendedScheduleWiringTests`,
 * restated against the pure functions.
 */
class RecordEditsTest {
    private val weekdayLunch = SnapshotHours("09:00", "18:00", listOf(1, 2, 3, 4, 5), "classic", breakStartTime = "12:00", breakDurationMinutes = 60)
    private var ids = 0
    private fun context(canEdit: Boolean = true, hours: SnapshotHours = weekdayLunch, nowDay: String = "2026-09-07") = RecordEditContext(
        nowMs = ms(nowDay, 10), recordsTimeZone = RecordTestFixtures.ZONE, canEdit = canEdit, holidays = HolidayCalendar.EMPTY,
        currentHours = { hours }, newId = { "00000000-0000-4000-8000-%012d".format(++ids) },
    )

    @Test
    fun theFirstHoursEditSeedsAndOverridesInOneChangeAndKeepsLunch() {
        val (state, ok) = RecordEdits.applyDayWrite(RecordState(), DayRecordWrite.CUSTOM_HOURS, "2026-09-07", context(), 8 * 60, 18 * 60)
        assertTrue(ok)
        assertEquals(1, state.periods.size)
        assertEquals(1, state.snapshots.size)
        assertEquals("2026-09-07", state.recordsStartedOn)
        val override = state.overrides.single()
        assertEquals(listOf(ShiftSegment(ms("2026-09-07", 8), ms("2026-09-07", 12)), ShiftSegment(ms("2026-09-07", 13), ms("2026-09-07", 18))), override.segments)
        assertEquals(1, override.editCount)

        val (again, okAgain) = RecordEdits.applyDayWrite(state, DayRecordWrite.CUSTOM_HOURS, "2026-09-07", context(), 8 * 60, 18 * 60)
        assertTrue(okAgain)
        assertEquals("identical edits write nothing", state, again)

        val (clipped, clippedOk) = RecordEdits.applyDayWrite(RecordState(), DayRecordWrite.CUSTOM_HOURS, "2026-09-07", context(), 10 * 60, 17 * 60)
        assertTrue(clippedOk)
        assertEquals(
            listOf(ShiftSegment(ms("2026-09-07", 10), ms("2026-09-07", 12)), ShiftSegment(ms("2026-09-07", 13), ms("2026-09-07", 17))),
            clipped.overrides.single().segments,
        )
    }

    @Test
    fun invalidDatesMinutesOrAccessLeaveHistoryUntouched() {
        val original = RecordState()
        assertFalse(RecordEdits.applyDayWrite(original, DayRecordWrite.CUSTOM_HOURS, "2026-09-07", context(), -1, 17 * 60).second)
        assertFalse(RecordEdits.applyDayWrite(original, DayRecordWrite.CUSTOM_HOURS, "2026-09-07", context(), 9 * 60, 1_440).second)
        assertFalse(RecordEdits.applyDayWrite(original, DayRecordWrite.REST, "2026-02-30", context()).second)
        for (write in DayRecordWrite.entries) {
            val (state, ok) = RecordEdits.applyDayWrite(original, write, "2026-09-07", context(canEdit = false))
            assertFalse(ok)
            assertSame(original, state)
        }
    }

    @Test
    fun restMakeupAndClearWriteBothLayersAndClearLeftoverHours() {
        var (state, _) = RecordEdits.applyDayWrite(RecordState(), DayRecordWrite.CUSTOM_HOURS, "2026-09-07", context(), 8 * 60, 18 * 60)
        state = RecordEdits.applyDayWrite(state, DayRecordWrite.REST, "2026-09-07", context()).first
        assertEquals(DayOverrideKind.CLEARED, state.overrides.single().kind)
        assertEquals(CalendarEffect.REST, state.exceptions.single().effect)
        assertEquals(2, state.overrides.single().editCount)
        var day = RecordHistory.resolveDay(state, "2026-09-07", HolidayCalendar.EMPTY)
        assertEquals(DayResolutionLayer.CALENDAR_EXCEPTION, day.layer)
        assertFalse(day.isScheduledWorkday)

        state = RecordEdits.applyDayWrite(state, DayRecordWrite.MAKEUP, "2026-09-12", context()).first
        day = RecordHistory.resolveDay(state, "2026-09-12", HolidayCalendar.EMPTY)
        assertTrue("a Saturday makeup day takes the snapshot's hours", day.isScheduledWorkday)
        assertEquals(2, day.segments.size)

        state = RecordEdits.applyDayWrite(state, DayRecordWrite.CLEAR, "2026-09-07", context()).first
        assertTrue(state.exceptions.first { it.date == "2026-09-07" }.isCleared)
        assertEquals(DayResolutionLayer.SCHEDULE, RecordHistory.resolveDay(state, "2026-09-07", HolidayCalendar.EMPTY).layer)
    }

    @Test
    fun leaveIsAnOverrideThatKeepsTheBaseSchedule() {
        val seeded = RecordEdits.ensureSeeded(RecordState(), weekdayLunch, context())
        val state = RecordEdits.applyDayWrite(seeded, DayRecordWrite.LEAVE, "2026-09-08", context()).first
        val day = RecordHistory.resolveDay(state, "2026-09-08", HolidayCalendar.EMPTY)
        assertEquals(DayResolutionLayer.OVERRIDE, day.layer)
        assertFalse(day.isScheduledWorkday)
        assertTrue("income keeps the planned day", day.baseScheduleIsWorkday)
    }

    @Test
    fun aSeededArchiveResolvesAWeekOfScheduleDays() {
        val state = RecordEdits.ensureSeeded(RecordState(), weekdayLunch, context())
        val week = (7..13).map { RecordHistory.resolveDay(state, "2026-09-%02d".format(it), HolidayCalendar.EMPTY) }
        assertEquals(listOf(true, true, true, true, true, false, false), week.map { it.isScheduledWorkday })
        assertTrue(week.all { it.layer == DayResolutionLayer.SCHEDULE })
        assertEquals(DayResolutionLayer.NONE, RecordHistory.resolveDay(state, "2026-09-06", HolidayCalendar.EMPTY).layer)
    }

    @Test
    fun aSecondScheduleSaveOnTheSameDayEditsTheWinningSnapshot() {
        val seeded = RecordEdits.ensureSeeded(RecordState(), weekdayLunch, context())
        val (same, sameChanged) = RecordEdits.commitHours(seeded, weekdayLunch, "2026-09-07", context())
        assertFalse(sameChanged)
        assertSame(seeded, same)
        val later = weekdayLunch.copy(endTime = "19:00")
        val (edited, changed) = RecordEdits.commitHours(seeded, later, "2026-09-07", context())
        assertTrue(changed)
        assertEquals(1, edited.snapshots.size)
        assertEquals(2, edited.snapshots.single().editCount)
        val (next, _) = RecordEdits.commitHours(edited, weekdayLunch, "2026-09-10", context())
        assertEquals(2, next.snapshots.size)
        assertEquals(ms("2026-09-09", 19), RecordHistory.resolveDay(next, "2026-09-09", HolidayCalendar.EMPTY).segments.last().endAtMs, 0.0)
        assertEquals(ms("2026-09-10", 18), RecordHistory.resolveDay(next, "2026-09-10", HolidayCalendar.EMPTY).segments.last().endAtMs, 0.0)
    }

    @Test
    fun recordingAnErasedDayAgainRevivesAboveItsTombstone() {
        var state = RecordEdits.applyDayWrite(RecordState(), DayRecordWrite.LEAVE, "2026-09-07", context()).first
        repeat(3) { state = RecordEdits.applyDayWrite(state, if (it % 2 == 0) DayRecordWrite.CONFIRMED else DayRecordWrite.LEAVE, "2026-09-07", context()).first }
        assertEquals(4, state.overrides.single().editCount)
        state = RecordJson.erase(state, RecordEntityType.DAY_OVERRIDE, "2026-09-07", ms("2026-09-07", 11))
        assertEquals(4, state.erased.single().editCount)
        state = RecordEdits.applyDayWrite(state, DayRecordWrite.LEAVE, "2026-09-07", context()).first
        assertTrue(state.erased.isEmpty())
        assertEquals(5, state.overrides.single().editCount)
    }

    // expandableHours: the only reader of stored hours.

    private val day = ShiftType(UUID.fromString("00000000-0000-0000-0000-0000000000D1"), "Day", ShiftType.Kind.WORK, 480, 1_020, false, 0, 0, "#FF8800", false)
    private val rest = ShiftType(UUID.fromString("00000000-0000-0000-0000-0000000000D2"), "Rest", ShiftType.Kind.REST, 0, 0, false, 0, 0, "#9E9E9E", false)
    private val content = ExtendedScheduleContent(listOf(day, rest), ShiftCycleRule(ShiftCycleRule.Preset.WEEKLY, "2026-10-05", listOf(day.id, day.id, day.id, day.id, day.id, rest.id, rest.id)))

    @Test
    fun hoursStoreTheTypesAndRuleButNeverTheRoster() {
        val encoded = ScheduleHoursCodec.encode(weekdayLunch.copy(extendedContent = content)).data.toString(Charsets.UTF_8)
        assertTrue(encoded.contains("\"extendedContent\""))
        assertFalse(encoded.contains("handSetDays"))
        assertEquals(content, ScheduleHoursCodec.decode(encoded.toByteArray())!!.extendedContent)
        for (region in listOf(null, "", "CN")) {
            val hours = weekdayLunch.copy(extendedContent = content.copy(holidayRegionIdentifier = region))
            assertEquals(region, ScheduleHoursCodec.decode(ScheduleHoursCodec.encode(hours).data)!!.extendedContent!!.holidayRegionIdentifier)
        }
    }

    @Test
    fun historyFollowsARosterEditWithoutANewSnapshot() {
        val seeded = RecordEdits.ensureSeeded(RecordState(), weekdayLunch.copy(extendedContent = content), context(nowDay = "2026-10-01"))
        fun workdays(state: RecordState) = listOf("2026-10-05", "2026-10-06").map { RecordHistory.resolveDay(state, it, HolidayCalendar.EMPTY).isScheduledWorkday }
        assertEquals(listOf(true, true), workdays(seeded))
        assertEquals("the roster's day type, not the fixed hours", ms("2026-10-05", 8), RecordHistory.resolveDay(seeded, "2026-10-05", HolidayCalendar.EMPTY).segments.first().startAtMs, 0.0)
        val edited = seeded.copy(rosterDays = listOf(RosterDay("2026-10-06", rest.id)))
        assertEquals(listOf(true, false), workdays(edited))
        assertEquals(seeded.snapshots, edited.snapshots)
    }

    @Test
    fun fixedSnapshotsTakeFrozenHistoryAndLegacyRowsOnlyBeforeTheExtendedStart() {
        val fixed = RecordEdits.ensureSeeded(RecordState(), weekdayLunch, context(nowDay = "2026-09-01"))
        val extended = RecordEdits.commitHours(fixed, weekdayLunch.copy(extendedContent = content), "2026-10-01", context()).first
        val frozenNight = day.copy(startMinutes = 1_320, endMinutes = 360)
        val state = extended.copy(
            extendedSchedule = com.rainif.doneat.core.domain.schedule.ExtendedSchedule(true, content),
            rosterDays = listOf(
                RosterDay("2026-09-08", rest.id), // legacy row on a fixed snapshot before the extended start
                RosterDay("2026-09-09", day.id, assignedShiftType = frozenNight), // frozen history
            ),
        )
        assertEquals("2026-10-01", RecordHistory.extendedScheduleStart(state))
        assertFalse("legacy rows apply before the extended start", RecordHistory.resolveDay(state, "2026-09-08", HolidayCalendar.EMPTY).isScheduledWorkday)
        assertEquals(ms("2026-09-09", 22), RecordHistory.resolveDay(state, "2026-09-09", HolidayCalendar.EMPTY).segments.first().startAtMs, 0.0)
        assertEquals("other fixed days keep their own hours", ms("2026-09-10", 9), RecordHistory.resolveDay(state, "2026-09-10", HolidayCalendar.EMPTY).segments.first().startAtMs, 0.0)

        // Switched back to fixed hours later: a legacy row after the extended start no longer applies.
        val refixed = RecordEdits.commitHours(state, weekdayLunch, "2026-11-01", context()).first
            .let { it.copy(rosterDays = it.rosterDays + RosterDay("2026-11-03", rest.id)) }
        assertTrue(RecordHistory.resolveDay(refixed, "2026-11-03", HolidayCalendar.EMPTY).isScheduledWorkday)
        assertFalse("still applies before the extended start", RecordHistory.resolveDay(refixed, "2026-09-08", HolidayCalendar.EMPTY).isScheduledWorkday)
    }

    @Test
    fun editedTypeChangesFutureSnapshotWhileFrozenHistorySurvivesDisablingExtendedSchedule() {
        val seeded = RecordEdits.ensureSeeded(RecordState(), weekdayLunch.copy(extendedContent = content), context(nowDay = "2026-10-01"))
        val frozenNight = day.copy(startMinutes = 1_320, endMinutes = 360)
        val withPast = seeded.copy(rosterDays = listOf(RosterDay("2026-10-06", day.id, assignedShiftType = frozenNight)))
        val updatedContent = content.copy(shiftTypes = listOf(day.copy(name = "Later", startMinutes = 540), rest))
        val changed = RecordEdits.commitHours(withPast, weekdayLunch.copy(extendedContent = updatedContent), "2026-10-10", context(nowDay = "2026-10-01")).first
        val disabled = RecordEdits.commitHours(changed, weekdayLunch.copy(startTime = "10:00", extendedContent = null), "2026-10-20", context(nowDay = "2026-10-01")).first

        assertEquals(ms("2026-10-06", 22), RecordHistory.resolveDay(disabled, "2026-10-06", HolidayCalendar.EMPTY).segments.first().startAtMs, 0.0)
        assertEquals(ms("2026-10-07", 8), RecordHistory.resolveDay(disabled, "2026-10-07", HolidayCalendar.EMPTY).segments.first().startAtMs, 0.0)
        assertEquals(ms("2026-10-12", 9), RecordHistory.resolveDay(disabled, "2026-10-12", HolidayCalendar.EMPTY).segments.first().startAtMs, 0.0)
        assertEquals(ms("2026-10-21", 10), RecordHistory.resolveDay(disabled, "2026-10-21", HolidayCalendar.EMPTY).segments.first().startAtMs, 0.0)
        assertEquals(3, disabled.snapshots.size)
    }

    @Test
    fun undecodableHoursFailTheExpansionInsteadOfInventingASchedule() {
        val seeded = RecordEdits.ensureSeeded(RecordState(), weekdayLunch, context())
        val broken = seeded.copy(snapshots = seeded.snapshots.map { it.copy(configurationData = FoundationCompat.base64("{}".toByteArray())) })
        val r = RecordHistory.resolveDay(broken, "2026-09-08", HolidayCalendar.EMPTY)
        assertTrue(r.expansionFailed)
        assertEquals(DayResolutionLayer.NONE, r.layer)
        assertNull(RecordHistory.expandableHours(broken, broken.snapshots.single(), HolidayCalendar.EMPTY))
    }

    @Test
    fun theEditDraftTracksChangesAndGenerations() {
        val seeded = RecordEdits.applyDayWrite(RecordState(), DayRecordWrite.LEAVE, "2026-09-07", context()).first
        val draft = DayEditDraft.load("2026-09-07", seeded, RecordHistory.resolveDay(seeded, "2026-09-07", HolidayCalendar.EMPTY), RecordTestFixtures.ZONE)
        assertEquals(DayEditDraft.Kind.LEAVE, draft.loadedKind)
        assertTrue(draft.hasStoredOverride)
        assertEquals(9 * 60, draft.loadedStartMinutes)
        assertFalse(draft.hasChanges)
        val edited = draft.withKind(DayEditDraft.Kind.CUSTOM_HOURS).withEnd(17 * 60)
        assertTrue(edited.hasChanges)
        assertEquals(2, edited.editGeneration)
        val submitted = edited.submission
        assertTrue(edited.stillMatches(submitted))
        assertFalse(edited.withStart(8 * 60).stillMatches(submitted))
        assertSame(edited, edited.withEnd(17 * 60))
    }
}
