package com.rainif.doneat.core.domain.schedule

import com.rainif.doneat.core.domain.records.CalendarEffect
import com.rainif.doneat.core.domain.records.CalendarException
import com.rainif.doneat.core.domain.records.CalendarExceptionOrigin
import com.rainif.doneat.core.domain.records.DayOverride
import com.rainif.doneat.core.domain.records.DayOverrideKind
import com.rainif.doneat.core.domain.records.DayRecordLookup
import com.rainif.doneat.core.domain.records.DayRecordResolver
import com.rainif.doneat.core.domain.records.DayResolution
import com.rainif.doneat.core.domain.records.DayResolutionLayer
import com.rainif.doneat.core.domain.records.LeaveDay
import com.rainif.doneat.core.domain.records.RecordTestFixtures
import com.rainif.doneat.core.domain.records.ScheduleExpansion
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.session.SessionEnvironment
import com.rainif.doneat.core.domain.session.SessionState
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.settings.PreferencesRules
import com.rainif.doneat.core.domain.summary.SummaryRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs

/**
 * The pure-rules parts of iOS `LeaveScheduleTests` (plan 020 P2b): adopted
 * leave in the live rules, summaries and as a Records layer, over both a fixed
 * schedule and an extended one.
 */
class LeaveOverlayTest {
    private companion object {
        const val ZONE = "Asia/Shanghai"
        val office: UUID = UUID.fromString("00000000-0000-0000-0000-000000000301")
        val rest: UUID = UUID.fromString("00000000-0000-0000-0000-000000000302")
        val classic = WorkSchedule(ScheduleMode.CLASSIC)
        val fixedHours = ExtendedScheduleDayHours("09:00", "18:00", "12:00", 60)

        /** Wednesday off, Thursday's morning off, Friday's afternoon off, and a half day on Saturday, which the schedule already rests. */
        val leave = mapOf(
            "2026-10-14" to LeavePortion.WHOLE, "2026-10-15" to LeavePortion.FIRST_HALF,
            "2026-10-16" to LeavePortion.SECOND_HALF, "2026-10-17" to LeavePortion.FIRST_HALF,
        )
        val salary = SalarySettings("", SalaryType.MONTHLY, 22.0, 0.0)

        fun instant(key: String, hour: Int, minute: Int = 0, zone: String = ZONE): Double {
            val (y, m, d) = key.split("-").map { it.toInt() }
            return LocalDateTime.of(y, m, d, hour, minute).atZone(ZoneId.of(zone)).toInstant().toEpochMilli().toDouble()
        }

        fun segment(key: String, from: Int, to: Int) = ShiftSegment(instant(key, from), instant(key, to))

        fun input(nowMs: Double, plan: ExtendedSchedulePlan?) = ScheduleRuleInput(
            hours = ScheduleHours("09:00", "18:00", listOf(1, 2, 3, 4, 5), classic, "12:00", 60, plan),
            nowMs = nowMs,
            zone = ZoneId.of(ZONE),
        )

        val fixedPlan get() = ExtendedSchedulePlan.applying(leave, null, fixedHours)

        val extendedPlan: ExtendedSchedulePlan?
            get() {
                val officeType = ShiftType(office, "Office", ShiftType.Kind.WORK, 9 * 60, 18 * 60, true, 12 * 60, 60, "#FF7A00", false)
                val restType = ShiftType(rest, "Rest", ShiftType.Kind.REST, 0, 0, false, 0, 0, "#777777", false)
                val plan = ExtendedSchedulePlan(
                    shiftTypes = listOf(officeType, restType),
                    rule = ShiftCycleRule(ShiftCycleRule.Preset.WEEKLY, "2026-10-12", listOf(office, office, office, office, office, rest, rest)),
                    handSetDays = emptyMap(),
                )
                return ExtendedSchedulePlan.applying(leave, plan, fixedHours)
            }

        fun plan(kind: String) = if (kind == "fixed") fixedPlan else extendedPlan
    }

    // Halves

    private fun checkRemaining(
        start: String, end: String, breakStart: String?, breakMinutes: Int,
        morning: Triple<String, String, String?>, afternoon: Triple<String, String, String?>,
    ) {
        val hours = ExtendedScheduleDayHours(start, end, breakStart, breakMinutes)
        assertNull(hours.remaining(LeavePortion.WHOLE))
        val morningOff = hours.remaining(LeavePortion.FIRST_HALF)!!
        assertEquals(morning.first, morningOff.startTime)
        assertEquals(morning.second, morningOff.endTime)
        assertEquals(morning.third, morningOff.breakStartTime)
        val afternoonOff = hours.remaining(LeavePortion.SECOND_HALF)!!
        assertEquals(afternoon.first, afternoonOff.startTime)
        assertEquals(afternoon.second, afternoonOff.endTime)
        assertEquals(afternoon.third, afternoonOff.breakStartTime)
    }

    @Test fun `the remaining half keeps its share of the break - break before the midpoint moves the split past it`() =
        checkRemaining("09:00", "18:00", "12:00", 60, Triple("14:00", "18:00", null), Triple("09:00", "14:00", "12:00"))

    @Test fun `the remaining half keeps its share of the break - break after the midpoint stays with the afternoon`() =
        checkRemaining("08:00", "17:00", "13:00", 60, Triple("12:00", "17:00", "13:00"), Triple("08:00", "12:00", null))

    @Test fun `the remaining half keeps its share of the break - break exactly at the midpoint belongs to neither half`() =
        checkRemaining("08:00", "17:00", "12:00", 60, Triple("13:00", "17:00", null), Triple("08:00", "12:00", null))

    @Test fun `the remaining half keeps its share of the break - overnight with no break`() =
        checkRemaining("22:00", "06:00", null, 0, Triple("02:00", "06:00", null), Triple("22:00", "02:00", null))

    // Live rules

    @Test fun `no leave keeps the plan exactly as it was`() {
        assertNull(ExtendedSchedulePlan.applying(emptyMap(), null, fixedHours))
        val plan = ExtendedSchedulePlan(shiftTypes = emptyList(), rule = null, handSetDays = emptyMap())
        assertSame(plan, ExtendedSchedulePlan.applying(emptyMap(), plan, fixedHours))
    }

    private fun countdown(kind: String) {
        val plan = plan(kind)
        fun snap(key: String, hour: Int) = ScheduleRules.snapshot(input(instant(key, hour), plan), salary)

        // After Tuesday's shift, Wednesday is off and Thursday starts at 14:00.
        assertEquals(instant("2026-10-15", 14), snap("2026-10-13", 20).nextShiftStartAtMs)

        val wednesday = snap("2026-10-14", 10)
        assertFalse(wednesday.isWorkday)
        assertEquals(instant("2026-10-15", 14), wednesday.countdownTargetAtMs)

        val thursday = snap("2026-10-15", 15)
        assertTrue(thursday.isWorkday)
        assertEquals(listOf(segment("2026-10-15", 14, 18)), thursday.segments)

        val friday = snap("2026-10-16", 10)
        assertEquals(listOf(segment("2026-10-16", 9, 12), segment("2026-10-16", 13, 14)), friday.segments)
        assertEquals(instant("2026-10-16", 14), friday.endAtMs, 0.0)

        // Leave never turns a rest day into work.
        val saturday = snap("2026-10-17", 10)
        assertFalse(saturday.isWorkday)
        assertEquals(instant("2026-10-19", 9), saturday.nextShiftStartAtMs)
    }

    @Test fun `leave changes the countdown on a fixed schedule`() = countdown("fixed")
    @Test fun `leave changes the countdown on an extended schedule`() = countdown("extended")

    @Test fun `reminders and the Widget skip a day off`() {
        val reminderInputs = ReminderInputs(
            mode = "all", fallbackTitle = "Off", breakTitle = "Break",
            milestoneTitles = mapOf(50 to "50", 75 to "75", 90 to "90", 95 to "95", 100 to "100"),
            milestoneMessages = mapOf(50 to listOf("50"), 75 to listOf("75"), 90 to listOf("90"), 95 to listOf("95"), 100 to listOf("100")),
            lunchStartEnabled = false, lunchStartBody = "", lunchEndEnabled = false, lunchEndBody = "",
            microBreakEnabled = false, microBreakTitle = "", microBreakIntervalMinutes = 0,
            microBreakMessages = emptyList(), cycleEndSummaryBody = null,
        )
        val wednesdayMorning = input(instant("2026-10-14", 8), fixedPlan)
        // The rules list the resting day's own shift too, as on any rest day;
        // the scheduler drops it. The next shift is Thursday afternoon.
        val reminders = ScheduleRules.reminders(wednesdayMorning, reminderInputs)
        val thursdayEnd = ReminderRules.jsString(instant("2026-10-15", 18))
        val next = reminders.filter { it.id.startsWith("next:") }
        assertTrue(next.isNotEmpty())
        assertTrue(next.all { it.id.startsWith("next:$thursdayEnd:") })
        val thursdayStart = instant("2026-10-15", 14)
        assertTrue(next.all { it.atMs > thursdayStart })

        val shifts = ScheduleRules.widgetShifts(wednesdayMorning, instant("2026-10-20", 0), 4)
        assertEquals(
            listOf(instant("2026-10-15", 14), instant("2026-10-16", 9), instant("2026-10-19", 9), instant("2026-10-20", 9)),
            shifts.map { it.startAtMs },
        )
    }

    private fun weekSummary(kind: String) {
        val summary = SummaryRules.summarize(
            SummaryRules.SummaryInput(
                period = SummaryRules.Period.WEEK,
                periodStartMs = instant("2026-10-12", 0),
                asOfMs = instant("2026-10-17", 12),
                workdays = listOf(1, 2, 3, 4, 5),
                schedule = classic,
                currentShiftStartMs = instant("2026-10-16", 9),
                currentShiftEndMs = instant("2026-10-16", 14),
                plannedDailyHours = 8.0,
                todayProgress = 0.0,
                dailySalary = null,
                todayEffectiveHours = 0.0,
                todayPayRatio = 0.0,
                zone = ZoneId.of(ZONE),
                extended = plan(kind),
            ),
        )
        // Monday and Tuesday in full, Wednesday off, four hours each on Thursday and Friday.
        assertEquals(4.0, summary.days, 0.0)
        assertTrue(abs(summary.hours - 24) < 0.0001)
    }

    @Test fun `a week summary counts leave days short on a fixed schedule`() = weekSummary("fixed")
    @Test fun `a week summary counts leave days short on an extended schedule`() = weekSummary("extended")

    // Live session

    @Test fun `the live session rules input applies adopted leave over the fixed hours`() {
        val prefs = PreferencesRules.defaults(ZONE, instant("2026-10-12", 0)).copy(
            startMinutes = 9 * 60, endMinutes = 18 * 60, lunchEnabled = true, lunchStartMinutes = 12 * 60, lunchDurationMinutes = 60,
        )
        val env = SessionEnvironment(prefs, true, null, emptyList(), HolidayCalendar.EMPTY, ZONE, leaveDays = leave)
        val session = ShiftSession(SessionState(), env)

        val input = session.rulesInput(instant("2026-10-14", 10))
        assertNotNull(input.hours.extended)
        assertEquals(leave, input.hours.extended!!.leaveDays)

        val wednesday = session.snapshot(instant("2026-10-14", 10))!!
        assertFalse(wednesday.isWorkday)
        assertEquals(instant("2026-10-15", 14), wednesday.countdownTargetAtMs)
        val thursday = session.snapshot(instant("2026-10-15", 15))!!
        assertEquals(listOf(segment("2026-10-15", 14, 18)), thursday.segments)

        // Without leave the plan stays null: the exact fixed-hours path.
        val plain = ShiftSession(SessionState(), SessionEnvironment(prefs, true, null, emptyList(), HolidayCalendar.EMPTY, ZONE))
        assertNull(plain.rulesInput(instant("2026-10-14", 10)).hours.extended)
    }

    // Records

    private fun resolution(
        dayKey: String,
        leaveDays: List<LeaveDay>,
        overrides: List<DayOverride> = emptyList(),
        exceptions: List<CalendarException> = emptyList(),
    ): DayResolution {
        val period = RecordTestFixtures.period(RecordTestFixtures.id(1), "2026-01-01")
        val snapshot = RecordTestFixtures.snapshot(RecordTestFixtures.id(2), period.id, "2026-01-01", "")
        val expansion = ScheduleExpansion(true, listOf(segment(dayKey, 9, 12), segment(dayKey, 13, 18)))
        return DayRecordResolver.resolve(dayKey, period, snapshot, DayRecordLookup(exceptions, overrides, leaveDays), expansion)
    }

    private fun leaveDay(dayKey: String, portion: LeavePortion) =
        LeaveDay(dayKey, portion.raw, emptyList(), null, ZONE, 0.0, 0, "00000000-0000-0000-0000-000000000000")

    @Test fun `records shows leave as a correction and keeps the plan beneath for income`() {
        val whole = resolution("2026-10-14", listOf(leaveDay("2026-10-14", LeavePortion.WHOLE)))
        assertEquals(DayResolutionLayer.OVERRIDE, whole.layer)
        assertFalse(whole.isScheduledWorkday)
        assertTrue(whole.segments.isEmpty())
        assertTrue(whole.baseScheduleIsWorkday)

        val morning = resolution("2026-10-15", listOf(leaveDay("2026-10-15", LeavePortion.FIRST_HALF)))
        assertEquals(listOf(segment("2026-10-15", 14, 18)), morning.segments)
        val afternoon = resolution("2026-10-16", listOf(leaveDay("2026-10-16", LeavePortion.SECOND_HALF)))
        assertEquals(listOf(segment("2026-10-16", 9, 12), segment("2026-10-16", 13, 14)), afternoon.segments)

        val untouched = resolution("2026-10-13", listOf(leaveDay("2026-10-14", LeavePortion.WHOLE)))
        assertEquals(DayResolutionLayer.SCHEDULE, untouched.layer)
        assertEquals(2, untouched.segments.size)
    }

    @Test fun `a day corrected by hand or rested by a holiday is not changed by leave`() {
        val worked = DayOverride("2026-10-14", DayOverrideKind.CUSTOM_SEGMENTS, listOf(segment("2026-10-14", 10, 16)), null, 0.0, 1, RecordTestFixtures.id(3), ZONE)
        val corrected = resolution("2026-10-14", listOf(leaveDay("2026-10-14", LeavePortion.WHOLE)), overrides = listOf(worked))
        assertEquals(worked.segments, corrected.segments)

        val holiday = CalendarException(
            "2026-10-14#user", "2026-10-14", CalendarEffect.REST, CalendarExceptionOrigin.USER, false, null, null, null,
            0.0, 1, RecordTestFixtures.id(4), ZONE,
        )
        val rested = resolution("2026-10-14", listOf(leaveDay("2026-10-14", LeavePortion.FIRST_HALF)), exceptions = listOf(holiday))
        assertEquals(DayResolutionLayer.CALENDAR_EXCEPTION, rested.layer)
        assertFalse(rested.isScheduledWorkday)
    }
}
