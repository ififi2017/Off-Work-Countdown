enum TimerVisualPhase: Hashable {
    /// `scheduleMode == .off` and today has no manual session.
    case unscheduled
    /// Clock-in countdown, clock-off countdown, or a lunch / overtime interlude.
    case running
    case lunch
    case overtime
    case completed
    case rest
    case rulesError

    static func resolve(
        followsSchedule: Bool,
        sessionActive: Bool,
        snapshot: NativeShiftSnapshot?,
        forceToday: Bool,
        endedEarly: Bool
    ) -> Self {
        if !followsSchedule, !sessionActive { return .unscheduled }
        guard let snapshot else { return .rulesError }
        // Clocked off early is a finished day. Checked before the rest-day
        // gate so a forced Saturday that was then ended by hand still lands
        // on the celebration rather than "today is off".
        if endedEarly { return .completed }
        if followsSchedule, !snapshot.isWorkday, !forceToday { return .rest }
        if snapshot.remainingMs <= 0 { return .completed }
        if snapshot.activeBreakEndAtMs != nil { return .lunch }
        if snapshot.overtimeEndAtMs != nil,
           snapshot.elapsedMs >= snapshot.plannedDurationMs {
            return .overtime
        }
        return .running
    }

    var showsActiveTimer: Bool {
        self == .running || self == .lunch || self == .overtime
    }

    var usesCommonTimerSurface: Bool {
        self == .completed || self == .rest || self == .rulesError || self == .unscheduled
    }

    /// Unscheduled idle and the rules-error banner have a primary button and
    /// no seconds-level figure. Sitting them in a 1s `TimelineView` rebuilds
    /// that button every tick and drops taps.
    var usesLiveTimeline: Bool {
        switch self {
        case .unscheduled, .rulesError: false
        case .running, .lunch, .overtime, .completed, .rest: true
        }
    }

    /// Lunch and overtime are interludes of the same running surface. Identity
    /// here must not change between them, or the whole screen cross-fades.
    var surfaceIdentity: String {
        switch self {
        case .running, .lunch, .overtime: "active"
        case .completed: "completed"
        case .rest: "rest"
        case .unscheduled: "unscheduled"
        case .rulesError: "rulesError"
        }
    }
}
