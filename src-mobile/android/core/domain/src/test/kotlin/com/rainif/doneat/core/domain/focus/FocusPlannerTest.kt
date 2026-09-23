package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.FocusTask
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.FocusTimerSettings
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pure cases of iOS `FocusPlannerTests` (the Live Activity ones are iOS-only), plus the identity vectors. */
class FocusPlannerTest {
    private val morning = ShiftSegment(1_787_557_200_000.0, 1_787_568_000_000.0) // 09:00–12:00
    private val afternoon = ShiftSegment(1_787_571_600_000.0, 1_787_586_000_000.0) // 13:00–17:00

    private fun task(title: String, pomodoros: Int, id: String = "00000000-0000-0000-0000-000000000009", sortIndex: Int = 0) = FocusTask(
        id, 0.0, null, null, title, pomodoros, FocusTaskIcon.FOCUS, false, null, null, sortIndex, 0.0, 1, id, null, null,
    )

    @Test fun identityVectorsMatchTheSpecification() {
        val block = FocusSessionIdentity.block("00000000-0000-0000-0000-000000000001", 1_789_981_200_000, 1_789_982_700_000)
        assertEquals("4a2cc914-0d4e-59f8-8710-87228d9a15a5".uppercase(), block)
        assertEquals("7f78eeba-9e3f-5cc3-9cbe-efa2f29b6854".uppercase(), FocusSessionIdentity.recovery(block, com.rainif.doneat.core.domain.records.FocusSessionKind.SHORT_BREAK))
        assertEquals("the seed lower-cases the id", block, FocusSessionIdentity.block("00000000-0000-0000-0000-000000000001".uppercase(), 1_789_981_200_000, 1_789_982_700_000))
    }

    @Test fun focusStopsAtLunchGap() {
        assertEquals(1_787_568_000_000.0, FocusPlanner.plannedEnd(1_787_566_800_000.0, listOf(morning, afternoon), null), 0.0)
    }

    @Test fun focusOverflowIsExplicit() {
        val (fits, overflow) = FocusPlanner.remainingPomodoros(listOf(task("Deep work", 4)), 25 * 60_000)
        assertTrue(fits.isEmpty())
        assertEquals(listOf("Deep work"), overflow.map { it.title })
    }

    @Test fun focusOverflowUsesRemainingBlocks() {
        val (fits, overflow) = FocusPlanner.remainingPomodoros(listOf(task("Deep work", 4)), 25 * 60_000, completedBlocks = { 3 })
        assertEquals(listOf("Deep work"), fits.map { it.title })
        assertTrue(overflow.isEmpty())
    }

    @Test fun focusOrderUsesIndexThenID() {
        val a = task("A", 1, id = "00000000-0000-0000-0000-000000000002", sortIndex = 1)
        val b = task("B", 1, id = "00000000-0000-0000-0000-000000000001", sortIndex = 1)
        assertEquals(listOf("B", "A"), FocusPlanner.sortedTasks(listOf(a, b)).map { it.title })
    }

    @Test fun focusStartsOnlyInsideWork() {
        val segments = listOf(morning, afternoon)
        assertFalse(FocusPlanner.isInsideWork(1_787_557_200_000.0 - 600_000, segments, null))
        assertFalse(FocusPlanner.isInsideWork(1_787_568_000_000.0 + 60_000, segments, null))
        assertTrue(FocusPlanner.isInsideWork(1_787_557_200_000.0 + 60_000, segments, null))
        assertTrue(FocusPlanner.isInsideWork(1_787_586_000_000.0 + 60_000, segments, 1_787_586_000_000.0 + 3_600_000))
    }

    @Test fun focusBlocksPreserveConfiguredLunchGap() {
        val morningStart = 1_788_143_400_000.0
        val morningEnd = morningStart + 2.5 * 3_600_000
        val afternoonStart = morningEnd + 90 * 60_000
        val blocks = FocusPlanner.workBlocks(listOf(ShiftSegment(morningStart, morningEnd), ShiftSegment(afternoonStart, afternoonStart + 5 * 3_600_000)))
        val morningLast = blocks.last { it.endAtMs <= morningEnd }
        val afternoonFirst = blocks.first { it.startAtMs.toDouble() == afternoonStart }
        assertTrue(afternoonFirst.startAtMs - morningLast.endAtMs >= 90 * 60_000)
    }

    @Test fun planningTimelineUsesPomodoroCycleDurations() {
        val start = 1_788_143_400_000.0
        val blocks = FocusPlanner.workBlocks(listOf(ShiftSegment(start, start + 200 * 60_000)))
        val t = FocusPlanBlockKind.TASK
        val b = FocusPlanBlockKind.BREAK_TIME
        assertEquals(listOf(t, b, t, b, t, b, t, b), blocks.take(8).map { it.kind })
        assertEquals(listOf(5, 5, 5, 15), listOf(1, 3, 5, 7).map { blocks[it].durationMinutes })
    }

    @Test fun focusTimerSettingsClampToSupportedRanges() {
        assertEquals(FocusTimerSettings(10, 15, 5, 6), FocusTimerSettings(2, 20, 2, 9).normalized)
    }

    @Test fun configuredFocusDurationIsUsedEverywhere() {
        val start = 1_787_557_200_000.0
        val settings = FocusTimerSettings(60, 5, 15, 4)
        val blocks = FocusPlanner.workBlocks(listOf(ShiftSegment(start, 1_787_561_100_000.0)), settings)
        assertEquals(1, blocks.count { it.kind == FocusPlanBlockKind.TASK })
        assertEquals(1, blocks.count { it.kind == FocusPlanBlockKind.BREAK_TIME })
        val cut = FocusPlanner.plannedEnd(start, listOf(ShiftSegment(start, 1_787_559_000_000.0)), null, 60)
        assertEquals(FocusEndReason.STOPPED_AT_BOUNDARY, FocusPlanner.endReason(start, cut, 60))
    }

    @Test fun onlyShiftBoundariesTruncateFocus() {
        val start = 1_787_557_200_000.0
        val end = FocusPlanner.plannedEnd(start, listOf(ShiftSegment(start, 1_787_560_800_000.0)), null, 25)
        assertEquals(start + 25 * 60_000, end, 0.0)
        assertEquals(FocusEndReason.COMPLETED, FocusPlanner.endReason(start, end, 25))
    }

    @Test fun boundaryRejectsSubMinuteStart() {
        val start = 1_787_557_200_000.0
        assertTrue(FocusPlanner.plannedEnd(start, listOf(ShiftSegment(start, 1_787_557_259_000.0)), null) - start < 60_000)
    }

    @Test fun workBlocksDoNotDependOnTheClock() {
        val blocks = FocusPlanner.workBlocks(listOf(morning))
        assertEquals(blocks, FocusPlanner.workBlocks(listOf(morning)))
        val origin = 1_787_557_200_000L
        assertEquals(listOf(0, 30, 60, 90, 130).map { origin + it * 60_000L }, blocks.filter { it.kind == FocusPlanBlockKind.TASK }.map { it.startAtMs })
    }

    @Test fun overtimeExtendsOnlyTheLastSegment() {
        val start = 1_787_585_000_000.0 // 16:43, 16:40 clock-off + overtime to 18:00
        assertEquals(start + 25 * 60_000, FocusPlanner.plannedEnd(start, listOf(morning, afternoon), 1_787_593_200_000.0), 0.0)
        val beforeLunch = 1_787_567_000_000.0
        assertEquals("lunch still stops a morning block", morning.endAtMs, FocusPlanner.plannedEnd(beforeLunch, listOf(morning, afternoon), 1_787_593_200_000.0), 0.0)
    }
}
