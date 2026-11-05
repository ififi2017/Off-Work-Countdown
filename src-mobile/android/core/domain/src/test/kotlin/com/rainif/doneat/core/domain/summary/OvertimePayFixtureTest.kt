package com.rainif.doneat.core.domain.summary

import com.rainif.doneat.core.domain.SharedRuleFixtures
import com.rainif.doneat.core.domain.bool
import com.rainif.doneat.core.domain.double
import com.rainif.doneat.core.domain.salary.DailySalaryBasis
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.OvertimePay
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.ShiftTimeline
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

/**
 * Holds the overtime pay multiplier (plan 024 phase 3) to the TypeScript oracle,
 * case for case with the Swift `ScheduleRuleFixtureTests.overtimePay`: pay ratio,
 * earned so far, elapsed overtime, the unpaid-rate comparison and Records.
 */
class OvertimePayFixtureTest {
    private val pay: JsonObject get() = SharedRuleFixtures.data.getValue("overtimePay").jsonObject

    private fun section(name: String) = pay.getValue(name).jsonArray.map { it.jsonObject }

    private class Scenario(val id: String, val hours: ScheduleHours, val zone: ZoneId)

    private val scenarios: List<Scenario> by lazy {
        section("scenarios").map { o ->
            val schedule = o.getValue("schedule").jsonObject
            Scenario(
                o.string("id")!!,
                ScheduleHours(
                    startTime = o.string("startTime")!!,
                    endTime = o.string("endTime")!!,
                    workdays = o.getValue("workdays").jsonArray.map { it.jsonPrimitive.int },
                    schedule = WorkSchedule(mode = ScheduleMode.fromRaw(schedule.string("mode")!!)!!),
                    breakStartTime = o.string("breakStartTime"),
                    breakDurationMinutes = o.getValue("breakDurationMinutes").jsonPrimitive.int,
                    extended = null,
                ),
                ZoneId.of(o.string("zone")!!),
            )
        }
    }

    private val salaries: List<SalarySettings> by lazy {
        section("salaries").map {
            SalarySettings(
                it.string("salaryAmount")!!, SalaryType.fromRaw(it.string("salaryType")!!),
                it.double("monthlyWorkingDays")!!, it.double("annualBonusMonths")!!,
                DailySalaryBasis.fromRaw(it.string("dailySalaryBasis")),
            )
        }
    }

    /** IEEE comparison, so 0 and -0 agree as they do in Swift. */
    private fun eq(a: Double?, b: Double?) = (a == null && b == null) || (a != null && b != null && a == b)

    @Test
    fun normalization() {
        val cases = section("normalize")
        for (case in cases) {
            val value = case["value"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content?.toDouble()
            assertEquals("normalize $value", case.double("expected")!!, OvertimePay.normalized(value), 0.0)
        }
        assertTrue(cases.size >= 20)
    }

    @Test
    fun snapshotsAndComparisons() {
        val failures = ArrayList<String>()
        val cases = section("snapshots")
        for (case in cases) {
            val s = scenarios[case.getValue("sc").jsonPrimitive.int]
            val now = case.double("now")!!
            val salary = salaries[case.getValue("s").jsonPrimitive.int].copy(overtimePayMultiplier = case.double("m")!!)
            val actual = ScheduleRules.snapshot(ScheduleRuleInput(s.hours, now, s.zone, overtimeEndAtMs = case.double("ot")), salary)
            val timeline = ShiftTimeline(actual.segments, actual.plannedEndAtMs, actual.overtimeEndAtMs)
            val elapsed = timeline.overtimeElapsedMs(now)
            val comparison = timeline.overtimeRateComparison(actual.dailySalary, now)
            val e = case.getValue("expected").jsonObject
            val ec = e["comparison"]?.takeIf { it !is JsonNull }?.jsonObject
            val comparisonMatches = if (ec == null) comparison == null else comparison != null &&
                comparison.elapsedOvertimeMs == ec.double("elapsedOvertimeMs") &&
                eq(comparison.unpaidHourlyRate, ec.double("unpaidHourlyRate")) &&
                eq(comparison.unpaidRateDecreasePercent, ec.double("unpaidRateDecreasePercent"))
            val same = eq(actual.dailySalary, e.double("dailySalary")) && eq(actual.earnedSoFar, e.double("earnedSoFar")) &&
                eq(actual.payRatio, e.double("payRatio")) && elapsed == e.double("overtimeElapsedMs") && comparisonMatches
            if (!same && failures.size < 5) {
                failures += "${s.id} salary ${case.string("s")} m ${case.double("m")} at $now: expected $e, actual earned ${actual.earnedSoFar} ratio ${actual.payRatio} elapsed $elapsed comparison $comparison"
            }
        }
        assertTrue(cases.size >= 1_000)
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
        // The multiplier matters: the same overtime pays differently.
        val ratios = cases.filter { it.getValue("sc").jsonPrimitive.int == 1 && it.getValue("s").jsonPrimitive.int == 0 }
            .filter { it.getValue("expected").jsonObject.double("overtimeElapsedMs")!! > 0 }
            .map { it.getValue("expected").jsonObject.double("payRatio") }.toSet()
        assertTrue(ratios.size > 10)
    }

    @Test
    fun records() {
        val failures = ArrayList<String>()
        val cases = section("forecasts")
        for (case in cases) {
            val i = case.getValue("input").jsonObject
            val rules = i.getValue("salaryRules").jsonObject
            val actual = SummaryRules.recordsActualForecast(
                SummaryRules.ActualForecastInput(
                    days = i.getValue("days").jsonArray.map { day(it.jsonObject) },
                    periodDayKeys = i.getValue("periodDayKeys").jsonArray.map { it.jsonPrimitive.content },
                    dailySalary = i.double("dailySalary"),
                    asOfMs = i.double("asOfMs")!!,
                    salary = SalarySettings(rules.string("salaryAmount")!!, SalaryType.fromRaw(rules.string("salaryType")!!), rules.double("monthlyWorkingDays")!!, rules.double("annualBonusMonths")!!),
                    zone = ZoneId.of(rules.string("timeZoneIdentifier")!!),
                ),
            )
            val e = case.getValue("expected").jsonObject
            fun part(o: JsonObject) = SummaryRules.Part(o.double("days")!!, o.double("hours")!!, o.double("earnings"))
            val expected = SummaryRules.ActualForecast(
                e.double("actualOvertimeHours")!!,
                part(e.getValue("actual").jsonObject), part(e.getValue("forecast").jsonObject), part(e.getValue("total").jsonObject),
            )
            if (expected != actual && failures.size < 5) failures += "records ${scenarios[case.getValue("sc").jsonPrimitive.int].id}: expected $expected, actual $actual"
        }
        assertTrue(cases.size >= 100)
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
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
        overtimePayMultiplier = o.double("overtimePayMultiplier"),
    )

    private fun segments(e: JsonElement) = e.jsonArray.map {
        val s = it.jsonObject
        ShiftSegment(s.double("startAtMs")!!, s.double("endAtMs")!!)
    }
}
