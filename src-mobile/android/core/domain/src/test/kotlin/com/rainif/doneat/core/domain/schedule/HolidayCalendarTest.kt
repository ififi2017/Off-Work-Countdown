package com.rainif.doneat.core.domain.schedule

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class HolidayCalendarTest {
    private fun bundledJson() = File(System.getProperty("owc.holidayTemplates")).readText()

    @Test fun `bundled prediction covers holidays and makeup workdays without changing formal years`() {
        val calendar = HolidayCalendar.parse(bundledJson())
        assertTrue(calendar.covers(2027, "CN"))
        assertTrue(calendar.isEstimated(2027, "CN"))
        assertFalse(calendar.isEstimated(2026, "CN"))
        assertFalse(calendar.isEstimated(2027, "US"))
        assertFalse(calendar.covers(2028, "CN"))
        for (date in listOf(20270101, 20270205, 20270213, 20270405, 20270505, 20270609, 20270915, 20271007)) {
            assertEquals("rest on $date", false, calendar.day(date, "CN")?.isWorkday)
        }
        for (date in listOf(20270131, 20270214, 20270508, 20270926, 20271009)) {
            assertEquals("makeup work on $date", true, calendar.day(date, "CN")?.isWorkday)
        }
    }

    @Test fun `a formal replacement removing metadata keeps coverage and removes prediction state`() {
        val root = Json.parseToJsonElement(bundledJson()).jsonObject
        val regions = root.getValue("regions").jsonObject
        val formalRegions = JsonObject(regions.mapValues { (_, region) -> JsonObject(region.jsonObject - "estimatedYears") })
        val formal = HolidayCalendar.parse(JsonObject(root + ("regions" to formalRegions)).toString())
        assertTrue(formal.covers(2027, "CN"))
        assertFalse(formal.isEstimated(2027, "CN"))
        assertEquals(false, formal.day(20270101, "CN")?.isWorkday)
        assertFalse(HolidayCalendar.EMPTY.isEstimated(2027, "CN"))
    }

    @Test fun `estimated metadata rejects uncovered duplicate and empty years`() {
        fun dataset(years: String) = """{
            "schemaVersion": 1, "datasetVersion": "test", "names": [{"en": "Holiday"}],
            "regions": {"CN": {"coveredFromYear": 2026, "coveredThroughYear": 2027,
                "estimatedYears": $years, "days": [[20270101, 0, 0]]}}
        }"""
        for (years in listOf("[2028]", "[2027,2027]", "[2026]", "[2027.5]", "[\"2027\"]")) {
            assertThrows(HolidayCalendar.InvalidDataset::class.java) { HolidayCalendar.parse(dataset(years)) }
        }
    }
}
