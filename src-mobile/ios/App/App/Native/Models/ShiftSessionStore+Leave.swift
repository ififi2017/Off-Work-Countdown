import Foundation

/// What the leave pages read (plan 020 §2): the rolling planning year, the
/// schedule the planner searches and what each balance has left.
extension ShiftSessionStore {
    /// One leave plan request.
    struct LeavePlanRequest: Equatable, Sendable {
        var goal: LeavePlanner.Goal
        var fromDayNumber: Int
        var throughDayNumber: Int
        var budgetIDs: [UUID]
    }

    /// Today through the day before the same date next year, in the records
    /// calendar.
    func leavePlanningWindow(at date: Date = .now) -> ClosedRange<Int>? {
        LeavePlannerSchedule.rollingYear(containing: date, calendar: preferences.recordsCalendar)
    }

    /// The schedule the planner searches: the one the countdown follows, with
    /// leave already adopted, so planned days are never planned twice.
    func leavePlannerConfiguration(at date: Date = .now) -> ScheduleHoursConfiguration {
        var configuration = session.hoursConfiguration(at: date)
        configuration.extendedSchedule = preferences.extendedSchedulePlan(
            configuration.extendedSchedule,
            applyingLeaveOver: ExtendedScheduleDayHours(
                startTime: configuration.startTime,
                endTime: configuration.endTime,
                breakStartTime: configuration.breakStartTime,
                breakDurationMinutes: configuration.breakDurationMinutes
            )
        )
        return configuration
    }

    /// Each valid balance with what is left after adopted leave.
    var leaveBudgets: [LeaveBudget] {
        LeaveAdoption.budgets(balances: records.state.leaveBalances, leaveDays: records.state.leaveDays)
    }

    func availableLeaveHalfDays(for balance: LeaveBalance) -> Int {
        leaveBudgets.first { $0.id == balance.id }?.availableHalfDays ?? 0
    }

    /// Adopted plans, newest-first by their first day, with the days each wrote.
    var adoptedLeavePlans: [(id: UUID, days: [LeaveDay])] {
        Dictionary(grouping: records.state.leaveDays.filter { $0.planID != nil }, by: { $0.planID! })
            .map { (id: $0.key, days: $0.value.sorted { $0.dayKey < $1.dayKey }) }
            .sorted { ($0.days.first?.dayKey ?? "") > ($1.days.first?.dayKey ?? "") }
    }

    /// Years inside `range` whose mainland China holidays this build does not
    /// carry yet, when the schedule follows that calendar. Those years are
    /// planned on the ordinary schedule and the page says so.
    func missingMainlandHolidayYears(in range: ClosedRange<Int>) -> [Int] {
        guard preferences.isExtendedScheduleEnabled,
              preferences.extendedScheduleContent?.holidayRegionIdentifier == "CN"
        else { return [] }
        let first = CivilZone.civilDate(dayNumber: range.lowerBound).year
        let last = CivilZone.civilDate(dayNumber: range.upperBound).year
        return (first...last).filter { !HolidayCalendar.shared.covers(year: $0, regionIdentifier: "CN") }
    }

    /// Runs the search off the main actor; a year of days takes tens of
    /// milliseconds, which a sheet should not stall on.
    func findLeavePlans(_ request: LeavePlanRequest, at date: Date = .now) async -> [LeavePlanProposal] {
        let configuration = leavePlannerConfiguration(at: date)
        let timeZone = preferences.recordsTimeZone
        let budgets = leaveBudgets.filter { request.budgetIDs.contains($0.id) && $0.availableHalfDays > 0 }
        let nowMs = date.timeIntervalSince1970 * 1_000
        return await Task.detached(priority: .userInitiated) {
            let days = LeavePlannerSchedule.days(
                configuration: configuration,
                range: request.fromDayNumber...request.throughDayNumber,
                timeZone: timeZone
            )
            return LeavePlanner.proposals(days: days, query: .init(
                goal: request.goal,
                fromDayNumber: request.fromDayNumber,
                throughDayNumber: request.throughDayNumber,
                nowMs: nowMs,
                budgets: budgets
            ))
        }.value
    }
}
