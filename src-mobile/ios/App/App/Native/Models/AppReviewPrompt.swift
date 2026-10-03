import Foundation

/// Durable eligibility for the system App Store review prompt.
///
/// Following App Store Review Guideline 5.6.1, we call the system review API
/// directly without a custom pre-prompt. Throttling ensures respectful usage:
/// - At most once per app version (CFBundleShortVersionString)
/// - At least 120 days between triggers
/// The system itself limits display to 3 times per year.
nonisolated struct AppReviewPromptState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case waitingForCompletion
        case readyForNextLaunch
        case never
    }

    static let minimumIntervalDays: Int = 120
    private static let minimumIntervalMs: Double = Double(minimumIntervalDays) * 24 * 60 * 60 * 1_000

    var phase: Phase = .waitingForCompletion
    var readyCompletionAtMs: Double?
    var handledCompletionAtMs: Double?
    var lastTriggeredVersion: String?
    var lastTriggeredAtMs: Double?

    mutating func noteCompletion(atMs completionAtMs: Double) {
        guard phase == .waitingForCompletion,
              completionAtMs > (handledCompletionAtMs ?? 0)
        else { return }
        phase = .readyForNextLaunch
        readyCompletionAtMs = completionAtMs
    }

    /// Captures a shift that ended while the app was not running and returns
    /// whether this cold launch may present the prompt.
    mutating func isEligibleOnLaunch(
        trackedCompletionAtMs: Double?,
        nowMs: Double
    ) -> Bool {
        guard phase != .never else { return false }
        if phase == .waitingForCompletion,
           let trackedCompletionAtMs,
           trackedCompletionAtMs <= nowMs {
            noteCompletion(atMs: trackedCompletionAtMs)
        }
        return phase == .readyForNextLaunch
    }

    /// Returns whether the system review should be triggered, applying throttling.
    /// Call this after `isEligibleOnLaunch` returns true.
    func shouldTriggerSystemReview(currentVersion: String, nowMs: Double) -> Bool {
        guard phase == .readyForNextLaunch else { return false }
        if let lastVersion = lastTriggeredVersion, lastVersion == currentVersion {
            return false
        }
        if let lastMs = lastTriggeredAtMs, nowMs - lastMs < Self.minimumIntervalMs {
            return false
        }
        return true
    }

    /// Records that the system review was triggered. Call this after requesting
    /// the system review.
    mutating func recordTrigger(version: String, atMs: Double) {
        lastTriggeredVersion = version
        lastTriggeredAtMs = atMs
        if let readyCompletionAtMs {
            handledCompletionAtMs = max(handledCompletionAtMs ?? 0, readyCompletionAtMs)
        }
        phase = .waitingForCompletion
        readyCompletionAtMs = nil
    }

    mutating func disable() {
        phase = .never
        readyCompletionAtMs = nil
    }

    mutating func revokeCompletion(atMs completionAtMs: Double) {
        guard phase == .readyForNextLaunch,
              readyCompletionAtMs == completionAtMs
        else { return }
        phase = .waitingForCompletion
        readyCompletionAtMs = nil
    }
}
