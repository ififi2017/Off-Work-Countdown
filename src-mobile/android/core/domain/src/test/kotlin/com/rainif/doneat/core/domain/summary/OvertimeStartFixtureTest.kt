package com.rainif.doneat.core.domain.summary

import com.rainif.doneat.core.domain.SharedRuleFixtures
import com.rainif.doneat.core.domain.bool
import com.rainif.doneat.core.domain.double
import com.rainif.doneat.core.domain.salary.DailySalaryBasis
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.CountedOvertime
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
 * Holds overtime that starts after a rest, and counted hours (plan 024 phase 4),
 * to the TypeScript oracle, case for case with the Swift
 * `ScheduleRuleFixtureTests.overtimeStart`.
 */
class OvertimeStartFixtureTest {
    private val fixtures: JsonObject get() = SharedRuleFixtures.data.getValue("overtimeStart").jsonObject

    private fun section(name: String) = fixtures.getValue(name).jsonArray.map { it.jsonObject }

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

    private fun JsonObject.optDouble(key: String) = this[key]?.takeIf { it !is JsonNull }?.let { it.jsonPrimitive.content.toDouble() }

    @Test
    fun countedHours() {
        val normalize = section("normalizeCounted")
        for (case in normalize) {
            assertEquals("normalize ${case["value"]}", case.optDouble("expected"), CountedOvertime.normalized(case.optDouble("value")))
        }
        val scales = section("scales")
        for (case in scales) {
            assertEquals(
                "scale ${case["fullMs"]} ${case["countedMs"]}",
                case.double("expected")!!, CountedOvertime.scale(case.double("fullMs")!!, case.optDouble("countedMs")), 0.0,
            )
        }
        assertTrue(normalize.size >= 10)
        assertTrue(scales.size >= 50)
    }

    @Test
    fun snapshots() {
        val failures = ArrayList<String>()
        val cases = section("snapshots")
        for (case in cases) {
            val s = scenarios[case.getValue("sc").jsonPrimitive.int]
            val now = case.double("now")!!
            val salary = salaries[case.getValue("s").jsonPrimitive.int].copy(overtimePayMultiplier = case.double("m")!!)
            val actual = ScheduleRules.snapshot(
                ScheduleRuleInput(s.hours, now, s.zone, overtimeEndAtMs = case.double("ot"), overtimeStartAtMs = case.optDouble("st")),
                salary,
            )
            val timeline = ShiftTimeline(actual.segments, actual.plannedEndAtMs, actual.overtimeEndAtMs)
            val elapsed = timeline.overtimeElapsedMs(now)
            val comparison = timeline.overtimeRateComparison(actual.dailySalary, now)
            val e = case.getValue("expected").jsonObject
            val expectedSegments = e.getValue("segments").jsonArray.map { ShiftSegment(it.jsonObject.double("startAtMs")!!, it.jsonObject.double("endAtMs")!!) }
            val ec = e["comparison"]?.takeIf { it !is JsonNull }?.jsonObject
            val comparisonMatches = if (ec == null) comparison == null else comparison != null &&
                comparison.elapsedOvertimeMs == ec.double("elapsedOvertimeMs") &&
                eq(comparison.unpaidHourlyRate, ec.double("unpaidHourlyRate")) &&
                eq(comparison.unpaidRateDecreasePercent, ec.double("unpaidRateDecreasePercent"))
            val same = actual.segments == expectedSegments && actual.durationMs == e.double("durationMs") &&
                actual.elapsedMs == e.double("elapsedMs") && actual.remainingMs == e.double("remainingMs") &&
                actual.progress == e.double("progress") && eq(actual.payRatio, e.double("payRatio")) &&
                eq(actual.activeBreakEndAtMs, e.optDouble("activeBreakEndAtMs")) &&
                eq(actual.dailySalary, e.optDouble("dailySalary")) && eq(actual.earnedSoFar, e.optDouble("earnedSoFar")) &&
                elapsed == e.double("overtimeElapsedMs") && comparisonMatches && timeline.isValid
            if (!same && failures.size < 5) {
                failures += "${s.id} salary ${case.string("s")} m ${case.double("m")} st ${case["st"]} at $now: expected $e, actual segments ${actual.segments} ratio ${actual.payRatio} elapsed $elapsed"
            }
        }
        assertTrue(cases.size >= 1_000)
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
        val durations = cases.filter { it.getValue("sc").jsonPrimitive.int == 0 && it.getValue("s").jsonPrimitive.int == 0 }
            .map { it.getValue("expected").jsonObject.double("durationMs") }.toSet()
        assertTrue(durations.size > 10)
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
        assertTrue(cases.size >= 500)
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
        overtimeCountedMs = o.optDouble("overtimeCountedMs"),
    )

    private fun segments(e: JsonElement) = e.jsonArray.map {
        val s = it.jsonObject
        ShiftSegment(s.double("startAtMs")!!, s.double("endAtMs")!!)
    }
}
