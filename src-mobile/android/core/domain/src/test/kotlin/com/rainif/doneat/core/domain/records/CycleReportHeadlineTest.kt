package com.rainif.doneat.core.domain.records

import org.junit.Assert.*
import org.junit.Test

class CycleReportHeadlineTest {
    private val hour = 3_600_000L
    private val period = CycleReportPeriod(CycleReportKind.WEEK, "2026-09-21", "2026-09-27", "UTC")
    private val report = CycleReportSnapshot(period, emptyList(), CycleReportFigures(5, 40 * hour), 2, 2, 5, false)
    private fun baseline(delta: Int) = CycleReportBaseline(4, 40 * hour, delta * hour)
    @Test fun factualHeadlinesMatchThePinnedIOSRules() {
        assertEquals(CycleReportHeadline.PLAIN, report.headline)
        assertEquals(CycleReportHeadline.IN_PROGRESS, report.copy(isInProgress = true).headline)
        assertEquals(CycleReportHeadline.STEADY, report.copy(baseline = baseline(1)).headline)
        assertEquals(CycleReportHeadline.FULL, report.copy(baseline = baseline(6)).headline)
        assertEquals(CycleReportHeadline.LIGHTER, report.copy(baseline = baseline(-6)).headline)
        assertEquals(CycleReportHeadline.REST, report.copy(restDayCount = 4).headline)
        assertEquals(CycleReportHeadline.FULL, report.copy(figures = report.figures.copy(workedMs = 44 * hour, overtimeMs = 4 * hour)).headline)
    }
    @Test fun nearBreakRequiresActualBaselineIncreaseAndYearsDoNotInventComparisons() {
        val next = CycleReportNextBreak("2026-09-30", java.time.LocalDate.parse("2026-09-30"), 4, 3)
        val r = report.copy(ahead = CycleReportAhead(0, null, null, next, emptyList(), true))
        assertEquals(CycleReportHeadline.PLAIN, r.headline)
        assertEquals(CycleReportHeadline.BREAK_SOON, r.copy(baseline = baseline(3)).headline)
        assertEquals(CycleReportHeadline.STEADY, r.copy(baseline = baseline(0)).headline)
        assertEquals(CycleReportHeadline.PLAIN, r.copy(period = period.copy(kind = CycleReportKind.YEAR), baseline = baseline(3)).headline)
    }
}
