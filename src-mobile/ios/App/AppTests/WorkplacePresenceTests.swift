import Foundation
import Testing
@testable import App

/// Plan 021: what the timer shows from arrivals and departures.
@Suite("Workplace presence")
struct WorkplacePresenceTests {
    private static let start = Date(timeIntervalSince1970: 1_794_000_000)
    private static let end = start.addingTimeInterval(9 * 3_600)

    private static func state(_ events: [(AutomationEventType, Date, Bool)], monitoring: Bool = true) -> WorkplaceAutomationState {
        var state = WorkplaceAutomationState()
        state.settings.isMonitoringEnabled = monitoring
        for (type, time, initial) in events {
            state.record(AutomationEvent(
                id: UUID(), source: .nativeGeofence, type: type, workplaceID: nil,
                registrationGeneration: 0, observedAt: time, receivedAt: time,
                timestampBasis: .systemObservation, isInitialState: initial
            ))
        }
        return state
    }

    private static func resolve(_ state: WorkplaceAutomationState, now: Date) -> WorkplacePresence? {
        WorkplacePresence.resolve(plannedStart: start, plannedEnd: end, state: state, now: now)
    }

    @Test func arrivalBeforeTheShiftShowsItsTime() {
        let arrival = Self.start.addingTimeInterval(-20 * 60)
        let state = Self.state([(.enterInner, arrival, false)])
        #expect(Self.resolve(state, now: Self.start.addingTimeInterval(-5 * 60)) == .arrived(at: arrival))
        // The arrival stays a fact through the shift, whatever work counts from.
        #expect(Self.resolve(state, now: Self.start.addingTimeInterval(3_600)) == .arrived(at: arrival))
    }

    @Test func returningFromLunchKeepsTheFirstArrival() {
        let arrival = Self.start.addingTimeInterval(-10 * 60)
        let state = Self.state([
            (.enterInner, arrival, false),
            (.exitOuter, Self.start.addingTimeInterval(3 * 3_600), false),
            (.enterInner, Self.start.addingTimeInterval(4 * 3_600), false),
        ])
        #expect(Self.resolve(state, now: Self.start.addingTimeInterval(5 * 3_600)) == .arrived(at: arrival))
    }

    @Test func alreadyThereWhenMonitoringStartedSaysNothingDuringTheShift() {
        let state = Self.state([(.enterInner, Self.start.addingTimeInterval(-600), true)])
        #expect(Self.resolve(state, now: Self.start.addingTimeInterval(3_600)) == nil)
    }

    @Test func alreadyThereWhenMonitoringStartedHasNoArrivalTime() {
        let state = Self.state([(.enterInner, Self.start.addingTimeInterval(-600), true)])
        #expect(Self.resolve(state, now: Self.start.addingTimeInterval(-60)) == .arrived(at: nil))
    }

    @Test func stillThereAfterThePlannedEndIsStayingLate() {
        let state = Self.state([(.enterInner, Self.start.addingTimeInterval(-600), false)])
        let now = Self.end.addingTimeInterval(83 * 60)
        let presence = Self.resolve(state, now: now)
        #expect(presence == .stayingLate(plannedEnd: Self.end))
        #expect(abs((presence?.overtime(at: now) ?? 0) - 83 * 60) < 0.001)
    }

    @Test func theFirstFiveMinutesAfterTheEndAreStillJustTheEnd() {
        let state = Self.state([(.enterInner, Self.start.addingTimeInterval(-600), false)])
        #expect(Self.resolve(state, now: Self.end) == nil)
        #expect(Self.resolve(state, now: Self.end.addingTimeInterval(4 * 60 + 59)) == nil)
        #expect(Self.resolve(state, now: Self.end.addingTimeInterval(5 * 60)) == .stayingLate(plannedEnd: Self.end))
    }

    @Test func stillThereAfterSixHoursNeedsCheckingAndCountsNothing() {
        let state = Self.state([(.enterInner, Self.start, false)])
        let now = Self.end.addingTimeInterval(WorkplaceAutomation.maximumAutomaticExtension + 60)
        let presence = Self.resolve(state, now: now)
        #expect(presence == .needsCheck(plannedEnd: Self.end))
        #expect(presence?.overtime(at: now) == 0)
    }

    @Test func leavingAfterTheEndCountsTheOvertime() {
        let exit = Self.end.addingTimeInterval(40 * 60)
        let state = Self.state([(.enterInner, Self.start, false), (.exitOuter, exit, false)])
        let presence = Self.resolve(state, now: exit.addingTimeInterval(3_600))
        #expect(presence == .left(at: exit, plannedEnd: Self.end))
        #expect(abs((presence?.overtime(at: .distantFuture) ?? 0) - 40 * 60) < 0.001)
    }

    @Test func leavingDuringTheShiftHasNoOvertime() {
        let exit = Self.start.addingTimeInterval(3 * 3_600)
        let state = Self.state([(.enterInner, Self.start, false), (.exitOuter, exit, false)])
        let presence = Self.resolve(state, now: exit.addingTimeInterval(60))
        #expect(presence == .left(at: exit, plannedEnd: Self.end))
        #expect(presence?.overtime(at: exit.addingTimeInterval(60)) == 0)
    }

    @Test func leavingBeforeTheShiftOrWithMonitoringOffSaysNothing() {
        let early = Self.state([(.exitOuter, Self.start.addingTimeInterval(-3_600), false)])
        #expect(Self.resolve(early, now: Self.start.addingTimeInterval(-60)) == nil)
        let off = Self.state([(.enterInner, Self.start.addingTimeInterval(-600), false)], monitoring: false)
        #expect(Self.resolve(off, now: Self.start.addingTimeInterval(-60)) == nil)
        // Yesterday's events are outside the window.
        let old = Self.state([(.enterInner, Self.start.addingTimeInterval(-20 * 3_600), false)])
        #expect(Self.resolve(old, now: Self.start.addingTimeInterval(-60)) == nil)
    }
}
