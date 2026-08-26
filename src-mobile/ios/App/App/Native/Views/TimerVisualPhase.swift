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
        endedEarly: Bool = false
    ) -> Self {
        // A shift the user has clocked off is over for them whatever the clock
        // says. Without this the button recorded the early finish and the screen
        // carried on counting, which read as the button doing nothing at all.
        guard !endedEarly else { return .setup }
        guard countdownStarted else { return .setup }
        guard let snapshot else { return .rulesError }
        guard snapshot.isWorkday || forceToday else { return .rest }
        guard snapshot.remainingMs > 0 else { return .completed }
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
}
