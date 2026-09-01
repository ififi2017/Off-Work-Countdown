import Foundation

nonisolated struct ScheduleCycleDay: Equatable, Sendable {
    var dayKey: String
    var isWorkday: Bool
    var workMs: Int64
    var overtimeMs: Int64
    var isComplete: Bool = true
}

nonisolated struct ScheduleCycleSummary: Equatable, Sendable {
    var workdayCount: Int
    var workMs: Int64
    var overtimeMs: Int64
}

nonisolated enum ScheduleCycleSummaryCalculator {
    /// A cycle is the contiguous run of resolved workdays immediately before a
    /// resolved rest day. Calendar exceptions and manual edits have already
    /// won before this projection reaches the calculator.
    static func summary(
        endingAt dayKey: String,
        in days: [ScheduleCycleDay]
    ) -> ScheduleCycleSummary? {
        guard let endIndex = days.firstIndex(where: { $0.dayKey == dayKey }),
              days.indices.contains(endIndex + 1),
              days[endIndex].isWorkday,
              days[endIndex + 1].isComplete,
              !days[endIndex + 1].isWorkday
        else { return nil }

        var startIndex = endIndex
        while startIndex > days.startIndex, days[startIndex - 1].isWorkday {
            startIndex -= 1
        }
        let cycle = days[startIndex...endIndex]
        guard cycle.allSatisfy(\.isComplete) else { return nil }
        return ScheduleCycleSummary(
            workdayCount: cycle.count,
            workMs: cycle.reduce(0) { $0 + $1.workMs },
            overtimeMs: cycle.reduce(0) { $0 + $1.overtimeMs }
        )
    }
}
