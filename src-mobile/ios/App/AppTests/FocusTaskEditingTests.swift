import Foundation
import Testing
@testable import App

@MainActor
@Suite("Focus task editing and template linkage")
struct FocusTaskEditingTests {
    private func fixture() throws -> (AppRuntime, Date) {
        let defaults = try #require(UserDefaults(suiteName: "FocusEditing.\(UUID())"))
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        store.plus.debugSetAuthorized(true)
        store.preferences.onboardingComplete = true
        store.preferences.applyPreferences { $0.startMinutes = 540 }
        store.preferences.applyPreferences { $0.endMinutes = 1020 }
        store.preferences.applyPreferences { $0.lunchEnabled = true }
        let date = try #require(store.preferences.recordsCalendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9, minute: 5)))
        return (store, date)
    }

    private func template(_ store: AppRuntime, at date: Date) throws -> FocusTemplate {
        let block = try #require(store.focus.focusTemplateBlocks(at: date).first { $0.kind == .task })
        return try #require(store.focus.saveFocusTemplate(name: "Daily", slots: [
            .init(blockIndex: block.index, kind: .task, taskKey: UUID(), taskTitle: "Original", taskIcon: .work)
        ]).synchronousResult)
    }

    @Test("An attached plan follows template edits; a manually edited plan does not")
    func templateUpdatesStopAfterManualEdit() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.focus.applyFocusTemplate(original, at: at).synchronousResult)
        let id = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.isAssigned }?.taskID)
        var slots = original.slots
        slots[0].taskTitle = "Updated template"
        slots[0].taskIcon = .study
        #expect(store.focus.updateFocusTemplate(original, name: "Renamed", slots: slots, at: at).synchronousResult)
        #expect(store.focus.appliedFocusTemplate(at: at)?.name == "Renamed")
        let task = try #require(store.records.state.focusTasks.first { $0.id == id })
        #expect(task.title == "Updated template")
        #expect(task.icon == .study)
        #expect(store.focus.editFocusTask(task, title: "Only today", icon: .code, pomodoros: 2, isFavorite: true, at: at).synchronousResult)
        #expect(store.focus.appliedFocusTemplate(at: at) == nil)
        #expect(store.focus.focusDayCanvas(at: at).blocks.count { $0.taskID == id } == 2)
        #expect(store.focus.savedFocusFavorite(title: "Only today", icon: .code)?.estimatedPomodoros == 2)
        slots[0].taskTitle = "Another template edit"
        #expect(store.focus.updateFocusTemplate(original, name: "Renamed again", slots: slots, at: at).synchronousResult)
        #expect(store.focus.focusDayCanvas(at: at).blocks.filter { $0.taskID == id }.allSatisfy { $0.taskTitle == "Only today" })
    }

    @Test("Editing a usual-day template after clock-off preserves tomorrow's linked tasks")
    func tomorrowTemplateEditKeepsTasks() throws {
        let (store, morning) = try fixture()
        let at = morning.addingTimeInterval(14 * 3_600)
        let original = try template(store, at: at)
        #expect(store.focus.focusDayCanvas(at: at).isNextShift)
        #expect(store.focus.applyFocusTemplate(original, at: at).synchronousResult)
        let originalDay = store.focus.focusDayCanvas(at: at).dayKey
        let id = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.isAssigned }?.taskID)
        var tasks = original.tasks
        tasks[0].pomodoros = 2
        tasks[0].title = "Updated tomorrow"
        tasks[0].icon = .study
        #expect(store.focus.updateFocusTemplate(original, name: "Tomorrow edited", slots: FocusTemplate.slots(from: tasks), at: at).synchronousResult)
        let canvas = store.focus.focusDayCanvas(at: at)
        #expect(canvas.dayKey == originalDay)
        #expect(canvas.blocks.count { $0.taskID == id } == 2)
        #expect(canvas.blocks.filter { $0.taskID == id }.allSatisfy { $0.taskTitle == "Updated tomorrow" })
        #expect(store.focus.appliedFocusTemplate(at: at)?.id == original.id)
        #expect(store.focus.applyDefaultFocusTemplateIfNeeded(at: at).synchronousResult == false)
        #expect(store.focus.focusDayCanvas(at: at).blocks.count { $0.taskID == id } == 2)
    }

    @Test("Deleting an assigned task detaches the day")
    func deletionDetachesTemplate() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.focus.applyFocusTemplate(original, at: at).synchronousResult)
        let id = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.isAssigned }?.taskID)
        let task = try #require(store.records.state.focusTasks.first { $0.id == id })
        #expect(store.focus.deleteFocusTask(task, at: at).synchronousResult)
        #expect(store.focus.appliedFocusTemplate(at: at) == nil)
        #expect(store.focus.updateFocusTemplate(original, name: "Updated", slots: original.slots, at: at).synchronousResult)
        #expect(!store.focus.focusDayCanvas(at: at).blocks.contains { $0.isAssigned })
    }

    @Test("Adding a manual task detaches the day, while saving a library favorite does not")
    func manualCreationVersusFavoriteOnly() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.focus.applyFocusTemplate(original, at: at).synchronousResult)
        store.focus.saveFocusFavorite(title: "For later", pomodoros: 3, icon: .study).synchronousResult
        #expect(store.focus.appliedFocusTemplate(at: at)?.id == original.id)
        let favorite = try #require(store.focus.savedFocusFavorite(title: "For later", icon: .study))
        #expect(favorite.plannedForDate == nil)
        _ = store.focus.createFocusTaskInNextEmptyBlock(title: "Extra", at: at).synchronousResult
        #expect(store.focus.appliedFocusTemplate(at: at) == nil)
    }

    @Test("Clearing a day preserves completed sessions and prevents automatic template reapplication")
    func clearPreservesHistory() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        store.focus.setDefaultFocusTemplate(original).synchronousResult
        #expect(store.focus.applyFocusTemplate(original, at: at).synchronousResult)
        let block = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.isAssigned })
        let taskID = try #require(block.taskID)
        let start = Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)
        let end = Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000)
        let session = FocusSession(id: UUID(), taskID: taskID, shiftAnchorDate: start,
            startedAt: start, plannedEndAt: end, endedAt: end, endReason: .completed,
            editedAt: end, editCount: 0, editTieBreaker: UUID())
        store.records.upsertFocusSession(session)
        let history = store.records.state.focusSessions
        store.focus.clearFocusDay(at: end).synchronousResult
        #expect(store.records.state.focusSessions == history)
        #expect(!store.focus.focusDayCanvas(at: end).blocks.contains { $0.isAssigned })
        #expect(!store.focus.applyDefaultFocusTemplateIfNeeded(at: end).synchronousResult)
        #expect(store.focus.focusPlanAssignments(for: try #require(store.session.snapshot(at: end))).isEmpty)
        #expect(store.focus.focusPlanning.templates.contains { $0.id == original.id })
    }

    @Test("Template refresh preserves past assignments and updates future ones")
    func templateRefreshPreservesPast() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.focus.applyFocusTemplate(original, at: at).synchronousResult)
        let before = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.isAssigned })
        let later = at.addingTimeInterval(60 * 60)
        let future = try #require(store.focus.focusTemplateBlocks(at: later).first { $0.kind == .task && $0.start > later })
        let slots = store.focus.focusTemplateBlocks(at: later).filter { $0.kind == .task && $0.index <= future.index }.map {
            FocusTemplateSlot(blockIndex: $0.index, kind: .task, taskKey: UUID(), taskTitle: "Future", taskIcon: .code)
        }
        #expect(store.focus.updateFocusTemplate(original, name: "Future plan", slots: slots, at: later).synchronousResult)
        let canvas = store.focus.focusDayCanvas(at: later)
        #expect(canvas.blocks.first { $0.startAtMs == before.startAtMs }?.taskID == before.taskID)
        #expect(canvas.blocks.first { $0.startAtMs == future.startAtMs }?.taskTitle == "Future")
    }

    @Test("Resizing skips another task and shrinking releases only this task’s extra slots")
    func resizingPreservesOtherTasks() throws {
        let (store, at) = try fixture()
        let first = store.focus.createFocusTaskInNextEmptyBlock(title: "First", at: at).synchronousResult
        guard case .placed(let id, _) = first else { Issue.record("Expected placement"); return }
        let other = store.focus.createFocusTaskInNextEmptyBlock(title: "Other", at: at).synchronousResult
        guard case .placed(let otherID, let otherStart) = other else { Issue.record("Expected another placement"); return }
        let task = try #require(store.records.state.focusTasks.first { $0.id == id })
        #expect(store.focus.editFocusTask(task, title: "First", icon: .work, pomodoros: 2, isFavorite: false, at: at).synchronousResult)
        let expanded = store.focus.focusDayCanvas(at: at)
        #expect(expanded.blocks.count { $0.taskID == id } == 2)
        #expect(expanded.blocks.first { $0.startAtMs == otherStart }?.taskID == otherID)
        #expect(store.focus.editFocusTask(task, title: "First", icon: .work, pomodoros: 1, isFavorite: false, at: at).synchronousResult)
        #expect(store.focus.focusDayCanvas(at: at).blocks.count { $0.taskID == id } == 1)
        #expect(store.focus.focusDayCanvas(at: at).blocks.first { $0.startAtMs == otherStart }?.taskID == otherID)
    }

    @Test("Template changes preserve the running round and clearing stops it without erasing history")
    func runningRoundSurvivesTemplateRefresh() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.focus.applyFocusTemplate(original, at: at).synchronousResult)
        let block = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.isAssigned })
        let taskID = try #require(block.taskID)
        let end = Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000)
        let session = FocusSession(id: UUID(), taskID: taskID,
            shiftAnchorDate: Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000),
            startedAt: at, plannedEndAt: end, endedAt: nil, endReason: nil,
            editedAt: at, editCount: 0, editTieBreaker: UUID())
        store.records.upsertFocusSession(session)
        let next = try #require(store.focus.focusTemplateBlocks(at: at).first { $0.kind == .task && $0.start >= end })
        var slots = original.slots
        slots.append(.init(blockIndex: next.index, kind: .task, taskKey: original.slots[0].taskKey,
                           taskTitle: "Updated", taskIcon: .code))
        #expect(store.focus.updateFocusTemplate(original, name: "Updated", slots: slots, at: at).synchronousResult)
        #expect(store.focus.activeFocusSession()?.id == session.id)
        #expect(store.focus.focusDayCanvas(at: at).blocks.first { $0.startAtMs == block.startAtMs }?.taskID == taskID)
        store.focus.clearFocusDay(at: at.addingTimeInterval(60)).synchronousResult
        #expect(store.focus.activeFocusSession() == nil)
        #expect(store.records.state.focusSessions.first { $0.id == session.id }?.endReason == .stoppedByUser)
        #expect(!store.focus.focusDayCanvas(at: at).blocks.contains { $0.isAssigned })
    }

    @Test("Clearing the displayed day keeps another day’s tasks")
    func clearingDoesNotTouchAnotherDay() throws {
        let (store, at) = try fixture()
        _ = store.focus.createFocusTaskInNextEmptyBlock(title: "Today", at: at).synchronousResult
        let later = at.addingTimeInterval(12 * 3600)
        let result = store.focus.createFocusTaskInNextEmptyBlock(title: "Tomorrow", at: later).synchronousResult
        guard case .placed(let nextID, _) = result else { Issue.record("Expected tomorrow placement"); return }
        store.focus.clearFocusDay(at: at).synchronousResult
        #expect(store.records.state.focusTasks.first { $0.id == nextID }?.deletedAt == nil)
        #expect(store.focus.focusDayCanvas(at: later).blocks.contains { $0.taskID == nextID })
    }

    @Test("Work-time eligibility distinguishes working time from lunch and clock-off")
    func startEligibilityExplainsOutsideHours() throws {
        let (store, at) = try fixture()
        #expect(store.focus.isWithinFocusWorkTime(at: at))
        #expect(!store.focus.isWithinFocusWorkTime(at: at.addingTimeInterval(-2 * 3600)))
        #expect(!store.focus.isWithinFocusWorkTime(at: at.addingTimeInterval(12 * 3600)))
        #expect(!store.focus.isWithinFocusWorkTime(at: at.addingTimeInterval(3 * 3600)))
    }
    @Test("Legacy task indices never become recovery blocks after a lunch-grid change")
    func legacySlotsFollowTaskOrder() throws {
        let (store, at) = try fixture()
        let key = UUID()
        let legacy = FocusTemplate(id: UUID(), name: "Legacy", slots: [
            .init(blockIndex: 0, kind: .task, taskKey: key, taskTitle: "Morning", taskIcon: .work),
            .init(blockIndex: 1, kind: .breakTime),
            .init(blockIndex: 13, kind: .task, taskKey: UUID(), taskTitle: "Afternoon", taskIcon: .study)
        ], createdAt: at, updatedAt: at)
        let blocks = store.focus.focusTemplateBlocks(at: at)
        let placed = legacy.placedSlots(in: blocks)
        #expect(placed.map(\.taskTitle) == ["Morning", "Afternoon"])
        #expect(placed.allSatisfy { blocks[$0.blockIndex].kind == .task })
        #expect(legacy.slots[2].blockIndex == 13)
    }

    @Test("Short shifts omit whole tail tasks without deleting or skipping ahead in the template")
    func wholeTaskPrefixFits() throws {
        let (store, at) = try fixture()
        let tasks = [
            FocusTemplateTask(taskKey: UUID(), legacyIndex: 0, title: "First", icon: .work, pomodoros: 2),
            FocusTemplateTask(taskKey: UUID(), legacyIndex: 1, title: "Second", icon: .study, pomodoros: 2),
            FocusTemplateTask(taskKey: UUID(), legacyIndex: 2, title: "Third", icon: .code, pomodoros: 1)
        ]
        let template = try #require(store.focus.saveFocusTemplate(name: "Full day", slots: FocusTemplate.slots(from: tasks)).synchronousResult)
        let blocks = Array(store.focus.focusTemplateBlocks(at: at).prefix(6))
        #expect(blocks.count { $0.kind == .task } == 3)
        #expect(template.placedSlots(in: blocks).map(\.taskTitle) == ["First", "First"])
        #expect(template.tasks.map(\.pomodoros) == [2, 2, 1])
    }

    @Test("Changing hours refills attached plans and leaves manually detached plans alone")
    func changedHoursRefillAttachedPlans() throws {
        let (store, morning) = try fixture()
        let at = morning.addingTimeInterval(-2 * 3600)
        let original = try template(store, at: at)
        #expect(store.focus.applyFocusTemplate(original, at: at).synchronousResult)
        let oldStart = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.isAssigned }?.startAtMs)
        store.shifts.applyScheduleChange(.init(startMinutes: 600, endMinutes: 1080), decision: .applyToToday, at: at)
        let canvas = store.focus.focusDayCanvas(at: at)
        let assigned = try #require(canvas.blocks.first { $0.isAssigned })
        #expect(assigned.startAtMs == oldStart + 3_600_000)
        #expect(assigned.taskTitle == "Original")
        let task = try #require(store.records.state.focusTasks.first { $0.id == assigned.taskID })
        #expect(store.focus.editFocusTask(task, title: "Manual", icon: .code, pomodoros: 1, isFavorite: false, at: at).synchronousResult)
        let saved = store.focus.focusPlanning.plans[canvas.dayKey]
        store.shifts.applyScheduleChange(.init(endMinutes: 1140), decision: .applyToToday, at: at)
        #expect(store.focus.focusPlanning.plans[canvas.dayKey] == saved)
    }

    @Test("Overtime restores omitted tail tasks from the unchanged linked template")
    func overtimeRestoresTail() throws {
        let (store, morning) = try fixture()
        store.preferences.applyPreferences { $0.lunchEnabled = false }
        store.preferences.applyPreferences { $0.endMinutes = 600 }
        let at = morning.addingTimeInterval(-2 * 3600)
        let tasks = (0..<4).map {
            FocusTemplateTask(taskKey: UUID(), legacyIndex: $0, title: "Task \($0)", icon: .work, pomodoros: 1)
        }
        let template = try #require(store.focus.saveFocusTemplate(name: "Longer", slots: FocusTemplate.slots(from: tasks)).synchronousResult)
        #expect(store.focus.applyFocusTemplate(template, at: at).synchronousResult)
        #expect(store.focus.focusDayCanvas(at: at).blocks.count { $0.isAssigned } == 2)
        let end = try #require(store.preferences.recordsCalendar.date(bySettingHour: 12, minute: 0, second: 0, of: morning))
        store.shifts.applyOvertime(date: end, declaredAt: morning)
        #expect(store.focus.focusDayCanvas(at: morning).blocks.count { $0.isAssigned } == 4)
        #expect(store.focus.focusPlanning.templates.first { $0.id == template.id } == template)
    }

    @Test("Applying a template persists all tasks and their sync outbox in one archive write")
    func templateApplicationBatchesDurableWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "archive.json")
        let records = RecordCoordinator(fileURL: file)
        let store = AppRuntime(defaults: try #require(UserDefaults(suiteName: "FocusBatch.\(UUID())")), records: records)
        store.plus.debugSetAuthorized(true)
        store.preferences.onboardingComplete = true
        store.preferences.applyPreferences { $0.startMinutes = 540 }
        store.preferences.applyPreferences { $0.endMinutes = 1080 }
        let at = try #require(store.preferences.recordsCalendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 8)))
        let tasks = (0..<10).map {
            FocusTemplateTask(taskKey: UUID(), legacyIndex: $0, title: "Task \($0)", icon: .work, pomodoros: 1)
        }
        let template = try #require(store.focus.saveFocusTemplate(name: "Ten tasks", slots: FocusTemplate.slots(from: tasks)).synchronousResult)
        try await records.flush()
        let before = records.revision
        let writesBefore = records.archiveWriteCount
        var notifications = 0
        records.onDirty = { notifications += 1 }
        #expect(store.focus.applyFocusTemplate(template, at: at).synchronousResult)
        #expect(records.revision == before + 1)
        try await records.flush()
        #expect(records.archiveWriteCount == writesBefore + 1)
        #expect(notifications == 1)
        let restored = RecordCoordinator(fileURL: file)
        #expect(restored.persistenceError == nil)
        #expect(restored.state.focusTasks.count == records.state.focusTasks.count)
        for var expected in records.state.focusTasks {
            let actual = try #require(restored.state.focusTasks.first { $0.id == expected.id })
            // The archive contract uses millisecond timestamps.
            #expect(abs(actual.createdAt.timeIntervalSince(expected.createdAt)) < 0.002)
            #expect(abs(actual.editedAt.timeIntervalSince(expected.editedAt)) < 0.002)
            expected.createdAt = actual.createdAt
            expected.editedAt = actual.editedAt
            #expect(actual == expected)
        }
        #expect(restored.state.sync == records.state.sync)
        #expect(restored.state.focusTasks.count == 10)
    }

    @Test("A shift shorter than one round clears linked assignments but retains the template")
    func zeroCapacityStillReflows() throws {
        let (store, morning) = try fixture()
        let at = morning.addingTimeInterval(-2 * 3600)
        let original = try template(store, at: at)
        #expect(store.focus.applyFocusTemplate(original, at: at).synchronousResult)
        let key = store.focus.focusDayCanvas(at: at).dayKey
        store.shifts.applyScheduleChange(.init(endMinutes: 550), decision: .applyToToday, at: at)
        #expect(store.focus.focusPlanning.plans[key]?.assignments.isEmpty == true)
        #expect(store.focus.focusPlanning.plans[key]?.appliedTemplateID == original.id)
        #expect(store.focus.focusPlanning.templates.first { $0.id == original.id } == original)
    }

    @Test("Remaining template capacity counts all tasks and excludes the task being edited")
    func remainingCapacity() throws {
        let (store, at) = try fixture()
        let blocks = Array(store.focus.focusTemplateBlocks(at: at).prefix(6))
        let first = FocusTemplateTask(taskKey: UUID(), legacyIndex: 0, title: "First", icon: .work, pomodoros: 2)
        let second = FocusTemplateTask(taskKey: UUID(), legacyIndex: 1, title: "Second", icon: .study, pomodoros: 1)
        #expect(FocusTemplate.remainingPomodoros([first], in: blocks) == 1)
        #expect(FocusTemplate.remainingPomodoros([first, second], in: blocks) == 0)
        #expect(FocusTemplate.remainingPomodoros([first, second], in: blocks, excluding: first.id) == 2)
        var oversized = first
        oversized.pomodoros = 10
        #expect(FocusTemplate.remainingPomodoros([oversized, second], in: blocks) == 0)
        #expect(FocusTemplate.remainingPomodoros([oversized, second], in: blocks, excluding: oversized.id) == 2)
        #expect(oversized.pomodoros == 10)
    }

}
