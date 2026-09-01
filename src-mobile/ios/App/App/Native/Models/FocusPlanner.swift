import Foundation

struct FocusBoundary: Equatable, Sendable {
    var at: Date
    var reason: FocusEndReason
}

enum FocusPlanner {
    static let pomodoroMinutes = 25 // legacy display compatibility

    /// Builds a real focus/recovery cycle from effective segments supplied by
    /// the shared rules bundle. The first boundary that cannot fit the next
    /// phase ends the timeline instead of silently stretching a break to a
    /// 25-minute tile or crossing lunch/clock-off.
    static func workBlocks(
        segments: [NativeShiftSegment],
        settings: FocusTimerSettings = .default,
        extraBoundaries: [Date] = []
    ) -> [FocusWorkBlock] {
        let configuration = settings.normalized
        var result: [FocusWorkBlock] = []
        var completedFocusRounds = 0
        for segment in segments.sorted(by: { $0.startAtMs < $1.startAtMs }) {
            let segmentStart = Int64(segment.startAtMs.rounded())
            let segmentEnd = Int64(segment.endAtMs.rounded())
            let cuts = extraBoundaries.map { Int64($0.timeIntervalSince1970 * 1_000) }
                .filter { $0 > segmentStart && $0 < segmentEnd }
                .sorted()
            for (startMs, endMs) in zip([segmentStart] + cuts, cuts + [segmentEnd]) {
                var cursor = startMs
                while cursor < endMs {
                    let focusMs = Int64(configuration.focusMinutes * 60_000)
                    guard cursor + focusMs <= endMs else { break }
                    result.append(FocusWorkBlock(
                        index: result.count,
                        start: Date(timeIntervalSince1970: Double(cursor) / 1_000),
                        end: Date(timeIntervalSince1970: Double(cursor + focusMs) / 1_000),
                        kind: .task
                    ))
                    cursor += focusMs
                    completedFocusRounds += 1

                    let breakMinutes = completedFocusRounds % configuration.longBreakEvery == 0
                        ? configuration.longBreakMinutes : configuration.shortBreakMinutes
                    let breakMs = Int64(breakMinutes * 60_000)
                    guard cursor + breakMs <= endMs else { break }
                    result.append(FocusWorkBlock(
                        index: result.count,
                        start: Date(timeIntervalSince1970: Double(cursor) / 1_000),
                        end: Date(timeIntervalSince1970: Double(cursor + breakMs) / 1_000),
                        kind: .breakTime
                    ))
                    cursor += breakMs
                }
            }
        }
        return result
    }

    /// Focus may start only inside a current work segment or the overtime
    /// stretch that continues from the last segment. A future segment start
    /// is not a startable window.
    static func isInsideWork(
        at date: Date,
        segments: [NativeShiftSegment],
        overtimeEndAtMs: Double?
    ) -> Bool {
        let nowMs = date.timeIntervalSince1970 * 1_000
        if segments.contains(where: { nowMs >= $0.startAtMs && nowMs < $0.endAtMs }) {
            return true
        }
        guard let last = segments.max(by: { $0.endAtMs < $1.endAtMs }),
              let overtimeEndAtMs,
              overtimeEndAtMs > last.endAtMs
        else { return false }
        return nowMs >= last.endAtMs && nowMs < overtimeEndAtMs
    }

    /// Next hard stop from shared-rule segments: lunch gap, shift end, or overtime end.
    static func nextBoundary(
        after start: Date,
        segments: [NativeShiftSegment],
        overtimeEndAtMs: Double?,
        durationMinutes: Int = pomodoroMinutes,
        extraBoundaries: [Date] = []
    ) -> FocusBoundary? {
        let startMs = start.timeIntervalSince1970 * 1_000
        let natural = start.addingTimeInterval(Double(durationMinutes * 60))
        let extraBoundary = extraBoundaries
            .filter { $0 > start && $0 < natural }
            .min()
        let sorted = segments.sorted { $0.startAtMs < $1.startAtMs }
        for (index, segment) in sorted.enumerated() {
            if startMs < segment.startAtMs {
                return FocusBoundary(
                    at: Date(timeIntervalSince1970: segment.startAtMs / 1_000),
                    reason: .stoppedAtBoundary
                )
            }
            if startMs >= segment.startAtMs && startMs < segment.endAtMs {
                let planned = start.addingTimeInterval(Double(durationMinutes * 60))
                let plannedMs = planned.timeIntervalSince1970 * 1_000
                var endMs = segment.endAtMs
                if let overtimeEndAtMs, overtimeEndAtMs > endMs {
                    endMs = overtimeEndAtMs
                }
                if plannedMs <= endMs {
                    if sorted[safe: index + 1] != nil, plannedMs > segment.endAtMs {
                        return FocusBoundary(
                            at: Date(timeIntervalSince1970: segment.endAtMs / 1_000),
                            reason: .stoppedAtBoundary
                        )
                    }
                    if let extraBoundary {
                        return FocusBoundary(at: extraBoundary, reason: .stoppedAtBoundary)
                    }
                    return nil
                }
                // `endMs` already carries the declared overtime. Clamping it
                // back to `segment.endAtMs` made that extension dead code and
                // cut the block at the planned clock-off. Only a segment with
                // a lunch gap after it still stops at its own end.
                let boundaryMs = sorted[safe: index + 1] == nil ? endMs : segment.endAtMs
                let segmentBoundary = FocusBoundary(
                    at: Date(timeIntervalSince1970: boundaryMs / 1_000),
                    reason: .stoppedAtBoundary
                )
                if let extraBoundary, extraBoundary < segmentBoundary.at {
                    return FocusBoundary(at: extraBoundary, reason: .stoppedAtBoundary)
                }
                return segmentBoundary
            }
        }
        if let overtimeEndAtMs, overtimeEndAtMs > startMs {
            let overtimeBoundary = FocusBoundary(
                at: Date(timeIntervalSince1970: overtimeEndAtMs / 1_000),
                reason: .stoppedAtBoundary
            )
            if let extraBoundary, extraBoundary < overtimeBoundary.at {
                return FocusBoundary(at: extraBoundary, reason: .stoppedAtBoundary)
            }
            return overtimeBoundary
        }
        return extraBoundary.map { FocusBoundary(at: $0, reason: .stoppedAtBoundary) }
    }

    static func plannedEnd(
        from start: Date,
        segments: [NativeShiftSegment],
        overtimeEndAtMs: Double?,
        durationMinutes: Int = pomodoroMinutes,
        extraBoundaries: [Date] = []
    ) -> Date {
        let natural = start.addingTimeInterval(Double(durationMinutes * 60))
        if let boundary = nextBoundary(
            after: start,
            segments: segments,
            overtimeEndAtMs: overtimeEndAtMs,
            durationMinutes: durationMinutes,
            extraBoundaries: extraBoundaries
        ),
           boundary.at < natural {
            return boundary.at
        }
        return natural
    }

    /// Why a block that ran all the way to its planned end stopped.
    ///
    /// `plannedEnd` returns the natural 25-minute mark only when a whole
    /// pomodoro fits before the next lunch or clock-off boundary — anything
    /// shorter was cut by that boundary. The planned duration is therefore the
    /// answer, and nothing extra has to be persisted on the session to know it.
    ///
    /// Everything used to report `.stoppedAtBoundary`, including a block that
    /// simply finished, so a completed pomodoro never marked its task done.
    static func endReason(
        startedAt: Date,
        plannedEndAt: Date,
        expectedDurationMinutes: Int = pomodoroMinutes
    ) -> FocusEndReason {
        let full = Double(expectedDurationMinutes * 60)
        // A second of slack: the planned end is computed from `Date.now` and
        // compared against a stored value that made a round trip through JSON.
        return plannedEndAt.timeIntervalSince(startedAt) >= full - 1 ? .completed : .stoppedAtBoundary
    }

    static func remainingPomodoros(
        tasks: [FocusTask],
        remainingWorkMs: Int64,
        completedBlocks: (FocusTask) -> Int = { _ in 0 },
        settings: FocusTimerSettings = .default
    ) -> (fits: [FocusTask], overflow: [FocusTask]) {
        var budget = remainingWorkMs
        var fits: [FocusTask] = []
        var overflow: [FocusTask] = []
        let slice = Int64(settings.normalized.focusMinutes) * 60_000
        for task in FocusTaskOrder.sorted(tasks) where task.completedAt == nil {
            let remaining = max(0, max(1, task.estimatedPomodoros) - completedBlocks(task))
            if remaining == 0 { continue }
            let need = Int64(remaining) * slice
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
