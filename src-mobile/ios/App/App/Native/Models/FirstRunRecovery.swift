import CloudKit
import Foundation

@MainActor
struct FirstRunCloudSnapshot {
    let accountID: String
    let generation: Int
    let rows: [CKRecord]
}

enum FirstRunRecoveryError: Error {
    case cloudChanged
    case noDownload
    case localDataNeedsReview
}

enum FirstRunRecoveryRetryPolicy {
    static func delay(for error: any Error) -> TimeInterval? {
        guard let error = error as? CKError else { return nil }
        switch error.code {
        case .networkFailure, .networkUnavailable, .requestRateLimited,
             .serviceUnavailable, .zoneBusy:
            return max(0.5, error.retryAfterSeconds ?? 2)
        default:
            return nil
        }
    }
}

enum FirstRunRecoveryPhase: Equatable {
    case checking
    case empty
    case needsSetup
    case failed
    case localDataNeedsReview
    case restoring
}

extension RecordState {
    /// Preferences are explicitly replaceable during setup; every other
    /// business row and unsent erasure must survive a generation mismatch.
    var hasUnpairedRecords: Bool {
        !periods.isEmpty || !snapshots.isEmpty || !exceptions.isEmpty
            || !overrides.isEmpty || !observations.isEmpty || lifeProfile != nil
            || !focusTasks.isEmpty || !focusSessions.isEmpty
            || focusPlanningConfiguration != nil || recordsStartedOn != nil
            || !erased.isEmpty
            || sync.rows.values.contains { $0.entityType != .syncedPreferences && ($0.dirty || $0.pendingErase) }
    }
}
