import Foundation
import JavaScriptCore

nonisolated struct NativeShiftSegment: Codable, Hashable, Sendable {
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

/// Salary-free absolute shift returned in one batch for WidgetKit. The shared
/// TypeScript rules still decide every boundary; this narrower projection only
/// avoids hundreds of Swift-to-JavaScriptCore calls while publishing a year.
/// One calendar day's planned hours from `expandScheduleRange`. Rest days
/// still carry segments so a makeup-day exception can reuse them.
nonisolated struct NativeScheduleDayExpansion: Codable, Hashable, Sendable {
    let dayKey: String
    let shiftAnchorStartAtMs: Double
    let isWorkday: Bool
    let segments: [NativeShiftSegment]
}

struct NativeWidgetShiftSnapshot: Codable, Hashable {
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

nonisolated enum CountdownRulesError: LocalizedError, Sendable {
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
            await ScheduleRangeEngine.shared.warmUp()
        }
    }

    private let context: JSContext?
    private let loadError: CountdownRulesError?
    private var expansionCache: [String: [NativeScheduleDayExpansion]] = [:]
    /// Insertion order, oldest first. This is a warm path for the JavaScriptCore
    /// walk, not a store, so it must not grow with browsing history.
    private var expansionCacheOrder: [String] = []
    private var expansionCacheDays = 0
    /// Counted in days, not entries: one Life expansion is worth thousands of
    /// Records windows, so an entry cap would not bound anything.
    private static let expansionCacheDayBudget = 40_000

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

    func expandScheduleRange(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone? = nil
    ) throws -> [NativeScheduleDayExpansion] {
        let key = Self.expansionCacheKey(
            configuration: configuration,
            from: from,
            through: through,
            timeZone: timeZone
        )
        if let cached = expansionCache[key] { return cached }
        let days = try invokeExpandScheduleRange(
            configuration: configuration,
            from: from,
            through: through,
            timeZone: timeZone
        )
        storeExpansion(days, forKey: key)
        return days
    }

    private func storeExpansion(_ days: [NativeScheduleDayExpansion], forKey key: String) {
        if let existing = expansionCache.removeValue(forKey: key) {
            expansionCacheDays -= existing.count
            expansionCacheOrder.removeAll { $0 == key }
        }
        expansionCache[key] = days
        expansionCacheOrder.append(key)
        expansionCacheDays += days.count
        // Keep at least the entry just stored, however large it is: evicting it
        // immediately would turn every Life read back into a cold walk.
        while expansionCacheDays > Self.expansionCacheDayBudget, expansionCacheOrder.count > 1 {
            let oldest = expansionCacheOrder.removeFirst()
            expansionCacheDays -= expansionCache.removeValue(forKey: oldest)?.count ?? 0
        }
    }

    /// Drops every warmed expansion. The next read walks JavaScriptCore again.
    func purgeExpansionCache() {
        expansionCache.removeAll()
        expansionCacheOrder.removeAll()
        expansionCacheDays = 0
    }

    /// Fills the expansion cache on a private JSContext so a year view can
    /// paint its first frame before the 365-day walk runs.
    func prefetchExpansion(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone? = nil
    ) async throws {
        let key = Self.expansionCacheKey(
            configuration: configuration,
            from: from,
            through: through,
            timeZone: timeZone
        )
        if expansionCache[key] != nil { return }
        let days = try await ScheduleRangeEngine.shared.expand(
            configuration: configuration,
            from: from,
            through: through,
            timeZone: timeZone
        )
        storeExpansion(days, forKey: key)
    }

    fileprivate func invokeExpandScheduleRange(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone?
    ) throws -> [NativeScheduleDayExpansion] {
        if let loadError { throw loadError }
        return try expandScheduleRangeOnContext(
            context,
            configuration: configuration,
            from: from,
            through: through,
            timeZone: timeZone
        )
    }

    private static func expansionCacheKey(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone?
    ) -> String {
        let fingerprint = (try? ScheduleHoursCodec.encode(configuration).fingerprint) ?? "hours"
        let zone = timeZone?.identifier ?? "_"
        return "\(fingerprint)|\(zone)|\(from.timeIntervalSince1970)|\(through.timeIntervalSince1970)"
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
        guard let context,
              let bridge = context.objectForKeyedSubscript("OWCNative"),
              !bridge.isUndefined,
              let data = try? JSONEncoder().encode(request),
              let json = String(data: data, encoding: .utf8),
              let result = bridge.invokeMethod("shouldPromptApplyToday", withArguments: [json]),
              !result.isUndefined,
              !result.isNull
        else { return true }
        return result.toBool()
    }
}

/// Isolated from `CountdownRules` so a background actor can expand a year
/// without hopping back to the main-actor JSContext. `nonisolated` so both
/// MainActor and `ScheduleRangeEngine` can call it on their own context.
nonisolated private func expandScheduleRangeOnContext(
    _ context: JSContext?,
    configuration: ScheduleHoursConfiguration,
    from: Date,
    through: Date,
    timeZone: TimeZone?
) throws -> [NativeScheduleDayExpansion] {
    let request = NativeScheduleRangeRequest(
        startTime: configuration.startTime,
        endTime: configuration.endTime,
        workdays: configuration.workdays,
        schedule: configuration.schedule,
        breakStartTime: configuration.breakStartTime,
        breakDurationMinutes: configuration.breakDurationMinutes,
        fromMs: from.timeIntervalSince1970 * 1_000,
        throughMs: through.timeIntervalSince1970 * 1_000,
        timeZoneIdentifier: timeZone?.identifier
    )
    guard let context,
          let bridge = context.objectForKeyedSubscript("OWCNative"),
          !bridge.isUndefined,
          let data = try? JSONEncoder().encode(request),
          let json = String(data: data, encoding: .utf8),
          let result = bridge.invokeMethod("expandScheduleRange", withArguments: [json]),
          !result.isUndefined,
          !result.isNull,
          let output = result.toString()?.data(using: .utf8),
          let days = try? JSONDecoder().decode([NativeScheduleDayExpansion].self, from: output)
    else {
        throw CountdownRulesError.invalidResult
    }
    return days
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
    let forcedWorkdayStartMs: Double?
    var timeZoneIdentifier: String? = nil
}

private struct NativeWidgetTimelineRequest: Codable {
    let rules: NativeRulesInput
    let throughMs: Double
    let maximumCount: Int
}

nonisolated private struct NativeScheduleRangeRequest: Codable, Sendable {
    let startTime: String
    let endTime: String
    let workdays: [Int]
    let schedule: NativeWorkSchedule
    let breakStartTime: String?
    let breakDurationMinutes: Int
    let fromMs: Double
    let throughMs: Double
    let timeZoneIdentifier: String?
}

private struct NativeTodayImpactRequest: Codable {
    let current: NativeRulesInput
    let candidate: NativeRulesInput
    let kind: String
    let schedulePatternChanged: Bool
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
    var timeZoneIdentifier: String? = nil
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

/// A second JSContext, isolated from the main-actor timer snapshot. Year
/// expansion used to share that context and freeze the Records tab.
actor ScheduleRangeEngine {
    static let shared = ScheduleRangeEngine()

    private var context: JSContext?
    private var loadError: CountdownRulesError?
    private var ready = false

    func warmUp() {
        ensureReady()
    }

    func expand(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone?
    ) throws -> [NativeScheduleDayExpansion] {
        ensureReady()
        if let loadError { throw loadError }
        return try expandScheduleRangeOnContext(
            context,
            configuration: configuration,
            from: from,
            through: through,
            timeZone: timeZone
        )
    }

    private func ensureReady() {
        guard !ready else { return }
        ready = true
        guard let context = JSContext() else {
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
            loadError = .missingResource
            return
        }
        context.evaluateScript(source)
        self.context = context
        loadError = capturedError
    }
}
