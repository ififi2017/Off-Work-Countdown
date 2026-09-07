import Foundation
import Testing
import UserNotifications
@testable import App

@MainActor
struct FocusAcceptanceReviewTests {
    private func fixture() throws -> (OffWorkStore, Date, FocusTask) {
        let defaults = try #require(UserDefaults(suiteName: "FocusAcceptance.\(UUID())"))
        let store = OffWorkStore(defaults: defaults, records: .inMemory())
        store.plus.debugSetAuthorized(true)
        store.countdownStarted = true
        store.languageOverride = "en"
        store.workdays = [1, 2, 3, 4, 5]
        store.startMinutes = 540
        store.endMinutes = 1020
        store.lunchEnabled = true
        let date = try #require(store.recordsCalendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9)))
        let task = FocusTask(id: UUID(), createdAt: date, plannedForDate: date, scheduledStartAt: nil,
            title: "Acceptance task", estimatedPomodoros: 2, completedAt: nil, sortIndex: 0,
            editedAt: date, editCount: 0, editTieBreaker: UUID())
        store.records.upsertFocusTask(task, at: date)
        let block = try #require(store.focusDayCanvas(at: date).blocks.first { $0.kind == .task })
        _ = store.assign(task, toBlockStartingAt: block.startAtMs, at: date)
        #expect(store.startFocus(task: task, inBlockStartingAt: block.startAtMs, at: date))
        return (store, date, task)
    }

    @Test(arguments: [30.0, 290.0])
    func returningDuringBreakMustNotOverlapFocusAndBreak(delay: TimeInterval) throws {
        let (store, _, _) = try fixture()
        let session = try #require(store.activeFocusSession())
        #expect(store.finishElapsedFocusSession(at: session.plannedEndAt.addingTimeInterval(delay)))
        let ended = try #require(store.records.state.focusSessions.first { $0.id == session.id })
        let recovery = try #require(store.activeFocusSession())
        #expect(ended.endedAt == recovery.startedAt)
        #expect(ended.actualDurationSeconds == 25 * 60)
    }

    @Test func expiredFocusMustNotAcceptExtraPomodoro() throws {
        let (store, _, task) = try fixture()
        let session = try #require(store.activeFocusSession())
        let duringBreak = session.plannedEndAt.addingTimeInterval(30)
        #expect(store.addFocusPomodoroToRunningTask(at: duringBreak) == false)
        #expect(store.records.state.focusTasks.first { $0.id == task.id }?.estimatedPomodoros == 2)
    }

    @Test func manualStopKeepsItsActualTime() throws {
        let (store, start, _) = try fixture()
        let stop = start.addingTimeInterval(90)
        store.stopFocus(reason: .stoppedByUser, at: stop)
        let session = try #require(store.records.state.focusSessions.first)
        #expect(session.endedAt == stop)
        #expect(session.actualDurationSeconds == 90)
        #expect(store.activeFocusSession() == nil)
    }

    @Test func cachedFocusButtonDisappearsAtTheFirstBoundary() {
        var state = OffWorkActivityAttributes.ContentState(
            endAtMs: 100, progress: 0, segments: [], phase: "working", locale: "en",
            appTitle: "DoneAt", caption: "Focus", completedCaption: "Done", completedNote: "",
            surface: "focus", addPomodoroLabel: "Add", addPomodoroEnabled: true
        )
        state.legs = [
            .init(startAtMs: 0, endAtMs: 100, surface: "focus", label: "Focus", title: "Task", icon: "stopwatch", detail: nil, finishNote: nil, nextNote: nil, isPreview: false),
            .init(startAtMs: 100, endAtMs: 200, surface: "shortBreak", label: "Break", title: nil, icon: "cup.and.saucer", detail: nil, finishNote: nil, nextNote: nil, isPreview: false),
            .init(startAtMs: 200, endAtMs: 300, surface: "focus", label: "Next", title: "Task", icon: "stopwatch", detail: nil, finishNote: nil, nextNote: nil, isPreview: true),
        ]
        #expect(state.showsAddPomodoro(atMs: 99))
        #expect(state.showsAddPomodoro(atMs: 100) == false)
        #expect(state.showsAddPomodoro(atMs: 200) == false)
        #expect(state.showsAddPomodoro(atMs: 300) == false)
    }

    @Test func extraPomodoroChangesBothNotificationMessages() throws {
        let (store, at, _) = try fixture()
        let session = try #require(store.activeFocusSession())
        let original = store.focusAlerts(for: session)
        #expect(store.addFocusPomodoroToRunningTask(at: at))
        let refreshed = store.focusAlerts(for: session)
        #expect(refreshed[0].body.contains("Pomodoro 1 of 3"))
        #expect(refreshed[1].body.contains("Acceptance task"))
        #expect(refreshed[1].body != original[1].body)
    }

    @Test func refreshSkipsPastAlertsAndSerializesSameSessionWrites() async throws {
        let id = UUID()
        var pending: [String: UNNotificationRequest] = [:]
        var generation = 1
        var releaseFirst: CheckedContinuation<Void, Never>?
        let entered = AsyncStream<Void>.makeStream()
        let center = NotificationService.ShiftCenter(
            authorization: { .allowed }, pendingIDs: { Array(pending.keys) }, deliveredIDs: { [] },
            add: { request in
                if request.content.body == "Old" {
                    await withCheckedContinuation { continuation in
                        releaseFirst = continuation
                        entered.continuation.yield(())
                    }
                }
                pending[request.identifier] = request
            },
            removePending: { ids in ids.forEach { pending.removeValue(forKey: $0) } },
            removeDelivered: { _ in }
        )
        let future = Date.now.addingTimeInterval(600)
        let first = Task {
            await NotificationService.scheduleFocusTimers(id: id, alerts: [
                .init(slot: .end, at: future, title: "Task", body: "Old"),
            ], center: center, isCurrent: { generation == 1 })
        }
        var iterator = entered.stream.makeAsyncIterator()
        await iterator.next()
        generation = 2
        let second = Task {
            await NotificationService.scheduleFocusTimers(id: id, alerts: [
                .init(slot: .end, at: .now.addingTimeInterval(-10), title: "Task", body: "Past"),
                .init(slot: .breakEnd, at: future, title: "Task", body: "New"),
            ], center: center, isCurrent: { generation == 2 })
        }
        try #require(releaseFirst).resume()
        #expect(await first.value == .superseded)
        #expect(await second.value == .scheduled)
        #expect(pending.values.map { $0.content.body } == ["New"])
        entered.continuation.finish()
    }
}
