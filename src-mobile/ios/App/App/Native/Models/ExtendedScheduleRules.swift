import Foundation

/// Plan 018 P8's extended scheduling: which shift each civil day gets, and the
/// hours that shift works.
///
/// This is iOS-only behaviour. There is no TypeScript oracle for it and none is
/// owed — plan 019's contract keeps shared rules on generated fixtures and
/// leaves 018 P8 to Swift tests alone. Nothing here is a second schedule
/// algorithm: the resolver answers with the same
/// `(startTime, endTime, break, isWorkday)` tuple the existing rules already
/// consume, and `CivilZone` runs its usual timeline, next-shift and expansion
/// code on that answer.
///
/// Day keys are civil dates (`YYYY-MM-DD`) and are read as labels, not
/// instants: `2026-10-03` means the third of October in whichever zone the
/// rules are resolving, so a stored schedule keeps meaning the same days after
/// the user travels.

/// The clock readings one assigned day works, in the shape the rules take.
nonisolated struct ExtendedScheduleDayHours: Codable, Equatable, Sendable {
    var startTime: String
    var endTime: String
    var breakStartTime: String?
    var breakDurationMinutes: Int
}

/// One civil day's conclusion, and which layer reached it.
nonisolated struct ExtendedScheduleDay: Equatable, Sendable {
    nonisolated enum Source: String, Sendable {
        /// A `RosterDay` the user set by hand. Wins over everything.
        case handSet
        /// The cycle rule, counted from its anchor.
        case rule
        /// Copied by day number from an earlier month the user filled in.
        case carriedOver
        /// Nothing assigns this day, so nothing counts down on it.
        case unassigned
    }

    var isWorkday: Bool
    /// `nil` on a rest or unassigned day, where the caller keeps its own hours:
    /// a rest day still carries a shape so a makeup day can reuse it, exactly
    /// as a classic rest day does.
    var hours: ExtendedScheduleDayHours?
    var shiftTypeID: UUID?
    var source: Source

    static let unassigned = ExtendedScheduleDay(
        isWorkday: false, hours: nil, shiftTypeID: nil, source: .unassigned
    )
}

/// The stored extended schedule flattened into what resolution needs, so it can
/// ride along in `NativeRulesInput` and `ScheduleHoursConfiguration` without
/// those types depending on the record archive.
///
/// `init?` returns `nil` for a schedule that is absent or switched off, which is
/// what every existing user has: a `nil` plan leaves every rule on exactly the
/// path it took before plan 018 P8.
nonisolated struct ExtendedSchedulePlan: Codable, Equatable, Sendable {
    var shiftTypes: [ShiftType]
    var rule: ShiftCycleRule?
    /// Civil day key to shift type, for the days the user set by hand.
    var handSetDays: [String: UUID]

    init(shiftTypes: [ShiftType], rule: ShiftCycleRule?, handSetDays: [String: UUID]) {
        self.shiftTypes = shiftTypes
        self.rule = rule
        self.handSetDays = handSetDays
    }

    init?(schedule: ExtendedSchedule?, rosterDays: [RosterDay]) {
        guard let schedule, schedule.isEnabled else { return nil }
        var handSet: [String: UUID] = [:]
        handSet.reserveCapacity(rosterDays.count)
        for day in rosterDays {
            handSet[day.dayKey] = day.shiftTypeID
        }
        self.init(shiftTypes: schedule.shiftTypes, rule: schedule.rule, handSetDays: handSet)
    }
}

/// Resolution for one run of the rules.
///
/// A class, and deliberately not `Sendable`: it indexes the plan once and
/// memoises per day, because a next-shift search or a life-sized expansion asks
/// about the same days repeatedly. `CivilZone` owns one for the length of a
/// rule call, the same way it owns its civil-reading cache.
nonisolated final class ExtendedScheduleResolver {
    /// How far back a month with no roster of its own will look for one to copy.
    /// Ten years is past any calendar the user can have filled in, and bounds
    /// the walk for a plan whose only roster is ancient.
    static let carryOverMonthLimit = 120

    private let typesByID: [UUID: ShiftType]
    private let rule: ShiftCycleRule?
    private let ruleAnchorDayNumber: Int?
    private let handSetByDayNumber: [Int: UUID]
    /// Month key to that month's hand-set days, by day of the month.
    private let authoredMonths: [Int: [Int: UUID]]
    private let authoredMonthKeys: [Int]
    private var cache: [Int: ExtendedScheduleDay] = [:]

    init(plan: ExtendedSchedulePlan) {
        typesByID = Dictionary(plan.shiftTypes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rule = plan.rule
        ruleAnchorDayNumber = plan.rule.flatMap { Self.dayNumber(dayKey: $0.anchorDayKey) }

        var byDayNumber: [Int: UUID] = [:]
        byDayNumber.reserveCapacity(plan.handSetDays.count)
        var months: [Int: [Int: UUID]] = [:]
        for (key, typeID) in plan.handSetDays {
            guard let parts = Self.parse(dayKey: key) else { continue }
            byDayNumber[CivilZone.dayNumber(year: parts.year, month: parts.month, day: parts.day)] = typeID
            months[Self.monthKey(year: parts.year, month: parts.month), default: [:]][parts.day] = typeID
        }
        handSetByDayNumber = byDayNumber
        authoredMonths = months
        authoredMonthKeys = months.keys.sorted()
    }

    convenience init?(plan: ExtendedSchedulePlan?) {
        guard let plan else { return nil }
        self.init(plan: plan)
    }

    func day(dayNumber: Int) -> ExtendedScheduleDay {
        if let cached = cache[dayNumber] { return cached }
        let resolved = resolve(dayNumber: dayNumber)
        cache[dayNumber] = resolved
        return resolved
    }

    /// The priority chain: a day the user set by hand, then the cycle rule,
    /// then the nearest earlier month copied by day number.
    ///
    /// The holiday template sits between the hand-set day and the rule. It is
    /// not here because the bundled holiday data it reads does not exist yet
    /// (018 P8 节假日数据); it lands with that data, not before.
    private func resolve(dayNumber: Int) -> ExtendedScheduleDay {
        if let typeID = handSetByDayNumber[dayNumber] {
            return day(typeID: typeID, source: .handSet)
        }
        if let rule, !rule.days.isEmpty, let anchor = ruleAnchorDayNumber {
            let count = rule.days.count
            let index = ((dayNumber - anchor) % count + count) % count
            return day(typeID: rule.days[index], source: .rule)
        }
        return carriedOver(dayNumber: dayNumber)
    }

    /// A month the user never touched repeats the nearest earlier month it can
    /// find, matched by day number rather than by weekday, because this kind of
    /// roster often has no weekly pattern at all. A day number the source month
    /// does not have — the 29th to 31st copied out of February — is rest.
    ///
    /// A month the user *did* touch is authored: its unset days are rest rather
    /// than a second month blended into the first.
    private func carriedOver(dayNumber: Int) -> ExtendedScheduleDay {
        let date = CivilZone.civilDate(dayNumber: dayNumber)
        let monthKey = Self.monthKey(year: date.year, month: date.month)
        guard authoredMonths[monthKey] == nil,
              let sourceKey = nearestAuthoredMonth(before: monthKey),
              let typeID = authoredMonths[sourceKey]?[date.day]
        else { return .unassigned }
        return day(typeID: typeID, source: .carriedOver)
    }

    private func nearestAuthoredMonth(before monthKey: Int) -> Int? {
        var low = 0
        var high = authoredMonthKeys.count
        while low < high {
            let middle = (low + high) / 2
            if authoredMonthKeys[middle] < monthKey { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let candidate = authoredMonthKeys[low - 1]
        return monthKey - candidate <= Self.carryOverMonthLimit ? candidate : nil
    }

    /// An archived type still resolves, so a past day keeps the shift it was
    /// worked as. A type the plan does not define is unassigned: sync can
    /// deliver a day before the schedule that names its type.
    private func day(typeID: UUID, source: ExtendedScheduleDay.Source) -> ExtendedScheduleDay {
        guard let type = typesByID[typeID], type.isValid else { return .unassigned }
        switch type.kind {
        case .rest:
            return ExtendedScheduleDay(isWorkday: false, hours: nil, shiftTypeID: typeID, source: source)
        case .work:
            return ExtendedScheduleDay(
                isWorkday: true,
                hours: ExtendedScheduleDayHours(
                    startTime: Self.timeString(type.startMinutes),
                    endTime: Self.timeString(type.endMinutes),
                    breakStartTime: type.breakEnabled && type.breakDurationMinutes > 0
                        ? Self.timeString(type.breakStartMinutes)
                        : nil,
                    breakDurationMinutes: type.breakEnabled ? type.breakDurationMinutes : 0
                ),
                shiftTypeID: typeID,
                source: source
            )
        }
    }

    private static func monthKey(year: Int, month: Int) -> Int { year * 12 + (month - 1) }

    private static func parse(dayKey: String) -> (year: Int, month: Int, day: Int)? {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return (year, month, day)
    }

    private static func dayNumber(dayKey: String) -> Int? {
        parse(dayKey: dayKey).map { CivilZone.dayNumber(year: $0.year, month: $0.month, day: $0.day) }
    }

    static func timeString(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 1_439)
        let hour = clamped / 60
        let minute = clamped % 60
        return "\(hour < 10 ? "0" : "")\(hour):\(minute < 10 ? "0" : "")\(minute)"
    }
}
