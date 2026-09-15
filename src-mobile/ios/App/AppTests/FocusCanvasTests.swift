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

    store.preferences.applyPreferences { $0.microBreakEnabled = false }
    let quiet = store.focus.focusWorkBlocks(at: morning).map(\.startAtMs)

    store.preferences.applyPreferences { $0.microBreakEnabled = true }
    store.preferences.applyPreferences { $0.microBreakIntervalMinutes = 30 }
    #expect(store.focus.focusWorkBlocks(at: morning).map(\.startAtMs) == quiet)
    #expect(store.focus.focusWorkBlocks(at: afternoon).map(\.startAtMs) == quiet)
}

@MainActor
@Test("The canvas marks past, current and future blocks from the clock alone")
func canvasBlockStatesFollowTheClock() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 10, minute: 5))
    let canvas = store.focus.focusDayCanvas(at: at)

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
    let canvas = store.focus.focusDayCanvas(at: at)
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
    let canvas = store.focus.focusDayCanvas(at: at)
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
    let expected = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)

    let favorite = makeTask(store, title: "Weekly report", favorite: true, at: at)
    let result = store.focus.placeFavoriteInNextEmptyBlock(favorite, at: at).synchronousResult
    #expect(result == .placed(taskID: placedID(result), blockStartAtMs: expected.startAtMs))

    let canvas = store.focus.focusDayCanvas(at: at)
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
    while store.focus.focusDayCanvas(at: at).nextEmptyBlock != nil, guard_ < 40 {
        _ = store.focus.createFocusTaskInNextEmptyBlock(title: "Filler \(guard_)", at: at).synchronousResult
        guard_ += 1
    }
    #expect(store.focus.focusDayCanvas(at: at).nextEmptyBlock == nil)

    let favorite = makeTask(store, title: "Extra", favorite: true, at: at)
    let result = store.focus.placeFavoriteInNextEmptyBlock(favorite, at: at).synchronousResult
    guard case .addedUnscheduled(let taskID) = result else {
        Issue.record("expected the task to be created without a block, got \(result)")
        return
    }
    let canvas = store.focus.focusDayCanvas(at: at)
    let row = try #require(canvas.tasks.first { $0.id == taskID })
    #expect(!row.isScheduled)
}

@MainActor
@Test("Block-first creation makes the task inside the block")
func blockFirstCreationNeedsNoExistingTask() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let target = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)

    let result = store.focus.createFocusTask(title: "Spec review", inBlockStartingAt: target.startAtMs, at: at).synchronousResult
    #expect(result == .placed(taskID: placedID(result), blockStartAtMs: target.startAtMs))
    let canvas = store.focus.focusDayCanvas(at: at)
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
    let blocks = store.focus.focusDayCanvas(at: at).blocks.filter { $0.isEditable && !$0.isAssigned }
    #expect(blocks.count >= 2)
    _ = store.focus.assign(task, toBlockStartingAt: blocks[0].startAtMs, at: at).synchronousResult
    _ = store.focus.assign(task, toBlockStartingAt: blocks[1].startAtMs, at: at).synchronousResult

    let row = try #require(store.focus.focusDayCanvas(at: at).tasks.first { $0.id == task.id })
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

    #expect(store.focus.focusTasksForCanvas(at: at).contains { $0.id == task.id })
    let target = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.focus.assign(task, toBlockStartingAt: target.startAtMs, at: at).synchronousResult

    let moved = try #require(store.records.state.focusTasks.first { $0.id == task.id })
    #expect(store.preferences.recordsCalendar.isDate(
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
    #expect(store.focus.focusTimerSettingsLockReason == nil)
    #expect(store.focus.updateFocusTimerSettings(FocusTimerSettings(focusMinutes: 30)).synchronousResult)

    let target = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.focus.createFocusTask(title: "Anything", inBlockStartingAt: target.startAtMs, at: at).synchronousResult
    _ = store.focus.saveFocusTemplate(name: "Default", at: at).synchronousResult

    #expect(store.focus.focusTimerSettingsLockReason == .hasTemplates)
    #expect(!store.focus.updateFocusTimerSettings(FocusTimerSettings(focusMinutes: 45)).synchronousResult)
}

@MainActor
@Test("Without Plus the canvas carries a shape and no values")
func lockedCanvasCarriesNoData() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let target = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.focus.createFocusTask(title: "Private", inBlockStartingAt: target.startAtMs, at: at).synchronousResult

    store.plus.debugSetAuthorized(false)
    let locked = store.focus.focusDayCanvas(at: at)
    #expect(locked.isLocked)
    #expect(!locked.blocks.isEmpty)
    #expect(locked.blocks.allSatisfy { $0.taskTitle == nil && $0.taskID == nil })
    #expect(locked.tasks.isEmpty)
    #expect(store.focus.placeFavoriteInNextEmptyBlock(
        makeTask(store, title: "Nope", favorite: true, at: at), at: at
    ).synchronousResult == .locked)
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
private func canvasStore() throws -> AppRuntime {
    let suite = "FocusCanvasTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let store = AppRuntime(defaults: defaults, records: .inMemory())
    store.plus.debugSetAuthorized(true)
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
    store.preferences.applyPreferences { $0.lunchEnabled = true }
    return store
}

@MainActor
private func day(_ store: AppRuntime, hour: Int, minute: Int) -> Date? {
    store.preferences.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: hour, minute: minute)
    )
}

@MainActor
private func makeTask(
    _ store: AppRuntime,
    title: String,
    pomodoros: Int = 1,
    favorite: Bool = false,
    at date: Date
) -> FocusTask {
    let task = FocusTask(
        id: UUID(),
        createdAt: date,
        plannedForDate: store.preferences.recordsCalendar.startOfDay(for: date),
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
    store.preferences.applyPreferences { $0.microBreakEnabled = true }
    store.preferences.applyPreferences { $0.microBreakIntervalMinutes = 60 }
    #expect(!store.focus.focusOwnsBreaks(at: at))

    let target = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.focus.createFocusTask(title: "Spec review", inBlockStartingAt: target.startAtMs, at: at).synchronousResult
    #expect(store.focus.focusOwnsBreaks(at: at))

    let reminders = store.shifts.shiftReminders(at: at)
    let shiftEnd = try #require(store.focus.focusCanvasShift(at: at)?.snapshot.segments.map(\.endAtMs).max())
    let shiftStart = try #require(store.focus.focusCanvasShift(at: at)?.snapshot.startAtMs)
    let inShift = reminders.filter {
        $0.kind == "microBreak" && $0.atMs >= shiftStart && $0.atMs <= shiftEnd
    }
    #expect(!inShift.isEmpty)
    // Every one of them now comes from the plan, not from the interval.
    #expect(inShift.allSatisfy { $0.id.hasPrefix("focusBreak:") })
    // Long breaks only: notifying on every short break would roughly triple
    // the interruptions the fixed interval used to produce.
    let longBreakMs = Int64(store.focus.focusTimerSettings.normalized.longBreakMinutes) * 60_000
    let blocks = store.focus.focusWorkBlocks(at: at)
    for reminder in inShift {
        let block = try #require(blocks.first { Double($0.startAtMs) == reminder.atMs })
        #expect(Int64(block.end.timeIntervalSince(block.start) * 1_000) >= longBreakMs)
    }
}

@MainActor
@Test("The settings row stops advertising an interval nothing counts to")
func healthLabelSaysWhoOwnsTheBreaks() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    store.preferences.applyPreferences { $0.microBreakEnabled = true }
    store.preferences.applyPreferences { $0.microBreakIntervalMinutes = 60 }
    #expect(store.shifts.healthLabel(at: at) == store.text.t("minutesShort", values: ["count": "60"]))

    let target = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.focus.createFocusTask(title: "Spec review", inBlockStartingAt: target.startAtMs, at: at).synchronousResult
    #expect(store.shifts.healthLabel(at: at) == store.text.t("microBreakFollowsFocus"))

    // Clearing the plan hands the interval back, and switching the reminder
    // off outranks both — an off reminder is not "following" anything.
    store.focus.clearBlock(startingAt: target.startAtMs, at: at).synchronousResult
    #expect(store.shifts.healthLabel(at: at) == store.text.t("minutesShort", values: ["count": "60"]))
    store.preferences.applyPreferences { $0.microBreakEnabled = false }
    #expect(store.shifts.healthLabel(at: at) == store.text.t("disabledShort"))
}

@MainActor
@Test("Clearing the plan gives the fixed interval back")
func clearingThePlanRestoresTheInterval() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    store.preferences.applyPreferences { $0.microBreakEnabled = true }
    store.preferences.applyPreferences { $0.microBreakIntervalMinutes = 60 }

    let target = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.focus.createFocusTask(title: "Spec review", inBlockStartingAt: target.startAtMs, at: at).synchronousResult
    #expect(store.focus.focusOwnsBreaks(at: at))

    store.focus.clearBlock(startingAt: target.startAtMs, at: at).synchronousResult
    #expect(!store.focus.focusOwnsBreaks(at: at))
    let reminders = store.shifts.shiftReminders(at: at)
    #expect(reminders.contains { $0.kind == "microBreak" && !$0.id.hasPrefix("focusBreak:") })
    #expect(!reminders.contains { $0.id.hasPrefix("focusBreak:") })
}

@MainActor
@Test("Without Plus the health reminder keeps its own rhythm")
func lockedUsersKeepTheFixedInterval() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    store.preferences.applyPreferences { $0.microBreakEnabled = true }
    let target = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)
    _ = store.focus.createFocusTask(title: "Spec review", inBlockStartingAt: target.startAtMs, at: at).synchronousResult

    store.plus.debugSetAuthorized(false)
    #expect(!store.focus.focusOwnsBreaks(at: at))
    #expect(store.focus.focusBreakReminders(at: at).isEmpty)
}

@MainActor
@Test("The shift the band draws is the shift a write lands in")
func writesFollowTheDrawnShift() throws {
    // Caught on device, not by the model tests: after clock-off the canvas
    // draws the next shift, but every write resolved its block through
    // `snapshot(at:)` — always today's — so the band was visible and inert,
    // and each edit returned "no shift".
    let store = try canvasStore()
    let afterWork = try #require(day(store, hour: 21, minute: 0))
    let drawn = try #require(store.focus.focusCanvasShift(at: afterWork))
    #expect(drawn.isNext)

    let canvas = store.focus.focusDayCanvas(at: afterWork)
    let target = try #require(canvas.nextEmptyBlock)
    let task = makeTask(store, title: "Tomorrow morning", at: drawn.snapshot.startDate)

    let result = store.focus.assign(task, toBlockStartingAt: target.startAtMs, at: afterWork).synchronousResult
    #expect(result == .placed(taskID: task.id, blockStartAtMs: target.startAtMs))

    let after = store.focus.focusDayCanvas(at: afterWork)
    #expect(after.blocks.first { $0.startAtMs == target.startAtMs }?.taskTitle == "Tomorrow morning")

    // And it is filed under the drawn shift's day, not today's.
    let dayKey = RecordJSON.dayKey(drawn.snapshot.startDate, calendar: store.preferences.recordsCalendar)
    #expect(store.focus.focusPlanning.plans[dayKey]?.assignments.contains { $0.taskID == task.id } == true)

    store.focus.clearBlock(startingAt: target.startAtMs, at: afterWork).synchronousResult
    #expect(store.focus.focusDayCanvas(at: afterWork).blocks
        .first { $0.startAtMs == target.startAtMs }?.taskTitle == nil)
}

@MainActor
@Test("A block turned into a break reads as a break, and can be turned back")
func convertedBreakIsVisibleAndReversible() throws {
    // On device "make this a break" and "clear this block" were
    // indistinguishable: the canvas took each block's kind from the grid, so a
    // converted block came back as `.task` with no task — exactly what an
    // empty block looks like — and the sheet's clear row, gated on `taskID`,
    // never appeared for it.
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    let target = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)
    #expect(!target.rendersAsBreak)
    #expect(!target.hasAssignment)

    store.focus.markBlockAsBreak(startingAt: target.startAtMs, at: at).synchronousResult
    let converted = try #require(store.focus.focusDayCanvas(at: at).blocks
        .first { $0.startAtMs == target.startAtMs })
    #expect(converted.isUserBreak)
    #expect(converted.rendersAsBreak)
    #expect(converted.hasAssignment)
    // Still a task block underneath, which is what keeps it editable: turning
    // a block into a break must not be a one-way door.
    #expect(converted.kind == .task)
    #expect(converted.isEditable)
    // And it is no longer free, so "put it in the next empty block" skips it.
    #expect(store.focus.focusDayCanvas(at: at).nextEmptyBlock?.startAtMs != target.startAtMs)

    store.focus.clearBlock(startingAt: target.startAtMs, at: at).synchronousResult
    let cleared = try #require(store.focus.focusDayCanvas(at: at).blocks
        .first { $0.startAtMs == target.startAtMs })
    #expect(!cleared.isUserBreak)
    #expect(!cleared.hasAssignment)
    #expect(store.focus.focusDayCanvas(at: at).nextEmptyBlock?.startAtMs == target.startAtMs)
}

@MainActor
@Test("Only assigned focus blocks contribute automatic upcoming breaks")
func upcomingBreaksRequireThePrecedingTask() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 8, minute: 55))
    let shift = try #require(store.session.snapshot(at: at))
    #expect(store.focus.focusPlanAssignments(for: shift).isEmpty)
    let blocks = store.focus.focusPlanningBlocks(for: shift)
    let task = makeTask(store, title: "One task", at: at)
    _ = store.focus.assign(task, toBlockStartingAt: blocks[0].startAtMs, at: at).synchronousResult
    let breaks = store.focus.focusUpcomingTimelineEvents(for: shift, at: at).filter { $0.kind == .focusBreak }
    #expect(breaks.count == 1)
    #expect(breaks.first?.date == blocks[1].start)
    let explicit = try #require(blocks.last(where: { $0.kind == .task }))
    store.focus.markBlockAsBreak(startingAt: explicit.startAtMs, at: at).synchronousResult
    #expect(store.focus.focusPlanAssignments(for: shift).contains {
        $0.block.startAtMs == explicit.startAtMs && $0.assignment.kind == .breakTime
    })
}

@MainActor
@Test("One more round reopens the same task and preserves existing sessions")
func oneMoreRoundKeepsTaskIdentity() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 5))
    var task = makeTask(store, title: "Continue", at: at)
    let blocks = store.focus.focusWorkBlocks(at: at).filter { $0.kind == .task }
    _ = store.focus.assign(task, toBlockStartingAt: blocks[0].startAtMs, at: at).synchronousResult
    task = try #require(store.records.state.focusTasks.first { $0.id == task.id })
    task.completedAt = at
    store.records.upsertFocusTask(task, at: at)
    let sessions = store.records.state.focusSessions
    let added = try store.focus.addOneFocusBlock(taskID: task.id, at: at).synchronousResult.get()
    #expect(added == blocks[1].startAtMs)
    let updated = try #require(store.records.state.focusTasks.first { $0.id == task.id })
    #expect(updated.completedAt == nil)
    #expect(updated.estimatedPomodoros == 2)
    #expect(store.records.state.focusSessions == sessions)
}

@MainActor
@Test("One more round cannot overwrite another task or a user break")
func oneMoreRoundReportsConflicts() throws {
    for userBreak in [false, true] {
        let store = try canvasStore()
        let at = try #require(day(store, hour: 9, minute: 5))
        let task = makeTask(store, title: "Continue", at: at)
        let blocks = store.focus.focusWorkBlocks(at: at).filter { $0.kind == .task }
        _ = store.focus.assign(task, toBlockStartingAt: blocks[0].startAtMs, at: at).synchronousResult
        if userBreak {
            store.focus.markBlockAsBreak(startingAt: blocks[1].startAtMs, at: at).synchronousResult
        } else {
            _ = store.focus.assign(makeTask(store, title: "Next task", at: at), toBlockStartingAt: blocks[1].startAtMs, at: at).synchronousResult
        }
        let before = store.focus.focusPlanning
        guard case .failure(.conflict) = store.focus.addOneFocusBlock(taskID: task.id, at: at).synchronousResult else {
            Issue.record("Expected a conflict")
            return
        }
        #expect(store.focus.focusPlanning == before)
        #expect(store.records.state.focusTasks.first { $0.id == task.id }?.estimatedPomodoros == 1)
    }
}

@MainActor
@Test("One more round cannot jump across lunch")
func oneMoreRoundStopsAtLunch() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 11, minute: 35))
    let task = makeTask(store, title: "Before lunch", at: at)
    let block = try #require(store.focus.focusWorkBlocks(at: at).last {
        $0.kind == .task && $0.start <= at
    })
    _ = store.focus.assign(task, toBlockStartingAt: block.startAtMs, at: at).synchronousResult
    guard case .failure(.noRoom) = store.focus.addOneFocusBlock(taskID: task.id, at: at).synchronousResult else {
        Issue.record("Expected lunch to block continuation")
        return
    }
}

@MainActor
@Test("Default template previews use the same task-dependent break rule")
func templatePreviewBreaksRequireTasks() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 8, minute: 55))
    let template = try #require(store.focus.saveFocusTemplate(name: "Sparse", slots: [
        FocusTemplateSlot(blockIndex: 0, kind: .task, taskKey: UUID(), taskTitle: "First task", taskIcon: .focus)
    ]).synchronousResult)
    store.focus.setDefaultFocusTemplate(template).synchronousResult
    let shift = try #require(store.session.snapshot(at: at))
    let items = store.focus.focusPlanAssignments(for: shift)
    #expect(items.filter { $0.assignment.kind == .task }.count == 1)
    #expect(items.filter { $0.assignment.kind == .breakTime }.count == 1)
}

@MainActor
@Test("Template estimates retain identity and order independently of grid indices")
func usualDayTaskEstimateCanBeEdited() throws {
    let key = UUID()
    var tasks = [FocusTemplateTask(taskKey: key, legacyIndex: 0, title: "Writing", icon: .focus, pomodoros: 3)]
    #expect(FocusTemplate.slots(from: tasks).count == 3)
    tasks[0].pomodoros = 2
    tasks[0].title = "Edited"
    let saved = FocusTemplate.slots(from: tasks)
    #expect(saved.count == 2)
    #expect(saved.allSatisfy { $0.taskKey == key && $0.taskTitle == "Edited" })
    #expect(FocusTemplate.tasks(from: saved).first?.pomodoros == 2)
}

@MainActor
@Test("Saving a usual-day favorite does not add unfinished work to today")
func usualDayFavoriteStaysInLibraryUntilPlaced() throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 9, minute: 0))
    store.focus.saveFocusFavorite(title: "Reusable writing", pomodoros: 3, icon: .focus).synchronousResult
    let favorite = try #require(store.focus.favoriteFocusTasks().first)
    #expect(favorite.estimatedPomodoros == 3)
    #expect(favorite.plannedForDate == nil)
    #expect(!store.focus.focusTasksForToday(at: at).contains { $0.id == favorite.id })
    #expect(!store.focus.focusTasksForCanvas(at: at).contains { $0.id == favorite.id })
    guard case .placed(let id, _) = store.focus.placeFavoriteInNextEmptyBlock(favorite, at: at).synchronousResult else {
        Issue.record("Expected favorite placement"); return
    }
    let copy = try #require(store.records.state.focusTasks.first { $0.id == id })
    #expect(copy.id != favorite.id)
    #expect(copy.estimatedPomodoros == 3)
    #expect(store.focus.savedFocusFavorite(title: copy.title, icon: copy.icon)?.id == favorite.id)
    let block = try #require(store.focus.focusDayCanvas(at: at).nextEmptyBlock)
    guard case .placed(let selectedID, _) = store.focus.createFocusTask(
        title: favorite.title, icon: favorite.icon, pomodoros: favorite.estimatedPomodoros,
        inBlockStartingAt: block.startAtMs, at: at
    ).synchronousResult else { Issue.record("Expected selected-block placement"); return }
    #expect(store.records.state.focusTasks.first { $0.id == selectedID }?.estimatedPomodoros == 3)

}

@MainActor
@Test("Saving a favorite again updates its estimate without duplicating the library")
func usualDayFavoriteUpdatesAndCanBeRemoved() throws {
    let store = try canvasStore()
    store.focus.saveFocusFavorite(title: "Reusable writing", pomodoros: 2, icon: .focus).synchronousResult
    let original = try #require(store.focus.favoriteFocusTasks().first)
    store.focus.saveFocusFavorite(title: "Reusable writing", pomodoros: 4, icon: .focus).synchronousResult
    #expect(store.focus.favoriteFocusTasks().count == 1)
    #expect(store.focus.favoriteFocusTasks().first?.id == original.id)
    #expect(store.focus.favoriteFocusTasks().first?.estimatedPomodoros == 4)
    store.focus.toggleFocusFavorite(try #require(store.focus.favoriteFocusTasks().first)).synchronousResult
    #expect(store.focus.favoriteFocusTasks().isEmpty)
    #expect(!store.focus.focusTasksForToday().contains { $0.id == original.id })
}

@MainActor
@Test("Quick add schedules the requested count from the current or next work block", arguments: [false, true])
func quickAddSchedulesCurrentOrNextBlock(duringBreak: Bool) throws {
    let store = try canvasStore()
    let morning = try #require(day(store, hour: 9, minute: 5))
    let initial = store.focus.focusDayCanvas(at: morning)
    let breakBlock = try #require(initial.blocks.first { $0.kind == .breakTime })
    let at = duringBreak ? Date(timeIntervalSince1970: Double(breakBlock.startAtMs) / 1_000 + 1) : morning
    let canvas = store.focus.focusDayCanvas(at: at)
    let target = try #require(canvas.nextEmptyBlock)
    let occupied = try #require(canvas.blocks.first { $0.kind == .task && $0.startAtMs > target.startAtMs })
    _ = store.focus.createFocusTask(title: "Keep this task", inBlockStartingAt: occupied.startAtMs, at: at).synchronousResult

    let result = store.focus.createFocusTaskInNextEmptyBlock(
        title: "Three pomodoros", pomodoros: 3, scheduleAllPomodoros: true, at: at
    ).synchronousResult
    let updated = store.focus.focusDayCanvas(at: at)
    let id = placedID(result)
    #expect(result == .placed(taskID: id, blockStartAtMs: target.startAtMs))
    #expect(updated.blocks.filter { $0.taskID == id }.count == 3)
    #expect(updated.blocks.first { $0.startAtMs == occupied.startAtMs }?.taskTitle == "Keep this task")
    #expect(updated.blocks.filter { $0.kind == .breakTime }.allSatisfy { $0.taskID == nil })
    #expect(store.records.state.focusTasks.first { $0.id == id }?.estimatedPomodoros == 3)
    #expect(store.focus.activeFocusSession() == nil)
    if duringBreak {
        #expect(target.startAtMs >= breakBlock.endAtMs)
    } else {
        #expect(target.state == .current)
    }
}

@MainActor
@Test("Creation finish matches the saved plan across occupied blocks and lunch", arguments: [1, 3, 12])
func creationFinishMatchesPlacement(count: Int) throws {
    let store = try canvasStore()
    let at = try #require(day(store, hour: 11, minute: 5))
    let before = store.focus.focusDayCanvas(at: at)
    let target = try #require(before.nextEmptyBlock)
    let future = before.blocks.filter { $0.kind == .task && $0.startAtMs > target.startAtMs }
    let busy = try #require(future.first)
    let other = makeTask(store, title: "Keep this task", at: at)
    _ = store.focus.assign(other, toBlockStartingAt: busy.startAtMs, at: at).synchronousResult
    let preview = store.focus.focusCreationFinish(pomodoros: count, startingAt: target.startAtMs, at: at)
    let result = store.focus.createFocusTask(title: "Finish preview", pomodoros: count,
                                     inBlockStartingAt: target.startAtMs, scheduleAllPomodoros: true, at: at).synchronousResult
    let id = placedID(result)
    let after = store.focus.focusDayCanvas(at: at)
    let assigned = after.blocks.filter { $0.taskID == id }
    #expect(assigned.first?.startAtMs == target.startAtMs)
    #expect(after.blocks.first { $0.startAtMs == busy.startAtMs }?.taskID == other.id)
    if assigned.count == count {
        #expect(preview == assigned.last.map { Date(timeIntervalSince1970: Double($0.endAtMs) / 1_000) })
    } else {
        #expect(preview == nil)
    }
    #expect(store.records.state.focusTasks.first { $0.id == id }?.estimatedPomodoros == count)
}

@MainActor
@Test("Start-now finish includes recovery and refuses an incomplete final round")
func immediateCreationFinishUsesActualBoundaries() throws {
    let store = try canvasStore()
    store.session.countdownStarted = true
    let at = try #require(day(store, hour: 10, minute: 5))
    #expect(store.focus.hasFocusRoom(at: at))
    let firstEnd = try #require(store.focus.focusCreationFinish(pomodoros: 1, startingAt: nil, startNow: true, at: at))
    #expect(firstEnd == at.addingTimeInterval(TimeInterval(store.focus.focusTimerSettings.normalized.focusMinutes * 60)))
    let twoEnd = try #require(store.focus.focusCreationFinish(pomodoros: 2, startingAt: nil, startNow: true, at: at))
    #expect(twoEnd > firstEnd.addingTimeInterval(TimeInterval(store.focus.focusTimerSettings.normalized.focusMinutes * 60)))
    let late = try #require(day(store, hour: 17, minute: 59))
    #expect(store.focus.focusCreationFinish(pomodoros: 12, startingAt: nil, startNow: true, at: late) == nil)
}

@MainActor
@Test("Alternating Saturdays agree between Records and Focus", arguments: [5, 12])
func alternatingSaturdayRecordsAndFocus(dayOfMonth: Int) throws {
    let store = try canvasStore()
    store.preferences.onboardingComplete = true
    store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
    store.preferences.applyPreferences { $0.scheduleMode = .alternating }
    store.preferences.applyPreferences { $0.alternatingWeekType = .single }
    store.preferences.applyPreferences { $0.alternatingWeekendWorkday = 6 }
    let monday = try #require(day(store, hour: 0, minute: 0))
    store.preferences.applyPreferences { $0.alternatingReferenceWeekStartMs = monday.timeIntervalSince1970 * 1_000 }
    let date = try #require(store.preferences.recordsCalendar.date(from: DateComponents(
        year: 2026, month: 9, day: dayOfMonth, hour: 10)))
    let isWorkday = dayOfMonth == 5
    store.shifts.reconcileRecordSchedule(at: date)
    let resolution = try #require(store.queries.resolvedDays(from: date, through: date, now: date).first)
    #expect(resolution.isScheduledWorkday == isWorkday)
    #expect(store.focus.hasFocusRoom(at: date) == isWorkday)
    let canvas = store.focus.focusDayCanvas(at: date)
    #expect(!canvas.blocks.isEmpty)
    #expect(canvas.isNextShift == !isWorkday)
    #expect((canvas.currentBlock != nil) == isWorkday)
    if !isWorkday {
        #expect(store.focus.plannedFocusBreakEnd(kind: .shortBreak, at: date) == nil)
    }
}

@MainActor
@Test("Rotating night shifts keep the start-day plan after midnight and split Records by civil day")
func rotatingNightShiftRecordsAndFocus() async throws {
    let store = try canvasStore()
    store.preferences.onboardingComplete = true
    store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
    store.preferences.applyPreferences { $0.scheduleMode = .rotation }
    store.preferences.applyPreferences { $0.rotationWorkDays = 2 }
    store.preferences.applyPreferences { $0.rotationRestDays = 2 }
    store.preferences.applyPreferences { $0.lunchEnabled = false }
    store.preferences.applyPreferences { $0.startMinutes = 22 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 6 * 60 }
    let monday = try #require(day(store, hour: 0, minute: 0))
    store.preferences.applyPreferences { $0.rotationAnchorMs = monday.timeIntervalSince1970 * 1_000 }
    let beforeMidnight = monday.addingTimeInterval(23 * 3_600)
    let afterMidnight = monday.addingTimeInterval(26 * 3_600)
    store.shifts.reconcileRecordSchedule(at: beforeMidnight)
    let canvas = store.focus.focusDayCanvas(at: beforeMidnight)
    #expect(canvas.dayKey == "2026-08-31")
    #expect(store.focus.focusDayCanvas(at: afterMidnight).dayKey == canvas.dayKey)
    #expect(store.focus.focusDayCanvas(at: afterMidnight).blocks.map(\.startAtMs) == canvas.blocks.map(\.startAtMs))
    #expect(store.focus.hasFocusRoom(at: afterMidnight))
    let task = makeTask(store, title: "Night shift", pomodoros: 3, at: beforeMidnight)
    #expect(store.focus.focusTasksForCanvas(at: afterMidnight).contains { $0.id == task.id })
    #expect(store.focus.focusTasksForToday(at: afterMidnight).contains { $0.id == task.id })
    let completed = FocusSession(
        id: UUID(), taskID: task.id,
        shiftAnchorDate: store.preferences.recordsCalendar.startOfDay(for: afterMidnight),
        startedAt: afterMidnight.addingTimeInterval(-30 * 60),
        plannedEndAt: afterMidnight.addingTimeInterval(-5 * 60),
        endedAt: afterMidnight.addingTimeInterval(-5 * 60), endReason: .completed,
        editedAt: afterMidnight, editCount: 0, editTieBreaker: UUID(), kind: .focus
    )
    store.records.upsertFocusSession(completed, at: afterMidnight)
    #expect(store.focus.focusDayCanvas(at: afterMidnight).tasks.first { $0.id == task.id }?.completedBlocks == 1)
    var finishedTask = task
    finishedTask.completedAt = afterMidnight
    store.records.upsertFocusTask(finishedTask, at: afterMidnight)
    #expect(store.focus.focusTasksForCanvas(at: afterMidnight).contains { $0.id == task.id })
    let record = try #require(await store.queries.recordsDayCanvas(dayKey: "2026-08-31", now: afterMidnight))
    #expect(record.allocation.workMs == 2 * 3_600_000)
    let rest = monday.addingTimeInterval(2 * 86_400 + 23 * 3_600)
    #expect(!store.focus.hasFocusRoom(at: rest))
    #expect(store.focus.focusDayCanvas(at: rest).isNextShift)
}

@MainActor
@Test("No schedule makes no phantom plan or records; manually starting enables focus")
func unscheduledRecordsAndFocus() async throws {
    let store = try canvasStore()
    store.preferences.onboardingComplete = true
    // A newly started manual session intentionally adopts the device zone.
    store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = TimeZone.current.identifier }
    store.preferences.applyPreferences { $0.scheduleMode = .off }
    store.preferences.applyPreferences { $0.lunchEnabled = false }
    let date = try #require(day(store, hour: 10, minute: 0))
    #expect(store.focus.focusDayCanvas(at: date).blocks.isEmpty)
    #expect(store.focus.refreshScheduledFocus(at: date).synchronousResult.isEmpty)
    #expect(!store.focus.hasFocusRoom(at: date))
    let record = try #require(await store.queries.recordsDayCanvas(dayKey: "2026-08-31", now: date))
    #expect(record.allocation.workMs == 0)
    store.shifts.startCountdown(at: date)
    #expect(!store.focus.focusDayCanvas(at: date).blocks.isEmpty)
    #expect(store.focus.hasFocusRoom(at: date))
}
