import Foundation

/// Derived cache of one day's conclusion. Rebuild anytime; never export or
/// sync. Matches 002 §7.
struct DailyWorkSummary: Equatable, Sendable, Identifiable {
    var id: UUID
    var shiftAnchorDate: Date
    var resolvedFrom: DayResolutionLayer
    var scheduleSnapshotID: UUID?
    var resolvedSegments: [NativeShiftSegment]
    var resolvedDurationMs: Int64
    var declaredOvertimeMs: Int64
    var isScheduledWorkday: Bool
    var observationCount: Int
    var firstObservationAt: Date?

    static func derive(
        from resolution: DayResolution,
        observations: [WorkObservation],
        declaredOvertimeMs: Int64 = 0
    ) -> DailyWorkSummary {
        let duration = resolution.segments.reduce(Int64(0)) { partial, segment in
            partial + Int64(segment.endAtMs - segment.startAtMs)
        }
        let first = observations.map(\.occurredAt).min()
        return DailyWorkSummary(
            id: UUID(),
            shiftAnchorDate: resolution.shiftAnchorDate,
            resolvedFrom: resolution.layer,
            scheduleSnapshotID: resolution.snapshotID,
            resolvedSegments: resolution.segments,
            resolvedDurationMs: duration,
            declaredOvertimeMs: declaredOvertimeMs,
            isScheduledWorkday: resolution.isScheduledWorkday,
            observationCount: observations.count,
            firstObservationAt: first
        )
    }
}
