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
        scheduledStartAt: nil,
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
@Test("Overflow measures remaining blocks, not the original estimate")
func focusOverflowUsesRemainingBlocks() {
    let long = FocusTask(
        id: UUID(),
        createdAt: .now,
        plannedForDate: nil,
        scheduledStartAt: nil,
        title: "Deep work",
        estimatedPomodoros: 4,
        completedAt: nil,
        sortIndex: 0,
        editedAt: .now,
        editCount: 1,
        editTieBreaker: UUID()
    )
    let result = FocusPlanner.remainingPomodoros(
        tasks: [long],
        remainingWorkMs: 25 * 60_000,
        completedBlocks: { _ in 3 }
    )
    #expect(result.fits.map(\.title) == ["Deep work"])
    #expect(result.overflow.isEmpty)
}

@MainActor
@Test("Task order is sortIndex then id")
func focusOrderUsesIndexThenID() {
    let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let a = FocusTask(id: high, createdAt: .now, plannedForDate: nil, scheduledStartAt: nil, title: "A", estimatedPomodoros: 1, completedAt: nil, sortIndex: 1, editedAt: .now, editCount: 1, editTieBreaker: UUID())
    let b = FocusTask(id: low, createdAt: .now, plannedForDate: nil, scheduledStartAt: nil, title: "B", estimatedPomodoros: 1, completedAt: nil, sortIndex: 1, editedAt: .now, editCount: 1, editTieBreaker: UUID())
    #expect(FocusTaskOrder.sorted([a, b]).map(\.title) == ["B", "A"])
}

@MainActor
@Test("Focus cannot start before the first segment or during lunch")
func focusStartsOnlyInsideWork() {
    let segments = [
        NativeShiftSegment(startAtMs: 1_787_557_200_000, endAtMs: 1_787_568_000_000),
        NativeShiftSegment(startAtMs: 1_787_571_600_000, endAtMs: 1_787_586_000_000),
    ]
    let before = Date(timeIntervalSince1970: 1_787_557_200 - 600)
    let lunch = Date(timeIntervalSince1970: 1_787_568_000 + 60)
    let morning = Date(timeIntervalSince1970: 1_787_557_200 + 60)
    let overtime = Date(timeIntervalSince1970: 1_787_586_000 + 60)
    #expect(!FocusPlanner.isInsideWork(at: before, segments: segments, overtimeEndAtMs: nil))
    #expect(!FocusPlanner.isInsideWork(at: lunch, segments: segments, overtimeEndAtMs: nil))
    #expect(FocusPlanner.isInsideWork(at: morning, segments: segments, overtimeEndAtMs: nil))
    #expect(
        FocusPlanner.isInsideWork(
            at: overtime,
            segments: segments,
            overtimeEndAtMs: 1_787_586_000_000 + 3_600_000
        )
    )
}

@MainActor
@Test("Pomodoro blocks follow effective segments and preserve a 90-minute lunch gap")
func focusBlocksPreserveConfiguredLunchGap() throws {
    let morningStart = 1_788_143_400_000.0 // 10:00
    let morningEnd = morningStart + 2.5 * 3_600_000 // 12:30
    let afternoonStart = morningEnd + 90 * 60_000 // 14:00
    let afternoonEnd = afternoonStart + 5 * 3_600_000 // 19:00
    let blocks = FocusPlanner.workBlocks(segments: [
        NativeShiftSegment(startAtMs: morningStart, endAtMs: morningEnd),
        NativeShiftSegment(startAtMs: afternoonStart, endAtMs: afternoonEnd),
    ])

    let morningLast = try #require(blocks.last(where: {
        $0.end.timeIntervalSince1970 * 1_000 <= morningEnd
    }))
    let afternoonFirst = try #require(blocks.first(where: { $0.start.timeIntervalSince1970 * 1_000 == afternoonStart }))
    #expect(morningLast.end.timeIntervalSince1970 * 1_000 <= morningEnd)
    #expect(afternoonFirst.start.timeIntervalSince(morningLast.end) >= 90 * 60)
}

@MainActor
@Test("Planning timeline alternates 25-minute focus with 5-minute breaks and a 15-minute fourth break")
func planningTimelineUsesPomodoroCycleDurations() {
    let start = Date(timeIntervalSince1970: 1_788_143_400)
    let blocks = FocusPlanner.workBlocks(segments: [
        NativeShiftSegment(startAtMs: start.timeIntervalSince1970 * 1_000, endAtMs: start.addingTimeInterval(200 * 60).timeIntervalSince1970 * 1_000),
    ])
    #expect(blocks.prefix(8).map(\.kind) == [.task, .breakTime, .task, .breakTime, .task, .breakTime, .task, .breakTime])
    #expect(blocks[1].durationMinutes == 5)
    #expect(blocks[3].durationMinutes == 5)
    #expect(blocks[5].durationMinutes == 5)
    #expect(blocks[7].durationMinutes == 15)
}

@MainActor
@Test("Timer settings clamp to supported focus and break ranges")
func focusTimerSettingsClampToSupportedRanges() {
    let settings = FocusTimerSettings(focusMinutes: 2, shortBreakMinutes: 20, longBreakMinutes: 2, longBreakEvery: 9).normalized
    #expect(settings.focusMinutes == 10)
    #expect(settings.shortBreakMinutes == 15)
    #expect(settings.longBreakMinutes == 5)
    #expect(settings.longBreakEvery == 6)
}

@MainActor
@Test("Configured focus duration determines blocks and boundary completion")
func configuredFocusDurationIsUsedEverywhere() {
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let longSegment = [NativeShiftSegment(startAtMs: 1_787_557_200_000, endAtMs: 1_787_561_100_000)]
    let shortSegment = [NativeShiftSegment(startAtMs: 1_787_557_200_000, endAtMs: 1_787_559_000_000)]
    let settings = FocusTimerSettings(focusMinutes: 60, shortBreakMinutes: 5, longBreakMinutes: 15, longBreakEvery: 4)
    let blocks = FocusPlanner.workBlocks(segments: longSegment, settings: settings)
    #expect(blocks.count(where: { $0.kind == .task }) == 1)
    #expect(blocks.count(where: { $0.kind == .breakTime }) == 1)
    let cut = FocusPlanner.plannedEnd(from: start, segments: shortSegment, overtimeEndAtMs: nil, durationMinutes: 60)
    #expect(FocusPlanner.endReason(startedAt: start, plannedEndAt: cut, expectedDurationMinutes: 60) == .stoppedAtBoundary)
}

@MainActor
@Test("A shared micro-break boundary truncates a focus phase")
func microBreakBoundaryTruncatesFocus() {
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let microBreak = start.addingTimeInterval(8 * 60)
    let segments = [NativeShiftSegment(startAtMs: 1_787_557_200_000, endAtMs: 1_787_560_800_000)]
    let end = FocusPlanner.plannedEnd(
        from: start,
        segments: segments,
        overtimeEndAtMs: nil,
        durationMinutes: 25,
        extraBoundaries: [microBreak]
    )
    #expect(end == microBreak)
    #expect(FocusPlanner.endReason(startedAt: start, plannedEndAt: end) == .stoppedAtBoundary)
}

@MainActor
@Test("A boundary less than one minute away leaves no startable focus room")
func microBreakBoundaryRejectsSubMinuteStart() {
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let boundary = start.addingTimeInterval(59)
    let segments = [NativeShiftSegment(startAtMs: 1_787_557_200_000, endAtMs: 1_787_560_800_000)]
    let end = FocusPlanner.plannedEnd(
        from: start,
        segments: segments,
        overtimeEndAtMs: nil,
        extraBoundaries: [boundary]
    )
    #expect(end.timeIntervalSince(start) < 60)
}

@MainActor
@Test("Live Activity gives work the one slot only in its configured window")
func liveActivityPriorityIsDeterministic() {
    let now = Date(timeIntervalSince1970: 1_787_557_200)
    let focus = FocusSession(
        id: UUID(), taskID: nil, shiftAnchorDate: now, startedAt: now,
        plannedEndAt: now.addingTimeInterval(5 * 60), endedAt: nil, endReason: nil,
        editedAt: now, editCount: 0, editTieBreaker: UUID(), kind: .shortBreak
    )
    #expect(LiveActivityDecision.choose(
        workEndAt: now.addingTimeInterval(60 * 60),
        workDisplayStartsAt: now.addingTimeInterval(30 * 60),
        focusSession: focus, now: now
    )?.surface == .shortBreak)
    #expect(LiveActivityDecision.choose(
        workEndAt: now.addingTimeInterval(60 * 60),
        workDisplayStartsAt: now.addingTimeInterval(-1),
        focusSession: focus, now: now
    )?.surface == .work)
}

@MainActor
@Test("A matching focus activity updates in place while identity changes replace it")
func focusLiveActivityReconciliationIsPure() {
    let focus = LiveActivityIdentity(plannedEndAtMs: 100, surface: .focus)
    #expect(LiveActivityReconciler.action(existing: [focus], desired: focus) == .updateExisting(duplicates: 0))
    #expect(LiveActivityReconciler.action(existing: [focus, focus], desired: focus) == .updateExisting(duplicates: 1))
    #expect(LiveActivityReconciler.action(
        existing: [focus],
        desired: .init(plannedEndAtMs: 100, surface: .shortBreak)
    ) == .replace)
}

@MainActor
@Test("A completion from an old Live Activity generation cannot end a replacement")
func staleLiveActivityCompletionIsRejected() {
    #expect(LiveActivityReconciler.completionMayRun(scheduledGeneration: 3, currentGeneration: 3))
    #expect(!LiveActivityReconciler.completionMayRun(scheduledGeneration: 3, currentGeneration: 4))
}

@MainActor
@Test("Focus Live Activity keeps a later work-window wake after focus completes")
func focusLiveActivityWakePlanCoversBothBoundaryOrders() {
    let now = Date(timeIntervalSince1970: 1_787_557_200)
    let focusEnd = now.addingTimeInterval(10 * 60)

    #expect(FocusLiveActivityWakePlan.make(
        focusEndsAt: focusEnd,
        workDisplayStartsAt: now.addingTimeInterval(5 * 60),
        now: now
    ) == .workHandoffBeforeCompletion)
    #expect(FocusLiveActivityWakePlan.make(
        focusEndsAt: focusEnd,
        workDisplayStartsAt: now.addingTimeInterval(30 * 60),
        now: now
    ) == .completionThenWorkHandoff)
    #expect(FocusLiveActivityWakePlan.make(
        focusEndsAt: focusEnd,
        workDisplayStartsAt: nil,
        now: now
    ) == .completionOnly)
}

@MainActor
@Test("Focus Live Activity service re-arbitrates at the work display boundary")
func focusLiveActivityPriorityTransitionRunsAtWorkBoundary() async {
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let boundary = start.addingTimeInterval(30 * 60)
    let clock = LiveActivityManualClock(now: start)
    let transition = LiveActivityPriorityTransitionService(clock: .init(
        now: { clock.now },
        sleep: { interval in await clock.sleep(for: interval) }
    ))
    var fired: [Date] = []

    transition.schedule(at: boundary) {
        fired.append(clock.now)
    }
    await Task.yield()

    #expect(transition.scheduledAt == boundary)
    #expect(clock.pendingSleepCount == 1)
    #expect(fired.isEmpty)

    clock.advance(to: boundary)
    await Task.yield()
    await Task.yield()

    #expect(fired == [boundary])
    #expect(transition.scheduledAt == nil)
}

@MainActor
@Test("Replacing a focus-to-work handoff rejects the stale scheduled action")
func staleFocusLiveActivityPriorityTransitionIsRejected() async {
    let start = Date(timeIntervalSince1970: 1_787_557_200)
    let firstBoundary = start.addingTimeInterval(10 * 60)
    let replacementBoundary = start.addingTimeInterval(20 * 60)
    let clock = LiveActivityManualClock(now: start)
    let transition = LiveActivityPriorityTransitionService(clock: .init(
        now: { clock.now },
        sleep: { interval in await clock.sleep(for: interval) }
    ))
    var fired: [String] = []

    transition.schedule(at: firstBoundary) {
        fired.append("stale")
    }
    await Task.yield()
    transition.schedule(at: replacementBoundary) {
        fired.append("replacement")
    }
    await Task.yield()

    clock.advance(to: firstBoundary)
    await Task.yield()
    #expect(fired.isEmpty)
    #expect(transition.scheduledAt == replacementBoundary)

    clock.advance(to: replacementBoundary)
    await Task.yield()
    await Task.yield()
    #expect(fired == ["replacement"])
}

@MainActor
@Test("Focus notification decision keeps permission and scheduling testable")
func focusNotificationDecisionIsPure() {
    #expect(NotificationService.focusSchedulingDecision(for: .notDetermined) == .requestPermission)
    #expect(NotificationService.focusSchedulingDecision(for: .allowed) == .schedule)
    #expect(NotificationService.focusSchedulingDecision(for: .denied) == .blocked)
}

@MainActor
private final class LiveActivityManualClock {
    private struct Sleeper {
        var deadline: Date
        var continuation: CheckedContinuation<Bool, Never>
    }

    var now: Date
    private var sleepers: [Sleeper] = []

    init(now: Date) {
        self.now = now
    }

    var pendingSleepCount: Int { sleepers.count }

    func sleep(for interval: TimeInterval) async -> Bool {
        let deadline = now.addingTimeInterval(max(0, interval))
        return await withCheckedContinuation { continuation in
            sleepers.append(.init(deadline: deadline, continuation: continuation))
        }
    }

    func advance(to date: Date) {
        now = date
        let ready = sleepers.filter { $0.deadline <= date }
        sleepers.removeAll { $0.deadline <= date }
        for sleeper in ready {
            sleeper.continuation.resume(returning: true)
        }
    }
}
