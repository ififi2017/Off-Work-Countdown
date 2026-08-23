import Combine
import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case timer
    case settings

    var id: String { rawValue }
}

enum AppRoute: String, Hashable, Identifiable {
    case schedule
    case salary
    case notifications
    case lunch
    case health
    case theme
    case about

    var id: String { rawValue }
}

enum WorkScheduleMode: String, CaseIterable, Identifiable {
    case classic
    case alternating
    case rotation
    case off

    var id: String { rawValue }
}

enum AlternatingWeekType: String, CaseIterable, Identifiable {
    case single
    case double

    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }
}

enum SalaryType: String, CaseIterable, Identifiable {
    case monthly
    case daily

    var id: String { rawValue }
}

enum OffWorkNotificationMode: String, CaseIterable, Identifiable {
    case off
    case simple
    case milestones

    var id: String { rawValue }
}

enum ShareMood: String, CaseIterable, Identifiable {
    case happy = "1f604"
    case relaxed = "1f60c"
    case tired = "1f62b"
    case crying = "1f62d"
    case firedUp = "1f525"
    case excited = "1f929"
    case celebrating = "1f973"
    case coffee = "2615"

    var id: String { rawValue }
    var assetName: String { "Mood-\(rawValue)" }

    /// Matches the mood keys the Web share dialog already ships in all 19
    /// locales, so the picker reads out properly under VoiceOver.
    var labelKey: String {
        switch self {
        case .happy: "moodHappy"
        case .relaxed: "moodRelaxed"
        case .tired: "moodTired"
        case .crying: "moodCounting"
        case .firedUp: "moodFiredUp"
        case .excited: "moodExcited"
        case .celebrating: "moodCelebrating"
        case .coffee: "moodCoffee"
        }
    }
}

@MainActor
final class OffWorkStore: ObservableObject {
    private enum Key {
        static let onboardingComplete = "ios.native.onboardingComplete"
#if DEBUG
        static let debugAlwaysOnboarding = "ios.native.debugAlwaysOnboarding"
        static let qaRoute = "ios.native.qaRoute"
#endif
        static let selectedTab = "ios.native.selectedTab"
        static let countdownStarted = "ios.native.countdownStarted"
        static let legacyForceToday = "ios.native.forceToday"
        static let forcedWorkdayDate = "ios.native.forcedWorkdayDate"
        static let startMinutes = "ios.native.startMinutes"
        static let endMinutes = "ios.native.endMinutes"
        static let workdays = "ios.native.workdays"
        static let scheduleMode = "ios.native.scheduleMode"
        static let alternatingWeekType = "ios.native.alternatingWeekType"
        static let alternatingWeekendWorkday = "ios.native.alternatingWeekendWorkday"
        static let alternatingReferenceWeekStartMs = "ios.native.alternatingReferenceWeekStartMs"
        static let rotationWorkDays = "ios.native.rotationWorkDays"
        static let rotationRestDays = "ios.native.rotationRestDays"
        static let rotationAnchorMs = "ios.native.rotationAnchorMs"
        static let lunchEnabled = "ios.native.lunchEnabled"
        static let lunchStartMinutes = "ios.native.lunchStartMinutes"
        static let lunchDuration = "ios.native.lunchDuration"
        static let salaryAmount = "ios.native.salaryAmount"
        static let salaryEnabled = "ios.native.salaryEnabled"
        static let salaryType = "ios.native.salaryType"
        static let monthlyWorkingDays = "ios.native.monthlyWorkingDays"
        static let annualBonusEnabled = "ios.native.annualBonusEnabled"
        static let annualBonusMonths = "ios.native.annualBonusMonths"
        static let hideEarnings = "hideEarnings"
        static let theme = "theme"
        static let notificationMode = "ios.native.notificationMode"
        static let liveActivityEnabled = "ios.native.liveActivityEnabled"
        static let liveActivityLead = "ios.native.liveActivityLead"
        static let legacyLunchEdgesEnabled = "ios.native.lunchEdgesEnabled"
        static let lunchStartReminderEnabled = "ios.native.lunchStartReminderEnabled"
        static let lunchEndReminderEnabled = "ios.native.lunchEndReminderEnabled"
        static let microBreakEnabled = "ios.native.microBreakEnabled"
        static let microBreakInterval = "ios.native.microBreakInterval"
        static let overtimeEndAtMs = "ios.native.overtimeEndAtMs"
        static let lastCelebratedEndAtMs = "ios.native.lastCelebratedEndAtMs"
    }

    static let allowedLiveActivityLeadMinutes = [5, 15, 30]

    let localizer = NativeLocalizer()
    private let defaults: UserDefaults

    @Published var selectedTab: AppTab { didSet { defaults.set(selectedTab.rawValue, forKey: Key.selectedTab) } }
    @Published var presentedRoute: AppRoute?
    @Published var onboardingPage = 0
    @Published var shareMood: ShareMood = .happy
    @Published var lastRulesError: String?

    @Published var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: Key.onboardingComplete) } }
#if DEBUG
    /// Replay the welcome flow on every launch. The property and its storage
    /// key do not exist in Release builds.
    @Published var debugAlwaysShowOnboarding: Bool {
        didSet { defaults.set(debugAlwaysShowOnboarding, forKey: Key.debugAlwaysOnboarding) }
    }
#endif
    @Published var countdownStarted: Bool { didSet { defaults.set(countdownStarted, forKey: Key.countdownStarted) } }
    @Published private var forcedWorkdayDate: String? {
        didSet {
            if let forcedWorkdayDate { defaults.set(forcedWorkdayDate, forKey: Key.forcedWorkdayDate) }
            else { defaults.removeObject(forKey: Key.forcedWorkdayDate) }
        }
    }
    @Published var startMinutes: Int { didSet { defaults.set(startMinutes, forKey: Key.startMinutes); clearOvertime() } }
    @Published var endMinutes: Int { didSet { defaults.set(endMinutes, forKey: Key.endMinutes); clearOvertime() } }
    @Published var workdays: Set<Int> { didSet { defaults.set(workdays.sorted(), forKey: Key.workdays) } }
    @Published var scheduleMode: WorkScheduleMode { didSet { defaults.set(scheduleMode.rawValue, forKey: Key.scheduleMode) } }
    @Published var alternatingWeekType: AlternatingWeekType { didSet { defaults.set(alternatingWeekType.rawValue, forKey: Key.alternatingWeekType) } }
    @Published var alternatingWeekendWorkday: Int { didSet { defaults.set(alternatingWeekendWorkday, forKey: Key.alternatingWeekendWorkday) } }
    @Published var alternatingReferenceWeekStartMs: Double { didSet { defaults.set(alternatingReferenceWeekStartMs, forKey: Key.alternatingReferenceWeekStartMs) } }
    @Published var rotationWorkDays: Int { didSet { defaults.set(rotationWorkDays, forKey: Key.rotationWorkDays) } }
    @Published var rotationRestDays: Int { didSet { defaults.set(rotationRestDays, forKey: Key.rotationRestDays) } }
    @Published var rotationAnchorMs: Double { didSet { defaults.set(rotationAnchorMs, forKey: Key.rotationAnchorMs) } }
    @Published var lunchEnabled: Bool { didSet { defaults.set(lunchEnabled, forKey: Key.lunchEnabled) } }
    @Published var lunchStartMinutes: Int { didSet { defaults.set(lunchStartMinutes, forKey: Key.lunchStartMinutes) } }
    @Published var lunchDurationMinutes: Int { didSet { defaults.set(lunchDurationMinutes, forKey: Key.lunchDuration) } }
    @Published var salaryAmount: String { didSet { defaults.set(salaryAmount, forKey: Key.salaryAmount) } }
    @Published var salaryEnabled: Bool { didSet { defaults.set(salaryEnabled, forKey: Key.salaryEnabled) } }
    @Published var salaryType: SalaryType { didSet { defaults.set(salaryType.rawValue, forKey: Key.salaryType) } }
    @Published var monthlyWorkingDays: Double { didSet { defaults.set(monthlyWorkingDays, forKey: Key.monthlyWorkingDays) } }
    @Published var annualBonusEnabled: Bool { didSet { defaults.set(annualBonusEnabled, forKey: Key.annualBonusEnabled) } }
    @Published var annualBonusMonths: Double { didSet { defaults.set(annualBonusMonths, forKey: Key.annualBonusMonths) } }
    @Published var hideEarnings: Bool { didSet { defaults.set(hideEarnings, forKey: Key.hideEarnings) } }
    @Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    @Published private(set) var languageCode: String
    @Published var notificationMode: OffWorkNotificationMode { didSet { defaults.set(notificationMode.rawValue, forKey: Key.notificationMode) } }
    @Published var liveActivityEnabled: Bool { didSet { defaults.set(liveActivityEnabled, forKey: Key.liveActivityEnabled) } }
    @Published var liveActivityLeadMinutes: Int { didSet { defaults.set(liveActivityLeadMinutes, forKey: Key.liveActivityLead) } }
    @Published var lunchStartReminderEnabled: Bool {
        didSet { defaults.set(lunchStartReminderEnabled, forKey: Key.lunchStartReminderEnabled) }
    }
    @Published var lunchEndReminderEnabled: Bool {
        didSet { defaults.set(lunchEndReminderEnabled, forKey: Key.lunchEndReminderEnabled) }
    }
    @Published var microBreakEnabled: Bool { didSet { defaults.set(microBreakEnabled, forKey: Key.microBreakEnabled) } }
    @Published var microBreakIntervalMinutes: Int { didSet { defaults.set(microBreakIntervalMinutes, forKey: Key.microBreakInterval) } }
    @Published var overtimeEndAtMs: Double? {
        didSet {
            if let overtimeEndAtMs { defaults.set(overtimeEndAtMs, forKey: Key.overtimeEndAtMs) }
            else { defaults.removeObject(forKey: Key.overtimeEndAtMs) }
        }
    }
    @Published var lastCelebratedEndAtMs: Double {
        didSet { defaults.set(lastCelebratedEndAtMs, forKey: Key.lastCelebratedEndAtMs) }
    }

    init(defaults: UserDefaults = .standard) {
#if DEBUG
        let debugRoute = AppRoute(rawValue: defaults.string(forKey: Key.qaRoute) ?? "")
#else
        let debugRoute: AppRoute? = nil
#endif
        self.defaults = defaults
        selectedTab = debugRoute == nil
            ? AppTab(rawValue: defaults.string(forKey: Key.selectedTab) ?? "timer") ?? .timer
            : .settings
        presentedRoute = debugRoute
#if DEBUG
        let replayOnboarding = defaults.bool(forKey: Key.debugAlwaysOnboarding)
        debugAlwaysShowOnboarding = replayOnboarding
        // Same effect as a fresh install, without uninstalling: the flow runs
        // and completing it still works normally for the rest of the session.
        onboardingComplete = replayOnboarding ? false : defaults.bool(forKey: Key.onboardingComplete)
#else
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
#endif
        countdownStarted = defaults.bool(forKey: Key.countdownStarted)
        let storedForcedDate = defaults.string(forKey: Key.forcedWorkdayDate)
        forcedWorkdayDate = storedForcedDate ?? (defaults.bool(forKey: Key.legacyForceToday) ? Self.dayKey(for: .now) : nil)
        startMinutes = defaults.object(forKey: Key.startMinutes) == nil ? 9 * 60 : defaults.integer(forKey: Key.startMinutes)
        endMinutes = defaults.object(forKey: Key.endMinutes) == nil ? 17 * 60 : defaults.integer(forKey: Key.endMinutes)
        let storedDays = defaults.array(forKey: Key.workdays) as? [Int] ?? [1, 2, 3, 4, 5]
        workdays = Set(storedDays)
        scheduleMode = WorkScheduleMode(rawValue: defaults.string(forKey: Key.scheduleMode) ?? "classic") ?? .classic
        alternatingWeekType = AlternatingWeekType(rawValue: defaults.string(forKey: Key.alternatingWeekType) ?? "double") ?? .double
        alternatingWeekendWorkday = defaults.object(forKey: Key.alternatingWeekendWorkday) == nil ? 6 : defaults.integer(forKey: Key.alternatingWeekendWorkday)
        alternatingReferenceWeekStartMs = defaults.object(forKey: Key.alternatingReferenceWeekStartMs) == nil
            ? Self.startOfCurrentWeek().timeIntervalSince1970 * 1_000
            : defaults.double(forKey: Key.alternatingReferenceWeekStartMs)
        rotationWorkDays = defaults.object(forKey: Key.rotationWorkDays) == nil ? 2 : max(1, defaults.integer(forKey: Key.rotationWorkDays))
        rotationRestDays = defaults.object(forKey: Key.rotationRestDays) == nil ? 2 : max(1, defaults.integer(forKey: Key.rotationRestDays))
        rotationAnchorMs = defaults.object(forKey: Key.rotationAnchorMs) == nil
            ? Calendar.current.startOfDay(for: .now).timeIntervalSince1970 * 1_000
            : defaults.double(forKey: Key.rotationAnchorMs)
        lunchEnabled = defaults.object(forKey: Key.lunchEnabled) == nil ? false : defaults.bool(forKey: Key.lunchEnabled)
        lunchStartMinutes = defaults.object(forKey: Key.lunchStartMinutes) == nil ? 12 * 60 : defaults.integer(forKey: Key.lunchStartMinutes)
        lunchDurationMinutes = defaults.object(forKey: Key.lunchDuration) == nil ? 60 : defaults.integer(forKey: Key.lunchDuration)
        salaryAmount = defaults.string(forKey: Key.salaryAmount) ?? "0"
        salaryEnabled = defaults.bool(forKey: Key.salaryEnabled)
        salaryType = SalaryType(rawValue: defaults.string(forKey: Key.salaryType) ?? "monthly") ?? .monthly
        monthlyWorkingDays = defaults.object(forKey: Key.monthlyWorkingDays) == nil ? 22 : defaults.double(forKey: Key.monthlyWorkingDays)
        annualBonusEnabled = defaults.bool(forKey: Key.annualBonusEnabled)
        let storedBonusMonths = defaults.object(forKey: Key.annualBonusMonths) == nil ? 1 : defaults.double(forKey: Key.annualBonusMonths)
        annualBonusMonths = max(0, storedBonusMonths)
        hideEarnings = defaults.bool(forKey: Key.hideEarnings)
        theme = AppTheme(rawValue: defaults.string(forKey: Key.theme) ?? "auto") ?? .auto
        languageCode = NativeLocalizer.systemLanguage()
        notificationMode = OffWorkNotificationMode(rawValue: defaults.string(forKey: Key.notificationMode) ?? "off") ?? .off
        liveActivityEnabled = defaults.bool(forKey: Key.liveActivityEnabled)
        let storedLead = defaults.object(forKey: Key.liveActivityLead) == nil ? 15 : defaults.integer(forKey: Key.liveActivityLead)
        liveActivityLeadMinutes = Self.allowedLiveActivityLeadMinutes.contains(storedLead) ? storedLead : 15
        let legacyLunchEdgesEnabled = defaults.bool(forKey: Key.legacyLunchEdgesEnabled)
        lunchStartReminderEnabled = defaults.object(forKey: Key.lunchStartReminderEnabled) == nil
            ? legacyLunchEdgesEnabled
            : defaults.bool(forKey: Key.lunchStartReminderEnabled)
        lunchEndReminderEnabled = defaults.object(forKey: Key.lunchEndReminderEnabled) == nil
            ? legacyLunchEdgesEnabled
            : defaults.bool(forKey: Key.lunchEndReminderEnabled)
        microBreakEnabled = defaults.bool(forKey: Key.microBreakEnabled)
        microBreakIntervalMinutes = defaults.object(forKey: Key.microBreakInterval) == nil ? 60 : defaults.integer(forKey: Key.microBreakInterval)
        overtimeEndAtMs = defaults.object(forKey: Key.overtimeEndAtMs) as? Double
        lastCelebratedEndAtMs = defaults.double(forKey: Key.lastCelebratedEndAtMs)
#if DEBUG
        if debugRoute != nil { defaults.removeObject(forKey: Key.qaRoute) }
#endif
    }

    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var layoutDirection: LayoutDirection { languageCode == "ar" ? .rightToLeft : .leftToRight }
    var locale: Locale { Locale(identifier: languageCode) }
    var forceToday: Bool { forcedWorkdayDate == Self.dayKey(for: .now) }
    /// SF Symbol for the two explicit themes. `auto` deliberately has none:
    /// the symbol named "a" is one of the localized symbols and renders as 字
    /// in Chinese, so Auto draws a literal "A" instead. See quickThemeIsAuto.
    var quickThemeIcon: String {
        switch theme {
        case .auto: ""
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var quickThemeIsAuto: Bool { theme == .auto }

    func refreshSystemLanguage() {
        let systemLanguage = NativeLocalizer.systemLanguage()
        if languageCode != systemLanguage {
            languageCode = systemLanguage
        }
    }

    func t(_ key: String, values: [String: String] = [:]) -> String {
        localizer.string(key, locale: languageCode, values: values)
    }

    func strings(_ key: String) -> [String] {
        localizer.strings(key, locale: languageCode)
    }

    func snapshot(at date: Date = .now) -> NativeShiftSnapshot? {
        do {
            let result = try CountdownRules.shared.snapshot(input: .init(
                startTime: timeString(startMinutes),
                endTime: timeString(endMinutes),
                nowMs: date.timeIntervalSince1970 * 1_000,
                workdays: workdays.sorted(),
                schedule: nativeSchedule,
                breakStartTime: lunchEnabled ? timeString(lunchStartMinutes) : nil,
                breakDurationMinutes: lunchEnabled ? lunchDurationMinutes : 0,
                overtimeEndAtMs: overtimeEndAtMs,
                salaryAmount: salaryEnabled ? salaryAmount : "",
                salaryType: salaryType.rawValue,
                monthlyWorkingDays: monthlyWorkingDays,
                annualBonusMonths: annualBonusEnabled ? annualBonusMonths : 0
            ))
            if lastRulesError != nil { lastRulesError = nil }
            return result
        } catch {
            lastRulesError = error.localizedDescription
            return nil
        }
    }

    func rulesInput(at date: Date = .now) -> NativeRulesInput {
        .init(
            startTime: timeString(startMinutes),
            endTime: timeString(endMinutes),
            nowMs: date.timeIntervalSince1970 * 1_000,
            workdays: workdays.sorted(),
            schedule: nativeSchedule,
            breakStartTime: lunchEnabled ? timeString(lunchStartMinutes) : nil,
            breakDurationMinutes: lunchEnabled ? lunchDurationMinutes : 0,
            overtimeEndAtMs: overtimeEndAtMs,
            salaryAmount: salaryEnabled ? salaryAmount : "",
            salaryType: salaryType.rawValue,
            monthlyWorkingDays: monthlyWorkingDays,
            annualBonusMonths: annualBonusEnabled ? annualBonusMonths : 0
        )
    }

    func reminderInputs() -> NativeReminderInputs {
        func title(_ remaining: Int) -> String {
            t("notificationMilestoneTitle", values: ["percent": "\(remaining)"])
        }
        return .init(
            mode: notificationMode.rawValue,
            fallbackTitle: t("offWorkReminder"),
            milestoneTitles: .init(
                milestone50: title(50),
                milestone75: title(25),
                milestone90: title(10),
                milestone95: title(5),
                milestone100: t("offWorkTime")
            ),
            milestoneMessages: .init(
                milestone50: [t("notificationMilestone50")],
                milestone75: [t("notificationMilestone75")],
                milestone90: [t("notificationMilestone90")],
                milestone95: [t("notificationMilestone95")],
                milestone100: [t("offWorkTime")]
            ),
            lunchStartEnabled: lunchStartReminderEnabled,
            lunchStartBody: t("lunchStartNotification"),
            lunchEndEnabled: lunchEndReminderEnabled,
            lunchEndBody: t("lunchEndNotification"),
            microBreakEnabled: microBreakEnabled,
            microBreakTitle: t("microBreakReminder"),
            microBreakIntervalMinutes: microBreakIntervalMinutes,
            microBreakMessages: strings("microBreakMessages")
        )
    }

    func startCountdown(force: Bool = false) {
        forcedWorkdayDate = force ? Self.dayKey(for: .now) : nil
        countdownStarted = true
    }

    func stopCountdown() {
        countdownStarted = false
        forcedWorkdayDate = nil
        clearOvertime()
    }

    func completeOnboarding(enableNotifications: Bool) {
        onboardingComplete = true
        // Deliberately does NOT reset onboardingPage. The welcome view is still
        // on screen for the length of the cross-fade, and resetting the page
        // snapped it back to the first slide mid-transition. `onboardingPage` is
        // not persisted, so a replay starts at 0 on its own.
        if enableNotifications { notificationMode = .simple }
    }

    func toggleWorkday(_ day: Int) {
        if workdays.contains(day) { workdays.remove(day) }
        else { workdays.insert(day) }
    }

    var nativeSchedule: NativeWorkSchedule {
        .init(
            mode: scheduleMode.rawValue,
            referenceWeekStartMs: scheduleMode == .alternating ? alternatingReferenceWeekStartMs : nil,
            referenceWeekType: scheduleMode == .alternating ? alternatingWeekType.rawValue : nil,
            singleWeekendWorkday: scheduleMode == .alternating ? alternatingWeekendWorkday : nil,
            rotationAnchorMs: scheduleMode == .rotation ? rotationAnchorMs : nil,
            rotationWorkDays: scheduleMode == .rotation ? rotationWorkDays : nil,
            rotationRestDays: scheduleMode == .rotation ? rotationRestDays : nil
        )
    }

    var isLunchInsideShift: Bool {
        !lunchEnabled || CountdownRules.shared.validateBreak(input: rulesInput())
    }

    func anchorAlternatingWeekToToday() {
        alternatingReferenceWeekStartMs = Self.startOfCurrentWeek().timeIntervalSince1970 * 1_000
    }

    func anchorRotationToToday() {
        rotationAnchorMs = Calendar.current.startOfDay(for: .now).timeIntervalSince1970 * 1_000
    }

    var rotationCycleLength: Int {
        max(2, rotationWorkDays + rotationRestDays)
    }

    /// Returns today's one-based position in the existing shared rotation
    /// schedule. Choosing another position only moves the schedule anchor; the
    /// TypeScript rules remain responsible for deciding work and rest days.
    var rotationCycleDay: Int {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date(timeIntervalSince1970: rotationAnchorMs / 1_000))
        let today = calendar.startOfDay(for: .now)
        let offset = calendar.dateComponents([.day], from: anchor, to: today).day ?? 0
        return ((offset % rotationCycleLength) + rotationCycleLength) % rotationCycleLength + 1
    }

    func setRotationCycleDay(_ day: Int) {
        let normalizedDay = min(rotationCycleLength, max(1, day))
        let today = Calendar.current.startOfDay(for: .now)
        let anchor = Calendar.current.date(byAdding: .day, value: -(normalizedDay - 1), to: today) ?? today
        rotationAnchorMs = anchor.timeIntervalSince1970 * 1_000
    }

    func toggleQuickTheme() {
        switch theme {
        case .auto: theme = .light
        case .light: theme = .dark
        case .dark: theme = .auto
        }
    }

    func applyOvertime(date: Date) {
        overtimeEndAtMs = date.timeIntervalSince1970 * 1_000
        countdownStarted = true
    }

    func clearOvertime() {
        if overtimeEndAtMs != nil { overtimeEndAtMs = nil }
    }

    func timeString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    func dateForMinutes(_ minutes: Int, base: Date = .now) -> Date {
        Calendar.current.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: base) ?? base
    }

    func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    func formatTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    func formatDuration(_ milliseconds: Double, includeSeconds: Bool = true) -> String {
        let total = max(0, Int(milliseconds / 1_000))
        guard includeSeconds else { return formatRelativeDuration(milliseconds) }
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }

    func formatDays(_ value: Double) -> String {
        let precision = value.rounded() == value ? 0 : 1
        let number = value.formatted(.number.precision(.fractionLength(precision)).locale(locale))
        return t("daysShort", values: ["count": number])
    }

    func formatRelativeDuration(_ milliseconds: Double) -> String {
        let total = max(0, Int(milliseconds / 1_000))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if languageCode == "en" {
            return hours > 0 ? "\(hours) h \(minutes) m" : "\(minutes) m"
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: TimeInterval(total)) ?? "—"
    }

    func formatHours(_ value: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = value.rounded() == value ? 0 : 1
        return formatter.string(from: Measurement(value: value, unit: UnitDuration.hours))
    }

    func formatMoney(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    func weekdayLabels() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.shortWeekdaySymbols
        return [1, 2, 3, 4, 5, 6, 0].map { day in
            let calendarIndex = day == 0 ? 0 : day
            return symbols[calendarIndex]
        }
    }

    func shareURL() -> URL {
        let compactStart = timeString(startMinutes).replacingOccurrences(of: ":", with: "")
        let compactEnd = timeString(endMinutes).replacingOccurrences(of: ":", with: "")
        var components = URLComponents(string: "https://off.rainif.com/")!
        components.queryItems = [
            URLQueryItem(name: "utm_source", value: "share"),
            URLQueryItem(name: "utm_medium", value: "image"),
            URLQueryItem(name: "utm_campaign", value: "countdown"),
            URLQueryItem(name: "s", value: "\(compactStart)-\(compactEnd)"),
            URLQueryItem(name: "from", value: "share"),
        ]
        return components.url!
    }

    func periodSummary(_ period: String, asOf: Date, snapshot: NativeShiftSnapshot) -> NativePeriodSummary? {
        guard scheduleMode != .off else { return nil }
        var summaryWorkdays = workdays
        if forceToday {
            summaryWorkdays.insert(Calendar.current.component(.weekday, from: snapshot.startDate) - 1)
        }
        do {
            let result = try CountdownRules.shared.summarize(input: .init(
                period: period,
                asOfMs: asOf.timeIntervalSince1970 * 1_000,
                workdays: summaryWorkdays.sorted(),
                schedule: nativeSchedule,
                currentShiftStartMs: snapshot.startAtMs,
                currentShiftEndMs: snapshot.endAtMs,
                plannedDailyHours: snapshot.plannedDurationMs / 3_600_000,
                todayProgress: min(100, snapshot.progress),
                dailySalary: snapshot.dailySalary,
                todayEffectiveHours: snapshot.durationMs / 3_600_000,
                todayPayRatio: snapshot.payRatio
            ))
            if lastRulesError != nil { lastRulesError = nil }
            return result
        } catch {
            lastRulesError = error.localizedDescription
            return nil
        }
    }

    func relativeDayLabel(for date: Date, from now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(date) { return t("tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).locale(locale))
    }

    func weekdayName(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).locale(locale))
    }

    func markCelebrated(endAtMs: Double) {
        lastCelebratedEndAtMs = endAtMs
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func startOfCurrentWeek() -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let day = calendar.startOfDay(for: .now)
        return calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    }
}
