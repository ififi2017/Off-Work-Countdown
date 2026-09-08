import Foundation
import Testing
@testable import App

@MainActor
@Suite("Focus task editing and template linkage")
struct FocusTaskEditingTests {
    private func fixture() throws -> (OffWorkStore, Date) {
        let defaults = try #require(UserDefaults(suiteName: "FocusEditing.\(UUID())"))
        let store = OffWorkStore(defaults: defaults, records: .inMemory())
        store.plus.debugSetAuthorized(true)
        store.onboardingComplete = true
        store.startMinutes = 540
        store.endMinutes = 1020
        store.lunchEnabled = true
        let date = try #require(store.recordsCalendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9, minute: 5)))
        return (store, date)
    }

    private func template(_ store: OffWorkStore, at date: Date) throws -> FocusTemplate {
        let block = try #require(store.focusTemplateBlocks(at: date).first { $0.kind == .task })
        return try #require(store.saveFocusTemplate(name: "Daily", slots: [
            .init(blockIndex: block.index, kind: .task, taskKey: UUID(), taskTitle: "Original", taskIcon: .work)
        ]))
    }

    @Test("An attached plan follows template edits; a manually edited plan does not")
    func templateUpdatesStopAfterManualEdit() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.applyFocusTemplate(original, at: at))
        let id = try #require(store.focusDayCanvas(at: at).blocks.first { $0.isAssigned }?.taskID)
        var slots = original.slots
        slots[0].taskTitle = "Updated template"
        slots[0].taskIcon = .study
        #expect(store.updateFocusTemplate(original, name: "Renamed", slots: slots, at: at))
        #expect(store.appliedFocusTemplate(at: at)?.name == "Renamed")
        let task = try #require(store.records.state.focusTasks.first { $0.id == id })
        #expect(task.title == "Updated template")
        #expect(task.icon == .study)
        #expect(store.editFocusTask(task, title: "Only today", icon: .code, pomodoros: 2, isFavorite: true, at: at))
        #expect(store.appliedFocusTemplate(at: at) == nil)
        #expect(store.focusDayCanvas(at: at).blocks.count { $0.taskID == id } == 2)
        #expect(store.savedFocusFavorite(title: "Only today", icon: .code)?.estimatedPomodoros == 2)
        slots[0].taskTitle = "Another template edit"
        #expect(store.updateFocusTemplate(original, name: "Renamed again", slots: slots, at: at))
        #expect(store.focusDayCanvas(at: at).blocks.filter { $0.taskID == id }.allSatisfy { $0.taskTitle == "Only today" })
    }

    @Test("Deleting an assigned task detaches the day")
    func deletionDetachesTemplate() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.applyFocusTemplate(original, at: at))
        let id = try #require(store.focusDayCanvas(at: at).blocks.first { $0.isAssigned }?.taskID)
        let task = try #require(store.records.state.focusTasks.first { $0.id == id })
        #expect(store.deleteFocusTask(task, at: at))
        #expect(store.appliedFocusTemplate(at: at) == nil)
        #expect(store.updateFocusTemplate(original, name: "Updated", slots: original.slots, at: at))
        #expect(!store.focusDayCanvas(at: at).blocks.contains { $0.isAssigned })
    }

    @Test("Adding a manual task detaches the day, while saving a library favorite does not")
    func manualCreationVersusFavoriteOnly() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.applyFocusTemplate(original, at: at))
        store.saveFocusFavorite(title: "For later", pomodoros: 3, icon: .study)
        #expect(store.appliedFocusTemplate(at: at)?.id == original.id)
        let favorite = try #require(store.savedFocusFavorite(title: "For later", icon: .study))
        #expect(favorite.plannedForDate == nil)
        _ = store.createFocusTaskInNextEmptyBlock(title: "Extra", at: at)
        #expect(store.appliedFocusTemplate(at: at) == nil)
    }

    @Test("Clearing a day preserves completed sessions and prevents automatic template reapplication")
    func clearPreservesHistory() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        store.setDefaultFocusTemplate(original)
        #expect(store.applyFocusTemplate(original, at: at))
        let block = try #require(store.focusDayCanvas(at: at).blocks.first { $0.isAssigned })
        let taskID = try #require(block.taskID)
        let start = Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)
        let end = Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000)
        let session = FocusSession(id: UUID(), taskID: taskID, shiftAnchorDate: start,
            startedAt: start, plannedEndAt: end, endedAt: end, endReason: .completed,
            editedAt: end, editCount: 0, editTieBreaker: UUID())
        store.records.upsertFocusSession(session)
        let history = store.records.state.focusSessions
        store.clearFocusDay(at: end)
        #expect(store.records.state.focusSessions == history)
        #expect(!store.focusDayCanvas(at: end).blocks.contains { $0.isAssigned })
        #expect(!store.applyDefaultFocusTemplateIfNeeded(at: end))
        #expect(store.focusPlanning.templates.contains { $0.id == original.id })
    }

    @Test("Template refresh preserves past assignments and updates future ones")
    func templateRefreshPreservesPast() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.applyFocusTemplate(original, at: at))
        let before = try #require(store.focusDayCanvas(at: at).blocks.first { $0.isAssigned })
        let later = at.addingTimeInterval(60 * 60)
        let future = try #require(store.focusTemplateBlocks(at: later).first { $0.kind == .task && $0.start > later })
        let slots = [FocusTemplateSlot(blockIndex: future.index, kind: .task, taskKey: UUID(), taskTitle: "Future", taskIcon: .code)]
        #expect(store.updateFocusTemplate(original, name: "Future plan", slots: slots, at: later))
        let canvas = store.focusDayCanvas(at: later)
        #expect(canvas.blocks.first { $0.startAtMs == before.startAtMs }?.taskID == before.taskID)
        #expect(canvas.blocks.first { $0.startAtMs == future.startAtMs }?.taskTitle == "Future")
    }

    @Test("Resizing skips another task and shrinking releases only this task’s extra slots")
    func resizingPreservesOtherTasks() throws {
        let (store, at) = try fixture()
        let first = store.createFocusTaskInNextEmptyBlock(title: "First", at: at)
        guard case .placed(let id, _) = first else { Issue.record("Expected placement"); return }
        let other = store.createFocusTaskInNextEmptyBlock(title: "Other", at: at)
        guard case .placed(let otherID, let otherStart) = other else { Issue.record("Expected another placement"); return }
        let task = try #require(store.records.state.focusTasks.first { $0.id == id })
        #expect(store.editFocusTask(task, title: "First", icon: .work, pomodoros: 2, isFavorite: false, at: at))
        let expanded = store.focusDayCanvas(at: at)
        #expect(expanded.blocks.count { $0.taskID == id } == 2)
        #expect(expanded.blocks.first { $0.startAtMs == otherStart }?.taskID == otherID)
        #expect(store.editFocusTask(task, title: "First", icon: .work, pomodoros: 1, isFavorite: false, at: at))
        #expect(store.focusDayCanvas(at: at).blocks.count { $0.taskID == id } == 1)
        #expect(store.focusDayCanvas(at: at).blocks.first { $0.startAtMs == otherStart }?.taskID == otherID)
    }

    @Test("Template changes preserve the running round and clearing stops it without erasing history")
    func runningRoundSurvivesTemplateRefresh() throws {
        let (store, at) = try fixture()
        let original = try template(store, at: at)
        #expect(store.applyFocusTemplate(original, at: at))
        let block = try #require(store.focusDayCanvas(at: at).blocks.first { $0.isAssigned })
        let taskID = try #require(block.taskID)
        let end = Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000)
        let session = FocusSession(id: UUID(), taskID: taskID,
            shiftAnchorDate: Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000),
            startedAt: at, plannedEndAt: end, endedAt: nil, endReason: nil,
            editedAt: at, editCount: 0, editTieBreaker: UUID())
        store.records.upsertFocusSession(session)
        let next = try #require(store.focusTemplateBlocks(at: at).first { $0.kind == .task && $0.start >= end })
        var slots = original.slots
        slots.append(.init(blockIndex: next.index, kind: .task, taskKey: original.slots[0].taskKey,
                           taskTitle: "Updated", taskIcon: .code))
        #expect(store.updateFocusTemplate(original, name: "Updated", slots: slots, at: at))
        #expect(store.activeFocusSession()?.id == session.id)
        #expect(store.focusDayCanvas(at: at).blocks.first { $0.startAtMs == block.startAtMs }?.taskID == taskID)
        store.clearFocusDay(at: at.addingTimeInterval(60))
        #expect(store.activeFocusSession() == nil)
        #expect(store.records.state.focusSessions.first { $0.id == session.id }?.endReason == .stoppedByUser)
        #expect(!store.focusDayCanvas(at: at).blocks.contains { $0.isAssigned })
    }

    @Test("Clearing the displayed day keeps another day’s tasks")
    func clearingDoesNotTouchAnotherDay() throws {
        let (store, at) = try fixture()
        _ = store.createFocusTaskInNextEmptyBlock(title: "Today", at: at)
        let later = at.addingTimeInterval(12 * 3600)
        let result = store.createFocusTaskInNextEmptyBlock(title: "Tomorrow", at: later)
        guard case .placed(let nextID, _) = result else { Issue.record("Expected tomorrow placement"); return }
        store.clearFocusDay(at: at)
        #expect(store.records.state.focusTasks.first { $0.id == nextID }?.deletedAt == nil)
        #expect(store.focusDayCanvas(at: later).blocks.contains { $0.taskID == nextID })
    }

    @Test("Work-time eligibility distinguishes working time from lunch and clock-off")
    func startEligibilityExplainsOutsideHours() throws {
        let (store, at) = try fixture()
        #expect(store.isWithinFocusWorkTime(at: at))
        #expect(!store.isWithinFocusWorkTime(at: at.addingTimeInterval(-2 * 3600)))
        #expect(!store.isWithinFocusWorkTime(at: at.addingTimeInterval(12 * 3600)))
        #expect(!store.isWithinFocusWorkTime(at: at.addingTimeInterval(3 * 3600)))
    }
}
