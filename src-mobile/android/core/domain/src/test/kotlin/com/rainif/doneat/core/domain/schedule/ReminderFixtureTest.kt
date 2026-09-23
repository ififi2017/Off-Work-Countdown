package com.rainif.doneat.core.domain.schedule

import com.rainif.doneat.core.domain.SharedRuleFixtures
import com.rainif.doneat.core.domain.bool
import com.rainif.doneat.core.domain.double
import com.rainif.doneat.core.domain.string
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Holds [ScheduleRules.reminders] to `lib/reminders.ts`, case for case with the
 * Swift `ScheduleRuleFixtureTests`: every list by digest, the short ones also
 * row by row.
 */
class ReminderFixtureTest {
    private val f = SharedRuleFixtures
    private val percents = listOf(50, 75, 90, 95, 100)

    private val inputs: List<ReminderInputs> by lazy {
        f.section("reminderInputs").map { o ->
            val titles = o.getValue("milestoneTitles").jsonObject
            val messages = o.getValue("milestoneMessages").jsonObject
            ReminderInputs(
                mode = o.string("mode")!!,
                fallbackTitle = o.string("fallbackTitle")!!,
                breakTitle = o.string("breakTitle")!!,
                milestoneTitles = percents.associateWith { titles.getValue("milestone$it").jsonPrimitive.content },
                milestoneMessages = percents.associateWith { p -> messages.getValue("milestone$p").jsonArray.map { it.jsonPrimitive.content } },
                lunchStartEnabled = o.bool("lunchStartEnabled"),
                lunchStartBody = o.string("lunchStartBody")!!,
                lunchEndEnabled = o.bool("lunchEndEnabled"),
                lunchEndBody = o.string("lunchEndBody")!!,
                microBreakEnabled = o.bool("microBreakEnabled"),
                microBreakTitle = o.string("microBreakTitle")!!,
                microBreakIntervalMinutes = o.getValue("microBreakIntervalMinutes").jsonPrimitive.int,
                microBreakMessages = o.getValue("microBreakMessages").jsonArray.map { it.jsonPrimitive.content },
                cycleEndSummaryBody = (o["cycleEndSummaryBody"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it !is JsonNull }?.content,
            )
        }
    }

    private fun line(r: Reminder): String {
        fun number(v: Double?) = v?.let(ReminderRules::jsString).orEmpty()
        return listOf(r.id, r.kind.raw, number(r.atMs), number(r.expiresAtMs), number(r.maxTickGapMs), r.collapseGroup.orEmpty(), r.title ?: "∅", r.body ?: "∅")
            .joinToString("|") + "\n"
    }

    @Test
    fun remindersMatchTheOracle() {
        val cases = f.section("reminders")
        var rowChecked = 0
        for (case in cases) {
            val profile = f.profiles[case.getValue("p").jsonPrimitive.int]
            val now = case.double("now")!!
            val list = ScheduleRules.reminders(
                f.input(profile, now, case.double("ot"), case.double("forced")),
                inputs[case.getValue("v").jsonPrimitive.int],
            )
            val label = "${profile.id} at $now v${case.getValue("v")} ot ${case.double("ot")}"
            case["expected"]?.jsonArray?.let { rows ->
                assertEquals(label, rows.map { row -> row.jsonArray.map { (it as? kotlinx.serialization.json.JsonPrimitive)?.let(::cell) } }, list.map(::row))
                rowChecked++
            }
            assertEquals("count $label", case.getValue("count").jsonPrimitive.int, list.size)
            assertEquals("digest $label", case.string("sha256"), SharedRuleFixtures.sha256(list.map(::line)))
        }
        assertEquals(320, cases.size)
        assertTrue("row-by-row cases: $rowChecked", rowChecked > 50)
    }

    private fun cell(p: kotlinx.serialization.json.JsonPrimitive): Any? = when {
        p is JsonNull -> null
        p.isString -> p.contentOrNull
        else -> p.doubleOrNull
    }

    private fun row(r: Reminder): List<Any?> = listOf(r.id, r.kind.raw, r.atMs, r.expiresAtMs, r.maxTickGapMs, r.collapseGroup, r.title, r.body)

    @Test
    fun jsNumberStringsMatchJavaScript() {
        assertEquals("1772668800000", ReminderRules.jsString(1_772_668_800_000.0))
        assertEquals("1772668800000.25", ReminderRules.jsString(1_772_668_800_000.25))
        assertEquals("120000", ReminderRules.jsString(120_000.0))
    }

}
