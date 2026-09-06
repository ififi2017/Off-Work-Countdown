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
    let store = OffWorkStore(defaults: defaults, records: records)
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
    store.hideEarnings = false
    store.liveActivityEnabled = false
    #expect(records.state.syncedPreferences?.editCount == originalEditCount)
    store.theme = .light
    #expect(records.state.syncedPreferences?.editCount == originalEditCount + 1)
}

@MainActor
@Test("A remote preference row updates shared settings and preserves device-only choices")
func remotePreferencesApplyToStore() throws {
    let suite = "SyncedPreferences.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.set(true, forKey: "ios.native.onboardingComplete")
    defer { defaults.removePersistentDomain(forName: suite) }
    let records = RecordCoordinator.inMemory()
    let store = OffWorkStore(defaults: defaults, records: records)
    store.hideEarnings = true
    store.liveActivityEnabled = true

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
    records.persistRemoteBatch()

    #expect(store.salaryAmount == "88000")
    #expect(store.salaryEnabled)
    #expect(store.theme == .dark)
    #expect(store.languageOverride == "ja")
    #expect(store.notificationMode == .simple)
    #expect(store.hideEarnings)
    #expect(store.liveActivityEnabled)
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
