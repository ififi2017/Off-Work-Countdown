import CloudKit
import Foundation
import Testing
@testable import App

@MainActor
private func recoveryStore(completed: Bool = false) throws -> (OffWorkStore, UserDefaults, String) {
    let suite = "FirstRunRecovery.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    if completed { defaults.set(true, forKey: "ios.native.onboardingComplete") }
    let store = OffWorkStore(defaults: defaults, records: .inMemory())
    return (store, defaults, suite)
}

@MainActor
private func recoverySnapshot(_ preferences: SyncedPreferences, generation: Int = 1) throws -> FirstRunCloudSnapshot {
    let row = CKRecord(recordType: "RecordRow", recordID: CKRecord.ID(
        recordName: SyncedPreferences.logicalKey,
        zoneID: CKRecordZone.ID(zoneName: RecordsSyncIdentity.dataZone(generation: generation))
    ))
    row["generation"] = generation
    row["entityType"] = RecordEntityType.syncedPreferences.rawValue
    row["logicalKey"] = SyncedPreferences.logicalKey
    row["payload"] = try JSONEncoder().encode(preferences)
    row["editCount"] = preferences.editCount
    row["editTieBreaker"] = preferences.editTieBreaker.uuidString
    return FirstRunCloudSnapshot(accountID: "test-account", generation: generation, rows: [row])
}

@MainActor
@Test("Fresh setup never seeds shared preferences or promotes onboarding drafts before completion")
func firstRunDoesNotUploadDefaults() throws {
    let (store, defaults, suite) = try recoveryStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(store.records.state.syncedPreferences == nil)
    #expect(RecordsSyncOutbox.pending(store.records.state.sync).isEmpty)
    #expect(!store.firstRunRecoveryResolved)
    store.startMinutes = 8 * 60
    store.salaryAmount = "10000"
    store.applyOnboardingReminderDefaultsIfNeeded()
    #expect(store.records.state.syncedPreferences == nil)
    #expect(RecordsSyncOutbox.pending(store.records.state.sync).isEmpty)
    store.continueFirstRunLocally(cloudCheckWasEmpty: false)
    #expect(store.localSetupNeedsCloudChoice)
    store.completeOnboarding(enableNotifications: false)
    #expect(store.records.state.syncedPreferences?.startMinutes == 8 * 60)
    #expect(!store.records.state.sync.syncEnabled)
}

@MainActor
@Test("Offline setup requires a cloud choice before enabling sync")
func offlineSetupRequiresCloudChoice() async throws {
    let (store, defaults, suite) = try recoveryStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    store.continueFirstRunLocally(cloudCheckWasEmpty: false)
    store.completeOnboarding(enableNotifications: false)
    await store.enableCloudSyncFromSettings()
    #expect(store.showsFirstRunCloudChoice)
    #expect(!store.records.state.sync.syncEnabled)
}

@MainActor
@Test("First-run cloud staging leaves the live store untouched until one durable commit")
func firstRunCloudCommitIsAtomic() throws {
    let (source, sourceDefaults, sourceSuite) = try recoveryStore(completed: true)
    defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
    source.salaryAmount = "10000"
    source.salaryEnabled = true
    source.startMinutes = 8 * 60
    let preferences = try #require(source.records.state.syncedPreferences)
    let snapshot = try recoverySnapshot(preferences)
    let (target, targetDefaults, targetSuite) = try recoveryStore()
    defer { targetDefaults.removePersistentDomain(forName: targetSuite) }
    let before = target.records.state
    let restored = try target.cloudSync.prepareFirstRunRestore(snapshot, initialState: before)
    #expect(target.records.state == before)
    #expect(restored.syncedPreferences?.salaryAmount == "10000")
    try target.records.commitRestoredState(restored)
    target.finishFirstRunCloudRestore(hasPreferences: restored.syncedPreferences != nil)
    #expect(target.salaryAmount == "10000")
    #expect(target.startMinutes == 8 * 60)
    #expect(target.onboardingComplete)
    #expect(target.plus.hasSeenIntro)
    #expect(!target.localSetupNeedsCloudChoice)
}

@MainActor
@Test("Choosing cloud setup preserves a newer local preference copy for recovery")
func firstRunCloudPreservesLocalAlternative() throws {
    let (store, defaults, suite) = try recoveryStore(completed: true)
    defer { defaults.removePersistentDomain(forName: suite) }
    store.salaryAmount = "5000"
    let local = try #require(store.records.state.syncedPreferences)
    var remote = local
    remote.salaryAmount = "10000"
    remote.editCount = 1
    let restored = try store.cloudSync.prepareFirstRunRestore(
        recoverySnapshot(remote), initialState: store.records.state
    )
    #expect(restored.syncedPreferences?.salaryAmount == "10000")
    #expect(restored.sync.conflicts.contains { $0.entityType == .syncedPreferences && $0.currentWinner == .incoming })
    #expect(store.salaryAmount == "5000")
}

@MainActor
@Test("Malformed downloaded rows cannot partially replace a local archive")
func firstRunRejectsPartialCorruptDownload() throws {
    let (store, defaults, suite) = try recoveryStore(completed: true)
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = try #require(store.records.state.syncedPreferences)
    let snapshot = try recoverySnapshot(preferences)
    let bad = CKRecord(recordType: "RecordRow")
    bad["generation"] = 1
    bad["entityType"] = "unknown-future-type"
    let before = store.records.state
    #expect(throws: RecordPersistenceError.self) {
        _ = try store.cloudSync.prepareFirstRunRestore(
            FirstRunCloudSnapshot(accountID: snapshot.accountID, generation: 1, rows: snapshot.rows + [bad]),
            initialState: before
        )
    }
    #expect(store.records.state == before)
}

@MainActor
@Test("A once-empty iCloud probe never permanently pairs a new local setup")
func initiallyEmptyCloudStillNeedsPairing() async throws {
    let (store, defaults, suite) = try recoveryStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    store.continueFirstRunLocally(cloudCheckWasEmpty: true)
    store.completeOnboarding(enableNotifications: false)
    #expect(store.localSetupNeedsCloudChoice)
    await store.restoreCloudSyncFromSettings()
    #expect(store.showsFirstRunCloudChoice)
    #expect(!store.records.state.sync.syncEnabled)
}

@MainActor
@Test("Cloud reset cannot silently discard even metadata-only local records")
func cloudResetProtectsLocalMetadata() throws {
    let (store, defaults, suite) = try recoveryStore(completed: true)
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = try #require(store.records.state.syncedPreferences)
    let snapshot = try recoverySnapshot(preferences, generation: 2)
    var local = store.records.state
    local.recordsStartedOn = .now
    #expect(local.hasUnpairedRecords)
    #expect(throws: FirstRunRecoveryError.self) {
        _ = try store.cloudSync.prepareFirstRunRestore(snapshot, initialState: local)
    }
    let confirmed = try store.cloudSync.prepareFirstRunRestore(
        snapshot, initialState: local, allowReplacingLocalData: true
    )
    #expect(confirmed.sync.generation == 2)
    #expect(confirmed.recordsStartedOn == nil)
    #expect(!confirmed.sync.syncEnabled)
}

@MainActor
@Test("A restored owner keeps the request to sync when Plus verification becomes available")
func restoredSyncIntentSurvivesUnavailableEntitlement() throws {
    let (store, defaults, suite) = try recoveryStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    store.finishFirstRunCloudRestore(hasPreferences: true)
    #expect(store.resumeCloudSyncWhenAuthorized)
    #expect(defaults.bool(forKey: "ios.native.resumeCloudSyncWhenAuthorized"))
    #expect(store.onboardingComplete)
    #expect(store.firstRunRecoveryResolved)
    #expect(!store.countdownStarted)
}
