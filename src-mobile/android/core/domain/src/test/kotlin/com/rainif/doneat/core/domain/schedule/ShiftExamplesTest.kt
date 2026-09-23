package com.rainif.doneat.core.domain.schedule

import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

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

    @Test
    fun overtimeExtendsTheOriginalRate() {
        val s = ScheduleRules.snapshot(ScheduleRuleInput(lunchDay, at(19), zone, overtimeEndAtMs = at(20)), eightyADay)
        assertEquals(9 * hour, s.elapsedMs, 0.0)
        assertEquals(10 * hour, s.durationMs, 0.0)
        assertEquals(8 * hour, s.plannedDurationMs, 0.0)
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

        val zeroCycle = lunchDay.copy(schedule = WorkSchedule(ScheduleMode.ROTATION, rotationWorkDays = 0, rotationRestDays = 0))
        ScheduleRules.snapshot(ScheduleRuleInput(zeroCycle, at(10), zone), eightyADay)

        val garbage = lunchDay.copy(startTime = "", endTime = "x:y", breakStartTime = "99:99")
        val s = ScheduleRules.snapshot(ScheduleRuleInput(garbage, at(10), zone), eightyADay)
        assertTrue(s.progress in 0.0..100.0)
        assertTrue(ScheduleRules.expandScheduleRange(garbage, at(10), at(10) + 400 * 24 * hour, zone).size in 400..402)
    }
}
