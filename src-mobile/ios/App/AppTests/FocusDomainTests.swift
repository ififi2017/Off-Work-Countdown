import Foundation
import Testing
@testable import App

@MainActor
@Suite("Focus domain without an application or scene")
struct FocusDomainTests {
    /// These cases need no shift rules. A missing shift must still allow
    /// configuration, task history and an already-recorded timer to work.
    private func focus(records: RecordCoordinator, defaults: UserDefaults, shift: NativeShiftSnapshot? = nil) -> FocusStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let plus = PlusEntitlement(defaults: defaults)
        plus.debugSetAuthorized(true)
        return FocusStore(records: records, defaults: defaults,
            plus: plus, sources: .init(
                calendar: { calendar }, snapshot: { _ in shift },
                scheduleEnabled: { _ in shift != nil }, shouldQuerySnapshot: { _ in shift != nil },
                isWorkday: { shift, _ in shift.isWorkday }, overtimeEnd: { nil }, microBreakEnabled: { false },
                text: { key, _ in key }, count: { String($0) },
                time: { $0.formatted(date: .omitted, time: .shortened) }
            ))
    }

    @Test("Creating a multi-block plan, renaming its task and clearing the day each save once")
    func planningBatches() async throws {
        let suite = "FocusDomainPlanning.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "focus-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let records = RecordCoordinator(fileURL: file)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        // The production TypeScript bundle supplies the shift; this test only
        // exercises the Focus action and its archive boundary.
        let shift = try CountdownRules.shared.snapshot(input: NativeRulesInput(
            startTime: "09:00", endTime: "17:00", nowMs: date.timeIntervalSince1970 * 1_000,
            workdays: [1, 2, 3, 4, 5],
            schedule: NativeWorkSchedule(mode: "classic", referenceWeekStartMs: nil,
                referenceWeekType: nil, singleWeekendWorkday: nil, rotationAnchorMs: nil,
                rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: nil, breakDurationMinutes: 0, overtimeEndAtMs: nil,
            salaryAmount: "", salaryType: "monthly", monthlyWorkingDays: 22,
            annualBonusMonths: 0, forcedWorkdayStartMs: nil, timeZoneIdentifier: "UTC"))
        let model = focus(records: records, defaults: defaults, shift: shift)
        var changes = 0
        records.onDirty = { changes += 1 }
        let result = model.createFocusTaskInNextEmptyBlock(title: "Draft", pomodoros: 3,
            scheduleAllPomodoros: true, at: date).synchronousResult
        guard case .placed(let taskID, _) = result else {
            Issue.record("Expected three blocks to be placed, got \(result)")
            return
        }
        try await records.flush()
        #expect(records.archiveWriteCount == 1)
        #expect(changes == 1)
        #expect(model.focusDayCanvas(at: date).blocks.filter { $0.taskID == taskID }.count == 3)
        let task = try #require(records.state.focusTasks.first { $0.id == taskID })
        #expect(model.editFocusTask(task, title: "Reviewed draft", icon: task.icon,
            pomodoros: 3, isFavorite: true, at: date).synchronousResult)
        try await records.flush()
        #expect(records.archiveWriteCount == 2)
        #expect(changes == 2)
        #expect(model.savedFocusFavorite(title: "Reviewed draft", icon: task.icon) != nil)
        #expect(model.focusDayCanvas(at: date).blocks.filter { $0.taskID == taskID }
            .allSatisfy { $0.taskTitle == "Reviewed draft" })
        model.clearFocusDay(at: date).synchronousResult
        try await records.flush()
        #expect(records.archiveWriteCount == 3)
        #expect(changes == 3)
        #expect(model.focusDayCanvas(at: date).blocks.allSatisfy { !$0.hasAssignment })
        #expect(model.savedFocusFavorite(title: "Reviewed draft", icon: task.icon) != nil)
    }

    @Test("Legacy Focus preferences migrate once; the archive wins on reopening")
    func legacyConfiguration() throws {
        let suite = "FocusDomainLegacy.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = FocusTimerSettings(focusMinutes: 40)
        defaults.set(try JSONEncoder().encode(legacy), forKey: "ios.native.focusTimerSettings.v1")
        defaults.set(false, forKey: "ios.native.focusNotificationsEnabled")
        let records = RecordCoordinator.inMemory()
        let first = focus(records: records, defaults: defaults)
        #expect(first.focusTimerSettings == legacy)
        #expect(!first.focusNotificationsEnabled)
        #expect(records.state.focusPlanningConfiguration?.timerSettings == legacy)
        let committed = records.state
        let revision = records.revision

        defaults.set(try JSONEncoder().encode(FocusTimerSettings.default), forKey: "ios.native.focusTimerSettings.v1")
        let reopened = focus(records: records, defaults: defaults)
        #expect(reopened.focusTimerSettings == legacy)
        #expect(records.state == committed)
        #expect(records.revision == revision)
        let mirrored = try #require(defaults.data(forKey: "ios.native.focusTimerSettings.v1"))
        #expect(try JSONDecoder().decode(FocusTimerSettings.self, from: mirrored) == legacy)
    }

    @Test("An unchanged Focus setting produces no archive write or invalidation")
    func unchangedConfiguration() async throws {
        let suite = "FocusDomainWrites.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "focus-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let records = RecordCoordinator(fileURL: file)
        let model = focus(records: records, defaults: defaults)
        #expect(model.updateFocusTimerSettings(.default).synchronousResult)
        try await records.flush()
        #expect(records.archiveWriteCount == 0)

        let changed = FocusTimerSettings(focusMinutes: 35)
        #expect(model.updateFocusTimerSettings(changed).synchronousResult)
        try await records.flush()
        #expect(records.archiveWriteCount == 1)
        let committed = records.state
        let revision = model.focusPlanningRevision
        #expect(model.updateFocusTimerSettings(changed).synchronousResult)
        model.persistFocusPlanning()
        try await records.flush()
        #expect(records.archiveWriteCount == 1)
        #expect(records.state == committed)
        #expect(model.focusPlanningRevision == revision)
    }

    @Test("Saving an unchanged template preserves its edit stamp and outbox")
    func unchangedTemplate() throws {
        let suite = "FocusDomainTemplate.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = RecordCoordinator.inMemory()
        let model = focus(records: records, defaults: defaults)
        let slots = [FocusTemplateSlot(blockIndex: 0, kind: .task, taskKey: UUID(),
            taskTitle: "Writing", taskIcon: .focus)]
        let template = try #require(model.saveFocusTemplate(name: "Morning", slots: slots).synchronousResult)
        let committed = records.state
        let revision = model.focusPlanningRevision
        #expect(model.updateFocusTemplate(template, name: template.name, slots: template.slots,
            at: template.updatedAt.addingTimeInterval(60)).synchronousResult)
        #expect(records.state == committed)
        #expect(model.focusPlanningRevision == revision)
        #expect(model.updateFocusTemplate(template, name: "Afternoon", slots: template.slots,
            at: template.updatedAt.addingTimeInterval(120)).synchronousResult)
        #expect(model.focusPlanningRevision == revision + 1)
        #expect(model.focusPlanning.templates.first?.name == "Afternoon")
    }

    @Test("A restored Focus timer completes its task once without a page or shift snapshot")
    func restoredCompletion() async throws {
        let suite = "FocusDomainCompletion.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "ios.native.focusNotificationsEnabled")
        let file = FileManager.default.temporaryDirectory.appending(path: "focus-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let records = RecordCoordinator(fileURL: file)
        let model = focus(records: records, defaults: defaults)
        let start = try #require(model.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        let end = start.addingTimeInterval(25 * 60)
        let task = model.addFocusTaskAuthorized(title: "Finish draft", pomodoros: 1, plannedFor: start).synchronousResult
        let session = FocusSession(id: UUID(), taskID: task.id, shiftAnchorDate: start,
            startedAt: start, plannedEndAt: end, editedAt: start, editCount: 0,
            editTieBreaker: UUID(), timeZoneIdentifier: "UTC", plannedEndReason: .completed)
        records.upsertFocusSession(session)
        try await records.flush()
        let writes = records.archiveWriteCount
        var changes = 0
        records.onDirty = { changes += 1 }

        #expect(model.finishElapsedFocusSession(at: end.addingTimeInterval(60)).synchronousResult)
        try await records.flush()
        #expect(records.archiveWriteCount == writes + 1)
        #expect(changes == 1)
        #expect(model.activeFocusSession() == nil)
        #expect(records.state.focusTasks.first?.completedAt == end)
        #expect(records.state.focusSessions.first?.endedAt == end)
        #expect(records.state.focusSessions.first?.endReason == .completed)
        #expect(!model.finishElapsedFocusSession(at: end.addingTimeInterval(120)).synchronousResult)
        try await records.flush()
        #expect(records.archiveWriteCount == writes + 1)
        #expect(changes == 1)
    }
}
