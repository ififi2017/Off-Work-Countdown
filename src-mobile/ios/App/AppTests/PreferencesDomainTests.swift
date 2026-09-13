import Foundation
import Observation
import Synchronization
import Testing
@testable import App

@MainActor
@Suite("Preferences without an application, shift or scene")
struct PreferencesDomainTests {
    @Test("Undated legacy settings migrate once and the archive wins on reopening")
    func legacyAndArchive() async throws {
        let suite = "PreferencesDomainLegacy.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        defaults.set(8 * 60, forKey: "ios.native.startMinutes")
        defaults.set("dark", forKey: "theme")
        let records = RecordCoordinator.inMemory()
        let first = PreferencesStore(defaults: defaults, records: records)
        let migrated = try #require(records.state.syncedPreferences)
        #expect(first.startMinutes == 8 * 60)
        #expect(migrated.editedAt == .distantPast)
        #expect(migrated.editCount == 1)
        #expect(migrated.theme == .dark)
        #expect(first.applyPreferences { $0.startMinutes = 7 * 60 }.synchronousResult)
        let committed = records.state
        defaults.set(9 * 60, forKey: "ios.native.startMinutes")
        let reopened = PreferencesStore(defaults: defaults, records: records)
        #expect(reopened.startMinutes == 7 * 60)
        #expect(defaults.integer(forKey: "ios.native.startMinutes") == 7 * 60)
        #expect(records.state == committed)
        #expect(records.state.periods.isEmpty)
        #expect(records.state.observations.isEmpty)
    }

    @Test("A compound setting saves once; an identical or invalid edit saves nothing")
    func atomicCommit() async throws {
        let suite = "PreferencesDomainCommit.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let file = FileManager.default.temporaryDirectory.appending(path: "preferences-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let records = RecordCoordinator(fileURL: file)
        let model = PreferencesStore(defaults: defaults, records: records)
        try await records.flush()
        let baselineWrites = records.archiveWriteCount
        var notifications = 0
        records.onDirty = { notifications += 1 }
        #expect(model.applyPreferences {
            $0.salaryAmount = "23000"
            $0.annualBonusEnabled = true
            $0.annualBonusMonths = 3
        }.synchronousResult)
        try await records.flush()
        #expect(records.archiveWriteCount == baselineWrites + 1)
        #expect(notifications == 1)
        let saved = records.state
        let revision = records.revision
        #expect(!model.applyPreferences {
            $0.salaryAmount = "23000"
            $0.annualBonusEnabled = true
            $0.annualBonusMonths = 3
        }.synchronousResult)
        #expect(!model.applyPreferences {
            $0.salaryAmount = "99999"
            $0.monthlyWorkingDays = 0
        }.synchronousResult)
        try await records.flush()
        #expect(model.salaryAmount == "23000")
        #expect(defaults.string(forKey: "ios.native.salaryAmount") == "23000")
        #expect(records.state == saved)
        #expect(records.revision == revision)
        #expect(records.archiveWriteCount == baselineWrites + 1)
        #expect(notifications == 1)
    }

    @Test("Reload ignores edit metadata; an open editor patches only its field onto incoming settings")
    func incomingState() throws {
        let suite = "PreferencesDomainIncoming.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let records = RecordCoordinator.inMemory()
        let model = PreferencesStore(defaults: defaults, records: records)
        var draft = SettingsFieldDraft(model.salaryAmount)
        draft.receive(model.salaryAmount)
        draft.value = "42000"
        let invalidated = Mutex(false)
        withObservationTracking {
            _ = model.currentSyncedPreferences()
            _ = model.startMinutes
            _ = model.salaryAmount
            _ = model.languageOverride
            _ = model.theme
        } onChange: {
            invalidated.withLock { $0 = true }
        }
        var incoming = try #require(records.state.syncedPreferences)
        incoming.editCount += 5
        incoming.editedAt = .now
        incoming.editTieBreaker = UUID()
        records.applyIncomingValue(.syncedPreferences(incoming))
        model.reloadFromArchive()
        #expect(!invalidated.withLock { $0 })
        incoming.startMinutes = 7 * 60
        incoming.salaryType = .daily
        incoming.annualBonusMonths = 4
        records.applyIncomingValue(.syncedPreferences(incoming))
        model.reloadFromArchive()
        #expect(invalidated.withLock { $0 })
        #expect(model.applyPreferences { $0.salaryAmount = draft.value }.synchronousResult)
        #expect(model.startMinutes == 7 * 60)
        #expect(model.salaryType == .daily)
        #expect(model.annualBonusMonths == 4)
        #expect(model.salaryAmount == "42000")
        let committed = records.state
        model.reloadFromArchive()
        #expect(records.state == committed)
    }

    @Test("A completed field commit cannot clear a later A to B to A edit")
    func fieldDraftCommitIdentity() {
        var draft = SettingsFieldDraft("original")
        draft.receive("original")
        draft.value = "A"
        let submitted = draft.editGeneration
        draft.value = "B"
        draft.value = "A"
        let acceptedOld = draft.accept("A", ifUnchangedSince: submitted)
        #expect(!acceptedOld)
        #expect(draft.value == "A")
        #expect(draft.hasChanges)

        let current = draft.editGeneration
        let acceptedCurrent = draft.accept("A", ifUnchangedSince: current)
        #expect(acceptedCurrent)
        #expect(!draft.hasChanges)
        let committedGeneration = draft.editGeneration
        draft.receive("new committed value")
        #expect(draft.value == "new committed value")
        #expect(draft.editGeneration == committedGeneration)
    }

    @Test("Setup choices stay local until completion and device capabilities never enter synced settings")
    func setupBoundary() throws {
        let suite = "PreferencesDomainSetup.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = RecordCoordinator.inMemory()
        let model = PreferencesStore(defaults: defaults, records: records)
        let initial = records.state
        model.applyOnboardingReminderDefaultsIfNeeded()
        #expect(model.lunchEnabled)
        #expect(model.notificationMode == .simple)
        #expect(model.applyPreferences { $0.notificationMode = .off }.synchronousResult)
        model.applyOnboardingReminderDefaultsIfNeeded()
        #expect(model.notificationMode == .off)
        #expect(records.state == initial)
        model.completeSetup(enableNotifications: true)
        let saved = records.state
        #expect(saved.syncedPreferences?.notificationMode == .simple)
        #expect(saved.syncedPreferences?.editCount == 1)
        model.completeSetup(enableNotifications: true)
        model.hideEarnings = true
        model.liveActivityEnabled = true
        model.focusLiveActivityEnabled = false
        #expect(records.state == saved)
        #expect(records.state.periods.isEmpty)
        #expect(records.state.observations.isEmpty)
    }
}
