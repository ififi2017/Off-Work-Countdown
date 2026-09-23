package com.rainif.doneat.core.domain

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Loads the TypeScript-oracle cases (npm run generate:android-rule-fixtures).
 * T07 onwards evaluates the Kotlin rules against [data]; this only guards the
 * file's shape so a truncated or empty fixture cannot pass as "no failures".
 */
class SharedRuleFixturesTest {
    private val root: JsonObject by lazy {
        val text = checkNotNull(javaClass.getResource("/shared-rule-fixtures.json")) {
            "shared-rule-fixtures.json missing from test resources"
        }.readText()
        Json.parseToJsonElement(text).jsonObject
    }

    private val data get() = root.getValue("data").jsonObject

    @Test
    fun declaresSchemaOne() {
        assertEquals(1, root.getValue("fixtureSchemaVersion").jsonPrimitive.int)
    }

    @Test
    fun everySectionMatchesItsDeclaredCount() {
        val counts = root.getValue("counts").jsonObject
        assertTrue(counts.isNotEmpty())
        counts.forEach { (section, count) ->
            val rows = data.getValue(section) as JsonArray
            assertEquals(section, count.jsonPrimitive.int, rows.size)
            assertTrue("$section is empty", rows.isNotEmpty())
        }
    }

    @Test
    fun coversEverySharedRuleEntryPoint() {
        val required = listOf(
            "snapshots", "watch", "widgetShifts", "expansions", "validateBreak", "reminders",
            "applyToday", "summaries", "recordsIncome", "monthlyEquivalent", "lifetimeIncome", "actualForecast",
        )
        required.forEach { assertTrue("missing $it", data.getValue(it).jsonArray.isNotEmpty()) }
    }
}
