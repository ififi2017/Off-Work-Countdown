import Foundation

/// Presentation geometry only. Day kinds still come from the planner's
/// resolved schedule, never from an assumed Saturday/Sunday weekend.
nonisolated struct LeavePlanCalendarPage: Equatable {
    let firstDayNumber: Int
    let days: [Int]
    let month: Int
    let year: Int

    init(containing dayNumber: Int, firstWeekday: Int) {
        let date = CivilZone.civilDate(dayNumber: dayNumber)
        year = date.year
        month = date.month
        firstDayNumber = CivilZone.dayNumber(year: date.year, month: date.month, day: 1)
        let weekday = ((firstDayNumber + 4) % 7 + 7) % 7
        let leading = (weekday - (firstWeekday - 1) + 7) % 7
        let start = firstDayNumber - leading
        // Six stable rows prevent the controls jumping between months.
        days = Array(start..<(start + 42))
    }

    func contains(_ day: Int) -> Bool {
        let date = CivilZone.civilDate(dayNumber: day)
        return date.year == year && date.month == month
    }

    static func coverage(of proposal: LeavePlanProposal) -> ClosedRange<Int> {
        let first = min(proposal.firstRestDayNumber, proposal.items.map(\.dayNumber).min() ?? proposal.firstRestDayNumber)
        let last = max(proposal.lastRestDayNumber, proposal.items.map(\.dayNumber).max() ?? proposal.lastRestDayNumber)
        return first...last
    }

    static func months(for proposal: LeavePlanProposal) -> [Int] {
        let coverage = coverage(of: proposal)
        let first = CivilZone.civilDate(dayNumber: coverage.lowerBound)
        let last = CivilZone.civilDate(dayNumber: coverage.upperBound)
        let count = (last.year - first.year) * 12 + last.month - first.month
        return (0...count).map { offset in
            let index = first.year * 12 + first.month - 1 + offset
            return CivilZone.dayNumber(year: index / 12, month: index % 12 + 1, day: 1)
        }
    }
}
