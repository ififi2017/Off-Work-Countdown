import Foundation

struct RecordsPeriodMetrics: Equatable, Sendable {
    var workdayCount: Int
    var workDurationMs: Int64
    var declaredOvertimeMs: Int64
    var shareOfDay: Double
    var shareOfAwake: Double
    var longestStreak: Int
    var ownAwakeMs: Int64
    var estimatedIncome: Double
    var usesCurrentSalary: Bool
}

enum RecordsMetrics {
    static func summarize(
        days: [DayResolution],
        observations: [WorkObservation],
        sleepHours: Double,
        dailySalary: Double,
        salaryEnabled: Bool
    ) -> RecordsPeriodMetrics {
        let workDays = days.filter { $0.isScheduledWorkday && !$0.segments.isEmpty }
        let workDuration = workDays.reduce(Int64(0)) { partial, day in
            partial + day.segments.reduce(Int64(0)) { $0 + Int64($1.endAtMs - $1.startAtMs) }
        }
        let declaredFromValues = observations.reduce(Int64(0)) { partial, item in
            guard item.kind == .overtimeDeclared, let data = item.valueData,
                  let payload = try? JSONDecoder().decode([String: Double].self, from: data),
                  let end = payload["overtimeEndAtMs"]
            else { return partial }
            return partial + Int64(max(0, end - item.occurredAt.timeIntervalSince1970 * 1_000))
        }
        let overtimeMs = declaredFromValues
        let dayCount = max(days.count, 1)
        let totalDayMs = Int64(dayCount) * 24 * 3_600_000
        let awakeMs = Int64(Double(dayCount) * max(0, 24 - sleepHours) * 3_600_000)
        let shareOfDay = totalDayMs == 0 ? 0 : Double(workDuration) / Double(totalDayMs)
        let shareOfAwake = awakeMs == 0 ? 0 : Double(workDuration) / Double(awakeMs)
        let ownAwake = max(0, awakeMs - workDuration)
        return RecordsPeriodMetrics(
            workdayCount: workDays.count,
            workDurationMs: workDuration,
            declaredOvertimeMs: overtimeMs,
            shareOfDay: shareOfDay,
            shareOfAwake: min(1, max(0, shareOfAwake)),
            longestStreak: longestStreak(in: days),
            ownAwakeMs: ownAwake,
            estimatedIncome: salaryEnabled ? Double(workDays.count) * dailySalary : 0,
            usesCurrentSalary: salaryEnabled
        )
    }

    static func longestStreak(in days: [DayResolution]) -> Int {
        var best = 0
        var current = 0
        for day in days.sorted(by: { $0.shiftAnchorDate < $1.shiftAnchorDate }) {
            if day.isScheduledWorkday && !day.segments.isEmpty {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }
}
