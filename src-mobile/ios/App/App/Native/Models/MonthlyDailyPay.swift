import Foundation

/// The figures behind the "Daily pay by month" page (plan 024).
///
/// Nothing here is a formula of its own: each month's count and daily pay come
/// from `SummaryRules.scheduledWorkdaysInMonth` and `SalaryRules.dailySalary`,
/// the same calls the timer's snapshot and the Records summary make, and each
/// calendar day asks `scheduledWorkdayCount` about itself. A page that counted
/// weekdays on its own would drift from the pay the timer shows.
nonisolated struct MonthlyDailyPay: Equatable, Sendable {
    struct Day: Equatable, Sendable, Identifiable {
        /// Day of the month, 1-based.
        let id: Int
        let isWorkday: Bool
        let isToday: Bool
    }

    struct Month: Equatable, Sendable, Identifiable {
        /// `YYYY-MM`.
        let id: String
        let startMs: Double
        let workdayCount: Int
        /// `nil` when the salary settings give no daily pay.
        let dailyPay: Double?
    }

    let timeZone: TimeZone
    let current: Month
    /// The days of `current`, in order.
    let days: [Day]
    /// Empty cells before day 1 so the grid starts on `firstWeekday`.
    let leadingBlanks: Int
    /// The three months after `current`.
    let upcoming: [Month]
    /// The monthly gross `current.dailyPay` divides: nominal pay plus its bonus share.
    let monthlyAmount: Double?

    /// Scheduled workdays in the civil month containing `now`, whatever the
    /// basis is set to: the count the "by monthly schedule" menu option offers.
    static func scheduledWorkdaysThisMonth(rules input: NativeRulesInput, now: Date) -> Int {
        let zone = CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
        return zone.scheduledWorkdaysInMonth(
            anchorMs: now.timeIntervalSince1970 * 1_000, workdays: input.workdays, schedule: input.schedule
        )
    }

    /// `nil` unless the salary is monthly and set to the scheduled-month basis.
    /// - Parameter firstWeekday: 1 for Sunday … 7 for Saturday, as `Calendar` uses.
    static func make(rules input: NativeRulesInput, now: Date, firstWeekday: Int) -> MonthlyDailyPay? {
        guard input.usesScheduledMonthBasis else { return nil }
        let zone = CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
        let nowMs = now.timeIntervalSince1970 * 1_000

        func month(offset: Int) -> Month {
            let startMs = zone.monthStartMs(nowMs, offset: offset)
            let start = zone.civil(startMs)
            return Month(
                id: String(format: "%04d-%02d", start.year, start.month),
                startMs: startMs,
                workdayCount: zone.scheduledWorkdaysInMonth(
                    anchorMs: startMs, workdays: input.workdays, schedule: input.schedule
                ),
                dailyPay: SalaryRules.dailySalary(rules: input, anchorMs: startMs, zone)
            )
        }

        let current = month(offset: 0)
        let first = zone.civil(current.startMs)
        let next = zone.civil(zone.monthStartMs(nowMs, offset: 1))
        let today = zone.civil(nowMs).dayNumber
        let days = (0..<max(0, next.dayNumber - first.dayNumber)).map { index -> Day in
            let dayNumber = first.dayNumber + index
            let startMs = zone.utcMs(dayNumber: dayNumber, Clock(hour: 0, minute: 0))
            let endMs = zone.utcMs(dayNumber: dayNumber + 1, Clock(hour: 0, minute: 0))
            return Day(
                id: index + 1,
                isWorkday: zone.scheduledWorkdayCount(
                    fromMs: startMs, toMs: endMs, workdays: input.workdays, schedule: input.schedule
                ) > 0,
                isToday: dayNumber == today
            )
        }
        return MonthlyDailyPay(
            timeZone: zone.timeZone,
            current: current,
            days: days,
            leadingBlanks: ((first.weekday - (firstWeekday - 1)) % 7 + 7) % 7,
            upcoming: (1...3).map { month(offset: $0) },
            monthlyAmount: SummaryRules.salaryMonthlyEquivalent(input: input)
        )
    }
}
