package com.rainif.doneat.ui.onboarding

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import org.junit.Assert.assertEquals
import org.junit.Test

class JourneyClockGeometryTest {
    @Test fun `settled countdown tracks every drag delta without interpolation`() {
        val slot = Rect(24f, 240f, 384f, 298f)
        val morph = JourneyClockMorph(null, slot)
        val scrolled = slot.translate(Offset(0f, -137f))
        assertEquals(scrolled, morph.bounds(scrolled, 1f))
    }

    @Test fun `host morph starts at existing clock and reaches the new slot`() {
        val ready = Rect(24f, 240f, 384f, 298f)
        val widget = Rect(84f, 320f, 324f, 378f)
        val morph = JourneyClockMorph(ready, widget)
        assertEquals(ready, morph.bounds(widget, 0f))
        assertEquals(Rect(54f, 280f, 354f, 338f), morph.bounds(widget, .5f))
        assertEquals(widget, morph.bounds(widget, 1f))
    }

    @Test fun `scroll during morph is applied immediately rather than becoming a new animation target`() {
        val widget = Rect(84f, 320f, 324f, 378f)
        val notification = Rect(40f, 260f, 220f, 318f)
        val morph = JourneyClockMorph(widget, notification)
        val drag = Offset(0f, -93f)
        for (progress in listOf(0f, .25f, .5f, .9f, 1f)) {
            assertEquals(morph.bounds(notification, progress).translate(drag),
                morph.bounds(notification.translate(drag), progress))
        }
    }

    @Test fun `partly hidden slot keeps its full layout geometry and separate clipping viewport`() {
        val slot = Rect(24f, 20f, 384f, 78f)
        val viewport = Rect(0f, 48f, 408f, 700f)
        val anchor = JourneyClockAnchor(JourneyClockHost.READY, slot, viewport)
        val translated = anchor.translated(Offset(0f, -10f))
        assertEquals(58f, translated.bounds.height)
        assertEquals(10f, translated.bounds.top)
        assertEquals(38f, translated.viewport.top)
        assertEquals(translated.bounds, JourneyClockMorph(null, translated.bounds).bounds(translated.bounds, 1f))
    }

    @Test fun `interrupted morph can continue from last displayed geometry`() {
        val ready = Rect(24f, 240f, 384f, 298f)
        val widget = Rect(84f, 320f, 324f, 378f)
        val notification = Rect(40f, 260f, 220f, 318f)
        val current = JourneyClockMorph(ready, widget).bounds(widget, .4f)
        val interrupted = JourneyClockMorph(current, notification)
        assertEquals(current, interrupted.bounds(notification, 0f))
        assertEquals(notification, interrupted.bounds(notification, 1f))
    }
}
