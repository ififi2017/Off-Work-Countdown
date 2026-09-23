package com.rainif.doneat.core.domain.summary

import com.rainif.doneat.core.domain.SharedRuleFixtures
import com.rainif.doneat.core.domain.bool
import com.rainif.doneat.core.domain.double
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import com.rainif.doneat.core.domain.string
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.ZoneId

/** Holds [SummaryRules] to the TypeScript oracle, case for case with Swift's `ScheduleRuleFixtureTests`. */
class SummaryFixtureTest {
    private val f = SharedRuleFixtures

    @Test
    fun periodSummaries() {
        val cases = f.section("summaries")
        val failures = ArrayList<String>()
        for (case in cases) {
            val i = case.getValue("input").jsonObject
            val actual = SummaryRules.summarize(
                SummaryRules.SummaryInput(
                    period = if (i.string("period") == "year") SummaryRules.Period.YEAR else SummaryRules.Period.WEEK,
                    periodStartMs = i.double("periodStartMs"),
                    asOfMs = i.double("asOfMs")!!,
                    workdays = i.getValue("workdays").jsonArray.map { it.jsonPrimitive.int },
                    schedule = schedule(i.getValue("schedule").jsonObject),
                    currentShiftStartMs = i.double("currentShiftStartMs")!!,
                    currentShiftEndMs = i.double("currentShiftEndMs")!!,
                    plannedDailyHours = i.double("plannedDailyHours")!!,
                    todayProgress = i.double("todayProgress")!!,
                    dailySalary = i.double("dailySalary"),
                    todayEffectiveHours = i.double("todayEffectiveHours")!!,
                    todayPayRatio = i.double("todayPayRatio")!!,
                    zone = ZoneId.of(i.string("timeZoneIdentifier")!!),
                ),
            )
            val e = case.getValue("expected").jsonObject
            val expected = SummaryRules.PeriodSummary(e.double("days")!!, e.double("hours")!!, e.double("earnings"))
            if (!same(expected, actual) && failures.size < 5) failures += "${i.string("period")} at ${i.double("asOfMs")}: expected $expected, actual $actual"
        }
        assertTrue(cases.size >= 300)
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
        // fa927fb: Wednesday afternoon halfway through the shift is 2.5 days of pay, not 2; manual mode counts today.
        assertEquals(SummaryRules.PeriodSummary(2.5, 22.5, 2_500.0), cases[0].getValue("expected").jsonObject.let {
            SummaryRules.PeriodSummary(it.double("days")!!, it.double("hours")!!, it.double("earnings"))
        })
    }

    @Test
    fun recordsIncomeAndMonthlyEquivalent() {
        for (case in f.section("recordsIncome")) {
            val salary = f.salaries[case.getValue("s").jsonPrimitive.int]
            val n = case.getValue("n").jsonPrimitive.int
            assertEquals("records income, salary ${case.string("s")}, $n days", case.double("expected"), SummaryRules.recordsIncome(n, salary))
        }
        for (case in f.section("monthlyEquivalent")) {
            val salary = f.salaries[case.getValue("s").jsonPrimitive.int].copy(type = SalaryType.fromRaw(case.string("type")!!))
            assertEquals("monthly equivalent ${case.string("s")} as ${case.string("type")}", case.double("expected"), SummaryRules.salaryMonthlyEquivalent(salary))
        }
    }

    @Test
    fun lifetimeIncome() {
        val cases = f.section("lifetimeIncome")
        var positive = 0
        cases.forEachIndexed { index, case ->
            val i = case.getValue("input").jsonObject
            val actual = SummaryRules.lifetimeIncome(
                SummaryRules.LifetimeInput(
                    periods = i.getValue("periods").jsonArray.map {
                        val p = it.jsonObject
                        SummaryRules.IncomePeriod(p.string("startsOn")!!, p.string("endsOn"), p.double("salaryAmount")!!, SummaryRules.Cadence.fromRaw(p.string("salaryCadence")!!))
                    },
                    currentSalary = i.obj("currentSalary")?.let {
                        SummaryRules.CurrentSalary(it.double("salaryAmount")!!, SummaryRules.Cadence.fromRaw(it.string("salaryCadence")!!), it.string("startsOn"))
                    },
                    futureIncomeDecline = i.obj("futureIncomeDecline")?.let { SummaryRules.IncomeDecline(it.string("startsOn")!!, it.double("retirementRatio")!!) },
                    asOf = i.string("asOf")!!,
                    retirementOn = i.string("retirementOn")!!,
                ),
            )
            val e = case.getValue("expected").jsonObject
            val expected = SummaryRules.LifetimeIncome(e.double("historicalGross")!!, e.double("projectedGross")!!, e.double("totalGross")!!)
            assertEquals("lifetime case $index", expected, actual)
            if (expected.totalGross > 0) positive++
        }
        assertTrue(positive > 0)
    }

    @Test
    fun actualAndForecast() {
        val cases = f.section("actualForecast")
        cases.forEachIndexed { index, case ->
            val i = case.getValue("input").jsonObject
            val rules = i.obj("salaryRules")
            val actual = SummaryRules.recordsActualForecast(
                SummaryRules.ActualForecastInput(
                    days = i.getValue("days").jsonArray.map { day(it.jsonObject) },
                    periodDayKeys = i.getValue("periodDayKeys").jsonArray.map { it.jsonPrimitive.content },
                    dailySalary = i.double("dailySalary"),
                    asOfMs = i.double("asOfMs")!!,
                    salary = rules?.let {
                        SalarySettings(it.string("salaryAmount")!!, SalaryType.fromRaw(it.string("salaryType")!!), it.double("monthlyWorkingDays")!!, it.double("annualBonusMonths")!!)
                    },
                    zone = ZoneId.of(rules?.string("timeZoneIdentifier") ?: "UTC"),
                ),
            )
            val e = case.getValue("expected").jsonObject
            fun part(o: JsonObject) = SummaryRules.Part(o.double("days")!!, o.double("hours")!!, o.double("earnings"))
            val expected = SummaryRules.ActualForecast(
                e.double("actualOvertimeHours")!!,
                part(e.getValue("actual").jsonObject),
                part(e.getValue("forecast").jsonObject),
                part(e.getValue("total").jsonObject),
            )
            assertEquals("actual/forecast case $index", expected, actual)
        }
        assertTrue(cases.size >= 100)
    }

    private fun day(o: JsonObject) = SummaryRules.RecordsDay(
        actualKind = SummaryRules.ActualKind.fromRaw(o.string("actualKind")),
        resolvedSegments = segments(o.getValue("resolvedSegments")),
        plannedSegments = segments(o.getValue("plannedSegments")),
        overtimeSegments = segments(o.getValue("overtimeSegments")),
        observations = o.getValue("observations").jsonArray.map {
            val x = it.jsonObject
            SummaryRules.Observation(x.string("kind") == "started", x.double("occurredAtMs")!!)
        },
        isActiveAnchor = o.bool("isActiveAnchor"),
    )

    private fun segments(e: JsonElement) = e.jsonArray.map {
        val s = it.jsonObject
        ShiftSegment(s.double("startAtMs")!!, s.double("endAtMs")!!)
    }

    private fun schedule(o: JsonObject) = WorkSchedule(
        mode = ScheduleMode.fromRaw(o.string("mode")!!)!!,
        referenceWeekStartMs = o.double("referenceWeekStartMs"),
        referenceWeekType = o.string("referenceWeekType"),
        singleWeekendWorkday = o.double("singleWeekendWorkday")?.toInt(),
        rotationAnchorMs = o.double("rotationAnchorMs"),
        rotationWorkDays = o.double("rotationWorkDays")?.toInt(),
        rotationRestDays = o.double("rotationRestDays")?.toInt(),
    )

    private fun JsonObject.obj(key: String) = get(key)?.takeIf { it !is JsonNull }?.jsonObject

    /** IEEE comparison, so 0 and -0 agree as they do in Swift. */
    private fun same(a: SummaryRules.PeriodSummary, b: SummaryRules.PeriodSummary) =
        a.days == b.days && a.hours == b.hours && (a.earnings == null) == (b.earnings == null) &&
            (a.earnings == null || a.earnings == b.earnings!!)
}

