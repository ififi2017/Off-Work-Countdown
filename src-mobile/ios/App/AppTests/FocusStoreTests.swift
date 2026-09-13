import Foundation
import Testing
@testable import App

@MainActor
@Test("A one-block task completes after a natural 25-minute end")
func onePomodoroTaskCompletesOnNaturalEnd() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 1, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)

    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(25 * 60)).synchronousResult)
    #expect(store.focus.completedFocusBlocks(for: reload(task, on: store)) == 1)
    #expect(reload(task, on: store).completedAt != nil)
}

@MainActor
@Test("The first block of a two-pomodoro task stays open at 1 / 2")
func twoPomodoroTaskStaysOpenAfterFirstBlock() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)

    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(25 * 60)).synchronousResult)
    let afterFirst = reload(task, on: store)
    #expect(store.focus.completedFocusBlocks(for: afterFirst) == 1)
    #expect(afterFirst.completedAt == nil)
}

@MainActor
@Test("A two-pomodoro task completes on the second natural end")
func twoPomodoroTaskCompletesOnSecondBlock() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(25 * 60)).synchronousResult)
    // The first block rolls into its break; the user cuts it short and starts
    // the second block by hand.
    store.focus.stopFocus(reason: .stoppedByUser, at: start.addingTimeInterval(26 * 60)).synchronousResult

    let secondStart = start.addingTimeInterval(26 * 60)
    insertOpenSession(on: store, task: task, startedAt: secondStart, plannedMinutes: 25)
    #expect(store.focus.finishElapsedFocusSession(at: secondStart.addingTimeInterval(25 * 60)).synchronousResult)

    let afterSecond = reload(task, on: store)
    #expect(store.focus.completedFocusBlocks(for: afterSecond) == 2)
    #expect(afterSecond.completedAt != nil)
}

@MainActor
@Test("A twelve-pomodoro task does not complete on the first block")
func twelvePomodoroTaskStaysOpenAfterFirstBlock() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 12, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)

    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(25 * 60)).synchronousResult)
    let afterFirst = reload(task, on: store)
    #expect(store.focus.completedFocusBlocks(for: afterFirst) == 1)
    #expect(afterFirst.completedAt == nil)
}

@MainActor
@Test("A natural end after the app was backgrounded still counts one block")
func backgroundNaturalEndCountsOneBlock() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)

    // Reconcile is what launch and foreground call. The view is not ticking.
    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(40 * 60)).synchronousResult)
    let after = reload(task, on: store)
    #expect(store.focus.completedFocusBlocks(for: after) == 1)
    #expect(after.completedAt == nil)
}

@MainActor
@Test("A boundary cut and a user stop do not count")
func incompleteEndsDoNotCountTowardTheTask() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 2, at: start)

    insertOpenSession(
        on: store,
        task: task,
        startedAt: start,
        plannedMinutes: 10,
        plannedEndReason: .stoppedAtBoundary
    )
    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(10 * 60)).synchronousResult)
    #expect(store.focus.completedFocusBlocks(for: reload(task, on: store)) == 0)
    #expect(reload(task, on: store).completedAt == nil)

    insertOpenSession(on: store, task: task, startedAt: start.addingTimeInterval(11 * 60), plannedMinutes: 25)
    store.focus.stopFocus(reason: .stoppedByUser).synchronousResult
    #expect(store.focus.completedFocusBlocks(for: reload(task, on: store)) == 0)

}

@MainActor
@Test("Start is refused when the shift has no room, without completing anything")
func startIsRefusedWhenTheShiftHasNoRoom() throws {
    let store = try focusStore()
    store.preferences.applyPreferences { $0.scheduleMode = .off }
    let task = insertTask(on: store, pomodoros: 1, at: .now)

    #expect(store.focus.focusStartAvailability(task) == .noRoom)
    #expect(store.focus.startFocus(task: task).synchronousResult == false)
    #expect(store.focus.activeFocusSession() == nil)
    #expect(store.focus.focusRejectedNoRoom)
}

@MainActor
@Test("A task scheduled for the next shift remains visible on the Focus page")
func nextShiftTaskRemainsVisible() throws {
    let store = try focusStore()
    let today = store.preferences.recordsCalendar.startOfDay(for: .now)
    let tomorrow = try #require(store.preferences.recordsCalendar.date(byAdding: .day, value: 1, to: today))
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

    #expect(store.focus.focusTasksForToday().isEmpty)
    #expect(store.focus.focusTasksForFocusPage().map(\.id) == [task.id])
}

@MainActor
@Test("Reading the Focus page never carries tasks or mutates the archive")
func focusPageReadIsPure() throws {
    let store = try focusStore()
    let today = store.preferences.recordsCalendar.startOfDay(for: .now)
    let yesterday = try #require(store.preferences.recordsCalendar.date(byAdding: .day, value: -1, to: today))
    let task = FocusTask(
        id: UUID(), createdAt: yesterday, plannedForDate: yesterday, scheduledStartAt: nil,
        title: "Carry", estimatedPomodoros: 1, completedAt: nil, sortIndex: 0,
        editedAt: yesterday, editCount: 0, editTieBreaker: UUID()
    )
    store.records.upsertFocusTask(task)
    let revision = store.records.revision
    _ = store.focus.focusTasksForFocusPage(at: today)
    _ = store.focus.focusTasksForFocusPage(at: today)
    #expect(store.records.revision == revision)
    #expect(store.records.state.focusTasks.first?.plannedForDate == yesterday)
}

@MainActor
@Test("Import immediately carries yesterday's unfinished focus task")
func importedPastTaskCarriesAtExternalStateBoundary() async throws {
    let store = try focusStore()
    let today = store.preferences.recordsCalendar.startOfDay(for: .now)
    let yesterday = try #require(store.preferences.recordsCalendar.date(byAdding: .day, value: -1, to: today))
    let source = RecordCoordinator.inMemory()
    let task = FocusTask(
        id: UUID(), createdAt: yesterday, plannedForDate: yesterday,
        scheduledStartAt: yesterday.addingTimeInterval(9 * 60 * 60),
        title: "Imported carry", estimatedPomodoros: 1, completedAt: nil,
        sortIndex: 0, editedAt: yesterday, editCount: 0,
        editTieBreaker: UUID()
    )
    source.upsertFocusTask(task, at: yesterday)
    let data = try await source.exportJSON(exportedAt: .now, timeZone: store.preferences.recordsTimeZone)
    let previousRuntimeRevision = store.focus.focusRuntimeRevision

    _ = try await store.records.import(data)

    let carried = try #require(store.records.state.focusTasks.first { $0.id == task.id })
    #expect(carried.plannedForDate == today)
    #expect(carried.scheduledStartAt == nil)
    #expect(store.focus.focusRuntimeRevision == previousRuntimeRevision + 1)
    #expect(store.focus.focusTasksForFocusPage().contains { $0.id == task.id })
}

@MainActor
@Test("Future scheduled focus task cannot start early")
func futureScheduledTaskIsNotYetAvailable() throws {
    let store = try focusStore()
    let now = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 1, at: now)
    var future = task
    future.scheduledStartAt = now.addingTimeInterval(60)
    store.records.upsertFocusTask(future)
    guard case let .notYetAvailable(date) = store.focus.focusStartAvailability(future, at: now) else {
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
    let plannedDay = store.preferences.recordsCalendar.startOfDay(for: now)
    let exactStart = now.addingTimeInterval(8 * 60 * 60)
    var task = insertTask(on: store, pomodoros: 1, at: now)
    task.plannedForDate = plannedDay
    task.scheduledStartAt = exactStart
    store.records.upsertFocusTask(task)

    guard case let .notYetAvailable(date) = store.focus.focusStartAvailability(task, at: now) else {
        Issue.record("Expected the exact future slot to remain locked after its planned day began")
        return
    }
    #expect(date == exactStart)
    #expect(!store.focus.startFocus(task: task).synchronousResult)
}

@MainActor
@Test("A future planned task without a legacy slot cannot start early")
func futurePlannedTaskWithoutSlotIsNotYetAvailable() throws {
    let store = try focusStore()
    let today = store.preferences.recordsCalendar.startOfDay(for: .now)
    let tomorrow = try #require(store.preferences.recordsCalendar.date(byAdding: .day, value: 1, to: today))
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

    guard case let .notYetAvailable(date) = store.focus.focusStartAvailability(task) else {
        Issue.record("Expected planned future task to remain locked")
        return
    }
    #expect(store.preferences.recordsCalendar.isDate(date, inSameDayAs: tomorrow))
    #expect(!store.focus.startFocus(task: task).synchronousResult)
    #expect(store.focus.activeFocusSession() == nil)
}

@MainActor
@Test("Expired cross-midnight session is resolved from its persisted outcome")
func crossMidnightRecoveryDoesNotBecomeAbandoned() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 1, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25,
                      shiftAnchor: store.preferences.recordsCalendar.date(byAdding: .day, value: -1, to: start))
    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(30 * 60)).synchronousResult)
    #expect(store.focus.completedFocusBlocks(for: reload(task, on: store)) == 1)
}

@MainActor
@Test("Multiple open sessions converge deterministically and losers do not count")
func multipleOpenSessionsConverge() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    insertOpenSession(on: store, task: task, startedAt: start.addingTimeInterval(1), plannedMinutes: 25)
    store.focus.reconcileOpenFocusSessions(at: start.addingTimeInterval(2)).synchronousResult
    #expect(store.records.state.focusSessions.filter { $0.endedAt == nil }.count == 1)
    #expect(store.records.state.focusSessions.contains { $0.endReason == .supersededBySync })
    #expect(store.focus.completedFocusBlocks(for: task) == 0)
}

@MainActor
@Test("Natural focus phases roll into a short break until the fourth round")
func focusRoundSelectsConfiguredBreak() throws {
    let store = try focusStore()
    // Keep all four focus-and-break pairs comfortably inside one shift. This
    // test owns cadence; the boundary-specific case below owns the no-room
    // behaviour at lunch and clock-off.
    let start = try #require(store.preferences.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 24, hour: 12, minute: 30)
    ))
    let task = insertTask(on: store, pomodoros: 6, at: start)
    for round in 1...4 {
        let phaseStart = start.addingTimeInterval(Double(round * 30 * 60))
        insertOpenSession(on: store, task: task, startedAt: phaseStart, plannedMinutes: 25)
        #expect(store.focus.finishElapsedFocusSession(at: phaseStart.addingTimeInterval(25 * 60)).synchronousResult)
        let recovery = try #require(store.focus.activeFocusSession())
        #expect(recovery.kind == (round == 4 ? .longBreak : .shortBreak))
        #expect(store.focus.focusLastNextAction == .none)
        store.focus.stopFocus(reason: .stoppedByUser, at: phaseStart.addingTimeInterval(26 * 60)).synchronousResult
    }
}

@MainActor
@Test("A completed 25-minute focus rolls straight into its five-minute short break")
func focusThenShortBreakUsesConfiguredDuration() throws {
    let store = try focusStore()
    let now = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 2, at: now)
    insertOpenSession(on: store, task: task, startedAt: now.addingTimeInterval(-25 * 60), plannedMinutes: 25)
    #expect(store.focus.finishElapsedFocusSession(at: now).synchronousResult)
    let rest = try #require(store.focus.activeFocusSession())
    #expect(rest.kind == .shortBreak)
    #expect(rest.startedAt == now)
    #expect(abs(rest.plannedEndAt.timeIntervalSince(now) - 5 * 60) < 1)
    // Nothing is being offered, because nothing is waiting to be accepted.
    #expect(store.focus.focusLastNextAction == .none)
    store.focus.skipFocusPhase().synchronousResult
}

@MainActor
@Test("A focus ending at a boundary does not leave an unusable break action")
func boundaryEndDoesNotOfferDeadBreakAction() throws {
    let store = try focusStore()
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
    store.preferences.applyPreferences { $0.lunchEnabled = true }
    store.preferences.applyPreferences { $0.lunchStartMinutes = 12 * 60 }
    store.preferences.applyPreferences { $0.lunchDurationMinutes = 60 }
    let calendar = store.preferences.recordsCalendar
    let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 11, minute: 59, second: 1)))
    let task = insertTask(on: store, pomodoros: 2, at: end)
    insertOpenSession(on: store, task: task, startedAt: end.addingTimeInterval(-25 * 60), plannedMinutes: 25)
    #expect(store.focus.finishElapsedFocusSession(at: end).synchronousResult)
    #expect(store.focus.focusLastNextAction == .none)
    #expect(!store.focus.startBreak(kind: .shortBreak, at: end).synchronousResult)
    #expect(!store.focus.skipSuggestedFocusBreak().synchronousResult)
}

@MainActor
@Test("Skipping a break offered after its own window advances without a session")
func skipSuggestedBreakAdvancesDirectlyToFocus() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    // Half an hour after the block ended: the recovery it earned is over, so
    // nothing is backfilled and the offer is all that remains.
    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(55 * 60)).synchronousResult)
    #expect(store.focus.activeFocusSession() == nil)
    #expect(store.focus.focusLastNextAction == .startShortBreak)

    #expect(store.focus.skipSuggestedFocusBreak().synchronousResult)
    #expect(store.focus.focusLastNextAction == .startNextFocus)
    #expect(store.focus.activeFocusSession() == nil)
}

@MainActor
@Test("Completed and skipped breaks do not increment the task and return to focus")
func breakCompletionAndSkipDoNotCountTask() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 5, kind: .shortBreak)
    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(5 * 60)).synchronousResult)
    #expect(store.focus.completedFocusBlocks(for: task) == 0)
    #expect(store.focus.focusLastNextAction == .startNextFocus)

    insertOpenSession(on: store, task: task, startedAt: start.addingTimeInterval(10 * 60), plannedMinutes: 5, kind: .shortBreak)
    store.focus.skipFocusPhase().synchronousResult
    #expect(store.focus.completedFocusBlocks(for: task) == 0)
    #expect(store.focus.focusLastNextAction == .startNextFocus)
}

@MainActor
@Test("Deleting a focus task hides it but preserves the synced record")
func deletingFocusTaskIsSoftAndKeepsHistoryIdentity() throws {
    let store = try focusStore()
    let task = insertTask(on: store, pomodoros: 1, at: .now)
    store.focus.toggleFocusFavorite(task).synchronousResult
    #expect(reload(task, on: store).isFavorite)

    #expect(store.focus.deleteFocusTask(reload(task, on: store)).synchronousResult)
    #expect(!store.focus.focusTasksForFocusPage().contains(where: { $0.id == task.id }))
    let stored = try #require(store.records.state.focusTasks.first(where: { $0.id == task.id }))
    #expect(stored.deletedAt != nil)
    #expect(stored.isFavorite)
}

@MainActor
@Test("A saved template recreates task and break assignments")
func focusTemplateRecreatesAssignments() throws {
    let store = try focusStore()
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
    store.preferences.applyPreferences { $0.lunchEnabled = false }
    let calendar = store.preferences.recordsCalendar
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)))
    let blocks = store.focus.focusWorkBlocks(at: date)
    #expect(blocks.count >= 2)
    let task = insertTask(on: store, pomodoros: 1, at: date)
    let initialPlanningRevision = store.focus.focusPlanningRevision
    store.focus.assignFocusBlock(blocks[0], to: task, at: date).synchronousResult
    store.focus.assignFocusBreak(blocks[1], at: date).synchronousResult
    #expect(store.focus.focusPlanningRevision > initialPlanningRevision)

    let template = try #require(store.focus.saveFocusTemplate(name: "Default", at: date).synchronousResult)
    store.focus.clearFocusBlock(blocks[0], at: date).synchronousResult
    store.focus.clearFocusBlock(blocks[1], at: date).synchronousResult
    #expect(store.focus.applyFocusTemplate(template, at: date).synchronousResult)
    #expect(store.focus.focusAssignment(for: blocks[0], at: date)?.kind == .task)
    #expect(store.focus.focusAssignment(for: blocks[1], at: date)?.kind == .breakTime)

    let original = store.focus.focusTimerSettings
    #expect(!store.focus.updateFocusTimerSettings(FocusTimerSettings(
        focusMinutes: 40,
        shortBreakMinutes: 8,
        longBreakMinutes: 20,
        longBreakEvery: 3
    )).synchronousResult)
    #expect(store.focus.focusTimerSettings == original)
}

@MainActor
@Test("Reapplying an unchanged template is a true no-op")
func reapplyingUnchangedFocusTemplateDoesNotRewriteState() throws {
    let store = try focusStore()
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
    store.preferences.applyPreferences { $0.lunchEnabled = false }
    let date = try #require(store.preferences.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let blocks = store.focus.focusWorkBlocks(at: date)
    let firstTask = try #require(blocks.first(where: { $0.kind == .task }))
    let firstBreak = try #require(blocks.first(where: { $0.kind == .breakTime }))
    let source = insertTask(on: store, pomodoros: 1, at: date)
    store.focus.assignFocusBlock(firstTask, to: source, at: date).synchronousResult
    store.focus.assignFocusBreak(firstBreak, at: date).synchronousResult
    let template = try #require(store.focus.saveFocusTemplate(name: "Default", at: date).synchronousResult)

    #expect(store.focus.applyFocusTemplate(template, at: date).synchronousResult)
    let planRevision = store.focus.focusPlanningRevision
    let recordRevision = store.records.revision
    let assignment = try #require(store.focus.focusAssignment(for: firstTask, at: date))

    #expect(store.focus.applyFocusTemplate(template, at: date).synchronousResult)
    #expect(store.focus.focusPlanningRevision == planRevision)
    #expect(store.records.revision == recordRevision)
    #expect(store.focus.focusAssignment(for: firstTask, at: date) == assignment)
}

@MainActor
@Test("Clearing an orphan template task soft-deletes it and Apply revives the same row")
func clearingOrphanTemplateTaskIsReversible() throws {
    let store = try focusStore()
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
    store.preferences.applyPreferences { $0.lunchEnabled = false }
    let date = try #require(store.preferences.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let blocks = store.focus.focusWorkBlocks(at: date)
    let firstTask = try #require(blocks.first(where: { $0.kind == .task }))
    let firstBreak = try #require(blocks.first(where: { $0.kind == .breakTime }))
    let source = insertTask(on: store, pomodoros: 1, at: date)
    store.focus.assignFocusBlock(firstTask, to: source, at: date).synchronousResult
    store.focus.assignFocusBreak(firstBreak, at: date).synchronousResult
    let template = try #require(store.focus.saveFocusTemplate(name: "Default", at: date).synchronousResult)
    #expect(store.focus.applyFocusTemplate(template, at: date).synchronousResult)
    let materializedID = try #require(store.focus.focusAssignment(for: firstTask, at: date)?.taskID)

    store.focus.clearFocusBlock(firstTask, at: date).synchronousResult
    let tombstone = try #require(store.records.state.focusTasks.first(where: { $0.id == materializedID }))
    #expect(tombstone.deletedAt != nil)
    #expect(tombstone.templateID == template.id)
    #expect(tombstone.templateTaskKey != nil)

    #expect(store.focus.applyFocusTemplate(template, at: date).synchronousResult)
    #expect(store.focus.focusAssignment(for: firstTask, at: date)?.taskID == materializedID)
    let revived = try #require(store.records.state.focusTasks.first(where: { $0.id == materializedID }))
    #expect(revived.deletedAt == nil)
}

@MainActor
@Test("Clearing a template task with history or a favourite preserves it as a user task")
func clearingMeaningfulTemplateTaskDetachesItsProvenance() throws {
    let store = try focusStore()
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
    store.preferences.applyPreferences { $0.lunchEnabled = false }
    let date = try #require(store.preferences.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let blocks = store.focus.focusWorkBlocks(at: date)
    let firstTask = try #require(blocks.first(where: { $0.kind == .task }))
    let firstBreak = try #require(blocks.first(where: { $0.kind == .breakTime }))
    let source = insertTask(on: store, pomodoros: 1, at: date)
    store.focus.assignFocusBlock(firstTask, to: source, at: date).synchronousResult
    store.focus.assignFocusBreak(firstBreak, at: date).synchronousResult
    let template = try #require(store.focus.saveFocusTemplate(name: "Default", at: date).synchronousResult)
    #expect(store.focus.applyFocusTemplate(template, at: date).synchronousResult)
    let materialized = try #require(store.focus.focusAssignment(for: firstTask, at: date)?.taskID)
    let task = try #require(store.records.state.focusTasks.first(where: { $0.id == materialized }))
    store.focus.toggleFocusFavorite(task).synchronousResult
    store.records.upsertFocusSession(completedFocusSession(for: task, at: date))

    store.focus.clearFocusBlock(firstTask, at: date).synchronousResult
    let retained = try #require(store.records.state.focusTasks.first(where: { $0.id == materialized }))
    #expect(retained.deletedAt == nil)
    #expect(retained.isFavorite)
    #expect(retained.templateID == nil)
    #expect(retained.templateTaskKey == nil)

    #expect(store.focus.applyFocusTemplate(template, at: date).synchronousResult)
    #expect(store.focus.focusAssignment(for: firstTask, at: date)?.taskID != materialized)
}

@MainActor
@Test("A template task retained by another plan is detached rather than deleted")
func clearingTemplateTaskReferencedByAnotherPlanPreservesIt() throws {
    let store = try focusStore()
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
    store.preferences.applyPreferences { $0.lunchEnabled = false }
    let date = try #require(store.preferences.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let nextDate = try #require(store.preferences.recordsCalendar.date(byAdding: .day, value: 1, to: date))
    let blocks = store.focus.focusWorkBlocks(at: date)
    let nextBlocks = store.focus.focusWorkBlocks(at: nextDate)
    let firstTask = try #require(blocks.first(where: { $0.kind == .task }))
    let nextTask = try #require(nextBlocks.first(where: { $0.kind == .task }))
    let firstBreak = try #require(blocks.first(where: { $0.kind == .breakTime }))
    let source = insertTask(on: store, pomodoros: 1, at: date)
    store.focus.assignFocusBlock(firstTask, to: source, at: date).synchronousResult
    store.focus.assignFocusBreak(firstBreak, at: date).synchronousResult
    let template = try #require(store.focus.saveFocusTemplate(name: "Default", at: date).synchronousResult)
    #expect(store.focus.applyFocusTemplate(template, at: date).synchronousResult)
    let materializedID = try #require(store.focus.focusAssignment(for: firstTask, at: date)?.taskID)
    let materialized = try #require(store.records.state.focusTasks.first(where: { $0.id == materializedID }))

    store.focus.assignFocusBlock(nextTask, to: materialized, at: nextDate).synchronousResult
    store.focus.clearFocusBlock(firstTask, at: date).synchronousResult
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
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
    store.preferences.applyPreferences { $0.lunchEnabled = false }
    let date = try #require(store.preferences.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)
    ))
    let taskBlocks = store.focus.focusWorkBlocks(at: date).filter { $0.kind == .task }
    let firstTask = try #require(taskBlocks.first)
    let secondTask = try #require(taskBlocks.dropFirst().first)
    let firstBreak = try #require(store.focus.focusWorkBlocks(at: date).first(where: { $0.kind == .breakTime }))
    let manual = insertTask(on: store, pomodoros: 1, at: date)
    store.focus.assignFocusBlock(firstTask, to: manual, at: date).synchronousResult
    store.focus.assignFocusBreak(firstBreak, at: date).synchronousResult
    let template = try #require(store.focus.saveFocusTemplate(name: "Default", at: date).synchronousResult)
    #expect(store.focus.applyFocusTemplate(template, at: date).synchronousResult)
    let templateID = try #require(store.focus.focusAssignment(for: firstTask, at: date)?.taskID)
    let templateTask = try #require(store.records.state.focusTasks.first(where: { $0.id == templateID }))

    for offset in 0..<3 {
        store.records.upsertFocusSession(
            completedFocusSession(for: templateTask, at: date.addingTimeInterval(Double(offset * 60)))
        )
    }
    // Reassigning the same slot runs the estimate reconciliation without
    // changing the plan's semantic content.
    store.focus.assignFocusBlock(firstTask, to: templateTask, at: date).synchronousResult
    #expect(reload(templateTask, on: store).estimatedPomodoros == 3)

    store.focus.assignFocusBlock(firstTask, to: manual, at: date).synchronousResult
    store.focus.assignFocusBlock(secondTask, to: manual, at: date).synchronousResult
    #expect(reload(manual, on: store).estimatedPomodoros == 1)
}

@MainActor
@Test("Session history restores global break cadence and skipped break next focus")
func sessionHistoryRestoresNextAction() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 8, at: start)

    for round in 0..<4 {
        let phaseStart = start.addingTimeInterval(Double(round * 30 * 60))
        insertOpenSession(on: store, task: task, startedAt: phaseStart, plannedMinutes: 25)
        // Closed after each break window had passed, so history holds four
        // focus blocks and no recovery — which is the state a cold launch has
        // to read the cadence back out of.
        #expect(store.focus.finishElapsedFocusSession(at: phaseStart.addingTimeInterval(31 * 60)).synchronousResult)
    }
    // This models a cold launch after the durable history was restored.
    store.focus.reconcileOpenFocusSessions(at: start.addingTimeInterval(4 * 30 * 60)).synchronousResult
    #expect(store.focus.focusLastNextAction == .startLongBreak)

    insertOpenSession(
        on: store,
        task: task,
        startedAt: start.addingTimeInterval(4 * 30 * 60),
        plannedMinutes: 15,
        kind: .longBreak
    )
    store.focus.skipFocusPhase().synchronousResult
    store.focus.reconcileOpenFocusSessions(at: start.addingTimeInterval(4 * 30 * 60 + 1)).synchronousResult
    #expect(store.focus.focusLastNextAction == .startNextFocus)
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
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 1, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    let sessionID = try #require(store.focus.activeFocusSession()?.id)

    store.focus.applyFocusNotificationResult(.permissionDenied, for: sessionID).synchronousResult
    #expect(store.focus.focusNotificationIssue == .permissionDenied)

    store.focus.applyFocusNotificationResult(.failed, for: sessionID).synchronousResult
    #expect(store.focus.focusNotificationIssue == .schedulingFailed)

    // A successful retry clears the card, while a stale result from another
    // phase cannot replace the current user's recovery state.
    store.focus.applyFocusNotificationResult(.scheduled, for: sessionID).synchronousResult
    #expect(store.focus.focusNotificationIssue == nil)
    store.focus.applyFocusNotificationResult(.permissionDenied, for: UUID()).synchronousResult
    #expect(store.focus.focusNotificationIssue == nil)
}

@MainActor
@Test("Focus delivery switches default on, persist independently, and suppress disabled notification errors")
func focusDeliveryPreferencesAreIndependent() throws {
    let suite = "FocusStoreTests.delivery.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AppRuntime(defaults: defaults, records: .inMemory())
    #expect(store.preferences.focusLiveActivityEnabled)
    #expect(store.focus.focusNotificationsEnabled)
    store.preferences.liveActivityEnabled = false
    #expect(store.preferences.focusLiveActivityEnabled)
    store.focus.focusNotificationsEnabled = false
    #expect(store.preferences.focusLiveActivityEnabled)
    store.preferences.focusLiveActivityEnabled = false
    let restored = AppRuntime(defaults: defaults, records: .inMemory())
    #expect(!restored.focus.focusNotificationsEnabled)
    #expect(!restored.preferences.focusLiveActivityEnabled)
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 1, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    let sessionID = try #require(store.focus.activeFocusSession()?.id)
    store.focus.applyFocusNotificationResult(.permissionDenied, for: sessionID).synchronousResult
    #expect(store.focus.focusNotificationIssue == nil)
    store.focus.focusNotificationsEnabled = true
    store.focus.applyFocusNotificationResult(.permissionDenied, for: sessionID).synchronousResult
    #expect(store.focus.focusNotificationIssue == .permissionDenied)
    store.focus.focusNotificationsEnabled = false
    #expect(store.focus.focusNotificationIssue == nil)
    #expect(store.focus.activeFocusSession()?.id == sessionID)
}

/// Monday 2026-08-24, mid-afternoon, inside the default 09:00–17:00 shift.
///
/// Built from the store's calendar rather than a fixed epoch. An absolute
/// instant is a different civil hour in every zone: the epoch this replaced
/// read 15:40 on the machine it was written on and 00:40 — the middle of the
/// night, outside any shift — when Xcode Cloud ran the suite in UTC-7.
@MainActor
private func shiftAfternoon(_ store: AppRuntime) throws -> Date {
    try #require(store.preferences.recordsCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 24, hour: 15, minute: 40)
    ))
}

@MainActor
private func focusStore() throws -> AppRuntime {
    let suite = "FocusStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let store = AppRuntime(defaults: defaults, records: .inMemory())
    store.plus.debugSetAuthorized(true)
    return store
}

@MainActor
private func insertTask(on store: AppRuntime, pomodoros: Int, at date: Date) -> FocusTask {
    let task = FocusTask(
        id: UUID(),
        createdAt: date,
        plannedForDate: store.preferences.recordsCalendar.startOfDay(for: date),
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
    on store: AppRuntime,
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
        shiftAnchorDate: shiftAnchor ?? store.preferences.recordsCalendar.startOfDay(for: startedAt),
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
private func reload(_ task: FocusTask, on store: AppRuntime) -> FocusTask {
    store.records.state.focusTasks.first { $0.id == task.id } ?? task
}

@MainActor
@Test("A new shift does not restore yesterday's completed-block recovery prompt")
func newShiftDiscardsPreviousRecoveryPrompt() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 8, at: start)
    insertOpenSession(on: store, task: task, startedAt: start, plannedMinutes: 25)
    #expect(store.focus.finishElapsedFocusSession(at: start.addingTimeInterval(31 * 60)).synchronousResult)
    store.focus.reconcileOpenFocusSessions(at: start.addingTimeInterval(32 * 60)).synchronousResult
    #expect(store.focus.focusLastNextAction == .startShortBreak)

    let nextMorning = start.addingTimeInterval(23 * 60 * 60)
    store.focus.reconcileOpenFocusSessions(at: nextMorning).synchronousResult
    #expect(store.focus.focusLastNextAction == .none)
    #expect(!store.focus.focusDayComplete(at: nextMorning))
}

@MainActor
@Test("Two devices finishing the same block start one shared break, not two")
func devicesShareAutomaticBreakIdentity() throws {
    let phone = try focusStore()
    let tablet = try focusStore()
    let now = try shiftAfternoon(phone)
    let task = insertTask(on: phone, pomodoros: 2, at: now)
    tablet.records.upsertFocusTask(task)
    let startedAt = now.addingTimeInterval(-25 * 60)
    let block = FocusSession(
        id: UUID(), taskID: task.id,
        shiftAnchorDate: phone.preferences.recordsCalendar.startOfDay(for: startedAt),
        startedAt: startedAt, plannedEndAt: now, endedAt: nil, endReason: nil,
        editedAt: startedAt, editCount: 0, editTieBreaker: UUID(), kind: .focus,
        plannedEndReason: .completed
    )
    phone.records.upsertFocusSession(block)
    tablet.records.upsertFocusSession(block)

    #expect(phone.focus.finishElapsedFocusSession(at: now.addingTimeInterval(10)).synchronousResult)
    #expect(tablet.focus.finishElapsedFocusSession(at: now.addingTimeInterval(90)).synchronousResult)
    let phoneBreak = try #require(phone.focus.activeFocusSession())
    let tabletBreak = try #require(tablet.focus.activeFocusSession())
    #expect(phoneBreak.kind == .shortBreak)
    #expect(phoneBreak.id == tabletBreak.id)
    #expect(phoneBreak.id == FocusSessionIdentity.recovery(after: block.id, kind: .shortBreak))
    #expect(phoneBreak.startedAt == tabletBreak.startedAt)
    #expect(phoneBreak.plannedEndAt == tabletBreak.plannedEndAt)
    #expect(FocusSessionIdentity.recovery(after: block.id, kind: .longBreak) != phoneBreak.id)
    phone.focus.skipFocusPhase().synchronousResult
    tablet.focus.skipFocusPhase().synchronousResult
}

@MainActor
@Test("Day history hides a superseded sync copy but keeps one with no surviving twin")
func dayHistoryHidesSyncCopies() throws {
    let store = try focusStore()
    let start = try shiftAfternoon(store)
    let task = insertTask(on: store, pomodoros: 2, at: start)
    func session(_ offset: TimeInterval, _ reason: FocusEndReason, taskID: UUID?) -> FocusSession {
        let startedAt = start.addingTimeInterval(offset)
        return FocusSession(
            id: UUID(), taskID: taskID, shiftAnchorDate: start,
            startedAt: startedAt, plannedEndAt: startedAt.addingTimeInterval(25 * 60),
            endedAt: startedAt.addingTimeInterval(6 * 60), endReason: reason,
            editedAt: startedAt, editCount: 0, editTieBreaker: UUID(), kind: .focus,
            plannedEndReason: .completed
        )
    }
    let kept = session(0, .completed, taskID: task.id)
    let copy = session(20, .supersededBySync, taskID: task.id)
    let lone = session(3 * 60 * 60, .supersededBySync, taskID: task.id)
    let otherTask = session(0, .supersededBySync, taskID: UUID())

    let visible = RecordsFocusHistoryCard.withoutSyncCopies([kept, copy, lone, otherTask]).map(\.id)
    #expect(visible == [kept.id, lone.id, otherTask.id])
}
