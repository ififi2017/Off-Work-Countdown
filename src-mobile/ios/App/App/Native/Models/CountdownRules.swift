import Foundation
import JavaScriptCore

nonisolated struct NativeShiftSegment: Codable, Hashable, Sendable {
    let startAtMs: Double
    let endAtMs: Double
}

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

nonisolated struct NativeWatchRulesProjection: Codable, Equatable, Sendable {
    nonisolated struct Shift: Codable, Equatable, Sendable {
        let segments: [NativeShiftSegment]
        let plannedEndAtMs: Double
        let overtimeEndAtMs: Double?
        let finishedAtMs: Double?
        let isRunning: Bool
        let transitions: [Transition]
    }

    nonisolated struct Transition: Codable, Equatable, Sendable {
        let atMs: Double
        let state: String
    }

    nonisolated struct NextShift: Codable, Equatable, Sendable {
        let startAtMs: Double
        let validUntilMs: Double
    }

    let scheduleState: String
    let shift: Shift?
    let nextShift: NextShift?
    let contentExpiresAtMs: Double
}

nonisolated struct NativeWatchCurrentShift: Codable, Sendable {
    let segments: [NativeShiftSegment]
    let plannedEndAtMs: Double
    let overtimeEndAtMs: Double?
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

struct NativePeriodSummary: Codable, Hashable {
    let days: Double
    let hours: Double
    let earnings: Double?
}

struct NativeRecordsIncome: Codable, Hashable {
    let earnings: Double?
}

nonisolated struct NativeLifetimeIncomeSummary: Codable, Hashable, Sendable {
    let historicalGross: Double
    let projectedGross: Double
    let totalGross: Double
}

struct NativeRecordsActualForecastPart: Codable, Hashable, Sendable {
    let days: Double
    let hours: Double
    let earnings: Double?
}

struct NativeRecordsActualForecastSummary: Codable, Hashable, Sendable {
    let actualOvertimeHours: Double
    let actual: NativeRecordsActualForecastPart
    let forecast: NativeRecordsActualForecastPart
    let total: NativeRecordsActualForecastPart
}

struct NativeMonthlySalaryEquivalent: Codable, Hashable, Sendable {
    let amount: Double?
}

nonisolated enum CountdownRulesError: LocalizedError, Sendable {
    case missingResource
    case unavailableRuntime(String)
    /// `rule` names the bundle method that failed. It is deliberately absent
    /// from `errorDescription`: that string is shown to the user, and the
    /// name of a JavaScript function is not something to put in front of them.
    case invalidResult(rule: String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "The shared countdown rules are missing from the app bundle."
        case let .unavailableRuntime(message):
            return message
        case .invalidResult:
            return "The shared countdown rules returned an unreadable snapshot."
        }
    }
}

/// One crossing of the JavaScriptCore boundary.
///
/// Encoding the request, invoking the method and decoding the reply fail in
/// different ways but read as one outcome to the caller, so each rule used to
/// carry its own copy of the same eleven-condition guard.
private func invokeRule<Request: Encodable>(
    _ context: JSContext?,
    _ rule: String,
    _ request: Request
) throws -> JSValue {
    guard let context,
          let bridge = context.objectForKeyedSubscript("OWCNative"),
          !bridge.isUndefined,
          let data = try? JSONEncoder().encode(request),
          let json = String(data: data, encoding: .utf8),
          let result = bridge.invokeMethod(rule, withArguments: [json]),
          !result.isUndefined,
          !result.isNull
    else {
        throw CountdownRulesError.invalidResult(rule: rule)
    }
    return result
}

/// As `invokeRule`, decoding the reply into the type the caller expects.
private func callRule<Request: Encodable, Response: Decodable>(
    _ context: JSContext?,
    _ rule: String,
    _ request: Request
) throws -> Response {
    let result = try invokeRule(context, rule, request)
    guard let output = result.toString()?.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(Response.self, from: output)
    else {
        throw CountdownRulesError.invalidResult(rule: rule)
    }
    return decoded
}

/// As `invokeRule`, for the rules that answer with a plain boolean. A rule
/// that cannot be reached answers `fallback` rather than throwing, because
/// the caller is asking a yes/no question about a settings edit.
private func askRule<Request: Encodable>(
    _ context: JSContext?,
    _ rule: String,
    _ request: Request,
    fallback: Bool
) -> Bool {
    guard let result = try? invokeRule(context, rule, request) else { return fallback }
    return result.toBool()
}

/// The JavaScriptCore bridge for the rules that have not moved to Swift yet:
/// reminders, summaries and income (plan 019 R2 and R3). Shift resolution,
/// snapshots and range expansion are `ScheduleRules`.
@MainActor
final class CountdownRules {
    static let shared = CountdownRules()

    /// Builds the JSContext and evaluates the rules bundle off the first-frame
    /// path, so the first reminder or summary request does not evaluate the
    /// bundle synchronously in the middle of launch.
    static func warmUp() {
        Task { @MainActor in
            // Let the first SwiftUI frame commit before evaluating the generated
            // bundle. JavaScriptCore stays on one explicitly isolated executor.
            await Task.yield()
            _ = CountdownRules.shared
        }
    }

    private let context: JSContext?
    private let loadError: CountdownRulesError?

    private init() {
        let loaded: (JSContext?, CountdownRulesError?) = LaunchTrace.interval("rulesLoad") {
            Self.loadContext()
        }
        context = loaded.0
        loadError = loaded.1
    }

    private static func loadContext() -> (JSContext?, CountdownRulesError?) {
        guard let context = JSContext() else {
            return (nil, .unavailableRuntime("JavaScriptCore could not start."))
        }

        var capturedError: CountdownRulesError?
        context.exceptionHandler = { _, exception in
            if let message = exception?.toString(), !message.isEmpty {
                capturedError = .unavailableRuntime(message)
            }
        }

        guard let url = Bundle.main.url(forResource: "CountdownRules", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            return (nil, .missingResource)
        }

        context.evaluateScript(source)
        return (context, capturedError)
    }

    func reminders(input: NativeRulesInput, reminderInputs: NativeReminderInputs) throws -> [NativeReminder] {
        if let loadError { throw loadError }
        let request = NativeReminderRequest(rules: input, reminderInputs: reminderInputs)
        return try callRule(context, "reminders", request)
    }

    func summarize(input: NativeSummaryInput) throws -> NativePeriodSummary {
        if let loadError { throw loadError }
        return try callRule(context, "summarize", input)
    }

    func recordsIncome(input: NativeRecordsIncomeInput) throws -> NativeRecordsIncome {
        if let loadError { throw loadError }
        return try callRule(context, "recordsIncome", input)
    }

    func lifetimeIncome(input: NativeLifetimeIncomeInput) throws -> NativeLifetimeIncomeSummary {
        if let loadError { throw loadError }
        return try callRule(context, "lifetimeIncome", input)
    }

    func recordsActualForecast(
        input: NativeRecordsActualForecastInput
    ) throws -> NativeRecordsActualForecastSummary {
        if let loadError { throw loadError }
        return try callRule(context, "recordsActualForecast", input)
    }

    func salaryMonthlyEquivalent(input: NativeRulesInput) throws -> NativeMonthlySalaryEquivalent {
        if let loadError { throw loadError }
        return try callRule(context, "salaryMonthlyEquivalent", input)
    }

    func shouldPromptApplyToday(
        current: NativeRulesInput,
        candidate: NativeRulesInput,
        kind: String,
        schedulePatternChanged: Bool
    ) -> Bool {
        if loadError != nil { return true }
        let request = NativeTodayImpactRequest(
            current: current,
            candidate: candidate,
            kind: kind,
            schedulePatternChanged: schedulePatternChanged
        )
        return askRule(context, "shouldPromptApplyToday", request, fallback: true)
    }
}

nonisolated struct NativeWorkSchedule: Codable, Equatable, Hashable, Sendable {
    let mode: String
    let referenceWeekStartMs: Double?
    let referenceWeekType: String?
    let singleWeekendWorkday: Int?
    let rotationAnchorMs: Double?
    let rotationWorkDays: Int?
    let rotationRestDays: Int?
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
}

private struct NativeTodayImpactRequest: Codable {
    let current: NativeRulesInput
    let candidate: NativeRulesInput
    let kind: String
    let schedulePatternChanged: Bool
}

struct NativeSummaryInput: Codable {
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

struct NativeRecordsIncomeInput: Codable {
    let completedWorkdays: Int
    let salaryAmount: String
    let salaryType: String
    let monthlyWorkingDays: Double
    let annualBonusMonths: Double

    init(completedWorkdays: Int, rules: NativeRulesInput) {
        self.completedWorkdays = completedWorkdays
        salaryAmount = rules.salaryAmount
        salaryType = rules.salaryType
        monthlyWorkingDays = rules.monthlyWorkingDays
        annualBonusMonths = rules.annualBonusMonths
    }
}

struct NativeLifetimeIncomePeriod: Codable {
    let startsOn: String
    let endsOn: String?
    let salaryAmount: Double
    let salaryCadence: String
}

struct NativeLifetimeIncomeSalary: Codable {
    let salaryAmount: Double
    let salaryCadence: String
    let startsOn: String?
}

struct NativeLifetimeIncomeDecline: Codable {
    let startsOn: String
    let retirementRatio: Double
}

struct NativeLifetimeIncomeInput: Codable {
    let periods: [NativeLifetimeIncomePeriod]
    let currentSalary: NativeLifetimeIncomeSalary?
    let futureIncomeDecline: NativeLifetimeIncomeDecline?
    let asOf: String
    let retirementOn: String
}

struct NativeRecordsActualForecastDay: Codable {
    var dayKey: String? = nil
    let actualKind: String?
    let resolvedSegments: [NativeShiftSegment]
    let plannedSegments: [NativeShiftSegment]
    let overtimeSegments: [NativeShiftSegment]
    let observations: [NativeRecordsSummaryObservation]
    let isActiveAnchor: Bool
}

struct NativeRecordsSummaryObservation: Codable {
    let kind: String
    let occurredAtMs: Double
}

struct NativeRecordsActualForecastInput: Codable {
    let days: [NativeRecordsActualForecastDay]
    let periodDayKeys: [String]
    let dailySalary: Double?
    let asOfMs: Double
    var salaryRules: NativeRulesInput? = nil
}

struct NativeReminder: Codable, Hashable {
    let id: String
    let kind: String
    let atMs: Double
    let expiresAtMs: Double?
    let maxTickGapMs: Double?
    let collapseGroup: String?
    let title: String?
    let body: String?
}

struct NativeMilestoneTitles: Codable {
    let milestone50: String
    let milestone75: String
    let milestone90: String
    let milestone95: String
    let milestone100: String
}

struct NativeMilestoneMessages: Codable {
    let milestone50: [String]
    let milestone75: [String]
    let milestone90: [String]
    let milestone95: [String]
    let milestone100: [String]
}

struct NativeReminderInputs: Codable {
    let mode: String
    let fallbackTitle: String
    /// Title for lunch start and end. Without it the bundle falls back to the
    /// off-work title, which is what made lunch pushes read "下班提醒".
    let breakTitle: String
    let milestoneTitles: NativeMilestoneTitles
    let milestoneMessages: NativeMilestoneMessages
    let lunchStartEnabled: Bool
    let lunchStartBody: String
    let lunchEndEnabled: Bool
    let lunchEndBody: String
    let microBreakEnabled: Bool
    let microBreakTitle: String
    let microBreakIntervalMinutes: Int
    let microBreakMessages: [String]
    let cycleEndSummaryBody: String?
}

private struct NativeReminderRequest: Codable {
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
    let timeZoneIdentifier: String?
    let reminderInputs: NativeReminderInputs

    init(rules: NativeRulesInput, reminderInputs: NativeReminderInputs) {
        startTime = rules.startTime
        endTime = rules.endTime
        nowMs = rules.nowMs
        workdays = rules.workdays
        schedule = rules.schedule
        breakStartTime = rules.breakStartTime
        breakDurationMinutes = rules.breakDurationMinutes
        overtimeEndAtMs = rules.overtimeEndAtMs
        salaryAmount = rules.salaryAmount
        salaryType = rules.salaryType
        monthlyWorkingDays = rules.monthlyWorkingDays
        annualBonusMonths = rules.annualBonusMonths
        forcedWorkdayStartMs = rules.forcedWorkdayStartMs
        timeZoneIdentifier = rules.timeZoneIdentifier
        self.reminderInputs = reminderInputs
    }
}
