import Foundation

/// Durable eligibility for the system App Store review prompt.
///
/// Following App Store Review Guideline 5.6.1, we call the system review API
/// directly without a custom pre-prompt. The ask waits until the user comes
/// back after off-work, instead of covering the clock-off celebration:
/// - Shifts finished on at least `minimumCompletedDays` different days since
///   the last request, so one trial day is not mistaken for a habit
/// - The first return from the background after that day's off-work time,
///   once the opening surface has settled, and at most one attempt per
///   records-calendar day
/// - Not while the paywall, lifetime gift, What's New, life-setup offer,
///   an editor, the schedule, focus, or another sheet is on screen; that
///   open is left unused for the next one that is clear
/// - At most once per app version (CFBundleShortVersionString)
/// - At least 120 days between requests
/// The system itself limits display to 3 times per year.
nonisolated struct AppReviewPromptState: Codable, Equatable, Sendable {
    /// Only `.never` still changes behaviour. The other two cases are what
    /// earlier versions stored, kept so their saved state still decodes.
    enum Phase: String, Codable, Sendable {
        case waitingForCompletion
        case readyForNextLaunch
        case never
    }

    static let minimumIntervalDays: Int = 120
    static let minimumCompletedDays: Int = 2
    /// Never over the first frame of a visit, nor over the five-second
    /// clock-off celebration.
    static let foregroundSettle: Duration = .seconds(6)
    private static let minimumIntervalMs: Double = Double(minimumIntervalDays) * 24 * 60 * 60 * 1_000

    var phase: Phase = .waitingForCompletion
    var lastTriggeredVersion: String?
    var lastTriggeredAtMs: Double?
    /// Different days with a finished shift since the last request. Optional
    /// so state written before this field existed decodes as zero.
    var completedDays: Int?
    var lastCompletedDayKey: String?
    /// Records-calendar day of the last real attempt. A blocked open does not set it.
    /// Optional so state written before this field existed still decodes.
    var lastAttemptDayKey: String?

    /// Counts a finished shift once per calendar day, however many times that
    /// day's completion is noted.
    mutating func noteCompletion(dayKey: String) {
        guard phase != .never, dayKey != lastCompletedDayKey else { return }
        completedDays = (completedDays ?? 0) + 1
        lastCompletedDayKey = dayKey
    }

    /// Undoes `noteCompletion` when the user carries on working that day.
    mutating func revokeCompletion(dayKey: String) {
        guard dayKey == lastCompletedDayKey, let days = completedDays, days > 0 else { return }
        completedDays = days - 1
        lastCompletedDayKey = nil
    }

    /// Whether this pause may show the system review request.
    func isDue(currentVersion: String, nowMs: Double) -> Bool {
        guard phase != .never, (completedDays ?? 0) >= Self.minimumCompletedDays else { return false }
        if lastTriggeredVersion == currentVersion { return false }
        if let lastMs = lastTriggeredAtMs, nowMs - lastMs < Self.minimumIntervalMs { return false }
        return true
    }

    /// Records the request and starts counting days afresh for the next one.
    mutating func recordTrigger(version: String, atMs: Double) {
        lastTriggeredVersion = version
        lastTriggeredAtMs = atMs
        completedDays = 0
    }

    mutating func disable() {
        phase = .never
    }

    /// After today's off-work time, the first clear foreground. A blocking layer
    /// does not consume the day's attempt.
    mutating func onForeground(_ event: ReviewForeground, currentVersion: String) -> Bool {
        noteFinishedShift(event)
        guard event.blocker == .none else { return false }
        guard let offWorkAtMs = event.offWorkAtMs, event.nowMs >= offWorkAtMs else { return false }
        guard lastAttemptDayKey != event.todayKey else { return false }
        guard isDue(currentVersion: currentVersion, nowMs: event.nowMs) else { return false }
        recordTrigger(version: currentVersion, atMs: event.nowMs)
        lastAttemptDayKey = event.todayKey
        return true
    }

#if DEBUG
    /// Skips the day count, version dedup and 120-day gap. A manual opt-out still wins.
    mutating func onForegroundIgnoringThresholds(_ event: ReviewForeground) -> Bool {
        noteFinishedShift(event)
        guard phase != .never, event.blocker == .none else { return false }
        guard let offWorkAtMs = event.offWorkAtMs, event.nowMs >= offWorkAtMs else { return false }
        guard lastAttemptDayKey != event.todayKey else { return false }
        lastAttemptDayKey = event.todayKey
        return true
    }
#endif

    private mutating func noteFinishedShift(_ event: ReviewForeground) {
        guard let day = event.finishedShiftDayKey, let offWorkAtMs = event.offWorkAtMs, event.nowMs >= offWorkAtMs else { return }
        noteCompletion(dayKey: day)
    }
}

nonisolated enum ReviewPromptBlocker: Equatable, Sendable {
    case none
    case paywall
    case lifetimeGift
    case whatsNew
    case lifeSetup
    case editor
    case schedule
    case focus
    case dialog
}

nonisolated enum ReviewScenePhase: Equatable, Sendable {
    case active, inactive, background
}

/// Which scene changes start a visit. A cold start still does (`backgrounded`
/// begins set). Control Center only goes inactive and does not. Leaving during
/// the settle wait does not decide the visit.
nonisolated struct ReviewVisits: Equatable, Sendable {
    var generation: Int = 0
    var backgrounded: Bool = true
    var decided: Int = 0

    func observed(_ phase: ReviewScenePhase) -> ReviewVisits {
        switch phase {
        case .background:
            var next = self
            next.backgrounded = true
            return next
        case .active where backgrounded:
            var next = self
            next.backgrounded = false
            next.generation += 1
            return next
        default:
            return self
        }
    }

    /// `stillActive` is false when the six-second wait was cancelled. The visit
    /// stays undecided, so a later settle of the same visit may still ask.
    func settled(visit: Int, stillActive: Bool) -> (visits: ReviewVisits, decide: Bool) {
        guard stillActive, visit == generation, visit > decided else { return (self, false) }
        var next = self
        next.decided = visit
        return (next, true)
    }
}

/// Editors, the schedule, focus and other sheets. Same deferral as the paywall.
nonisolated struct ReviewSurface: Equatable, Sendable {
    var dayEditor = false
    var scheduleEditor = false
    var focus = false
    var dialog = false

    var blocker: ReviewPromptBlocker {
        if dayEditor { return .editor }
        if scheduleEditor { return .schedule }
        if focus { return .focus }
        if dialog { return .dialog }
        return .none
    }
}

nonisolated struct ReviewForeground: Equatable, Sendable {
    var nowMs: Double
    var todayKey: String
    var offWorkAtMs: Double?
    var finishedShiftDayKey: String?
    var blocker: ReviewPromptBlocker

    /// [todayKey] is the records day of [nowMs]. The finished day is set only once off-work is past.
    static func capture(nowMs: Double, offWorkAtMs: Double?, calendar: Calendar, blocker: ReviewPromptBlocker) -> ReviewForeground {
        let now = Date(timeIntervalSince1970: nowMs / 1_000)
        let finished = offWorkAtMs.flatMap { end -> String? in
            guard nowMs >= end else { return nil }
            return RecordJSON.dayKey(Date(timeIntervalSince1970: end / 1_000), calendar: calendar)
        }
        return ReviewForeground(
            nowMs: nowMs,
            todayKey: RecordJSON.dayKey(now, calendar: calendar),
            offWorkAtMs: offWorkAtMs,
            finishedShiftDayKey: finished,
            blocker: blocker
        )
    }
}

#if DEBUG
/// Debug builds only. Release never compiles these keys or the menu that writes them.
enum AppReviewDebugSwitch {
    private static let ignoreKey = "ios.native.debug.reviewIgnoreThresholds"
    private static let forceKey = "ios.native.debug.reviewForce"

    static var ignoresThresholds: Bool {
        get { UserDefaults.standard.bool(forKey: ignoreKey) }
        set { UserDefaults.standard.set(newValue, forKey: ignoreKey) }
    }

    static var forceArmed: Bool {
        get { UserDefaults.standard.bool(forKey: forceKey) }
        set { UserDefaults.standard.set(newValue, forKey: forceKey) }
    }
}
#endif
