import Foundation
import Testing
@testable import App

@MainActor
@Suite("Record commands and scene drafts without the application")
struct RecordsActionTests {
    private func hours() -> ScheduleHoursConfiguration {
        .init(startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: "12:00", breakDurationMinutes: 60)
    }

    private func actions(defaults: UserDefaults, records: RecordCoordinator) -> RecordsActions {
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        let preferences = PreferencesStore(defaults: defaults, records: records)
        let plus = PlusEntitlement(defaults: defaults)
        plus.debugSetAuthorized(true)
        return RecordsActions(records: records, preferences: preferences, plus: plus,
            text: AppText(preferences: preferences), currentHours: { _ in hours() })
    }

    private func queries(actions: RecordsActions) -> RecordsQueries {
        RecordsQueries(records: actions.records, plus: actions.plus, localizer: actions.text.localizer,
            sources: .init(calendar: { actions.preferences.recordsCalendar }, hours: { _ in hours() },
                rules: { _, _ in nil }, snapshot: { _ in nil }, isCounting: { false },
                salaryIsVisible: { false }, salaryType: { nil }, language: { "en" }))
    }

    @Test("The first hours edit seeds and overrides in one durable commit; identical edits write nothing")
    func firstEditIsOneCommit() async throws {
        let suite = "RecordsActionBatch.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "record-action-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let records = RecordCoordinator(fileURL: file)
        let actions = actions(defaults: defaults, records: records)
        try await records.flush()
        let writes = records.archiveWriteCount
        let revision = records.historyRevision
        var publications = 0
        records.onDirty = { publications += 1 }

        #expect(actions.saveCustomHours(dayKey: "2026-09-07", startMinutes: 8 * 60, endMinutes: 18 * 60).synchronousResult)
        try await records.flush()
        #expect(records.archiveWriteCount == writes + 1)
        #expect(records.historyRevision == revision + 1)
        #expect(publications == 1)
        #expect(records.state.periods.count == 1)
        #expect(records.state.snapshots.count == 1)
        #expect(records.state.overrides.first?.segments.count == 2) // Existing lunch gap is preserved.
        let saved = records.state

        #expect(actions.saveCustomHours(dayKey: "2026-09-07", startMinutes: 8 * 60, endMinutes: 18 * 60).synchronousResult)
        try await records.flush()
        #expect(records.state == saved)
        #expect(records.archiveWriteCount == writes + 1)
        #expect(publications == 1)
        let reopened = RecordCoordinator(fileURL: file)
        #expect(reopened.state.overrides.count == 1)
        let restored = try #require(reopened.state.overrides.first)
        let original = try #require(saved.overrides.first)
        #expect(RecordIncomingValue.override(restored).hasSameBusinessContent(as: .override(original)))
        #expect(restored.editCount == original.editCount)
        #expect(restored.editTieBreaker == original.editTieBreaker)
        // The existing JSON contract stores epoch milliseconds. Its Double
        // conversion need not retain sub-millisecond Date binary precision.
        #expect(abs(restored.editedAt.timeIntervalSince(original.editedAt)) < 0.001)
        #expect(reopened.state.snapshots == saved.snapshots)
    }

    @Test("Invalid dates, minutes, or expired access cannot seed or mutate history")
    func rejectedEditsLeaveHistoryUntouched() throws {
        let suite = "RecordsActionAdmission.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = RecordCoordinator.inMemory()
        let actions = actions(defaults: defaults, records: records)
        let original = records.state
        #expect(!actions.saveCustomHours(dayKey: "2026-09-07", startMinutes: -1, endMinutes: 17 * 60).synchronousResult)
        #expect(!actions.saveCustomHours(dayKey: "2026-09-07", startMinutes: 9 * 60, endMinutes: 1440).synchronousResult)
        #expect(!actions.applyDayWrite(.rest, dayKey: "2026-02-30").synchronousResult)
        actions.plus.debugSetAuthorized(false)
        for write: DayRecordWrite in [.customHours, .confirmed, .leave, .rest, .makeup] {
            #expect(!actions.applyDayWrite(write, dayKey: "2026-09-07").synchronousResult)
        }
        #expect(!actions.clearDayOverride(dayKey: "2026-09-07").synchronousResult)
        #expect(records.state == original)
    }

    @Test("Archive protection rejects edits; a normal write failure keeps them editable")
    func archiveAdmission() async throws {
        let suite = "RecordsActionProtection.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "record-protection-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("damaged".utf8).write(to: file)
        let protected = RecordCoordinator(fileURL: file)
        let protectedActions = actions(defaults: defaults, records: protected)
        let original = protected.state
        #expect(!protectedActions.applyDayWrite(.customHours, dayKey: "2026-09-07").synchronousResult)
        #expect(!protectedActions.clearDayOverride(dayKey: "2026-09-07").synchronousResult)
        #expect(protected.state == original)
        #expect(try Data(contentsOf: file) == Data("damaged".utf8))

        try FileManager.default.removeItem(at: file)
        let failed = RecordCoordinator(fileURL: file, prepareArchive: { _, _ in throw RecordPersistenceError.writeFailed })
        let failedActions = actions(defaults: defaults, records: failed)
        #expect(failedActions.applyDayWrite(.leave, dayKey: "2026-09-07").synchronousResult)
        await #expect(throws: RecordPersistenceError.writeFailed) { try await failed.flush() }
        #expect(failedActions.applyDayWrite(.rest, dayKey: "2026-09-07").synchronousResult)
        await #expect(throws: RecordPersistenceError.writeFailed) { try await failed.flush() }
        #expect(failed.state.exceptions.first?.effect == .rest)
    }

    @Test("Scenes retain independent drafts across archive refresh and repeated presentation")
    func sceneDraftLifetime() throws {
        let suite = "RecordEditorScene.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = actions(defaults: defaults, records: .inMemory())
        let queries = queries(actions: actions)
        let first = SceneState()
        let second = SceneState()
        first.openDayEditor(dayKey: "2026-09-07", actions: actions, queries: queries)
        second.openDayEditor(dayKey: "2026-09-07", actions: actions, queries: queries)
        let draft = try #require(first.dayEditor)
        let other = try #require(second.dayEditor)
        #expect(draft !== other)
        let originalSubmission = draft.submission
        draft.startMinutes = 7 * 60
        draft.pendingKind = .restDay
        draft.confirmsDiscard = true
        #expect(actions.applyDayWrite(.leave, dayKey: draft.dayKey).synchronousResult)
        first.openDayEditor(dayKey: draft.dayKey, actions: actions, queries: queries)
        #expect(first.dayEditor === draft)
        #expect(draft.startMinutes == 7 * 60)
        #expect(draft.pendingKind == .restDay)
        #expect(draft.confirmsDiscard)
        #expect(other.startMinutes == 9 * 60)
        draft.startMinutes = originalSubmission.startMinutes
        #expect(!draft.stillMatches(originalSubmission))
        draft.startMinutes = 7 * 60
        actions.plus.debugSetAuthorized(false)
        #expect(!actions.applyDayWrite(draft.kind.write, dayKey: draft.dayKey,
            startMinutes: draft.startMinutes, endMinutes: draft.endMinutes).synchronousResult)
        #expect(first.dayEditor === draft)
        #expect(draft.hasChanges)
        first.dayEditor = nil
        #expect(second.dayEditor === other)
    }
}
