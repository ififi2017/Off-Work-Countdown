import Foundation

/// The 007 timer marks that must project 1:1 onto a `DayOverride`.
///
/// These are the predecessor of a day override, not a second "actual hours"
/// system. Overtime is a `WorkObservation` and is not a mark here.
struct TimerDayMarks: Equatable, Sendable {
    /// Clocked in before the planned start.
    var earlyStartAtMs: Double?
    /// Clocked off before the planned end.
    var earlyOffAtMs: Double?
    /// Rest-day manual timing, keyed on the shift start day.
    var forcedWorkdayDate: String?
    /// Settings kept today's hours while the committed schedule moved.
    var hasTodayOverride: Bool
    /// Unscheduled "start a session" — no `forcedWorkdayDate`.
    var hasUnscheduledSession: Bool
    /// Whether the base snapshot is a workday. A today-only overlay that
    /// leaves today as rest is not a day override.
    var isWorkday: Bool

    var createsOverride: Bool {
        if earlyStartAtMs != nil || earlyOffAtMs != nil { return true }
        if forcedWorkdayDate != nil || hasUnscheduledSession { return true }
        return hasTodayOverride && isWorkday
    }
}

/// Pure mapping from timer marks onto `DayOverride`.
///
/// | Mark | Kind | Segments |
/// |---|---|---|
/// | none | nil | fall through to schedule |
/// | early start | customSegments | first segment starts at the clock-in |
/// | early off | customSegments | last work ends at the clock-off; not leave |
/// | both | customSegments | both bounds |
/// | forced workday | customSegments | planned hours on that rest day |
/// | unscheduled session | customSegments | planned hours for the session |
/// | today overlay on a workday | customSegments | overlay hours already in `plannedSegments` |
/// | today overlay on a rest day | nil | schedule revision, not a day worked |
/// | apply-to-today with no leftover marks | nil | the schedule itself changed |
/// | overtime only | nil | observation, not an override |
enum DayOverrideProjection {
    /// Maps marks onto at most one override for the shift start day.
    static func project(
        marks: TimerDayMarks,
        dayKey: String,
        shiftAnchorDate: Date,
        plannedSegments: [NativeShiftSegment],
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> DayOverride? {
        guard marks.createsOverride else { return nil }
        let segments = applyTimeBounds(
            to: plannedSegments,
            startAtMs: marks.earlyStartAtMs,
            endAtMs: marks.earlyOffAtMs
        )
        return DayOverride(
            dayKey: dayKey,
            shiftAnchorDate: shiftAnchorDate,
            kind: .customSegments,
            segments: segments,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    /// Clips or extends planned fragments. Not a second schedule algorithm:
    /// lunch gaps and overnight splits stay as the rules already drew them.
    static func applyTimeBounds(
        to segments: [NativeShiftSegment],
        startAtMs: Double?,
        endAtMs: Double?
    ) -> [NativeShiftSegment] {
        var result = segments
        // The planned window's own end, captured before clipping. Extending is
        // only correct past that end: an early clock-off that lands inside a
        // lunch gap must still finish work at the gap, not swallow the break.
        let plannedEndAtMs = segments.map(\.endAtMs).max()
        if let startAtMs {
            result = result.compactMap { segment in
                if segment.endAtMs <= startAtMs { return nil }
                if segment.startAtMs < startAtMs {
                    return NativeShiftSegment(startAtMs: startAtMs, endAtMs: segment.endAtMs)
                }
                return segment
            }
            if var first = result.first, first.startAtMs > startAtMs {
                first = NativeShiftSegment(startAtMs: startAtMs, endAtMs: first.endAtMs)
                result[0] = first
            } else if result.isEmpty, let endAtMs, startAtMs < endAtMs {
                result = [NativeShiftSegment(startAtMs: startAtMs, endAtMs: endAtMs)]
            }
        }
        if let endAtMs {
            result = result.compactMap { segment in
                if segment.startAtMs >= endAtMs { return nil }
                if segment.endAtMs > endAtMs {
                    return NativeShiftSegment(startAtMs: segment.startAtMs, endAtMs: endAtMs)
                }
                return segment
            }
            if let plannedEndAtMs, endAtMs > plannedEndAtMs, let last = result.last {
                result[result.count - 1] = NativeShiftSegment(
                    startAtMs: last.startAtMs,
                    endAtMs: endAtMs
                )
            }
        }
        return result
    }
}
