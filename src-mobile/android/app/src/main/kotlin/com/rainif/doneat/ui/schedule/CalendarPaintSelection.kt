package com.rainif.doneat.ui.schedule

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import com.rainif.doneat.core.domain.session.RosterDayEdit
import java.util.UUID

/** Draft-only brush undo. Each day toggles once per stroke, even if the finger doubles back. */
internal class CalendarPaintSelection(val brushID: UUID) {
    private val originals = mutableMapOf<String, RosterDayEdit>()
    private val visited = mutableSetOf<String>()

    fun endStroke() = visited.clear()

    fun edit(key: String, currentShiftID: UUID?): RosterDayEdit? {
        if (!visited.add(key)) return null
        if (currentShiftID == brushID) return originals.remove(key) ?: RosterDayEdit.FollowPattern
        originals[key] = currentShiftID?.let { RosterDayEdit.Shift(it) } ?: RosterDayEdit.FollowPattern
        return RosterDayEdit.Shift(brushID)
    }
}

/** Include cells crossed between pointer samples; gutters and weekday headings are excluded. */
internal fun crossedCalendarDays(start: Offset, end: Offset, frames: Map<String, Rect>): List<String> =
    frames.mapNotNull { (key, frame) ->
        var entry = 0f
        var exit = 1f
        for ((origin, delta, lower, upper) in listOf(
            listOf(start.x, end.x - start.x, frame.left, frame.right),
            listOf(start.y, end.y - start.y, frame.top, frame.bottom),
        )) {
            if (delta == 0f) {
                if (origin < lower || origin > upper) return@mapNotNull null
            } else {
                val first = (lower - origin) / delta
                val last = (upper - origin) / delta
                entry = maxOf(entry, minOf(first, last))
                exit = minOf(exit, maxOf(first, last))
                if (entry > exit) return@mapNotNull null
            }
        }
        key to entry
    }.sortedWith(compareBy({ it.second }, { it.first })).map { it.first }
