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

    /// What is still worked once `portion` is taken as leave (plan 020), or
    /// `nil` when nothing is. The shift splits at half its working minutes
    /// with the break left out, so 09:00–18:00 with lunch at 12:00–13:00
    /// splits at 14:00: taking the morning leaves 14:00–18:00, taking the
    /// afternoon leaves 09:00–14:00 with its lunch.
    ///
    /// Minutes are wall-clock minutes. Across a DST change during the shift
    /// the split can sit an hour away from half the elapsed time; the planner,
    /// which works on absolute segments, may preview that night differently.
    func remaining(after portion: LeavePortion) -> ExtendedScheduleDayHours? {
        guard portion != .whole else { return nil }
        let start = Clock(startTime).minutes
        let length = (Clock(endTime).minutes - start + 1_440 - 1) % 1_440 + 1
        var breakOffset: Int?
        if let breakStartTime, breakDurationMinutes > 0 {
            let offset = (Clock(breakStartTime).minutes - start + 1_440) % 1_440
            // The same test `CivilZone.timeline` applies: strictly inside.
            if offset > 0, offset + breakDurationMinutes < length { breakOffset = offset }
        }
        let working = length - (breakOffset == nil ? 0 : breakDurationMinutes)
        let half = working / 2
        guard half > 0 else { return nil }
        func clock(_ offset: Int) -> String { ExtendedScheduleResolver.timeString((start + offset) % 1_440) }
        let keepsBreak: Bool
        let from: Int
        let to: Int
        if let breakOffset, half > breakOffset {
            // The first half runs through the break.
            let split = half + breakDurationMinutes
            (from, to, keepsBreak) = portion == .firstHalf ? (split, length, false) : (0, split, true)
        } else {
            let secondStart = breakOffset == half ? half + breakDurationMinutes : half
            (from, to, keepsBreak) = portion == .firstHalf
                ? (secondStart, length, breakOffset.map { $0 > half } ?? false)
                : (0, half, false)
        }
        return ExtendedScheduleDayHours(
            startTime: clock(from),
            endTime: clock(to),
            breakStartTime: keepsBreak ? breakStartTime : nil,
            breakDurationMinutes: keepsBreak ? breakDurationMinutes : 0
        )
    }
}

/// Which part of one shift a leave request frees (plan 020).
nonisolated enum LeavePortion: String, Codable, Sendable, CaseIterable {
    case whole
    case firstHalf
    case secondHalf

    var halfDays: Int { self == .whole ? 2 : 1 }
}

/// One civil day's conclusion, and which layer reached it.
nonisolated struct ExtendedScheduleDay: Equatable, Sendable {
    nonisolated enum Source: String, Sendable {
        /// A `RosterDay` the user set by hand. Wins over everything.
        case handSet
        /// The cycle rule, counted from its anchor.
        case rule
        /// Annual month/day bounds replace the saved pattern's work hours.
        case annualRange
        /// An enabled bundled national holiday or makeup workday.
        case holiday
        /// Copied by day number from an earlier month the user filled in.
        case carriedOver
        /// Leave (plan 020) replaced an assigned shift: rest for a whole
        /// shift, the remaining half's hours for half of one.
        case leave
        /// Half a shift of leave over the fixed schedule underneath a
        /// fallback plan. The hours are the remaining half; whether the day
        /// is worked at all is still the fixed schedule's answer.
        case leaveOverBase
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

    /// Whether a fallback plan leaves this day's work-or-rest answer to the
    /// fixed schedule underneath.
    var followsBaseSchedule: Bool { source == .unassigned || source == .leaveOverBase }
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
    let clearedFromDayKey: String?
    let holidayRegionIdentifier: String?
    let holidayOverrides: [Int: Bool]?
    /// Civil day key to shift type, for the days the user set by hand.
    let handSetDays: [String: UUID]
    /// Past assignments carry their type with them so old schedule snapshots
    /// can resolve the exact hours chosen later.
    let frozenShiftTypes: [String: ShiftType]
    /// Historical assignments can be laid over a classic snapshot. Days with
    /// no exact assignment then keep that snapshot's normal schedule.
    let fallsBackToBaseSchedule: Bool
    /// The day `pinning` fixed. It resolves to `pinnedShiftTypeID` without
    /// counting as a day the user set: otherwise it would make a carried-over
    /// month authored, and every other day of that month would read as rest.
    let pinnedDayKey: String?
    /// Leave taken per civil day key (plan 020), laid over whatever the rest
    /// of the plan resolves. Empty for every plan without adopted leave.
    let leaveDays: [String: LeavePortion]
    /// The fixed hours underneath a fallback plan, which half a shift of
    /// leave on an otherwise unassigned day is taken from.
    let baseHours: ExtendedScheduleDayHours?
    /// Process-local version from `RecordCoordinator`, so caches keyed on a
    /// plan can tell two plans apart without comparing every day.
    let revision: Int
    fileprivate let index: ExtendedScheduleIndex

    init(
        shiftTypes: [ShiftType],
        rule: ShiftCycleRule?,
        handSetDays: [String: UUID],
        holidayRegionIdentifier: String? = nil,
        clearedFromDayKey: String? = nil,
        holidayOverrides: [Int: Bool]? = nil,
        frozenShiftTypes: [String: ShiftType] = [:],
        fallsBackToBaseSchedule: Bool = false,
        pinnedDayKey: String? = nil,
        leaveDays: [String: LeavePortion] = [:],
        baseHours: ExtendedScheduleDayHours? = nil,
        revision: Int = 0
    ) {
        self.shiftTypes = shiftTypes
        self.leaveDays = leaveDays
        self.baseHours = baseHours
        self.rule = rule
        self.holidayRegionIdentifier = holidayRegionIdentifier
        self.clearedFromDayKey = clearedFromDayKey
        self.holidayOverrides = holidayOverrides
        self.handSetDays = handSetDays
        self.frozenShiftTypes = frozenShiftTypes
        self.fallsBackToBaseSchedule = fallsBackToBaseSchedule
        self.pinnedDayKey = pinnedDayKey
        self.revision = revision
        index = ExtendedScheduleIndex(
            shiftTypes: shiftTypes,
            rule: rule,
            handSetDays: handSetDays,
            holidayRegionIdentifier: holidayRegionIdentifier,
            clearedFromDayKey: clearedFromDayKey,
            holidayOverrides: holidayOverrides,
            frozenShiftTypes: frozenShiftTypes,
            fallsBackToBaseSchedule: fallsBackToBaseSchedule,
            pinnedDayKey: pinnedDayKey,
            leaveDays: leaveDays,
            baseHours: baseHours
        )
    }

    /// The same plan with `leave` laid over it, or a fallback plan carrying
    /// only the leave over `baseHours` when there is no plan. `nil` stays
    /// `nil` without leave, so a user who never adopted any keeps the exact
    /// path they had.
    static func applying(
        leave: [String: LeavePortion],
        to plan: ExtendedSchedulePlan?,
        baseHours: ExtendedScheduleDayHours,
        revision: Int
    ) -> ExtendedSchedulePlan? {
        guard !leave.isEmpty else { return plan }
        guard let plan else {
            return ExtendedSchedulePlan(
                shiftTypes: [], rule: nil, handSetDays: [:],
                fallsBackToBaseSchedule: true,
                leaveDays: leave, baseHours: baseHours, revision: revision
            )
        }
        return ExtendedSchedulePlan(
            shiftTypes: plan.shiftTypes,
            rule: plan.rule,
            handSetDays: plan.handSetDays,
            holidayRegionIdentifier: plan.holidayRegionIdentifier,
            clearedFromDayKey: plan.clearedFromDayKey,
            holidayOverrides: plan.holidayOverrides,
            frozenShiftTypes: plan.frozenShiftTypes,
            fallsBackToBaseSchedule: plan.fallsBackToBaseSchedule,
            pinnedDayKey: plan.pinnedDayKey,
            leaveDays: leave,
            baseHours: plan.fallsBackToBaseSchedule ? baseHours : plan.baseHours,
            revision: revision
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
            holidayRegionIdentifier: schedule.holidayRegionIdentifier,
            clearedFromDayKey: schedule.clearedFromDayKey,
            frozenShiftTypes: Self.frozenShiftTypes(from: rosterDays),
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

    static func frozenShiftTypes(from rosterDays: [RosterDay]) -> [String: ShiftType] {
        Dictionary(rosterDays.compactMap { day in
            day.assignedShiftType.map { (day.dayKey, $0) }
        }, uniquingKeysWith: { _, latest in latest })
    }

    /// Historical assignments over an otherwise fixed snapshot. Frozen rows
    /// always apply. Legacy rows can be included for fixed snapshots from
    /// before extended scheduling began, using the live archived types older
    /// builds left them pointing at.
    init?(
        historicalRosterDays rosterDays: [RosterDay],
        legacyShiftTypes: [ShiftType] = [],
        includesLegacyRows: Bool = false,
        revision: Int = 0
    ) {
        let frozen = Self.frozenShiftTypes(from: rosterDays)
        let handSet = Dictionary(uniqueKeysWithValues: rosterDays.compactMap { day in
            if day.assignedShiftType != nil || includesLegacyRows { return (day.dayKey, day.shiftTypeID) }
            return nil
        })
        guard !handSet.isEmpty else { return nil }
        self.init(
            shiftTypes: legacyShiftTypes, rule: nil,
            handSetDays: handSet,
            frozenShiftTypes: frozen,
            fallsBackToBaseSchedule: true,
            revision: revision
        )
    }

    private enum CodingKeys: String, CodingKey {
        case clearedFromDayKey, shiftTypes, rule, handSetDays, holidayRegionIdentifier, holidayOverrides, frozenShiftTypes, fallsBackToBaseSchedule, pinnedDayKey, leaveDays, baseHours, revision
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shiftTypes: try container.decode([ShiftType].self, forKey: .shiftTypes),
            rule: try container.decodeIfPresent(ShiftCycleRule.self, forKey: .rule),
            handSetDays: try container.decode([String: UUID].self, forKey: .handSetDays),
            holidayRegionIdentifier: try container.decodeIfPresent(String.self, forKey: .holidayRegionIdentifier),
            clearedFromDayKey: try container.decodeIfPresent(String.self, forKey: .clearedFromDayKey),
            holidayOverrides: try container.decodeIfPresent([Int: Bool].self, forKey: .holidayOverrides),
            frozenShiftTypes: try container.decodeIfPresent([String: ShiftType].self, forKey: .frozenShiftTypes) ?? [:],
            fallsBackToBaseSchedule: try container.decodeIfPresent(Bool.self, forKey: .fallsBackToBaseSchedule) ?? false,
            pinnedDayKey: try container.decodeIfPresent(String.self, forKey: .pinnedDayKey),
            leaveDays: try container.decodeIfPresent([String: LeavePortion].self, forKey: .leaveDays) ?? [:],
            baseHours: try container.decodeIfPresent(ExtendedScheduleDayHours.self, forKey: .baseHours),
            revision: try container.decode(Int.self, forKey: .revision)
        )
    }

    /// Written as before for a plan without leave, so the Watch payload and
    /// every fixture that encodes a plan stay byte-for-byte what they were.
    func encode(to encoder: any Encoder) throws {
        // The synthesized order, which is `CodingKeys` order.
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(clearedFromDayKey, forKey: .clearedFromDayKey)
        try container.encode(shiftTypes, forKey: .shiftTypes)
        try container.encodeIfPresent(rule, forKey: .rule)
        try container.encode(handSetDays, forKey: .handSetDays)
        try container.encodeIfPresent(holidayRegionIdentifier, forKey: .holidayRegionIdentifier)
        try container.encodeIfPresent(holidayOverrides, forKey: .holidayOverrides)
        try container.encode(frozenShiftTypes, forKey: .frozenShiftTypes)
        try container.encode(fallsBackToBaseSchedule, forKey: .fallsBackToBaseSchedule)
        try container.encodeIfPresent(pinnedDayKey, forKey: .pinnedDayKey)
        if !leaveDays.isEmpty { try container.encode(leaveDays, forKey: .leaveDays) }
        try container.encodeIfPresent(baseHours, forKey: .baseHours)
        try container.encode(revision, forKey: .revision)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision
            && lhs.shiftTypes == rhs.shiftTypes
            && lhs.rule == rhs.rule
            && lhs.clearedFromDayKey == rhs.clearedFromDayKey
            && lhs.holidayRegionIdentifier == rhs.holidayRegionIdentifier
            && lhs.holidayOverrides == rhs.holidayOverrides
            && lhs.handSetDays == rhs.handSetDays
            && lhs.frozenShiftTypes == rhs.frozenShiftTypes
            && lhs.fallsBackToBaseSchedule == rhs.fallsBackToBaseSchedule
            && lhs.pinnedDayKey == rhs.pinnedDayKey
            && lhs.leaveDays == rhs.leaveDays
            && lhs.baseHours == rhs.baseHours
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
            holidayRegionIdentifier: holidayRegionIdentifier,
            clearedFromDayKey: clearedFromDayKey,
            holidayOverrides: holidayOverrides,
            frozenShiftTypes: frozenShiftTypes,
            fallsBackToBaseSchedule: fallsBackToBaseSchedule,
            pinnedDayKey: dayKey,
            leaveDays: leaveDays,
            baseHours: baseHours,
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
    let clearedFromDayNumber: Int?
    let holidayRegionIdentifier: String?
    let holidayOverrides: [Int: Bool]?
    let defaultWorkTypeID: UUID?
    let defaultRestTypeID: UUID?
    let annualWorkTypes: [(id: UUID, range: AnnualShiftDateRange)]
    let ruleAnchorDayNumber: Int?
    let handSetByDayNumber: [Int: UUID]
    let frozenByDayNumber: [Int: ShiftType]
    let fallsBackToBaseSchedule: Bool
    /// Month key to that month's hand-set days, by day of the month.
    let authoredMonths: [Int: [Int: UUID]]
    let authoredFrozenMonths: [Int: [Int: ShiftType]]
    let authoredMonthKeys: [Int]
    let leaveByDayNumber: [Int: LeavePortion]
    let baseHours: ExtendedScheduleDayHours?

    init(
        shiftTypes: [ShiftType], rule: ShiftCycleRule?, handSetDays: [String: UUID],
        holidayRegionIdentifier: String?, clearedFromDayKey: String?,
        holidayOverrides: [Int: Bool]?,
        frozenShiftTypes: [String: ShiftType], fallsBackToBaseSchedule: Bool,
        pinnedDayKey: String?,
        leaveDays: [String: LeavePortion],
        baseHours: ExtendedScheduleDayHours?
    ) {
        var leave: [Int: LeavePortion] = [:]
        for (key, portion) in leaveDays {
            if let dayNumber = ExtendedScheduleResolver.dayNumber(dayKey: key) { leave[dayNumber] = portion }
        }
        leaveByDayNumber = leave
        self.baseHours = baseHours
        self.holidayRegionIdentifier = holidayRegionIdentifier
        clearedFromDayNumber = clearedFromDayKey.flatMap(ExtendedScheduleResolver.dayNumber(dayKey:))
        self.holidayOverrides = holidayOverrides
        defaultWorkTypeID = shiftTypes.first { $0.kind == .work && !$0.isArchived }?.id
        defaultRestTypeID = shiftTypes.first { $0.kind == .rest && !$0.isArchived }?.id
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
        annualWorkTypes = shiftTypes.compactMap { type in
            guard type.kind == .work, !type.isArchived, type.isValid,
                  let range = type.annualDateRange else { return nil }
            return (type.id, range)
        }
        self.rule = rule
        self.fallsBackToBaseSchedule = fallsBackToBaseSchedule
        ruleAnchorDayNumber = rule.flatMap { ExtendedScheduleResolver.dayNumber(dayKey: $0.anchorDayKey) }

        var byDayNumber: [Int: UUID] = [:]
        byDayNumber.reserveCapacity(handSetDays.count)
        var months: [Int: [Int: UUID]] = [:]
        var frozen: [Int: ShiftType] = [:]
        // A day set to a type this schedule does not have — written under an
        // earlier set of types, such as one rebuilt from a fresh seed — says
        // nothing about the day. Letting it win would turn a workday into a day
        // with no shift; the pattern and holidays decide it instead. Archived
        // types are still present, so days worked under them keep their shift.
        let knownTypeIDs = Set(shiftTypes.map(\.id))
        for (key, typeID) in handSetDays where knownTypeIDs.contains(typeID) {
            guard let parts = ExtendedScheduleResolver.parse(dayKey: key) else { continue }
            byDayNumber[CivilZone.dayNumber(year: parts.year, month: parts.month, day: parts.day)] = typeID
            months[ExtendedScheduleResolver.monthKey(year: parts.year, month: parts.month), default: [:]][parts.day] = typeID
        }
        for (key, type) in frozenShiftTypes {
            guard let parts = ExtendedScheduleResolver.parse(dayKey: key), type.isValid else { continue }
            let dayNumber = CivilZone.dayNumber(year: parts.year, month: parts.month, day: parts.day)
            frozen[dayNumber] = type
        }
        if let pinned = pinnedDayKey.flatMap(ExtendedScheduleResolver.dayNumber(dayKey:)) {
            byDayNumber[pinned] = ExtendedSchedulePlan.pinnedShiftTypeID
        }
        handSetByDayNumber = byDayNumber
        frozenByDayNumber = frozen
        authoredMonths = months
        authoredFrozenMonths = Dictionary(grouping: frozenShiftTypes.compactMap { key, type in
            ExtendedScheduleResolver.parse(dayKey: key).map {
                (month: ExtendedScheduleResolver.monthKey(year: $0.year, month: $0.month), day: $0.day, type: type)
            }
        }, by: \.month).mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.day, $0.type) }) }
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

    /// Leave is laid over everything else. It only ever frees work: leave on
    /// a day the schedule already rests changes nothing.
    private func resolve(dayNumber: Int) -> ExtendedScheduleDay {
        let base = resolveSchedule(dayNumber: dayNumber)
        guard let portion = index.leaveByDayNumber[dayNumber] else { return base }
        if base.source == .unassigned, index.fallsBackToBaseSchedule {
            guard portion != .whole else {
                return ExtendedScheduleDay(isWorkday: false, hours: nil, shiftTypeID: nil, source: .leave)
            }
            guard let hours = index.baseHours?.remaining(after: portion) else { return base }
            return ExtendedScheduleDay(isWorkday: true, hours: hours, shiftTypeID: nil, source: .leaveOverBase)
        }
        guard base.isWorkday, let hours = base.hours else { return base }
        return ExtendedScheduleDay(
            isWorkday: portion != .whole,
            hours: hours.remaining(after: portion),
            shiftTypeID: base.shiftTypeID,
            source: .leave
        )
    }

    /// Explicit assignments win over bundled holidays, then the saved pattern.
    private func resolveSchedule(dayNumber: Int) -> ExtendedScheduleDay {
        if let type = index.frozenByDayNumber[dayNumber] {
            return day(type: type, source: .handSet)
        }
        if let typeID = index.handSetByDayNumber[dayNumber] {
            return day(typeID: typeID, source: .handSet)
        }
        if index.fallsBackToBaseSchedule { return .unassigned }
        if index.rule == nil, let cleared = index.clearedFromDayNumber, dayNumber >= cleared { return .unassigned }
        let base = annualDay(patternDay(dayNumber: dayNumber), dayNumber: dayNumber)
        guard let region = index.holidayRegionIdentifier, !region.isEmpty else { return base }
        let isWorkday: Bool?
        if let overrides = index.holidayOverrides {
            let civil = CivilZone.civilDate(dayNumber: dayNumber)
            isWorkday = overrides[civil.year * 10_000 + civil.month * 100 + civil.day]
        } else {
            isWorkday = HolidayCalendar.shared.day(dayNumber: dayNumber, regionIdentifier: region)?.isWorkday
        }
        guard let isWorkday else { return base }
        if !isWorkday {
            if let id = index.defaultRestTypeID { return day(typeID: id, source: .holiday) }
            return ExtendedScheduleDay(isWorkday: false, hours: nil, shiftTypeID: nil, source: .holiday)
        }
        if base.isWorkday {
            var result = base
            result.source = .holiday
            return result
        }
        guard let id = index.defaultWorkTypeID else { return base }
        return annualDay(day(typeID: id, source: .holiday), dayNumber: dayNumber)
    }

    private func annualDay(_ base: ExtendedScheduleDay, dayNumber: Int) -> ExtendedScheduleDay {
        guard base.isWorkday, !index.annualWorkTypes.isEmpty else { return base }
        let civil = CivilZone.civilDate(dayNumber: dayNumber)
        guard let type = index.annualWorkTypes.first(where: { $0.range.contains(month: civil.month, day: civil.day) })
        else { return base }
        return day(typeID: type.id, source: base.source == .holiday ? .holiday : .annualRange)
    }

    private func patternDay(dayNumber: Int) -> ExtendedScheduleDay {
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
        if let frozen = index.authoredFrozenMonths[sourceKey]?[date.day] {
            return day(type: frozen, source: .carriedOver)
        }
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
        return candidate
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

    private func day(type: ShiftType, source: ExtendedScheduleDay.Source) -> ExtendedScheduleDay {
        switch type.kind {
        case .rest:
            return ExtendedScheduleDay(isWorkday: false, hours: nil, shiftTypeID: type.id, source: source)
        case .work:
            return ExtendedScheduleDay(
                isWorkday: true,
                hours: ExtendedScheduleDayHours(
                    startTime: Self.timeString(type.startMinutes),
                    endTime: Self.timeString(type.endMinutes),
                    breakStartTime: type.breakEnabled && type.breakDurationMinutes > 0
                        ? Self.timeString(type.breakStartMinutes) : nil,
                    breakDurationMinutes: type.breakEnabled ? type.breakDurationMinutes : 0
                ),
                shiftTypeID: type.id,
                source: source
            )
        }
    }

    var fallsBackToBaseSchedule: Bool { index.fallsBackToBaseSchedule }
    var baseHours: ExtendedScheduleDayHours? { index.baseHours }

    static func monthKey(year: Int, month: Int) -> Int { year * 12 + (month - 1) }

    static func parse(dayKey: String) -> (year: Int, month: Int, day: Int)? {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard dayKey.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil,
              parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9_999).contains(year), (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        let civil = CivilZone.civilDate(dayNumber: CivilZone.dayNumber(year: year, month: month, day: day))
        guard civil.year == year, civil.month == month, civil.day == day else { return nil }
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
