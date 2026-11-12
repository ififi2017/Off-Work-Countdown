import Foundation

// Plan 021 §I2: the pure half of native workplace monitoring. Which circles
// the system should hold, how to bring its registrations in line without
// re-adding ones it keeps across launches, and how a system condition change
// becomes an automation event. `WorkplaceMonitor` only carries these out.

nonisolated enum WorkplaceRing: String, Sendable {
    /// Crossing in is an arrival.
    case inner = "i"
    /// Crossing out is a departure. It is larger, so walking along the
    /// edge is not counted as coming and going.
    case outer = "o"
}

/// One circle the system should watch.
nonisolated struct WorkplaceMonitorCondition: Equatable, Hashable, Sendable {
    var identifier: String
    var workplaceID: UUID
    var generation: Int
    var ring: WorkplaceRing
    var latitude: Double
    var longitude: Double
    var radius: Double
}

/// A condition state as the system reports it, without CoreLocation types.
nonisolated enum WorkplaceConditionState: Equatable, Sendable {
    case satisfied
    case unsatisfied
    /// Not known yet, or no longer monitored. Never a departure (§I2).
    case unknown
}

nonisolated enum WorkplaceMonitorPlan {
    /// The `CLMonitor` name; alphanumeric only, as the system requires.
    static let monitorName = "DoneAtWorkplaces"

    /// `W<uuid hex>G<generation><ring>`: alphanumeric, and it carries the
    /// generation, so an event for an edited region can never match the
    /// new one even if the system delivers it late.
    static func identifier(workplaceID: UUID, generation: Int, ring: WorkplaceRing) -> String {
        let hex = workplaceID.uuidString.replacingOccurrences(of: "-", with: "")
        return "W\(hex)G\(generation)\(ring.rawValue)"
    }

    static func parse(_ identifier: String) -> (workplaceID: UUID, generation: Int, ring: WorkplaceRing)? {
        let characters = Array(identifier)
        // "W" + 32 hex + "G" + at least one digit + ring.
        guard characters.count >= 36, characters[0] == "W", characters[33] == "G",
              let ring = WorkplaceRing(rawValue: String(characters[characters.count - 1]))
        else { return nil }
        let hex = characters[1...32]
        let digits = String(characters[34..<(characters.count - 1)])
        guard hex.allSatisfy(\.isHexDigit), !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let generation = Int(digits)
        else { return nil }
        let h = Array(hex)
        let dashed = String(h[0..<8]) + "-" + String(h[8..<12]) + "-" + String(h[12..<16]) + "-"
            + String(h[16..<20]) + "-" + String(h[20..<32])
        guard let id = UUID(uuidString: dashed) else { return nil }
        return (id, generation, ring)
    }

    /// The same circle registered with the region-monitoring API: `L` plus
    /// the condition identifier, so neither API's set touches the other's.
    static func regionIdentifier(for identifier: String) -> String { "L" + identifier }

    /// The condition identifier a region stands for, if it is one of ours.
    static func conditionIdentifier(forRegion identifier: String) -> String? {
        guard identifier.hasPrefix("L") else { return nil }
        let core = String(identifier.dropFirst())
        return parse(core) == nil ? nil : core
    }

    /// Whether anything should be watched at all. Off means no session and
    /// no circles: nothing keeps location access busy for nothing.
    static func isActive(state: WorkplaceAutomationState, canCollect: Bool) -> Bool {
        canCollect && state.settings.isMonitoringEnabled && state.workplaces.contains(where: \.isEnabled)
    }

    /// Two circles per enabled workplace; a paused one is not watched.
    static func wantedConditions(state: WorkplaceAutomationState, canCollect: Bool) -> [WorkplaceMonitorCondition] {
        guard isActive(state: state, canCollect: canCollect) else { return [] }
        return state.workplaces.filter(\.isEnabled).flatMap { place in
            [WorkplaceRing.inner, .outer].map { ring in
                WorkplaceMonitorCondition(
                    identifier: identifier(workplaceID: place.id, generation: place.registrationGeneration, ring: ring),
                    workplaceID: place.id,
                    generation: place.registrationGeneration,
                    ring: ring,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    radius: ring == .inner ? place.innerRadius : place.outerRadius
                )
            }
        }
    }

    /// What to remove and add so the system holds exactly `wanted`. Kept
    /// circles are not re-added: the system's state for them survives.
    static func reconcile(
        registered: Set<String>,
        wanted: [WorkplaceMonitorCondition]
    ) -> (remove: [String], add: [WorkplaceMonitorCondition]) {
        let wantedIDs = Set(wanted.map(\.identifier))
        return (
            registered.subtracting(wantedIDs).sorted(),
            wanted.filter { !registered.contains($0.identifier) }
        )
    }

    /// The automation event a condition change means, if any. Only the
    /// inner circle filling and the outer circle emptying are business
    /// events; the other two edges and every unknown state are not.
    static func event(
        identifier: String,
        state: WorkplaceConditionState,
        observedAt: Date?,
        receivedAt: Date,
        isInitialState: Bool
    ) -> AutomationEvent? {
        guard let parsed = parse(identifier) else { return nil }
        let type: AutomationEventType
        switch (parsed.ring, state) {
        case (.inner, .satisfied): type = .enterInner
        case (.outer, .unsatisfied): type = .exitOuter
        default: return nil
        }
        // A date the system cannot have observed yet is not an observation.
        let observed = observedAt.flatMap { $0 <= receivedAt.addingTimeInterval(60) ? $0 : nil }
        return AutomationEvent(
            id: UUID(),
            source: .nativeGeofence,
            type: type,
            workplaceID: parsed.workplaceID,
            registrationGeneration: parsed.generation,
            observedAt: observed,
            receivedAt: receivedAt,
            timestampBasis: observed == nil ? .callbackReceipt : .systemObservation,
            isInitialState: isInitialState
        )
    }
}

/// What the settings page may honestly say about monitoring (§I2): four
/// separate facts, never one switch read as "working".
nonisolated struct WorkplaceMonitorStatus: Equatable, Sendable {
    enum Problem: Equatable, Sendable {
        case needsAlways
        case needsPreciseLocation
        case locationOff
        case tooManyRegions
        case unsupported
        case storageUnavailable
    }

    /// The workplaces saved and switched on.
    var configuredCount = 0
    /// Of the circles wanted, how many the system holds.
    var registeredCount = 0
    var wantedCount = 0
    var lastEventAt: Date?
    var problems: Set<Problem> = []

    var isRegistered: Bool { wantedCount > 0 && registeredCount == wantedCount }

    /// Problems the system reported, from the flags shared by monitor
    /// events and service-session diagnostics.
    static func problems(
        authorizationDenied: Bool,
        deniedGlobally: Bool,
        restricted: Bool,
        alwaysDenied: Bool,
        accuracyLimited: Bool,
        conditionLimitExceeded: Bool,
        conditionUnsupported: Bool,
        persistenceUnavailable: Bool
    ) -> Set<Problem> {
        var result: Set<Problem> = []
        if deniedGlobally { result.insert(.locationOff) }
        if authorizationDenied || restricted || alwaysDenied { result.insert(.needsAlways) }
        if accuracyLimited { result.insert(.needsPreciseLocation) }
        if conditionLimitExceeded { result.insert(.tooManyRegions) }
        if conditionUnsupported { result.insert(.unsupported) }
        if persistenceUnavailable { result.insert(.storageUnavailable) }
        return result
    }
}

/// Plan 021 §I2: each circle is watched by `CLMonitor` and by the region API.
/// Both usually report the same crossing within milliseconds; while the app
/// is swiped away, `CLMonitor` may hold its report until the app is opened.
/// The ledger lets the first report of each edge through, preferring
/// `CLMonitor` (it carries the observation time), and drops the other.
nonisolated struct WorkplaceCrossingLedger: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case monitor, region }
    struct Edge: Codable, Equatable, Sendable {
        var satisfied: Bool
        var source: Source
    }

    private(set) var edges: [String: Edge] = [:]

    /// A `CLMonitor` report. Dropped only when the region API already
    /// delivered this same edge; its own repeats pass as before.
    mutating func monitorReports(_ identifier: String, state: WorkplaceConditionState, isInitialState: Bool) -> Bool {
        guard state != .unknown else { return true }
        let satisfied = state == .satisfied
        let previous = edges[identifier]
        edges[identifier] = Edge(satisfied: satisfied, source: .monitor)
        return isInitialState || !(previous?.source == .region && previous?.satisfied == satisfied)
    }

    /// A region API report, checked after `CLMonitor` had a moment to report
    /// the same crossing. Dropped when the circle is already in this state.
    mutating func regionReports(_ identifier: String, satisfied: Bool) -> Bool {
        guard edges[identifier]?.satisfied != satisfied else { return false }
        edges[identifier] = Edge(satisfied: satisfied, source: .region)
        return true
    }

    mutating func keep(only identifiers: Set<String>) {
        edges = edges.filter { identifiers.contains($0.key) }
    }
}
