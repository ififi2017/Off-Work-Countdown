import Foundation
import Testing
@testable import App

@MainActor
@Test("Focus appointments reach idle and rest-day widgets without duplicate rows", arguments: [false, true])
func focusAppointmentsReachWidget(recurring: Bool) throws {
    let suite = "WidgetFocusProjectionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let now = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 8
    )))
    let start = now.addingTimeInterval(2 * 3_600)
    let store = OffWorkStore(defaults: defaults, records: .inMemory())
    store.plus.debugSetAuthorized(true)
    store.scheduleMode = recurring ? .classic : .off
    store.workdays = [1, 2, 3, 4, 5]
    store.addScheduledFocusTask(
        title: "Read a chapter",
        slot: FocusScheduleSlot(
            start: start,
            end: start.addingTimeInterval(25 * 60),
            shiftAnchor: Calendar.current.startOfDay(for: now),
            isCurrentShift: true
        )
    )
    let snapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: now),
        active: false,
        nowMs: Int64(now.timeIntervalSince1970 * 1_000)
    )
    let tasks = snapshot.upcoming.filter { $0.title == "Read a chapter" }
    #expect(tasks.count == 1)
    #expect(tasks.first?.kind == "focus")
    #expect(tasks.first?.dateMs == Int64(start.timeIntervalSince1970 * 1_000))

    store.plus.debugSetAuthorized(false)
    let freeSnapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: now),
        active: false,
        nowMs: Int64(now.timeIntervalSince1970 * 1_000)
    )
    #expect(!freeSnapshot.upcoming.contains { $0.kind == "focus" || $0.kind == "focusBreak" })
}
