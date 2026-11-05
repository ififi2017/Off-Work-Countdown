package com.rainif.doneat.core.domain.summary

import com.rainif.doneat.core.domain.SharedRuleFixtures
import com.rainif.doneat.core.domain.asDouble
import com.rainif.doneat.core.domain.double
import com.rainif.doneat.core.domain.salary.DailySalaryBasis
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.ShiftType
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import com.rainif.doneat.core.domain.string
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.ZoneId
import java.util.UUID

/**
 * Holds scheduled-month daily pay (plan 024) to the TypeScript oracle, case for case
 * with the Swift `ScheduleRuleFixtureTests.scheduledMonthBasis`.
 */
class MonthBasisFixtureTest {
    private val basis: JsonObject get() = SharedRuleFixtures.data.getValue("monthBasis").jsonObject

    private fun section(name: String) = basis.getValue(name).jsonArray.map { it.jsonObject }

    private class Scenario(val id: String, val hours: ScheduleHours, val zone: ZoneId, val plan: ExtendedSchedulePlan?)

    private val work = UUID.fromString("11111111-1111-4111-8111-111111111111")
    private val rest = UUID.fromString("22222222-2222-4222-8222-222222222222")

    private fun type(id: UUID, name: String, kind: ShiftType.Kind) =
        ShiftType(id, name, kind, 540, 1_020, true, 720, 60, "#3366CC", false)

    private fun plan(extended: JsonObject?): ExtendedSchedulePlan? {
        if (extended == null) return null
        val handSet = extended.getValue("handSet").jsonObject.mapValues { (_, kind) -> if (kind.jsonPrimitive.content == "work") work else rest }
        return ExtendedSchedulePlan(
            listOf(type(work, "Day", ShiftType.Kind.WORK), type(rest, "Rest", ShiftType.Kind.REST)),
            null, handSet, fallsBackToBaseSchedule = true,
        )
    }

    private val scenarios: List<Scenario> by lazy {
        section("scenarios").map { o ->
            val plan = plan(o["extended"]?.takeIf { it !is JsonNull }?.jsonObject)
            val schedule = o.getValue("schedule").jsonObject
            Scenario(
                o.string("id")!!,
                ScheduleHours(
                    startTime = o.string("startTime")!!,
                    endTime = o.string("endTime")!!,
                    workdays = o.getValue("workdays").jsonArray.map { it.jsonPrimitive.int },
                    schedule = WorkSchedule(
                        mode = ScheduleMode.fromRaw(schedule.string("mode")!!)!!,
                        referenceWeekStartMs = schedule.double("referenceWeekStartMs"),
                        referenceWeekType = schedule.string("referenceWeekType"),
                        singleWeekendWorkday = schedule.double("singleWeekendWorkday")?.toInt(),
                        rotationAnchorMs = schedule.double("rotationAnchorMs"),
                        rotationWorkDays = schedule.double("rotationWorkDays")?.toInt(),
                        rotationRestDays = schedule.double("rotationRestDays")?.toInt(),
                    ),
                    breakStartTime = o.string("breakStartTime"),
                    breakDurationMinutes = o.getValue("breakDurationMinutes").jsonPrimitive.int,
                    extended = plan,
                ),
                ZoneId.of(o.string("timeZoneIdentifier")!!),
                plan,
            )
        }
    }

    private fun salary(o: JsonObject, type: SalaryType? = null) = SalarySettings(
        amount = o.string("salaryAmount") ?: o.string("amount")!!,
        type = type ?: SalaryType.fromRaw(o.string("salaryType") ?: o.string("type")!!),
        monthlyWorkingDays = o.double("monthlyWorkingDays")!!,
        annualBonusMonths = o.double("annualBonusMonths")!!,
        dailySalaryBasis = DailySalaryBasis.fromRaw(o.string("dailySalaryBasis") ?: o.string("basis")),
    )

    private val salaries: List<SalarySettings> by lazy { section("salaries").map { salary(it) } }

    /** IEEE comparison, so 0 and -0 agree as they do in Swift. */
    private fun eq(a: Double?, b: Double?) = (a == null && b == null) || (a != null && b != null && a == b)

    private fun zone(s: Scenario) = CivilZone(s.zone, s.plan?.let(::ExtendedScheduleResolver))

    @Test
    fun snapshots() {
        val failures = ArrayList<String>()
        val cases = section("snapshots")
        for (case in cases) {
            val s = scenarios[case.getValue("sc").jsonPrimitive.int]
            val now = case.double("now")!!
            val actual = ScheduleRules.snapshot(ScheduleRuleInput(s.hours, now, s.zone), salaries[case.getValue("s").jsonPrimitive.int])
            val e = case.getValue("expected").jsonArray
            val same = eq(actual.dailySalary, e[0].asDouble()) && eq(actual.earnedSoFar, e[1].asDouble()) && eq(actual.payRatio, e[2].asDouble()) &&
                eq(actual.startAtMs, e[3].asDouble()) && actual.isWorkday == e[4].jsonPrimitive.boolean
            if (!same && failures.size < 5) failures += "${s.id} salary ${case.string("s")} at $now: expected $e, actual ${actual.dailySalary} ${actual.earnedSoFar} ${actual.payRatio} ${actual.startAtMs} ${actual.isWorkday}"
        }
        assertTrue(cases.size >= 400)
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
    }

    @Test
    fun summaries() {
        val failures = ArrayList<String>()
        val cases = section("summaries")
        for (case in cases) {
            val s = scenarios[case.getValue("sc").jsonPrimitive.int]
            val i = case.getValue("input").jsonObject
            val actual = SummaryRules.summarize(
                SummaryRules.SummaryInput(
                    period = if (i.string("period") == "year") SummaryRules.Period.YEAR else SummaryRules.Period.WEEK,
                    periodStartMs = i.double("periodStartMs"),
                    asOfMs = i.double("asOfMs")!!,
                    workdays = s.hours.workdays,
                    schedule = s.hours.schedule,
                    currentShiftStartMs = i.double("currentShiftStartMs")!!,
                    currentShiftEndMs = i.double("currentShiftEndMs")!!,
                    plannedDailyHours = i.double("plannedDailyHours")!!,
                    todayProgress = i.double("todayProgress")!!,
                    dailySalary = i.double("dailySalary"),
                    todayEffectiveHours = i.double("todayEffectiveHours")!!,
                    todayPayRatio = i.double("todayPayRatio")!!,
                    zone = s.zone,
                    extended = s.plan,
                    salary = salary(i.getValue("salary").jsonObject),
                ),
            )
            val e = case.getValue("expected").jsonObject
            val expected = SummaryRules.PeriodSummary(e.double("days")!!, e.double("hours")!!, e.double("earnings"))
            val same = expected.days == actual.days && expected.hours == actual.hours && eq(expected.earnings, actual.earnings)
            if (!same && failures.size < 5) failures += "${s.id} ${i.string("period")} at ${i.double("asOfMs")}: expected $expected, actual $actual"
        }
        assertTrue(cases.size >= 60)
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
    }

    @Test
    fun recordsIncomeAndMonthlyEquivalent() {
        for (case in section("recordsIncome")) {
            val s = scenarios[case.getValue("sc").jsonPrimitive.int]
            val months = case.getValue("completedByMonth").jsonArray.map {
                val m = it.jsonObject
                SummaryRules.MonthWorkdays(m.double("anchorMs")!!, m.getValue("count").jsonPrimitive.int)
            }
            val actual = SummaryRules.recordsIncome(
                case.getValue("completedWorkdays").jsonPrimitive.int, salaries[case.getValue("s").jsonPrimitive.int], months,
                SummaryRules.MonthContext(s.hours.workdays, s.hours.schedule, s.zone, s.plan),
            )
            assertTrue("records income ${s.id} salary ${case.string("s")} months ${case.string("m")}: expected ${case.double("expected")}, actual $actual", eq(case.double("expected"), actual))
        }
        for (case in section("monthlyEquivalent")) {
            val actual = SummaryRules.salaryMonthlyEquivalent(salaries[case.getValue("s").jsonPrimitive.int].copy(type = SalaryType.fromRaw(case.string("type")!!)))
            assertTrue("monthly equivalent ${case.string("s")} as ${case.string("type")}: expected ${case.double("expected")}, actual $actual", eq(case.double("expected"), actual))
        }
    }

    @Test
    fun monthCounts() {
        val cases = section("monthCounts")
        for (case in cases) {
            val s = scenarios[case.getValue("sc").jsonPrimitive.int]
            val actual = SummaryRules.scheduledWorkdaysInMonth(case.double("anchorMs")!!, s.hours.workdays, s.hours.schedule, s.plan != null, zone(s))
            assertEquals("${s.id} at ${case.double("anchorMs")}", case.getValue("expected").jsonPrimitive.int, actual)
        }
        val manual = scenarios.indexOfFirst { it.id == "shanghai-manual" }
        assertTrue(cases.filter { it.getValue("sc").jsonPrimitive.int == manual }.all { it.getValue("expected").jsonPrimitive.int == 0 })
        val goldenWeek = scenarios.indexOfFirst { it.id == "shanghai-golden-week" }
        val plain = scenarios.indexOfFirst { it.id == "shanghai-weekdays" }
        fun count(scenario: Int, month: Int) = cases.filter { it.getValue("sc").jsonPrimitive.int == scenario }[month].getValue("expected").jsonPrimitive.int
        assertEquals(18 to 22, count(goldenWeek, 9) to count(plain, 9))
        assertEquals(23 to 22, count(goldenWeek, 8) to count(plain, 8))
    }
}
