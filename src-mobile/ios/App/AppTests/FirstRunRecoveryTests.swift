import CloudKit
import Foundation
import Testing
@testable import App

private actor FirstRunRestoreGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pauseFirst() async {
        guard !entered else { return }
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
private func recoveryStore(completed: Bool = false) throws -> (AppRuntime, UserDefaults, String) {
    let suite = "FirstRunRecovery.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    if completed { defaults.set(true, forKey: "ios.native.onboardingComplete") }
    let store = AppRuntime(defaults: defaults, records: .inMemory())
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
    #expect(!store.recovery.firstRunRecoveryResolved)
    store.preferences.applyPreferences { $0.startMinutes = 8 * 60 }
    store.preferences.applyPreferences { $0.salaryAmount = "10000" }
    store.preferences.applyOnboardingReminderDefaultsIfNeeded()
    #expect(store.records.state.syncedPreferences == nil)
    #expect(RecordsSyncOutbox.pending(store.records.state.sync).isEmpty)
    store.recovery.continueFirstRunLocally()
    #expect(store.recovery.localSetupNeedsCloudChoice)
    store.preferences.completeSetup(enableNotifications: false)
    #expect(store.records.state.syncedPreferences?.startMinutes == 8 * 60)
    #expect(!store.records.state.sync.syncEnabled)
}

@MainActor
@Test("Offline setup requires a cloud choice before enabling sync")
func offlineSetupRequiresCloudChoice() async throws {
    let (store, defaults, suite) = try recoveryStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    store.recovery.continueFirstRunLocally()
    store.preferences.completeSetup(enableNotifications: false)
    #expect(await store.recovery.enableCloudSyncFromSettings() == .needsDataReview)
    #expect(!store.records.state.sync.syncEnabled)
}

@MainActor
@Test("First-run cloud staging leaves the live store untouched until one durable commit")
func firstRunCloudCommitIsAtomic() async throws {
    let (source, sourceDefaults, sourceSuite) = try recoveryStore(completed: true)
    defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
    source.preferences.applyPreferences { $0.salaryAmount = "10000" }
    source.preferences.applyPreferences { $0.salaryEnabled = true }
    source.preferences.applyPreferences { $0.startMinutes = 8 * 60 }
    let preferences = try #require(source.records.state.syncedPreferences)
    let snapshot = try recoverySnapshot(preferences)
    let (target, targetDefaults, targetSuite) = try recoveryStore()
    defer { targetDefaults.removePersistentDomain(forName: targetSuite) }
    let before = target.records.state
    let restored = try target.recovery.cloudSync.prepareFirstRunRestore(snapshot, initialState: before)
    #expect(target.records.state == before)
    #expect(restored.syncedPreferences?.salaryAmount == "10000")
    try await target.records.commitRestoredState(restored)
    target.recovery.finishFirstRunCloudRestore(hasPreferences: restored.syncedPreferences != nil)
    #expect(target.preferences.salaryAmount == "10000")
    #expect(target.preferences.startMinutes == 8 * 60)
    #expect(target.preferences.onboardingComplete)
    #expect(target.plus.hasSeenIntro)
    #expect(!target.recovery.localSetupNeedsCloudChoice)
    #expect(target.records.state.sync.syncEnabled)
    #expect(!target.recovery.resumeCloudSyncWhenAuthorized)
}

@MainActor
@Test("First-run restore builds from the state published by an earlier candidate")
func firstRunRestoreUsesLatestAdmittedState() async throws {
    let suite = "FirstRunRestoreAdmission.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let root = FileManager.default.temporaryDirectory.appending(path: "first-run-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = FirstRunRestoreGate()
    let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"), prepareArchive: { state, url in
        await gate.pauseFirst()
        return try await RecordArchive.prepare(state, for: url)
    })
    let store = AppRuntime(defaults: defaults, records: records)
    var first = records.state
    first.lifeProfile = LifeProfile(
        birthYear: 1990, retirementAge: 65,
        editedAt: .now, editCount: 1, editTieBreaker: UUID()
    )
    let earlier = Task { try await records.commitRestoredState(first) }
    await gate.waitUntilEntered()

    var cloudPreferences = store.preferences.currentSyncedPreferences()
    cloudPreferences.salaryAmount = "12000"
    let snapshot = try recoverySnapshot(cloudPreferences)
    let restore = Task { @MainActor in
        try await records.commitRestoredState { latest in
            let restored = try store.recovery.cloudSync.prepareFirstRunRestore(
                snapshot,
                initialState: latest
            )
            return (restored, restored.lifeProfile?.retirementAge)
        }
    }
    await gate.release()
    try await earlier.value

    #expect(try await restore.value == 65)
    #expect(records.state.lifeProfile?.retirementAge == 65)
    #expect(records.state.syncedPreferences?.salaryAmount == "12000")
}

@MainActor
@Test("Choosing cloud setup preserves a newer local preference copy for recovery")
func firstRunCloudPreservesLocalAlternative() throws {
    let (store, defaults, suite) = try recoveryStore(completed: true)
    defer { defaults.removePersistentDomain(forName: suite) }
    store.preferences.applyPreferences { $0.salaryAmount = "5000" }
    let local = try #require(store.records.state.syncedPreferences)
    var remote = local
    remote.salaryAmount = "10000"
    remote.editCount = 1
    let restored = try store.recovery.cloudSync.prepareFirstRunRestore(
        recoverySnapshot(remote), initialState: store.records.state
    )
    #expect(restored.syncedPreferences?.salaryAmount == "10000")
    #expect(restored.sync.conflicts.contains { $0.entityType == .syncedPreferences && $0.currentWinner == .incoming })
    #expect(store.preferences.salaryAmount == "5000")
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
        _ = try store.recovery.cloudSync.prepareFirstRunRestore(
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
    store.recovery.continueFirstRunLocally()
    store.preferences.completeSetup(enableNotifications: false)
    #expect(store.recovery.localSetupNeedsCloudChoice)
    #expect(await store.recovery.restoreCloudSyncFromSettings() == .needsDataReview)
    #expect(!store.records.state.sync.syncEnabled)
}

@MainActor
@Test("A recovery choice is presented only in the requesting scene")
func recoveryChoiceIsSceneLocal() async throws {
    let (store, defaults, suite) = try recoveryStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    store.recovery.continueFirstRunLocally()
    let first = SceneState()
    let second = SceneState()

    await first.enableCloudSync(using: store.recovery)
    #expect(first.showsFirstRunCloudChoice)
    #expect(!second.showsFirstRunCloudChoice)
    first.showsFirstRunCloudChoice = false
    await second.enableCloudSync(using: store.recovery)
    #expect(!first.showsFirstRunCloudChoice)
    #expect(second.showsFirstRunCloudChoice)
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
        _ = try store.recovery.cloudSync.prepareFirstRunRestore(snapshot, initialState: local)
    }
    let confirmed = try store.recovery.cloudSync.prepareFirstRunRestore(
        snapshot, initialState: local, allowReplacingLocalData: true
    )
    #expect(confirmed.sync.generation == 2)
    #expect(confirmed.recordsStartedOn == nil)
    #expect(confirmed.sync.syncEnabled)
}

@MainActor
@Test("A restored owner keeps the request to sync when Plus verification becomes available")
func restoredSyncIntentSurvivesUnavailableEntitlement() throws {
    let (store, defaults, suite) = try recoveryStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    store.recovery.finishFirstRunCloudRestore(hasPreferences: true)
    #expect(store.recovery.resumeCloudSyncWhenAuthorized)
    #expect(defaults.bool(forKey: "ios.native.resumeCloudSyncWhenAuthorized"))
    #expect(store.preferences.onboardingComplete)
    #expect(store.recovery.firstRunRecoveryResolved)
    #expect(!store.session.countdownStarted)
}

@Test("First-run CloudKit retries only transient transport failures")
@MainActor
func firstRunRetryPolicy() {
    #expect(FirstRunRecoveryRetryPolicy.delay(for: CKError(.networkUnavailable)) == 2)
    #expect(FirstRunRecoveryRetryPolicy.delay(for: CKError(.notAuthenticated)) == nil)
}
