import Foundation

/// What a report says beyond the raw totals (plan 020 §4, round 2).
///
/// Everything here is arranged from figures the app already records: the Records
/// headline, the day cells, overtime declarations, early clock-offs, leave rows,
/// the live schedule and focus sessions. Nothing recomputes hours or pay. Each
/// insight is `nil` when its data is missing or too thin, and the chapter that
/// would tell it is left out rather than padded.

// MARK: - Against your usual

/// How the period sits next to the person's own past, never next to a target.
nonisolated struct CycleReportBaseline: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        /// The average of this many earlier periods that hold records.
        case usual(periods: Int)
        /// Only the period before had records; said so, not dressed up as usual.
        case previous
    }

    var kind: Kind
    var baselineWorkedMs: Int64
    var deltaMs: Int64

    var deltaFraction: Double {
        baselineWorkedMs > 0 ? Double(deltaMs) / Double(baselineWorkedMs) : 0
    }

    /// Weeks look back four, months three. `priors` run newest first. A running
    /// period is never compared: half a week against whole ones would only say
    /// that it is not over.
    static func make(
        current: CycleReportFigures,
        priors: [CycleReportFigures],
        window: Int,
        minimumWorkdays: Int = 2,
        isInProgress: Bool
    ) -> Self? {
        guard current.hasData, !isInProgress else { return nil }
        // A period with a day or two on file is where records began, not a
        // pattern to measure against.
        let usable = priors.prefix(window).filter { $0.hasData && $0.workdays >= minimumWorkdays }
        if usable.count >= 2 {
            let average = usable.reduce(Int64(0)) { $0 + $1.workedMs } / Int64(usable.count)
            return Self(kind: .usual(periods: usable.count), baselineWorkedMs: average,
                        deltaMs: current.workedMs - average)
        }
        if let first = priors.first, first.hasData, first.workdays >= minimumWorkdays {
            return Self(kind: .previous, baselineWorkedMs: first.workedMs,
                        deltaMs: current.workedMs - first.workedMs)
        }
        return nil
    }
}

// MARK: - How the days finished

/// One recorded workday's finish against its planned end.
nonisolated struct CycleReportFinishInput: Equatable, Sendable {
    var dayKey: String
    var date: Date
    var plannedEndMs: Double
    /// When the day actually ended, if the person said so: a declared overtime
    /// end, or an early clock-off. `nil` means nothing moved it.
    var finishedAtMs: Double?
}

/// Only what is recorded: the app learns a day ran late when overtime is logged
/// and that it ended early when the person clocked off. A day with neither is
/// read as finishing on schedule, which the page says plainly.
nonisolated struct CycleReportFinish: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case onPlan
        case late(ms: Int64)
        case early(ms: Int64)
    }

    nonisolated struct Day: Equatable, Sendable, Identifiable {
        var dayKey: String
        var date: Date
        var kind: Kind
        var id: String { dayKey }
    }

    var days: [Day]
    var lateCount: Int
    var earlyCount: Int
    var latest: Day?

    var recordedCount: Int { days.count }
    var onScheduleCount: Int { days.count - lateCount }

    /// Ten minutes either way is "on schedule": a clock-off a minute early is
    /// not a story.
    static let tolerance: Double = 10 * 60_000
    static let minimumDays = 2

    static func make(_ inputs: [CycleReportFinishInput]) -> Self? {
        guard inputs.count >= minimumDays else { return nil }
        let days = inputs.map { input -> Day in
            let kind: Kind
            if let finished = input.finishedAtMs {
                let delta = finished - input.plannedEndMs
                if delta > tolerance { kind = .late(ms: Int64(delta)) }
                else if delta < -tolerance { kind = .early(ms: Int64(-delta)) }
                else { kind = .onPlan }
            } else {
                kind = .onPlan
            }
            return Day(dayKey: input.dayKey, date: input.date, kind: kind)
        }
        var lateCount = 0
        var earlyCount = 0
        var latest: Day?
        var latestLate: Int64 = 0
        for day in days {
            switch day.kind {
            case .late(let ms):
                lateCount += 1
                if ms > latestLate { latestLate = ms; latest = day }
            case .early: earlyCount += 1
            case .onPlan: break
            }
        }
        return Self(days: days, lateCount: lateCount, earlyCount: earlyCount, latest: latest)
    }
}

// MARK: - Looking ahead

nonisolated struct CycleReportNextBreak: Equatable, Sendable {
    var startDayKey: String
    var startDate: Date
    var length: Int
    /// From today: 1 is tomorrow.
    var daysAway: Int
}

nonisolated struct CycleReportAhead: Equatable, Sendable {
    var leaveUsedHalfDays: Int
    /// `nil` when no leave balance is kept.
    var leaveRemainingHalfDays: Int?
    /// What the same balances were granted, so what is left can be drawn as a share.
    var leaveEntitledHalfDays: Int?
    var nextBreak: CycleReportNextBreak?
    /// Rest flags for the days after today, for drawing the road ahead.
    var horizon: [Bool]

    static let minimumBreak = 3
    static let horizonDays = 28

    /// The first run of at least `minimumBreak` rest days. `days` start tomorrow.
    static func findBreak(in days: [(dayKey: String, date: Date, isRest: Bool)]) -> CycleReportNextBreak? {
        var index = 0
        while index < days.count {
            guard days[index].isRest else { index += 1; continue }
            var end = index
            while end + 1 < days.count, days[end + 1].isRest { end += 1 }
            let length = end - index + 1
            // A run that touches the edge of what was looked at may be longer.
            if length >= minimumBreak {
                return CycleReportNextBreak(startDayKey: days[index].dayKey, startDate: days[index].date,
                                            length: length, daysAway: index + 1)
            }
            index = end + 1
        }
        return nil
    }

    static func make(
        upcoming: [(dayKey: String, date: Date, isRest: Bool)],
        leaveUsedHalfDays: Int,
        leaveRemainingHalfDays: Int?,
        leaveEntitledHalfDays: Int? = nil
    ) -> Self? {
        let next = findBreak(in: upcoming)
        guard next != nil || leaveUsedHalfDays > 0 || leaveRemainingHalfDays != nil else { return nil }
        return Self(leaveUsedHalfDays: leaveUsedHalfDays, leaveRemainingHalfDays: leaveRemainingHalfDays,
                    leaveEntitledHalfDays: leaveEntitledHalfDays,
                    nextBreak: next, horizon: upcoming.prefix(horizonDays).map(\.isRest))
    }
}

// MARK: - Focus

nonisolated struct CycleReportFocus: Equatable, Sendable {
    var rounds: Int
    var focusedMs: Int64
    /// Completed rounds on each day of the period, in order.
    var perDay: [Int]
    var bestDayIndex: Int
    var topIcon: FocusTaskIcon?

    static let minimumRounds = 2

    /// `rounds` are completed focus rounds in the period, each with the day it
    /// belongs to (an index into the period), its length and its task's icon.
    static func make(
        rounds: [(dayIndex: Int, ms: Int64, icon: FocusTaskIcon?)],
        dayCount: Int
    ) -> Self? {
        guard rounds.count >= minimumRounds, dayCount > 0 else { return nil }
        var perDay = [Int](repeating: 0, count: dayCount)
        var icons: [FocusTaskIcon: Int] = [:]
        for round in rounds where perDay.indices.contains(round.dayIndex) {
            perDay[round.dayIndex] += 1
            if let icon = round.icon { icons[icon, default: 0] += 1 }
        }
        let best = perDay.enumerated().max { ($0.element, -$0.offset) < ($1.element, -$1.offset) }?.offset ?? 0
        // The most common category; ties go to the earlier case so it is stable.
        let top = icons.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value
                : FocusTaskIcon.allCases.firstIndex(of: lhs.key)! > FocusTaskIcon.allCases.firstIndex(of: rhs.key)!
        }?.key
        return Self(rounds: perDay.reduce(0, +), focusedMs: rounds.reduce(0) { $0 + $1.ms },
                    perDay: perDay, bestDayIndex: best, topIcon: top)
    }
}

// MARK: - Pay

/// Pay read through the figures Records already prints. Only built when the
/// person chose to include income.
nonisolated struct CycleReportPay: Equatable, Sendable {
    var total: Double
    var perHour: Double?
    /// The part of the total that overtime added. Only where the salary rules pay
    /// overtime at the usual rate; a fixed monthly salary does not grow with it.
    var overtimeExtra: Double?

    static func make(figures: CycleReportFigures, overtimeIsPaid: Bool) -> Self? {
        guard let total = figures.income else { return nil }
        let hours = Double(figures.workedMs) / 3_600_000
        let perHour = hours >= 1 ? total / hours : nil
        var extra: Double?
        if overtimeIsPaid, figures.overtimeMs >= 15 * 60_000, figures.workedMs > 0 {
            extra = total * Double(figures.overtimeMs) / Double(figures.workedMs)
        }
        return Self(total: total, perHour: perHour, overtimeExtra: extra)
    }
}

// MARK: - The headline

/// A one-line title for the period, chosen by plain rules and worded so that no
/// outcome reads as a verdict.
nonisolated enum CycleReportHeadline: String, Equatable, Sendable {
    case steady
    case fullStretch
    case lighter
    case roomToBreathe
    case sprint
    case inProgress
    case plain

    var titleKey: String {
        switch self {
        case .steady: "reportHeadlineSteady"
        case .fullStretch: "reportHeadlineFull"
        case .lighter: "reportHeadlineLighter"
        case .roomToBreathe: "reportHeadlineRoom"
        case .sprint: "reportHeadlineSprint"
        case .inProgress: "reportHeadlineInProgress"
        case .plain: "reportHeadlinePlain"
        }
    }

    static func choose(
        figures: CycleReportFigures,
        baseline: CycleReportBaseline?,
        restDayCount: Int,
        longestRestRun: Int,
        kind: CycleReportKind,
        nextBreak: CycleReportNextBreak?,
        isInProgress: Bool
    ) -> Self {
        if isInProgress { return .inProgress }
        let delta = baseline?.deltaFraction ?? 0
        let overtimeShare = figures.workedMs > 0 ? Double(figures.overtimeMs) / Double(figures.workedMs) : 0
        // A break just ahead after a heavier-than-usual stretch.
        if let nextBreak, nextBreak.daysAway <= 7, baseline != nil, delta >= 0.05 { return .sprint }
        if overtimeShare >= 0.08 && figures.overtimeMs >= 2 * 3_600_000 { return .fullStretch }
        if baseline != nil, delta >= 0.10 { return .fullStretch }
        if baseline != nil, delta <= -0.10 { return .lighter }
        let restful = kind == .week ? restDayCount >= 4 : restDayCount >= 12
        if restful || longestRestRun >= 3 { return .roomToBreathe }
        if baseline != nil { return .steady }
        return .plain
    }
}
