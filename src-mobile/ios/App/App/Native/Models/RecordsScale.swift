import Foundation

enum RecordsScale: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year
    case life

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .week: "recordsScaleWeek"
        case .month: "recordsScaleMonth"
        case .year: "recordsScaleYear"
        case .life: "recordsScaleLife"
        }
    }

    var requiresPlus: Bool {
        self == .year || self == .life
    }

    var zoomedIn: RecordsScale {
        switch self {
        case .week: .week
        case .month: .week
        case .year: .month
        case .life: .year
        }
    }

    var zoomedOut: RecordsScale {
        switch self {
        case .week: .month
        case .month: .year
        case .year: .life
        case .life: .life
        }
    }
}

enum RecordsDayAppearance: String, Equatable, Sendable {
    case unrecorded
    case recorded
    case corrected
    case planned
    case rest
    case locked
}

struct RecordsDayCell: Equatable, Sendable, Identifiable {
    var id: String { dayKey }
    var dayKey: String
    var date: Date
    var appearance: RecordsDayAppearance
    var workMs: Int64
    var overtimeMs: Int64
    var breakMs: Int64
    var freeMs: Int64
    var observationCount: Int
    var isToday: Bool
    var isFuture: Bool
    var isProjection: Bool
    var hasConflict: Bool
}

struct RecordsDayDetail: Equatable, Sendable {
    var dayKey: String
    var date: Date
    var appearance: RecordsDayAppearance
    var sourceKey: String
    var regularWorkMs: Int64
    var overtimeMs: Int64
    var breakMs: Int64
    var sleepMs: Int64
    var freeMs: Int64
    var sleepSourceKey: String
    var observations: [String]
    var isPlanned: Bool
    var isProjection: Bool
}

/// Four headline numbers plus the 100% allocation bar. Locked summaries
/// never carry these values into a view.
struct RecordsHeadlineSummary: Equatable, Sendable {
    var workdays: Int
    var regularWorkMs: Int64
    var overtimeMs: Int64
    var wakingFreeMs: Int64
    var estimatedIncome: Double?
    var allocation: TimeAllocationShare
    var sleepSourceKey: String
}

enum RecordsLockedKind: String, Equatable, Sendable {
    case day
    case scale
    case summary
}

struct RecordsYearBucket: Equatable, Sendable, Identifiable {
    var id: Int { index }
    var index: Int
    var start: Date
    var end: Date
    var month: Int
    var kind: RecordsDayAppearance
    var workMs: Int64
    var isProjection: Bool
}

enum LifeStageKind: String, Equatable, Sendable {
    case childhood
    case study
    case work
    case retirement
    case unset

    var titleKey: String {
        switch self {
        case .childhood: "lifeStageChildhood"
        case .study: "lifeStageStudy"
        case .work: "lifeStageWork"
        case .retirement: "lifeStageRetirement"
        case .unset: "lifeStageUnset"
        }
    }

    var iconName: String {
        switch self {
        case .childhood: "figure.and.child.holdinghands"
        case .study: "graduationcap.fill"
        case .work: "briefcase.fill"
        case .retirement: "sun.horizon.fill"
        case .unset: "questionmark"
        }
    }
}

struct LifeStageSpan: Equatable, Sendable, Identifiable {
    var id: LifeStageKind { kind }
    var kind: LifeStageKind
    var start: Date?
    var end: Date?
    var startPrecision: CivilDatePrecision?
    var endPrecision: CivilDatePrecision?
}

struct LifeCanvasBucket: Equatable, Sendable, Identifiable {
    var id: Int { index }
    var index: Int
    var start: Date
    var end: Date
    var kind: LifeStageKind
    var isCurrent: Bool
    var isFuture: Bool
}

struct FocusScheduleSlot: Equatable, Sendable, Identifiable {
    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
    var start: Date
    var end: Date
    var shiftAnchor: Date
    var isCurrentShift: Bool
}

enum LifeStageCalculator {
    static func stages(profile: LifeProfile, calendar: Calendar) -> [LifeStageSpan] {
        var next = profile
        next.migrateLegacyFields(calendar: calendar)
        let born = next.bornOn?.calculationAnchor(in: calendar)
        let school = next.schoolStartedOn?.calculationAnchor(in: calendar)
        let work = next.workStartedPartial?.calculationAnchor(in: calendar) ?? next.workStartedOn
        let retire = next.retirementOn?.calculationAnchor(in: calendar)

        return [
            LifeStageSpan(
                kind: .childhood,
                start: born,
                end: school,
                startPrecision: next.bornOn?.precision,
                endPrecision: next.schoolStartedOn?.precision
            ),
            LifeStageSpan(
                kind: .study,
                start: school,
                end: work,
                startPrecision: next.schoolStartedOn?.precision,
                endPrecision: next.workStartedPartial?.precision
            ),
            LifeStageSpan(
                kind: .work,
                start: work,
                end: retire,
                startPrecision: next.workStartedPartial?.precision,
                endPrecision: next.retirementOn?.precision
            ),
            LifeStageSpan(
                kind: .retirement,
                start: retire,
                end: nil,
                startPrecision: next.retirementOn?.precision,
                endPrecision: nil
            ),
        ]
    }

    static func timelineBounds(stages: [LifeStageSpan], now: Date) -> (Date, Date)? {
        let starts = stages.compactMap(\.start)
        guard let origin = starts.min() else { return nil }
        let retire = stages.first(where: { $0.kind == .retirement })?.start
        // Retirement has no invented death date. Once it has actually begun,
        // however, the canvas must include the elapsed retired years instead
        // of ending just before the currently selected stage.
        let configuredEnd = retire ?? stages.compactMap(\.end).max() ?? now
        let end = max(configuredEnd, now)
        guard end > origin else { return nil }
        return (origin, end)
    }

    static func buckets(
        stages: [LifeStageSpan],
        from: Date,
        to: Date,
        count: Int,
        now: Date
    ) -> [LifeCanvasBucket] {
        guard count > 0, to > from else { return [] }
        let span = to.timeIntervalSince(from)
        return (0..<count).map { index in
            let start = from.addingTimeInterval(span * Double(index) / Double(count))
            let end = from.addingTimeInterval(span * Double(index + 1) / Double(count))
            let mid = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            return LifeCanvasBucket(
                index: index,
                start: start,
                end: end,
                kind: kind(at: mid, stages: stages),
                isCurrent: now >= start && now < end,
                isFuture: mid > now
            )
        }
    }

    static func kind(at date: Date, stages: [LifeStageSpan]) -> LifeStageKind {
        stage(at: date, stages: stages)?.kind ?? .unset
    }

    static func stage(at date: Date, stages: [LifeStageSpan]) -> LifeStageSpan? {
        stages.first { contains($0, date, stages: stages) }
    }

    static func progress(from start: Date, to end: Date, at date: Date) -> Double {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }

    /// An open-ended stage stops at the next stage that has a start, so
    /// childhood without a school year does not paint over work or retirement.
    private static func contains(_ stage: LifeStageSpan, _ date: Date, stages: [LifeStageSpan]) -> Bool {
        guard let start = stage.start else { return false }
        let end = stage.end ?? stages.compactMap(\.start).filter { $0 > start }.min()
        if let end { return date >= start && date < end }
        return date >= start
    }
}

enum RecordsYearSampler {
    static func buckets(
        from: Date,
        to: Date,
        count: Int,
        cells: [RecordsDayCell],
        calendar: Calendar
    ) -> [RecordsYearBucket] {
        guard count > 0, to > from else { return [] }
        let span = to.timeIntervalSince(from)
        return (0..<count).map { index in
            let start = from.addingTimeInterval(span * Double(index) / Double(count))
            let end = from.addingTimeInterval(span * Double(index + 1) / Double(count))
            let inside = cells.filter { $0.date >= start && $0.date < end }
            let workMs = inside.reduce(Int64(0)) { $0 + $1.workMs }
            let isProjection = inside.contains(where: \.isProjection)
            let appearance: RecordsDayAppearance
            if inside.contains(where: { $0.appearance == .corrected }) {
                appearance = .corrected
            } else if inside.contains(where: { $0.appearance == .recorded }) {
                appearance = .recorded
            } else if inside.contains(where: { $0.appearance == .planned }) {
                appearance = .planned
            } else if inside.contains(where: { $0.appearance == .locked }) {
                appearance = .locked
            } else {
                appearance = .unrecorded
            }
            return RecordsYearBucket(
                index: index,
                start: start,
                end: end,
                month: calendar.component(.month, from: start),
                kind: appearance,
                workMs: workMs,
                isProjection: isProjection
            )
        }
    }
}

extension RecordsAccess {
    static func canRevealDay(
        dayKey: String,
        today: Date,
        calendar: Calendar,
        authorized: Bool
    ) -> Bool {
        authorized || freeWindowContains(dayKey: dayKey, today: today, calendar: calendar)
    }
}

extension TimeAllocationCalculator {
    static func share(
        dayStart: Date,
        nextDayStart: Date,
        workSegments: [NativeShiftSegment],
        overtimeSegments: [NativeShiftSegment] = [],
        breakSegments: [NativeShiftSegment] = [],
        sleepHours: Double,
        incomplete: Bool = false
    ) -> TimeAllocationShare {
        let dayStartMs = Int64((dayStart.timeIntervalSince1970 * 1_000).rounded())
        let dayEndMs = Int64((nextDayStart.timeIntervalSince1970 * 1_000).rounded())
        let dayLength = max(0, dayEndMs - dayStartMs)
        let work = clippedDuration(workSegments, from: dayStartMs, to: dayEndMs)
        let overtime = clippedDuration(overtimeSegments, from: dayStartMs, to: dayEndMs)
        let breaks = clippedDuration(breakSegments, from: dayStartMs, to: dayEndMs)
        let sleepBudget = Int64(max(0, sleepHours) * 3_600_000)
        let occupied = min(dayLength, work + overtime)
        let sleep = min(sleepBudget, max(0, dayLength - occupied))
        var free = max(0, dayLength - occupied - sleep)
        let boundedBreak = min(breaks, free)
        free -= boundedBreak
        let unclassified: Int64
        if incomplete {
            unclassified = free
            free = 0
        } else {
            unclassified = 0
        }
        return TimeAllocationShare(
            workMs: work,
            overtimeMs: overtime,
            breakMs: boundedBreak,
            sleepMs: sleep,
            freeMs: free,
            unclassifiedMs: unclassified,
            dayLengthMs: dayLength
        )
    }

    static func combining(_ shares: [TimeAllocationShare]) -> TimeAllocationShare {
        shares.reduce(TimeAllocationShare(
            workMs: 0,
            overtimeMs: 0,
            breakMs: 0,
            sleepMs: 0,
            freeMs: 0,
            unclassifiedMs: 0,
            dayLengthMs: 0
        )) { partial, next in
            TimeAllocationShare(
                workMs: partial.workMs + next.workMs,
                overtimeMs: partial.overtimeMs + next.overtimeMs,
                breakMs: partial.breakMs + next.breakMs,
                sleepMs: partial.sleepMs + next.sleepMs,
                freeMs: partial.freeMs + next.freeMs,
                unclassifiedMs: partial.unclassifiedMs + next.unclassifiedMs,
                dayLengthMs: partial.dayLengthMs + next.dayLengthMs
            )
        }
    }

    static func gaps(in segments: [NativeShiftSegment]) -> [NativeShiftSegment] {
        let sorted = segments.sorted { $0.startAtMs < $1.startAtMs }
        guard sorted.count >= 2 else { return [] }
        return zip(sorted, sorted.dropFirst()).compactMap { current, next in
            guard next.startAtMs > current.endAtMs else { return nil }
            return NativeShiftSegment(startAtMs: current.endAtMs, endAtMs: next.startAtMs)
        }
    }
}
