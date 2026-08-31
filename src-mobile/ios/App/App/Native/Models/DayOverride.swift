import Foundation

/// How a single day leaves the schedule default. Matches 002 §4.
///
/// Timer marks only ever produce `customSegments` or no override. Confirm,
/// leave, and clear are records-tab actions and are not invented here.
enum DayOverrideKind: String, Codable, Sendable {
    /// User checked the day and it matches the schedule.
    case confirmedAsScheduled
    /// The day ran on these segments instead of the schedule default.
    case customSegments
    /// Leave / a personal rest day. Not an early clock-off.
    case notWorking
    /// Cleared back to calendar exception or schedule. The row stays.
    case cleared
}

/// One day's user-facing conclusion. Value type only — SwiftData lands later.
///
/// `dayKey` is the shift start day (`YYYY-MM-DD`). Overnight Friday 22:00 to
/// Saturday 06:00 still keys as Friday, even if the clock-off is Saturday.
/// Persist stamps travel with the row from day one so P0B does not rewrite
/// the identity. Timer projection leaves them unset.
struct DayOverride: Equatable, Sendable {
    static let schemaVersion = 1
    static let unsetTieBreaker = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var dayKey: String
    var shiftAnchorDate: Date
    var kind: DayOverrideKind
    var segments: [NativeShiftSegment]
    var note: String? = nil
    var editedAt: Date = .distantPast
    var editCount: Int = 0
    var editTieBreaker: UUID = DayOverride.unsetTieBreaker
    /// Civil day this row was recorded in. Travel does not rewrite it.
    var timeZoneIdentifier: String = TimeZone.current.identifier
}
