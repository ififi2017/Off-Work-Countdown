import Foundation
import Observation

/// Owns the durable choice to use local or restored data. Presentation belongs
/// to the requesting scene; a background sync never opens another scene's UI.
@MainActor
@Observable
final class RecoveryStore {
    enum SettingsResult: Equatable {
        case handled
        case needsDataReview
    }

    let records: RecordCoordinator
    let preferences: PreferencesStore
    let plus: PlusEntitlement
    let cloudSync: RecordsCloudSync
    private let defaults: UserDefaults
    private(set) var resumeCloudSyncWhenAuthorized: Bool
    private(set) var firstRunRecoveryResolved: Bool
    private(set) var localSetupNeedsCloudChoice: Bool

    private enum Key {
        static let resumeCloudSyncWhenAuthorized = "ios.native.resumeCloudSyncWhenAuthorized"
        static let firstRunRecoveryResolved = "ios.native.firstRunRecoveryResolved"
        static let localSetupNeedsCloudChoice = "ios.native.localSetupNeedsCloudChoice"
    }

    init(records: RecordCoordinator, preferences: PreferencesStore, plus: PlusEntitlement,
         defaults: UserDefaults, cloudSync: RecordsCloudSync = RecordsCloudSync()) {
        self.records = records
        self.preferences = preferences
        self.plus = plus
        self.defaults = defaults
        self.cloudSync = cloudSync
        resumeCloudSyncWhenAuthorized = defaults.bool(forKey: Key.resumeCloudSyncWhenAuthorized)
        firstRunRecoveryResolved = defaults.bool(forKey: Key.firstRunRecoveryResolved)
        localSetupNeedsCloudChoice = defaults.bool(forKey: Key.localSetupNeedsCloudChoice)
        cloudSync.attach(records: records)
    }

    func continueFirstRunLocally() {
        firstRunRecoveryResolved = true
        // An empty probe is a momentary answer: an older device can upload
        // later. Every unpaired local setup gets checked again at first sync.
        localSetupNeedsCloudChoice = true
        defaults.set(true, forKey: Key.firstRunRecoveryResolved)
        defaults.set(true, forKey: Key.localSetupNeedsCloudChoice)
    }

    func finishFirstRunCloudRestore(hasPreferences: Bool) {
        localSetupNeedsCloudChoice = false
        defaults.set(false, forKey: Key.localSetupNeedsCloudChoice)
        resumeCloudSyncWhenAuthorized = !records.state.sync.syncEnabled
        defaults.set(resumeCloudSyncWhenAuthorized, forKey: Key.resumeCloudSyncWhenAuthorized)
        if hasPreferences {
            preferences.onboardingComplete = true
            plus.markIntroSeen()
        }
        // Last marker: interruption cannot expose setup after preferences were
        // restored successfully but before completion was persisted.
        firstRunRecoveryResolved = true
        defaults.set(true, forKey: Key.firstRunRecoveryResolved)
    }

    func confirmEmptyCloudAndEnableSync() async -> SettingsResult {
        localSetupNeedsCloudChoice = false
        defaults.set(false, forKey: Key.localSetupNeedsCloudChoice)
        return await enableCloudSyncFromSettings()
    }

    func resumeRestoredSyncIfNeeded() async {
        // This marker is a restored owner's intent, never an override of the
        // user's decision to disable synchronization.
        guard resumeCloudSyncWhenAuthorized else { return }
        await cloudSync.restore()
        if records.state.sync.syncEnabled {
            resumeCloudSyncWhenAuthorized = false
            defaults.set(false, forKey: Key.resumeCloudSyncWhenAuthorized)
        }
    }

    /// The caller presents a choice only in the scene that requested it.
    func restoreCloudSyncFromSettings() async -> SettingsResult {
        guard !localSetupNeedsCloudChoice, records.state.sync.accountID != nil else {
            return .needsDataReview
        }
        await cloudSync.restore()
        return .handled
    }

    func enableCloudSyncFromSettings() async -> SettingsResult {
        guard !localSetupNeedsCloudChoice else { return .needsDataReview }
        await cloudSync.enable(authorized: plus.isAuthorized)
        if cloudSync.existingDataRequiresChoice {
            localSetupNeedsCloudChoice = true
            defaults.set(true, forKey: Key.localSetupNeedsCloudChoice)
            return .needsDataReview
        }
        return .handled
    }

    func recordsDataStatusLabel(using text: AppText) -> String {
        if !records.state.sync.conflicts.isEmpty {
            return text.t("recordsConflictCount", values: ["count": "\(records.state.sync.conflicts.count)"])
        }
        if cloudSync.higherFenceNeedsReview { return text.t("syncStatusPaused") }
        return text.t(records.state.sync.syncEnabled ? "syncStatusReady" : "syncStatusOff")
    }
}
