import Foundation
import JavaScriptCore

struct NativeShiftSegment: Codable, Hashable {
    let startAtMs: Double
    let endAtMs: Double
}

struct NativeShiftSnapshot: Codable, Hashable {
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
    let nextShiftStartAtMs: Double?
    let nextShiftEndAtMs: Double?

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

    /// Completed figures stay frozen; tomorrow's hours can still move.
    func withLiveNextShift(from live: NativeShiftSnapshot) -> NativeShiftSnapshot {
        NativeShiftSnapshot(
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
            nextRestAtMs: nextRestAtMs,
            dailySalary: dailySalary,
            nextShiftStartAtMs: live.nextShiftStartAtMs,
            nextShiftEndAtMs: live.nextShiftEndAtMs
        )
    }
}

/// Salary-free absolute shift returned in one batch for WidgetKit. The shared
/// TypeScript rules still decide every boundary; this narrower projection only
/// avoids hundreds of Swift-to-JavaScriptCore calls while publishing a year.
struct NativeWidgetShiftSnapshot: Codable, Hashable {
    let segments: [NativeShiftSegment]
    let startAtMs: Double
    let endAtMs: Double
    let plannedEndAtMs: Double
    let overtimeEndAtMs: Double?
    let durationMs: Double
}

struct NativePeriodSummary: Codable, Hashable {
    let days: Double
    let hours: Double
    let earnings: Double?
}

enum CountdownRulesError: LocalizedError {
    case missingResource
    case unavailableRuntime(String)
    case invalidResult

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

@MainActor
final class CountdownRules {
    static let shared = CountdownRules()

    /// Builds the JSContext and evaluates the rules bundle off the first-frame
    /// path. Without this the singleton is created lazily inside the first
    /// `snapshot()` call, which happens while the timer screen is laying out —
    /// a synchronous 37 KB `evaluateScript` in the middle of launch.
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
        guard let context = JSContext() else {
            self.context = nil
            loadError = .unavailableRuntime("JavaScriptCore could not start.")
            return
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
            self.context = nil
            loadError = .missingResource
            return
        }

        context.evaluateScript(source)
        self.context = context
        loadError = capturedError
    }

    func snapshot(input: NativeRulesInput) throws -> NativeShiftSnapshot {
        if let loadError { throw loadError }
        guard let context,
              let bridge = context.objectForKeyedSubscript("OWCNative"),
              !bridge.isUndefined,
              let data = try? JSONEncoder().encode(input),
              let json = String(data: data, encoding: .utf8),
              let result = bridge.invokeMethod("snapshot", withArguments: [json]),
              !result.isUndefined,
              !result.isNull,
              let output = result.toString()?.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(NativeShiftSnapshot.self, from: output)
        else {
            throw CountdownRulesError.invalidResult
        }
        return snapshot
    }

    func widgetShifts(
        input: NativeRulesInput,
        throughMs: Double,
        maximumCount: Int
    ) throws -> [NativeWidgetShiftSnapshot] {
        if let loadError { throw loadError }
        let request = NativeWidgetTimelineRequest(
            rules: input,
            throughMs: throughMs,
            maximumCount: maximumCount
        )
        guard let context,
              let bridge = context.objectForKeyedSubscript("OWCNative"),
              !bridge.isUndefined,
              let data = try? JSONEncoder().encode(request),
              let json = String(data: data, encoding: .utf8),
              let result = bridge.invokeMethod("widgetShifts", withArguments: [json]),
              !result.isUndefined,
              !result.isNull,
              let output = result.toString()?.data(using: .utf8),
              let shifts = try? JSONDecoder().decode([NativeWidgetShiftSnapshot].self, from: output)
        else {
            throw CountdownRulesError.invalidResult
        }
        return shifts
    }

    func reminders(input: NativeRulesInput, reminderInputs: NativeReminderInputs) throws -> [NativeReminder] {
        if let loadError { throw loadError }
        let request = NativeReminderRequest(rules: input, reminderInputs: reminderInputs)
        guard let context,
              let bridge = context.objectForKeyedSubscript("OWCNative"),
              !bridge.isUndefined,
              let data = try? JSONEncoder().encode(request),
              let json = String(data: data, encoding: .utf8),
              let result = bridge.invokeMethod("reminders", withArguments: [json]),
              !result.isUndefined,
              !result.isNull,
              let output = result.toString()?.data(using: .utf8),
              let reminders = try? JSONDecoder().decode([NativeReminder].self, from: output)
        else {
            throw CountdownRulesError.invalidResult
        }
        return reminders
    }

    func summarize(input: NativeSummaryInput) throws -> NativePeriodSummary {
        if let loadError { throw loadError }
        guard let context,
              let bridge = context.objectForKeyedSubscript("OWCNative"),
              !bridge.isUndefined,
              let data = try? JSONEncoder().encode(input),
              let json = String(data: data, encoding: .utf8),
              let result = bridge.invokeMethod("summarize", withArguments: [json]),
              !result.isUndefined,
              !result.isNull,
              let output = result.toString()?.data(using: .utf8),
              let summary = try? JSONDecoder().decode(NativePeriodSummary.self, from: output)
        else {
            throw CountdownRulesError.invalidResult
        }
        return summary
    }

    func validateBreak(input: NativeRulesInput) -> Bool {
        guard let context,
              let bridge = context.objectForKeyedSubscript("OWCNative"),
              !bridge.isUndefined,
              let data = try? JSONEncoder().encode(input),
              let json = String(data: data, encoding: .utf8),
              let result = bridge.invokeMethod("validateBreak", withArguments: [json]),
              !result.isUndefined,
              !result.isNull
        else { return false }
        return result.toBool()
    }
}

struct NativeWorkSchedule: Codable {
    let mode: String
    let referenceWeekStartMs: Double?
    let referenceWeekType: String?
    let singleWeekendWorkday: Int?
    let rotationAnchorMs: Double?
    let rotationWorkDays: Int?
    let rotationRestDays: Int?
}

struct NativeRulesInput: Codable {
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
}

private struct NativeWidgetTimelineRequest: Codable {
    let rules: NativeRulesInput
    let throughMs: Double
    let maximumCount: Int
}

struct NativeSummaryInput: Codable {
    let period: String
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
        self.reminderInputs = reminderInputs
    }
}
