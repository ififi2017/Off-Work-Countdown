package com.rainif.doneat.core.domain.schedule

import com.rainif.doneat.core.domain.SharedRuleFixtures
import com.rainif.doneat.core.domain.SharedRuleFixtures.integer
import com.rainif.doneat.core.domain.SharedRuleFixtures.segments
import com.rainif.doneat.core.domain.SharedRuleFixtures.segmentsText
import com.rainif.doneat.core.domain.asDouble
import com.rainif.doneat.core.domain.bool
import com.rainif.doneat.core.domain.double
import com.rainif.doneat.core.domain.string
import kotlinx.serialization.json.JsonArray
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

/**
 * Holds [ScheduleRules] to the TypeScript oracle, case for case with the Swift
 * `ScheduleRuleFixtureTests`. A failure means Kotlin and `lib/` disagree about
 * shared behaviour: decide which is right before regenerating anything.
 */
class ScheduleRuleFixtureTest {
    private val f = SharedRuleFixtures

    @Test
    fun snapshots() {
        val cases = f.section("snapshots")
        val failures = ArrayList<String>()
        for (case in cases) {
            val profile = f.profiles[case.getValue("p").jsonPrimitive.int]
            val input = f.input(profile, case.double("now")!!, case.double("ot"), case.double("forced"))
            val actual = ScheduleRules.snapshot(input, f.salaries[case.getValue("s").jsonPrimitive.int])
            val expected = case.getValue("expected").jsonArray
            val mismatch = compareSnapshot(actual, expected)
            if (mismatch != null && failures.size < 5) failures += "${profile.id} at ${case.double("now")}: $mismatch"
            else if (mismatch != null) failures += ""
        }
        assertTrue("snapshot cases: ${cases.size}", cases.size > 2_000)
        if (failures.isNotEmpty()) fail("${failures.size} snapshot mismatches, first:\n" + failures.filter { it.isNotEmpty() }.joinToString("\n"))
    }

    @Test
    fun widgetShifts() {
        for (case in f.section("widgetShifts")) {
            val profile = f.profiles[case.getValue("p").jsonPrimitive.int]
            val actual = ScheduleRules.widgetShifts(
                f.input(profile, case.double("now")!!, case.double("ot")),
                case.double("through")!!,
                case.getValue("max").jsonPrimitive.int,
            )
            val expected = case.getValue("expected").jsonArray.map { it.jsonObject.toWidgetShift() }
            assertEquals("widget ${profile.id} at ${case.double("now")}", expected, actual)
        }
        for (case in f.section("widgetDigests")) {
            val profile = f.profiles[case.getValue("p").jsonPrimitive.int]
            val shifts = ScheduleRules.widgetShifts(
                f.input(profile, case.double("now")!!),
                case.double("through")!!,
                case.getValue("max").jsonPrimitive.int,
            )
            assertEquals("widget horizon ${profile.id}", case.getValue("count").jsonPrimitive.int, shifts.size)
            assertEquals("widget horizon ${profile.id}", case.string("sha256"), SharedRuleFixtures.sha256(shifts.map(::widgetLine)))
        }
    }

    @Test
    fun expansions() {
        for (case in f.section("expansions")) {
            val profile = f.profiles[case.getValue("p").jsonPrimitive.int]
            val actual = ScheduleRules.expandScheduleRange(profile.hours, case.double("from")!!, case.double("through")!!, profile.zone)
            val expected = case.getValue("expected").jsonArray.map { it.jsonObject.toExpansion() }
            assertEquals("expansion ${profile.id}", expected, actual)
        }
        for (case in f.section("expansionDigests")) {
            val profile = f.profiles[case.getValue("p").jsonPrimitive.int]
            val days = ScheduleRules.expandScheduleRange(profile.hours, case.double("from")!!, case.double("through")!!, profile.zone)
            assertEquals("expansion years ${profile.id}", case.getValue("count").jsonPrimitive.int, days.size)
            assertEquals("expansion years ${profile.id}", case.string("sha256"), SharedRuleFixtures.sha256(days.map(::expansionLine)))
        }
    }

    @Test
    fun breakValidation() {
        val cases = f.section("validateBreak")
        for (case in cases) {
            val profile = f.profiles[case.getValue("p").jsonPrimitive.int]
            val hours = profile.hours.copy(
                breakStartTime = case.string("breakStartTime"),
                breakDurationMinutes = case.getValue("breakDurationMinutes").jsonPrimitive.int,
            )
            val input = f.input(profile, case.double("now")!!, case.double("ot")).copy(hours = hours)
            assertEquals("break ${profile.id} ${hours.breakStartTime}", case.bool("expected"), ScheduleRules.validateBreak(input))
        }
        assertEquals(setOf(true, false), cases.map { it.bool("expected") }.toSet())
    }

    @Test
    fun applyToday() {
        val cases = f.section("applyToday")
        for (case in cases) {
            val profile = f.profiles[case.getValue("p").jsonPrimitive.int]
            val other = f.profiles[case.getValue("c").jsonPrimitive.int]
            val now = case.double("now")!!
            val forced = case.double("forced")
            val current = f.input(profile, now, forcedWorkdayStartMs = forced)
            // Another profile's hours, edited by the same user in the same zone.
            val candidate = f.input(other, now, forcedWorkdayStartMs = forced, zone = profile.zone)
            assertEquals("apply today ${profile.id} → ${other.id} at $now", case.bool("expected"), ScheduleRules.shouldPromptApplyToday(current, candidate))
        }
        assertEquals(setOf(true, false), cases.map { it.bool("expected") }.toSet())
    }

    /** Field-by-field in generator order; doubles compare as IEEE values, so 0 and -0 agree as in Swift. */
    private fun compareSnapshot(actual: ShiftSnapshot, expected: JsonArray): String? {
        val expectedSegments = expected[0].jsonArray.map { pair ->
            val (start, end) = pair.jsonArray.map { it.asDouble()!! }
            ShiftSegment(start, end)
        }
        if (expectedSegments != actual.segments) return "segments ${actual.segments} ≠ $expectedSegments"
        val fields = listOf(
            "startAtMs" to actual.startAtMs, "endAtMs" to actual.endAtMs, "plannedEndAtMs" to actual.plannedEndAtMs,
            "overtimeEndAtMs" to actual.overtimeEndAtMs, "durationMs" to actual.durationMs,
            "plannedDurationMs" to actual.plannedDurationMs, "elapsedMs" to actual.elapsedMs,
            "remainingMs" to actual.remainingMs, "progress" to actual.progress, "payRatio" to actual.payRatio,
            "activeBreakEndAtMs" to actual.activeBreakEndAtMs, "isWorkday" to actual.isWorkday,
            "nextRestAtMs" to actual.nextRestAtMs, "dailySalary" to actual.dailySalary,
            "earnedSoFar" to actual.earnedSoFar, "nextShiftStartAtMs" to actual.nextShiftStartAtMs,
            "nextShiftEndAtMs" to actual.nextShiftEndAtMs, "countdownTargetAtMs" to actual.countdownTargetAtMs,
            "countdownAnchorAtMs" to actual.countdownAnchorAtMs, "countdownProgress" to actual.countdownProgress,
        )
        fields.forEachIndexed { index, (name, value) ->
            val e = expected[index + 1]
            val same = when (value) {
                is Boolean -> e.jsonPrimitive.boolean == value
                is Double -> e.asDouble()?.let { it == value } ?: false
                null -> e.asDouble() == null
                else -> false
            }
            if (!same) return "$name: expected $e, actual $value"
        }
        return null
    }

    private fun JsonObject.toWidgetShift() = WidgetShift(
        segments = segments(getValue("segments")),
        startAtMs = double("startAtMs")!!,
        endAtMs = double("endAtMs")!!,
        plannedEndAtMs = double("plannedEndAtMs")!!,
        overtimeEndAtMs = double("overtimeEndAtMs"),
        durationMs = double("durationMs")!!,
        countdownAnchorAtMs = double("countdownAnchorAtMs")!!,
    )

    private fun JsonObject.toExpansion() = ScheduleDayExpansion(
        dayKey = string("dayKey")!!,
        shiftAnchorStartAtMs = double("shiftAnchorStartAtMs")!!,
        isWorkday = bool("isWorkday"),
        segments = segments(getValue("segments")),
    )

    // Must write exactly what `expansionLine` / `widgetLine` in the generator write.
    private fun expansionLine(day: ScheduleDayExpansion) =
        "${day.dayKey}|${integer(day.shiftAnchorStartAtMs)}|${if (day.isWorkday) 1 else 0}|${segmentsText(day.segments)}\n"

    private fun widgetLine(s: WidgetShift): String {
        val overtime = s.overtimeEndAtMs?.let(::integer) ?: ""
        return "${segmentsText(s.segments)}|${integer(s.startAtMs)}|${integer(s.endAtMs)}|${integer(s.plannedEndAtMs)}|" +
            "$overtime|${integer(s.durationMs)}|${integer(s.countdownAnchorAtMs)}\n"
    }
}
