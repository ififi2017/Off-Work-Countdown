package com.rainif.doneat.ui.records

import com.rainif.doneat.core.designsystem.DoneAtReportMotion as Ease
import org.junit.Assert.*
import org.junit.Test

class ReportStripGeometryTest {
    private val calendar = ReportRect(180f, 30f, 42f, 42f)
    private val bar = ReportRect(45f, 25f, 6f, 275f)
    private fun frame(m: Float, r: Float = 1f) = reportStripFrame(calendar, bar, 300f, m, r, 12, 30, false, 26f)
    @Test fun calendarShrinksBeforeTravellingAndBarsGrowAfterLanding() {
        assertEquals(calendar, frame(0f))
        assertEquals(calendar.centerX, frame(.2f).centerX, .001f)
        assertEquals(6f, frame(.2f).height, .001f)
        assertEquals(6f, frame(.4f).height, .001f)
        assertEquals(294f, frame(.64f).y, .001f)
        assertEquals(bar, frame(1f))
    }
    @Test fun bothMorphBoundariesAreContinuous() {
        for (boundary in listOf(.2f, .64f)) {
            val before = frame(boundary - .00001f)
            val after = frame(boundary + .00001f)
            assertEquals(before.centerX, after.centerX, .1f)
            assertEquals(before.centerY, after.centerY, .1f)
            assertEquals(before.height, after.height, .1f)
        }
    }
    @Test fun arrivalHasDiagonalStaggerAndSettlesExactly() {
        assertTrue(Ease.stagger(.35f, 1, 11, .42f) > Ease.stagger(.35f, 8, 11, .42f))
        assertTrue(frame(0f, 0f).centerY > calendar.centerY)
        assertEquals(calendar, frame(0f, 1f))
        assertEquals(0f, Ease.window(-1f, 0f, 1f))
        assertEquals(1f, Ease.outCubic(2f))
    }
}
