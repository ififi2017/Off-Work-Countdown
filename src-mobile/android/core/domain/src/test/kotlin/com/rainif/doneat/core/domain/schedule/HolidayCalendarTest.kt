package com.rainif.doneat.core.domain.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class HolidayCalendarTest {
    private fun bundledJson() = File(System.getProperty("owc.holidayTemplates")).readText()

    @Test fun `bundled official calendar covers holidays and makeup workdays without estimates`() {
        val calendar = HolidayCalendar.parse(bundledJson())
        assertTrue(calendar.covers(2027, "CN"))
        assertFalse(calendar.isEstimated(2027, "CN"))
        assertFalse(calendar.isEstimated(2026, "CN"))
        assertFalse(calendar.isEstimated(2027, "US"))
        assertFalse(calendar.covers(2028, "CN"))
        val restDates = (20270101..20270103).toList() + (20270205..20270213).toList() +
            (20270403..20270405).toList() + (20270501..20270505).toList() +
            listOf(20270609, 20270915) + (20271001..20271007).toList()
        val makeupDates = listOf(20270131, 20270214, 20270508, 20270926, 20271009)
        val expected = restDates.associateWith { false } + makeupDates.associateWith { true }
        assertEquals(29, restDates.size)
        assertEquals(5, makeupDates.size)
        assertEquals(34, expected.size)
        assertEquals(expected, calendar.workdayOverrides("CN").filterKeys { it / 10000 == 2027 })
        assertEquals(false, calendar.day(20260101, "CN")?.isWorkday)
        assertEquals(true, calendar.day(20260104, "CN")?.isWorkday)
        assertEquals("建国記念の日", calendar.day(20260211, "JP")?.names?.get("ja"))
    }

    @Test fun `a synthetic formal replacement clears explicit prediction metadata`() {
        val predictedJson = """{
            "schemaVersion": 1, "datasetVersion": "test", "names": [{"en": "Holiday"}],
            "regions": {"CN": {"coveredFromYear": 2027, "coveredThroughYear": 2027,
                "estimatedYears": [2027], "days": [[20270101, 0, 0], [20270131, 1, 0]]}}
        }"""
        val predicted = HolidayCalendar.parse(predictedJson)
        val formal = HolidayCalendar.parse(predictedJson.replace("\"estimatedYears\": [2027], ", ""))
        assertTrue(predicted.isEstimated(2027, "CN"))
        assertTrue(formal.covers(2027, "CN"))
        assertFalse(formal.isEstimated(2027, "CN"))
        assertEquals(predicted.workdayOverrides("CN"), formal.workdayOverrides("CN"))
        assertEquals(false, formal.day(20270101, "CN")?.isWorkday)
        assertEquals(true, formal.day(20270131, "CN")?.isWorkday)
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
