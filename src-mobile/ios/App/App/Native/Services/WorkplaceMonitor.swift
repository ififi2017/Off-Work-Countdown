import CoreLocation
import Observation
import UIKit

/// Plan 021 §I2: the one app-level owner of native workplace monitoring.
///
/// It holds an always-authorization `CLServiceSession` and a single named
/// `CLMonitor`, keeps the system's circles in line with the saved workplaces
/// (`WorkplaceMonitorPlan`), and hands each crossing to the automation
/// coordinator, the same command path a Shortcuts action uses. It resumes at
/// every launch, including a background launch the system makes for a
/// crossing, so it never waits for the settings page. Coordinates go to the
/// system and the device-only automation file, nowhere else.
@MainActor
@Observable
final class WorkplaceMonitor {
    struct Dependencies {
        var automation: WorkplaceAutomationCoordinator
        var canCollect: @MainActor () -> Bool
        var shifts: @MainActor (Date) -> [AutomationShift]
        /// Called with each crossing's outcome, for the arrival notice.
        var didHandle: @MainActor (AutomationEvent, AutomationCommandOutcome) async -> Void
        /// iOS woke the app for a crossing but is holding the event until the
        /// app is opened (it was swiped away): ask the person to open it.
        var didHoldCrossing: @MainActor () async -> Void = {}
        /// The held events are flowing again; the ask is no longer needed.
        var didReleaseHold: @MainActor () async -> Void = {}
    }

    private(set) var status = WorkplaceMonitorStatus()

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var session: CLServiceSession?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var reconciling = false
    @ObservationIgnored private var reconcileAgain = false
    @ObservationIgnored private var sessionProblems: Set<WorkplaceMonitorStatus.Problem> = []
    @ObservationIgnored private var monitorProblems: Set<WorkplaceMonitorStatus.Problem> = []
    @ObservationIgnored private var lastDiagnosticHeld: Bool?
    @ObservationIgnored private var heldNotedThisProcess = false
    /// This process, in the background, heard from the region API about a
    /// crossing: the sign it was woken for one. Launch options do not say so
    /// (device tests 2026-11-12/13: region launches carried no location key).
    @ObservationIgnored private var wokeForCrossing = false
    /// The region API recorded a crossing in this process, so there is
    /// nothing left to ask the person to open the app for.
    @ObservationIgnored private var regionRecordedThisProcess = false
    /// When held events started flowing again; events received shortly
    /// after take the held wake time.
    @ObservationIgnored private var releasedAt: Date?
    /// One report per crossing from the two APIs watching each circle.
    @ObservationIgnored private var ledger: WorkplaceCrossingLedger

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        ledger = Self.loadLedger()
        refreshStatus(registered: 0)
        WorkplaceRegions.shared.onCrossing = { [weak self] crossing in
            Task { await self?.handle(crossing) }
        }
    }

    private var automation: WorkplaceAutomationCoordinator { dependencies.automation }

    /// Brings session, monitor and circles in line with the saved settings.
    /// Safe to call at launch, on foreground and after every settings change;
    /// overlapping calls collapse into one more pass.
    func reconcile() async {
        if reconciling { reconcileAgain = true; return }
        reconciling = true
        defer { reconciling = false }
        repeat {
            reconcileAgain = false
            await reconcileOnce()
        } while reconcileAgain
    }

    private func reconcileOnce() async {
        let state = automation.state
        let canCollect = dependencies.canCollect()
        guard automation.isAvailable, WorkplaceMonitorPlan.isActive(state: state, canCollect: canCollect) else {
            await stop()
            return
        }
        startSession()
        let monitor = await ensureMonitor()
        let wanted = WorkplaceMonitorPlan.wantedConditions(state: state, canCollect: canCollect)
        let registered = Set(await monitor.identifiers)
        let plan = WorkplaceMonitorPlan.reconcile(registered: registered, wanted: wanted)
        for identifier in plan.remove { await monitor.remove(identifier) }
        // Saved before adding: a report that races the add is still a baseline.
        if !plan.add.isEmpty || !state.awaitingBaseline.isSubset(of: Set(wanted.map(\.identifier))) {
            automation.update {
                $0.keepBaseline(only: Set(wanted.map(\.identifier)))
                $0.awaitBaseline(plan.add.map(\.identifier))
            }
        }
        if !plan.add.isEmpty { UserDefaults.standard.set(true, forKey: Self.mayHoldConditionsKey) }
        for condition in plan.add {
            await monitor.add(
                CLMonitor.CircularGeographicCondition(
                    center: CLLocationCoordinate2D(latitude: condition.latitude, longitude: condition.longitude),
                    radius: condition.radius
                ),
                identifier: condition.identifier
            )
        }
        WorkplaceRegions.shared.reconcile(wanted: wanted)
        // In a background launch, ask where the person is: a crossing iOS
        // woke the app for shows up even if its callback is held.
        if UIApplication.shared.applicationState == .background { WorkplaceRegions.shared.requestStates() }
        updateLedger { $0.keep(only: Set(wanted.map(\.identifier))) }
        refreshStatus(registered: Set(await monitor.identifiers).intersection(wanted.map(\.identifier)).count)
    }

    /// Set once circles were added, so a later launch with automation off
    /// (or Plus ended) still clears what the system kept, while a person who
    /// never used automation never gets a monitor created at all.
    private static let mayHoldConditionsKey = "owc.workplaceMonitor.mayHoldConditions"

    /// Nothing to watch: no circles, no session, no event loop.
    private func stop() async {
        let defaults = UserDefaults.standard
        if monitor != nil || defaults.bool(forKey: Self.mayHoldConditionsKey) {
            let monitor = await ensureMonitor()
            for identifier in await monitor.identifiers { await monitor.remove(identifier) }
            WorkplaceRegions.shared.stopAll()
            defaults.set(false, forKey: Self.mayHoldConditionsKey)
        }
        if !ledger.edges.isEmpty { updateLedger { $0.keep(only: []) } }
        eventTask?.cancel()
        sessionTask?.cancel()
        session?.invalidate()
        eventTask = nil
        sessionTask = nil
        session = nil
        monitor = nil
        sessionProblems = []
        monitorProblems = []
        if !automation.state.awaitingBaseline.isEmpty {
            automation.update { $0.keepBaseline(only: []) }
        }
        refreshStatus(registered: 0)
    }

    // MARK: System objects

    private func startSession() {
        guard session == nil else { return }
        // Created again at every launch: the session is what keeps
        // always-authorization monitoring alive across relaunches.
        let session = CLServiceSession(authorization: .always)
        self.session = session
        sessionTask = Task { [weak self] in
            do {
                for try await diagnostic in session.diagnostics {
                    self?.handle(diagnostic)
                }
            } catch {}
        }
    }

    private func ensureMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let monitor = await CLMonitor(WorkplaceMonitorPlan.monitorName)
        self.monitor = monitor
        eventTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    await self?.handle(event)
                }
            } catch {}
        }
        return monitor
    }

    // MARK: Events

    private func handle(_ event: CLMonitor.Event) async {
        monitorProblems = WorkplaceMonitorStatus.problems(
            authorizationDenied: event.authorizationDenied,
            deniedGlobally: event.authorizationDeniedGlobally,
            restricted: event.authorizationRestricted,
            alwaysDenied: false,
            accuracyLimited: event.accuracyLimited,
            conditionLimitExceeded: event.conditionLimitExceeded,
            conditionUnsupported: event.conditionUnsupported,
            persistenceUnavailable: event.persistenceUnavailable
        )
        let state: WorkplaceConditionState = switch event.state {
        case .satisfied: .satisfied
        case .unsatisfied: .unsatisfied
        default: .unknown
        }
        let now = Date.now
        // The first known state of a new circle is where the person is, not
        // a crossing. Unknown does not use up the baseline.
        var isInitial = false
        if state != .unknown, automation.state.awaitingBaseline.contains(event.identifier) {
            automation.update { _ = $0.takeBaseline(event.identifier) }
            isInitial = true
        }
        // The region API may already have delivered this crossing.
        var delivers = true
        updateLedger { delivers = $0.monitorReports(event.identifier, state: state, isInitialState: isInitial) }
        guard delivers, var automationEvent = WorkplaceMonitorPlan.event(
            identifier: event.identifier, state: state, observedAt: event.date,
            receivedAt: now, isInitialState: isInitial
        ) else {
            refreshStatus(registered: status.registeredCount)
            return
        }
        // Held while the app was swiped away: the system dates the event
        // when it finally delivers it, but it woke the app at the crossing.
        if !isInitial, let releasedAt,
           now.timeIntervalSince(releasedAt) <= WorkplaceAutomation.heldReleaseWindow {
            var wake: Date?
            automation.update { wake = $0.takeHeldWake(receivedAt: now) }
            if let wake {
                automationEvent.observedAt = wake
                automationEvent.timestampBasis = .heldWake
            }
        }
        let outcome = await automation.receive(automationEvent, shifts: dependencies.shifts(now), now: now)
        refreshStatus(registered: status.registeredCount)
        await dependencies.didHandle(automationEvent, outcome)
    }

    /// How long a region callback waits for `CLMonitor` to report the same
    /// crossing; in device tests the two came within milliseconds.
    private static let regionGrace: Duration = .seconds(3)

    /// A region API crossing: used only when `CLMonitor` has not reported it.
    private func handle(_ crossing: WorkplaceRegions.Crossing) async {
        // A crossing callback, or a state read that disagrees with the last
        // known edge, in the background: the app was woken for a crossing.
        // An agreeing read (any background launch asks) says nothing.
        let isNews = !crossing.isStateRead
            || ledger.edges[crossing.identifier].map { $0.satisfied != crossing.satisfied } ?? false
        if isNews, UIApplication.shared.applicationState == .background {
            noteWokeForCrossing()
        }
        try? await Task.sleep(for: Self.regionGrace)
        // A circle added moments ago has no baseline yet; this is not a crossing.
        guard !automation.state.awaitingBaseline.contains(crossing.identifier) else { return }
        var delivers = false
        updateLedger {
            delivers = crossing.isStateRead
                ? $0.regionStateRead(crossing.identifier, satisfied: crossing.satisfied)
                : $0.regionReports(crossing.identifier, satisfied: crossing.satisfied)
        }
        if delivers { regionRecordedThisProcess = true }
        guard delivers, var event = WorkplaceMonitorPlan.event(
            identifier: crossing.identifier, state: crossing.satisfied ? .satisfied : .unsatisfied,
            observedAt: nil, receivedAt: crossing.receivedAt, isInitialState: false
        ) else { return }
        event.observedAt = crossing.receivedAt
        event.timestampBasis = .regionCallback
        let now = Date.now
        let outcome = await automation.receive(event, shifts: dependencies.shifts(now), now: now)
        refreshStatus(registered: status.registeredCount)
        await dependencies.didHandle(event, outcome)
    }

    private static let ledgerKey = "owc.workplaceMonitor.crossingLedger"

    private static func loadLedger() -> WorkplaceCrossingLedger {
        guard let data = UserDefaults.standard.data(forKey: ledgerKey),
              let ledger = try? JSONDecoder().decode(WorkplaceCrossingLedger.self, from: data)
        else { return WorkplaceCrossingLedger() }
        return ledger
    }

    private func updateLedger(_ change: (inout WorkplaceCrossingLedger) -> Void) {
        let before = ledger
        change(&ledger)
        guard ledger != before, let data = try? JSONEncoder().encode(ledger) else { return }
        UserDefaults.standard.set(data, forKey: Self.ledgerKey)
    }

    private func handle(_ diagnostic: CLServiceSession.Diagnostic) {
        noteHold(diagnostic.insufficientlyInUse)
        let next = WorkplaceMonitorStatus.problems(
            authorizationDenied: diagnostic.authorizationDenied,
            deniedGlobally: diagnostic.authorizationDeniedGlobally,
            restricted: diagnostic.authorizationRestricted,
            alwaysDenied: diagnostic.alwaysAuthorizationDenied,
            accuracyLimited: diagnostic.fullAccuracyDenied,
            conditionLimitExceeded: false,
            conditionUnsupported: false,
            persistenceUnavailable: false
        )
        // The stream repeats itself; only a change is worth a redraw.
        guard next != sessionProblems else { return }
        sessionProblems = next
        refreshStatus(registered: status.registeredCount)
    }

    private func noteWokeForCrossing() {
        guard !wokeForCrossing else { return }
        wokeForCrossing = true
        // The session may already have said events are held.
        if lastDiagnosticHeld == true { noteHeldWake() }
    }

    /// Tracks iOS holding events back. A crossing wake that is not let in
    /// marks a held wake; the first time events are let in again, in this
    /// process or a later foreground one, opens the release window.
    private func noteHold(_ held: Bool) {
        let previous = lastDiagnosticHeld
        lastDiagnosticHeld = held
        if held {
            if wokeForCrossing { noteHeldWake() }
            return
        }
        let now = Date.now
        guard previous != false, !automation.state.heldWakes.isEmpty else { return }
        releasedAt = now
        Task {
            await dependencies.didReleaseHold()
            try? await Task.sleep(for: .seconds(WorkplaceAutomation.heldReleaseWindow))
            // Whatever the release did not use was no crossing we can place.
            guard releasedAt == now else { return }
            releasedAt = nil
            automation.update { $0.clearHeldWakes() }
        }
    }

    /// Woken for a crossing while `CLMonitor` is held back. The wake time
    /// stands in for its held report; the person is asked to open the app
    /// only if the region API could not record the crossing itself.
    private func noteHeldWake() {
        guard !heldNotedThisProcess, UIApplication.shared.applicationState == .background else { return }
        heldNotedThisProcess = true
        let now = Date.now
        Task {
            try? await Task.sleep(for: Self.regionGrace + .seconds(1))
            guard !regionRecordedThisProcess else { return }
            var starts = false
            automation.update { starts = $0.noteHeldWake(at: now) }
            if starts { await dependencies.didHoldCrossing() }
        }
    }

    private func refreshStatus(registered: Int) {
        let state = automation.state
        let wanted = WorkplaceMonitorPlan.wantedConditions(state: state, canCollect: dependencies.canCollect())
        status = WorkplaceMonitorStatus(
            configuredCount: state.settings.isMonitoringEnabled ? state.workplaces.filter(\.isEnabled).count : 0,
            registeredCount: min(registered, wanted.count),
            wantedCount: wanted.count,
            lastEventAt: state.lastNativeEventAt,
            problems: sessionProblems.union(monitorProblems)
        )
    }
}

nonisolated extension WorkplaceAutomationState {
    /// When this device last received a workplace crossing from the system.
    var lastNativeEventAt: Date? {
        events.filter { $0.source == .nativeGeofence }.map(\.receivedAt).max()
    }
}
