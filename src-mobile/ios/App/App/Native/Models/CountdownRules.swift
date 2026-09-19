import Foundation

nonisolated struct NativeShiftSnapshot: Codable, Hashable, Sendable {
    let segments: [NativeShiftSegment]
    let startAtMs: Double
    let endAtMs: Double
    let plannedEndAtMs: Double
    let overtimeEndAtMs: Double?
    let durationMs: Double
    let plannedDurationMs: Double
    let elapsedMs: Double
    let remainingMs: Double
    let progress: Double
    let payRatio: Double
    let activeBreakEndAtMs: Double?
    let isWorkday: Bool
    let nextRestAtMs: Double?
    let dailySalary: Double?
    let earnedSoFar: Double?
    let nextShiftStartAtMs: Double?
    let nextShiftEndAtMs: Double?
    let countdownTargetAtMs: Double?
    let countdownAnchorAtMs: Double?
    let countdownProgress: Double

    var startDate: Date { Date(timeIntervalSince1970: startAtMs / 1_000) }
    var endDate: Date { Date(timeIntervalSince1970: endAtMs / 1_000) }
    var plannedEndDate: Date { Date(timeIntervalSince1970: plannedEndAtMs / 1_000) }
    var overtimeEndDate: Date? { overtimeEndAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) } }
    var activeBreakEndDate: Date? { activeBreakEndAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) } }
    var nextRestDate: Date? { nextRestAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) } }
    var nextShiftStartDate: Date? { nextShiftStartAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) } }
    var nextShiftEndDate: Date? { nextShiftEndAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) } }

    func isBeforeStart(at now: Date) -> Bool {
        now.timeIntervalSince1970 * 1_000 < startAtMs
    }

    var isOnBreak: Bool { activeBreakEndAtMs != nil }

    func isOvertimeActive(at now: Date) -> Bool {
        overtimeEndAtMs != nil && now.timeIntervalSince1970 * 1_000 >= plannedEndAtMs
    }

    /// Remaining time the shared running surfaces count. Before clock-in this is
    /// time until start; during a break it is time until the break ends;
    /// otherwise it is effective shift remaining.
    func heroRemainingMs(at now: Date) -> Double {
        let nowMs = now.timeIntervalSince1970 * 1_000
        if nowMs < startAtMs { return max(0, startAtMs - nowMs) }
        if let breakEnd = activeBreakEndAtMs { return max(0, breakEnd - nowMs) }
        return remainingMs
    }

    /// Next-shift and next-rest come from `source`. Current-shift figures stay.
    func withProjectedFuture(from source: NativeShiftSnapshot) -> NativeShiftSnapshot {
        let countsToCurrentStart = countdownTargetAtMs == startAtMs
        let restAtMs: Double?
        if let candidate = source.nextRestAtMs {
            let endDay = Calendar.current.startOfDay(for: endDate)
            let afterEndDay = Calendar.current.date(byAdding: .day, value: 1, to: endDay)
                .map { $0.timeIntervalSince1970 * 1_000 } ?? endAtMs
            restAtMs = candidate >= afterEndDay ? candidate : nextRestAtMs
        } else {
            restAtMs = nextRestAtMs
        }
        return NativeShiftSnapshot(
            segments: segments,
            startAtMs: startAtMs,
            endAtMs: endAtMs,
            plannedEndAtMs: plannedEndAtMs,
            overtimeEndAtMs: overtimeEndAtMs,
            durationMs: durationMs,
            plannedDurationMs: plannedDurationMs,
            elapsedMs: elapsedMs,
            remainingMs: remainingMs,
            progress: progress,
            payRatio: payRatio,
            activeBreakEndAtMs: activeBreakEndAtMs,
            isWorkday: isWorkday,
            nextRestAtMs: restAtMs,
            dailySalary: dailySalary,
            earnedSoFar: earnedSoFar,
            nextShiftStartAtMs: source.nextShiftStartAtMs,
            nextShiftEndAtMs: source.nextShiftEndAtMs,
            countdownTargetAtMs: countsToCurrentStart
                ? countdownTargetAtMs
                : source.countdownTargetAtMs,
            countdownAnchorAtMs: countsToCurrentStart
                ? countdownAnchorAtMs
                : source.countdownAnchorAtMs,
            countdownProgress: countsToCurrentStart
                ? countdownProgress
                : source.countdownProgress
        )
    }
}

/// One calendar day's planned hours from `ScheduleRules.expandScheduleRange`.
/// Rest days still carry segments so a makeup-day exception can reuse them.
nonisolated struct NativeScheduleDayExpansion: Codable, Hashable, Sendable {
    let dayKey: String
    let shiftAnchorStartAtMs: Double
    let isWorkday: Bool
    let segments: [NativeShiftSegment]
}

/// Salary-free absolute shift for WidgetKit, from `ScheduleRules.widgetShifts`.
nonisolated struct NativeWidgetShiftSnapshot: Codable, Hashable, Sendable {
    let segments: [NativeShiftSegment]
    let startAtMs: Double
    let endAtMs: Double
    let plannedEndAtMs: Double
    let overtimeEndAtMs: Double?
    let durationMs: Double
    let countdownAnchorAtMs: Double
}

nonisolated struct NativeRulesInput: Codable, Equatable, Sendable {
    let startTime: String
    let endTime: String
    let nowMs: Double
    let workdays: [Int]
    let schedule: NativeWorkSchedule
    let breakStartTime: String?
    let breakDurationMinutes: Int
    let overtimeEndAtMs: Double?
    let salaryAmount: String
    let salaryType: String
    let monthlyWorkingDays: Double
    let annualBonusMonths: Double
    let forcedWorkdayStartMs: Double?
    var timeZoneIdentifier: String? = nil
    /// Plan 018 P8's extended schedule, when the user has one switched on.
    /// `nil` keeps every rule on the fixed-hours path it took before.
    var extendedSchedule: ExtendedSchedulePlan? = nil
}

nonisolated extension NativeRulesInput {
    var scheduleInput: ScheduleRuleInput {
        ScheduleRuleInput(startTime: startTime, endTime: endTime, nowMs: nowMs,
                          workdays: workdays, schedule: schedule, breakStartTime: breakStartTime,
                          breakDurationMinutes: breakDurationMinutes, overtimeEndAtMs: overtimeEndAtMs,
                          forcedWorkdayStartMs: forcedWorkdayStartMs, timeZoneIdentifier: timeZoneIdentifier,
                          extendedSchedule: extendedSchedule)
    }
}
