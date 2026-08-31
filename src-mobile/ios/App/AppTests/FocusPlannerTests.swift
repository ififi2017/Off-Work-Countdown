import Foundation
import Testing
@testable import App

@MainActor
@Test("A focus block stops at the lunch gap instead of crossing it")
func focusStopsAtLunchGap() {
    let start = Date(timeIntervalSince1970: 1_787_566_800) // 11:40
    let segments = [
        NativeShiftSegment(startAtMs: 1_787_557_200_000, endAtMs: 1_787_568_000_000), // 09:00-12:00
        NativeShiftSegment(startAtMs: 1_787_571_600_000, endAtMs: 1_787_586_000_000), // 13:00-17:00
    ]
    let planned = FocusPlanner.plannedEnd(from: start, segments: segments, overtimeEndAtMs: nil)
    #expect(planned.timeIntervalSince1970 == 1_787_568_000)
}

@MainActor
@Test("Tasks that do not fit the remaining shift are overflow, not guilt")
func focusOverflowIsExplicit() {
    let long = FocusTask(
        id: UUID(),
        createdAt: .now,
        plannedForDate: nil,
        title: "Deep work",
        estimatedPomodoros: 4,
        completedAt: nil,
        sortIndex: 0,
        editedAt: .now,
        editCount: 1,
        editTieBreaker: UUID()
    )
    let result = FocusPlanner.remainingPomodoros(tasks: [long], remainingWorkMs: 25 * 60_000)
    #expect(result.fits.isEmpty)
    #expect(result.overflow.map(\.title) == ["Deep work"])
}

@MainActor
@Test("Task order is sortIndex then id")
func focusOrderUsesIndexThenID() {
    let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let a = FocusTask(id: high, createdAt: .now, plannedForDate: nil, title: "A", estimatedPomodoros: 1, completedAt: nil, sortIndex: 1, editedAt: .now, editCount: 1, editTieBreaker: UUID())
    let b = FocusTask(id: low, createdAt: .now, plannedForDate: nil, title: "B", estimatedPomodoros: 1, completedAt: nil, sortIndex: 1, editedAt: .now, editCount: 1, editTieBreaker: UUID())
    #expect(FocusTaskOrder.sorted([a, b]).map(\.title) == ["B", "A"])
}
