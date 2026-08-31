import Foundation

struct FocusBoundary: Equatable, Sendable {
    var at: Date
    var reason: FocusEndReason
}

enum FocusPlanner {
    static let pomodoroMinutes = 25

    /// Next hard stop from shared-rule segments: lunch gap, shift end, or overtime end.
    static func nextBoundary(
        after start: Date,
        segments: [NativeShiftSegment],
        overtimeEndAtMs: Double?
    ) -> FocusBoundary? {
        let startMs = start.timeIntervalSince1970 * 1_000
        let sorted = segments.sorted { $0.startAtMs < $1.startAtMs }
        for (index, segment) in sorted.enumerated() {
            if startMs < segment.startAtMs {
                return FocusBoundary(
                    at: Date(timeIntervalSince1970: segment.startAtMs / 1_000),
                    reason: .stoppedAtBoundary
                )
            }
            if startMs >= segment.startAtMs && startMs < segment.endAtMs {
                let planned = start.addingTimeInterval(Double(pomodoroMinutes * 60))
                let plannedMs = planned.timeIntervalSince1970 * 1_000
                var endMs = segment.endAtMs
                if let overtimeEndAtMs, overtimeEndAtMs > endMs {
                    endMs = overtimeEndAtMs
                }
                if plannedMs <= endMs {
                    if let next = sorted[safe: index + 1], plannedMs > segment.endAtMs {
                        return FocusBoundary(
                            at: Date(timeIntervalSince1970: segment.endAtMs / 1_000),
                            reason: .stoppedAtBoundary
                        )
                    }
                    return nil
                }
                return FocusBoundary(
                    at: Date(timeIntervalSince1970: min(endMs, segment.endAtMs) / 1_000),
                    reason: .stoppedAtBoundary
                )
            }
        }
        if let overtimeEndAtMs, overtimeEndAtMs > startMs {
            return FocusBoundary(
                at: Date(timeIntervalSince1970: overtimeEndAtMs / 1_000),
                reason: .stoppedAtBoundary
            )
        }
        return nil
    }

    static func plannedEnd(
        from start: Date,
        segments: [NativeShiftSegment],
        overtimeEndAtMs: Double?
    ) -> Date {
        let natural = start.addingTimeInterval(Double(pomodoroMinutes * 60))
        if let boundary = nextBoundary(after: start, segments: segments, overtimeEndAtMs: overtimeEndAtMs),
           boundary.at < natural {
            return boundary.at
        }
        return natural
    }

    static func remainingPomodoros(
        tasks: [FocusTask],
        remainingWorkMs: Int64
    ) -> (fits: [FocusTask], overflow: [FocusTask]) {
        var budget = remainingWorkMs
        var fits: [FocusTask] = []
        var overflow: [FocusTask] = []
        let slice = Int64(pomodoroMinutes) * 60_000
        for task in FocusTaskOrder.sorted(tasks) where task.completedAt == nil {
            let need = Int64(max(1, task.estimatedPomodoros)) * slice
            if need <= budget {
                fits.append(task)
                budget -= need
            } else {
                overflow.append(task)
            }
        }
        return (fits, overflow)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
