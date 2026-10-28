package com.rainif.doneat.ui.onboarding

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect

internal enum class JourneyClockHost { READY, WIDGET, NOTIFICATION }

internal data class JourneyClockAnchor(val host: JourneyClockHost, val bounds: Rect, val viewport: Rect) {
    fun translated(offset: Offset) = copy(bounds = bounds.translate(offset), viewport = viewport.translate(offset))
}

/** A host change contributes a decaying correction; scroll geometry stays direct. */
internal class JourneyClockMorph(from: Rect?, destination: Rect) {
    private val correction = (from ?: destination).let {
        Rect(it.left - destination.left, it.top - destination.top,
            it.right - destination.right, it.bottom - destination.bottom)
    }

    fun bounds(destination: Rect, progress: Float): Rect {
        val remaining = 1f - progress.coerceIn(0f, 1f)
        return Rect(destination.left + correction.left * remaining, destination.top + correction.top * remaining,
            destination.right + correction.right * remaining, destination.bottom + correction.bottom * remaining)
    }
}
