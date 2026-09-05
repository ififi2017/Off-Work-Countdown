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
    var isFromSavedSchedule: Bool = false
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

/// Recorded hours, their civil-day coverage, and a separate salary basis. Locked summaries
/// never carry these values into a view.
struct RecordsHeadlineSummary: Equatable, Sendable {
    var workdays: Int
    var regularWorkMs: Int64
    var overtimeMs: Int64
    var wakingFreeMs: Int64
    var estimatedIncome: Double?
    var completedScheduledWorkdays: Int
    var allocationDays: Int
    var allocation: TimeAllocationShare
    var sleepSourceKey: String
    var actualForecast: NativeRecordsActualForecastSummary? = nil
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

/// One month of the expanded year chart.
///
/// `workMs` and `overtimeMs` are summed from the same per-day
/// `TimeAllocationShare` values `recordsHeadline` combines, over the same
/// recorded-or-corrected days, so a month row and the month selection card
/// cannot print different numbers for the same month.
struct RecordsYearMonthBar: Equatable, Sendable, Identifiable {
    var id: Int { month }
    var month: Int
    var workMs: Int64
    var overtimeMs: Int64
    /// Future days a life projection can actually price. A merely scheduled
    /// future day carries no numbers, and inventing them here would be the
    /// fabricated history 010 removed.
    var projectedMs: Int64
    var workdays: Int
    var hasLockedDays: Bool

    var totalMs: Int64 { workMs + overtimeMs }
    var hasRecords: Bool { workdays > 0 }
    /// The full length a row draws, recorded work plus any projection sitting
    /// after it.
    var drawnMs: Int64 { totalMs + projectedMs }
}

enum RecordsYearMonthSampler {
    private static let hourMs = 3_600_000.0

    static func months(cells: [RecordsDayCell], calendar: Calendar) -> [RecordsYearMonthBar] {
        guard !cells.isEmpty else { return [] }
        var byMonth: [Int: RecordsYearMonthBar] = [:]
        for cell in cells {
            let month = calendar.component(.month, from: cell.date)
            var bar = byMonth[month] ?? RecordsYearMonthBar(
                month: month,
                workMs: 0,
                overtimeMs: 0,
                projectedMs: 0,
                workdays: 0,
                hasLockedDays: false
            )
            switch cell.appearance {
            case .recorded, .corrected:
                bar.workMs += cell.workMs
                bar.overtimeMs += cell.overtimeMs
                bar.workdays += 1
            case .locked:
                // A locked cell carries zeroes by construction. Recording only
                // that the month has one keeps the row from claiming the month
                // was empty.
                bar.hasLockedDays = true
            case .planned, .unrecorded, .rest:
                if cell.isProjection { bar.projectedMs += cell.workMs + cell.overtimeMs }
            }
            byMonth[month] = bar
        }
        return byMonth.keys.sorted().compactMap { byMonth[$0] }
    }

    /// One ceiling shared by every row. Each month filling its own track would
    /// make twelve bars that cannot be compared, which is the whole point of
    /// this form.
    static func axisCeiling(for months: [RecordsYearMonthBar]) -> Int64 {
        let peak = months.map(\.drawnMs).max() ?? 0
        guard peak > 0 else { return Int64(hourMs) }
        let hours = Double(peak) / hourMs
        let step: Double = if hours <= 40 { 10 } else if hours <= 120 { 20 } else { 50 }
        return Int64((hours / step).rounded(.up) * step * hourMs)
    }
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
    var id: String {
        [
            kind.rawValue,
            workPeriod?.rawValue ?? "all",
            start.map { String($0.timeIntervalSinceReferenceDate) } ?? "open",
            end.map { String($0.timeIntervalSinceReferenceDate) } ?? "open",
        ].joined(separator: ".")
    }
    var kind: LifeStageKind
    var start: Date?
    var end: Date?
    var startPrecision: CivilDatePrecision?
    var endPrecision: CivilDatePrecision?
    var workPeriod: LifeWorkPeriod? = nil

    var titleKey: String {
        switch workPeriod {
        case .elapsed: "lifeStageWorkElapsed"
        case .future: "lifeStageWorkFuture"
        case nil: kind.titleKey
        }
    }
}

enum LifeWorkPeriod: String, Equatable, Sendable {
    case elapsed
    case future
}

struct LifeCanvasBucket: Equatable, Sendable, Identifiable {
    var id: Int { index }
    var index: Int
    var start: Date
    var end: Date
    var kind: LifeStageKind
    var stageID: String
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
    /// Presentation intervals only: split the career at now without creating
    /// work records or changing the profile's retirement boundary.
    static func canvasStages(_ stages: [LifeStageSpan], now: Date) -> [LifeStageSpan] {
        stages.flatMap { stage -> [LifeStageSpan] in
            guard stage.kind == .work, let start = stage.start else { return [stage] }
            var result: [LifeStageSpan] = []
            if start < now {
                var elapsed = stage
                elapsed.end = min(stage.end ?? now, now)
                elapsed.workPeriod = .elapsed
                if elapsed.end == now { elapsed.endPrecision = .day }
                result.append(elapsed)
            }
            if let end = stage.end, end > now {
                var future = stage
                future.start = max(start, now)
                future.workPeriod = .future
                if future.start == now { future.startPrecision = .day }
                result.append(future)
            }
            return result.isEmpty ? [stage] : result
        }
    }

    static func stages(profile: LifeProfile, calendar: Calendar, now: Date = .now) -> [LifeStageSpan] {
        var next = profile
        next.migrateLegacyFields(calendar: calendar)
        let born = next.bornOn?.calculationAnchor(in: calendar)
        let school = next.schoolStartedOn?.calculationAnchor(in: calendar)
        let work = next.workStartedPartial?.calculationAnchor(in: calendar) ?? next.workStartedOn
        let retire = next.retirementOn?.calculationAnchor(in: calendar)

        let earlyStages = [
            LifeStageSpan(
                kind: .childhood,
                start: born,
                end: school ?? work,
                startPrecision: next.bornOn?.precision,
                endPrecision: next.schoolStartedOn?.precision ?? next.workStartedPartial?.precision
            ),
            LifeStageSpan(
                kind: .study,
                start: school,
                end: work,
                startPrecision: next.schoolStartedOn?.precision,
                endPrecision: next.workStartedPartial?.precision
            ),
        ]
        let workStages: [LifeStageSpan]
        if next.workHistoryMode == .detailed {
            workStages = detailedWorkStages(profile: next, retirement: retire, now: now, calendar: calendar)
        } else {
            workStages = [LifeStageSpan(
                kind: .work,
                start: work,
                end: retire,
                startPrecision: next.workStartedPartial?.precision,
                endPrecision: next.retirementOn?.precision
            )]
        }
        return earlyStages + workStages + [
            LifeStageSpan(
                kind: .retirement,
                start: retire,
                end: nil,
                startPrecision: next.retirementOn?.precision,
                endPrecision: nil
            ),
        ]
    }

    private static func detailedWorkStages(
        profile: LifeProfile,
        retirement: Date?,
        now: Date,
        calendar: Calendar
    ) -> [LifeStageSpan] {
        var stages = profile.employmentPeriods.compactMap { period -> LifeStageSpan? in
            guard let start = period.startsOn.calculationAnchor(in: calendar) else { return nil }
            let end = period.endsOn?.calculationAnchor(in: calendar) ?? retirement
            guard end.map({ $0 > start }) ?? true else { return nil }
            return LifeStageSpan(
                kind: .work,
                start: start,
                end: end,
                startPrecision: period.startsOn.precision,
                endPrecision: period.endsOn?.precision ?? profile.retirementOn?.precision
            )
        }
        if !profile.employmentPeriods.contains(where: { $0.endsOn == nil }),
           profile.roughCurrentSalary?.isValid == true {
            let start = calendar.startOfDay(for: now)
            if retirement.map({ $0 > start }) ?? true {
                stages.append(LifeStageSpan(
                    kind: .work,
                    start: start,
                    end: retirement,
                    startPrecision: .day,
                    endPrecision: profile.retirementOn?.precision
                ))
            }
        }
        return stages.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
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
            let stage = stage(at: mid, stages: stages)
            return LifeCanvasBucket(
                index: index,
                start: start,
                end: end,
                kind: stage?.kind ?? .unset,
                stageID: stage?.id ?? LifeStageKind.unset.rawValue,
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
}

/// One shared axis preserves comparisons without clipping long shifts.
enum RecordsWeekAxis {
    static func ceiling(for cells: [RecordsDayCell]) -> Int64 {
        max(12 * 3_600_000, cells.map { $0.workMs + $0.overtimeMs }.max() ?? 0)
    }
}
