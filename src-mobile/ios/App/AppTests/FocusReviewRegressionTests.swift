import Foundation
import Testing
@testable import App

@MainActor
struct FocusReviewRegressionTests {
    private func makeStore() throws -> AppRuntime {
        let defaults = try #require(UserDefaults(suiteName: "FocusReview.\(UUID())"))
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        store.plus.debugSetAuthorized(true)
        store.preferences.applyPreferences { $0.startMinutes = 540 }
        store.preferences.applyPreferences { $0.endMinutes = 1020 }
        store.preferences.applyPreferences { $0.lunchEnabled = true }
        return store
    }

    private func date(_ store: AppRuntime, hour: Int) throws -> Date {
        try #require(store.preferences.recordsCalendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: hour, minute: 5)))
    }

    @Test func disabledHealthRemindersStayDisabled() throws {
        let store = try makeStore()
        let at = try date(store, hour: 9)
        store.preferences.applyPreferences { $0.microBreakEnabled = false }
        _ = store.focus.createFocusTaskInNextEmptyBlock(title: "Review fixture", at: at).synchronousResult
        let reminders = store.shifts.shiftReminders(at: at)
        #expect(!reminders.contains { $0.id.hasPrefix("focusBreak:") })
    }

    @Test func afterWorkTemplateDraftIncludesDrawnAssignments() throws {
        let store = try makeStore()
        let at = try date(store, hour: 21)
        _ = store.focus.createFocusTaskInNextEmptyBlock(title: "Tomorrow fixture", at: at).synchronousResult
        #expect(store.focus.focusDayCanvas(at: at).blocks.contains { $0.taskTitle == "Tomorrow fixture" })
        #expect(store.focus.focusTemplateDraftFromToday(at: at).contains { $0.taskTitle == "Tomorrow fixture" })
    }

    @Test func templateApplicationTargetsDrawnShift() throws {
        let store = try makeStore()
        let at = try date(store, hour: 21)
        let template = try #require(store.focus.saveFocusTemplate(name: "Review fixture", slots: [
            FocusTemplateSlot(blockIndex: 0, kind: .task, taskKey: UUID(), taskTitle: "Template fixture", taskIcon: .focus)
        ]).synchronousResult)
        #expect(store.focus.applyFocusTemplate(template, at: at).synchronousResult)
        #expect(store.focus.focusDayCanvas(at: at).blocks.contains { $0.taskTitle == "Template fixture" })
    }
    @Test(arguments: [(5, 5), (15, 5)])
    func longBreaksAreIdentifiedByCadenceNotDuration(durations: (Int, Int)) throws {
        let store = try makeStore()
        let at = try date(store, hour: 9)
        store.preferences.applyPreferences { $0.microBreakEnabled = true }
        #expect(store.focus.updateFocusTimerSettings(.init(shortBreakMinutes: durations.0, longBreakMinutes: durations.1)).synchronousResult)
        _ = store.focus.createFocusTaskInNextEmptyBlock(title: "Planned work", at: at).synchronousResult
        let blocks = store.focus.focusWorkBlocks(at: at)
        let reminders = store.focus.focusBreakReminders(at: at)
        #expect(!reminders.isEmpty)
        #expect(reminders.count < blocks.count { $0.kind == .breakTime })
        for reminder in reminders {
            let block = try #require(blocks.first { Double($0.startAtMs) == reminder.atMs })
            #expect(block.breakKind == .longBreak)
        }
    }

    @Test func manualBreakStaysOnDayInsteadOfBecomingATemplateTask() throws {
        let store = try makeStore()
        let at = try date(store, hour: 9)
        let target = try #require(store.focus.focusTemplateBlocks(at: at).first { $0.kind == .task })
        store.focus.markBlockAsBreak(startingAt: target.startAtMs, at: at).synchronousResult
        #expect(store.focus.saveFocusTemplate(name: "Only a break", slots: store.focus.focusTemplateDraftFromToday(at: at)).synchronousResult == nil)
        _ = store.focus.createFocusTaskInNextEmptyBlock(title: "Writing", at: at).synchronousResult
        let template = try #require(store.focus.saveFocusTemplate(name: "Tasks", slots: store.focus.focusTemplateDraftFromToday(at: at)).synchronousResult)
        #expect(template.tasks.map(\.title) == ["Writing"])
        let afterWork = try date(store, hour: 21)
        #expect(store.focus.applyFocusTemplate(template, at: afterWork).synchronousResult)
        #expect(store.focus.focusDayCanvas(at: afterWork).blocks.first?.taskTitle == "Writing")
        #expect(store.focus.focusDayCanvas(at: afterWork).blocks.first?.isUserBreak == false)
        #expect(store.focus.focusDayCanvas(at: at).blocks.first?.isUserBreak == true)
    }

    @Test func lateStartKeepsSlotEndAndRollsIntoItsBreak() throws {
        let store = try makeStore()
        store.session.countdownStarted = true
        let at = try date(store, hour: 9)
        let result = store.focus.createFocusTaskInNextEmptyBlock(title: "Scheduled work", at: at).synchronousResult
        guard case .placed(let taskID, let blockStart) = result else { Issue.record("Expected placement"); return }
        var task = try #require(store.records.state.focusTasks.first { $0.id == taskID })
        task.estimatedPomodoros = 2
        store.records.upsertFocusTask(task)
        let block = try #require(store.focus.focusWorkBlocks(at: at).first { $0.startAtMs == blockStart })
        #expect(store.focus.startFocus(task: task, inBlockStartingAt: blockStart, at: at).synchronousResult)
        let session = try #require(store.focus.activeFocusSession())
        #expect(session.plannedEndAt == block.end)
        #expect(session.plannedEndAt.timeIntervalSince(at) == 20 * 60)
        #expect(session.plannedEndReason == .completed)
        #expect(store.focus.finishElapsedFocusSession(at: block.end).synchronousResult)
        // The break the block earned starts from the block's own end, so the
        // Lock Screen countdown and the recorded session say the same thing.
        let recovery = try #require(store.focus.activeFocusSession())
        #expect(recovery.kind == .shortBreak)
        #expect(recovery.startedAt == block.end)
        #expect(recovery.plannedEndAt == block.end.addingTimeInterval(5 * 60))
        #expect(store.focus.focusLastNextAction == .none)
        let legs = LiveActivityService.focusLegs(
            store.focus.focusChain(for: recovery, at: recovery.startedAt),
            shifts: store.shifts
        )
        #expect(legs.first?.label == store.text.t("focusShortBreak"))
        store.focus.stopFocus(reason: .stoppedByUser, at: recovery.startedAt.addingTimeInterval(60)).synchronousResult
        #expect(store.focus.focusLastNextAction == .startNextFocus)
    }

    @Test func futureSlotCannotStartEarly() throws {
        let store = try makeStore()
        store.session.countdownStarted = true
        let at = try date(store, hour: 9)
        let target = try #require(store.focus.focusWorkBlocks(at: at).first { $0.kind == .task && $0.start > at })
        let result = store.focus.createFocusTask(title: "Later", inBlockStartingAt: target.startAtMs, at: at).synchronousResult
        guard case .placed(let taskID, _) = result else { Issue.record("Expected placement"); return }
        let task = try #require(store.records.state.focusTasks.first { $0.id == taskID })
        #expect(!store.focus.startFocus(task: task, inBlockStartingAt: target.startAtMs, at: at).synchronousResult)
        #expect(store.focus.activeFocusSession() == nil)
    }

    @Test func fourthScheduledSlotOffersLongBreakWithoutThreeEarlierSessions() throws {
        let store = try makeStore()
        store.session.countdownStarted = true
        let morning = try date(store, hour: 9)
        let blocks = store.focus.focusWorkBlocks(at: morning)
        let recovery = try #require(blocks.first { $0.breakKind == .longBreak })
        let focus = try #require(blocks.last { $0.kind == .task && $0.end == recovery.start })
        let at = focus.start.addingTimeInterval(300)
        let result = store.focus.createFocusTask(title: "Fourth slot", inBlockStartingAt: focus.startAtMs, at: at).synchronousResult
        guard case .placed(let taskID, _) = result else { Issue.record("Expected placement"); return }
        var task = try #require(store.records.state.focusTasks.first { $0.id == taskID })
        task.estimatedPomodoros = 2
        store.records.upsertFocusTask(task)
        #expect(store.focus.startFocus(task: task, inBlockStartingAt: focus.startAtMs, at: at).synchronousResult)
        let session = try #require(store.focus.activeFocusSession())
        #expect(store.focus.nextFocusBreakKind(after: session) == .longBreak)
        let legs = LiveActivityService.focusLegs(store.focus.focusChain(for: session, at: at), shifts: store.shifts)
        #expect(legs.first?.nextNote == store.text.t(
            "focusActivityThenBreak",
            values: ["count": store.text.formatCount(15)]
        ))
        // A block with nothing behind it earns no break, so the chain must not
        // promise one either.
        var unassigned = session
        unassigned.taskID = nil
        let unassignedChain = store.focus.focusChain(for: unassigned, at: at)
        #expect(unassignedChain.count == 1)
        #expect(LiveActivityService.focusLegs(unassignedChain, shifts: store.shifts).first?.nextNote == nil)
        #expect(store.focus.finishElapsedFocusSession(at: session.plannedEndAt).synchronousResult)
        #expect(store.focus.activeFocusSession()?.kind == .longBreak)
    }

    @Test func immediateCreationPreservesEstimateAndFavorite() throws {
        let scene = SceneState()
        let store = try makeStore()
        scene.addAndStartFocusTask(title: "Three rounds", pomodoros: 3, icon: .code, isFavorite: true, using: store.focus)
        let task = try #require(store.records.state.focusTasks.first { $0.title == "Three rounds" })
        #expect(task.estimatedPomodoros == 3)
        #expect(task.icon == .code)
        #expect(task.isFavorite)
    }

}
