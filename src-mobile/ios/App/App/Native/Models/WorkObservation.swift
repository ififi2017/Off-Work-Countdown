import Foundation

/// Application observations that annotate a day. They never enter the
/// three-layer conclusion chain. Matches 002 §3.
enum WorkObservationKind: String, Codable, Sendable {
    case timerSurfaceFirstSeen
    case countdownStarted
    case countdownStopped
    case overtimeDeclared
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

    var id: UUID { eventID }
}
