import Foundation
import Testing
@testable import App

/// What the Lock Screen is promised while the phone is asleep.
///
/// The chain is the only thing the Live Activity can walk without the app, so
/// these describe the shape it hands over: the running block, the recovery it
/// earns, and the block queued behind them — and where that stops.

@MainActor
@Test("A running block hands the chain to its break and to the next planned block")
func chainRunsFocusThenBreakThenNext() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focus.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)

    let running = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    let queued = chainTask(store, title: "Inbox", pomodoros: 1, at: at)
    _ = store.focus.assign(running, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    _ = store.focus.assign(queued, toBlockStartingAt: second.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: running, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    let session = try #require(store.focus.activeFocusSession())
    let chain = store.focus.focusChain(for: session, at: at)

    #expect(chain.count == 3)
    #expect(chain[0].kind == .focus)
    #expect(chain[0].role == .running)
    #expect(chain[0].taskTitle == "Spec review")
    #expect(chain[0].pomodoroIndex == 1)
    #expect(chain[0].pomodoroTotal == 1)
    #expect(chain[0].taskFinishAt == session.plannedEndAt)
    #expect(chain[1].kind == .shortBreak)
    #expect(chain[1].start == session.plannedEndAt)
    #expect(chain[2].role == .upNext)
    #expect(chain[2].taskTitle == "Inbox")
    #expect(chain[2].start == Date(timeIntervalSince1970: Double(second.startAtMs) / 1_000))
}

@MainActor
@Test("The last task ends the day without an unnecessary recovery timer")
func chainStopsAfterTheBreakWhenNothingIsPlanned() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    let session = try #require(store.focus.activeFocusSession())
    let chain = store.focus.focusChain(for: session, at: at)
    #expect(chain.count == 1)
    #expect(chain.last?.kind == .focus)
    #expect(store.focus.completesFocusDay(after: session, at: at))
}

@MainActor
@Test("A two-block task names the clock time its last block ends")
func chainProjectsTheTaskFinishTime() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focus.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)

    let task = chainTask(store, title: "Spec review", pomodoros: 2, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    _ = store.focus.assign(task, toBlockStartingAt: second.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    let session = try #require(store.focus.activeFocusSession())
    let chain = store.focus.focusChain(for: session, at: at)
    #expect(chain[0].pomodoroIndex == 1)
    #expect(chain[0].pomodoroTotal == 2)
    #expect(chain[0].taskFinishAt == Date(timeIntervalSince1970: Double(second.endAtMs) / 1_000))
}

@MainActor
@Test("A finish time is withheld rather than guessed when the shift runs out")
func chainWithholdsAnImpossibleFinishTime() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    // More blocks than the whole shift holds, so no honest hour exists.
    let task = chainTask(store, title: "Spec review", pomodoros: 99, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    let session = try #require(store.focus.activeFocusSession())
    #expect(store.focus.focusChain(for: session, at: at)[0].taskFinishAt == nil)
}

@MainActor
@Test("Another task's blocks are skipped, not treated as the end of the walk")
func projectionSkipsBlocksOwnedByAnotherTask() {
    let mine = UUID()
    let theirs = UUID()
    let blocks = [
        chainBlock(0, start: 0, end: 100, taskID: mine),
        chainBlock(1, start: 100, end: 200, taskID: theirs),
        chainBlock(2, start: 200, end: 300, taskID: nil),
    ]
    let projected = FocusLiveChain.projectedBlocks(
        taskID: mine, remaining: 2, blocks: blocks, fromMs: 0
    )
    #expect(projected.map(\.startAtMs) == [0, 200])
}

@MainActor
@Test("A block already promised to another task is not somewhere to continue")
func continuationRefusesAConflictingBlock() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focus.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)

    let running = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    let other = chainTask(store, title: "Inbox", pomodoros: 1, at: at)
    _ = store.focus.assign(running, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    _ = store.focus.assign(other, toBlockStartingAt: second.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: running, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    // The next block belongs to Inbox. The plus greys out rather than taking
    // it, and the write refuses for exactly the same reason — one resolver
    // answers both.
    #expect(!store.focus.canAddFocusPomodoro(at: at))
    #expect(!store.focus.addFocusPomodoroToRunningTask(at: at).synchronousResult)
    #expect(store.records.state.focusTasks.first { $0.id == running.id }?.estimatedPomodoros == 1)
}

@MainActor
@Test("Adding a pomodoro raises the estimate and places the block in one step")
func addingAPomodoroPlacesTheBlock() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    #expect(store.focus.canAddFocusPomodoro(at: at))
    #expect(store.focus.addFocusPomodoroToRunningTask(at: at).synchronousResult)

    let reloaded = try #require(store.records.state.focusTasks.first { $0.id == task.id })
    #expect(reloaded.estimatedPomodoros == 2)
    let assigned = store.focus.focusDayCanvas(at: at).blocks.filter { $0.taskID == task.id }
    #expect(assigned.count == 2)
}

@MainActor
@Test("A break with no task behind it is not offered one more block")
func breaksDoNotOfferAnExtraPomodoro() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    let end = try #require(store.focus.activeFocusSession()).plannedEndAt
    #expect(store.focus.finishElapsedFocusSession(at: end).synchronousResult)
    #expect(store.focus.activeFocusSession()?.kind != .focus)
    #expect(!store.focus.canAddFocusPomodoro(at: end))
}

@MainActor
@Test("A completed block's break starts with it, from the block's own end")
func completedBlockStartsItsBreakAutomatically() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 2, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    let end = try #require(store.focus.activeFocusSession()).plannedEndAt
    #expect(store.focus.finishElapsedFocusSession(at: end.addingTimeInterval(30)).synchronousResult)

    let running = try #require(store.focus.activeFocusSession())
    #expect(running.kind == .shortBreak)
    #expect(running.startedAt == end)
    #expect(store.focus.focusLastNextAction == .none)
}

@MainActor
@Test("Coming back after the break window does not backfill a break nobody took")
func lateReturnDoesNotBackfillABreak() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 2, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    let end = try #require(store.focus.activeFocusSession()).plannedEndAt
    #expect(store.focus.finishElapsedFocusSession(at: end.addingTimeInterval(45 * 60)).synchronousResult)

    #expect(store.focus.activeFocusSession() == nil)
    #expect(store.focus.focusLastNextAction == .startShortBreak)
}

@MainActor
@Test("A block's alerts name the task and say when the break ends")
func focusAlertsDescribeTheWholePhase() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 2, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)

    let session = try #require(store.focus.activeFocusSession())
    let alerts = store.focus.focusAlerts(for: session)
    #expect(alerts.count == 2)
    #expect(alerts[0].slot == .end)
    #expect(alerts[0].title == "Spec review")
    #expect(alerts[0].body.contains("Pomodoro 1 of 2"))
    #expect(alerts[0].body.contains("break"))
    #expect(alerts[0].at == session.plannedEndAt)
    #expect(alerts[1].slot == .breakEnd)
    #expect(alerts[1].at > session.plannedEndAt)
    #expect(!alerts[1].body.isEmpty)
}

@MainActor
@Test("A block cut short by a boundary owes only its own alert")
func boundaryBlockHasNoBreakAlert() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 11, minute: 45))
    let end = try #require(chainDay(store, hour: 12, minute: 0))
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    // Written directly rather than started: `startFocus(task:)` reads the wall
    // clock, so driving it made this assert nothing outside shift hours.
    store.records.upsertFocusSession(FocusSession(
        id: UUID(),
        taskID: task.id,
        shiftAnchorDate: store.preferences.recordsCalendar.startOfDay(for: at),
        startedAt: at,
        plannedEndAt: end,
        endedAt: nil,
        endReason: nil,
        editedAt: at,
        editCount: 0,
        editTieBreaker: UUID(),
        kind: .focus,
        plannedEndReason: .stoppedAtBoundary
    ))

    let session = try #require(store.focus.activeFocusSession())
    // It stopped at lunch instead of finishing, so it earned no break and has
    // nothing to say about one.
    let alerts = store.focus.focusAlerts(for: session)
    #expect(alerts.count == 1)
    #expect(alerts[0].slot == .end)
    #expect(alerts[0].title == "Spec review")
    #expect(store.focus.focusChain(for: session, at: at).count == 1)
}

// MARK: - Fixtures

@MainActor
private func chainStore() throws -> AppRuntime {
    let suite = "FocusLiveChainTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let store = AppRuntime(defaults: defaults, records: .inMemory())
    store.plus.debugSetAuthorized(true)
    store.session.countdownStarted = true
    store.preferences.applyPreferences { $0.languageOverride = "en" }
    store.preferences.applyPreferences { $0.workdays = [1, 2, 3, 4, 5] }
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
    store.preferences.applyPreferences { $0.lunchEnabled = true }
    return store
}

/// A Monday, so the default recurring schedule is a workday.
@MainActor
private func chainDay(_ store: AppRuntime, hour: Int, minute: Int) -> Date? {
    store.preferences.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: hour, minute: minute)
    )
}

@MainActor
private func chainTask(
    _ store: AppRuntime,
    title: String,
    pomodoros: Int,
    at date: Date
) -> FocusTask {
    let task = FocusTask(
        id: UUID(),
        createdAt: date,
        plannedForDate: store.preferences.recordsCalendar.startOfDay(for: date),
        scheduledStartAt: nil,
        title: title,
        estimatedPomodoros: pomodoros,
        completedAt: nil,
        sortIndex: store.records.state.focusTasks.count,
        editedAt: date,
        editCount: 0,
        editTieBreaker: UUID()
    )
    store.records.upsertFocusTask(task)
    return task
}

private func chainBlock(
    _ index: Int,
    start: Int64,
    end: Int64,
    taskID: UUID?
) -> FocusDayCanvasModel.Block {
    FocusDayCanvasModel.Block(
        index: index,
        startAtMs: start,
        endAtMs: end,
        kind: .task,
        state: .future,
        taskID: taskID,
        taskTitle: taskID == nil ? nil : "Block \(index)",
        taskIcon: taskID == nil ? nil : .focus
    )
}

@MainActor
@Test("Assigning today's tasks arms every start without a manual focus session")
func assignedDayStartsWithoutManualActivation() throws {
    let store = try chainStore()
    let planning = try #require(chainDay(store, hour: 8, minute: 30))
    let blocks = store.focus.focusDayCanvas(at: planning).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)
    let one = chainTask(store, title: "One", pomodoros: 1, at: planning)
    let two = chainTask(store, title: "Two", pomodoros: 1, at: planning)
    _ = store.focus.assign(one, toBlockStartingAt: first.startAtMs, at: planning).synchronousResult
    _ = store.focus.assign(two, toBlockStartingAt: second.startAtMs, at: planning).synchronousResult
    let queued = store.focus.refreshScheduledFocus(at: planning).synchronousResult
    #expect(queued.count == 2)
    #expect(store.focus.activeFocusSession() == nil)
    #expect(store.focus.refreshScheduledFocus(at: planning).synchronousResult.map(\.id) == queued.map(\.id))

    let wake = Date(timeIntervalSince1970: Double(second.startAtMs) / 1_000 + 60)
    store.focus.restoreScheduledFocus(at: wake).synchronousResult
    let running = try #require(store.focus.activeFocusSession())
    #expect(running.taskID == two.id)
    #expect(running.startedAt == queued[1].startedAt)
    #expect(running.plannedEndAt == queued[1].plannedEndAt)
    #expect(store.focus.completedFocusBlocks(for: one) == 1)
    store.focus.restoreScheduledFocus(at: wake).synchronousResult
    #expect(store.records.state.focusSessions.filter { $0.id == running.id }.count == 1)
}

@MainActor
@Test("A task assigned during recovery starts at the next block's absolute boundary")
func taskAssignedDuringBreakStartsAutomatically() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focus.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)
    let one = chainTask(store, title: "One", pomodoros: 2, at: at)
    _ = store.focus.assign(one, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: one, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)
    let end = try #require(store.focus.activeFocusSession()).plannedEndAt
    #expect(store.focus.finishElapsedFocusSession(at: end).synchronousResult)
    #expect(store.focus.activeFocusSession()?.kind == .shortBreak)
    let two = chainTask(store, title: "Added during break", pomodoros: 1, at: end)
    _ = store.focus.assign(two, toBlockStartingAt: second.startAtMs, at: end).synchronousResult
    #expect(store.focus.refreshScheduledFocus(at: end).synchronousResult.count == 1)
    let start = Date(timeIntervalSince1970: Double(second.startAtMs) / 1_000)
    store.focus.restoreScheduledFocus(at: start.addingTimeInterval(20)).synchronousResult
    #expect(store.focus.activeFocusSession()?.taskID == two.id)
    #expect(store.focus.activeFocusSession()?.startedAt == start)
}

@MainActor
@Test("Clearing an assignment cancels its armed start; stopped blocks never restart")
func clearingOrStoppingDoesNotRestartScheduledFocus() throws {
    let store = try chainStore()
    let planning = try #require(chainDay(store, hour: 8, minute: 30))
    let block = try #require(store.focus.focusDayCanvas(at: planning).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "One", pomodoros: 1, at: planning)
    _ = store.focus.assign(task, toBlockStartingAt: block.startAtMs, at: planning).synchronousResult
    #expect(store.focus.refreshScheduledFocus(at: planning).synchronousResult.count == 1)
    let workBlock = try #require(store.focus.focusWorkBlocks(at: planning).first { $0.startAtMs == block.startAtMs })
    store.focus.clearFocusBlock(workBlock, at: planning).synchronousResult
    #expect(store.focus.refreshScheduledFocus(at: planning).synchronousResult.isEmpty)
    let start = Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)
    store.focus.restoreScheduledFocus(at: start).synchronousResult
    #expect(store.focus.activeFocusSession() == nil)

    _ = store.focus.assign(task, toBlockStartingAt: block.startAtMs, at: start).synchronousResult
    _ = store.focus.refreshScheduledFocus(at: start).synchronousResult
    let session = try #require(store.focus.activeFocusSession())
    #expect(!store.focus.stopFocusFromActivity(startAtMs: block.startAtMs - 1, at: start.addingTimeInterval(60)).synchronousResult)
    #expect(store.focus.stopFocusFromActivity(startAtMs: block.startAtMs, at: start.addingTimeInterval(60)).synchronousResult)
    #expect(store.focus.refreshScheduledFocus(at: start.addingTimeInterval(90)).synchronousResult.isEmpty)
    #expect(store.focus.activeFocusSession() == nil)
    #expect(store.records.state.focusSessions.first { $0.id == session.id }?.endReason == .stoppedByUser)
}

@MainActor
@Test("An unarmed past assignment creates no completed focus history")
func pastUnarmedAssignmentsDoNotCreateHistory() throws {
    let store = try chainStore()
    let planning = try #require(chainDay(store, hour: 8, minute: 30))
    let block = try #require(store.focus.focusDayCanvas(at: planning).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Unarmed", pomodoros: 1, at: planning)
    _ = store.focus.assign(task, toBlockStartingAt: block.startAtMs, at: planning).synchronousResult
    _ = store.focus.refreshScheduledFocus(at: Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000 + 60)).synchronousResult
    #expect(store.records.state.focusSessions.isEmpty)
}

@MainActor
@Test("Every final phase reaches the same day-complete state", arguments: [FocusSessionKind.focus, .shortBreak, .longBreak])
func allFinalPhasesCompleteTheDay(kind: FocusSessionKind) throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    var task = chainTask(store, title: "Final task", pomodoros: 1, at: at)
    if kind != .focus {
        task.completedAt = at
        store.records.upsertFocusTask(task)
    }
    let session = FocusSession(
        id: UUID(), taskID: kind == .focus ? task.id : nil,
        shiftAnchorDate: store.preferences.recordsCalendar.startOfDay(for: at),
        startedAt: at, plannedEndAt: at.addingTimeInterval(25 * 60),
        endedAt: nil, endReason: nil, editedAt: at, editCount: 0,
        editTieBreaker: UUID(), kind: kind, plannedEndReason: .completed
    )
    store.records.upsertFocusSession(session)
    #expect(store.focus.completesFocusDay(after: session, at: at))
    #expect(store.focus.focusChain(for: session, at: at).count == 1)
    #expect(store.focus.finishElapsedFocusSession(at: session.plannedEndAt).synchronousResult)
    #expect(store.focus.activeFocusSession() == nil)
    #expect(store.focus.focusDayComplete(at: session.plannedEndAt))
}

@MainActor
@Test("The last queued block includes the currently running block in day completion")
func finalQueuedBlockCompletesRunningTask() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focus.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let task = chainTask(store, title: "Two blocks", pomodoros: 2, at: at)
    for block in blocks.prefix(2) {
        _ = store.focus.assign(task, toBlockStartingAt: block.startAtMs, at: at).synchronousResult
    }
    let queued = store.focus.refreshScheduledFocus(at: at).synchronousResult
    let running = try #require(store.focus.activeFocusSession())
    #expect(!store.focus.completesFocusDay(after: running, at: at))
    let last = try #require(queued.last)
    #expect(store.focus.completesFocusDay(after: last, at: at))
}

@MainActor
@Test("Activity actions open confirmation without changing the running task")
func activityActionsRequireConfirmation() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focus.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Review", pomodoros: 1, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: first.startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at).synchronousResult)
    let session = try #require(store.focus.activeFocusSession())
    let start = Int64(session.startedAt.timeIntervalSince1970 * 1_000)

    for action in [FocusActivityRequest.Action.addPomodoros, .stop] {
        // One scene per action: a second request in the same scene queues behind
        // the first, which SceneStateTests covers separately.
        let scene = SceneState()
        scene.requestFocusActivityConfirmation(action, startAtMs: start)
        let request = try #require(scene.focusActivityRequest)
        #expect(request.action == action)
        scene.activateFocusActivityPresentationIfPossible(isBlocked: false)
        #expect(scene.selectedTab == .focus)
        #expect(scene.focusPath.isEmpty)
        #expect(store.focus.matchesFocusActivity(request, at: at))
        #expect(!store.focus.matchesFocusActivity(request, at: session.plannedEndAt))
        #expect(store.focus.activeFocusSession()?.id == session.id)
        #expect(store.records.state.focusTasks.first { $0.id == task.id }?.estimatedPomodoros == 1)
    }
    #expect(!store.focus.matchesFocusActivity(.init(action: .stop, startAtMs: start - 1), at: at))
}

@MainActor
@Test("Adding several pomodoros stops before the next task and rejects excess without edits")
func extraPomodorosRespectNextTask() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focus.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    try #require(blocks.count >= 4)
    let task = chainTask(store, title: "Review", pomodoros: 1, at: at)
    let next = chainTask(store, title: "Next task", pomodoros: 1, at: at)
    _ = store.focus.assign(task, toBlockStartingAt: blocks[0].startAtMs, at: at).synchronousResult
    _ = store.focus.assign(next, toBlockStartingAt: blocks[3].startAtMs, at: at).synchronousResult
    #expect(store.focus.startFocus(task: task, inBlockStartingAt: blocks[0].startAtMs, at: at).synchronousResult)
    #expect(store.focus.addableFocusBlocks(at: at).count == 2)
    #expect(!store.focus.addFocusPomodoroToRunningTask(count: 3, at: at).synchronousResult)
    #expect(store.records.state.focusTasks.first { $0.id == task.id }?.estimatedPomodoros == 1)
    #expect(store.focus.addFocusPomodoroToRunningTask(count: 2, at: at).synchronousResult)
    #expect(store.focus.addableFocusBlocks(at: at).isEmpty)
    #expect(store.records.state.focusTasks.first { $0.id == task.id }?.estimatedPomodoros == 3)
    #expect(store.focus.focusDayCanvas(at: at).blocks.first { $0.startAtMs == blocks[3].startAtMs }?.taskID == next.id)
}

@MainActor
@Test("Focus tab navigation preserves the other tabs and never requests a paywall")
func focusTabNavigationPreservesOtherTabs() {
    let scene = SceneState()
    scene.timerPath = [.about]
    scene.settingsPath = [.language]
    scene.focusPath = [.plus]
    scene.presentedRoute = .focus
    scene.openFocusTab()
    #expect(scene.selectedTab == .focus)
    #expect(scene.focusPath.isEmpty)
    #expect(scene.timerPath == [.about])
    #expect(scene.settingsPath == [.language])
    #expect(scene.presentedRoute == nil)
    #expect(scene.paywallSheet == nil)
    scene.activePath = [.plus]
    #expect(scene.focusPath == [.plus])
    #expect(scene.timerPath == [.about])
}

@MainActor
@Test("Two devices queue the same planned block under one identity")
func devicesShareScheduledBlockIdentity() throws {
    let phone = try chainStore()
    let tablet = try chainStore()
    let planning = try #require(chainDay(phone, hour: 8, minute: 30))
    let block = try #require(phone.focus.focusDayCanvas(at: planning).blocks.first { $0.kind == .task })
    let task = chainTask(phone, title: "One", pomodoros: 1, at: planning)
    _ = phone.focus.assign(task, toBlockStartingAt: block.startAtMs, at: planning).synchronousResult
    for synced in phone.records.state.focusTasks { tablet.records.upsertFocusTask(synced) }
    if let configuration = phone.records.state.focusPlanningConfiguration {
        tablet.records.upsertFocusPlanningConfiguration(configuration)
    }
    // The same path a CloudKit import takes into the store's planning state.
    tablet.focus.reconcileExternalState(at: planning).synchronousResult

    let phoneQueue = phone.focus.refreshScheduledFocus(at: planning).synchronousResult
    let tabletQueue = tablet.focus.refreshScheduledFocus(at: planning.addingTimeInterval(120)).synchronousResult
    #expect(phoneQueue.count == 1)
    #expect(phoneQueue.map(\.id) == tabletQueue.map(\.id))
    #expect(phoneQueue.first?.id == FocusSessionIdentity.block(
        taskID: task.id, startAtMs: block.startAtMs, endAtMs: block.endAtMs
    ))
}
