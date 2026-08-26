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
    case language
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

    /// Rendered at runtime by the system emoji font. Keeping the stable code
    /// point as the raw value avoids changing picker identity or saved state.
    var emoji: String {
        switch self {
        case .happy: "😄"
        case .relaxed: "😌"
        case .tired: "😫"
        case .crying: "😭"
        case .firedUp: "🔥"
        case .excited: "🤩"
        case .celebrating: "🥳"
        case .coffee: "☕️"
        }
    }

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
@Observable
final class OffWorkStore {
    private enum Key {
        static let onboardingComplete = "ios.native.onboardingComplete"
#if DEBUG
        static let debugAlwaysOnboarding = "ios.native.debugAlwaysOnboarding"
        static let qaRoute = "ios.native.qaRoute"
#endif
        static let selectedTab = "ios.native.selectedTab"
        static let countdownStarted = "ios.native.countdownStarted"
        static let automaticCountdownMigrationCompleted = "ios.native.automaticCountdownMigrationCompleted"
        static let earlyOffAtMs = "ios.native.earlyOffAtMs"
        static let earlyOffShiftEndAtMs = "ios.native.earlyOffShiftEndAtMs"
        static let earlyOffSnapshot = "ios.native.earlyOffSnapshot"
        static let dismissedCompletedEndAtMs = "ios.native.dismissedCompletedEndAtMs"
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
        static let languageOverride = "ios.native.languageOverride"
        static let notificationMode = "ios.native.notificationMode"
        static let liveActivityEnabled = "ios.native.liveActivityEnabled"
        static let liveActivityLead = "ios.native.liveActivityLead"
        static let legacyLunchEdgesEnabled = "ios.native.lunchEdgesEnabled"
        static let lunchStartReminderEnabled = "ios.native.lunchStartReminderEnabled"
        static let lunchEndReminderEnabled = "ios.native.lunchEndReminderEnabled"
        static let microBreakEnabled = "ios.native.microBreakEnabled"
        static let microBreakInterval = "ios.native.microBreakInterval"
        static let overtimeEndAtMs = "ios.native.overtimeEndAtMs"
        static let activeCountdownEndAtMs = "ios.native.activeCountdownEndAtMs"
        static let lastCelebratedEndAtMs = "ios.native.lastCelebratedEndAtMs"
    }

    static let allowedLiveActivityLeadMinutes = [5, 15, 30]

    let localizer = NativeLocalizer()
    private let defaults: UserDefaults

    var selectedTab: AppTab { didSet { defaults.set(selectedTab.rawValue, forKey: Key.selectedTab) } }
    var presentedRoute: AppRoute?

    /// Whether the "coming up" list is showing everything.
    ///
    /// Held here rather than in the timer views because its lifetime is one
    /// countdown session, not one view instance. As view `@State` it outlived
    /// `stopCountdown()`: stopping and starting again inside SwiftUI's retention
    /// window reattached the same view, and the list came back expanded. Waiting
    /// a second or two first "fixed" it, which is the tell.
    var timelineExpanded = false

    /// Hours the setup page is editing. The running snapshot, notifications
    /// and widgets keep using `startMinutes`/`endMinutes` until the apply
    /// button commits them — otherwise dragging the end time to "now" would
    /// yank the completed screen over the editor.
    var draftStartMinutes: Int?
    var draftEndMinutes: Int?

    /// The two navigation stacks, held here rather than in the shells so a
    /// pushed page survives a rotation — portrait and landscape are separate
    /// view trees, and each used to own its own path. Not persisted.
    var timerPath: [AppRoute] = []
    var settingsPath: [AppRoute] = []

    /// Landscape drives a single `NavigationStack` for both tabs, where
    /// portrait has one per tab; this projects whichever is current.
    var activePath: [AppRoute] {
        get { selectedTab == .timer ? timerPath : settingsPath }
        set {
            if selectedTab == .timer { timerPath = newValue } else { settingsPath = newValue }
        }
    }
    var onboardingPage = 0
    var shareMood: ShareMood = .happy
    var lastRulesError: String?

    var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: Key.onboardingComplete) } }
#if DEBUG
    /// Replay the welcome flow on every launch. The property and its storage
    /// key do not exist in Release builds.
    var debugAlwaysShowOnboarding: Bool {
        didSet { defaults.set(debugAlwaysShowOnboarding, forKey: Key.debugAlwaysOnboarding) }
    }
#endif
    var countdownStarted: Bool { didSet { defaults.set(countdownStarted, forKey: Key.countdownStarted) } }

    /// When the user said they had finished for the day, and at what moment.
    ///
    /// This is not a "skip today" switch. It is the first thing this app records
    /// about what actually happened rather than what was planned — `002`'s
    /// `actualEndAtMs` on a `.session` record — which is why it stores the
    /// instant and not a day flag.
    ///
    /// It ends **the shift the user was in**, not the calendar day:
    /// `start <= earlyOffAtMs < end`. That phrasing settles the awkward case on
    /// its own. Change the hours afterwards so a new shift begins after this
    /// moment — a night shift, say — and that shift is genuinely new, does not
    /// match, and counts normally. No special case needed.
    var earlyOffAtMs: Double? { didSet { defaults.set(earlyOffAtMs, forKey: Key.earlyOffAtMs) } }

    /// The end of the shift that was on screen when they said they had
    /// finished. Stored because the moment alone is not enough to identify it:
    /// clocking off *before* a shift begins is a perfectly ordinary thing to do
    /// — "I'm not going in today" — and a moment earlier than the start falls
    /// outside the shift's own window.
    var earlyOffShiftEndAtMs: Double? { didSet { defaults.set(earlyOffShiftEndAtMs, forKey: Key.earlyOffShiftEndAtMs) } }

    /// The rules snapshot as it stood when they clocked off. Re-querying
    /// `snapshot(at:)` after a settings change would rebuild elapsed time,
    /// lunch gaps and pay from the new configuration, which is not a freeze.
    /// App defaults only — this carries `dailySalary` and must not enter the
    /// App Group projection.
    private var earlyOffSnapshot: NativeShiftSnapshot? {
        didSet { persistEarlyOffSnapshot() }
    }

    /// The completed shift the user has put away so they can see setup again.
    ///
    /// Distinct from early clock-off: the day ended on its own, and they are
    /// not recording a different finish — they are leaving the celebration
    /// without disarming the schedule. Matched against `endAtMs` so a later
    /// shift is not swallowed by yesterday's dismiss.
    var dismissedCompletedEndAtMs: Double? {
        didSet { defaults.set(dismissedCompletedEndAtMs, forKey: Key.dismissedCompletedEndAtMs) }
    }
    private var forcedWorkdayDate: String? {
        didSet {
            if let forcedWorkdayDate { defaults.set(forcedWorkdayDate, forKey: Key.forcedWorkdayDate) }
            else { defaults.removeObject(forKey: Key.forcedWorkdayDate) }
        }
    }
    var startMinutes: Int {
        didSet {
            defaults.set(startMinutes, forKey: Key.startMinutes)
            clearOvertime()
            draftStartMinutes = nil
        }
    }
    var endMinutes: Int {
        didSet {
            defaults.set(endMinutes, forKey: Key.endMinutes)
            clearOvertime()
            draftEndMinutes = nil
        }
    }

    var displayedStartMinutes: Int { draftStartMinutes ?? startMinutes }
    var displayedEndMinutes: Int { draftEndMinutes ?? endMinutes }

    func setDisplayedStartMinutes(_ minutes: Int) {
        draftStartMinutes = minutes == startMinutes ? nil : minutes
    }

    func setDisplayedEndMinutes(_ minutes: Int) {
        draftEndMinutes = minutes == endMinutes ? nil : minutes
    }

    func commitDisplayedHours() {
        if let draftStartMinutes { startMinutes = draftStartMinutes }
        if let draftEndMinutes { endMinutes = draftEndMinutes }
    }
    var workdays: Set<Int> { didSet { defaults.set(workdays.sorted(), forKey: Key.workdays) } }
    var scheduleMode: WorkScheduleMode { didSet { defaults.set(scheduleMode.rawValue, forKey: Key.scheduleMode) } }
    var alternatingWeekType: AlternatingWeekType { didSet { defaults.set(alternatingWeekType.rawValue, forKey: Key.alternatingWeekType) } }
    var alternatingWeekendWorkday: Int { didSet { defaults.set(alternatingWeekendWorkday, forKey: Key.alternatingWeekendWorkday) } }
    var alternatingReferenceWeekStartMs: Double { didSet { defaults.set(alternatingReferenceWeekStartMs, forKey: Key.alternatingReferenceWeekStartMs) } }
    var rotationWorkDays: Int { didSet { defaults.set(rotationWorkDays, forKey: Key.rotationWorkDays) } }
    var rotationRestDays: Int { didSet { defaults.set(rotationRestDays, forKey: Key.rotationRestDays) } }
    var rotationAnchorMs: Double { didSet { defaults.set(rotationAnchorMs, forKey: Key.rotationAnchorMs) } }
    var lunchEnabled: Bool { didSet { defaults.set(lunchEnabled, forKey: Key.lunchEnabled) } }
    var lunchStartMinutes: Int { didSet { defaults.set(lunchStartMinutes, forKey: Key.lunchStartMinutes) } }
    var lunchDurationMinutes: Int { didSet { defaults.set(lunchDurationMinutes, forKey: Key.lunchDuration) } }
    var salaryAmount: String { didSet { defaults.set(salaryAmount, forKey: Key.salaryAmount) } }
    var salaryEnabled: Bool { didSet { defaults.set(salaryEnabled, forKey: Key.salaryEnabled) } }
    var salaryType: SalaryType { didSet { defaults.set(salaryType.rawValue, forKey: Key.salaryType) } }
    var monthlyWorkingDays: Double { didSet { defaults.set(monthlyWorkingDays, forKey: Key.monthlyWorkingDays) } }
    var annualBonusEnabled: Bool { didSet { defaults.set(annualBonusEnabled, forKey: Key.annualBonusEnabled) } }
    var annualBonusMonths: Double { didSet { defaults.set(annualBonusMonths, forKey: Key.annualBonusMonths) } }
    var hideEarnings: Bool { didSet { defaults.set(hideEarnings, forKey: Key.hideEarnings) } }
    var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    /// The language iOS would give us, kept as stored state so a change while
    /// the app is backgrounded invalidates the views that read it.
    private(set) var systemLanguageCode: String

    /// The language the user pinned, or nil to follow the system.
    ///
    /// The app owns this rather than deferring to iOS because the only way to
    /// reach the system's per-app language is `UIApplication.openSettingsURLString`,
    /// and since iOS 18 reorganised Settings that link no longer reliably lands
    /// on the app's own page — testers were dropped at the Settings root, where
    /// third-party apps are now buried under "Apps". Every string in this app
    /// already comes from the bundled JSON via `t()`, so there was nothing to
    /// gain from routing the choice through a page we cannot navigate to.
    var languageOverride: String? {
        didSet { defaults.set(languageOverride, forKey: Key.languageOverride) }
    }

    /// What the UI actually renders in. Widgets, the Live Activity and the
    /// notification copy all read this, so pinning a language carries through
    /// without any of them knowing an override exists.
    var languageCode: String { languageOverride ?? systemLanguageCode }
    var notificationMode: OffWorkNotificationMode { didSet { defaults.set(notificationMode.rawValue, forKey: Key.notificationMode) } }
    var liveActivityEnabled: Bool { didSet { defaults.set(liveActivityEnabled, forKey: Key.liveActivityEnabled) } }
    var liveActivityLeadMinutes: Int { didSet { defaults.set(liveActivityLeadMinutes, forKey: Key.liveActivityLead) } }
    var lunchStartReminderEnabled: Bool {
        didSet { defaults.set(lunchStartReminderEnabled, forKey: Key.lunchStartReminderEnabled) }
    }
    var lunchEndReminderEnabled: Bool {
        didSet { defaults.set(lunchEndReminderEnabled, forKey: Key.lunchEndReminderEnabled) }
    }
    var microBreakEnabled: Bool { didSet { defaults.set(microBreakEnabled, forKey: Key.microBreakEnabled) } }
    var microBreakIntervalMinutes: Int { didSet { defaults.set(microBreakIntervalMinutes, forKey: Key.microBreakInterval) } }
    var overtimeEndAtMs: Double? {
        didSet {
            if let overtimeEndAtMs { defaults.set(overtimeEndAtMs, forKey: Key.overtimeEndAtMs) }
            else { defaults.removeObject(forKey: Key.overtimeEndAtMs) }
        }
    }
    private var activeCountdownEndAtMs: Double? {
        didSet {
            if let activeCountdownEndAtMs {
                defaults.set(activeCountdownEndAtMs, forKey: Key.activeCountdownEndAtMs)
            } else {
                defaults.removeObject(forKey: Key.activeCountdownEndAtMs)
            }
        }
    }
    var lastCelebratedEndAtMs: Double {
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
        systemLanguageCode = NativeLocalizer.systemLanguage()
        // Only honour a code this build still ships; a language dropped between
        // versions must fall back rather than leave the UI on missing keys.
        languageOverride = defaults.string(forKey: Key.languageOverride).flatMap { stored in
            NativeLocalizer.supportedLanguages.contains { $0.id == stored } ? stored : nil
        }
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
        earlyOffAtMs = defaults.object(forKey: Key.earlyOffAtMs) as? Double
        earlyOffShiftEndAtMs = defaults.object(forKey: Key.earlyOffShiftEndAtMs) as? Double
        earlyOffSnapshot = Self.decodeEarlyOffSnapshot(from: defaults)
        dismissedCompletedEndAtMs = defaults.object(forKey: Key.dismissedCompletedEndAtMs) as? Double
        activeCountdownEndAtMs = defaults.object(forKey: Key.activeCountdownEndAtMs) as? Double
        lastCelebratedEndAtMs = defaults.double(forKey: Key.lastCelebratedEndAtMs)

        // Before automatic scheduled countdowns, a completed shift cleared
        // `countdownStarted` at the following midnight. Arm existing configured
        // schedules once on upgrade so they do not need another manual start.
        // The marker preserves an explicit Stop after this migration.
        if defaults.object(forKey: Key.automaticCountdownMigrationCompleted) == nil {
            defaults.set(true, forKey: Key.automaticCountdownMigrationCompleted)
            if onboardingComplete, scheduleMode != .off {
                countdownStarted = true
            }
        }
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
    /// Part of the schedule signature. Forcing a rest day changes what the
    /// widget and the notification list should say, and once the schedule arms
    /// itself nothing else in that signature moves when the button is pressed —
    /// `countdownStarted` was already true, so the widget kept publishing
    /// "rest day" while the app counted the shift down.
    var forcedWorkdayKey: String? { forcedWorkdayDate }

    /// Whether `shift` is a rest day the user chose to work anyway.
    ///
    /// Keyed on the day the shift *starts*, never on today's date. An overnight
    /// forced shift is one run, and comparing against `.now` ended it at
    /// midnight: at 00:00 the screen fell back to "today is off" with hours
    /// still to work, and `reconcileCountdownSession` then deleted the mark for
    /// good. Reading it off the shift also makes the reverse case work —
    /// forcing that same shift from the far side of midnight now marks the run
    /// that is actually on screen instead of a day it does not belong to.
    func isForcedWorkday(_ shift: NativeShiftSnapshot) -> Bool {
        guard let forcedWorkdayDate else { return false }
        return forcedWorkdayDate == Self.dayKey(for: shift.startDate)
    }
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
        if systemLanguageCode != systemLanguage {
            systemLanguageCode = systemLanguage
        }
    }

    func t(_ key: String, values: [String: String] = [:]) -> String {
        localizer.string(key, locale: languageCode, values: values)
    }

    func strings(_ key: String) -> [String] {
        localizer.strings(key, locale: languageCode)
    }

    func snapshot(
        at date: Date = .now,
        startMinutes: Int? = nil,
        endMinutes: Int? = nil
    ) -> NativeShiftSnapshot? {
        do {
            let result = try CountdownRules.shared.snapshot(input: rulesInput(
                at: date,
                startMinutes: startMinutes,
                endMinutes: endMinutes
            ))
            if lastRulesError != nil { lastRulesError = nil }
            return result
        } catch {
            lastRulesError = error.localizedDescription
            return nil
        }
    }

    /// Snapshot of the hours the setup page is currently showing, including
    /// uncommitted edits. The timer phase must not use this — that is how
    /// dragging the wheel used to replace the editor with the completed screen.
    func setupSnapshot(at date: Date = .now) -> NativeShiftSnapshot? {
        snapshot(at: date, startMinutes: displayedStartMinutes, endMinutes: displayedEndMinutes)
    }

    func rulesInput(
        at date: Date = .now,
        startMinutes: Int? = nil,
        endMinutes: Int? = nil
    ) -> NativeRulesInput {
        let start = startMinutes ?? self.startMinutes
        let end = endMinutes ?? self.endMinutes
        return .init(
            startTime: timeString(start),
            endTime: timeString(end),
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

    /// Builds the presentation timeline from shared absolute boundaries.
    /// Scheduled reminders stay scoped to today, while the shift start/end
    /// boundaries remain visible for a complete (including overnight) flow.
    func upcomingTimelineEvents(
        for snapshot: NativeShiftSnapshot,
        at now: Date = .now
    ) -> [UpcomingTimelineEvent] {
        let nowMs = now.timeIntervalSince1970 * 1_000
        var events: [UpcomingTimelineEvent] = []

        // Bounded by the shift, not by the calendar day. Requiring the same day
        // as `now` silently dropped lunch, health reminders and the Live
        // Activity lead-in from every overnight shift — they all land after
        // midnight, so only the shift's own start and end rows survived.
        func isDuringShift(_ atMs: Double) -> Bool {
            atMs > nowMs && atMs <= snapshot.endAtMs
        }

        if snapshot.startAtMs > nowMs {
            events.append(.init(
                id: "shift-start-\(Int64(snapshot.startAtMs))",
                kind: .shiftStart,
                date: snapshot.startDate,
                title: t("startTime"),
                detail: t("todaysShift")
            ))
        }

        for (index, segment) in snapshot.segments.dropLast().enumerated() {
            let nextSegment = snapshot.segments[index + 1]
            guard nextSegment.startAtMs > segment.endAtMs else { continue }

            if isDuringShift(segment.endAtMs) {
                events.append(.init(
                    id: "lunch-start-\(Int64(segment.endAtMs))",
                    kind: .lunchStart,
                    date: Date(timeIntervalSince1970: segment.endAtMs / 1_000),
                    title: t("lunchBreak"),
                    detail: t("lunchStartTime")
                ))
            }

            if isDuringShift(nextSegment.startAtMs) {
                events.append(.init(
                    id: "lunch-end-\(Int64(nextSegment.startAtMs))",
                    kind: .lunchEnd,
                    date: Date(timeIntervalSince1970: nextSegment.startAtMs / 1_000),
                    title: t("lunchBreak"),
                    detail: t("lunchBackAt")
                ))
            }
        }

        // Exactly one micro-break row, carrying its interval, rather than one
        // per firing — eight identical hourly rows buried the two that matter.
        // It is effectively permanent near the top of the list, which is the
        // point: this is the seam a pomodoro timer will plug into later.
        //
        // The Live Activity lead-in stays out of the running list. It is a
        // notification about this countdown rather than an event within it, and
        // by the time it fires the user is already looking at the screen.
        if microBreakEnabled,
           let reminders = try? CountdownRules.shared.reminders(
               input: rulesInput(at: now),
               reminderInputs: reminderInputs()
           ),
           let next = reminders
               .filter({ $0.kind == "microBreak" && isDuringShift($0.atMs) })
               .min(by: { $0.atMs < $1.atMs }) {
            events.append(.init(
                id: next.id,
                kind: .health,
                date: Date(timeIntervalSince1970: next.atMs / 1_000),
                title: t("microBreakReminder"),
                detail: t("minutesShort", values: ["count": "\(microBreakIntervalMinutes)"])
            ))
        }

        // One row per push. Unlike the micro-break these fire at distinct points
        // rather than on a cycle, and seeing them is what turns "ends at 23:00"
        // into a shift broken into markers — which is why they live here, on the
        // running screen, and not in the pre-start preview.
        //
        // A milestone the rules engine left untitled is a silent tick rather
        // than a push, so it gets no row; that is also what keeps "at off-work
        // time only" from listing anything, since its one audible milestone is
        // the shift's end and the list already has a row for that.
        if notificationMode == .milestones {
            events.append(contentsOf: (try? CountdownRules.shared.reminders(
                input: rulesInput(at: now),
                reminderInputs: reminderInputs()
            ))?
                // The 100% milestone lands on the stroke of the shift's end,
                // where the list already has a row saying exactly that. Two
                // rows at 19:00 is not two events.
                //
                // Matched by suffix, not equality: the JS bridge re-keys every
                // reminder as "<scope>:<shiftEnd>:<id>" before handing it back,
                // so the rule engine's own "milestone:100" is only ever the tail
                // of what arrives here.
                .filter {
                    $0.kind == "milestone" && !$0.id.hasSuffix(":milestone:100")
                        && $0.title != nil && isDuringShift($0.atMs)
                }
                .map { reminder in
                    UpcomingTimelineEvent(
                        id: reminder.id,
                        kind: .milestone,
                        date: Date(timeIntervalSince1970: reminder.atMs / 1_000),
                        title: t("offWorkReminder"),
                        detail: reminder.title ?? ""
                    )
                } ?? [])
        }

        if snapshot.endAtMs > nowMs {
            events.append(.init(
                id: "shift-end-\(Int64(snapshot.endAtMs))",
                kind: .shiftEnd,
                date: snapshot.endDate,
                title: t("endTime"),
                detail: snapshot.overtimeEndAtMs == nil ? t("todaysShift") : t("overtime")
            ))
        }

        func boundaryOrder(_ kind: UpcomingTimelineEvent.Kind) -> Int {
            switch kind {
            case .shiftStart: 0
            case .shiftEnd: 2
            default: 1
            }
        }

        return events.sorted {
            if $0.date == $1.date {
                let leftOrder = boundaryOrder($0.kind)
                let rightOrder = boundaryOrder($1.kind)
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return $0.id < $1.id
            }
            return $0.date < $1.date
        }
    }

    /// Commits the setup draft. This is not undo: an early clock-off that still
    /// covers this shift stays until `undoEarlyClockOff`, overtime, or a
    /// genuinely new shift that does not overlap the ended one.
    func applySettings(force: Bool = false, at date: Date = .now) {
        startCountdown(force: force, at: date)
    }

    func startCountdown(force: Bool = false, at date: Date = .now) {
        if scheduleMode == .off {
            // Manual "start" is a new session. A leftover early-off from a
            // scheduled day that was then switched to off would otherwise pin
            // this button to setup: ended-early only dismisses, never runs.
            clearEarlyClockOffRecord()
            dismissedCompletedEndAtMs = nil
        }
        let hadDraft = draftStartMinutes != nil || draftEndMinutes != nil
        commitDisplayedHours()
        countdownStarted = true
        let shift = snapshot(at: date)
        // The day the shift starts, not the day the button was pressed. They
        // differ for an overnight shift forced after midnight, and marking the
        // press day there would mark a run nobody is looking at.
        forcedWorkdayDate = force ? Self.dayKey(for: shift?.startDate ?? date) : nil
        if let shift, isEndedEarly(shift) {
            // Same shift, possibly with nudged hours. Keep the early-off
            // record and pin dismiss to the new end so setup does not bounce
            // back into the celebration.
            dismissedCompletedEndAtMs = shift.endAtMs
        } else {
            // A different shift, or none. The old record must not leak onto it.
            clearEarlyClockOffRecord()
            // A draft that has been applied is a new configuration, even if it
            // lands on a remaining of zero. An apply with nothing pending keeps
            // a dismissed celebration from bouncing straight back.
            if hadDraft || (shift?.remainingMs ?? 0) > 0 {
                dismissedCompletedEndAtMs = nil
            }
        }
        recordActiveCountdownBoundary(at: date)
    }

    /// Ends today's shift early. On a schedule this is a record, not a switch.
    ///
    /// It used to clear `countdownStarted`, which had no way back: the flag is
    /// only ever set by a manual start, so one press silenced every scheduled
    /// shift after it too. The widget then spent working hours counting down to
    /// tomorrow's clock-in under the words "好好休息".
    ///
    /// A schedule does not have sessions to stop, so there is nothing here for
    /// a session flag to mean. What the user is telling us is that they have
    /// finished for the day, and that is a fact about them rather than about the
    /// configuration — so it is written down and the schedule keeps running.
    /// Whether the clock-off button is waiting for its second press.
    ///
    /// Held here rather than in the button because the action exists across
    /// several timer layouts, and separate confirmation states could remain
    /// armed after another layout has already fired.
    var clockOffConfirmPending = false

    /// First press arms, second press commits. Ending the day early is not
    /// something to do by brushing past a button, and unlike the old "return"
    /// it now writes a record rather than flipping a switch back.
    func requestClockOffEarly(at date: Date = .now) {
        guard scheduleMode != .off else {
            stopCountdown()
            return
        }
        guard snapshot(at: date) != nil else { return }
        guard clockOffConfirmPending else {
            clockOffConfirmPending = true
            return
        }
        clockOffConfirmPending = false
        clockOffEarly(at: date)
    }

    /// Disarms without acting. Anything that takes the user's attention
    /// elsewhere should call this: a confirmation still waiting when they come
    /// back would fire on a press they meant as their first.
    func cancelClockOffConfirmation() {
        if clockOffConfirmPending { clockOffConfirmPending = false }
    }

    func clockOffEarly(at date: Date = .now) {
        guard scheduleMode != .off else {
            stopCountdown()
            return
        }
        // No shift means there is nothing to end. Writing the timestamps
        // anyway left a record that `isEndedEarly` can never match, while
        // still clearing today's forced-workday mark.
        guard let shift = snapshot(at: date) else { return }
        earlyOffAtMs = date.timeIntervalSince1970 * 1_000
        earlyOffShiftEndAtMs = shift.endAtMs
        earlyOffSnapshot = shift
        dismissedCompletedEndAtMs = nil
        clockOffConfirmPending = false
        timelineExpanded = false
        forcedWorkdayDate = nil
        activeCountdownEndAtMs = nil
        // Leave overtime in place. Clearing it here shrinks the shift back to
        // the planned end, so a clock-off during overtime no longer overlaps
        // that window and the completed page loses the extra hours, pay, and undo.
    }

    /// Takes it back. Deliberately its own action rather than a side effect of
    /// editing the schedule: changing tomorrow's hours must never quietly
    /// resurrect today, or every settings visit becomes a coin toss.
    func undoEarlyClockOff() {
        clearEarlyClockOffRecord()
        dismissedCompletedEndAtMs = nil
        recordActiveCountdownBoundary()
    }

    /// Whether `shift` is one the user already ended by hand.
    ///
    /// The comparison is against the shift's own window, so a later change to
    /// the hours cannot un-end it, and a genuinely new shift beginning after
    /// that moment is not caught by it.
    func isEndedEarly(_ shift: NativeShiftSnapshot) -> Bool {
        guard let earlyOffAtMs, let earlyOffShiftEndAtMs else { return false }
        // Overlaps the shift that was ended. Two properties fall out of that
        // one sentence: nudge the hours and it is still the same shift, so it
        // stays finished; move them far enough that a new shift begins after
        // the ended one, and it does not overlap, so it counts.
        return shift.endAtMs > earlyOffAtMs && shift.startAtMs < earlyOffShiftEndAtMs
    }

    /// Leaves the completed celebration without disarming a schedule.
    ///
    /// Manual mode still has a session to stop. On a schedule the day already
    /// ended on its own; this only puts the setup page back on screen so
    /// changing tomorrow does not silence every shift after it. Early clock-off
    /// still has remaining time on the rules snapshot, so remaining alone is
    /// not enough to recognise a finished day.
    func dismissCompletedShift(at date: Date = .now) {
        guard scheduleMode != .off else {
            stopCountdown()
            return
        }
        guard let shift = snapshot(at: date),
              shift.remainingMs <= 0 || isEndedEarly(shift)
        else { return }
        dismissedCompletedEndAtMs = shift.endAtMs
        timelineExpanded = false
    }

    /// Copy for the undo banner. Present while an early clock-off still covers
    /// the current shift; once the planned end has passed there is nothing left
    /// to undo.
    func earlyClockOffNote(for shift: NativeShiftSnapshot) -> String? {
        guard let earlyOffAtMs, isEndedEarly(shift) else { return nil }
        let at = Date(timeIntervalSince1970: earlyOffAtMs / 1_000)
        return t("clockedOffEarlyNote", values: ["time": formatTime(at)])
    }

    func earlyClockOffNote(at date: Date = .now) -> String? {
        guard let shift = snapshot(at: date) else { return nil }
        return earlyClockOffNote(for: shift)
    }

    /// The shift as it stood when the user clocked off, so completed figures
    /// do not keep growing after that moment, and do not rebuild from later
    /// settings edits. Next-shift times stay live so tomorrow's hours can move.
    func clockOffSnapshot(for shift: NativeShiftSnapshot) -> NativeShiftSnapshot {
        guard isEndedEarly(shift) else { return shift }
        guard let frozen = earlyOffSnapshot else { return shift }
        return frozen.withLiveNextShift(from: shift)
    }

    func isShiftComplete(_ shift: NativeShiftSnapshot) -> Bool {
        shift.remainingMs <= 0 || isEndedEarly(shift)
    }

    func isDismissedCompleted(_ shift: NativeShiftSnapshot) -> Bool {
        guard let dismissedCompletedEndAtMs else { return false }
        return shift.endAtMs == dismissedCompletedEndAtMs
    }

    func visualPhase(snapshot: NativeShiftSnapshot?) -> TimerVisualPhase {
        TimerVisualPhase.resolve(
            countdownStarted: countdownStarted,
            snapshot: snapshot,
            forceToday: snapshot.map(isForcedWorkday) ?? false,
            endedEarly: snapshot.map(isEndedEarly) ?? false,
            dismissedCompleted: snapshot.map(isDismissedCompleted) ?? false
        )
    }

    func visualPhase(at date: Date = .now) -> TimerVisualPhase {
        visualPhase(snapshot: countdownStarted ? snapshot(at: date) : nil)
    }

    /// Reminders that still belong to a shift the user has already ended.
    func shouldDeliverReminder(_ reminder: NativeReminder, for snapshot: NativeShiftSnapshot) -> Bool {
        guard isEndedEarly(snapshot) else { return true }
        // Classic with an empty workday set has no next shift. Falling back
        // to `endAtMs` with `>=` would also let milestone:100 through, because
        // that fires at exactly the planned end.
        guard let nextStart = snapshot.nextShiftStartAtMs else { return false }
        return reminder.atMs >= nextStart
    }

    func stopCountdown() {
        clockOffConfirmPending = false
        countdownStarted = false
        timelineExpanded = false
        forcedWorkdayDate = nil
        activeCountdownEndAtMs = nil
        dismissedCompletedEndAtMs = nil
        draftStartMinutes = nil
        draftEndMinutes = nil
        clearOvertime()
    }

    /// Scheduled countdowns stay armed across calendar days. The concrete
    /// boundary still scopes one-off state such as overtime and a forced rest-
    /// day run to the shift that created it. Manual (`scheduleMode == .off`)
    /// countdowns retain their one-session behavior and reset after the end day.
    @discardableResult
    func reconcileCountdownSession(at date: Date = .now) -> Bool {
        guard countdownStarted else {
            activeCountdownEndAtMs = nil
            return false
        }

        if scheduleMode != .off {
            var changed = false
            let current = snapshot(at: date)

            if let overtimeEndAtMs {
                let overtimeEnd = Date(timeIntervalSince1970: overtimeEndAtMs / 1_000)
                let overtimeEndDay = Calendar.current.startOfDay(for: overtimeEnd)
                if let resetDate = Calendar.current.date(byAdding: .day, value: 1, to: overtimeEndDay),
                   date >= resetDate {
                    self.overtimeEndAtMs = nil
                    changed = true
                }
            }

            // Everything below needs a shift to compare against. Without one
            // the rules are unavailable, and deleting a record because it
            // cannot be matched right now is how a forced run disappears.
            guard let current else { return changed }

            // One-off marks are scoped to the shift that created them, and each
            // already reads as "off" once the schedule has moved past it, so
            // removing them changes no behaviour. What it removes is dead
            // weight nothing else clears: a past day key and two past
            // timestamps no later shift can match, plus the frozen clock-off
            // snapshot, which otherwise sits in defaults indefinitely.
            if forcedWorkdayDate != nil, !isForcedWorkday(current) {
                forcedWorkdayDate = nil
                changed = true
            }
            if dismissedCompletedEndAtMs != nil, !isDismissedCompleted(current) {
                dismissedCompletedEndAtMs = nil
                changed = true
            }
            if earlyOffAtMs != nil, !isEndedEarly(current) {
                clearEarlyClockOffRecord()
                changed = true
            }

            if activeCountdownEndAtMs != current.endAtMs {
                activeCountdownEndAtMs = current.endAtMs
                changed = true
            }
            return changed
        }

        guard let activeCountdownEndAtMs else {
            // Migration for sessions created before the concrete boundary was
            // persisted. Preserve an actually running shift, but do not let an
            // already-finished or not-yet-started resolved shift masquerade as
            // the old session.
            guard let current = snapshot(at: date),
                  current.remainingMs > 0,
                  current.startAtMs <= date.timeIntervalSince1970 * 1_000
            else {
                stopCountdown()
                return true
            }
            self.activeCountdownEndAtMs = current.endAtMs
            return false
        }

        let endDate = Date(timeIntervalSince1970: activeCountdownEndAtMs / 1_000)
        let endDay = Calendar.current.startOfDay(for: endDate)
        guard let resetDate = Calendar.current.date(byAdding: .day, value: 1, to: endDay),
              date >= resetDate
        else { return false }

        stopCountdown()
        return true
    }

    func completeOnboarding(enableNotifications: Bool) {
        onboardingComplete = true
        // Deliberately does NOT reset onboardingPage. The welcome view is still
        // on screen for the length of the cross-fade, and resetting the page
        // snapped it back to the first slide mid-transition. `onboardingPage` is
        // not persisted, so a replay starts at 0 on its own.
        if enableNotifications { notificationMode = .simple }
        if scheduleMode != .off { startCountdown() }
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
        !lunchEnabled || CountdownRules.shared.validateBreak(input: rulesInput(
            startMinutes: displayedStartMinutes,
            endMinutes: displayedEndMinutes
        ))
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
        activeCountdownEndAtMs = overtimeEndAtMs
        // Overtime after an early clock-off is "I wasn't done".
        clearEarlyClockOffRecord()
        dismissedCompletedEndAtMs = nil
    }

    private func clearEarlyClockOffRecord() {
        earlyOffAtMs = nil
        earlyOffShiftEndAtMs = nil
        earlyOffSnapshot = nil
    }

    private func persistEarlyOffSnapshot() {
        if let earlyOffSnapshot, let data = try? JSONEncoder().encode(earlyOffSnapshot) {
            defaults.set(data, forKey: Key.earlyOffSnapshot)
        } else {
            defaults.removeObject(forKey: Key.earlyOffSnapshot)
        }
    }

    private static func decodeEarlyOffSnapshot(from defaults: UserDefaults) -> NativeShiftSnapshot? {
        guard let data = defaults.data(forKey: Key.earlyOffSnapshot) else { return nil }
        return try? JSONDecoder().decode(NativeShiftSnapshot.self, from: data)
    }

    func clearOvertime() {
        if overtimeEndAtMs != nil { overtimeEndAtMs = nil }
        if countdownStarted { recordActiveCountdownBoundary() }
    }

    private func recordActiveCountdownBoundary(at date: Date = .now) {
        activeCountdownEndAtMs = snapshot(at: date)?.endAtMs
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
        RelativeDurationFormatter.string(milliseconds: milliseconds, languageCode: languageCode)
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

    func formatPercent(_ value: Double) -> String {
        (value / 100).formatted(
            .percent.precision(.fractionLength(1)).locale(locale)
        )
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
        if isForcedWorkday(snapshot) {
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
