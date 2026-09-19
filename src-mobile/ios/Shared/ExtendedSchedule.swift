import Foundation

/// A named kind of shift the extended schedule assigns to days (plan 018 P8).
/// `rest` is a type as well: the day is assigned, but nothing counts down to it.
nonisolated struct ShiftType: Codable, Hashable, Sendable, Identifiable {
    nonisolated enum Kind: String, Codable, Sendable {
        case work
        case rest
    }

    static let maximumNameLength = 40

    var id: UUID
    var name: String
    var kind: Kind
    /// Civil minutes after midnight. An end at or before the start crosses
    /// midnight into the next day.
    var startMinutes: Int
    var endMinutes: Int
    /// The in-shift break. The extended schedule never calls it lunch.
    var breakEnabled: Bool
    var breakStartMinutes: Int
    var breakDurationMinutes: Int
    /// `#RRGGBB`, generated when the type is created; the user may change it.
    var colorHex: String
    /// Archived types stay so past days that used them still resolve.
    var isArchived: Bool

    var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.count <= Self.maximumNameLength
            && (0..<1_440).contains(startMinutes)
            && (0..<1_440).contains(endMinutes)
            && (0..<1_440).contains(breakStartMinutes)
            && (0..<1_440).contains(breakDurationMinutes)
            && (!breakEnabled || breakDurationMinutes > 0)
            && colorHex.wholeMatch(of: /#[0-9A-Fa-f]{6}/) != nil
    }
}

/// A repeating pattern that fills the calendar: one shift type per day of the
/// cycle, counted from `anchorDayKey`. Single and double weekends are a 14-day
/// cycle and a rotation is N + M days, so both are the same data; `preset` only
/// remembers which editor produced it.
nonisolated struct ShiftCycleRule: Codable, Hashable, Sendable {
    nonisolated enum Preset: String, Codable, Sendable {
        /// Seven days from a Monday, labelled by weekday.
        case weekly
        case alternatingWeeks
        case rotation
        case custom

        /// Only a hint for the editor, so a preset a newer build added reads as
        /// custom instead of rejecting the whole schedule.
        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Preset(rawValue: raw) ?? .custom
        }
    }

    static let maximumLength = 366

    var preset: Preset
    /// Civil date, `YYYY-MM-DD`, in the schedule's zone.
    var anchorDayKey: String
    var days: [UUID]
}

/// Plan 018 P8's extended schedule: the shift types and the optional cycle
/// rule. Days the user sets by hand are separate `RosterDay` rows, so two
/// devices editing different days never conflict. A month with neither a rule
/// nor hand-set days copies the previous month by day number; that is a
/// resolution rule, not stored data.
nonisolated struct ExtendedSchedule: Equatable, Sendable {
    static let schemaVersion = 1
    static let logicalKey = "extended-schedule"

    var isEnabled: Bool
    var shiftTypes: [ShiftType]
    var rule: ShiftCycleRule?
    /// Nil predates templates; an empty identifier explicitly disables them.
    var holidayRegionIdentifier: String? = nil
    /// The zone whose civil dates the rule anchor and roster day keys name.
    var timeZoneIdentifier: String
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID

    var content: ExtendedScheduleContent {
        get { ExtendedScheduleContent(shiftTypes: shiftTypes, rule: rule, holidayRegionIdentifier: holidayRegionIdentifier) }
        set {
            shiftTypes = newValue.shiftTypes
            rule = newValue.rule
            holidayRegionIdentifier = newValue.holidayRegionIdentifier
        }
    }

    var isValid: Bool {
        guard let zone = TimeZone(identifier: timeZoneIdentifier), editCount >= 0 else { return false }
        return content.isValid(in: zone)
    }
}

/// What a schedule edit changes and what a Records snapshot keeps: the shift
/// types and the rule. Hand-set days are left out on purpose — each is a fact
/// about one day, so they stay live instead of being copied into every
/// snapshot.
nonisolated struct ExtendedScheduleContent: Codable, Hashable, Sendable {
    var shiftTypes: [ShiftType]
    var rule: ShiftCycleRule?
    var holidayRegionIdentifier: String? = nil

    func isValid(in zone: TimeZone) -> Bool {
        guard HolidayCalendar.isValidRegionIdentifier(holidayRegionIdentifier),
              shiftTypes.allSatisfy(\.isValid),
              Set(shiftTypes.map(\.id)).count == shiftTypes.count
        else { return false }
        guard let rule else { return true }
        let known = Set(shiftTypes.map(\.id))
        return !rule.days.isEmpty
            && rule.days.count <= ShiftCycleRule.maximumLength
            && rule.days.allSatisfy { known.contains($0) }
            && ExtendedScheduleResolver.parse(dayKey: rule.anchorDayKey) != nil
    }
}

/// One day the user assigned by hand. It wins over the cycle rule and over
/// copying the previous month; erasing the row puts the day back on the rule.
///
/// The shift type is not checked against `ExtendedSchedule` here: sync can
/// deliver a day before the type it names, and resolution treats an unknown
/// type as unassigned.
nonisolated struct RosterDay: Equatable, Sendable {
    static let schemaVersion = 1

    var dayKey: String
    var shiftTypeID: UUID
    /// The assigned type as it stood when a past day was edited. Historical
    /// plans must not change when that live type is later renamed or edited.
    /// Nil keeps rows written by older builds and future roster assignments
    /// on the live schedule type.
    var assignedShiftType: ShiftType? = nil
    var timeZoneIdentifier: String
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID
}

/// Planned history for the roster editor. Actual overrides and leave are
/// deliberately absent: the calendar edits the plan underneath those layers.
nonisolated enum PlannedRosterPreview: Equatable, Sendable {
    case shift(ShiftType)
    case rest
    case noPlan
}
