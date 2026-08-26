enum TimerVisualPhase: Hashable {
    case setup
    case running
    case lunch
    case overtime
    case completed
    case rest
    case rulesError

    static func resolve(
        countdownStarted: Bool,
        snapshot: NativeShiftSnapshot?,
        forceToday: Bool,
        endedEarly: Bool = false,
        dismissedCompleted: Bool = false
    ) -> Self {
        guard countdownStarted else { return .setup }
        guard let snapshot else { return .rulesError }
        // Clocked off early is a finished day, not a return to setup. Setup is
        // only for an explicit dismiss, and it must not disarm the schedule.
        // Checked before the rest-day gate so a forced Saturday that was then
        // ended by hand still lands on the celebration rather than "today is off".
        if endedEarly { return dismissedCompleted ? .setup : .completed }
        guard snapshot.isWorkday || forceToday else { return .rest }
        if snapshot.remainingMs <= 0 { return dismissedCompleted ? .setup : .completed }
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
        self == .completed || self == .rest || self == .rulesError
    }

    /// Setup and the rules-error page have a primary button and no
    /// seconds-level figure. Sitting them in a 1s `TimelineView` rebuilds
    /// that button every tick and drops taps — which is how "Apply settings"
    /// looked dead. Rest still ticks so midnight can leave the rest day.
    var usesLiveTimeline: Bool {
        switch self {
        case .setup, .rulesError: false
        case .running, .lunch, .overtime, .completed, .rest: true
        }
    }
}
