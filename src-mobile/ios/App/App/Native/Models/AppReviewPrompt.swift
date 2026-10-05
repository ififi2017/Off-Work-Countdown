import Foundation

/// Durable eligibility for the system App Store review prompt.
///
/// Following App Store Review Guideline 5.6.1, we call the system review API
/// directly without a custom pre-prompt. Because nothing softens that sheet,
/// it is only offered at a natural pause the user has just watched happen —
/// the clock-off celebration in the app — and never on launch, where Apple's
/// guidance says not to ask. Throttling keeps it respectful:
/// - Shifts finished on at least `minimumCompletedDays` different days since
///   the last request, so one trial day is not mistaken for a habit
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
    static let minimumCompletedDays: Int = 3
    private static let minimumIntervalMs: Double = Double(minimumIntervalDays) * 24 * 60 * 60 * 1_000

    var phase: Phase = .waitingForCompletion
    var lastTriggeredVersion: String?
    var lastTriggeredAtMs: Double?
    /// Different days with a finished shift since the last request. Optional
    /// so state written before this field existed decodes as zero.
    var completedDays: Int?
    var lastCompletedDayKey: String?

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
}
