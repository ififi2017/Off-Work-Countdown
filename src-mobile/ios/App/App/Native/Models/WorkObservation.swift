import Foundation

/// Application observations that annotate a day. They never enter the
/// three-layer conclusion chain. Matches 002 §3.
enum WorkObservationKind: String, Codable, Sendable {
    case timerSurfaceFirstSeen
    case countdownStarted
    case countdownStopped
    case overtimeDeclared

    /// Opening the timer is not clocking in. The free records list only
    /// shows days that have one of these.
    var isWorkSessionRecord: Bool {
        self != .timerSurfaceFirstSeen
    }
}

/// One civil day that actually started, stopped, or logged overtime.
struct RecordedWorkDay: Equatable, Sendable, Identifiable {
    var dayKey: String
    var shiftAnchorDate: Date
    var observations: [WorkObservation]

    var id: String { dayKey }

    var firstStart: Date? {
        observations.first { $0.kind == .countdownStarted }?.occurredAt
    }

    var lastStop: Date? {
        observations.last { $0.kind == .countdownStopped }?.occurredAt
    }
}

/// An immutable use event. Writes never edit; a retry reuses `eventID`.
struct WorkObservation: Equatable, Sendable, Identifiable {
    static let schemaVersion = 1

    var eventID: UUID
    var shiftAnchorDate: Date
    var occurredAt: Date
    var kind: WorkObservationKind
    var valueData: Data?
    var scheduleSnapshotID: UUID
    var schemaVersion: Int = WorkObservation.schemaVersion
    /// Civil day this row was recorded in. Travel does not rewrite it.
    var timeZoneIdentifier: String = TimeZone.current.identifier

    var id: UUID { eventID }
}
