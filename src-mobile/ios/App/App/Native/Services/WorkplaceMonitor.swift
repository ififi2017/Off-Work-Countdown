import CoreLocation
import Observation

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

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        refreshStatus(registered: 0)
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
            defaults.set(false, forKey: Self.mayHoldConditionsKey)
        }
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
        guard let automationEvent = WorkplaceMonitorPlan.event(
            identifier: event.identifier, state: state, observedAt: event.date,
            receivedAt: now, isInitialState: isInitial
        ) else {
            refreshStatus(registered: status.registeredCount)
            return
        }
        let outcome = await automation.receive(automationEvent, shifts: dependencies.shifts(now), now: now)
        refreshStatus(registered: status.registeredCount)
        await dependencies.didHandle(automationEvent, outcome)
    }

    private func handle(_ diagnostic: CLServiceSession.Diagnostic) {
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
