import Foundation

/// Durable eligibility for the one respectful App Store review prompt.
///
/// A completion only arms a future launch. Choosing Later consumes that
/// completion, so the same finished shift cannot trigger the prompt again.
nonisolated struct AppReviewPromptState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case waitingForCompletion
        case readyForNextLaunch
        case never
    }

    var phase: Phase = .waitingForCompletion
    var readyCompletionAtMs: Double?
    var handledCompletionAtMs: Double?

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

    mutating func deferUntilNextCompletion() {
        guard phase == .readyForNextLaunch else { return }
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
