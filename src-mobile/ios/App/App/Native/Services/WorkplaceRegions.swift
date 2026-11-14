import CoreLocation

/// Plan 021 §I2: the workplace circles, registered with the region-monitoring
/// API as well as `CLMonitor`.
///
/// Device test 2026-11-12 (probe build 5): with these regions registered, a
/// swiped-away app was woken for a departure and `CLMonitor` let its event
/// through live; without them (2026-11-10) it held the event until the app
/// was opened. Their own callbacks stand in only when `CLMonitor`'s report
/// does not arrive; `WorkplaceCrossingLedger` keeps one report per crossing.
///
/// Created and given its delegate before launch returns, so the crossing a
/// background launch was made for has somewhere to go; callbacks that come
/// before the monitor attaches wait here.
@MainActor
final class WorkplaceRegions: NSObject {
    static let shared = WorkplaceRegions()

    /// A crossing, or (`isStateRead`) the current state iOS reports when asked.
    typealias Crossing = (identifier: String, satisfied: Bool, receivedAt: Date, isStateRead: Bool)

    private let manager = CLLocationManager()
    private var waiting: [Crossing] = []

    /// Set by the monitor; receives every crossing, earlier ones first.
    var onCrossing: ((Crossing) -> Void)? {
        didSet {
            guard let onCrossing else { return }
            let earlier = waiting
            waiting = []
            earlier.forEach(onCrossing)
        }
    }

    func attach() {
        if manager.delegate == nil { manager.delegate = self }
    }

    /// Ours among what the system holds, keyed by condition identifier.
    private var registered: [String: CLRegion] {
        Dictionary(
            manager.monitoredRegions.compactMap { region in
                WorkplaceMonitorPlan.conditionIdentifier(forRegion: region.identifier).map { ($0, region) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Makes the system hold exactly `wanted`, keeping regions it already has.
    func reconcile(wanted: [WorkplaceMonitorCondition]) {
        attach()
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let held = registered
        let plan = WorkplaceMonitorPlan.reconcile(registered: Set(held.keys), wanted: wanted)
        for identifier in plan.remove {
            if let region = held[identifier] { manager.stopMonitoring(for: region) }
        }
        for condition in plan.add {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: condition.latitude, longitude: condition.longitude),
                radius: min(condition.radius, manager.maximumRegionMonitoringDistance),
                identifier: WorkplaceMonitorPlan.regionIdentifier(for: condition.identifier)
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    /// Asks iOS where the person is for each of our regions. The answers
    /// arrive as state reads; one that disagrees with the last known edge is
    /// a crossing nothing has reported yet.
    func requestStates() {
        for region in registered.values { manager.requestState(for: region) }
    }

    func stopAll() {
        for region in registered.values { manager.stopMonitoring(for: region) }
    }

    fileprivate func report(_ regionIdentifier: String, satisfied: Bool, isStateRead: Bool = false) {
        guard let identifier = WorkplaceMonitorPlan.conditionIdentifier(forRegion: regionIdentifier) else { return }
        let crossing = (identifier: identifier, satisfied: satisfied, receivedAt: Date.now, isStateRead: isStateRead)
        if let onCrossing { onCrossing(crossing) } else { waiting.append(crossing) }
    }
}

extension WorkplaceRegions: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        MainActor.assumeIsolated { report(identifier, satisfied: true) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let identifier = region.identifier
        MainActor.assumeIsolated { report(identifier, satisfied: false) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard state != .unknown else { return }
        let identifier = region.identifier
        let satisfied = state == .inside
        MainActor.assumeIsolated { report(identifier, satisfied: satisfied, isStateRead: true) }
    }
}
