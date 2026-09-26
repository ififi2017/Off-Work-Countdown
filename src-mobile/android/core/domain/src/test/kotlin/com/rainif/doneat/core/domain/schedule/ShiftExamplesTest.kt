package com.rainif.doneat.core.domain.schedule

import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.session.heroRemainingMs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

/** The worked examples from the Android plan (02 §4.2) and T07's degenerate inputs. */
class ShiftExamplesTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val hour = 3_600_000.0
    private val lunchDay = ScheduleHours(
        startTime = "09:00", endTime = "18:00", workdays = listOf(1, 2, 3, 4, 5),
        schedule = WorkSchedule(ScheduleMode.CLASSIC), breakStartTime = "12:00", breakDurationMinutes = 60,
    )
    private val eightyADay = SalarySettings("80", SalaryType.DAILY, 21.75, 0.0)

    // Tuesday 2026-09-22.
    private fun at(h: Int, m: Int = 0) =
        LocalDateTime.of(2026, 9, 22, h, m).atZone(zone).toInstant().toEpochMilli().toDouble()

    @Test
    fun lunchFreezesWorkAndPay() {
        val s = ScheduleRules.snapshot(ScheduleRuleInput(lunchDay, at(12, 30), zone), eightyADay)
        assertEquals(3 * hour, s.elapsedMs, 0.0)
        assertEquals(5 * hour, s.remainingMs, 0.0)
        assertEquals(at(13), s.activeBreakEndAtMs!!, 0.0)
        assertEquals(30.0, s.earnedSoFar!!, 1e-9)
    }

    @Test fun beforeAndAtLunchUseEffectiveWorkTime() {
        val beforeLunch = ScheduleRules.snapshot(ScheduleRuleInput(lunchDay, at(11), zone), eightyADay)
        assertEquals(2 * hour, beforeLunch.elapsedMs, 0.0)
        assertEquals(6 * hour, beforeLunch.remainingMs, 0.0)
        assertEquals(25.0, beforeLunch.progress, 0.0)
        assertEquals(20.0, beforeLunch.earnedSoFar!!, 0.0)

        val lunchStart = ScheduleRules.snapshot(ScheduleRuleInput(lunchDay, at(12), zone), eightyADay)
        assertEquals(3 * hour, lunchStart.elapsedMs, 0.0)
        assertEquals(5 * hour, lunchStart.remainingMs, 0.0)
        assertEquals(at(13), lunchStart.activeBreakEndAtMs!!, 0.0)
        assertEquals(1 * hour, lunchStart.heroRemainingMs(at(12)), 0.0)
        assertEquals(30.0, lunchStart.earnedSoFar!!, 0.0)
    }

    @Test fun workStartAndBreakEndAreExactBoundaries() {
        val beforeStart = ScheduleRules.snapshot(ScheduleRuleInput(lunchDay, at(8), zone), eightyADay)
        assertEquals(0.0, beforeStart.elapsedMs, 0.0)
        assertEquals(8 * hour, beforeStart.remainingMs, 0.0)
        assertEquals(1 * hour, beforeStart.heroRemainingMs(at(8)), 0.0)
        assertEquals(0.0, beforeStart.earnedSoFar!!, 0.0)
        assertTrue(beforeStart.startAtMs > at(8))

        val start = ScheduleRules.snapshot(ScheduleRuleInput(lunchDay, at(9), zone), eightyADay)
        assertEquals(0.0, start.elapsedMs, 0.0)
        assertEquals(8 * hour, start.remainingMs, 0.0)
        assertEquals(8 * hour, start.heroRemainingMs(at(9)), 0.0)
        assertEquals(0.0, start.progress, 0.0)
        assertEquals(0.0, start.earnedSoFar!!, 0.0)

        val afterBreak = ScheduleRules.snapshot(ScheduleRuleInput(lunchDay, at(13), zone), eightyADay)
        assertEquals(3 * hour, afterBreak.elapsedMs, 0.0)
        assertEquals(5 * hour, afterBreak.remainingMs, 0.0)
        assertEquals(5 * hour, afterBreak.heroRemainingMs(at(13)), 0.0)
        assertNull(afterBreak.activeBreakEndAtMs)
        assertTrue(afterBreak.progress.isFinite())
    }

    @Test fun clockOffAndFiveMinutesLaterDoNotCreateOvertime() {
        for (now in listOf(at(18), at(18, 5))) {
            val shift = ScheduleRules.snapshot(ScheduleRuleInput(lunchDay, now, zone), eightyADay)
            assertEquals(8 * hour, shift.elapsedMs, 0.0)
            assertEquals(0.0, shift.remainingMs, 0.0)
            assertEquals(8 * hour, shift.durationMs, 0.0)
            assertEquals(80.0, shift.earnedSoFar!!, 0.0)
            assertNull(shift.overtimeEndAtMs)
        }
    }

    @Test fun severalGapsDoNotCountAsWorkOrAccumulateTogether() {
        val shift = ShiftTimeline(
            listOf(ShiftSegment(at(9), at(10)), ShiftSegment(at(11), at(12)), ShiftSegment(at(14), at(16))),
            at(16),
        )
        assertTrue(shift.isValid)
        assertEquals(1 * hour, shift.elapsedMs(at(10, 30)), 0.0)
        assertEquals(3 * hour, shift.remainingMs(at(10, 30)), 0.0)
        assertEquals(at(11), shift.activeBreakEndAtMs(at(10, 30))!!, 0.0)
        assertEquals(30 * 60_000.0, shift.activeBreakEndAtMs(at(10, 30))!! - at(10, 30), 0.0)
        assertNull(shift.activeBreakEndAtMs(at(11)))
        assertEquals(at(14), shift.activeBreakEndAtMs(at(13))!!, 0.0)
    }

    @Test fun malformedSegmentsAreRejectedWithoutNegativeOrNanFigures() {
        val good = ShiftSegment(at(9), at(10))
        val bad = listOf(
            emptyList(),
            listOf(ShiftSegment(at(9), at(9))),
            listOf(ShiftSegment(at(10), at(9))),
            listOf(good, ShiftSegment(at(9, 30), at(11))),
            listOf(ShiftSegment(Double.NaN, at(10))),
        )
        for (segments in bad) {
            val shift = ShiftTimeline(segments, at(11))
            assertFalse("$segments", shift.isValid)
            for (now in listOf(at(9), at(10), at(11))) {
                assertEquals(0.0, shift.elapsedMs(now), 0.0)
                assertEquals(0.0, shift.remainingMs(now), 0.0)
                assertEquals(0.0, shift.progress(now), 0.0)
                assertEquals(0.0, shift.payRatio(now), 0.0)
            }
        }
    }

    @Test fun eachSegmentBoundaryUsesHalfOpenTime() {
        val shift = ShiftTimeline(
            listOf(ShiftSegment(at(9), at(10)), ShiftSegment(at(11), at(12)), ShiftSegment(at(14), at(16))),
            at(16),
        )
        val boundaries = listOf(
            at(9) to 0.0, at(10) to hour, at(11) to hour,
            at(12) to 2 * hour, at(14) to 2 * hour, at(16) to 4 * hour,
        )
        for ((now, expected) in boundaries) {
            assertEquals("at $now", expected, shift.elapsedMs(now), 0.0)
            assertEquals("at $now", 4 * hour - expected, shift.remainingMs(now), 0.0)
        }
        assertEquals(at(11), shift.activeBreakEndAtMs(at(10))!!, 0.0)
        assertNull(shift.activeBreakEndAtMs(at(11)))
        assertEquals(at(14), shift.activeBreakEndAtMs(at(12))!!, 0.0)
        assertNull(shift.activeBreakEndAtMs(at(14)))
    }

    @Test
    fun overtimeExtendsTheOriginalRate() {
        val s = ScheduleRules.snapshot(ScheduleRuleInput(lunchDay, at(19), zone, overtimeEndAtMs = at(20)), eightyADay)
        assertEquals(9 * hour, s.elapsedMs, 0.0)
        assertEquals(10 * hour, s.durationMs, 0.0)
        assertEquals(8 * hour, s.plannedDurationMs, 0.0)
        assertEquals(1 * hour, s.remainingMs, 0.0)
        assertEquals(90.0, s.progress, 1e-9)
        assertEquals(1.125, s.payRatio, 1e-12)
        // Not 90% of 80 = 72: overtime keeps the planned hourly rate.
        assertEquals(90.0, s.earnedSoFar!!, 1e-9)
    }

    @Test
    fun noWorkdaysMeansNoNextShift() {
        val hours = lunchDay.copy(workdays = emptyList())
        val s = ScheduleRules.snapshot(ScheduleRuleInput(hours, at(10), zone), eightyADay)
        assertNull(s.nextShiftStartAtMs)
        assertEquals(false, s.isWorkday)
        assertTrue(ScheduleRules.widgetShifts(ScheduleRuleInput(hours, at(10), zone), at(10) + 30 * 24 * hour, 50).isEmpty())
    }

    @Test
    fun unresolvedFutureTypeNeverBecomesAnInventedTomorrow() {
        val missing = UUID.fromString("00000000-0000-0000-0000-000000000099")
        val plan = ExtendedSchedulePlan(
            emptyList(), ShiftCycleRule(ShiftCycleRule.Preset.CUSTOM, "2026-09-22", listOf(missing)), emptyMap(),
        )
        val hours = lunchDay.copy(extended = plan)
        val input = ScheduleRuleInput(hours, at(10), zone)
        assertNull(ScheduleRules.snapshot(input, eightyADay).nextShiftStartAtMs)
        assertTrue(ScheduleRules.widgetShifts(input, at(10) + 3 * 24 * hour, 10).isEmpty())
    }

    @Test
    fun manualModeHasNoRestDayAndNoPlannedShift() {
        val hours = lunchDay.copy(schedule = WorkSchedule(ScheduleMode.OFF))
        val s = ScheduleRules.snapshot(ScheduleRuleInput(hours, at(10), zone), eightyADay)
        assertNull(s.nextRestAtMs)
        assertNull(s.nextShiftStartAtMs)
        assertTrue(s.isWorkday)
    }

    @Test
    fun degenerateClocksAndCyclesTerminate() {
        val sameClock = lunchDay.copy(startTime = "09:00", endTime = "09:00", breakStartTime = null, breakDurationMinutes = 0)
        val fullDay = ScheduleRules.snapshot(ScheduleRuleInput(sameClock, at(10), zone), eightyADay)
        assertEquals(24 * hour, fullDay.durationMs, 0.0)
        assertEquals(listOf(ShiftSegment(at(9), at(9) + 24 * hour)), fullDay.segments)
        assertTrue(ShiftTimeline(fullDay.segments, fullDay.plannedEndAtMs).isValid)

        val zeroCycle = lunchDay.copy(schedule = WorkSchedule(ScheduleMode.ROTATION, rotationWorkDays = 0, rotationRestDays = 0))
        ScheduleRules.snapshot(ScheduleRuleInput(zeroCycle, at(10), zone), eightyADay)

        val garbage = lunchDay.copy(startTime = "", endTime = "x:y", breakStartTime = "99:99")
        val s = ScheduleRules.snapshot(ScheduleRuleInput(garbage, at(10), zone), eightyADay)
        assertTrue(s.progress in 0.0..100.0)
        assertTrue(ScheduleRules.expandScheduleRange(garbage, at(10), at(10) + 400 * 24 * hour, zone).size in 400..402)
    }
}
