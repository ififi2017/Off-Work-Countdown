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
@Test("With nothing planned after it, the chain stops at the break so the activity can retire")
func chainStopsAfterTheBreakWhenNothingIsPlanned() throws {
    let store = try chainStore()
    let at = try #require(chainDay(store, hour: 9, minute: 0))
    let first = try #require(store.focusDayCanvas(at: at).blocks.first { $0.kind == .task })
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    _ = store.assign(task, toBlockStartingAt: first.startAtMs, at: at)
    #expect(store.startFocus(task: task, inBlockStartingAt: first.startAtMs, at: at))

    let session = try #require(store.activeFocusSession())
    let chain = store.focusChain(for: session, at: at)
    #expect(chain.count == 2)
    #expect(chain.last?.kind == .shortBreak)
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
@Test("A shift whose remaining blocks all belong to others cannot take one more")
func addableBlockIsNilWhenTheShiftIsFull() {
    let full = [
        chainBlock(0, start: 0, end: 100, taskID: UUID()),
        chainBlock(1, start: 100, end: 200, taskID: UUID()),
    ]
    #expect(FocusLiveChain.addableBlock(blocks: full, fromMs: 0) == nil)

    let withRoom = full + [chainBlock(2, start: 200, end: 300, taskID: nil)]
    #expect(FocusLiveChain.addableBlock(blocks: withRoom, fromMs: 0)?.startAtMs == 200)
    // An empty block already behind the running one is not somewhere to put
    // the next pomodoro.
    #expect(FocusLiveChain.addableBlock(blocks: withRoom, fromMs: 300) == nil)
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
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
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
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
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
    // 12:20 leaves five minutes before the lunch gap, so the block is cut.
    let at = try #require(chainDay(store, hour: 12, minute: 20))
    let task = chainTask(store, title: "Spec review", pomodoros: 1, at: at)
    #expect(store.startFocus(task: task))

    let session = try #require(store.activeFocusSession())
    guard session.plannedEndReason != .completed else { return }
    let alerts = store.focusAlerts(for: session)
    #expect(alerts.count == 1)
    #expect(alerts[0].slot == .end)
}

// MARK: - Fixtures

@MainActor
private func chainStore() throws -> OffWorkStore {
    let suite = "FocusLiveChainTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
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
