import Foundation

/// Hours that can replay the shared rules. Salary, overtime and "now" stay
/// off this payload so a snapshot can cross CloudKit and JSON later.
nonisolated struct ScheduleHoursConfiguration: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var startTime: String
    var endTime: String
    var workdays: [Int]
    var schedule: NativeWorkSchedule
    var breakStartTime: String?
    var breakDurationMinutes: Int
    /// Plan 018 P8: these hours follow the extended schedule. Only the marker
    /// is stored — the roster keeps changing day by day, and a copy frozen
    /// into a snapshot would go stale the moment one day was edited. `nil`
    /// when unused, so hours saved without it encode and fingerprint as before.
    var usesExtendedSchedule: Bool? = nil
    /// The live plan, attached at read time (`RecordCoordinator.expandableHours`)
    /// or by whoever builds the hours. Never encoded.
    var extendedSchedule: ExtendedSchedulePlan? = nil

    private enum CodingKeys: String, CodingKey {
        case startTime, endTime, workdays, schedule, breakStartTime, breakDurationMinutes, usesExtendedSchedule
    }
}

/// A stretch of working life. Overlaps are allowed; the winner is chosen
/// at read time. Value type only — SwiftData lands later.
nonisolated struct CareerPeriod: Codable, Equatable, Sendable, Identifiable {
    static let schemaVersion = 1

    var id: UUID
    var startsOn: Date
    var endsBefore: Date?
    var label: String?
    var timeZoneIdentifier: String
    var calendarIdentifier: String
    var createdAt: Date
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    func civilCalendar() -> Calendar {
        var calendar = Calendar(identifier: calendarIdentifier == "iso8601" ? .iso8601 : .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    func covers(_ day: Date) -> Bool {
        if day < startsOn { return false }
        if let endsBefore, day >= endsBefore { return false }
        return true
    }
}

/// One revision of hours inside a career period. Salary is not stored here.
nonisolated struct ScheduleSnapshot: Codable, Equatable, Sendable, Identifiable {
    static let schemaVersion = 1

    var id: UUID
    var periodID: UUID
    var effectiveFrom: Date
    var configurationData: Data
    /// Identifies the same hours; never a substitute for `configurationData`.
    var fingerprint: String
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID
}
