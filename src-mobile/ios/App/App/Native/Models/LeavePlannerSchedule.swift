import Foundation

/// Feeds `LeavePlanner` from the schedule the rest of the app already uses,
/// and owns the rolling planning year (plan 020 §2).
///
/// Days come from `ScheduleRules.expandScheduleRange`, so the planner sees the
/// same shifts as the countdown, reminders and Watch: the cycle rule, days set
/// by hand, bundled holidays and makeup workdays. No second schedule or
/// holiday algorithm lives here; this only labels where each day came from.
nonisolated enum LeavePlannerSchedule {
    /// Days resolved either side of a search range, for the overnight shift
    /// running into its first day and the shifts that bound a break.
    static let contextDays = 31

    /// Today through the day before the same date a calendar year later —
    /// the half-open "today to today plus one year" window, in `calendar`'s
    /// zone. 2026-09-27 gives 2026-09-27…2027-09-26; 2028-02-29 ends on
    /// 2029-02-27, since a calendar year from it lands on 2029-02-28.
    static func rollingYear(containing date: Date, calendar: Calendar) -> ClosedRange<Int>? {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .year, value: 1, to: start),
              let first = dayNumber(of: start, calendar: calendar),
              let limit = dayNumber(of: end, calendar: calendar),
              limit > first
        else { return nil }
        return first...(limit - 1)
    }

    static func dayNumber(of date: Date, calendar: Calendar) -> Int? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return CivilZone.dayNumber(year: year, month: month, day: day)
    }

    /// `range` plus `contextDays` either side, resolved under `configuration`.
    /// Attach the live extended schedule first (`RecordCoordinator`'s
    /// expandable hours): without it the days follow the fixed hours alone.
    static func days(
        configuration: ScheduleHoursConfiguration,
        range: ClosedRange<Int>,
        timeZone: TimeZone,
        holidayCoverage: (_ year: Int, _ region: String) -> Bool = {
            HolidayCalendar.shared.covers(year: $0, regionIdentifier: $1)
        },
        holidayEstimation: (_ year: Int, _ region: String) -> Bool = {
            HolidayCalendar.shared.isEstimated(year: $0, regionIdentifier: $1)
        }
    ) -> [LeavePlannerDay] {
        let zone = CivilZone(timeZone: timeZone)
        let firstDay = range.lowerBound - contextDays
        let lastDay = range.upperBound + contextDays
        func noon(_ dayNumber: Int) -> Date {
            Date(timeIntervalSince1970: zone.utcMs(dayNumber: dayNumber, Clock(hour: 12, minute: 0)) / 1_000)
        }
        let expanded = ScheduleRules.expandScheduleRange(
            configuration: configuration, from: noon(firstDay), through: noon(lastDay), timeZone: timeZone
        )
        guard expanded.count == lastDay - firstDay + 1 else { return [] }

        let plan = configuration.extendedSchedule
        let resolver = plan.map(ExtendedScheduleResolver.init(plan:))
        let region = plan.flatMap { $0.fallsBackToBaseSchedule ? nil : $0.holidayRegionIdentifier }
            .flatMap { $0.isEmpty ? nil : $0 }

        return expanded.enumerated().map { offset, expansion in
            let dayNumber = firstDay + offset
            let source = resolver?.day(dayNumber: dayNumber).source
            var caveats: Set<LeavePlannerCaveat> = []
            switch source {
            case .carriedOver: caveats.insert(.carriedOverRoster)
            // A fallback plan (leave over the fixed hours) leaves such a day
            // to the fixed schedule: known, not unassigned.
            case .unassigned where plan?.fallsBackToBaseSchedule != true: caveats.insert(.unassigned)
            default: break
            }
            if let region {
                let year = CivilZone.civilDate(dayNumber: dayNumber).year
                if holidayEstimation(year, region) { caveats.insert(.holidaysEstimated(year: year)) }
                else if source != .handSet, !holidayCoverage(year, region) {
                    caveats.insert(.holidaysNotIncluded(year: year))
                }
            }
            return LeavePlannerDay(
                dayNumber: dayNumber,
                dayKey: expansion.dayKey,
                startAtMs: zone.utcMs(dayNumber: dayNumber, Clock(hour: 0, minute: 0)),
                endAtMs: zone.utcMs(dayNumber: dayNumber + 1, Clock(hour: 0, minute: 0)),
                segments: expansion.isWorkday ? expansion.segments : [],
                isHoliday: source == .holiday && !expansion.isWorkday,
                caveats: caveats
            )
        }
    }
}
