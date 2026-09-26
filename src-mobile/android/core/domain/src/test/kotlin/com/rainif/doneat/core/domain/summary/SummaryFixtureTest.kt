package com.rainif.doneat.core.domain.summary

import com.rainif.doneat.core.domain.SharedRuleFixtures
import com.rainif.doneat.core.domain.bool
import com.rainif.doneat.core.domain.double
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryRules
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
import java.time.LocalDate
import java.time.LocalDateTime

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
    fun salaryInputKeepsEmptyDistinctFromZeroAndRejectsInvalidNumbers() {
        fun daily(amount: String) = SalaryRules.dailySalary(SalarySettings(amount, SalaryType.DAILY, 20.0, 0.0))
        assertEquals(null, daily(""))
        assertEquals(0.0, daily("0")!!, 0.0)
        for (amount in listOf("-1", "1e309", "NaN", "Infinity", "1,5")) {
            assertEquals("salary '$amount'", null, daily(amount))
        }
        assertEquals(null, SalaryRules.dailySalary(SalarySettings("1000", SalaryType.MONTHLY, 0.0, 0.0)))
        assertEquals(null, SalaryRules.dailySalary(SalarySettings("1000", SalaryType.MONTHLY, 20.0, Double.POSITIVE_INFINITY)))
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
    fun lifetimeIncomeLeavesEmploymentGapsEmptyAndRejectsOverlap() {
        val january = SummaryRules.IncomePeriod("2026-01-01", "2026-02-01", 1_000.0, SummaryRules.Cadence.MONTHLY)
        val march = SummaryRules.IncomePeriod("2026-03-01", "2026-04-01", 2_000.0, SummaryRules.Cadence.MONTHLY)
        val separated = SummaryRules.lifetimeIncome(SummaryRules.LifetimeInput(listOf(january, march), null, null, "2026-04-01", "2026-04-01"))
        assertEquals(3_000.0, separated.historicalGross, 1e-7)
        assertEquals(0.0, separated.projectedGross, 0.0)
        val overlap = march.copy(startsOn = "2026-01-15")
        val refused = SummaryRules.lifetimeIncome(SummaryRules.LifetimeInput(listOf(january, overlap), null, null, "2026-04-01", "2026-04-01"))
        assertEquals(0.0, refused.totalGross, 0.0)
        val reversed = january.copy(endsOn = "2025-12-31")
        assertEquals(0.0, SummaryRules.lifetimeIncome(SummaryRules.LifetimeInput(listOf(reversed), null, null, "2026-04-01", "2026-04-01")).totalGross, 0.0)
    }

    @Test
    fun futureAgeThresholdAppliesOneFixedRatioUntilRetirement() {
        val base = SummaryRules.LifetimeInput(
            emptyList(), SummaryRules.CurrentSalary(1_000.0, SummaryRules.Cadence.MONTHLY, "2020-01-01"),
            SummaryRules.IncomeDecline("2035-01-01", 0.6), "2030-01-01", "2050-01-01",
        )
        val income = SummaryRules.lifetimeIncome(base)
        assertEquals(120_000.0, income.historicalGross, 1e-7)
        assertEquals(60_000.0 + 108_000.0, income.projectedGross, 1e-7)
        assertEquals(288_000.0, income.totalGross, 1e-7)
    }

    @Test
    fun partialLeapMonthUsesItsOwnDayCountAndAnExclusiveEnd() {
        val month = SummaryRules.IncomePeriod("2028-02-15", "2028-03-02", 2_900.0, SummaryRules.Cadence.MONTHLY)
        val year = month.copy(salaryAmount = 34_800.0, cadence = SummaryRules.Cadence.YEARLY)
        val expected = 2_900.0 * 15 / 29 + 2_900.0 / 31
        for (period in listOf(month, year)) {
            val income = SummaryRules.lifetimeIncome(SummaryRules.LifetimeInput(listOf(period), null, null, "2028-03-02", "2028-03-02"))
            assertEquals(expected, income.historicalGross, 1e-7)
            assertEquals(0.0, income.projectedGross, 0.0)
        }
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

    @Test
    fun fixedMonthlyPayKeepsTheFullMonthAndBonusShareDespiteSparseRecords() {
        val zone = ZoneId.of("UTC")
        val keys = (1..30).map { "2026-09-%02d".format(it) }
        val salary = SalarySettings("3000", SalaryType.MONTHLY, 20.0, 1.0)
        val asOf = LocalDateTime.of(2026, 9, 15, 12, 0).atZone(zone).toInstant().toEpochMilli().toDouble()
        fun result(days: List<SummaryRules.RecordsDay>) = SummaryRules.recordsActualForecast(
            SummaryRules.ActualForecastInput(days, keys, null, asOf, salary, zone),
        )
        val sparse = result(emptyList())
        val leave = result(listOf(SummaryRules.RecordsDay(SummaryRules.ActualKind.CORRECTED, emptyList(), emptyList(), emptyList(), emptyList(), false)))
        assertEquals(3_250.0, sparse.total.earnings!!, 1e-7)
        assertEquals(1_625.0, sparse.actual.earnings!!, 1e-7)
        assertEquals(1_625.0, sparse.forecast.earnings!!, 1e-7)
        assertEquals(sparse.total.earnings, leave.total.earnings)
    }

    @Test
    fun monthlyWeekCrossingMonthsUsesEachMonthsNaturalDays() {
        val zone = ZoneId.of("UTC")
        val keys = listOf("2026-08-30", "2026-08-31") + (1..5).map { "2026-09-%02d".format(it) }
        val asOf = LocalDateTime.of(2026, 9, 1, 12, 0).atZone(zone).toInstant().toEpochMilli().toDouble()
        val salary = SalarySettings("3100", SalaryType.MONTHLY, 21.75, 0.0)
        val result = SummaryRules.recordsActualForecast(SummaryRules.ActualForecastInput(emptyList(), keys, null, asOf, salary, zone))
        assertEquals(3_100.0 * (2.0 / 31 + 1.0 / 30), result.actual.earnings!!, 1e-7)
        assertEquals(3_100.0 * 4 / 30, result.forecast.earnings!!, 1e-7)
        assertEquals(result.actual.earnings!! + result.forecast.earnings!!, result.total.earnings!!, 1e-7)
    }

    @Test
    fun dailyPayFollowsWorkdaysWhileMonthlyPayIncludesRestDays() {
        val zone = ZoneId.of("UTC")
        val start = LocalDateTime.of(2026, 9, 1, 9, 0).atZone(zone).toInstant().toEpochMilli().toDouble()
        val work = listOf(ShiftSegment(start, start + 8 * 3_600_000))
        val day = SummaryRules.RecordsDay(null, work, work, emptyList(), emptyList(), false)
        val keys = listOf("2026-09-01", "2026-09-02")
        val asOf = LocalDate.parse("2026-08-31").atStartOfDay(zone).toInstant().toEpochMilli().toDouble()
        val daily = SalarySettings("100", SalaryType.DAILY, 20.0, 0.0)
        val fixed = SalarySettings("3000", SalaryType.MONTHLY, 20.0, 0.0)
        val actualDaily = SummaryRules.recordsActualForecast(SummaryRules.ActualForecastInput(listOf(day), keys, SalaryRules.dailySalary(daily), asOf, daily, zone))
        val actualFixed = SummaryRules.recordsActualForecast(SummaryRules.ActualForecastInput(listOf(day), keys, SalaryRules.dailySalary(fixed), asOf, fixed, zone))
        assertEquals(100.0, actualDaily.total.earnings!!, 1e-7)
        assertEquals(200.0, actualFixed.total.earnings!!, 1e-7)
    }

    @Test
    fun partlyObservedDayReconcilesElapsedAndFutureWithoutOverlap() {
        val zone = ZoneId.of("UTC")
        val start = LocalDateTime.of(2026, 9, 1, 9, 0).atZone(zone).toInstant().toEpochMilli().toDouble()
        val now = start + 4 * 3_600_000
        val work = listOf(ShiftSegment(start, start + 8 * 3_600_000))
        val day = SummaryRules.RecordsDay(
            SummaryRules.ActualKind.OBSERVED, work, work, emptyList(),
            listOf(SummaryRules.Observation(true, start)), true,
        )
        val result = SummaryRules.recordsActualForecast(SummaryRules.ActualForecastInput(listOf(day), listOf("2026-09-01"), 100.0, now, null, zone))
        assertEquals(4.0, result.actual.hours, 1e-9)
        assertEquals(4.0, result.forecast.hours, 1e-9)
        assertEquals(8.0, result.total.hours, 1e-9)
        assertEquals(50.0, result.actual.earnings!!, 1e-9)
        assertEquals(50.0, result.forecast.earnings!!, 1e-9)
        assertEquals(100.0, result.total.earnings!!, 1e-9)
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
