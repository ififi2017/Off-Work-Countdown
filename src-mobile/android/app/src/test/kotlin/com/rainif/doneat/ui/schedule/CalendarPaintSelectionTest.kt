package com.rainif.doneat.ui.schedule

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import com.rainif.doneat.core.domain.session.RosterDayEdit
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class CalendarPaintSelectionTest {
    private val brush = UUID.randomUUID()

    @Test fun togglesOncePerStrokeAndRestoresPriorShift() {
        val prior = UUID.randomUUID()
        val selection = CalendarPaintSelection(brush)
        assertEquals(RosterDayEdit.Shift(brush), selection.edit("2026-10-01", prior))
        assertNull(selection.edit("2026-10-01", brush))
        selection.endStroke()
        assertEquals(RosterDayEdit.Shift(prior), selection.edit("2026-10-01", brush))
    }

    @Test fun clearsPreviouslyUnassignedOrExistingBrushDay() {
        val selection = CalendarPaintSelection(brush)
        assertEquals(RosterDayEdit.Shift(brush), selection.edit("2026-10-01", null))
        selection.endStroke()
        assertEquals(RosterDayEdit.FollowPattern, selection.edit("2026-10-01", brush))
        assertEquals(RosterDayEdit.FollowPattern, selection.edit("2026-10-02", brush))
    }

    @Test fun fastStrokeIncludesSkippedCellsInBothDirections() {
        val cells = mapOf("a" to Rect(0f, 0f, 10f, 10f), "b" to Rect(12f, 0f, 22f, 10f), "c" to Rect(24f, 0f, 34f, 10f))
        assertEquals(listOf("a", "b", "c"), crossedCalendarDays(Offset(5f, 5f), Offset(30f, 5f), cells))
        assertEquals(listOf("c", "b", "a"), crossedCalendarDays(Offset(30f, 5f), Offset(5f, 5f), cells))
        assertTrue(crossedCalendarDays(Offset(11f, 0f), Offset(11f, 10f), cells).isEmpty())
    }

    @Test fun diagonalStrokeIncludesOnlyIntersectedCells() {
        val cells = mapOf("a" to Rect(0f, 0f, 10f, 10f), "b" to Rect(12f, 0f, 22f, 10f), "c" to Rect(12f, 12f, 22f, 22f))
        assertEquals(listOf("a", "c"), crossedCalendarDays(Offset(5f, 5f), Offset(18f, 18f), cells))
    }
}
