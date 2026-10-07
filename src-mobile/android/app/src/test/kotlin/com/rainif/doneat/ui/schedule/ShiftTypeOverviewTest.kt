package com.rainif.doneat.ui.schedule

import com.rainif.doneat.core.domain.schedule.*
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class ShiftTypeOverviewTest {
    private fun type(name: String, range: AnnualShiftDateRange? = null, kind: ShiftType.Kind = ShiftType.Kind.WORK) =
        ShiftType(UUID.randomUUID(), name, kind, 540, 1020, false, 720, 30, "#FF8800", false, range)

    @Test fun summarizesSeasonalWorkAndLeavesRestDaysUntouched() {
        val winter = type("winter", AnnualShiftDateRange(10, 1, 4, 30))
        val summer = type("summer", AnnualShiftDateRange(5, 1, 9, 30))
        val rest = type("rest", kind = ShiftType.Kind.REST)
        val from = "2026-09-30"
        val rule = ShiftCycleRule(ShiftCycleRule.Preset.WEEKLY, from,
            listOf(winter.id, winter.id, winter.id, rest.id, rest.id, winter.id, winter.id))
        val coverage = shiftDateCoverage(ExtendedSchedulePlan(listOf(winter, summer, rest), rule, emptyMap()), from)
        assertEquals("2026-09-30", coverage[summer.id]?.first)
        assertEquals("2027-09-29", coverage[summer.id]?.last)
        assertEquals("2026-10-01", coverage[winter.id]?.first)
        assertEquals("2027-04-30", coverage[winter.id]?.last)
        assertEquals(365, coverage.values.sumOf { it.count })
        assertEquals(104, coverage[rest.id]?.count)
    }

    @Test fun leapYearWindowAndExplicitAssignmentMatchResolver() {
        val base = type("base")
        val assigned = type("assigned")
        val plan = ExtendedSchedulePlan(listOf(base, assigned), ShiftCycleRule(ShiftCycleRule.Preset.CUSTOM, "2024-02-29", listOf(base.id)),
            mapOf("2024-03-01" to assigned.id))
        val coverage = shiftDateCoverage(plan, "2024-02-29")
        assertEquals(365, coverage.values.sumOf { it.count })
        assertEquals(ShiftDateCoverage("2024-03-01", "2024-03-01", 1), coverage[assigned.id])
        assertEquals("2025-02-27", coverage[base.id]?.last)
    }

    @Test fun predictedWarningsFollowThePreviewWindowAndSelectedRegion() {
        val calendar = HolidayCalendar.parse("""{
            "schemaVersion": 1, "datasetVersion": "test", "names": [{"en": "New Year"}],
            "regions": {"CN": {"coveredFromYear": 2026, "coveredThroughYear": 2027,
                "estimatedYears": [2027], "days": [[20270101, 0, 0]]}}
        }""")
        assertEquals(listOf(2027), estimatedCoverageYears(calendar, "CN", "2026-10-07"))
        assertEquals(listOf(2027), estimatedCoverageYears(calendar, "CN", "2027-01-01"))
        assertTrue(estimatedCoverageYears(calendar, "CN", "2026-01-01").isEmpty())
        assertTrue(estimatedCoverageYears(calendar, "US", "2026-10-07").isEmpty())
        assertTrue(estimatedCoverageYears(calendar, null, "2026-10-07").isEmpty())
    }
}
