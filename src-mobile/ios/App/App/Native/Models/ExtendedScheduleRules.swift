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
///
/// The fields are read-only because the plan carries its own index, built once
/// here: the countdown resolves a shift every second, and re-parsing a roster
/// of a thousand day keys on each call is what made that cost milliseconds.
nonisolated struct ExtendedSchedulePlan: Codable, Equatable, Sendable {
    /// The type `pinning` adds for today's fixed clock readings. It never
    /// reaches the archive, so a constant is enough to recognise it.
    static let pinnedShiftTypeID = UUID(uuidString: "00000000-0000-0000-0000-00000000F1ED")!

    let shiftTypes: [ShiftType]
    let rule: ShiftCycleRule?
    /// Civil day key to shift type, for the days the user set by hand.
    let handSetDays: [String: UUID]
    /// The day `pinning` fixed. It resolves to `pinnedShiftTypeID` without
    /// counting as a day the user set: otherwise it would make a carried-over
    /// month authored, and every other day of that month would read as rest.
    let pinnedDayKey: String?
    /// Process-local version from `RecordCoordinator`, so caches keyed on a
    /// plan can tell two plans apart without comparing every day.
    let revision: Int
    fileprivate let index: ExtendedScheduleIndex

    init(
        shiftTypes: [ShiftType],
        rule: ShiftCycleRule?,
        handSetDays: [String: UUID],
        pinnedDayKey: String? = nil,
        revision: Int = 0
    ) {
        self.shiftTypes = shiftTypes
        self.rule = rule
        self.handSetDays = handSetDays
        self.pinnedDayKey = pinnedDayKey
        self.revision = revision
        index = ExtendedScheduleIndex(
            shiftTypes: shiftTypes,
            rule: rule,
            handSetDays: handSetDays,
            pinnedDayKey: pinnedDayKey
        )
    }

    /// `includeDisabled` is for history: days already worked under an extended
    /// schedule keep resolving through it after the user switches it off.
    init?(
        schedule: ExtendedSchedule?,
        rosterDays: [RosterDay],
        includeDisabled: Bool = false,
        revision: Int = 0
    ) {
        guard let schedule, schedule.isEnabled || includeDisabled else { return nil }
        self.init(
            shiftTypes: schedule.shiftTypes,
            rule: schedule.rule,
            handSetDays: Self.handSetDays(from: rosterDays),
            revision: revision
        )
    }

    static func handSetDays(from rosterDays: [RosterDay]) -> [String: UUID] {
        var handSet: [String: UUID] = [:]
        handSet.reserveCapacity(rosterDays.count)
        for day in rosterDays {
            handSet[day.dayKey] = day.shiftTypeID
        }
        return handSet
    }

    private enum CodingKeys: String, CodingKey {
        case shiftTypes, rule, handSetDays, pinnedDayKey, revision
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shiftTypes: try container.decode([ShiftType].self, forKey: .shiftTypes),
            rule: try container.decodeIfPresent(ShiftCycleRule.self, forKey: .rule),
            handSetDays: try container.decode([String: UUID].self, forKey: .handSetDays),
            pinnedDayKey: try container.decodeIfPresent(String.self, forKey: .pinnedDayKey),
            revision: try container.decode(Int.self, forKey: .revision)
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision
            && lhs.shiftTypes == rhs.shiftTypes
            && lhs.rule == rhs.rule
            && lhs.handSetDays == rhs.handSetDays
            && lhs.pinnedDayKey == rhs.pinnedDayKey
    }

    /// The hours this plan gives one civil day, or `nil` when it is rest.
    func hours(onDayKey dayKey: String) -> ExtendedScheduleDayHours? {
        guard let dayNumber = ExtendedScheduleResolver.dayNumber(dayKey: dayKey) else { return nil }
        return ExtendedScheduleResolver(plan: self).day(dayNumber: dayNumber).hours
    }

    /// The same plan with one day fixed to the given clock readings.
    ///
    /// An early clock-in, or a caller that fixes today's start and end, gives
    /// the rules one pair of readings — which an assigned day would otherwise
    /// replace with its own. Fixing the day keeps both: the rest of the roster
    /// resolves as before, and today reads what the caller asked for. Nothing
    /// here is stored or synced.
    func pinning(dayKey: String, to hours: ExtendedScheduleDayHours) -> ExtendedSchedulePlan {
        let start = Clock(hours.startTime)
        let end = Clock(hours.endTime)
        let breakStart = hours.breakStartTime.map { Clock($0).minutes }
        var types = shiftTypes.filter { $0.id != Self.pinnedShiftTypeID }
        types.append(ShiftType(
            id: Self.pinnedShiftTypeID,
            name: "pinned",
            kind: .work,
            startMinutes: start.minutes,
            endMinutes: end.minutes,
            breakEnabled: breakStart != nil && hours.breakDurationMinutes > 0,
            breakStartMinutes: breakStart ?? 0,
            breakDurationMinutes: breakStart == nil ? 0 : hours.breakDurationMinutes,
            colorHex: "#000000",
            isArchived: true
        ))
        return ExtendedSchedulePlan(
            shiftTypes: types,
            rule: rule,
            handSetDays: handSetDays,
            pinnedDayKey: dayKey,
            revision: revision
        )
    }
}

/// Everything resolution needs from a plan, parsed once. Immutable, so plans
/// that share it can cross actors.
fileprivate nonisolated final class ExtendedScheduleIndex: Sendable {
    /// What each defined type resolves to, before the source is known.
    let dayByType: [UUID: (isWorkday: Bool, hours: ExtendedScheduleDayHours?)]
    let rule: ShiftCycleRule?
    let ruleAnchorDayNumber: Int?
    let handSetByDayNumber: [Int: UUID]
    /// Month key to that month's hand-set days, by day of the month.
    let authoredMonths: [Int: [Int: UUID]]
    let authoredMonthKeys: [Int]

    init(shiftTypes: [ShiftType], rule: ShiftCycleRule?, handSetDays: [String: UUID], pinnedDayKey: String?) {
        var dayByType: [UUID: (isWorkday: Bool, hours: ExtendedScheduleDayHours?)] = [:]
        for type in shiftTypes where dayByType[type.id] == nil {
            // An archived type still resolves, so a past day keeps the shift it
            // was worked as; an invalid one resolves to nothing.
            guard type.isValid else { continue }
            switch type.kind {
            case .rest:
                dayByType[type.id] = (false, nil)
            case .work:
                dayByType[type.id] = (true, ExtendedScheduleDayHours(
                    startTime: ExtendedScheduleResolver.timeString(type.startMinutes),
                    endTime: ExtendedScheduleResolver.timeString(type.endMinutes),
                    breakStartTime: type.breakEnabled && type.breakDurationMinutes > 0
                        ? ExtendedScheduleResolver.timeString(type.breakStartMinutes)
                        : nil,
                    breakDurationMinutes: type.breakEnabled ? type.breakDurationMinutes : 0
                ))
            }
        }
        self.dayByType = dayByType
        self.rule = rule
        ruleAnchorDayNumber = rule.flatMap { ExtendedScheduleResolver.dayNumber(dayKey: $0.anchorDayKey) }

        var byDayNumber: [Int: UUID] = [:]
        byDayNumber.reserveCapacity(handSetDays.count)
        var months: [Int: [Int: UUID]] = [:]
        for (key, typeID) in handSetDays {
            guard let parts = ExtendedScheduleResolver.parse(dayKey: key) else { continue }
            byDayNumber[CivilZone.dayNumber(year: parts.year, month: parts.month, day: parts.day)] = typeID
            months[ExtendedScheduleResolver.monthKey(year: parts.year, month: parts.month), default: [:]][parts.day] = typeID
        }
        if let pinned = pinnedDayKey.flatMap(ExtendedScheduleResolver.dayNumber(dayKey:)) {
            byDayNumber[pinned] = ExtendedSchedulePlan.pinnedShiftTypeID
        }
        handSetByDayNumber = byDayNumber
        authoredMonths = months
        authoredMonthKeys = months.keys.sorted()
    }
}

/// Resolution for one run of the rules.
///
/// A class, and deliberately not `Sendable`: it memoises per day, because a
/// next-shift search or a life-sized expansion asks about the same days
/// repeatedly. `CivilZone` owns one for the length of a rule call, the same way
/// it owns its civil-reading cache. The index it reads belongs to the plan.
nonisolated final class ExtendedScheduleResolver {
    /// How far back a month with no roster of its own will look for one to copy.
    /// Ten years is past any calendar the user can have filled in, and bounds
    /// the walk for a plan whose only roster is ancient.
    static let carryOverMonthLimit = 120

    private let index: ExtendedScheduleIndex
    private var cache: [Int: ExtendedScheduleDay] = [:]

    init(plan: ExtendedSchedulePlan) {
        index = plan.index
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
        if let typeID = index.handSetByDayNumber[dayNumber] {
            return day(typeID: typeID, source: .handSet)
        }
        if let rule = index.rule, !rule.days.isEmpty, let anchor = index.ruleAnchorDayNumber {
            let count = rule.days.count
            let position = ((dayNumber - anchor) % count + count) % count
            return day(typeID: rule.days[position], source: .rule)
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
        guard index.authoredMonths[monthKey] == nil,
              let sourceKey = nearestAuthoredMonth(before: monthKey),
              let typeID = index.authoredMonths[sourceKey]?[date.day]
        else { return .unassigned }
        return day(typeID: typeID, source: .carriedOver)
    }

    private func nearestAuthoredMonth(before monthKey: Int) -> Int? {
        let keys = index.authoredMonthKeys
        var low = 0
        var high = keys.count
        while low < high {
            let middle = (low + high) / 2
            if keys[middle] < monthKey { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let candidate = keys[low - 1]
        return monthKey - candidate <= Self.carryOverMonthLimit ? candidate : nil
    }

    /// A type the plan does not define is unassigned: sync can deliver a day
    /// before the schedule that names its type.
    private func day(typeID: UUID, source: ExtendedScheduleDay.Source) -> ExtendedScheduleDay {
        guard let resolved = index.dayByType[typeID] else { return .unassigned }
        return ExtendedScheduleDay(
            isWorkday: resolved.isWorkday,
            hours: resolved.hours,
            shiftTypeID: typeID,
            source: source
        )
    }

    static func monthKey(year: Int, month: Int) -> Int { year * 12 + (month - 1) }

    static func parse(dayKey: String) -> (year: Int, month: Int, day: Int)? {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return (year, month, day)
    }

    static func dayNumber(dayKey: String) -> Int? {
        parse(dayKey: dayKey).map { CivilZone.dayNumber(year: $0.year, month: $0.month, day: $0.day) }
    }

    static func timeString(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 1_439)
        let hour = clamped / 60
        let minute = clamped % 60
        return "\(hour < 10 ? "0" : "")\(hour):\(minute < 10 ? "0" : "")\(minute)"
    }
}
