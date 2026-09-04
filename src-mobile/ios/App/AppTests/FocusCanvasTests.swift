import Foundation
import Testing
@testable import App

/// The arrangement contracts 014 introduces. The behaviour suites in
/// `FocusStoreTests` and `FocusPlannerTests` keep their own assertions; this
/// file only describes what the canvas promises.

@MainActor
@Test("Enabling the health reminder does not move a single block")
func microBreaksNoLongerCutTheGrid() throws {
    // F6, at the level where it actually bit: the grid was cut by micro-break
    // times filtered to "later than now", so the same shift produced different
    // block keys in the morning and in the afternoon — and a plan is stored
    // against those keys.
    let store = try canvasStore()
    let morning = try #require(day(store, hour: 9, minute: 30))
    let afternoon = try #require(day(store, hour: 15, minute: 30))

    store.microBreakEnabled = false
    let quiet = store.focusWorkBlocks(at: morning).map(\.startAtMs)

    store.microBreakEnabled = true
    store.microBreakIntervalMinutes = 30
    #expect(store.focusWorkBlocks(at: morning).map(\.startAtMs) == quiet)
    #expect(store.focusWorkBlocks(at: afternoon).map(\.startAtMs) == quiet)
}

@MainActor
@Test("The canvas marks past, current and future blocks from the clock alone")
func canvasBlockStatesFollowTheClock() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 10, minute: 5))
    let canvas = store.focusDayCanvas(at: at)

    #expect(!canvas.blocks.isEmpty)
    let current = try #require(canvas.currentBlock)
    #expect(current.startAtMs <= Int64(at.timeIntervalSince1970 * 1_000))
    #expect(current.endAtMs > Int64(at.timeIntervalSince1970 * 1_000))
    #expect(canvas.blocks.filter { $0.state == .current }.count == 1)
    #expect(canvas.blocks.contains { $0.state == .past })
    #expect(canvas.blocks.contains { $0.state == .future })
    #expect(canvas.nowAtMs != nil)
}

@MainActor
@Test("A break block is never an editing target")
func breakBlocksAreNotEditable() throws {
    // The planning grid used to draw them as buttons. Both writes reject a
    // non-task block, so every choice in that sheet was a silent no-op that
    // still played a haptic — and its clear action detached the day from its
    // template.
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let canvas = store.focusDayCanvas(at: at)
    let breaks = canvas.blocks.filter { $0.kind == .breakTime }
    #expect(!breaks.isEmpty)
    #expect(breaks.allSatisfy { !$0.isEditable })
    #expect(canvas.blocks.filter { $0.state == .past }.allSatisfy { !$0.isEditable })
}

@MainActor
@Test("A shift's leftover tail is reported as a gap, not as a block")
func canvasReportsTheUnusableTail() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let canvas = store.focusDayCanvas(at: at)
    #expect(canvas.gaps.contains { $0.kind == .betweenSegments })
    #expect(canvas.gaps.contains { $0.kind == .tail })
    // Nothing overlaps: gaps sit strictly between blocks.
    for gap in canvas.gaps {
        #expect(!canvas.blocks.contains { $0.startAtMs < gap.endAtMs && $0.endAtMs > gap.startAtMs })
    }
}

@MainActor
@Test("One tap on a favourite lands in the next empty block")
func favouriteLandsInTheNextEmptyBlock() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let expected = try #require(store.focusDayCanvas(at: at).nextEmptyBlock)

    let favorite = makeTask(store, title: "Weekly report", favorite: true, at: at)
    let result = store.placeFavoriteInNextEmptyBlock(favorite, at: at)
    #expect(result == .placed(taskID: placedID(result), blockStartAtMs: expected.startAtMs))

    let canvas = store.focusDayCanvas(at: at)
    let filled = try #require(canvas.blocks.first { $0.startAtMs == expected.startAtMs })
    #expect(filled.taskTitle == "Weekly report")
    #expect(canvas.nextEmptyBlock?.startAtMs != expected.startAtMs)
}

@MainActor
@Test("With no empty block left the task is still created, and says so")
func favouriteWithoutRoomIsNotSilent() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    var guard_ = 0
    while store.focusDayCanvas(at: at).nextEmptyBlock != nil, guard_ < 40 {
        _ = store.createFocusTaskInNextEmptyBlock(title: "Filler \(guard_)", at: at)
        guard_ += 1
    }
    #expect(store.focusDayCanvas(at: at).nextEmptyBlock == nil)

    let favorite = makeTask(store, title: "Extra", favorite: true, at: at)
    let result = store.placeFavoriteInNextEmptyBlock(favorite, at: at)
    guard case .addedUnscheduled(let taskID) = result else {
        Issue.record("expected the task to be created without a block, got \(result)")
        return
    }
    let canvas = store.focusDayCanvas(at: at)
    let row = try #require(canvas.tasks.first { $0.id == taskID })
    #expect(!row.isScheduled)
}

@MainActor
@Test("Block-first creation makes the task inside the block")
func blockFirstCreationNeedsNoExistingTask() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let target = try #require(store.focusDayCanvas(at: at).nextEmptyBlock)

    let result = store.createFocusTask(title: "Spec review", inBlockStartingAt: target.startAtMs, at: at)
    #expect(result == .placed(taskID: placedID(result), blockStartAtMs: target.startAtMs))
    let canvas = store.focusDayCanvas(at: at)
    #expect(canvas.blocks.first { $0.startAtMs == target.startAtMs }?.taskTitle == "Spec review")
    #expect(canvas.tasks.contains { $0.title == "Spec review" && $0.assignedBlocks == 1 })
}

@MainActor
@Test("Progress counts scheduled blocks, leaving the manual estimate alone")
func progressCountsScheduledBlocks() throws {
    // Block-first has to stay coherent without touching estimate semantics:
    // a manual estimate is what the user intended, the schedule is what they
    // drew. The row reports both rather than reconciling them.
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let task = makeTask(store, title: "Deep work", pomodoros: 1, at: at)
    let blocks = store.focusDayCanvas(at: at).blocks.filter { $0.isEditable && !$0.isAssigned }
    #expect(blocks.count >= 2)
    _ = store.assign(task, toBlockStartingAt: blocks[0].startAtMs, at: at)
    _ = store.assign(task, toBlockStartingAt: blocks[1].startAtMs, at: at)

    let row = try #require(store.focusDayCanvas(at: at).tasks.first { $0.id == task.id })
    #expect(row.assignedBlocks == 2)
    #expect(row.estimatedBlocks == 1)
    #expect(row.completedBlocks == 0)
}

@MainActor
@Test("A task scheduled for a later day is offered and files under the shift it lands in")
func assigningRepatriatesAFutureTask() throws {
    // F2: the page list and the assignment sheet asked two different
    // questions, so a task created for tomorrow was visible on one and
    // unselectable on the other.
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let tomorrow = at.addingTimeInterval(86_400)
    let task = makeTask(store, title: "Tomorrow's thing", at: tomorrow)

    #expect(store.focusTasksForCanvas(at: at).contains { $0.id == task.id })
    let target = try #require(store.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.assign(task, toBlockStartingAt: target.startAtMs, at: at)

    let moved = try #require(store.records.state.focusTasks.first { $0.id == task.id })
    #expect(store.recordsCalendar.isDate(
        try #require(moved.plannedForDate),
        inSameDayAs: at
    ))
}

@MainActor
@Test("The cadence lock the sheet shows is the one the store enforces")
func timerLockReasonMatchesTheStore() throws {
    // F5: the sheet locked on "this day has a saved plan" while the store
    // rejects on "any template exists". With a template and no plan, the
    // fields were editable, Save was enabled, and the write was dropped.
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    #expect(store.focusTimerSettingsLockReason == nil)
    #expect(store.updateFocusTimerSettings(FocusTimerSettings(focusMinutes: 30)))

    let target = try #require(store.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.createFocusTask(title: "Anything", inBlockStartingAt: target.startAtMs, at: at)
    _ = store.saveFocusTemplate(name: "Default", at: at)

    #expect(store.focusTimerSettingsLockReason == .hasTemplates)
    #expect(!store.updateFocusTimerSettings(FocusTimerSettings(focusMinutes: 45)))
}

@MainActor
@Test("Without Plus the canvas carries a shape and no values")
func lockedCanvasCarriesNoData() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let target = try #require(store.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.createFocusTask(title: "Private", inBlockStartingAt: target.startAtMs, at: at)

    store.plus.debugSetAuthorized(false)
    let locked = store.focusDayCanvas(at: at)
    #expect(locked.isLocked)
    #expect(!locked.blocks.isEmpty)
    #expect(locked.blocks.allSatisfy { $0.taskTitle == nil && $0.taskID == nil })
    #expect(locked.tasks.isEmpty)
    #expect(store.placeFavoriteInNextEmptyBlock(
        makeTask(store, title: "Nope", favorite: true, at: at), at: at
    ) == .locked)
}

@MainActor
@Test("Band density keeps a focus block above the minimum hit target")
func bandDensityClearsTheHitTarget() {
    for minutes in [10, 25, 30, 45, 60] {
        let pph = FocusDayCanvasModel.pointsPerHour(focusMinutes: minutes)
        let blockHeight = Double(minutes) / 60 * pph
        #expect(blockHeight >= 44)
    }
    // Strictly proportional: a five-minute break really is a fifth of a
    // twenty-five-minute block, with no minimum inflating it.
    var model = FocusDayCanvasModel.empty
    model.pointsPerHour = FocusDayCanvasModel.pointsPerHour(focusMinutes: 25)
    #expect(abs(model.height(ofMs: 25 * 60_000) - 44) < 0.01)
    #expect(abs(model.height(ofMs: 5 * 60_000) - 8.8) < 0.01)
    #expect(model.height(ofMs: 60_000) < 2)
}

// MARK: - helpers

@MainActor
private func canvasStore() throws -> OffWorkStore {
    let suite = "FocusCanvasTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let store = OffWorkStore(defaults: defaults, records: .inMemory())
    store.plus.debugSetAuthorized(true)
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    return store
}

@MainActor
private func day(_ store: OffWorkStore, hour: Int, minute: Int) -> Date? {
    store.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: hour, minute: minute)
    )
}

@MainActor
private func makeTask(
    _ store: OffWorkStore,
    title: String,
    pomodoros: Int = 1,
    favorite: Bool = false,
    at date: Date
) -> FocusTask {
    let task = FocusTask(
        id: UUID(),
        createdAt: date,
        plannedForDate: store.recordsCalendar.startOfDay(for: date),
        scheduledStartAt: nil,
        title: title,
        estimatedPomodoros: pomodoros,
        isFavorite: favorite,
        completedAt: nil,
        sortIndex: 0,
        editedAt: date,
        editCount: 0,
        editTieBreaker: UUID()
    )
    store.records.upsertFocusTask(task)
    return task
}

private func placedID(_ result: FocusPlacementResult) -> UUID {
    if case .placed(let taskID, _) = result { return taskID }
    return UUID()
}

// MARK: - the health reminder takeover

@MainActor
@Test("A planned shift hands its break rhythm to the pomodoro")
func plannedShiftTakesOverTheHealthReminder() throws {
    // The two used to run on separate clocks: a reminder every 60 minutes
    // against a break every 25. Worse, the reminder's times were fed back in
    // as hard cuts, so turning it on re-sliced the grid.
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    store.microBreakEnabled = true
    store.microBreakIntervalMinutes = 60
    #expect(!store.focusOwnsBreaks(at: at))

    let target = try #require(store.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.createFocusTask(title: "Spec review", inBlockStartingAt: target.startAtMs, at: at)
    #expect(store.focusOwnsBreaks(at: at))

    let reminders = try store.shiftReminders(at: at)
    let shiftEnd = try #require(store.focusCanvasShift(at: at)?.snapshot.segments.map(\.endAtMs).max())
    let shiftStart = try #require(store.focusCanvasShift(at: at)?.snapshot.startAtMs)
    let inShift = reminders.filter {
        $0.kind == "microBreak" && $0.atMs >= shiftStart && $0.atMs <= shiftEnd
    }
    #expect(!inShift.isEmpty)
    // Every one of them now comes from the plan, not from the interval.
    #expect(inShift.allSatisfy { $0.id.hasPrefix("focusBreak:") })
    // Long breaks only: notifying on every short break would roughly triple
    // the interruptions the fixed interval used to produce.
    let longBreakMs = Int64(store.focusTimerSettings.normalized.longBreakMinutes) * 60_000
    let blocks = store.focusWorkBlocks(at: at)
    for reminder in inShift {
        let block = try #require(blocks.first { Double($0.startAtMs) == reminder.atMs })
        #expect(Int64(block.end.timeIntervalSince(block.start) * 1_000) >= longBreakMs)
    }
}

@MainActor
@Test("Clearing the plan gives the fixed interval back")
func clearingThePlanRestoresTheInterval() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    store.microBreakEnabled = true
    store.microBreakIntervalMinutes = 60

    let target = try #require(store.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.createFocusTask(title: "Spec review", inBlockStartingAt: target.startAtMs, at: at)
    #expect(store.focusOwnsBreaks(at: at))

    store.clearBlock(startingAt: target.startAtMs, at: at)
    #expect(!store.focusOwnsBreaks(at: at))
    let reminders = try store.shiftReminders(at: at)
    #expect(reminders.contains { $0.kind == "microBreak" && !$0.id.hasPrefix("focusBreak:") })
    #expect(!reminders.contains { $0.id.hasPrefix("focusBreak:") })
}

@MainActor
@Test("Without Plus the health reminder keeps its own rhythm")
func lockedUsersKeepTheFixedInterval() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    store.microBreakEnabled = true
    let target = try #require(store.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.createFocusTask(title: "Spec review", inBlockStartingAt: target.startAtMs, at: at)

    store.plus.debugSetAuthorized(false)
    #expect(!store.focusOwnsBreaks(at: at))
    #expect(store.focusBreakReminders(at: at).isEmpty)
}
