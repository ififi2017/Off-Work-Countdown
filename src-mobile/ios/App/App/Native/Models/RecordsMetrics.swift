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

/// Facts captured when the user extends a shift. `plannedEndAtMs` was added
/// after the first 002 build; decoding keeps it optional so existing archives
/// remain readable. Legacy observations fall back to the base schedule
/// expansion for their civil day and are ignored if that fact is unavailable.
struct OvertimeDeclarationPayload: Codable, Equatable, Sendable {
    var overtimeEndAtMs: Double
    var plannedEndAtMs: Double?
}

enum RecordsMetrics {
    static func summarize(
        days: [DayResolution],
        observations: [WorkObservation],
        sleepHours: Double,
        dailySalary: Double,
        salaryEnabled: Bool,
        asOf: Date,
        calendar: Calendar
    ) -> RecordsPeriodMetrics {
        let workDays = days.filter { $0.isScheduledWorkday && !$0.segments.isEmpty }
        let workDuration = workDays.reduce(Int64(0)) { partial, day in
            partial + day.segments.reduce(Int64(0)) { $0 + Int64($1.endAtMs - $1.startAtMs) }
        }
        var daysByKey: [String: DayResolution] = [:]
        for day in days {
            daysByKey[day.dayKey] = day
        }
        let declaredFromValues = observations.reduce(Int64(0)) { partial, item in
            let dayKey = RecordJSON.dayKey(item.shiftAnchorDate, calendar: calendar)
            guard let day = daysByKey[dayKey],
                  let segment = declaredOvertimeSegment(
                    observation: item,
                    day: day,
                    avoidingRegularWork: false
                  )
            else { return partial }
            let duration = segment.endAtMs - segment.startAtMs
            guard duration <= Double(Int64.max) else { return partial }
            let milliseconds = Int64(duration.rounded(.towardZero))
            let (sum, overflow) = partial.addingReportingOverflow(milliseconds)
            return overflow ? partial : sum
        }
        let overtimeMs = declaredFromValues
        let sleepMsPerDay = Int64(max(0, sleepHours) * 3_600_000)
        let dayLengths = days.map { civilDayLengthMs(for: $0, calendar: calendar) }
        let totalDayMs = dayLengths.reduce(Int64(0), +)
        let awakeMs = dayLengths.reduce(Int64(0)) { partial, dayLength in
            partial + max(0, dayLength - sleepMsPerDay)
        }
        let shareOfDay = totalDayMs == 0 ? 0 : Double(workDuration) / Double(totalDayMs)
        let shareOfAwake = awakeMs == 0 ? 0 : Double(workDuration) / Double(awakeMs)
        let ownAwake = max(0, awakeMs - workDuration)
        let today = calendar.startOfDay(for: asOf)
        let completedScheduledDays = days.filter { day in
            guard day.baseScheduleIsWorkday else { return false }
            return civilDayStart(for: day, calendar: calendar) < today
        }
        return RecordsPeriodMetrics(
            workdayCount: workDays.count,
            workDurationMs: workDuration,
            declaredOvertimeMs: overtimeMs,
            shareOfDay: shareOfDay,
            shareOfAwake: min(1, max(0, shareOfAwake)),
            longestStreak: longestStreak(in: days),
            ownAwakeMs: ownAwake,
            estimatedIncome: salaryEnabled ? Double(completedScheduledDays.count) * dailySalary : 0,
            usesCurrentSalary: salaryEnabled
        )
    }

    /// Resolves an immutable overtime declaration without treating the moment
    /// the user tapped Save as the beginning of overtime.
    static func declaredOvertimeSegment(
        observation: WorkObservation,
        day: DayResolution,
        avoidingRegularWork: Bool
    ) -> NativeShiftSegment? {
        guard observation.kind == .overtimeDeclared,
              let data = observation.valueData,
              let payload = try? JSONDecoder().decode(OvertimeDeclarationPayload.self, from: data)
        else { return nil }
        let legacyPlannedEnd = day.baseScheduleSegments.map(\.endAtMs).max()
        guard var start = payload.plannedEndAtMs ?? legacyPlannedEnd else { return nil }
        if avoidingRegularWork, let regularEnd = day.segments.map(\.endAtMs).max() {
            start = max(start, regularEnd)
        }
        guard start.isFinite,
              payload.overtimeEndAtMs.isFinite,
              payload.overtimeEndAtMs > start
        else { return nil }
        return NativeShiftSegment(startAtMs: start, endAtMs: payload.overtimeEndAtMs)
    }

    private static func civilDayStart(for day: DayResolution, calendar: Calendar) -> Date {
        let date = RecordJSON.date(fromDayKey: day.dayKey, calendar: calendar)
            ?? day.shiftAnchorDate
        return calendar.startOfDay(for: date)
    }

    private static func civilDayLengthMs(for day: DayResolution, calendar: Calendar) -> Int64 {
        let start = civilDayStart(for: day, calendar: calendar)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return Int64((next.timeIntervalSince(start) * 1_000).rounded())
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
