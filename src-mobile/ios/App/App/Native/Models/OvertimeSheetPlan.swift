import Foundation

/// Plan 024 phase 4: the rests the overtime sheet offers before the overtime
/// begins (dinner, say). They are breaks, not overtime.
nonisolated enum OvertimeRestChoices {
    static let minutes = [0, 15, 30, 45, 60]

    /// The choice closest to `minutes`, for prefilling a sheet from a session.
    static func nearest(to minutes: Double) -> Int {
        Self.minutes.min { abs(Double($0) - minutes) < abs(Double($1) - minutes) } ?? 0
    }
}

/// What the overtime sheet has chosen so far, and the instants and figures
/// that follow from it. Pure, so the sheet and its tests read the same rules:
/// the overtime starts at the planned clock-off plus the rest, and the counted
/// hours are the time from that start to the end.
nonisolated struct OvertimeSheetPlan: Equatable, Sendable {
    enum Entry: Hashable, Sendable {
        /// Pick the clock time the overtime ends.
        case until
        /// Pick how long it lasts, after the rest.
        case duration
    }

    static let durationStepMinutes = 15
    static let maximumDurationMinutes = 12 * 60

    var plannedEnd: Date
    var now: Date
    var entry: Entry = .until
    var restMinutes = 0
    var untilDate: Date
    var durationMinutes = 60

    /// When the overtime itself starts: after the rest.
    var startDate: Date { plannedEnd.addingTimeInterval(Double(restMinutes) * 60) }

    var endDate: Date {
        switch entry {
        case .until: untilDate
        case .duration: startDate.addingTimeInterval(Double(durationMinutes) * 60)
        }
    }

    /// An overtime end cannot precede the overtime's start or the current time.
    /// After a rest it must also leave a minute of overtime to count.
    var minimumEnd: Date {
        max(restMinutes > 0 ? startDate.addingTimeInterval(60) : startDate, now)
    }

    /// What the session receives as the start: only a rest moves it.
    var overtimeStart: Date? { restMinutes > 0 ? startDate : nil }

    var isValid: Bool { endDate >= minimumEnd }

    /// Counted milliseconds: the end minus the start, never negative.
    var countedMs: Double { max(0, endDate.timeIntervalSince(startDate) * 1_000) }

    /// Durations that still end now or later, 15 minutes apart.
    var durationChoices: [Int] {
        let step = Self.durationStepMinutes
        let elapsed = max(0, now.timeIntervalSince(startDate) / 60)
        let first = max(step, Int((elapsed / Double(step)).rounded(.up)) * step)
        return Array(stride(from: first, through: max(first, Self.maximumDurationMinutes), by: step))
    }

    /// The duration choice closest to the current end, for switching modes.
    private func closestDuration(to end: Date) -> Int {
        let minutes = end.timeIntervalSince(startDate) / 60
        let choices = durationChoices
        return choices.min { abs(Double($0) - minutes) < abs(Double($1) - minutes) } ?? Self.durationStepMinutes
    }

    /// Switch between the two ways of choosing, keeping the same end.
    mutating func select(_ entry: Entry) {
        guard entry != self.entry else { return }
        if entry == .duration {
            durationMinutes = closestDuration(to: untilDate)
        } else {
            untilDate = max(endDate, minimumEnd)
        }
        self.entry = entry
    }

    /// Keep the choices valid after the rest or the clock moved.
    mutating func settle() {
        switch entry {
        case .until:
            untilDate = max(untilDate, minimumEnd)
        case .duration:
            let choices = durationChoices
            if let first = choices.first, durationMinutes < first { durationMinutes = first }
            if let last = choices.last, durationMinutes > last { durationMinutes = last }
        }
    }
}
