#if DEBUG || WORKPLACE_PROBE
import CoreLocation
import UIKit

/// Plan 021 P0: a DEBUG-only geofence probe for real-device checks.
///
/// It registers inner and outer circles with `CLMonitor`, holds an
/// always-authorization `CLServiceSession`, resumes both at every launch
/// (including a background launch the system makes for a crossing) and logs
/// what arrives. It never touches records, shifts or notifications.
@MainActor
@Observable
final class WorkplaceProbe {
    static let shared = WorkplaceProbe()
    /// Alphanumeric only, as `CLMonitor` requires.
    static let monitorName = "DoneAtWorkplaceProbe"

    private(set) var archive: WorkplaceProbeArchive
    private(set) var isLocating = false
    private(set) var authorizationLabel = "unknown"
    private(set) var accuracyLabel = "unknown"

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var session: CLServiceSession?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var lastSessionFlags: [String]?
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?

    init(url: URL = WorkplaceProbeStorage.defaultURL) {
        self.url = url
        archive = WorkplaceProbeStorage.load(from: url)
        refreshAuthorization()
    }

    // MARK: Lifecycle

    /// Called from `didFinishLaunching`, before it returns, so a launch the
    /// system makes for a crossing delivers its event to a live monitor.
    /// The launch entry's app state tells a background launch from a tap.
    func resumeAfterLaunch() {
        guard archive.isEnabled else { return }
        log(.launch)
        observeForeground()
        startSession()
        Task { await reconcileMonitor() }
    }

    func enable() async {
        archive.isEnabled = true
        log(.note, detail: "probe enabled")
        observeForeground()
        startSession()
        await reconcileMonitor()
    }

    func disable() async {
        if let monitor {
            for place in archive.places {
                await monitor.remove(place.innerIdentifier)
                await monitor.remove(place.outerIdentifier)
            }
        }
        eventTask?.cancel()
        sessionTask?.cancel()
        session?.invalidate()
        eventTask = nil
        sessionTask = nil
        session = nil
        monitor = nil
        archive.isEnabled = false
        log(.note, detail: "probe disabled")
    }

    // MARK: Places

    /// Saves the current position as a place with a 200 m inner circle
    /// (or `innerRadius`) and an outer circle 100 m larger.
    func addCurrentLocation(innerRadius: Double) async {
        guard archive.places.count < WorkplaceProbeArchive.maximumPlaces else {
            log(.note, detail: "place limit reached")
            return
        }
        isLocating = true
        defer { isLocating = false }
        guard let location = await currentLocation() else {
            log(.error, detail: "no location within 30 s")
            return
        }
        let real = archive.places.filter { !$0.isFiller }.count
        let place = WorkplaceProbePlace(
            id: UUID(),
            name: "Place \(real + 1)",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            innerRadius: innerRadius,
            outerRadius: innerRadius + WorkplaceAutomation.defaultOuterRadiusMargin,
            isFiller: false
        )
        archive.places.append(place)
        log(.note, detail: String(format: "added %@ accuracy=%.0fm", place.name, location.horizontalAccuracy))
        await register(place)
    }

    /// Adds synthetic places 1–4 km away until five places hold ten conditions.
    func fillToFivePlaces() async {
        guard let anchor = archive.places.first(where: { !$0.isFiller }) else {
            log(.note, detail: "add a real place first")
            return
        }
        let fillers = WorkplaceProbeArchive.fillers(
            around: (anchor.latitude, anchor.longitude),
            existing: archive.places.count,
            radius: anchor.innerRadius
        )
        archive.places.append(contentsOf: fillers)
        log(.note, detail: "added \(fillers.count) filler places; conditions=\(archive.conditionCount)")
        for filler in fillers { await register(filler) }
    }

    func removeAllPlaces() async {
        if let monitor {
            for place in archive.places {
                await monitor.remove(place.innerIdentifier)
                await monitor.remove(place.outerIdentifier)
            }
        }
        archive.places.removeAll()
        log(.note, detail: "removed all places")
    }

    func clearLog() {
        archive.entries.removeAll()
        save()
    }

    /// A plain-text export for sharing; it holds place names and radii, never coordinates.
    func exportFile() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "doneat-workplace-probe.tsv")
        try Data(archive.exportText().utf8).write(to: file, options: .atomic)
        return file
    }

    // MARK: Monitoring

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
            } catch {
                self?.log(.error, detail: "session: \(error)")
            }
        }
    }

    private func ensureMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let monitor = await CLMonitor(Self.monitorName)
        self.monitor = monitor
        eventTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    self?.handle(event)
                }
            } catch {
                self?.log(.error, detail: "monitor: \(error)")
            }
        }
        return monitor
    }

    /// Makes the system's conditions match the saved places without
    /// re-adding ones it already holds, so a relaunch keeps their state.
    private func reconcileMonitor() async {
        let monitor = await ensureMonitor()
        let registered = Set(await monitor.identifiers)
        let wanted = Set(archive.places.flatMap { [$0.innerIdentifier, $0.outerIdentifier] })
        for stale in registered.subtracting(wanted) { await monitor.remove(stale) }
        for place in archive.places where !registered.contains(place.innerIdentifier)
            || !registered.contains(place.outerIdentifier) {
            await register(place)
        }
        log(.note, detail: "monitor ready: \(registered.intersection(wanted).count) kept, \(wanted.count) wanted")
    }

    private func register(_ place: WorkplaceProbePlace) async {
        guard archive.isEnabled else { save(); return }
        let monitor = await ensureMonitor()
        let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        await monitor.add(
            CLMonitor.CircularGeographicCondition(center: center, radius: place.innerRadius),
            identifier: place.innerIdentifier
        )
        await monitor.add(
            CLMonitor.CircularGeographicCondition(center: center, radius: place.outerRadius),
            identifier: place.outerIdentifier
        )
        save()
    }

    private func handle(_ event: CLMonitor.Event) {
        var flags: [String] = []
        if event.accuracyLimited { flags.append("accuracyLimited") }
        if event.authorizationDenied { flags.append("authorizationDenied") }
        if event.authorizationDeniedGlobally { flags.append("authorizationDeniedGlobally") }
        if event.authorizationRequestInProgress { flags.append("authorizationRequestInProgress") }
        if event.authorizationRestricted { flags.append("authorizationRestricted") }
        if event.conditionLimitExceeded { flags.append("conditionLimitExceeded") }
        if event.conditionUnsupported { flags.append("conditionUnsupported") }
        if event.insufficientlyInUse { flags.append("insufficientlyInUse") }
        if event.persistenceUnavailable { flags.append("persistenceUnavailable") }
        if event.serviceSessionRequired { flags.append("serviceSessionRequired") }
        log(
            .event,
            identifier: event.identifier,
            state: Self.label(event.state),
            observedAt: event.date,
            flags: flags
        )
    }

    private func handle(_ diagnostic: CLServiceSession.Diagnostic) {
        var flags: [String] = []
        if diagnostic.alwaysAuthorizationDenied { flags.append("alwaysAuthorizationDenied") }
        if diagnostic.authorizationDenied { flags.append("authorizationDenied") }
        if diagnostic.authorizationDeniedGlobally { flags.append("authorizationDeniedGlobally") }
        if diagnostic.authorizationRequestInProgress { flags.append("authorizationRequestInProgress") }
        if diagnostic.authorizationRestricted { flags.append("authorizationRestricted") }
        if diagnostic.fullAccuracyDenied { flags.append("fullAccuracyDenied") }
        if diagnostic.insufficientlyInUse { flags.append("insufficientlyInUse") }
        if diagnostic.serviceSessionRequired { flags.append("serviceSessionRequired") }
        // The stream repeats itself; only changes are worth a line.
        guard flags != lastSessionFlags else { return }
        lastSessionFlags = flags
        log(.sessionDiagnostic, flags: flags.isEmpty ? ["ok"] : flags)
    }

    /// One location good enough to save a place: ≤ 100 m accuracy, 30 s at most.
    private func currentLocation() async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location,
                           location.horizontalAccuracy >= 0,
                           location.horizontalAccuracy <= 100 {
                            return location
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: Logging

    private func observeForeground() {
        guard foregroundObserver == nil else { return }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.log(.note, detail: "became active") }
        }
    }

    private func log(
        _ kind: WorkplaceProbeEntry.Kind,
        identifier: String? = nil,
        state: String? = nil,
        observedAt: Date? = nil,
        flags: [String] = [],
        detail: String? = nil
    ) {
        refreshAuthorization()
        let application = UIApplication.shared
        archive.append(WorkplaceProbeEntry(
            receivedAt: .now,
            kind: kind,
            identifier: identifier,
            state: state,
            observedAt: observedAt,
            appState: Self.label(application.applicationState),
            protectedDataAvailable: application.isProtectedDataAvailable,
            authorization: authorizationLabel,
            accuracy: accuracyLabel,
            flags: flags,
            detail: detail
        ))
        save()
    }

    private func save() {
        do {
            try WorkplaceProbeStorage.save(archive, to: url)
        } catch {
            // Locked before first unlock: keep the entry in memory and retry
            // on the next one rather than losing the run.
        }
    }

    private func refreshAuthorization() {
        authorizationLabel = switch manager.authorizationStatus {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "whenInUse"
        @unknown default: "other"
        }
        accuracyLabel = switch manager.accuracyAuthorization {
        case .fullAccuracy: "full"
        case .reducedAccuracy: "reduced"
        @unknown default: "other"
        }
    }

    private static func label(_ state: CLMonitor.Event.State) -> String {
        switch state {
        case .unknown: "unknown"
        case .satisfied: "satisfied"
        case .unsatisfied: "unsatisfied"
        case .unmonitored: "unmonitored"
        @unknown default: "other"
        }
    }

    private static func label(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "other"
        }
    }
}
#endif
