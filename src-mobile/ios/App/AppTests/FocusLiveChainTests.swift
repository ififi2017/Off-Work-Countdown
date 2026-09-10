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
    let blocks = store.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)

    let running = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    let queued = chainTask(store, title: "Inbox", pomodoros: 1, at: at)
    _ = store.assign(running, toBlockStartingAt: first.startAtMs, at: at)
    _ = store.assign(queued, toBlockStartingAt: second.startAtMs, at: at)
    #expect(store.startFocus(task: running, inBlockStartingAt: first.startAtMs, at: at))

    let session = try #require(store.activeFocusSession())
    let chain = store.focusChain(for: session, at: at)

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
    let first = try #require(store.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))

    let session = try #require(store.activeFocusSession())
    let chain = store.focusChain(for: session, at: at)
    #expect(chain.count == 1)
    #expect(chain.last?.kind == .focus)
    #expect(store.completesFocusDay(after: session, at: at))
}

@MainActor
@Test("A two-block task names the clock time its last block ends")
func chainProjectsTheTaskFinishTime() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)

    let task = chainTask(store, title: "Spec review", pomodoros: 2, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    _ = store.assign(task, toBlockStartingAt: second.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))

    let session = try #require(store.activeFocusSession())
    let chain = store.focusChain(for: session, at: at)
    #expect(chain[0].pomodoroIndex == 1)
    #expect(chain[0].pomodoroTotal == 2)
    #expect(chain[0].taskFinishAt == Date(timeIntervalSince1970: Double(second.endAtMs) / 1_000))
}

@MainActor
@Test("A finish time is withheld rather than guessed when the shift runs out")
func chainWithholdsAnImpossibleFinishTime() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    // More blocks than the whole shift holds, so no honest hour exists.
    let task = chainTask(store, title: "Spec review", pomodoros: 99, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))

    let session = try #require(store.activeFocusSession())
    #expect(store.focusChain(for: session, at: at)[0].taskFinishAt == nil)
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
    let blocks = store.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)

    let running = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    let other = chainTask(store, title: "Inbox", pomodoros: 1, at: at)
    _ = store.assign(running, toBlockStartingAt: first.startAtMs, at: at)
    _ = store.assign(other, toBlockStartingAt: second.startAtMs, at: at)
    #expect(store.startFocus(task: running, inBlockStartingAt: first.startAtMs, at: at))

    // The next block belongs to Inbox. The plus greys out rather than taking
    // it, and the write refuses for exactly the same reason — one resolver
    // answers both.
    #expect(!store.canAddFocusPomodoro(at: at))
    #expect(!store.addFocusPomodoroToRunningTask(at: at))
    #expect(store.records.state.focusTasks.first { $0.id == running.id }?.estimatedPomodoros == 1)
}

@MainActor
@Test("Adding a pomodoro raises the estimate and places the block in one step")
func addingAPomodoroPlacesTheBlock() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))

    #expect(store.canAddFocusPomodoro(at: at))
    #expect(store.addFocusPomodoroToRunningTask(at: at))

    let reloaded = try #require(store.records.state.focusTasks.first { $0.id == task.id })
    #expect(reloaded.estimatedPomodoros == 2)
    let assigned = store.focusDayCanvas(at: at).blocks.filter { $0.taskID == task.id }
    #expect(assigned.count == 2)
}

@MainActor
@Test("A break with no task behind it is not offered one more block")
func breaksDoNotOfferAnExtraPomodoro() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))

    let end = try #require(store.activeFocusSession()).plannedEndAt
    #expect(store.finishElapsedFocusSession(at: end))
    #expect(store.activeFocusSession()?.kind != .focus)
    #expect(!store.canAddFocusPomodoro(at: end))
}

@MainActor
@Test("A completed block's break starts with it, from the block's own end")
func completedBlockStartsItsBreakAutomatically() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 2, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))

    let end = try #require(store.activeFocusSession()).plannedEndAt
    #expect(store.finishElapsedFocusSession(at: end.addingTimeInterval(30)))

    let running = try #require(store.activeFocusSession())
    #expect(running.kind == .shortBreak)
    #expect(running.startedAt == end)
    #expect(store.focusLastNextAction == .none)
}

@MainActor
@Test("Coming back after the break window does not backfill a break nobody took")
func lateReturnDoesNotBackfillABreak() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 2, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))

    let end = try #require(store.activeFocusSession()).plannedEndAt
    #expect(store.finishElapsedFocusSession(at: end.addingTimeInterval(45 * 60)))

    #expect(store.activeFocusSession() == nil)
    #expect(store.focusLastNextAction == .startShortBreak)
}

@MainActor
@Test("A block's alerts name the task and say when the break ends")
func focusAlertsDescribeTheWholePhase() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 2, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))

    let session = try #require(store.activeFocusSession())
    let alerts = store.focusAlerts(for: session)
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
        shiftAnchorDate: store.recordsCalendar.startOfDay(for: at),
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

    let session = try #require(store.activeFocusSession())
    // It stopped at lunch instead of finishing, so it earned no break and has
    // nothing to say about one.
    let alerts = store.focusAlerts(for: session)
    #expect(alerts.count == 1)
    #expect(alerts[0].slot == .end)
    #expect(alerts[0].title == "Spec review")
    #expect(store.focusChain(for: session, at: at).count == 1)
}

// MARK: - Fixtures

@MainActor
private func chainStore() throws -> OffWorkStore {
    let suite = "FocusLiveChainTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    TestTimeZone.pin(defaults)
    let store = OffWorkStore(defaults: defaults, records: .inMemory())
    store.plus.debugSetAuthorized(true)
    store.countdownStarted = true
    store.languageOverride = "en"
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    return store
}

/// A Monday, so the default recurring schedule is a workday.
@MainActor
private func chainDay(_ store: OffWorkStore, hour: Int, minute: Int) -> Date? {
    store.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: hour, minute: minute)
    )
}

@MainActor
private func chainTask(
    _ store: OffWorkStore,
    title: String,
    pomodoros: Int,
    at date: Date
) -> FocusTask {
    let task = FocusTask(
        id: UUID(),
        createdAt: date,
        plannedForDate: store.recordsCalendar.startOfDay(for: date),
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
    let blocks = store.focusDayCanvas(at: planning).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)
    let one = chainTask(store, title: "One", pomodoros: 1, at: planning)
    let two = chainTask(store, title: "Two", pomodoros: 1, at: planning)
    _ = store.assign(one, toBlockStartingAt: first.startAtMs, at: planning)
    _ = store.assign(two, toBlockStartingAt: second.startAtMs, at: planning)
    let queued = store.refreshScheduledFocus(at: planning)
    #expect(queued.count == 2)
    #expect(store.activeFocusSession() == nil)
    #expect(store.refreshScheduledFocus(at: planning).map(\.id) == queued.map(\.id))

    let wake = Date(timeIntervalSince1970: Double(second.startAtMs) / 1_000 + 60)
    store.restoreScheduledFocus(at: wake)
    let running = try #require(store.activeFocusSession())
    #expect(running.taskID == two.id)
    #expect(running.startedAt == queued[1].startedAt)
    #expect(running.plannedEndAt == queued[1].plannedEndAt)
    #expect(store.completedFocusBlocks(for: one) == 1)
    store.restoreScheduledFocus(at: wake)
    #expect(store.records.state.focusSessions.filter { $0.id == running.id }.count == 1)
}

@MainActor
@Test("A task assigned during recovery starts at the next block's absolute boundary")
func taskAssignedDuringBreakStartsAutomatically() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let first = try #require(blocks.first)
    let second = try #require(blocks.dropFirst().first)
    let one = chainTask(store, title: "One", pomodoros: 2, at: at)
    _ = store.assign(one, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: one, inBlockStartingAt: first.startAtMs, at: at))
    let end = try #require(store.activeFocusSession()).plannedEndAt
    #expect(store.finishElapsedFocusSession(at: end))
    #expect(store.activeFocusSession()?.kind == .shortBreak)
    let two = chainTask(store, title: "Added during break", pomodoros: 1, at: end)
    _ = store.assign(two, toBlockStartingAt: second.startAtMs, at: end)
    #expect(store.refreshScheduledFocus(at: end).count == 1)
    let start = Date(timeIntervalSince1970: Double(second.startAtMs) / 1_000)
    store.restoreScheduledFocus(at: start.addingTimeInterval(20))
    #expect(store.activeFocusSession()?.taskID == two.id)
    #expect(store.activeFocusSession()?.startedAt == start)
}

@MainActor
@Test("Clearing an assignment cancels its armed start; stopped blocks never restart")
func clearingOrStoppingDoesNotRestartScheduledFocus() throws {
    let store = try chainStore()
    let planning = try #require(chainDay(store, hour: 8, minute: 30))
    let block = try #require(store.focusDayCanvas(at: planning).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "One", pomodoros: 1, at: planning)
    _ = store.assign(task, toBlockStartingAt: block.startAtMs, at: planning)
    #expect(store.refreshScheduledFocus(at: planning).count == 1)
    let workBlock = try #require(store.focusWorkBlocks(at: planning).first { $0.startAtMs == block.startAtMs })
    store.clearFocusBlock(workBlock, at: planning)
    #expect(store.refreshScheduledFocus(at: planning).isEmpty)
    let start = Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)
    store.restoreScheduledFocus(at: start)
    #expect(store.activeFocusSession() == nil)

    _ = store.assign(task, toBlockStartingAt: block.startAtMs, at: start)
    store.refreshScheduledFocus(at: start)
    let session = try #require(store.activeFocusSession())
    #expect(!store.stopFocusFromActivity(startAtMs: block.startAtMs - 1, at: start.addingTimeInterval(60)))
    #expect(store.stopFocusFromActivity(startAtMs: block.startAtMs, at: start.addingTimeInterval(60)))
    #expect(store.refreshScheduledFocus(at: start.addingTimeInterval(90)).isEmpty)
    #expect(store.activeFocusSession() == nil)
    #expect(store.records.state.focusSessions.first { $0.id == session.id }?.endReason == .stoppedByUser)
}

@MainActor
@Test("An unarmed past assignment creates no completed focus history")
func pastUnarmedAssignmentsDoNotCreateHistory() throws {
    let store = try chainStore()
    let planning = try #require(chainDay(store, hour: 8, minute: 30))
    let block = try #require(store.focusDayCanvas(at: planning).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Unarmed", pomodoros: 1, at: planning)
    _ = store.assign(task, toBlockStartingAt: block.startAtMs, at: planning)
    store.refreshScheduledFocus(at: Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000 + 60))
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
        shiftAnchorDate: store.recordsCalendar.startOfDay(for: at),
        startedAt: at, plannedEndAt: at.addingTimeInterval(25 * 60),
        endedAt: nil, endReason: nil, editedAt: at, editCount: 0,
        editTieBreaker: UUID(), kind: kind, plannedEndReason: .completed
    )
    store.records.upsertFocusSession(session)
    #expect(store.completesFocusDay(after: session, at: at))
    #expect(store.focusChain(for: session, at: at).count == 1)
    #expect(store.finishElapsedFocusSession(at: session.plannedEndAt))
    #expect(store.activeFocusSession() == nil)
    #expect(store.focusDayComplete(at: session.plannedEndAt))
}

@MainActor
@Test("The last queued block includes the currently running block in day completion")
func finalQueuedBlockCompletesRunningTask() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    let task = chainTask(store, title: "Two blocks", pomodoros: 2, at: at)
    for block in blocks.prefix(2) {
        _ = store.assign(task, toBlockStartingAt: block.startAtMs, at: at)
    }
    let queued = store.refreshScheduledFocus(at: at)
    let running = try #require(store.activeFocusSession())
    #expect(!store.completesFocusDay(after: running, at: at))
    let last = try #require(queued.last)
    #expect(store.completesFocusDay(after: last, at: at))
}

@MainActor
@Test("Activity actions open confirmation without changing the running task")
func activityActionsRequireConfirmation() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Review", pomodoros: 1, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))
    let session = try #require(store.activeFocusSession())
    let start = Int64(session.startedAt.timeIntervalSince1970 * 1_000)

    for action in [FocusActivityRequest.Action.addPomodoros, .stop] {
        store.requestFocusActivityConfirmation(action, startAtMs: start)
        let request = try #require(store.focusActivityRequest)
        #expect(request.action == action)
        #expect(store.selectedTab == .focus)
        #expect(store.focusPath.isEmpty)
        #expect(store.matchesFocusActivity(request, at: at))
        #expect(!store.matchesFocusActivity(request, at: session.plannedEndAt))
        #expect(store.activeFocusSession()?.id == session.id)
        #expect(store.records.state.focusTasks.first { $0.id == task.id }?.estimatedPomodoros == 1)
    }
    #expect(!store.matchesFocusActivity(.init(action: .stop, startAtMs: start - 1), at: at))
}

@MainActor
@Test("Adding several pomodoros stops before the next task and rejects excess without edits")
func extraPomodorosRespectNextTask() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let blocks = store.focusDayCanvas(at: at).blocks.filter { $0.kind == .task }
    try #require(blocks.count >= 4)
    let task = chainTask(store, title: "Review", pomodoros: 1, at: at)
    let next = chainTask(store, title: "Next task", pomodoros: 1, at: at)
    _ = store.assign(task, toBlockStartingAt: blocks[0].startAtMs, at: at)
    _ = store.assign(next, toBlockStartingAt: blocks[3].startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: blocks[0].startAtMs, at: at))
    #expect(store.addableFocusBlocks(at: at).count == 2)
    #expect(!store.addFocusPomodoroToRunningTask(count: 3, at: at))
    #expect(store.records.state.focusTasks.first { $0.id == task.id }?.estimatedPomodoros == 1)
    #expect(store.addFocusPomodoroToRunningTask(count: 2, at: at))
    #expect(store.addableFocusBlocks(at: at).isEmpty)
    #expect(store.records.state.focusTasks.first { $0.id == task.id }?.estimatedPomodoros == 3)
    #expect(store.focusDayCanvas(at: at).blocks.first { $0.startAtMs == blocks[3].startAtMs }?.taskID == next.id)
}

@MainActor
@Test("Focus tab navigation preserves the other tabs and never requests a paywall")
func focusTabNavigationPreservesOtherTabs() throws {
    let store = try chainStore()
    store.timerPath = [.about]
    store.settingsPath = [.language]
    store.focusPath = [.plus]
    store.presentedRoute = .focus
    store.openFocusTab()
    #expect(store.selectedTab == .focus)
    #expect(store.focusPath.isEmpty)
    #expect(store.timerPath == [.about])
    #expect(store.settingsPath == [.language])
    #expect(store.presentedRoute == nil)
    #expect(store.paywallSheet == nil)
    store.activePath = [.plus]
    #expect(store.focusPath == [.plus])
    #expect(store.timerPath == [.about])
}
