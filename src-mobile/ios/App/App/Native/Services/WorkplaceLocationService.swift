import CoreLocation
import Observation

/// Plan 021 U1: location permission and a one-off position for saving a
/// workplace. Region monitoring itself belongs to the geofence service (I2);
/// this never tracks the person.
@MainActor
@Observable
final class WorkplaceLocationService: NSObject, CLLocationManagerDelegate {
    private(set) var access: WorkplaceLocationAccess = .notRequested
    @ObservationIgnored private let manager = CLLocationManager()
    /// Set by the settings button: once "while using" is granted, iOS shows
    /// the "Always" upgrade prompt only if asked again.
    @ObservationIgnored private var wantsAlways = false

    override init() {
        super.init()
        manager.delegate = self
        refresh()
    }

    static func access(
        status: CLAuthorizationStatus,
        accuracy: CLAccuracyAuthorization
    ) -> WorkplaceLocationAccess {
        switch status {
        case .notDetermined: .notRequested
        case .denied, .restricted: .denied
        case .authorizedWhenInUse: .whenInUseOnly
        case .authorizedAlways: accuracy == .fullAccuracy ? .always : .reducedAccuracy
        @unknown default: .denied
        }
    }

    /// Asks for "while using" first, then for "Always", as iOS requires.
    func requestAccess() {
        wantsAlways = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// One position good enough to save a workplace: within 100 m, 30 s at most.
    func currentLocation() async -> CLLocationCoordinate2D? {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
                        if let location = update.location,
                           location.horizontalAccuracy >= 0,
                           location.horizontalAccuracy <= 100 {
                            return location.coordinate
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

    func refresh() {
        access = Self.access(status: manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refresh()
            if wantsAlways, self.manager.authorizationStatus == .authorizedWhenInUse {
                wantsAlways = false
                self.manager.requestAlwaysAuthorization()
            }
        }
    }
}
