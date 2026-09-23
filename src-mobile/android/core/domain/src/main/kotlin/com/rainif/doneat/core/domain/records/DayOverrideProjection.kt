package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ShiftSegment

/**
 * The timer marks that project one-to-one onto a [DayOverride]: the
 * predecessor of a day override, not a second "actual hours" system. Overtime
 * is an observation, not a mark.
 */
data class TimerDayMarks(
    /** Clocked in before the planned start. */
    val earlyStartAtMs: Double? = null,
    /** Clocked off before the planned end. */
    val earlyOffAtMs: Double? = null,
    /** Rest-day manual timing, keyed on the shift start day. */
    val forcedWorkdayDate: String? = null,
    /** Settings kept today's hours while the committed schedule moved. */
    val hasTodayOverride: Boolean = false,
    /** Unscheduled "start a session". */
    val hasUnscheduledSession: Boolean = false,
    /** Whether the base snapshot is a workday; a today-only overlay on rest is not an override. */
    val isWorkday: Boolean = true,
) {
    val createsOverride: Boolean
        get() = earlyStartAtMs != null || earlyOffAtMs != null || forcedWorkdayDate != null || hasUnscheduledSession ||
            (hasTodayOverride && isWorkday)
}

/** iOS `DayOverrideProjection`: timer marks only ever produce custom segments or nothing. */
object DayOverrideProjection {
    /** At most one override for the shift start day; its stamps are set when it is saved. */
    fun project(marks: TimerDayMarks, dayKey: String, plannedSegments: List<ShiftSegment>, timeZoneIdentifier: String): DayOverride? {
        if (!marks.createsOverride) return null
        return DayOverride(
            dayKey, DayOverrideKind.CUSTOM_SEGMENTS, applyTimeBounds(plannedSegments, marks.earlyStartAtMs, marks.earlyOffAtMs),
            note = null, editedAtMs = 0.0, editCount = 0, editTieBreaker = ZERO_UUID, timeZoneIdentifier = timeZoneIdentifier,
        )
    }

    /**
     * Clips or extends planned fragments. Lunch gaps and overnight splits stay
     * as the rules drew them; only a clock-off past the planned end extends
     * the last fragment, so leaving during lunch never swallows the break.
     */
    fun applyTimeBounds(segments: List<ShiftSegment>, startAtMs: Double?, endAtMs: Double?): List<ShiftSegment> {
        var result = segments
        val plannedEndAtMs = segments.maxOfOrNull { it.endAtMs }
        if (startAtMs != null) {
            result = result.mapNotNull { s ->
                when {
                    s.endAtMs <= startAtMs -> null
                    s.startAtMs < startAtMs -> ShiftSegment(startAtMs, s.endAtMs)
                    else -> s
                }
            }
            val first = result.firstOrNull()
            if (first != null && first.startAtMs > startAtMs) {
                result = listOf(first.copy(startAtMs = startAtMs)) + result.drop(1)
            } else if (result.isEmpty() && endAtMs != null && startAtMs < endAtMs) {
                result = listOf(ShiftSegment(startAtMs, endAtMs))
            }
        }
        if (endAtMs != null) {
            result = result.mapNotNull { s ->
                when {
                    s.startAtMs >= endAtMs -> null
                    s.endAtMs > endAtMs -> ShiftSegment(s.startAtMs, endAtMs)
                    else -> s
                }
            }
            val last = result.lastOrNull()
            if (plannedEndAtMs != null && endAtMs > plannedEndAtMs && last != null) {
                result = result.dropLast(1) + last.copy(endAtMs = endAtMs)
            }
        }
        return result
    }

    internal const val ZERO_UUID = "00000000-0000-0000-0000-000000000000"
}
