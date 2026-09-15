import Foundation

/// Period summaries, Records income and forecast, the monthly salary
/// equivalent and lifetime income for iOS (plan 019 R3).
///
/// `lib/summary.ts` and the salary helpers in `lib/countdown.ts` stay the
/// specification: Web and Desktop still run them, and the timer's "This week"
/// row once shipped a different number from Records because a second formula
/// existed. `scripts/ios-schedule-rule-oracle.mjs` keeps these entry points in
/// TypeScript and `ScheduleRuleFixtureTests` holds this file to them.
nonisolated enum SummaryRules {
    // MARK: - Period summary

    /// Work from the period start to `asOfMs`, estimated from the schedule. The
    /// current shift counts only when it starts on a scheduled day inside the
    /// period, by its progress, matching the timer's "earned today".
    static func summarize(input: NativeSummaryInput) -> NativePeriodSummary {
        let zone = CivilZone(identifier: input.timeZoneIdentifier)
        // An explicit window start wins over the period name: the Records grids
        // follow the locale's first weekday, not the ISO week the name derives.
        let periodStartMs = input.periodStartMs.flatMap { $0.isFinite ? $0 : nil }
            ?? (input.period == "year" ? zone.yearStartMs(input.asOfMs) : zone.weekStartMs(input.asOfMs))
        let shiftDayMs = zone.startOfCivilDayMs(input.currentShiftStartMs)
        let shiftEndDayMs = zone.startOfCivilDayMs(input.currentShiftEndMs)
        let periodDayMs = zone.startOfCivilDayMs(periodStartMs)
        let asOfDayMs = zone.startOfCivilDayMs(input.asOfMs)
        // A same-day shift keeps counting by progress after it ends, and an
        // overnight one still belongs to its start day on its end day. Past the
        // end day the snapshot is stale and must not cut later workdays short.
        let coversAsOfDay = shiftDayMs >= periodDayMs && shiftDayMs <= asOfDayMs && shiftEndDayMs >= asOfDayMs
        let completed = Double(countScheduledWorkdays(
            fromMs: periodDayMs,
            toMs: coversAsOfDay ? shiftDayMs : asOfDayMs,
            input.workdays, input.schedule, zone
        ))
        // `isScheduledWorkday`, not the in-zone helper: manual mode still counts
        // today. Splitting the two once made an iOS week disagree with the Web's.
        let todayCounts = coversAsOfDay && zone.isScheduledWorkday(shiftDayMs, input.workdays, input.schedule)
        let todayFraction: Double = todayCounts ? min(100, max(0, input.todayProgress)) / 100 : 0
        let todayHours: Double = todayCounts ? input.todayEffectiveHours * todayFraction : 0
        let todayPay: Double = todayCounts ? max(0, input.todayPayRatio) : 0
        let hours: Double = completed * input.plannedDailyHours + todayHours
        return NativePeriodSummary(
            days: completed + todayFraction,
            hours: hours,
            earnings: earnings(input.dailySalary, ratio: completed + todayPay)
        )
    }

    private static func countScheduledWorkdays(
        fromMs: Double,
        toMs: Double,
        _ workdays: [Int],
        _ schedule: NativeWorkSchedule,
        _ zone: CivilZone
    ) -> Int {
        if schedule.mode == "off" { return 0 }
        var cursor = zone.startOfCivilDayMs(fromMs)
        let end = zone.startOfCivilDayMs(toMs)
        var count = 0
        while cursor < end {
            if zone.isScheduledWorkdayInZone(cursor, workdays, schedule) { count += 1 }
            cursor = zone.addCivilDaysMs(cursor, 1)
        }
        return count
    }

    // MARK: - Salary

    /// Completed scheduled workdays at the configured daily pay. Today's partial
    /// shift and overtime belong to the timer's live summary instead.
    static func recordsIncome(completedWorkdays: Int, rules: NativeRulesInput) -> Double? {
        earnings(
            SalaryRules.dailySalary(
                amount: rules.salaryAmount,
                type: rules.salaryType,
                monthlyWorkingDays: rules.monthlyWorkingDays,
                annualBonusMonths: rules.annualBonusMonths
            ),
            ratio: Double(max(0, completedWorkdays))
        )
    }

    /// The monthly gross a daily or monthly setting amounts to, used to seed
    /// the life profile.
    static func salaryMonthlyEquivalent(input: NativeRulesInput) -> Double? {
        monthlyEquivalent(
            amount: input.salaryAmount,
            type: input.salaryType,
            monthlyWorkingDays: input.monthlyWorkingDays,
            annualBonusMonths: input.annualBonusMonths
        )
    }

    private static func monthlyEquivalent(
        amount: String,
        type: String,
        monthlyWorkingDays: Double,
        annualBonusMonths: Double
    ) -> Double? {
        guard monthlyWorkingDays.isFinite, monthlyWorkingDays > 0, monthlyWorkingDays <= 31,
              let daily = SalaryRules.dailySalary(
                amount: amount,
                type: type,
                monthlyWorkingDays: monthlyWorkingDays,
                annualBonusMonths: annualBonusMonths
              )
        else { return nil }
        return daily * monthlyWorkingDays
    }

    private static func earnings(_ dailySalary: Double?, ratio: Double) -> Double? {
        dailySalary.map { max(0, ratio) * $0 }
    }

    // MARK: - Lifetime income

    /// Gross lifetime income from the salary intervals the user entered. Gaps
    /// contribute nothing; no raise, inflation or missing salary is inferred.
    static func lifetimeIncome(input: NativeLifetimeIncomeInput) -> NativeLifetimeIncomeSummary {
        let none = NativeLifetimeIncomeSummary(historicalGross: 0, projectedGross: 0, totalGross: 0)
        guard let asOf = civilDayNumber(input.asOf), let retirement = civilDayNumber(input.retirementOn) else { return none }

        var periods = input.periods
        if let current = input.currentSalary {
            periods.append(NativeLifetimeIncomePeriod(
                startsOn: current.startsOn ?? input.asOf,
                endsOn: input.retirementOn,
                salaryAmount: current.salaryAmount,
                salaryCadence: current.salaryCadence
            ))
        }
        struct Interval {
            let period: NativeLifetimeIncomePeriod
            let start: Int
            let end: Int
            let isCurrentSalary: Bool
        }
        var intervals: [Interval] = []
        for (index, period) in periods.enumerated() {
            let explicitEnd: Int? = if let endsOn = period.endsOn, !endsOn.isEmpty { civilDayNumber(endsOn) } else { retirement }
            guard let start = civilDayNumber(period.startsOn), let explicitEnd,
                  period.salaryAmount.isFinite, period.salaryAmount > 0
            else { continue }
            let end = min(explicitEnd, retirement)
            guard end > start else { continue }
            intervals.append(Interval(
                period: period,
                start: start,
                end: end,
                isCurrentSalary: input.currentSalary != nil && index == periods.count - 1
            ))
        }
        intervals = intervals.enumerated()
            .sorted { $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset }
            .map(\.element)

        // Work history is sequential. Reject overlap rather than inventing which
        // salary wins or counting two full-time jobs for the same day.
        if intervals.indices.contains(where: { $0 > 0 && intervals[$0].start < intervals[$0 - 1].end }) {
            return none
        }

        let decline: (start: Int, ratio: Double)? = if let value = input.futureIncomeDecline,
            let start = civilDayNumber(value.startsOn),
            value.retirementRatio.isFinite, value.retirementRatio >= 0, value.retirementRatio <= 1 {
            (start, value.retirementRatio)
        } else {
            nil
        }
        var historicalGross = 0.0
        var projectedGross = 0.0
        for interval in intervals {
            let amount = interval.period.salaryAmount
            let monthlySalary = interval.period.salaryCadence == "monthly" ? amount : amount / 12
            let totalForPeriod = monthlySalary * civilMonthsBetween(interval.start, interval.end)
            let historicalForPeriod = monthlySalary * civilMonthsBetween(interval.start, min(interval.end, asOf))
            historicalGross += historicalForPeriod
            let projectedStart = max(interval.start, asOf)
            guard interval.isCurrentSalary, let decline, projectedStart < interval.end else {
                projectedGross += totalForPeriod - historicalForPeriod
                continue
            }
            let anchor = max(projectedStart, decline.start)
            projectedGross += monthlySalary * civilMonthsBetween(projectedStart, min(anchor, interval.end))
            if anchor < interval.end {
                projectedGross += monthlySalary * decline.ratio * civilMonthsBetween(anchor, interval.end)
            }
        }
        return NativeLifetimeIncomeSummary(
            historicalGross: historicalGross,
            projectedGross: projectedGross,
            totalGross: historicalGross + projectedGross
        )
    }

    /// Each partial calendar month is prorated by that month's own day count.
    private static func civilMonthsBetween(_ start: Int, _ end: Int) -> Double {
        guard end > start else { return 0 }
        var cursor = start
        var total = 0.0
        while cursor < end {
            let (year, month, _) = CivilZone.civilDate(dayNumber: cursor)
            let monthStart = CivilZone.dayNumber(year: year, month: month, day: 1)
            let nextMonth = month == 12
                ? CivilZone.dayNumber(year: year + 1, month: 1, day: 1)
                : CivilZone.dayNumber(year: year, month: month + 1, day: 1)
            let segmentEnd = min(end, nextMonth)
            total += Double(segmentEnd - cursor) / Double(nextMonth - monthStart)
            cursor = segmentEnd
        }
        return total
    }

    /// A `YYYY-MM-DD` Gregorian date as a day number, or nil for anything
    /// `Date.UTC` would not round-trip — including years before 100, which it
    /// reads as 19xx.
    static func civilDayNumber(_ value: String) -> Int? {
        guard let match = value.wholeMatch(of: /([0-9]{4})-([0-9]{2})-([0-9]{2})/),
              let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
              year >= 100, (1...12).contains(month)
        else { return nil }
        let dayNumber = CivilZone.dayNumber(year: year, month: month, day: day)
        let roundTrip = CivilZone.civilDate(dayNumber: dayNumber)
        return roundTrip.year == year && roundTrip.month == month && roundTrip.day == day ? dayNumber : nil
    }

    // MARK: - Records actual and forecast

    /// Recorded or corrected work against schedule estimates for one visible
    /// period. A day enters only one side, and actual always wins.
    static func recordsActualForecast(input: NativeRecordsActualForecastInput) -> NativeRecordsActualForecastSummary {
        let asOfMs = input.asOfMs
        let usesFixedMonthlyPay = input.salaryRules?.salaryType == "monthly"
        var fixedMonthlyPay: (actual: Double, forecast: Double)?
        if usesFixedMonthlyPay, let rules = input.salaryRules {
            fixedMonthlyPay = allocateFixedMonthlyPay(dayKeys: input.periodDayKeys, asOfMs: asOfMs, rules: rules)
        }
        var hasSalary = usesFixedMonthlyPay ? fixedMonthlyPay != nil : input.dailySalary != nil
        var actualDays = 0.0
        var actualMs = 0.0
        var actualOvertimeMs = 0.0
        var actualPay = 0.0
        var forecastDays = 0.0
        var forecastMs = 0.0
        var forecastPay = 0.0

        for day in input.days {
            if day.resolvedSegments.isEmpty && day.overtimeSegments.isEmpty { continue }
            let rate = input.dailySalary
            if !usesFixedMonthlyPay && rate == nil { hasSalary = false }
            let plannedMs = mergedDuration(day.plannedSegments)
            let kind = day.actualKind
            guard kind == "corrected" || kind == "observed" || kind == "scheduled" else {
                let forecastWorkMs = mergedDuration(day.resolvedSegments)
                guard forecastWorkMs > 0 else { continue }
                forecastDays += 1
                forecastMs += forecastWorkMs
                if !usesFixedMonthlyPay { forecastPay += rate ?? 0 }
                continue
            }
            let regular = kind != "observed"
                ? day.resolvedSegments
                : intersect(observedWorkSegments(day.observations, asOfMs: asOfMs, closesOpen: day.isActiveAnchor), day.resolvedSegments)
            let elapsedRegular = regular.map { NativeShiftSegment(startAtMs: $0.startAtMs, endAtMs: min($0.endAtMs, asOfMs)) }
            let elapsedOvertime = day.overtimeSegments.map { NativeShiftSegment(startAtMs: $0.startAtMs, endAtMs: min($0.endAtMs, asOfMs)) }
            let workedMs = mergedDuration(elapsedRegular + elapsedOvertime)
            actualOvertimeMs += max(0, workedMs - mergedDuration(elapsedRegular))
            if workedMs > 0 {
                actualDays += 1
                actualMs += workedMs
                if !usesFixedMonthlyPay {
                    actualPay += (rate ?? 0) * (plannedMs > 0 ? workedMs / plannedMs : 1)
                }
            }
            if day.isActiveAnchor || kind == "scheduled" {
                let futureMs = mergedDuration((day.resolvedSegments + day.overtimeSegments).map {
                    NativeShiftSegment(startAtMs: max($0.startAtMs, asOfMs), endAtMs: $0.endAtMs)
                })
                if futureMs > 0 {
                    if workedMs <= 0 { forecastDays += 1 }
                    forecastMs += futureMs
                    if !usesFixedMonthlyPay {
                        forecastPay += (rate ?? 0) * (plannedMs > 0 ? futureMs / plannedMs : (workedMs <= 0 ? 1 : 0))
                    }
                }
            }
        }

        if let fixedMonthlyPay {
            actualPay = fixedMonthlyPay.actual
            forecastPay = fixedMonthlyPay.forecast
        }
        // Built in steps: as one expression, older Swift compilers give up on
        // type-checking it in reasonable time.
        let msPerHour = 3_600_000.0
        let actualEarnings: Double? = hasSalary ? actualPay : nil
        let forecastEarnings: Double? = hasSalary ? forecastPay : nil
        var totalEarnings: Double?
        if let actualEarnings, let forecastEarnings {
            totalEarnings = actualEarnings + forecastEarnings
        }
        let actual = NativeRecordsActualForecastPart(days: actualDays, hours: actualMs / msPerHour, earnings: actualEarnings)
        let forecast = NativeRecordsActualForecastPart(days: forecastDays, hours: forecastMs / msPerHour, earnings: forecastEarnings)
        let totalMs: Double = actualMs + forecastMs
        let total = NativeRecordsActualForecastPart(days: actualDays + forecastDays, hours: totalMs / msPerHour, earnings: totalEarnings)
        return NativeRecordsActualForecastSummary(
            actualOvertimeHours: actualOvertimeMs / msPerHour,
            actual: actual,
            forecast: forecast,
            total: total
        )
    }

    /// A monthly salary spread over the visible days, each day taking its own
    /// month's share, split at the civil day containing `asOfMs`.
    private static func allocateFixedMonthlyPay(
        dayKeys: [String],
        asOfMs: Double,
        rules: NativeRulesInput
    ) -> (actual: Double, forecast: Double)? {
        guard asOfMs.isFinite,
              let monthlySalary = monthlyEquivalent(
                amount: rules.salaryAmount,
                type: "monthly",
                monthlyWorkingDays: rules.monthlyWorkingDays,
                annualBonusMonths: rules.annualBonusMonths
              )
        else { return nil }
        let asOfDay = CivilZone(identifier: rules.timeZoneIdentifier).civil(asOfMs).dayNumber
        var seen = Set<String>()
        var actual = 0.0
        var forecast = 0.0
        for key in dayKeys where seen.insert(key).inserted {
            guard let day = civilDayNumber(key) else { continue }
            let (year, month, _) = CivilZone.civilDate(dayNumber: day)
            let nextMonth = month == 12
                ? CivilZone.dayNumber(year: year + 1, month: 1, day: 1)
                : CivilZone.dayNumber(year: year, month: month + 1, day: 1)
            let daysInMonth = Double(nextMonth - CivilZone.dayNumber(year: year, month: month, day: 1))
            if day <= asOfDay {
                actual += monthlySalary / daysInMonth
            } else {
                forecast += monthlySalary / daysInMonth
            }
        }
        return (actual, forecast)
    }

    /// Total length of the union of `segments`; empty and non-finite ones are ignored.
    private static func mergedDuration(_ segments: [NativeShiftSegment]) -> Double {
        let sorted = segments
            .filter { $0.startAtMs.isFinite && $0.endAtMs.isFinite && $0.endAtMs > $0.startAtMs }
            .enumerated()
            .sorted { left, right in
                if left.element.startAtMs != right.element.startAtMs { return left.element.startAtMs < right.element.startAtMs }
                if left.element.endAtMs != right.element.endAtMs { return left.element.endAtMs < right.element.endAtMs }
                return left.offset < right.offset
            }
            .map(\.element)
        var total = 0.0
        var current: (start: Double, end: Double)?
        for segment in sorted {
            if let open = current, segment.startAtMs <= open.end {
                current = (open.start, max(open.end, segment.endAtMs))
            } else {
                if let open = current { total += open.end - open.start }
                current = (segment.startAtMs, segment.endAtMs)
            }
        }
        guard let open = current else { return total }
        return total + open.end - open.start
    }

    private static func intersect(_ left: [NativeShiftSegment], _ right: [NativeShiftSegment]) -> [NativeShiftSegment] {
        left.flatMap { first in
            right.compactMap { second in
                let startAtMs = max(first.startAtMs, second.startAtMs)
                let endAtMs = min(first.endAtMs, second.endAtMs)
                return endAtMs > startAtMs ? NativeShiftSegment(startAtMs: startAtMs, endAtMs: endAtMs) : nil
            }
        }
    }

    /// Started/stopped pairs as intervals. An unmatched start is closed at
    /// `asOfMs` only for the day that owns the running shift.
    private static func observedWorkSegments(
        _ observations: [NativeRecordsSummaryObservation],
        asOfMs: Double,
        closesOpen: Bool
    ) -> [NativeShiftSegment] {
        let sorted = observations
            .filter { $0.occurredAtMs.isFinite }
            .enumerated()
            .sorted { $0.element.occurredAtMs != $1.element.occurredAtMs ? $0.element.occurredAtMs < $1.element.occurredAtMs : $0.offset < $1.offset }
            .map(\.element)
        var result: [NativeShiftSegment] = []
        var startedAt: Double?
        for observation in sorted {
            if observation.kind == "started" {
                if startedAt == nil { startedAt = observation.occurredAtMs }
            } else if let start = startedAt {
                if observation.occurredAtMs > start {
                    result.append(NativeShiftSegment(startAtMs: start, endAtMs: observation.occurredAtMs))
                }
                startedAt = nil
            }
        }
        if let start = startedAt, closesOpen, asOfMs.isFinite, asOfMs > start {
            result.append(NativeShiftSegment(startAtMs: start, endAtMs: asOfMs))
        }
        return result
    }
}

extension CivilZone {
    /// Civil midnight on 1 January of the year containing `ms` (`zonedYearStartMs`).
    nonisolated func yearStartMs(_ ms: Double) -> Double {
        utcMs(dayNumber: Self.dayNumber(year: civil(ms).year, month: 1, day: 1), Clock(hour: 0, minute: 0))
    }
}

nonisolated struct NativePeriodSummary: Codable, Hashable, Sendable {
    let days: Double
    let hours: Double
    let earnings: Double?
}

nonisolated struct NativeSummaryInput: Codable, Sendable {
    let period: String
    /// Explicit window start, winning over `period`. The Records tab draws its
    /// week and month grids with the locale's own first weekday, so it must
    /// summarise the boundary it already drew rather than the ISO week the
    /// period name derives. Omitted for the timer's own week/year rows.
    var periodStartMs: Double? = nil
    let asOfMs: Double
    let workdays: [Int]
    let schedule: NativeWorkSchedule
    let currentShiftStartMs: Double
    let currentShiftEndMs: Double
    let plannedDailyHours: Double
    let todayProgress: Double
    let dailySalary: Double?
    let todayEffectiveHours: Double
    let todayPayRatio: Double
    var timeZoneIdentifier: String? = nil
}

nonisolated struct NativeLifetimeIncomeSummary: Codable, Hashable, Sendable {
    let historicalGross: Double
    let projectedGross: Double
    let totalGross: Double
}

nonisolated struct NativeLifetimeIncomePeriod: Codable, Sendable {
    let startsOn: String
    let endsOn: String?
    let salaryAmount: Double
    let salaryCadence: String
}

nonisolated struct NativeLifetimeIncomeSalary: Codable, Sendable {
    let salaryAmount: Double
    let salaryCadence: String
    let startsOn: String?
}

nonisolated struct NativeLifetimeIncomeDecline: Codable, Sendable {
    let startsOn: String
    let retirementRatio: Double
}

nonisolated struct NativeLifetimeIncomeInput: Codable, Sendable {
    let periods: [NativeLifetimeIncomePeriod]
    let currentSalary: NativeLifetimeIncomeSalary?
    let futureIncomeDecline: NativeLifetimeIncomeDecline?
    let asOf: String
    let retirementOn: String
}

nonisolated struct NativeRecordsActualForecastDay: Codable, Sendable {
    var dayKey: String? = nil
    let actualKind: String?
    let resolvedSegments: [NativeShiftSegment]
    let plannedSegments: [NativeShiftSegment]
    let overtimeSegments: [NativeShiftSegment]
    let observations: [NativeRecordsSummaryObservation]
    let isActiveAnchor: Bool
}

nonisolated struct NativeRecordsSummaryObservation: Codable, Sendable {
    let kind: String
    let occurredAtMs: Double
}

nonisolated struct NativeRecordsActualForecastInput: Codable, Sendable {
    let days: [NativeRecordsActualForecastDay]
    let periodDayKeys: [String]
    let dailySalary: Double?
    let asOfMs: Double
    var salaryRules: NativeRulesInput? = nil
}

nonisolated struct NativeRecordsActualForecastPart: Codable, Hashable, Sendable {
    let days: Double
    let hours: Double
    let earnings: Double?
}

nonisolated struct NativeRecordsActualForecastSummary: Codable, Hashable, Sendable {
    let actualOvertimeHours: Double
    let actual: NativeRecordsActualForecastPart
    let forecast: NativeRecordsActualForecastPart
    let total: NativeRecordsActualForecastPart
}
