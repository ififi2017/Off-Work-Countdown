package com.rainif.doneat.core.domain.records

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** iOS `RecordsMetricsTests`' collapsed-year cases, and the grid's selection rows. */
class RecordsYearSamplerTest {
    private val hour = 3_600_000L

    private fun cell(day: String, appearance: RecordsDayAppearance, workHours: Long = 0, overtimeHours: Long = 0, isProjection: Boolean = false, isFuture: Boolean = false) =
        RecordsDayCell(day, LocalDate.parse(day), appearance, workHours * hour, overtimeHours * hour, 0, 0, 0, false, isFuture, isProjection, false)

    @Test fun historicalProjectionsAreDrawnAsEstimatedWork() {
        val bucket = RecordsYearSampler.buckets(
            LocalDate.parse("2026-03-01"), LocalDate.parse("2026-04-01"), 1,
            listOf(cell("2026-03-02", RecordsDayAppearance.UNRECORDED, workHours = 8, isProjection = true)),
        ).single()
        assertEquals(RecordsDayAppearance.PLANNED, bucket.kind)
        assertTrue(bucket.isProjection)
        assertTrue(bucket.hasEstimatedWork)
        assertEquals(8 * hour, bucket.workMs)
    }

    @Test fun hatchingMarksOnlyEstimatedWork() {
        val cells = listOf(
            cell("2026-03-01", RecordsDayAppearance.RECORDED, workHours = 8),
            cell("2026-03-02", RecordsDayAppearance.PLANNED, workHours = 8),
            cell("2026-03-03", RecordsDayAppearance.UNRECORDED, isProjection = true),
            cell("2026-03-04", RecordsDayAppearance.UNRECORDED, overtimeHours = 2, isProjection = true),
            cell("2026-03-05", RecordsDayAppearance.PLANNED),
        )
        val buckets = RecordsYearSampler.buckets(LocalDate.parse("2026-03-01"), LocalDate.parse("2026-03-06"), 5, cells)
        assertEquals(listOf(false, true, false, true, false), buckets.map { it.hasEstimatedWork })
    }

    @Test fun depthUsesTheBusiestRecordedDayAndNeverFutureWork() {
        val cells = listOf(
            cell("2026-03-01", RecordsDayAppearance.RECORDED, workHours = 12),
            cell("2026-03-02", RecordsDayAppearance.RECORDED, workHours = 8, overtimeHours = 2),
            cell("2026-03-03", RecordsDayAppearance.CORRECTED, workHours = 8, overtimeHours = 1),
        )
        val start = LocalDate.parse("2026-03-01")
        val end = LocalDate.parse("2026-03-04")
        assertEquals(listOf(0L, 2 * hour, hour), RecordsYearSampler.buckets(start, end, 3, cells).map { it.peakOvertimeMs })
        assertEquals(2 * hour, RecordsYearSampler.buckets(start, end, 1, cells).single().peakOvertimeMs)
        val future = RecordsYearSampler.buckets(start, end, 1, listOf(cells[1].copy(isFuture = true, appearance = RecordsDayAppearance.CORRECTED))).single()
        assertTrue(future.isFuture)
        assertTrue(future.hasEstimatedWork)
        assertEquals(0L, future.peakOvertimeMs)
    }

    @Test fun aSelectionBecomesOneBlockPerRow() {
        val grid = RecordsCanvasGrid(width = 160f, height = 80f, targetCell = 12f, gap = 3f, minimumColumns = 10, minimumRows = 5)
        assertEquals(10, grid.columns)
        assertEquals(listOf(8 to 9, 10 to 12, 20 to 20), grid.selectionRows(listOf(12, 8, 9, 10, 11, 20)))
        assertEquals(0, grid.index(1f, 1f))
        assertEquals(grid.columns + 1, grid.index(grid.cell + grid.gap + 1f, grid.cell + grid.gap + 1f))
    }
}
