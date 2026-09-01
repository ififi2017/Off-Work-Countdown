import Foundation
import Testing
@testable import App

@MainActor
@Test("A one-block task completes after a natural 25-minute end")
func onePomodoroTaskCompletesOnNaturalEnd() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200) // 09:00
    let task = insertTask(on: store, pomodoros: 1, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)

    #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(25 * 60)))
    #expect(store.completedFocusBlocks(for: reload(task, on: store)) == 1)
    #expect(reload(task, on: store).completedAt != nil)
}

@MainActor
@Test("The first block of a two-pomodoro task stays open at 1 / 2")
func twoPomodoroTaskStaysOpenAfterFirstBlock() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)

    #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(25 * 60)))
    let afterFirst = reload(task, on: store)
    #expect(store.completedFocusBlocks(for: afterFirst) == 1)
    #expect(afterFirst.completedAt == nil)
}

@MainActor
@Test("A two-pomodoro task completes on the second natural end")
func twoPomodoroTaskCompletesOnSecondBlock() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(25 * 60)))

    let secondStart = start.addingTimeInterval(26 * 60)
    insertOpenSession(on: store, task: task, startedAt: secondStart, plannedMinutes: 25)
    #expect(store.finishElapsedFocusSession(at: secondStart.addingTimeInterval(25 * 60)))

    let afterSecond = reload(task, on: store)
    #expect(store.completedFocusBlocks(for: afterSecond) == 2)
    #expect(afterSecond.completedAt != nil)
}

@MainActor
@Test("A twelve-pomodoro task does not complete on the first block")
func twelvePomodoroTaskStaysOpenAfterFirstBlock() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 12, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)

    #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(25 * 60)))
    let afterFirst = reload(task, on: store)
    #expect(store.completedFocusBlocks(for: afterFirst) == 1)
    #expect(afterFirst.completedAt == nil)
}

@MainActor
@Test("A natural end after the app was backgrounded still counts one block")
func backgroundNaturalEndCountsOneBlock() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)

    // Reconcile is what launch and foreground call. The view is not ticking.
    #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(40 * 60)))
    let after = reload(task, on: store)
    #expect(store.completedFocusBlocks(for: after) == 1)
    #expect(after.completedAt == nil)
}

@MainActor
@Test("A boundary cut and a user stop do not count")
func incompleteEndsDoNotCountTowardTheTask() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 2, at: start)

    insertOpenSession(
        on: store,
        task: task,
        startedAt: start,
        plannedMinutes: 10,
        plannedEndReason: .stoppedAtBoundary
    )
    #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(10 * 60)))
    #expect(store.completedFocusBlocks(for: reload(task, on: store)) == 0)
    #expect(reload(task, on: store).completedAt == nil)

    insertOpenSession(on: store, task: task, startedAt: start.addingTimeInterval(11 * 60), plannedMinutes: 25)
    store.stopFocus(reason: .stoppedByUser)
    #expect(store.completedFocusBlocks(for: reload(task, on: store)) == 0)

}

@MainActor
@Test("Start is refused when the shift has no room, without completing anything")
func startIsRefusedWhenTheShiftHasNoRoom() throws {
    let store = try focusStore()
    store.scheduleMode = .off
    let task = insertTask(on: store, pomodoros: 1, at: .now)

    #expect(store.focusStartAvailability(task) == .noRoom)
    #expect(store.startFocus(task: task) == false)
    #expect(store.activeFocusSession() == nil)
    #expect(store.focusRejectedNoRoom)
}

@MainActor
@Test("A task scheduled for the next shift remains visible on the Focus page")
func nextShiftTaskRemainsVisible() throws {
    let store = try focusStore()
    let today = store.recordsCalendar.startOfDay(for: .now)
    let tomorrow = try #require(store.recordsCalendar.date(byAdding: .day, value: 1, to: today))
    let task = FocusTask(
        id: UUID(),
        createdAt: .now,
        plannedForDate: tomorrow,
        scheduledStartAt: tomorrow.addingTimeInterval(10 * 3_600),
        title: "Tomorrow",
        estimatedPomodoros: 1,
        completedAt: nil,
        sortIndex: 0,
        editedAt: .now,
        editCount: 0,
        editTieBreaker: UUID()
    )
    store.records.upsertFocusTask(task)

    #expect(store.focusTasksForToday().isEmpty)
    #expect(store.focusTasksForFocusPage().map(\.id) == [task.id])
}

@MainActor
@Test("Reading the Focus page never carries tasks or mutates the archive")
func focusPageReadIsPure() throws {
    let store = try focusStore()
    let today = store.recordsCalendar.startOfDay(for: .now)
    let yesterday = try #require(store.recordsCalendar.date(byAdding: .day, value: -1, to: today))
    let task = FocusTask(
        id: UUID(), createdAt: yesterday, plannedForDate: yesterday, scheduledStartAt: nil,
        title: "Carry", estimatedPomodoros: 1, completedAt: nil, sortIndex: 0,
        editedAt: yesterday, editCount: 0, editTieBreaker: UUID()
    )
    store.records.upsertFocusTask(task)
    let revision = store.records.revision
    _ = store.focusTasksForFocusPage(at: today)
    _ = store.focusTasksForFocusPage(at: today)
    #expect(store.records.revision == revision)
    #expect(store.records.state.focusTasks.first?.plannedForDate == yesterday)
}

@MainActor
@Test("Import immediately carries yesterday's unfinished focus task")
func importedPastTaskCarriesAtExternalStateBoundary() throws {
    let store = try focusStore()
    let today = store.recordsCalendar.startOfDay(for: .now)
    let yesterday = try #require(store.recordsCalendar.date(byAdding: .day, value: -1, to: today))
    let source = RecordCoordinator.inMemory()
    let task = FocusTask(
        id: UUID(), createdAt: yesterday, plannedForDate: yesterday,
        scheduledStartAt: yesterday.addingTimeInterval(9 * 60 * 60),
        title: "Imported carry", estimatedPomodoros: 1, completedAt: nil,
        sortIndex: 0, editedAt: yesterday, editCount: 0,
        editTieBreaker: UUID()
    )
    source.upsertFocusTask(task, at: yesterday)
    let data = try source.exportJSON(exportedAt: .now, timeZone: store.recordsTimeZone)
    let previousRuntimeRevision = store.focusRuntimeRevision

    _ = try store.records.import(data)

    let carried = try #require(store.records.state.focusTasks.first { $0.id == task.id })
    #expect(carried.plannedForDate == today)
    #expect(carried.scheduledStartAt == nil)
    #expect(store.focusRuntimeRevision == previousRuntimeRevision + 1)
    #expect(store.focusTasksForFocusPage().contains { $0.id == task.id })
}

@MainActor
@Test("Future scheduled focus task cannot start early")
func futureScheduledTaskIsNotYetAvailable() throws {
    let store = try focusStore()
    let now = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 1, at: now)
    var future = task
    future.scheduledStartAt = now.addingTimeInterval(60)
    store.records.upsertFocusTask(future)
    guard case let .notYetAvailable(date) = store.focusStartAvailability(future, at: now) else {
        Issue.record("Expected notYetAvailable")
        return
    }
    #expect(date == future.scheduledStartAt)
}

@MainActor
@Test("An exact future slot stays locked after its planned day begins")
func exactFutureSlotOutranksPlannedDayBoundary() throws {
    let store = try focusStore()
    let now = Date.now
    let plannedDay = store.recordsCalendar.startOfDay(for: now)
    let exactStart = now.addingTimeInterval(8 * 60 * 60)
    var task = insertTask(on: store, pomodoros: 1, at: now)
    task.plannedForDate = plannedDay
    task.scheduledStartAt = exactStart
    store.records.upsertFocusTask(task)

    guard case let .notYetAvailable(date) = store.focusStartAvailability(task, at: now) else {
        Issue.record("Expected the exact future slot to remain locked after its planned day began")
        return
    }
    #expect(date == exactStart)
    #expect(!store.startFocus(task: task))
}

@MainActor
@Test("A future planned task without a legacy slot cannot start early")
func futurePlannedTaskWithoutSlotIsNotYetAvailable() throws {
    let store = try focusStore()
    let today = store.recordsCalendar.startOfDay(for: .now)
    let tomorrow = try #require(store.recordsCalendar.date(byAdding: .day, value: 1, to: today))
    let task = FocusTask(
        id: UUID(),
        createdAt: .now,
        plannedForDate: tomorrow,
        scheduledStartAt: nil,
        title: "Migrated tomorrow",
        estimatedPomodoros: 1,
        completedAt: nil,
        sortIndex: 0,
        editedAt: .now,
        editCount: 0,
        editTieBreaker: UUID()
    )
    store.records.upsertFocusTask(task)

    guard case let .notYetAvailable(date) = store.focusStartAvailability(task) else {
        Issue.record("Expected planned future task to remain locked")
        return
    }
    #expect(store.recordsCalendar.isDate(date, inSameDayAs: tomorrow))
    #expect(!store.startFocus(task: task))
    #expect(store.activeFocusSession() == nil)
}

@MainActor
@Test("Expired cross-midnight session is resolved from its persisted outcome")
func crossMidnightRecoveryDoesNotBecomeAbandoned() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 1, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25,
                      shiftAnchor: store.recordsCalendar.date(byAdding: .day, value: -1, to: start))
    #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(30 * 60)))
    #expect(store.completedFocusBlocks(for: reload(task, on: store)) == 1)
}

@MainActor
@Test("Multiple open sessions converge deterministically and losers do not count")
func multipleOpenSessionsConverge() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    insertOpenSession(on: store, task: task, startedAt: start.addingTimeInterval(1), plannedMinutes: 25)
    store.reconcileOpenFocusSessions(at: start.addingTimeInterval(2))
    #expect(store.records.state.focusSessions.filter { $0.endedAt == nil }.count == 1)
    #expect(store.records.state.focusSessions.contains { $0.endReason == .supersededBySync })
    #expect(store.completedFocusBlocks(for: task) == 0)
}

@MainActor
@Test("Natural focus phases recommend a short break until the fourth round")
func focusRoundSelectsConfiguredBreak() throws {
    let store = try focusStore()
    // Keep all four focus-and-break pairs comfortably inside one shift. This
    // test owns cadence; the boundary-specific case below owns the no-room
    // behaviour at lunch and clock-off.
    let start = try #require(store.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 24, hour: 12, minute: 30)
    ))
    let task = insertTask(on: store, pomodoros: 6, at: start)
    for round in 1...4 {
        insertOpenSession(on: store, task: task, startedAt: start.addingTimeInterval(Double(round * 30 * 60)), plannedMinutes: 25)
        #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(Double(round * 30 * 60 + 25 * 60))))
        #expect(store.focusLastNextAction == (round == 4 ? .startLongBreak : .startShortBreak))
    }
}

@MainActor
@Test("A completed 25-minute focus can manually start a five-minute short break")
func focusThenManualShortBreakUsesConfiguredDuration() throws {
    let store = try focusStore()
    let now = Date(timeIntervalSince1970: 1_787_557_200) // 09:00 inside the configured shift
    let task = insertTask(on: store, pomodoros: 2, at: now)
    insertOpenSession(on: store, task: task, startedAt: now.addingTimeInterval(-25 * 60), plannedMinutes: 25)
    #expect(store.finishElapsedFocusSession(at: now))
    #expect(store.focusLastNextAction == .startShortBreak)
    #expect(store.startBreak(kind: .shortBreak, at: now))
    let rest = try #require(store.activeFocusSession())
    #expect(rest.kind == .shortBreak)
    #expect(abs(rest.plannedEndAt.timeIntervalSince(now) - 5 * 60) < 1)
    store.skipFocusPhase()
}

@MainActor
@Test("A focus ending at a boundary does not leave an unusable break action")
func boundaryEndDoesNotOfferDeadBreakAction() throws {
    let store = try focusStore()
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60
    store.lunchDurationMinutes = 60
    let calendar = store.recordsCalendar
    let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 11, minute: 59, second: 1)))
    let task = insertTask(on: store, pomodoros: 2, at: end)
    insertOpenSession(on: store, task: task, startedAt: end.addingTimeInterval(-25 * 60), plannedMinutes: 25)
    #expect(store.finishElapsedFocusSession(at: end))
    #expect(store.focusLastNextAction == .none)
    #expect(!store.startBreak(kind: .shortBreak, at: end))
    #expect(!store.skipSuggestedFocusBreak())
}

@MainActor
@Test("Skipping a suggested break advances without manufacturing a break session")
func skipSuggestedBreakAdvancesDirectlyToFocus() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(25 * 60)))
    #expect(store.focusLastNextAction == .startShortBreak)

    #expect(store.skipSuggestedFocusBreak())
    #expect(store.focusLastNextAction == .startNextFocus)
    #expect(store.activeFocusSession() == nil)
}

@MainActor
@Test("Completed and skipped breaks do not increment the task and return to focus")
func breakCompletionAndSkipDoNotCountTask() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 5, kind: .shortBreak)
    #expect(store.finishElapsedFocusSession(at: start.addingTimeInterval(5 * 60)))
    #expect(store.completedFocusBlocks(for: task) == 0)
    #expect(store.focusLastNextAction == .startNextFocus)

    insertOpenSession(on: store, task: task, startedAt: start.addingTimeInterval(10 * 60), plannedMinutes: 5, kind: .shortBreak)
    store.skipFocusPhase()
    #expect(store.completedFocusBlocks(for: task) == 0)
    #expect(store.focusLastNextAction == .startNextFocus)
}

@MainActor
@Test("Deleting a focus task hides it but preserves the synced record")
func deletingFocusTaskIsSoftAndKeepsHistoryIdentity() throws {
    let store = try focusStore()
    let task = insertTask(on: store, pomodoros: 1, at: .now)
    store.toggleFocusFavorite(task)
    #expect(reload(task, on: store).isFavorite)

    #expect(store.deleteFocusTask(reload(task, on: store)))
    #expect(!store.focusTasksForFocusPage().contains(where: { $0.id == task.id }))
    let stored = try #require(store.records.state.focusTasks.first(where: { $0.id == task.id }))
    #expect(stored.deletedAt != nil)
    #expect(stored.isFavorite)
}

@MainActor
@Test("A saved template recreates task and break assignments")
func focusTemplateRecreatesAssignments() throws {
    let store = try focusStore()
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = false
    let calendar = store.recordsCalendar
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)))
    let blocks = store.focusWorkBlocks(at: date)
    #expect(blocks.count >= 2)
    let task = insertTask(on: store, pomodoros: 1, at: date)
    let initialPlanningRevision = store.focusPlanningRevision
    store.assignFocusBlock(blocks[0], to: task, at: date)
    store.assignFocusBreak(blocks[1], at: date)
    #expect(store.focusPlanningRevision > initialPlanningRevision)

    let template = try #require(store.saveFocusTemplate(name: "Default", at: date))
    store.clearFocusBlock(blocks[0], at: date)
    store.clearFocusBlock(blocks[1], at: date)
    #expect(store.applyFocusTemplate(template, at: date))
    #expect(store.focusAssignment(for: blocks[0], at: date)?.kind == .task)
    #expect(store.focusAssignment(for: blocks[1], at: date)?.kind == .breakTime)

    let original = store.focusTimerSettings
    #expect(!store.updateFocusTimerSettings(FocusTimerSettings(
        focusMinutes: 40,
        shortBreakMinutes: 8,
        longBreakMinutes: 20,
        longBreakEvery: 3
    )))
    #expect(store.focusTimerSettings == original)
}

@MainActor
@Test("Reapplying an unchanged template is a true no-op")
func reapplyingUnchangedFocusTemplateDoesNotRewriteState() throws {
    let store = try focusStore()
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = false
    let date = try #require(store.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let blocks = store.focusWorkBlocks(at: date)
    let firstTask = try #require(blocks.first(where: { $0.kind == .task }))
    let firstBreak = try #require(blocks.first(where: { $0.kind == .breakTime }))
    let source = insertTask(on: store, pomodoros: 1, at: date)
    store.assignFocusBlock(firstTask, to: source, at: date)
    store.assignFocusBreak(firstBreak, at: date)
    let template = try #require(store.saveFocusTemplate(name: "Default", at: date))

    #expect(store.applyFocusTemplate(template, at: date))
    let planRevision = store.focusPlanningRevision
    let recordRevision = store.records.revision
    let assignment = try #require(store.focusAssignment(for: firstTask, at: date))

    #expect(store.applyFocusTemplate(template, at: date))
    #expect(store.focusPlanningRevision == planRevision)
    #expect(store.records.revision == recordRevision)
    #expect(store.focusAssignment(for: firstTask, at: date) == assignment)
}

@MainActor
@Test("Clearing an orphan template task soft-deletes it and Apply revives the same row")
func clearingOrphanTemplateTaskIsReversible() throws {
    let store = try focusStore()
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = false
    let date = try #require(store.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let blocks = store.focusWorkBlocks(at: date)
    let firstTask = try #require(blocks.first(where: { $0.kind == .task }))
    let firstBreak = try #require(blocks.first(where: { $0.kind == .breakTime }))
    let source = insertTask(on: store, pomodoros: 1, at: date)
    store.assignFocusBlock(firstTask, to: source, at: date)
    store.assignFocusBreak(firstBreak, at: date)
    let template = try #require(store.saveFocusTemplate(name: "Default", at: date))
    #expect(store.applyFocusTemplate(template, at: date))
    let materializedID = try #require(store.focusAssignment(for: firstTask, at: date)?.taskID)

    store.clearFocusBlock(firstTask, at: date)
    let tombstone = try #require(store.records.state.focusTasks.first(where: { $0.id == materializedID }))
    #expect(tombstone.deletedAt != nil)
    #expect(tombstone.templateID == template.id)
    #expect(tombstone.templateTaskKey != nil)

    #expect(store.applyFocusTemplate(template, at: date))
    #expect(store.focusAssignment(for: firstTask, at: date)?.taskID == materializedID)
    let revived = try #require(store.records.state.focusTasks.first(where: { $0.id == materializedID }))
    #expect(revived.deletedAt == nil)
}

@MainActor
@Test("Clearing a template task with history or a favourite preserves it as a user task")
func clearingMeaningfulTemplateTaskDetachesItsProvenance() throws {
    let store = try focusStore()
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = false
    let date = try #require(store.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let blocks = store.focusWorkBlocks(at: date)
    let firstTask = try #require(blocks.first(where: { $0.kind == .task }))
    let firstBreak = try #require(blocks.first(where: { $0.kind == .breakTime }))
    let source = insertTask(on: store, pomodoros: 1, at: date)
    store.assignFocusBlock(firstTask, to: source, at: date)
    store.assignFocusBreak(firstBreak, at: date)
    let template = try #require(store.saveFocusTemplate(name: "Default", at: date))
    #expect(store.applyFocusTemplate(template, at: date))
    let materialized = try #require(store.focusAssignment(for: firstTask, at: date)?.taskID)
    let task = try #require(store.records.state.focusTasks.first(where: { $0.id == materialized }))
    store.toggleFocusFavorite(task)
    store.records.upsertFocusSession(completedFocusSession(for: task, at: date))

    store.clearFocusBlock(firstTask, at: date)
    let retained = try #require(store.records.state.focusTasks.first(where: { $0.id == materialized }))
    #expect(retained.deletedAt == nil)
    #expect(retained.isFavorite)
    #expect(retained.templateID == nil)
    #expect(retained.templateTaskKey == nil)

    #expect(store.applyFocusTemplate(template, at: date))
    #expect(store.focusAssignment(for: firstTask, at: date)?.taskID != materialized)
}

@MainActor
@Test("A template task retained by another plan is detached rather than deleted")
func clearingTemplateTaskReferencedByAnotherPlanPreservesIt() throws {
    let store = try focusStore()
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = false
    let date = try #require(store.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let nextDate = try #require(store.recordsCalendar.date(byAdding: .day, value: 1, to: date))
    let blocks = store.focusWorkBlocks(at: date)
    let nextBlocks = store.focusWorkBlocks(at: nextDate)
    let firstTask = try #require(blocks.first(where: { $0.kind == .task }))
    let nextTask = try #require(nextBlocks.first(where: { $0.kind == .task }))
    let firstBreak = try #require(blocks.first(where: { $0.kind == .breakTime }))
    let source = insertTask(on: store, pomodoros: 1, at: date)
    store.assignFocusBlock(firstTask, to: source, at: date)
    store.assignFocusBreak(firstBreak, at: date)
    let template = try #require(store.saveFocusTemplate(name: "Default", at: date))
    #expect(store.applyFocusTemplate(template, at: date))
    let materializedID = try #require(store.focusAssignment(for: firstTask, at: date)?.taskID)
    let materialized = try #require(store.records.state.focusTasks.first(where: { $0.id == materializedID }))

    store.assignFocusBlock(nextTask, to: materialized, at: nextDate)
    store.clearFocusBlock(firstTask, at: date)
    let retained = try #require(store.records.state.focusTasks.first(where: { $0.id == materializedID }))
    #expect(retained.deletedAt == nil)
    #expect(retained.templateID == nil)
    #expect(retained.templateTaskKey == nil)
    #expect(retained.scheduledStartAt == nextTask.start)
}

@MainActor
@Test("Template estimates never shrink below completed rounds and manual estimates stay manual")
func templateAndManualTaskEstimatesRemainSemanticallyDistinct() throws {
    let store = try focusStore()
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = false
    let date = try #require(store.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let taskBlocks = store.focusWorkBlocks(at: date).filter { $0.kind == .task }
    let firstTask = try #require(taskBlocks.first)
    let secondTask = try #require(taskBlocks.dropFirst().first)
    let firstBreak = try #require(store.focusWorkBlocks(at: date).first(where: { $0.kind == .breakTime }))
    let manual = insertTask(on: store, pomodoros: 1, at: date)
    store.assignFocusBlock(firstTask, to: manual, at: date)
    store.assignFocusBreak(firstBreak, at: date)
    let template = try #require(store.saveFocusTemplate(name: "Default", at: date))
    #expect(store.applyFocusTemplate(template, at: date))
    let templateID = try #require(store.focusAssignment(for: firstTask, at: date)?.taskID)
    let templateTask = try #require(store.records.state.focusTasks.first(where: { $0.id == templateID }))

    for offset in 0..<3 {
        store.records.upsertFocusSession(
            completedFocusSession(for: templateTask, at: date.addingTimeInterval(Double(offset * 60)))
        )
    }
    // Reassigning the same slot runs the estimate reconciliation without
    // changing the plan's semantic content.
    store.assignFocusBlock(firstTask, to: templateTask, at: date)
    #expect(reload(templateTask, on: store).estimatedPomodoros == 3)

    store.assignFocusBlock(firstTask, to: manual, at: date)
    store.assignFocusBlock(secondTask, to: manual, at: date)
    #expect(reload(manual, on: store).estimatedPomodoros == 1)
}

@MainActor
@Test("Session history restores global break cadence and skipped break next focus")
func sessionHistoryRestoresNextAction() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 8, at: start)

    for round in 0..<4 {
        let phaseStart = start.addingTimeInterval(Double(round * 30 * 60))
        insertOpenSession(on: store, task: task, startedAt: phaseStart, plannedMinutes: 25)
        #expect(store.finishElapsedFocusSession(at: phaseStart.addingTimeInterval(25 * 60)))
    }
    // This models a cold launch after the durable history was restored.
    store.reconcileOpenFocusSessions(at: start.addingTimeInterval(4 * 30 * 60))
    #expect(store.focusLastNextAction == .startLongBreak)

    insertOpenSession(
        on: store,
        task: task,
        startedAt: start.addingTimeInterval(4 * 30 * 60),
        plannedMinutes: 15,
        kind: .longBreak
    )
    store.skipFocusPhase()
    store.reconcileOpenFocusSessions(at: start.addingTimeInterval(4 * 30 * 60 + 1))
    #expect(store.focusLastNextAction == .startNextFocus)
}

@MainActor
@Test("A stale asynchronous notification request cannot mutate a newer focus channel")
func staleFocusNotificationRequestIsRejected() {
    let sessionID = UUID()
    #expect(NotificationService.shouldKeepFocusNotification(
        requestGeneration: 4,
        currentGeneration: 4,
        requestID: sessionID,
        activeSessionID: sessionID
    ))
    #expect(!NotificationService.shouldKeepFocusNotification(
        requestGeneration: 4,
        currentGeneration: 5,
        requestID: sessionID,
        activeSessionID: nil
    ))
    #expect(!NotificationService.shouldKeepFocusNotification(
        requestGeneration: 4,
        currentGeneration: 4,
        requestID: sessionID,
        activeSessionID: UUID()
    ))
    #expect(!NotificationService.mayMutateFocusNotificationChannel(
        requestGeneration: 4,
        currentGeneration: 5,
        requestID: sessionID,
        activeSessionID: UUID()
    ))
}

@MainActor
@Test("Notification permission and scheduling failures reach the active timer state")
func focusNotificationFailuresAreVisibleAndRecoverable() throws {
    let store = try focusStore()
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let task = insertTask(on: store, pomodoros: 1, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    let sessionID = try #require(store.activeFocusSession()?.id)

    store.applyFocusNotificationResult(.permissionDenied, for: sessionID)
    #expect(store.focusNotificationIssue == .permissionDenied)

    store.applyFocusNotificationResult(.failed, for: sessionID)
    #expect(store.focusNotificationIssue == .schedulingFailed)

    // A successful retry clears the card, while a stale result from another
    // phase cannot replace the current user's recovery state.
    store.applyFocusNotificationResult(.scheduled, for: sessionID)
    #expect(store.focusNotificationIssue == nil)
    store.applyFocusNotificationResult(.permissionDenied, for: UUID())
    #expect(store.focusNotificationIssue == nil)
}

@MainActor
private func focusStore() throws -> OffWorkStore {
    let suite = "FocusStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let store = OffWorkStore(defaults: defaults, records: .inMemory())
    store.plus.debugSetAuthorized(true)
    return store
}

@MainActor
private func insertTask(on store: OffWorkStore, pomodoros: Int, at date: Date) -> FocusTask {
    let task = FocusTask(
        id: UUID(),
        createdAt: date,
        plannedForDate: store.recordsCalendar.startOfDay(for: date),
        scheduledStartAt: nil,
        title: "Deep work",
        estimatedPomodoros: pomodoros,
        completedAt: nil,
        sortIndex: 0,
        editedAt: date,
        editCount: 0,
        editTieBreaker: UUID()
    )
    store.records.upsertFocusTask(task)
    return task
}

@MainActor
private func insertOpenSession(
    on store: OffWorkStore,
    task: FocusTask,
    startedAt: Date,
    plannedMinutes: Int,
    shiftAnchor: Date? = nil,
    kind: FocusSessionKind = .focus,
    plannedEndReason: FocusEndReason? = nil
) {
    let session = FocusSession(
        id: UUID(),
        taskID: task.id,
        shiftAnchorDate: shiftAnchor ?? store.recordsCalendar.startOfDay(for: startedAt),
        startedAt: startedAt,
        plannedEndAt: startedAt.addingTimeInterval(Double(plannedMinutes * 60)),
        endedAt: nil,
        endReason: nil,
        editedAt: startedAt,
        editCount: 0,
        editTieBreaker: UUID(),
        kind: kind,
        plannedEndReason: plannedEndReason ?? FocusPlanner.endReason(
            startedAt: startedAt,
            plannedEndAt: startedAt.addingTimeInterval(Double(plannedMinutes * 60)),
            expectedDurationMinutes: plannedMinutes
        )
    )
    store.records.upsertFocusSession(session)
}

@MainActor
private func completedFocusSession(for task: FocusTask, at date: Date) -> FocusSession {
    FocusSession(
        id: UUID(),
        taskID: task.id,
        shiftAnchorDate: date,
        startedAt: date,
        plannedEndAt: date.addingTimeInterval(25 * 60),
        endedAt: date.addingTimeInterval(25 * 60),
        endReason: .completed,
        editedAt: date,
        editCount: 0,
        editTieBreaker: UUID(),
        kind: .focus,
        plannedEndReason: .completed
    )
}

@MainActor
private func reload(_ task: FocusTask, on store: OffWorkStore) -> FocusTask {
    store.records.state.focusTasks.first { $0.id == task.id } ?? task
}
