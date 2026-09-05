import Foundation
import Testing
@testable import App

@MainActor
struct FocusReviewRegressionTests {
    private func makeStore() throws -> OffWorkStore {
        let defaults = try #require(UserDefaults(suiteName: "FocusReview.\(UUID())"))
        let store = OffWorkStore(defaults: defaults, records: .inMemory())
        store.plus.debugSetAuthorized(true)
        store.startMinutes = 540
        store.endMinutes = 1020
        store.lunchEnabled = true
        return store
    }

    private func date(_ store: OffWorkStore, hour: Int) throws -> Date {
        try #require(store.recordsCalendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: hour, minute: 5)))
    }

    @Test func disabledHealthRemindersStayDisabled() throws {
        let store = try makeStore()
        let at = try date(store, hour: 9)
        store.microBreakEnabled = false
        _ = store.createFocusTaskInNextEmptyBlock(title: "Review fixture", at: at)
        let reminders = try store.shiftReminders(at: at)
        #expect(!reminders.contains { $0.id.hasPrefix("focusBreak:") })
    }

    @Test func afterWorkTemplateDraftIncludesDrawnAssignments() throws {
        let store = try makeStore()
        let at = try date(store, hour: 21)
        _ = store.createFocusTaskInNextEmptyBlock(title: "Tomorrow fixture", at: at)
        #expect(store.focusDayCanvas(at: at).blocks.contains { $0.taskTitle == "Tomorrow fixture" })
        #expect(store.focusTemplateDraftFromToday(at: at).contains { $0.taskTitle == "Tomorrow fixture" })
    }

    @Test func templateApplicationTargetsDrawnShift() throws {
        let store = try makeStore()
        let at = try date(store, hour: 21)
        let template = try #require(store.saveFocusTemplate(name: "Review fixture", slots: [
            FocusTemplateSlot(blockIndex: 0, kind: .task, taskKey: UUID(), taskTitle: "Template fixture", taskIcon: .focus)
        ]))
        #expect(store.applyFocusTemplate(template, at: at))
        #expect(store.focusDayCanvas(at: at).blocks.contains { $0.taskTitle == "Template fixture" })
    }
    @Test(arguments: [(5, 5), (15, 5)])
    func longBreaksAreIdentifiedByCadenceNotDuration(durations: (Int, Int)) throws {
        let store = try makeStore()
        let at = try date(store, hour: 9)
        store.microBreakEnabled = true
        #expect(store.updateFocusTimerSettings(.init(shortBreakMinutes: durations.0, longBreakMinutes: durations.1)))
        _ = store.createFocusTaskInNextEmptyBlock(title: "Planned work", at: at)
        let blocks = store.focusWorkBlocks(at: at)
        let reminders = store.focusBreakReminders(at: at)
        #expect(!reminders.isEmpty)
        #expect(reminders.count < blocks.count { $0.kind == .breakTime })
        for reminder in reminders {
            let block = try #require(blocks.first { Double($0.startAtMs) == reminder.atMs })
            #expect(block.breakKind == .longBreak)
        }
    }

    @Test func manualBreakSurvivesTemplateRoundTrip() throws {
        let store = try makeStore()
        let at = try date(store, hour: 9)
        let blocks = store.focusTemplateBlocks(at: at)
        let target = try #require(blocks.first { $0.kind == .task })
        store.markBlockAsBreak(startingAt: target.startAtMs, at: at)
        let slots = store.focusTemplateDraftFromToday(at: at)
        #expect(slots.contains { $0.blockIndex == target.index && $0.kind == .breakTime })
        let template = try #require(store.saveFocusTemplate(name: "Recovery morning", slots: slots))
        let afterWork = try date(store, hour: 21)
        #expect(store.applyFocusTemplate(template, at: afterWork))
        #expect(store.focusDayCanvas(at: afterWork).blocks.first?.isUserBreak == true)
        #expect(store.applyFocusTemplate(template, at: afterWork))
        #expect(store.focusDayCanvas(at: afterWork).blocks.first?.isUserBreak == true)
    }

    @Test func lateStartKeepsSlotEndAndOffersItsBreak() throws {
        let store = try makeStore()
        store.countdownStarted = true
        let at = try date(store, hour: 9)
        let result = store.createFocusTaskInNextEmptyBlock(title: "Scheduled work", at: at)
        guard case .placed(let taskID, let blockStart) = result else { Issue.record("Expected placement"); return }
        let task = try #require(store.records.state.focusTasks.first { $0.id == taskID })
        let block = try #require(store.focusWorkBlocks(at: at).first { $0.startAtMs == blockStart })
        #expect(store.startFocus(task: task, inBlockStartingAt: blockStart, at: at))
        let session = try #require(store.activeFocusSession())
        #expect(session.plannedEndAt == block.end)
        #expect(session.plannedEndAt.timeIntervalSince(at) == 20 * 60)
        #expect(session.plannedEndReason == .completed)
        #expect(store.finishElapsedFocusSession(at: block.end))
        #expect(store.focusLastNextAction == .startShortBreak)
        #expect(store.startBreak(kind: .shortBreak, at: block.end.addingTimeInterval(60)))
        let recovery = try #require(store.activeFocusSession())
        #expect(recovery.plannedEndAt == block.end.addingTimeInterval(5 * 60))
        #expect(LiveActivityService.focusNextLabel(session: recovery, store: store, now: recovery.startedAt) == store.t("focusStartNextFocus"))
        store.stopFocus(reason: .stoppedByUser, at: recovery.startedAt.addingTimeInterval(60))
        #expect(store.focusLastNextAction == .startNextFocus)
    }

    @Test func futureSlotCannotStartEarly() throws {
        let store = try makeStore()
        store.countdownStarted = true
        let at = try date(store, hour: 9)
        let target = try #require(store.focusWorkBlocks(at: at).first { $0.kind == .task && $0.start > at })
        let result = store.createFocusTask(title: "Later", inBlockStartingAt: target.startAtMs, at: at)
        guard case .placed(let taskID, _) = result else { Issue.record("Expected placement"); return }
        let task = try #require(store.records.state.focusTasks.first { $0.id == taskID })
        #expect(!store.startFocus(task: task, inBlockStartingAt: target.startAtMs, at: at))
        #expect(store.activeFocusSession() == nil)
    }

    @Test func fourthScheduledSlotOffersLongBreakWithoutThreeEarlierSessions() throws {
        let store = try makeStore()
        store.countdownStarted = true
        let morning = try date(store, hour: 9)
        let blocks = store.focusWorkBlocks(at: morning)
        let recovery = try #require(blocks.first { $0.breakKind == .longBreak })
        let focus = try #require(blocks.last { $0.kind == .task && $0.end == recovery.start })
        let at = focus.start.addingTimeInterval(300)
        let result = store.createFocusTask(title: "Fourth slot", inBlockStartingAt: focus.startAtMs, at: at)
        guard case .placed(let taskID, _) = result else { Issue.record("Expected placement"); return }
        let task = try #require(store.records.state.focusTasks.first { $0.id == taskID })
        #expect(store.startFocus(task: task, inBlockStartingAt: focus.startAtMs, at: at))
        let session = try #require(store.activeFocusSession())
        #expect(store.nextFocusBreakKind(after: session) == .longBreak)
        #expect(LiveActivityService.focusNextLabel(session: session, store: store, now: at) == store.t("focusActivityThenBreak", values: ["count": "15"]))
        #expect(store.finishElapsedFocusSession(at: session.plannedEndAt))
        #expect(store.focusLastNextAction == .startLongBreak)
    }

    @Test func immediateCreationPreservesEstimateAndFavorite() throws {
        let store = try makeStore()
        store.addAndStartFocusTask(title: "Three rounds", pomodoros: 3, icon: .code, isFavorite: true)
        let task = try #require(store.records.state.focusTasks.first { $0.title == "Three rounds" })
        #expect(task.estimatedPomodoros == 3)
        #expect(task.icon == .code)
        #expect(task.isFavorite)
    }

}
