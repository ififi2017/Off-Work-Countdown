import Foundation

/// The submitted conditions belonging to one result set, never live balances.
nonisolated struct LeavePlanSearchContext: Equatable, Sendable {
    let goal: LeavePlanner.Goal
    let availableHalfDays: Int
    let fromDayNumber: Int
    let throughDayNumber: Int
}
