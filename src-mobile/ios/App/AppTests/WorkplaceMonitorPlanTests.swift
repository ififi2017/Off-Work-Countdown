import Foundation
import Testing
@testable import App

/// Plan 021 §I2: which circles the system holds, how registrations are kept
/// in line across launches and edits, and what a condition change means.
@Suite("Workplace monitor plan")
nonisolated struct WorkplaceMonitorPlanTests {
    private static let now = Date(timeIntervalSince1970: 1_794_211_200)

    private static func state(workplaces: Int = 1, monitoring: Bool = true) -> WorkplaceAutomationState {
        var state = WorkplaceAutomationState()
        state.settings.isMonitoringEnabled = monitoring
        for index in 0..<workplaces {
            _ = try? state.addWorkplace(name: "Place \(index)", latitude: 31 + Double(index) / 100, longitude: 121)
        }
        return state
    }

    @Test("Identifiers are alphanumeric, round-trip, and carry the generation")
    func identifiers() throws {
        let id = UUID()
        let identifier = WorkplaceMonitorPlan.identifier(workplaceID: id, generation: 12, ring: .outer)
        #expect(identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
        let parsed = try #require(WorkplaceMonitorPlan.parse(identifier))
        #expect(parsed.workplaceID == id)
        #expect(parsed.generation == 12)
        #expect(parsed.ring == .outer)
    }

    @Test("Foreign or damaged identifiers are not workplaces", arguments: [
        "", "DoneAtWorkplaceProbe", "W1234", "WZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZG1i",
        "W00000000000000000000000000000000G1x", "W00000000000000000000000000000000Gi",
    ])
    func rejects(_ identifier: String) {
        #expect(WorkplaceMonitorPlan.parse(identifier) == nil)
    }

    @Test("Two circles per enabled workplace; paused ones are not watched")
    func wanted() throws {
        var state = Self.state(workplaces: 2)
        let paused = state.workplaces[1].id
        try state.updateWorkplace(paused, isEnabled: false)
        let wanted = WorkplaceMonitorPlan.wantedConditions(state: state, canCollect: true)
        #expect(wanted.count == 2)
        #expect(Set(wanted.map(\.ring)) == [.inner, .outer])
        let place = state.workplaces[0]
        #expect(wanted.first { $0.ring == .inner }?.radius == place.innerRadius)
        #expect(wanted.first { $0.ring == .outer }?.radius == place.outerRadius)
        #expect(!wanted.contains { $0.workplaceID == paused })
    }

    @Test("Nothing is watched when automation is off, without Plus or without places")
    func inactive() {
        #expect(WorkplaceMonitorPlan.wantedConditions(state: Self.state(monitoring: false), canCollect: true).isEmpty)
        #expect(WorkplaceMonitorPlan.wantedConditions(state: Self.state(), canCollect: false).isEmpty)
        #expect(WorkplaceMonitorPlan.wantedConditions(state: Self.state(workplaces: 0), canCollect: true).isEmpty)
        #expect(!WorkplaceMonitorPlan.isActive(state: Self.state(workplaces: 0), canCollect: true))
    }

    @Test("Five workplaces fit in ten circles")
    func fivePlaces() {
        #expect(WorkplaceMonitorPlan.wantedConditions(state: Self.state(workplaces: 5), canCollect: true).count == 10)
    }

    @Test("A relaunch keeps what the system holds and adds nothing twice")
    func reconcileKeeps() {
        let wanted = WorkplaceMonitorPlan.wantedConditions(state: Self.state(workplaces: 2), canCollect: true)
        let plan = WorkplaceMonitorPlan.reconcile(registered: Set(wanted.map(\.identifier)), wanted: wanted)
        #expect(plan.remove.isEmpty)
        #expect(plan.add.isEmpty)
    }

    @Test("Moving a workplace replaces its circles; others stay; strangers go")
    func reconcileEdit() throws {
        var state = Self.state(workplaces: 2)
        let before = WorkplaceMonitorPlan.wantedConditions(state: state, canCollect: true)
        let moved = state.workplaces[0].id
        try state.updateWorkplace(moved, latitude: 32)
        let after = WorkplaceMonitorPlan.wantedConditions(state: state, canCollect: true)
        let plan = WorkplaceMonitorPlan.reconcile(registered: Set(before.map(\.identifier) + ["Stranger1"]), wanted: after)
        #expect(Set(plan.remove) == Set(before.filter { $0.workplaceID == moved }.map(\.identifier) + ["Stranger1"]))
        #expect(plan.add.count == 2)
        #expect(plan.add.allSatisfy { $0.workplaceID == moved && $0.latitude == 32 })
    }

    @Test("Only the inner circle filling and the outer one emptying are crossings")
    func events() throws {
        let id = UUID()
        let inner = WorkplaceMonitorPlan.identifier(workplaceID: id, generation: 3, ring: .inner)
        let outer = WorkplaceMonitorPlan.identifier(workplaceID: id, generation: 3, ring: .outer)
        func event(_ identifier: String, _ state: WorkplaceConditionState) -> AutomationEvent? {
            WorkplaceMonitorPlan.event(identifier: identifier, state: state, observedAt: Self.now,
                                       receivedAt: Self.now.addingTimeInterval(40), isInitialState: false)
        }
        let arrival = try #require(event(inner, .satisfied))
        #expect(arrival.type == .enterInner)
        #expect(arrival.workplaceID == id)
        #expect(arrival.registrationGeneration == 3)
        #expect(arrival.source == .nativeGeofence)
        #expect(arrival.observedAt == Self.now)
        #expect(arrival.timestampBasis == .systemObservation)
        #expect(event(outer, .unsatisfied)?.type == .exitOuter)
        #expect(event(inner, .unsatisfied) == nil)
        #expect(event(outer, .satisfied) == nil)
        // Unknown is never a departure.
        #expect(event(outer, .unknown) == nil)
        #expect(event(inner, .unknown) == nil)
        #expect(event("Stranger1", .satisfied) == nil)
    }

    @Test("A missing or impossible observation time falls back to receipt time")
    func observationTime() throws {
        let identifier = WorkplaceMonitorPlan.identifier(workplaceID: UUID(), generation: 1, ring: .inner)
        let missing = try #require(WorkplaceMonitorPlan.event(
            identifier: identifier, state: .satisfied, observedAt: nil, receivedAt: Self.now, isInitialState: false
        ))
        #expect(missing.observedAt == nil)
        #expect(missing.timestampBasis == .callbackReceipt)
        let future = try #require(WorkplaceMonitorPlan.event(
            identifier: identifier, state: .satisfied, observedAt: Self.now.addingTimeInterval(3_600),
            receivedAt: Self.now, isInitialState: false
        ))
        #expect(future.observedAt == nil)
        #expect(WorkplaceMonitorPlan.event(
            identifier: identifier, state: .satisfied, observedAt: Self.now, receivedAt: Self.now, isInitialState: true
        )?.isInitialState == true)
    }

    @Test("A circle's first report is its baseline, once")
    func baseline() {
        var state = WorkplaceAutomationState()
        state.awaitBaseline(["A", "B"])
        let first = state.takeBaseline("A")
        let second = state.takeBaseline("A")
        #expect(first)
        #expect(!second)
        state.keepBaseline(only: ["C"])
        #expect(state.awaitingBaseline.isEmpty)
    }

    @Test("A held stretch asks once, and the release takes the latest wake")
    func heldWakes() {
        var state = WorkplaceAutomationState()
        let first = Self.now
        let second = Self.now.addingTimeInterval(87 * 60)
        let starts = state.noteHeldWake(at: first)
        let startsAgain = state.noteHeldWake(at: second)
        #expect(starts)
        #expect(!startsAgain)
        let released = second.addingTimeInterval(7 * 60)
        let taken = state.takeHeldWake(receivedAt: released)
        // Spent, with everything before it: the next event keeps its own time.
        let takenAgain = state.takeHeldWake(receivedAt: released)
        #expect(taken == second)
        #expect(takenAgain == nil)
        #expect(state.heldWakes.isEmpty)
    }

    @Test("A held wake older than twelve hours places nothing")
    func staleHeldWake() {
        var state = WorkplaceAutomationState()
        _ = state.noteHeldWake(at: Self.now)
        let later = Self.now.addingTimeInterval(13 * 60 * 60)
        let taken = state.takeHeldWake(receivedAt: later)
        #expect(taken == nil)
        // A new stretch starts once the old wake has aged out.
        let starts = state.noteHeldWake(at: later)
        #expect(starts)
    }

    @Test("Files written before held wakes decode with none")
    func heldWakesDecodeEmpty() throws {
        var state = WorkplaceAutomationState()
        _ = state.noteHeldWake(at: Self.now)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "heldWakes")
        let decoded = try JSONDecoder().decode(
            WorkplaceAutomationState.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.heldWakes.isEmpty)
    }

    @Test("An edited region's late event is stale for the coordinator")
    @MainActor
    func staleGeneration() throws {
        var state = Self.state()
        let place = state.workplaces[0]
        let identifier = WorkplaceMonitorPlan.identifier(workplaceID: place.id, generation: place.registrationGeneration, ring: .inner)
        try state.updateWorkplace(place.id, innerRadius: 300)
        let event = try #require(WorkplaceMonitorPlan.event(
            identifier: identifier, state: .satisfied, observedAt: Self.now, receivedAt: Self.now, isInitialState: false
        ))
        let disposition = WorkplaceAutomationRules.disposition(
            for: event, now: Self.now, currentGeneration: state.workplace(place.id)?.registrationGeneration,
            settings: state.settings, canCollect: true, canAutoApply: true, isManuallySuppressed: false
        )
        #expect(disposition == .ignore(.staleRegistration))
    }

    @Test("System flags map to the problems the settings page explains")
    func problems() {
        #expect(WorkplaceMonitorStatus.problems(
            authorizationDenied: false, deniedGlobally: true, restricted: false, alwaysDenied: true,
            accuracyLimited: true, conditionLimitExceeded: true, conditionUnsupported: false, persistenceUnavailable: false
        ) == [.locationOff, .needsAlways, .needsPreciseLocation, .tooManyRegions])
        #expect(WorkplaceMonitorStatus.problems(
            authorizationDenied: false, deniedGlobally: false, restricted: false, alwaysDenied: false,
            accuracyLimited: false, conditionLimitExceeded: false, conditionUnsupported: false, persistenceUnavailable: false
        ).isEmpty)
        #expect(!WorkplaceMonitorStatus().isRegistered)
        #expect(WorkplaceMonitorStatus(registeredCount: 2, wantedCount: 2).isRegistered)
    }

    @Test("A region stands for its condition; others are not ours")
    func regionIdentifiers() {
        let identifier = WorkplaceMonitorPlan.identifier(workplaceID: UUID(), generation: 2, ring: .inner)
        let region = WorkplaceMonitorPlan.regionIdentifier(for: identifier)
        #expect(region.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
        #expect(WorkplaceMonitorPlan.conditionIdentifier(forRegion: region) == identifier)
        #expect(WorkplaceMonitorPlan.conditionIdentifier(forRegion: identifier) == nil)
        #expect(WorkplaceMonitorPlan.conditionIdentifier(forRegion: "legacy.inner") == nil)
        #expect(WorkplaceMonitorPlan.conditionIdentifier(forRegion: "LStranger") == nil)
    }

    @Test("Both APIs reporting one crossing deliver it once, CLMonitor first")
    func ledgerBothReport() {
        var ledger = WorkplaceCrossingLedger()
        let r1 = ledger.monitorReports("A", state: .satisfied, isInitialState: false)
        #expect(r1)
        let r2 = ledger.regionReports("A", satisfied: true)
        #expect(!r2)
        // CLMonitor's own repeat still passes, as before.
        let r3 = ledger.monitorReports("A", state: .satisfied, isInitialState: false)
        #expect(r3)
    }

    @Test("A held CLMonitor report after the region's is dropped")
    func ledgerHeldMonitor() {
        var ledger = WorkplaceCrossingLedger()
        let r4 = ledger.monitorReports("A", state: .unsatisfied, isInitialState: true)
        #expect(r4)
        let r5 = ledger.regionReports("A", satisfied: true)
        #expect(r5)
        let r6 = ledger.monitorReports("A", state: .satisfied, isInitialState: false)
        #expect(!r6)
        // The next real edge goes through from either side.
        let r7 = ledger.regionReports("A", satisfied: false)
        #expect(r7)
        let r8 = ledger.monitorReports("A", state: .satisfied, isInitialState: false)
        #expect(r8)
    }

    @Test("Unknown never counts; a baseline always passes; removed circles are forgotten")
    func ledgerEdges() {
        var ledger = WorkplaceCrossingLedger()
        let r9 = ledger.regionReports("A", satisfied: true)
        #expect(r9)
        let r10 = ledger.monitorReports("A", state: .unknown, isInitialState: false)
        #expect(r10)
        let r11 = ledger.monitorReports("A", state: .satisfied, isInitialState: true)
        #expect(r11)
        ledger.keep(only: ["B"])
        #expect(ledger.edges.isEmpty)
        let r12 = ledger.regionReports("A", satisfied: true)
        #expect(r12)
    }

    @Test("A state read is a crossing only when it disagrees with a known edge")
    func ledgerStateRead() {
        var ledger = WorkplaceCrossingLedger()
        // Nothing known yet: remembered, not a crossing.
        let first = ledger.regionStateRead("A", satisfied: false)
        #expect(!first)
        let same = ledger.regionStateRead("A", satisfied: false)
        #expect(!same)
        let crossed = ledger.regionStateRead("A", satisfied: true)
        #expect(crossed)
        // CLMonitor's later report of that edge is the same crossing.
        let monitor = ledger.monitorReports("A", state: .satisfied, isInitialState: false)
        #expect(!monitor)
    }
}
