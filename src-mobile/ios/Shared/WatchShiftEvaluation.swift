import Foundation

nonisolated enum WatchShiftPhase: String, Codable, Equatable, Sendable {
    case before
    case working
    case resting
    case overtime
    case finished
}

nonisolated struct WatchShiftEvaluation: Equatable, Sendable {
    let phase: WatchShiftPhase
    let totalMs: Int64
    let elapsedMs: Int64
    let remainingMs: Int64
    let progress: Double
    let nextBoundaryAtMs: Int64?
}

nonisolated enum WatchShiftEvaluator {
    /// Evaluates only the absolute segments prepared by the shared TypeScript rules.
    /// It never derives a schedule, lunch boundary, overtime declaration, or future shift.
    static func evaluate(_ shift: WatchShiftProjectionV1, nowMs: Int64) -> WatchShiftEvaluation? {
        guard nowMs >= 0, nowMs <= WatchSnapshotContract.maximumJSONTimestamp,
              !shift.segments.isEmpty,
              shift.plannedEndAtMs > 0,
              shift.plannedEndAtMs <= WatchSnapshotContract.maximumJSONTimestamp,
              shift.overtimeEndAtMs.map({ $0 > shift.plannedEndAtMs && $0 <= WatchSnapshotContract.maximumJSONTimestamp }) ?? true,
              shift.finishedAtMs.map({ $0 >= shift.segments[0].startAtMs && $0 <= (shift.overtimeEndAtMs ?? shift.plannedEndAtMs) }) ?? true else { return nil }

        let evaluationAtMs = min(nowMs, shift.finishedAtMs ?? nowMs)
        var total: Int64 = 0
        var elapsed: Int64 = 0
        var previousEnd: Int64?
        for segment in shift.segments {
            guard segment.startAtMs >= 0, segment.startAtMs < segment.endAtMs,
                  segment.endAtMs <= WatchSnapshotContract.maximumJSONTimestamp,
                  previousEnd.map({ $0 <= segment.startAtMs }) ?? true else { return nil }
            let (duration, durationOverflow) = segment.endAtMs.subtractingReportingOverflow(segment.startAtMs)
            let (newTotal, totalOverflow) = total.addingReportingOverflow(duration)
            guard !durationOverflow, !totalOverflow else { return nil }
            total = newTotal

            let segmentElapsed: Int64
            if evaluationAtMs <= segment.startAtMs {
                segmentElapsed = 0
            } else if evaluationAtMs >= segment.endAtMs {
                segmentElapsed = duration
            } else {
                let (value, overflow) = evaluationAtMs.subtractingReportingOverflow(segment.startAtMs)
                guard !overflow else { return nil }
                segmentElapsed = value
            }
            let (newElapsed, elapsedOverflow) = elapsed.addingReportingOverflow(segmentElapsed)
            guard !elapsedOverflow else { return nil }
            elapsed = newElapsed
            previousEnd = segment.endAtMs
        }

        let endAtMs = shift.overtimeEndAtMs ?? shift.plannedEndAtMs
        guard total > 0, shift.plannedEndAtMs > shift.segments[0].startAtMs,
              shift.plannedEndAtMs > shift.segments[shift.segments.count - 1].startAtMs,
              shift.plannedEndAtMs <= endAtMs, previousEnd == endAtMs else { return nil }

        let phase: WatchShiftPhase
        let nextBoundaryAtMs: Int64?
        if let finishedAtMs = shift.finishedAtMs, nowMs >= finishedAtMs {
            phase = .finished
            nextBoundaryAtMs = nil
        } else if nowMs < shift.segments[0].startAtMs {
            phase = .before
            nextBoundaryAtMs = shift.segments[0].startAtMs
        } else if nowMs >= endAtMs {
            phase = .finished
            nextBoundaryAtMs = nil
        } else if let segment = shift.segments.first(where: { nowMs >= $0.startAtMs && nowMs < $0.endAtMs }) {
            phase = shift.overtimeEndAtMs != nil && nowMs >= shift.plannedEndAtMs ? .overtime : .working
            nextBoundaryAtMs = shift.overtimeEndAtMs != nil && nowMs < shift.plannedEndAtMs
                ? min(segment.endAtMs, shift.plannedEndAtMs)
                : segment.endAtMs
        } else if let next = shift.segments.first(where: { nowMs < $0.startAtMs }) {
            phase = .resting
            nextBoundaryAtMs = next.startAtMs
        } else {
            return nil
        }

        return WatchShiftEvaluation(
            phase: phase,
            totalMs: total,
            elapsedMs: elapsed,
            remainingMs: total - elapsed,
            progress: Double(elapsed) / Double(total) * 100,
            nextBoundaryAtMs: nextBoundaryAtMs
        )
    }
}
