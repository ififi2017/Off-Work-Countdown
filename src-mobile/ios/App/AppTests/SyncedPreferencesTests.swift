import Foundation
import Testing
@testable import App

@MainActor
@Test("Existing device preferences migrate into one sync row")
func existingPreferencesSeedSyncRow() throws {
    let suite = "SyncedPreferences.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.set(true, forKey: "ios.native.onboardingComplete")
    defaults.set(8 * 60 + 30, forKey: "ios.native.startMinutes")
    defaults.set("52000", forKey: "ios.native.salaryAmount")
    defaults.set(true, forKey: "ios.native.salaryEnabled")
    defaults.set("milestones", forKey: "ios.native.notificationMode")
    defaults.set("dark", forKey: "theme")
    defaults.set("zh-CN", forKey: "ios.native.languageOverride")
    defaults.set(true, forKey: "hideEarnings")
    defaults.set(true, forKey: "ios.native.liveActivityEnabled")
    defer { defaults.removePersistentDomain(forName: suite) }

    let records = RecordCoordinator.inMemory()
    let store = AppRuntime(defaults: defaults, records: records)
    let preferences = try #require(records.state.syncedPreferences)
    #expect(preferences.startMinutes == 8 * 60 + 30)
    #expect(preferences.salaryAmount == "52000")
    #expect(preferences.salaryEnabled)
    #expect(preferences.notificationMode == .milestones)
    #expect(preferences.theme == .dark)
    #expect(preferences.languageOverride == "zh-CN")
    #expect(preferences.editedAt == .distantPast)
    #expect(records.state.sync.rows[SyncedPreferences.logicalKey]?.entityType == .syncedPreferences)
    #expect(records.state.sync.rows[SyncedPreferences.logicalKey]?.dirty == true)

    let originalEditCount = preferences.editCount
    store.preferences.hideEarnings = false
    store.preferences.liveActivityEnabled = false
    #expect(records.state.syncedPreferences?.editCount == originalEditCount)
    store.preferences.applyPreferences { $0.theme = .light }
    #expect(records.state.syncedPreferences?.editCount == originalEditCount + 1)
}

@MainActor
@Test("A remote preference row updates shared settings and preserves device-only choices")
func remotePreferencesApplyToStore() async throws {
    let suite = "SyncedPreferences.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.set(true, forKey: "ios.native.onboardingComplete")
    defer { defaults.removePersistentDomain(forName: suite) }
    let records = RecordCoordinator.inMemory()
    let store = AppRuntime(defaults: defaults, records: records)
    store.preferences.hideEarnings = true
    store.preferences.liveActivityEnabled = true

    var remote = try #require(records.state.syncedPreferences)
    remote.salaryAmount = "88000"
    remote.salaryEnabled = true
    remote.theme = .dark
    remote.languageOverride = "ja"
    remote.notificationMode = .simple
    remote.editCount += 5
    remote.editTieBreaker = UUID()
    remote.editedAt = .now.addingTimeInterval(60)
    let payload = try JSONEncoder().encode(remote)

    records.applyRemotePayload(
        type: .syncedPreferences,
        key: SyncedPreferences.logicalKey,
        payload: payload,
        editCount: remote.editCount,
        editTieBreaker: remote.editTieBreaker.uuidString,
        systemFields: nil,
        generation: records.state.sync.generation
    )
    try await records.persistRemoteBatch()

    #expect(store.preferences.salaryAmount == "88000")
    #expect(store.preferences.salaryEnabled)
    #expect(store.preferences.theme == .dark)
    #expect(store.preferences.languageOverride == "ja")
    #expect(store.preferences.notificationMode == .simple)
    #expect(store.preferences.hideEarnings)
    #expect(store.preferences.liveActivityEnabled)
}

@MainActor
@Test("Preference conflicts merge independent fields against the cloud baseline")
func syncedPreferencesMergeIndependentFields() {
    let baseline = sampleSyncedPreferences()
    var local = baseline
    local.startMinutes = 7 * 60
    local.editCount = 2
    local.editedAt = Date(timeIntervalSince1970: 2)
    var server = baseline
    server.salaryAmount = "72000"
    server.editCount = 2
    server.editedAt = Date(timeIntervalSince1970: 3)

    let merged = RecordsSyncConflict.mergeSyncedPreferences(
        local: local,
        server: server,
        baseline: baseline
    )
    #expect(merged.startMinutes == 7 * 60)
    #expect(merged.salaryAmount == "72000")
    #expect(merged.editCount == 3)
}

@MainActor
@Test("Backup JSON includes shared salary settings but excludes device security state")
func backupIncludesSyncedPreferencesOnly() throws {
    var state = RecordState()
    state.syncedPreferences = sampleSyncedPreferences()
    let timeZone = try #require(TimeZone(identifier: "UTC"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let data = try RecordJSON.export(state, exportedAt: .now, timeZone: timeZone, calendar: calendar)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.contains("salaryAmount"))
    #expect(text.contains("64000"))
    #expect(!text.contains("hideEarnings"))
    #expect(!text.contains("liveActivityEnabled"))

    let document = try RecordJSON.decode(data)
    var restored = RecordState()
    _ = try RecordJSON.apply(document, to: &restored, mode: .skipErased)
    #expect(restored.syncedPreferences == state.syncedPreferences)

    var invalid = document
    invalid.syncedPreferences?.recordsTimeZoneIdentifier = "Not/A-Time-Zone"
    var rejected = RecordState()
    let report = try RecordJSON.apply(invalid, to: &rejected, mode: .skipErased)
    #expect(report.rejected == [
        RecordImportRejection(
            entityType: .syncedPreferences,
            logicalKey: SyncedPreferences.logicalKey
        )
    ])
    #expect(rejected.syncedPreferences == nil)
}

@MainActor
@Test("An archive from the first preferences-sync build migrates its Date revision stamp")
func legacySyncedPreferencesDateStampMigrates() throws {
    var state = RecordState()
    state.syncedPreferences = sampleSyncedPreferences()
    let timeZone = try #require(TimeZone(identifier: "UTC"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let currentData = try RecordJSON.export(
        state,
        exportedAt: Date(timeIntervalSince1970: 10),
        timeZone: timeZone,
        calendar: calendar
    )
    var object = try #require(
        JSONSerialization.jsonObject(with: currentData) as? [String: Any]
    )
    var preferences = try #require(object["syncedPreferences"] as? [String: Any])
    preferences.removeValue(forKey: "editedAtMs")
    preferences["editedAt"] = Date(timeIntervalSince1970: 1).timeIntervalSinceReferenceDate
    preferences.removeValue(forKey: "languageOverride")
    object["syncedPreferences"] = preferences

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let document = try RecordJSON.decode(legacyData)
    var restored = RecordState()
    let report = try RecordJSON.apply(document, to: &restored, mode: .skipErased)

    #expect(report.rejected.isEmpty)
    #expect(restored.syncedPreferences?.editedAtMs == 1_000)
    #expect(restored.syncedPreferences?.languageOverride == nil)

    let rewritten = try RecordJSON.export(
        restored,
        exportedAt: Date(timeIntervalSince1970: 11),
        timeZone: timeZone,
        calendar: calendar
    )
    let rewrittenObject = try #require(
        JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
    )
    let rewrittenPreferences = try #require(
        rewrittenObject["syncedPreferences"] as? [String: Any]
    )
    #expect(rewrittenPreferences["editedAtMs"] != nil)
    #expect(rewrittenPreferences["editedAt"] == nil)
}

@MainActor
@Test("Equivalent preferences do not create revisions, outbox changes or notifications")
func unchangedPreferencesDoNotWrite() async throws {
    let records = RecordCoordinator.inMemory()
    records.upsertSyncedPreferences(sampleSyncedPreferences())
    let original = records.state
    let revision = records.revision
    var notifications = 0
    records.onDirty = { notifications += 1 }
    var draft = try #require(original.syncedPreferences)
    draft.editedAtMs += 10_000
    draft.editCount += 100
    draft.editTieBreaker = UUID()

    records.upsertSyncedPreferences(draft)
    #expect(records.state == original)
    #expect(records.revision == revision)
    #expect(notifications == 0)
    #expect(await records.commitSyncState { sync, _ in sync = original.sync })
    #expect(records.revision == revision)
}

@MainActor
@Test("Committing both displayed hours publishes one final preference revision")
func displayedHoursCommitOnePreferenceRow() throws {
    let scene = SceneState()
    let suite = "PreferencesBatch.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "ios.native.onboardingComplete")
    let records = RecordCoordinator.inMemory()
    let store = AppRuntime(defaults: defaults, records: records)
    let original = try #require(records.state.syncedPreferences)
    let revision = records.revision
    var published: [SyncedPreferences] = []
    records.onDirty = {
        if let preferences = records.state.syncedPreferences { published.append(preferences) }
    }

    scene.setDisplayedStartMinutes(8 * 60, using: store.preferences)
    scene.setDisplayedEndMinutes(18 * 60, using: store.preferences)
    #expect(records.revision == revision)
    scene.commitDisplayedHours(using: store.shifts)

    #expect(records.revision == revision + 1)
    #expect(published.count == 1)
    let saved = try #require(published.first)
    #expect(saved.startMinutes == 8 * 60)
    #expect(saved.endMinutes == 18 * 60)
    #expect(saved.editCount == original.editCount + 1)
    scene.commitDisplayedHours(using: store.shifts)
    #expect(records.revision == revision + 1)
    #expect(published.count == 1)
}

@MainActor
@Test("Preference dirty notifications wait for a successful archive write")
func preferenceNotificationsFollowDurableSave() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "archive.json")
    let records = RecordCoordinator(fileURL: file)
    var durableEditCounts: [Int] = []
    records.onDirty = {
        let reopened = RecordCoordinator(fileURL: file)
        if let saved = reopened.state.syncedPreferences {
            durableEditCounts.append(saved.editCount)
        }
    }

    records.upsertSyncedPreferences(sampleSyncedPreferences())
    await #expect(throws: RecordPersistenceError.writeFailed) { try await records.flush() }
    #expect(records.persistenceError == .writeFailed)
    #expect(durableEditCounts.isEmpty)
    let failedEditCount = try #require(records.state.syncedPreferences?.editCount)

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var revised = try #require(records.state.syncedPreferences)
    revised.startMinutes += 30
    records.upsertSyncedPreferences(revised)
    try await records.flush()
    #expect(records.persistenceError == nil)
    #expect(durableEditCounts == [failedEditCount + 1])
}

@MainActor
@Test("Theme, sync bookkeeping and focus edits preserve Life projection inputs")
func unrelatedChangesPreserveLifeProjection() async throws {
    let suite = "ProjectionInputs.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "ios.native.onboardingComplete")
    let records = RecordCoordinator.inMemory()
    let store = AppRuntime(defaults: defaults, records: records)
    store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
    let now = try #require(store.preferences.recordsCalendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 10)))
    let input = store.life.lifeSummaryRefreshInput(now: now)
    let key = store.life.lifeViewModelCacheKey(now: now)
    let contentRevision = records.contentRevision
    let historyRevision = records.historyRevision

    store.preferences.applyPreferences { $0.theme = .dark }
    var sync = records.state.sync
    sync.engineState = Data("test sync checkpoint".utf8)
    #expect(await records.commitSyncState { current, _ in
        current.engineState = sync.engineState
    })
    #expect(records.contentRevision == contentRevision)
    #expect(records.historyRevision == historyRevision)
    #expect(store.life.lifeSummaryRefreshInput(now: now) == input)
    #expect(store.life.lifeViewModelCacheKey(now: now) == key)

    records.upsertFocusPlanningConfiguration(.init(
        planning: .init(), timerSettings: .default, editedAt: now,
        editCount: 0, editTieBreaker: UUID()
    ))
    #expect(records.contentRevision == contentRevision + 1)
    #expect(records.historyRevision == historyRevision)
    #expect(store.life.lifeSummaryRefreshInput(now: now) == input)

    store.preferences.applyPreferences { $0.salaryAmount = "12000" }
    #expect(store.life.lifeSummaryRefreshInput(now: now) != input)
    let salaryKey = store.life.lifeViewModelCacheKey(now: now)
    #expect(salaryKey != key)
    #expect(salaryKey.hasSameSchedule(as: key))
}

@MainActor
@Test("A remote preference stamp update preserves projections and unsaved time drafts")
func remotePreferenceMetadataPreservesProjectionRevision() async throws {
    let scene = SceneState()
    let suite = "RemotePreferenceStamp.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "ios.native.onboardingComplete")
    let records = RecordCoordinator.inMemory()
    let store = AppRuntime(defaults: defaults, records: records)
    let draftStart = store.preferences.startMinutes + 15
    scene.setDisplayedStartMinutes(draftStart, using: store.preferences)
    let revision = records.contentRevision
    var remote = try #require(records.state.syncedPreferences)
    remote.editCount += 10
    remote.editTieBreaker = UUID()
    let payload = try JSONEncoder().encode(remote)
    records.applyRemotePayload(
        type: .syncedPreferences, key: SyncedPreferences.logicalKey, payload: payload,
        editCount: remote.editCount, editTieBreaker: remote.editTieBreaker.uuidString,
        systemFields: nil, generation: records.state.sync.generation,
        persistImmediately: false
    )
    try await records.persistRemoteBatch()
    #expect(records.state.syncedPreferences?.editCount == remote.editCount)
    #expect(records.contentRevision == revision)
    #expect(store.preferences.startMinutes == remote.startMinutes)
    #expect(scene.displayedStartMinutes(using: store.preferences) == draftStart)
}

@MainActor
@Test("One mixed record batch advances each affected domain once")
func batchedRecordDomainsAdvanceOnce() {
    let records = RecordCoordinator.inMemory()
    records.withBatchedWrites {
        records.upsertSyncedPreferences(sampleSyncedPreferences())
        records.upsertFocusPlanningConfiguration(.init(
            planning: .init(), timerSettings: .default, editedAt: .now,
            editCount: 0, editTieBreaker: UUID()
        ))
        records.updateLifeProfile(.init(editedAt: .now, editCount: 0, editTieBreaker: UUID()))
    }
    #expect(records.revision == 1)
    #expect(records.contentRevision == 1)
    #expect(records.projectionRevision == 1)
    #expect(records.lifeRevision == 1)
    #expect(records.focusRevision == 1)
    #expect(records.historyRevision == 0)
}

private func sampleSyncedPreferences() -> SyncedPreferences {
    SyncedPreferences(
        startMinutes: 9 * 60,
        endMinutes: 17 * 60,
        workdays: [1, 2, 3, 4, 5],
        scheduleMode: .classic,
        alternatingWeekType: .double,
        alternatingWeekendWorkday: 6,
        alternatingReferenceWeekStartMs: 1_788_000_000_000,
        rotationWorkDays: 2,
        rotationRestDays: 2,
        rotationAnchorMs: 1_788_000_000_000,
        lunchEnabled: true,
        lunchStartMinutes: 12 * 60,
        lunchDurationMinutes: 60,
        recordsTimeZoneIdentifier: "UTC",
        salaryAmount: "64000",
        salaryEnabled: true,
        salaryType: .monthly,
        monthlyWorkingDays: 22,
        annualBonusEnabled: true,
        annualBonusMonths: 2,
        notificationMode: .milestones,
        cycleEndSummaryNotificationEnabled: true,
        lunchStartReminderEnabled: true,
        lunchEndReminderEnabled: true,
        microBreakEnabled: true,
        microBreakIntervalMinutes: 60,
        theme: .auto,
        languageOverride: nil,
        editedAtMs: 1_000,
        editCount: 1,
        editTieBreaker: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )
}

@MainActor
@Test("Service scheduling ignores theme and sync metadata but observes shift inputs")
func serviceSchedulingUsesRelevantInputs() async throws {
    let suite = "ServiceInputs.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let records = RecordCoordinator.inMemory()
    let store = AppRuntime(defaults: defaults, records: records)
    store.preferences.completeSetup(enableNotifications: false)
    let original = ServiceScheduleSignal(shifts: store.shifts)
    store.preferences.applyPreferences { $0.theme = .dark }
    var sync = records.state.sync
    sync.engineState = Data([1, 2, 3])
    #expect(await records.commitSyncState { current, _ in
        current.engineState = sync.engineState
    })
    #expect(ServiceScheduleSignal(shifts: store.shifts) == original)
    store.preferences.applyPreferences { $0.startMinutes += 15 }
    #expect(ServiceScheduleSignal(shifts: store.shifts) != original)
    let afterHours = ServiceScheduleSignal(shifts: store.shifts)
    store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = store.preferences.recordsTimeZoneIdentifier == "UTC" ? "Asia/Shanghai" : "UTC" }
    #expect(ServiceScheduleSignal(shifts: store.shifts) != afterHours)
    let afterZone = ServiceScheduleSignal(shifts: store.shifts)
    store.preferences.applyPreferences { $0.monthlyWorkingDays += 1 }
    #expect(ServiceScheduleSignal(shifts: store.shifts) != afterZone)
}
