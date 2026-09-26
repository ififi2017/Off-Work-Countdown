package com.rainif.doneat.ui.records

import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import org.junit.Assert.assertEquals
import org.junit.Test

class RecordsCalloutTest {
    @Test fun selectionFollowsItsCellAndAvoidsChartEdges() {
        val chart = IntSize(360, 240)
        val label = IntSize(140, 60)
        assertEquals(IntOffset(120, 52), recordsCalloutOffset(Rect(180f, 120f, 200f, 140f), label, chart, 8))
        assertEquals(IntOffset(8, 28), recordsCalloutOffset(Rect(0f, 0f, 20f, 20f), label, chart, 8))
        assertEquals(IntOffset(212, 152), recordsCalloutOffset(Rect(340f, 220f, 360f, 240f), label, chart, 8))
        // Large text keeps the entire label inside the same insets.
        assertEquals(IntOffset(8, 52), recordsCalloutOffset(Rect(340f, 20f, 360f, 44f), IntSize(344, 180), chart, 8))
    }
}
