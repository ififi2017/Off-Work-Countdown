import Foundation

/// Plan 021: what the timer can say about today from arrivals and departures
/// automation saw. A display fact only; it never adopts a time or changes the
/// countdown, which keeps following the schedule and the person's own edits.
nonisolated enum WorkplacePresence: Equatable, Sendable {
    /// At work, before or during the shift. `at` is the day's first seen
    /// arrival, kept whatever time work counts from; nil when monitoring
    /// started with the person already there, so no arrival was seen.
    case arrived(at: Date?)
    /// Still at work more than `overtimeGrace` after the planned end.
    case stayingLate(plannedEnd: Date)
    /// Still at work past `maximumAutomaticExtension`: maybe asleep there,
    /// maybe the phone stayed behind. Nothing is counted; the person checks.
    case needsCheck(plannedEnd: Date)
    /// Left during or after the shift.
    case left(at: Date, plannedEnd: Date)

    /// How far past the planned end the person stayed, or is staying.
    func overtime(at now: Date) -> TimeInterval {
        switch self {
        case .arrived, .needsCheck: 0
        case .stayingLate(let plannedEnd): max(0, now.timeIntervalSince(plannedEnd))
        case .left(let at, let plannedEnd): max(0, at.timeIntervalSince(plannedEnd))
        }
    }

    /// Nobody walks out on the minute. Until this has passed, still being at
    /// work is just packing up: the day ends as usual, celebration included.
    static let overtimeGrace: TimeInterval = 5 * 60

    /// How long before the shift arrival and departure events still describe
    /// it: a little more than the earliest arrival automation suggests.
    static let lookBack: TimeInterval = WorkplaceAutomation.arrivalLeadWindow + 60 * 60

    /// The newest event between `lookBack` before the planned start and now
    /// decides.
    static func resolve(
        plannedStart: Date,
        plannedEnd: Date,
        state: WorkplaceAutomationState,
        now: Date
    ) -> WorkplacePresence? {
        guard state.settings.isMonitoringEnabled, plannedEnd > plannedStart else { return nil }
        let windowStart = plannedStart.addingTimeInterval(-lookBack)
        let latest = state.events
            .filter { $0.proposedTime >= windowStart && $0.proposedTime <= now }
            .max { $0.proposedTime < $1.proposedTime }
        guard let latest else { return nil }
        switch latest.type {
        case .enterInner:
            // The first arrival, not a return from lunch: it is when the
            // person got to work, whether or not work counts from it.
            let firstArrival = state.events
                .filter { $0.type == .enterInner && !$0.isInitialState
                    && $0.proposedTime >= windowStart && $0.proposedTime <= now }
                .map(\.proposedTime)
                .min()
            if now < plannedStart {
                return .arrived(at: latest.isInitialState ? nil : firstArrival)
            }
            let pastEnd = now.timeIntervalSince(plannedEnd)
            if pastEnd > WorkplaceAutomation.maximumAutomaticExtension { return .needsCheck(plannedEnd: plannedEnd) }
            if pastEnd >= overtimeGrace { return .stayingLate(plannedEnd: plannedEnd) }
            // Until the end the arrival is the day's fact; after it, the
            // day ends as usual.
            return now < plannedEnd ? firstArrival.map { .arrived(at: $0) } : nil
        case .exitOuter:
            // Leaving before the shift says nothing about the shift.
            guard !latest.isInitialState, latest.proposedTime >= plannedStart else { return nil }
            return .left(at: latest.proposedTime, plannedEnd: plannedEnd)
        }
    }
}
