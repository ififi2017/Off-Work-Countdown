package com.rainif.doneat.core.designsystem

import org.junit.Assert.assertEquals
import org.junit.Test

class GlassNavigationTest {
    @Test fun dragCoordinatesMatchVisualTabsAndClampAtBothEnds() {
        // Four centres remain selectable in either direction, at any measured width.
        for (width in listOf(400, 1080)) {
            for (index in 0..3) {
                val x = width * (index + 0.5f) / 4
                assertEquals(index.toFloat(), glassTabPosition(x, width, 4, false), 0.001f)
                assertEquals((3 - index).toFloat(), glassTabPosition(x, width, 4, true), 0.001f)
            }
            assertEquals(0f, glassTabPosition(-100f, width, 4, false), 0f)
            assertEquals(3f, glassTabPosition(width + 100f, width, 4, false), 0f)
            assertEquals(3f, glassTabPosition(-100f, width, 4, true), 0f)
            assertEquals(0f, glassTabPosition(width + 100f, width, 4, true), 0f)
        }
        assertEquals(0f, glassTabPosition(100f, 0, 4, false), 0f)
        assertEquals(0f, glassTabPosition(100f, 400, 1, true), 0f)
    }
}
