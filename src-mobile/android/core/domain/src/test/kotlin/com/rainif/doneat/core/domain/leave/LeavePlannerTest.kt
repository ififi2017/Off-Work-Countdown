package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.records.LeaveBalance
import com.rainif.doneat.core.domain.records.LeaveBalanceUse
import com.rainif.doneat.core.domain.records.LeaveBudget
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.LeavePortion
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ShiftCycleRule
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.ShiftType
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

/** One-to-one with iOS `LeavePlannerTests`. */
class LeavePlannerTest {
    private companion object {
        const val SHANGHAI = "Asia/Shanghai"
        fun uuid(n: Int) = UUID.fromString("00000000-0000-0000-0000-%012d".format(n))
        val office = uuid(201)
        val rest = uuid(202)
        val night = uuid(203)
        val annual = uuid(211).toString()
        val inLieu = uuid(212).toString()

        val holidays: HolidayCalendar by lazy {
            HolidayCalendar.parse(File(System.getProperty("owc.holidayTemplates")).readText())
        }

        val officeType = ShiftType(office, "Office", ShiftType.Kind.WORK, 9 * 60, 18 * 60, true, 12 * 60, 60, "#FF7A00", false)
        val restType = ShiftType(rest, "Rest", ShiftType.Kind.REST, 9 * 60, 18 * 60, false, 12 * 60, 0, "#777777", false)
        val nightType = ShiftType(night, "Night", ShiftType.Kind.WORK, 22 * 60, 6 * 60, false, 0, 0, "#3366FF", false)

        fun dayNumber(key: String) = ExtendedScheduleResolver.dayNumber(key)!!

        fun instant(key: String, hour: Int, minute: Int = 0, zone: String = SHANGHAI): Double {
            val (y, m, d) = key.split("-").map { it.toInt() }
            return LocalDateTime.of(y, m, d, hour, minute).atZone(ZoneId.of(zone)).toInstant().toEpochMilli().toDouble()
        }

        fun seg(key: String, from: Int, to: Int) = ShiftSegment(instant(key, from), instant(key, to))

        /** Monday-Friday of [workType], weekends off, optionally on a holiday region. */
        fun weeklyPlan(workType: ShiftType = officeType, region: String? = null, handSet: Map<String, UUID> = emptyMap()) =
            ExtendedSchedulePlan(
                shiftTypes = listOf(workType, restType),
                rule = ShiftCycleRule(
                    ShiftCycleRule.Preset.WEEKLY, "2026-09-21",
                    listOf(workType.id, workType.id, workType.id, workType.id, workType.id, rest, rest),
                ),
                handSetDays = handSet,
                holidayRegionIdentifier = region,
                holidays = holidays,
            )

        fun hours(plan: ExtendedSchedulePlan?) =
            ScheduleHours("09:00", "17:00", listOf(1, 2, 3, 4, 5), WorkSchedule(ScheduleMode.CLASSIC), null, 0, plan)

        fun proposals(
            plan: ExtendedSchedulePlan?,
            goal: LeavePlanner.Goal,
            from: String,
            through: String,
            now: Double,
            budgets: List<LeaveBudget>,
            zone: String = SHANGHAI,
        ): List<LeavePlanProposal> {
            val range = dayNumber(from)..dayNumber(through)
            val days = LeavePlannerSchedule.days(hours(plan), range, ZoneId.of(zone), holidays)
            return LeavePlanner.proposals(days, LeavePlanner.Query(goal, range.first, range.last, now, budgets))
        }

        fun budget(id: String = annual, halfDays: Int, from: String? = null, through: String? = null) =
            LeaveBudget(id, halfDays, from?.let(::dayNumber), through?.let(::dayNumber))
    }

    // Halves

    @Test fun `halves split effective time and skip the break`() {
        val segments = listOf(seg("2026-09-24", 9, 12), seg("2026-09-24", 13, 18))
        val halves = LeaveShiftHalves(segments)
        assertEquals(listOf(segments[0], seg("2026-09-24", 13, 14)), halves.first)
        assertEquals(listOf(seg("2026-09-24", 14, 18)), halves.second)
        assertEquals(halves.second, halves.remaining(LeavePortion.FIRST_HALF))
        assertTrue(halves.remaining(LeavePortion.WHOLE).isEmpty())
    }

    // Mid-Autumn and National Day 2026

    @Test fun `three days bridge Mid-Autumn to National Day for thirteen off`() {
        val result = proposals(
            weeklyPlan(region = "CN"), LeavePlanner.Goal.RestAtLeast(13), "2026-09-21", "2026-10-31",
            instant("2026-09-20", 10), listOf(budget(halfDays = 20)),
        )
        val best = result.first()
        assertEquals("2026-09-25", best.firstRestDayKey)
        assertEquals("2026-10-07", best.lastRestDayKey)
        assertEquals(13, best.fullRestDays)
        assertEquals(6, best.costHalfDays)
        assertEquals(listOf("2026-09-28", "2026-09-29", "2026-09-30"), best.items.map { it.dayKey })
        assertTrue(best.items.all { it.portion == LeavePortion.WHOLE && it.role == LeavePlanItem.Role.BRIDGE })
        assertEquals(
            List(3) { LeavePlanProposal.DayKind.HOLIDAY } + List(3) { LeavePlanProposal.DayKind.LEAVE } +
                List(7) { LeavePlanProposal.DayKind.HOLIDAY },
            best.dayKinds,
        )
        assertEquals(instant("2026-09-24", 18), best.lastShiftEndAtMs)
        assertEquals(instant("2026-10-08", 9), best.nextShiftStartAtMs)
        assertEquals(listOf(LeaveBalanceUse(annual, 6)), best.uses)
        assertTrue(best.caveats.isEmpty())
    }

    @Test fun `seven days off during National Day costs nothing`() {
        val result = proposals(
            weeklyPlan(region = "CN"), LeavePlanner.Goal.RestAtLeast(7), "2026-09-21", "2026-10-31",
            instant("2026-09-20", 10), listOf(budget(halfDays = 20)),
        )
        val best = result.first()
        assertEquals("2026-10-01", best.firstRestDayKey)
        assertEquals("2026-10-07", best.lastRestDayKey)
        assertEquals(0, best.costHalfDays)
        // Distinct stretches only: nothing else overlaps the week chosen.
        assertFalse(result.drop(1).any { it.firstRestDayNumber <= best.lastRestDayNumber && it.lastRestDayNumber >= best.firstRestDayNumber })
    }

    @Test fun `a spare half day leaves early on the last working afternoon`() {
        val result = proposals(
            weeklyPlan(region = "CN"), LeavePlanner.Goal.LeaveAtMost(7), "2026-09-21", "2026-10-31",
            instant("2026-09-20", 10), listOf(budget(halfDays = 20)),
        )
        val best = result.first()
        assertEquals("2026-09-25", best.firstRestDayKey)
        assertEquals("2026-10-07", best.lastRestDayKey)
        assertEquals(6, best.bridgeHalfDays)
        assertEquals(7, best.costHalfDays)
        val early = best.items.first()
        assertEquals("2026-09-24", early.dayKey)
        assertEquals(LeavePortion.SECOND_HALF, early.portion)
        assertEquals(LeavePlanItem.Role.EARLY_DEPARTURE, early.role)
        assertEquals(listOf(seg("2026-09-24", 14, 18)), early.segments)
        assertEquals(instant("2026-09-24", 14), best.lastShiftEndAtMs)
    }

    @Test fun `a makeup Saturday is not a free day off`() {
        val result = proposals(
            weeklyPlan(region = "CN"), LeavePlanner.Goal.RestAtLeast(2), "2026-10-08", "2026-10-18",
            instant("2026-09-20", 10), listOf(budget(halfDays = 20)),
        )
        val best = result.first()
        assertEquals("2026-10-17", best.firstRestDayKey)
        assertEquals(0, best.costHalfDays)
        val makeupDay = dayNumber("2026-10-10")
        for (proposal in result) {
            if (makeupDay in proposal.firstRestDayNumber..proposal.lastRestDayNumber) {
                assertTrue(proposal.items.any { it.dayKey == "2026-10-10" })
            }
        }
    }

    @Test fun `a holiday the roster still works has to be taken as leave`() {
        val result = proposals(
            weeklyPlan(region = "CN", handSet = mapOf("2026-10-03" to office)), LeavePlanner.Goal.RestAtLeast(7),
            "2026-09-21", "2026-10-31", instant("2026-09-20", 10), listOf(budget(halfDays = 20)),
        )
        val best = result.first()
        assertEquals("2026-10-01", best.firstRestDayKey)
        assertEquals("2026-10-07", best.lastRestDayKey)
        assertEquals(listOf("2026-10-03"), best.items.map { it.dayKey })
        assertEquals(2, best.costHalfDays)
    }

    // Balances

    @Test fun `leave is spent from the balance that expires first`() {
        val result = proposals(
            weeklyPlan(region = "CN"), LeavePlanner.Goal.RestAtLeast(13), "2026-09-21", "2026-10-31",
            instant("2026-09-20", 10),
            listOf(budget(inLieu, halfDays = 4), budget(annual, halfDays = 4, through = "2026-09-29")),
        )
        val best = result.first()
        assertEquals(13, best.fullRestDays)
        assertEquals(
            listOf(
                listOf(LeaveBalanceUse(annual, 2)),
                listOf(LeaveBalanceUse(annual, 2)),
                listOf(LeaveBalanceUse(inLieu, 2)),
            ),
            best.items.map { it.uses },
        )
        assertEquals(listOf(LeaveBalanceUse(inLieu, 2), LeaveBalanceUse(annual, 4)), best.uses)
    }

    @Test fun `an expired balance cannot pay for later days`() {
        val result = proposals(
            weeklyPlan(region = "CN"), LeavePlanner.Goal.RestAtLeast(13), "2026-09-21", "2026-10-31",
            instant("2026-09-20", 10),
            listOf(budget(inLieu, halfDays = 4), budget(annual, halfDays = 4, through = "2026-09-27")),
        )
        assertTrue(result.isEmpty())
    }

    @Test fun `three and a half days are seven half days`() {
        var balance = LeaveBalance(annual, "annual", null, 10, 3, null, "2027-03-31", 0.0, 0, "")
        assertEquals(7, balance.remainingHalfDays)
        assertEquals(5, balance.budget(adoptedHalfDays = 2)?.availableHalfDays)
        assertEquals(dayNumber("2027-03-31"), balance.budget()?.validThroughDayNumber)
        balance = balance.copy(validThroughDayKey = "2027-02-30")
        assertFalse(balance.isValid)
        balance = balance.copy(validThroughDayKey = null, kind = "custom")
        assertFalse(balance.isValid)
        balance = balance.copy(name = "Marriage leave")
        assertTrue(balance.isValid)
    }

    // Time

    @Test fun `a shift that has started cannot be taken off`() {
        val result = proposals(
            weeklyPlan(region = "CN"), LeavePlanner.Goal.RestAtLeast(13), "2026-09-28", "2026-10-31",
            instant("2026-09-28", 10), listOf(budget(halfDays = 20)),
        )
        // Today's shift is under way, so thirteen days now start tomorrow and
        // reach past National Day through the makeup Saturday instead.
        val best = result.first()
        assertEquals("2026-09-29", best.firstRestDayKey)
        assertEquals("2026-10-11", best.lastRestDayKey)
        assertEquals(listOf("2026-09-29", "2026-09-30", "2026-10-08", "2026-10-09", "2026-10-10"), best.items.map { it.dayKey })
        assertFalse(result.any { p -> p.items.any { it.dayKey == "2026-09-28" } })
    }

    @Test fun `half an overnight shift frees the evening it starts`() {
        val result = proposals(
            weeklyPlan(workType = nightType), LeavePlanner.Goal.RestAtLeast(2), "2026-10-05", "2026-10-25",
            instant("2026-10-01", 10), listOf(budget(halfDays = 20)),
        )
        val best = result.first()
        // Saturday still carries Friday night's shift until 06:00, so the
        // cheap pair is Sunday plus Monday, whose shift starts at 22:00.
        assertEquals("2026-10-11", best.firstRestDayKey)
        assertEquals("2026-10-12", best.lastRestDayKey)
        assertEquals(listOf(LeavePortion.FIRST_HALF), best.items.map { it.portion })
        assertEquals(listOf("2026-10-12"), best.items.map { it.dayKey })
        assertEquals(instant("2026-10-10", 6), best.lastShiftEndAtMs)
        assertEquals(instant("2026-10-13", 2), best.nextShiftStartAtMs)
    }

    @Test fun `across a DST change days are civil days, not 24 hours`() {
        val zone = "America/New_York"
        val range = dayNumber("2026-10-26")..dayNumber("2026-11-15")
        val days = LeavePlannerSchedule.days(hours(null), range, ZoneId.of(zone), holidays)
        val fallBack = days.first { it.dayKey == "2026-11-01" }
        assertEquals(25 * 3_600_000.0, fallBack.endAtMs - fallBack.startAtMs, 0.0)

        val weekend = proposals(
            null, LeavePlanner.Goal.RestAtLeast(2), "2026-10-26", "2026-11-15",
            instant("2026-10-20", 10, zone = zone), listOf(budget(halfDays = 20)), zone,
        )
        assertEquals("2026-10-31", weekend.first().firstRestDayKey)
        assertEquals("2026-11-01", weekend.first().lastRestDayKey)
        assertEquals(0, weekend.first().costHalfDays)

        val nine = proposals(
            null, LeavePlanner.Goal.RestAtLeast(9), "2026-10-26", "2026-11-15",
            instant("2026-10-20", 10, zone = zone), listOf(budget(halfDays = 20)), zone,
        )
        assertEquals(9, nine.first().fullRestDays)
        assertEquals(10, nine.first().costHalfDays)
    }

    // Planning window and data coverage

    @Test fun `the planning year rolls from today and never stops at New Year`() {
        assertEquals(dayNumber("2026-09-27")..dayNumber("2027-09-26"), LeavePlannerSchedule.rollingYear(LocalDate.of(2026, 9, 27)))
        assertEquals(dayNumber("2028-02-29")..dayNumber("2029-02-27"), LeavePlannerSchedule.rollingYear(LocalDate.of(2028, 2, 29)))
    }

    @Test fun `a year this build has no holidays for follows the ordinary schedule`() {
        val range = dayNumber("2026-12-20")..dayNumber("2027-01-31")
        val plan = weeklyPlan(region = "CN")
        val days = LeavePlannerSchedule.days(hours(plan), range, ZoneId.of(SHANGHAI), holidays)
        val newYearsEve = days.first { it.dayKey == "2026-12-31" }
        val newYearsDay = days.first { it.dayKey == "2027-01-01" }
        assertTrue(newYearsEve.caveats.isEmpty())
        // A Friday on the roster, with no predicted holiday mixed in.
        assertTrue(newYearsDay.segments.isNotEmpty())
        assertFalse(newYearsDay.isHoliday)
        assertEquals(setOf<LeavePlannerCaveat>(LeavePlannerCaveat.HolidaysNotIncluded(2027)), newYearsDay.caveats)

        val covered = LeavePlannerSchedule.days(hours(plan), range, ZoneId.of(SHANGHAI)) { _, _ -> true }
        assertTrue(covered.all { it.caveats.isEmpty() })

        val result = proposals(
            plan, LeavePlanner.Goal.RestAtLeast(9), "2027-01-04", "2027-01-31",
            instant("2026-12-20", 10), listOf(budget(halfDays = 20)),
        )
        val best = result.first()
        assertEquals(10, best.costHalfDays)
        assertEquals(setOf<LeavePlannerCaveat>(LeavePlannerCaveat.HolidaysNotIncluded(2027)), best.caveats)
    }

    @Test fun `a whole rolling year is searched for both goals`() {
        val today = LocalDate.of(2026, 9, 1)
        val range = LeavePlannerSchedule.rollingYear(today)!!
        val zone = ZoneId.of(SHANGHAI)
        val days = LeavePlannerSchedule.days(hours(weeklyPlan(region = "CN")), range, zone, holidays)
        val budgets = listOf(budget(halfDays = 30))
        val nowMs = LocalDateTime.of(2026, 9, 1, 8, 0).atZone(zone).toInstant().toEpochMilli().toDouble()
        for (goal in listOf(LeavePlanner.Goal.RestAtLeast(10), LeavePlanner.Goal.LeaveAtMost(30))) {
            val result = LeavePlanner.proposals(days, LeavePlanner.Query(goal, range.first, range.last, nowMs, budgets))
            assertTrue(result.isNotEmpty())
            assertTrue(result.all { it.costHalfDays <= 30 })
            assertTrue(result.all { it.firstRestDayNumber in range && it.lastRestDayNumber in range })
        }
    }
}
