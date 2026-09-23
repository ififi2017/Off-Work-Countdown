package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.records.RecordTestFixtures.ms
import com.rainif.doneat.core.domain.records.RecordTestFixtures.segment
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The pure cases of iOS `DayOverrideProjectionTests`; the store-driven ones belong to the timer (T16). */
class DayOverrideProjectionTest {
    private val zone = RecordTestFixtures.ZONE
    private val nineToFive = listOf(segment("2026-08-24", 9, 17))
    private val withLunch = listOf(segment("2026-08-24", 9, 12), segment("2026-08-24", 13, 17))

    private fun project(marks: TimerDayMarks, planned: List<ShiftSegment>, dayKey: String = "2026-08-24") =
        DayOverrideProjection.project(marks, dayKey, planned, zone)

    @Test fun timerMarksNeverInventRecordsKinds() {
        val marks = TimerDayMarks(ms("2026-08-24", 8), ms("2026-08-24", 15), "2026-08-24", true, true, true)
        assertEquals(DayOverrideKind.CUSTOM_SEGMENTS, project(marks, nineToFive)?.kind)
    }

    @Test fun noMarksMeansNoOverride() {
        assertNull(project(TimerDayMarks(isWorkday = true), nineToFive))
    }

    @Test fun todayOverlayOnRestDayIsNotAnOverride() {
        assertNull(project(TimerDayMarks(hasTodayOverride = true, isWorkday = false), emptyList(), "2026-08-29"))
    }

    @Test fun earlyStartExtendsFirstSegment() {
        val o = project(TimerDayMarks(earlyStartAtMs = ms("2026-08-24", 8)), nineToFive)!!
        assertEquals("2026-08-24", o.dayKey)
        assertEquals(listOf(ShiftSegment(ms("2026-08-24", 8), ms("2026-08-24", 17))), o.segments)
    }

    @Test fun earlyOffClipsLastSegment() {
        val o = project(TimerDayMarks(earlyOffAtMs = ms("2026-08-24", 15)), nineToFive)!!
        assertEquals(DayOverrideKind.CUSTOM_SEGMENTS, o.kind)
        assertEquals(listOf(ShiftSegment(ms("2026-08-24", 9), ms("2026-08-24", 15))), o.segments)
    }

    @Test fun earlyStartAndOffCompose() {
        val o = project(TimerDayMarks(ms("2026-08-24", 8), ms("2026-08-24", 15)), nineToFive)!!
        assertEquals(listOf(ShiftSegment(ms("2026-08-24", 8), ms("2026-08-24", 15))), o.segments)
    }

    @Test fun lunchGapSurvivesClockOffAfterBreak() {
        val o = project(TimerDayMarks(earlyOffAtMs = ms("2026-08-24", 14)), withLunch)!!
        assertEquals(listOf(segment("2026-08-24", 9, 12), ShiftSegment(ms("2026-08-24", 13), ms("2026-08-24", 14))), o.segments)
    }

    @Test fun clockOffDuringLunchDropsAfternoon() {
        val o = project(TimerDayMarks(earlyOffAtMs = ms("2026-08-24", 12, 30)), withLunch)!!
        assertEquals(listOf(segment("2026-08-24", 9, 12)), o.segments)
    }

    @Test fun overnightClockOffKeepsStartDayKey() {
        val planned = listOf(ShiftSegment(ms("2026-08-21", 22), ms("2026-08-22", 6)))
        val o = project(TimerDayMarks(earlyOffAtMs = ms("2026-08-22", 1)), planned, "2026-08-21")!!
        assertEquals("2026-08-21", o.dayKey)
        assertEquals(listOf(ShiftSegment(ms("2026-08-21", 22), ms("2026-08-22", 1))), o.segments)
    }

    @Test fun clockOffPastThePlannedEndExtendsTheLastFragment() {
        val o = project(TimerDayMarks(earlyOffAtMs = ms("2026-08-24", 19)), withLunch)!!
        assertEquals(listOf(segment("2026-08-24", 9, 12), segment("2026-08-24", 13, 19)), o.segments)
    }
}
