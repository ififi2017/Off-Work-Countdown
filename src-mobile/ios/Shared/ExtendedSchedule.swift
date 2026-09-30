import Foundation

/// Inclusive month/day bounds that repeat every year. An end before the start
/// crosses New Year; February 29 is valid and applies only when that day exists.
nonisolated struct AnnualShiftDateRange: Codable, Hashable, Sendable {
    var startMonth: Int
    var startDay: Int
    var endMonth: Int
    var endDay: Int

    var isValid: Bool {
        Self.isValid(month: startMonth, day: startDay)
            && Self.isValid(month: endMonth, day: endDay)
    }

    func contains(month: Int, day: Int) -> Bool {
        guard isValid, Self.isValid(month: month, day: day) else { return false }
        let start = startMonth * 100 + startDay
        let end = endMonth * 100 + endDay
        let date = month * 100 + day
        return start <= end ? (start...end).contains(date) : date >= start || date <= end
    }

    func overlaps(_ other: Self) -> Bool {
        guard isValid, other.isValid else { return false }
        return contains(month: other.startMonth, day: other.startDay)
            || contains(month: other.endMonth, day: other.endDay)
            || other.contains(month: startMonth, day: startDay)
            || other.contains(month: endMonth, day: endDay)
    }

    private static func isValid(month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), (1...31).contains(day) else { return false }
        let civil = CivilZone.civilDate(dayNumber: CivilZone.dayNumber(year: 2000, month: month, day: day))
        return civil.year == 2000 && civil.month == month && civil.day == day
    }
}

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
    /// Replaces the pattern's work hours during these dates each year, while
    /// retaining its work/rest days and explicit calendar assignments.
    var annualDateRange: AnnualShiftDateRange? = nil

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
            && (annualDateRange.map { kind == .work && $0.isValid } ?? true)
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
    /// Free schedules stop automatic carry-over and holiday assignments from this civil day.
    var clearedFromDayKey: String? = nil
    /// The zone whose civil dates the rule anchor and roster day keys name.
    var timeZoneIdentifier: String
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID

    var content: ExtendedScheduleContent {
        get { ExtendedScheduleContent(shiftTypes: shiftTypes, rule: rule, holidayRegionIdentifier: holidayRegionIdentifier, clearedFromDayKey: clearedFromDayKey) }
        set {
            shiftTypes = newValue.shiftTypes
            rule = newValue.rule
            holidayRegionIdentifier = newValue.holidayRegionIdentifier
            clearedFromDayKey = newValue.clearedFromDayKey
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
    /// Free schedules stop automatic carry-over and holiday assignments from this civil day.
    var clearedFromDayKey: String? = nil

    var hasOverlappingAnnualDateRanges: Bool {
        let ranges = shiftTypes.filter { $0.kind == .work && !$0.isArchived }.compactMap(\.annualDateRange)
        return ranges.enumerated().contains { index, range in
            ranges.dropFirst(index + 1).contains { range.overlaps($0) }
        }
    }

    func isValid(in zone: TimeZone) -> Bool {
        guard clearedFromDayKey.map({ ExtendedScheduleResolver.parse(dayKey: $0) != nil }) ?? true,
              HolidayCalendar.isValidRegionIdentifier(holidayRegionIdentifier),
              shiftTypes.allSatisfy(\.isValid),
              !hasOverlappingAnnualDateRanges,
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
    /// Missing on older rows, which must conservatively remain manual.
    var generatedFromPattern: Bool? = nil
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
