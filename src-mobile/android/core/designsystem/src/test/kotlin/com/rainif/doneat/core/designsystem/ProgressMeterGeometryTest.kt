package com.rainif.doneat.core.designsystem

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

/** The bubble placement from iOS `OWCProgressMeter`, in points: 300 wide, a 60 × 22 bubble, a 12 pt pointer, 14 pt overflow. */
class ProgressMeterGeometryTest {
    private fun place(percent: Double) = ProgressMeterGeometry.place(300f, percent, 60f, 22f, 12f, 14f)

    @Test fun inTheMiddleTheBubbleIsCentredOnThePointer() {
        val p = place(50.0)
        assertEquals(150f, p.targetX, 0.001f)
        assertEquals(120f, p.bubbleX, 0.001f)
    }

    @Test fun atTheEndsThePointerStaysOnTheMarkAndTheBubbleSlides() {
        // 0%: the pointer is at 0; the bubble hangs 14 past the start but may
        // shift at most 30 - (6 + 11) = 13, so its flat edge still meets the pointer.
        val start = place(0.0)
        assertEquals(0f, start.targetX, 0.001f)
        assertEquals(-17f, start.bubbleX, 0.001f)
        val end = place(100.0)
        assertEquals(300f, end.targetX, 0.001f)
        assertEquals(300f - 60f + 17f, end.bubbleX + 0f, 0.001f)
    }

    @Test fun nearTheEdgeTheBubbleShiftsOnlyAsFarAsTheOverflowAllows() {
        // At 5% the target is 15; the centre may go no lower than 30 - 14 = 16, a shift of +1.
        val p = place(5.0)
        assertEquals(15f, p.targetX, 0.001f)
        assertEquals(15f - 30f + 1f, p.bubbleX, 0.001f)
    }

    @Test fun outOfRangeValuesAreClamped() {
        assertEquals(place(100.0), place(140.0))
        assertEquals(place(0.0), place(-3.0))
    }

    @Test fun labelsFollowTheLocale() {
        assertEquals("62.4%", ProgressMeterGeometry.bubbleLabel(62.4, Locale.US))
        assertEquals("100.0%", ProgressMeterGeometry.bubbleLabel(100.0, Locale.US))
        assertEquals("62%", ProgressMeterGeometry.spokenValue(62.4, Locale.US))
        assertEquals("62,4 %", ProgressMeterGeometry.bubbleLabel(62.4, Locale.GERMANY).replace(' ', ' '))
    }
}
