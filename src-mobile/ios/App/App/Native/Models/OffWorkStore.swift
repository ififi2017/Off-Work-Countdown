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

enum ScheduleChangeDecision: String, Equatable {
    case nextShiftOnly
    case applyToToday
}

enum RulesScheduleSource {
    /// Today's override and an early clock-in, if they still cover `date`.
    case effective
    /// Persisted hours and pattern. Future shifts and `nextShift*` use this
    /// so "from the next shift only" does not paint a year of old times.
    case base
}

/// One settings mutation that must ask whether today is included.
struct ScheduleFieldChange: Equatable {
    var startMinutes: Int?
    var endMinutes: Int?
    var workdays: Set<Int>?
    var scheduleMode: WorkScheduleMode?
    var lunchEnabled: Bool?
    var lunchStartMinutes: Int?
    var lunchDurationMinutes: Int?
    var alternatingWeekType: AlternatingWeekType?
    var alternatingWeekendWorkday: Int?
    var rotationWorkDays: Int?
    var rotationRestDays: Int?
    var rotationCycleDay: Int?
}

/// Hours and calendar in force until the current shift's settlement seam.
/// The committed fields already hold the future schedule.
private struct TodayScheduleOverride: Codable, Equatable {
    var startMinutes: Int
    var endMinutes: Int
    var workdays: [Int]
    var scheduleMode: String
    var lunchEnabled: Bool
    var lunchStartMinutes: Int
    var lunchDurationMinutes: Int
    var alternatingWeekType: String
    var alternatingWeekendWorkday: Int
    var alternatingReferenceWeekStartMs: Double
    var rotationWorkDays: Int
    var rotationRestDays: Int
    var rotationAnchorMs: Double
    var untilMs: Double
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
        static let earlyStartAtMs = "ios.native.earlyStartAtMs"
        static let earlyStartUntilMs = "ios.native.earlyStartUntilMs"
        static let todayScheduleOverride = "ios.native.todayScheduleOverride"
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

    /// Hours the setup page is editing. Settings commits through the
    /// next-shift / today prompt rather than this draft; onboarding still
    /// writes hours directly.
    var draftStartMinutes: Int?
    var draftEndMinutes: Int?

    /// The two navigation stacks, held here rather than in the shells so a
    /// pushed page survives a rotation — portrait and landscape are separate
    /// view trees, and each used to own its own path. Not persisted.
    var timerPath: [AppRoute] = []
    var settingsPath: [AppRoute] = []
    /// Survives the page that asked it. Lunch duration still needs the prompt
    /// after the detail has popped.
    var pendingSchedulePrompt: ScheduleFieldChange?

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
    /// 007 no longer dismisses settlement back to a configuration page. The
    /// value is still read on upgrade so an old mark can be cleared, and is
    /// never written from new UI.
    var dismissedCompletedEndAtMs: Double? {
        didSet { defaults.set(dismissedCompletedEndAtMs, forKey: Key.dismissedCompletedEndAtMs) }
    }

    /// Clocked in before the planned start. Bound to the settlement seam of
    /// that shift so a leftover 08:00 does not become tomorrow's start.
    var earlyStartAtMs: Double? {
        didSet {
            if let earlyStartAtMs { defaults.set(earlyStartAtMs, forKey: Key.earlyStartAtMs) }
            else { defaults.removeObject(forKey: Key.earlyStartAtMs) }
        }
    }
    private var earlyStartUntilMs: Double? {
        didSet {
            if let earlyStartUntilMs { defaults.set(earlyStartUntilMs, forKey: Key.earlyStartUntilMs) }
            else { defaults.removeObject(forKey: Key.earlyStartUntilMs) }
        }
    }
    private var todayOverride: TodayScheduleOverride? {
        didSet { persistTodayOverride() }
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
            draftStartMinutes = nil
        }
    }
    var endMinutes: Int {
        didSet {
            defaults.set(endMinutes, forKey: Key.endMinutes)
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
        earlyStartAtMs = defaults.object(forKey: Key.earlyStartAtMs) as? Double
        earlyStartUntilMs = defaults.object(forKey: Key.earlyStartUntilMs) as? Double
        todayOverride = Self.decodeTodayOverride(from: defaults)
        dismissedCompletedEndAtMs = defaults.object(forKey: Key.dismissedCompletedEndAtMs) as? Double
        activeCountdownEndAtMs = defaults.object(forKey: Key.activeCountdownEndAtMs) as? Double
        lastCelebratedEndAtMs = defaults.double(forKey: Key.lastCelebratedEndAtMs)

        if scheduleMode == .classic, workdays.isEmpty {
            workdays = [1, 2, 3, 4, 5]
        }

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
            var result = try CountdownRules.shared.snapshot(input: rulesInput(
                at: date,
                startMinutes: startMinutes,
                endMinutes: endMinutes
            ))
            if startMinutes == nil, endMinutes == nil, projectsFutureFromBase(at: date),
               let projected = try? CountdownRules.shared.snapshot(
                input: rulesInput(at: date, using: .base)
               ) {
                result = result.withProjectedFuture(from: projected)
            }
            if lastRulesError != nil { lastRulesError = nil }
            return result
        } catch {
            lastRulesError = error.localizedDescription
            return nil
        }
    }

    /// Snapshot of the hours a picker is currently showing, including
    /// uncommitted edits. The timer phase must not use this.
    func setupSnapshot(at date: Date = .now) -> NativeShiftSnapshot? {
        snapshot(at: date, startMinutes: displayedStartMinutes, endMinutes: displayedEndMinutes)
    }

    func rulesInput(
        at date: Date = .now,
        startMinutes: Int? = nil,
        endMinutes: Int? = nil,
        using source: RulesScheduleSource = .effective
    ) -> NativeRulesInput {
        let applyOverride = source == .effective
        let start = startMinutes ?? (applyOverride ? effectiveStartMinutes(at: date) : self.startMinutes)
        let end = endMinutes ?? (applyOverride ? effectiveEndMinutes(at: date) : self.endMinutes)
        let lunchOn = applyOverride ? effectiveLunchEnabled(at: date) : lunchEnabled
        return .init(
            startTime: timeString(start),
            endTime: timeString(end),
            nowMs: date.timeIntervalSince1970 * 1_000,
            workdays: (applyOverride ? effectiveWorkdays(at: date) : workdays).sorted(),
            schedule: nativeSchedule(at: date, using: source),
            breakStartTime: lunchOn
                ? timeString(applyOverride ? effectiveLunchStartMinutes(at: date) : lunchStartMinutes)
                : nil,
            breakDurationMinutes: lunchOn
                ? (applyOverride ? effectiveLunchDurationMinutes(at: date) : lunchDurationMinutes)
                : 0,
            overtimeEndAtMs: applyOverride ? overtimeEndAtMs : nil,
            salaryAmount: salaryEnabled ? salaryAmount : "",
            salaryType: salaryType.rawValue,
            monthlyWorkingDays: monthlyWorkingDays,
            annualBonusMonths: annualBonusEnabled ? annualBonusMonths : 0,
            forcedWorkdayStartMs: applyOverride ? forcedWorkdayStartMs : nil
        )
    }

    func shiftReminders(at date: Date = .now) throws -> [NativeReminder] {
        let inputs = reminderInputs()
        let effective = try CountdownRules.shared.reminders(
            input: rulesInput(at: date),
            reminderInputs: inputs
        )
        let current = effective.filter { $0.id.hasPrefix("current:") }
        let next: [NativeReminder]
        if projectsFutureFromBase(at: date) {
            next = try CountdownRules.shared.reminders(
                input: rulesInput(at: date, using: .base),
                reminderInputs: inputs
            ).filter { $0.id.hasPrefix("next:") }
        } else {
            next = effective.filter { $0.id.hasPrefix("next:") }
        }
        guard let snapshot = snapshot(at: date) else { return current + next }
        // Rest days and settlement both still produce a `current:` window from
        // `getShiftBounds` — Saturday 09:00–17:00 on a weekend, or Saturday
        // 22:00 after a Friday overnight ended at 06:00. Those are not a shift
        // the user is in, so they must not be scheduled.
        let includeCurrent = (snapshot.isWorkday || isForcedWorkday(snapshot))
            && !isShiftComplete(snapshot)
        return (includeCurrent ? current : []) + next
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

    /// Starts a manual session (unscheduled or a rest-day override).
    func applySettings(force: Bool = false, at date: Date = .now) {
        startCountdown(force: force, at: date)
    }

    func startCountdown(force: Bool = false, at date: Date = .now) {
        if scheduleMode == .off {
            // Manual "start" is a new session. A leftover early-off from a
            // scheduled day that was then switched to off would otherwise pin
            // this button to settlement: ended-early never runs.
            clearEarlyClockOffRecord()
            clearEarlyClockInRecord()
            dismissedCompletedEndAtMs = nil
        }
        commitDisplayedHours()
        countdownStarted = true
        let shift = snapshot(at: date)
        // The day the shift starts, not the day the button was pressed. They
        // differ for an overnight shift forced after midnight, and marking the
        // press day there would mark a run nobody is looking at.
        forcedWorkdayDate = force ? Self.dayKey(for: shift?.startDate ?? date) : nil
        if let shift, isEndedEarly(shift) {
            // Same shift, possibly with nudged hours. Keep the early-off
            // record so settlement stays on this run.
        } else {
            clearEarlyClockOffRecord()
            dismissedCompletedEndAtMs = nil
        }
        recordActiveCountdownBoundary(at: date)
    }

    /// Ends today's shift early. On a schedule this is a record, not a switch.
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
    var cancelManualTimingConfirmPending = false

    /// First press arms, second press commits. Ending the day early is not
    /// something to do by brushing past a button.
    func requestClockOffEarly(at date: Date = .now) {
        guard let shift = snapshot(at: date), !shift.isBeforeStart(at: date) else { return }
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
        if cancelManualTimingConfirmPending { cancelManualTimingConfirmPending = false }
    }

    func clockOffEarly(at date: Date = .now) {
        guard let shift = snapshot(at: date), !shift.isBeforeStart(at: date) else { return }
        earlyOffAtMs = date.timeIntervalSince1970 * 1_000
        earlyOffShiftEndAtMs = shift.endAtMs
        earlyOffSnapshot = shift
        dismissedCompletedEndAtMs = nil
        clockOffConfirmPending = false
        timelineExpanded = false
        // Leave a forced rest-day run in place until settlement: cancelling
        // manual timing is a different action. Clocking off still ends the day.
        forcedWorkdayDate = isForcedWorkday(shift) ? forcedWorkdayDate : nil
        // Keep the session boundary so an unscheduled midnight reset still
        // knows which calendar day this run belonged to. Overtime stays too:
        // clearing it here would shrink the window and settlement would lose
        // the extra hours.
    }

    /// Takes it back. Deliberately its own action rather than a side effect of
    /// editing the schedule: changing tomorrow's hours must never quietly
    /// resurrect today, or every settings visit becomes a coin toss.
    func undoEarlyClockOff() {
        clearEarlyClockOffRecord()
        dismissedCompletedEndAtMs = nil
        recordActiveCountdownBoundary()
    }

    func clockInEarly(at date: Date = .now) {
        guard let shift = snapshot(at: date), shift.isBeforeStart(at: date) else { return }
        let floored = Self.floorToMinute(date)
        earlyStartAtMs = floored.timeIntervalSince1970 * 1_000
        let endDay = Calendar.current.startOfDay(for: shift.endDate)
        earlyStartUntilMs = Calendar.current.date(byAdding: .day, value: 1, to: endDay)
            .map { $0.timeIntervalSince1970 * 1_000 }
    }

    func undoEarlyClockIn() {
        clearEarlyClockInRecord()
        recordActiveCountdownBoundary()
    }

    func isStartedEarly(at date: Date = .now) -> Bool {
        guard let earlyStartAtMs, let earlyStartUntilMs else { return false }
        let nowMs = date.timeIntervalSince1970 * 1_000
        return nowMs >= earlyStartAtMs && nowMs < earlyStartUntilMs
    }

    func requestCancelManualTiming() {
        guard cancelManualTimingConfirmPending else {
            cancelManualTimingConfirmPending = true
            return
        }
        cancelManualTimingConfirmPending = false
        cancelManualTiming()
    }

    /// Rest-day manual timing only. Does not leave an "I worked" record.
    func cancelManualTiming() {
        forcedWorkdayDate = nil
        cancelManualTimingConfirmPending = false
        clockOffConfirmPending = false
        timelineExpanded = false
        clearEarlyClockOffRecord()
        clearEarlyClockInRecord()
        clearOvertime()
        recordActiveCountdownBoundary()
    }

    /// Whether `shift` is one the user already ended by hand.
    ///
    /// The comparison is against the shift's own window, so a later change to
    /// the hours cannot un-end it, and a genuinely new shift beginning after
    /// that moment is not caught by it.
    func isEndedEarly(_ shift: NativeShiftSnapshot) -> Bool {
        guard let earlyOffAtMs, let earlyOffShiftEndAtMs else { return false }
        return shift.endAtMs > earlyOffAtMs && shift.startAtMs < earlyOffShiftEndAtMs
    }

    /// Settlement is not dismissible. Kept as a no-op so older tests and
    /// call sites compile while they are rewritten.
    func dismissCompletedShift(at date: Date = .now) {
        _ = date
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

    func earlyClockInNote(at date: Date = .now) -> String? {
        guard isStartedEarly(at: date), let earlyStartAtMs else { return nil }
        let at = Date(timeIntervalSince1970: earlyStartAtMs / 1_000)
        return t("clockedInEarlyNote", values: ["time": formatTime(at)])
    }

    /// The shift as it stood when the user clocked off, so completed figures
    /// do not keep growing after that moment, and do not rebuild from later
    /// settings edits. Next-shift times stay live so tomorrow's hours can move.
    func clockOffSnapshot(for shift: NativeShiftSnapshot) -> NativeShiftSnapshot {
        guard isEndedEarly(shift) else { return shift }
        guard let frozen = earlyOffSnapshot else { return shift }
        return frozen.withProjectedFuture(from: shift)
    }

    func isShiftComplete(_ shift: NativeShiftSnapshot) -> Bool {
        shift.remainingMs <= 0 || isEndedEarly(shift)
    }

    func isDismissedCompleted(_ shift: NativeShiftSnapshot) -> Bool {
        guard let dismissedCompletedEndAtMs else { return false }
        return shift.endAtMs == dismissedCompletedEndAtMs
    }

    var publishesLiveSurfaces: Bool {
        onboardingComplete && (followsSchedule || countdownStarted)
    }

    var followsSchedule: Bool { followsSchedule(at: .now) }

    func followsSchedule(at date: Date = .now) -> Bool {
        onboardingComplete && effectiveScheduleMode(at: date) != .off
    }

    func shouldQuerySnapshot(at date: Date = .now) -> Bool {
        followsSchedule(at: date) || countdownStarted
    }

    func visualPhase(snapshot: NativeShiftSnapshot?, at date: Date = .now) -> TimerVisualPhase {
        TimerVisualPhase.resolve(
            followsSchedule: followsSchedule(at: date),
            sessionActive: countdownStarted,
            snapshot: snapshot,
            forceToday: snapshot.map(isForcedWorkday) ?? false,
            endedEarly: snapshot.map(isEndedEarly) ?? false
        )
    }

    func visualPhase(at date: Date = .now) -> TimerVisualPhase {
        visualPhase(
            snapshot: shouldQuerySnapshot(at: date) ? snapshot(at: date) : nil,
            at: date
        )
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
        // A schedule has no session to stop. Unscheduled midnight still
        // tears down today's manual run.
        guard !followsSchedule else {
            clockOffConfirmPending = false
            cancelManualTimingConfirmPending = false
            return
        }
        clockOffConfirmPending = false
        cancelManualTimingConfirmPending = false
        countdownStarted = false
        timelineExpanded = false
        forcedWorkdayDate = nil
        activeCountdownEndAtMs = nil
        dismissedCompletedEndAtMs = nil
        draftStartMinutes = nil
        draftEndMinutes = nil
        clearOvertime()
        clearEarlyClockInRecord()
        clearEarlyClockOffRecord()
    }

    /// Scheduled countdowns stay armed across calendar days. The concrete
    /// boundary still scopes one-off state such as overtime and a forced rest-
    /// day run to the shift that created it. Manual (`scheduleMode == .off`)
    /// countdowns retain their one-session behavior and reset after the end day.
    @discardableResult
    func reconcileCountdownSession(at date: Date = .now) -> Bool {
        var changed = false
        if let override = todayOverride, date.timeIntervalSince1970 * 1_000 >= override.untilMs {
            todayOverride = nil
            changed = true
            if scheduleMode == .off {
                stopUnscheduledSession(at: date)
            }
        }
        if let earlyStartUntilMs, date.timeIntervalSince1970 * 1_000 >= earlyStartUntilMs {
            clearEarlyClockInRecord()
            changed = true
        }

        guard countdownStarted || followsSchedule(at: date) else {
            activeCountdownEndAtMs = nil
            return changed
        }

        if followsSchedule(at: date) {
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
            // An early clock-off that lost its boundary (older builds cleared
            // it) must still wait until that end day's next midnight. The
            // snapshot on the following morning is a different shift, so
            // `isEndedEarly` would not catch it.
            if let endMs = earlyOffShiftEndAtMs ?? earlyOffAtMs {
                let endDate = Date(timeIntervalSince1970: endMs / 1_000)
                let endDay = Calendar.current.startOfDay(for: endDate)
                if let resetDate = Calendar.current.date(byAdding: .day, value: 1, to: endDay),
                   date >= resetDate {
                    stopCountdown()
                    return true
                }
                return changed
            }
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
            return changed
        }

        let endDate = Date(timeIntervalSince1970: activeCountdownEndAtMs / 1_000)
        let endDay = Calendar.current.startOfDay(for: endDate)
        guard let resetDate = Calendar.current.date(byAdding: .day, value: 1, to: endDay),
              date >= resetDate
        else { return changed }

        stopCountdown()
        return true
    }

    private func stopUnscheduledSession(at date: Date) {
        _ = date
        countdownStarted = false
        timelineExpanded = false
        forcedWorkdayDate = nil
        activeCountdownEndAtMs = nil
        draftStartMinutes = nil
        draftEndMinutes = nil
        clearOvertime()
        clearEarlyClockInRecord()
        clearEarlyClockOffRecord()
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
        if workdays.contains(day) {
            guard workdays.count > 1 else { return }
            workdays.remove(day)
        } else {
            workdays.insert(day)
        }
    }

    var canRemoveLastWorkday: Bool { workdays.count <= 1 }

    var nativeSchedule: NativeWorkSchedule { nativeSchedule(at: .now) }

    func nativeSchedule(at date: Date, using source: RulesScheduleSource = .effective) -> NativeWorkSchedule {
        let applyOverride = source == .effective && usesTodayOverride(at: date)
        let mode = applyOverride ? effectiveScheduleMode(at: date) : scheduleMode
        let weekType = applyOverride
            ? (todayOverride.flatMap { AlternatingWeekType(rawValue: $0.alternatingWeekType) } ?? alternatingWeekType)
            : alternatingWeekType
        let weekendDay = applyOverride
            ? (todayOverride?.alternatingWeekendWorkday ?? alternatingWeekendWorkday)
            : alternatingWeekendWorkday
        let weekStart = applyOverride
            ? (todayOverride?.alternatingReferenceWeekStartMs ?? alternatingReferenceWeekStartMs)
            : alternatingReferenceWeekStartMs
        let rotWork = applyOverride
            ? (todayOverride?.rotationWorkDays ?? rotationWorkDays)
            : rotationWorkDays
        let rotRest = applyOverride
            ? (todayOverride?.rotationRestDays ?? rotationRestDays)
            : rotationRestDays
        let rotAnchor = applyOverride
            ? (todayOverride?.rotationAnchorMs ?? rotationAnchorMs)
            : rotationAnchorMs
        return .init(
            mode: mode.rawValue,
            referenceWeekStartMs: mode == .alternating ? weekStart : nil,
            referenceWeekType: mode == .alternating ? weekType.rawValue : nil,
            singleWeekendWorkday: mode == .alternating ? weekendDay : nil,
            rotationAnchorMs: mode == .rotation ? rotAnchor : nil,
            rotationWorkDays: mode == .rotation ? rotWork : nil,
            rotationRestDays: mode == .rotation ? rotRest : nil
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

    func applyScheduleChange(
        _ change: ScheduleFieldChange,
        decision: ScheduleChangeDecision,
        at date: Date = .now
    ) {
        if decision == .nextShiftOnly, let until = overrideExpiry(at: date) {
            todayOverride = captureSchedule(untilMs: until)
        } else {
            todayOverride = nil
        }

        if let startMinutes = change.startMinutes { self.startMinutes = startMinutes }
        if let endMinutes = change.endMinutes { self.endMinutes = endMinutes }
        if let workdays = change.workdays {
            self.workdays = workdays.isEmpty ? self.workdays : workdays
        }
        if let scheduleMode = change.scheduleMode {
            self.scheduleMode = scheduleMode
            if scheduleMode == .alternating { anchorAlternatingWeekToToday() }
            if scheduleMode == .rotation { anchorRotationToToday() }
        }
        if let lunchEnabled = change.lunchEnabled { self.lunchEnabled = lunchEnabled }
        if let lunchStartMinutes = change.lunchStartMinutes { self.lunchStartMinutes = lunchStartMinutes }
        if let lunchDurationMinutes = change.lunchDurationMinutes {
            self.lunchDurationMinutes = lunchDurationMinutes
        }
        if let alternatingWeekType = change.alternatingWeekType {
            self.alternatingWeekType = alternatingWeekType
            anchorAlternatingWeekToToday()
        }
        if let alternatingWeekendWorkday = change.alternatingWeekendWorkday {
            self.alternatingWeekendWorkday = alternatingWeekendWorkday
        }
        if let rotationWorkDays = change.rotationWorkDays { self.rotationWorkDays = rotationWorkDays }
        if let rotationRestDays = change.rotationRestDays { self.rotationRestDays = rotationRestDays }
        if let rotationCycleDay = change.rotationCycleDay { setRotationCycleDay(rotationCycleDay) }

        if decision == .applyToToday {
            todayOverride = nil
            clearTodayAdjustments()
            if self.scheduleMode == .off {
                stopUnscheduledSession(at: date)
            } else if onboardingComplete {
                countdownStarted = true
                recordActiveCountdownBoundary(at: date)
            }
        } else if self.scheduleMode != .off, onboardingComplete {
            countdownStarted = true
        }
    }

    private func clearTodayAdjustments() {
        clearEarlyClockOffRecord()
        clearEarlyClockInRecord()
        clearOvertime()
        dismissedCompletedEndAtMs = nil
        forcedWorkdayDate = nil
    }

    private func captureSchedule(untilMs: Double) -> TodayScheduleOverride {
        .init(
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            workdays: workdays.sorted(),
            scheduleMode: scheduleMode.rawValue,
            lunchEnabled: lunchEnabled,
            lunchStartMinutes: lunchStartMinutes,
            lunchDurationMinutes: lunchDurationMinutes,
            alternatingWeekType: alternatingWeekType.rawValue,
            alternatingWeekendWorkday: alternatingWeekendWorkday,
            alternatingReferenceWeekStartMs: alternatingReferenceWeekStartMs,
            rotationWorkDays: rotationWorkDays,
            rotationRestDays: rotationRestDays,
            rotationAnchorMs: rotationAnchorMs,
            untilMs: untilMs
        )
    }

    private func overrideExpiry(at date: Date) -> Double? {
        guard let shift = snapshot(at: date) else { return nil }
        let inShiftContext = shift.isWorkday
            || isForcedWorkday(shift)
            || isEndedEarly(shift)
            || (countdownStarted && scheduleMode == .off)
        guard inShiftContext else { return nil }
        let endDay = Calendar.current.startOfDay(for: shift.endDate)
        return Calendar.current.date(byAdding: .day, value: 1, to: endDay)
            .map { $0.timeIntervalSince1970 * 1_000 }
    }

    func usesTodayOverride(at date: Date) -> Bool {
        guard let todayOverride else { return false }
        return date.timeIntervalSince1970 * 1_000 < todayOverride.untilMs
    }

    /// Future projections must not inherit today's early clock-in or overlay.
    func projectsFutureFromBase(at date: Date) -> Bool {
        usesTodayOverride(at: date) || isStartedEarly(at: date)
    }

    var forcedWorkdayStartMs: Double? {
        guard let forcedWorkdayDate else { return nil }
        let parts = forcedWorkdayDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar.current.date(from: components)
            .map { Calendar.current.startOfDay(for: $0).timeIntervalSince1970 * 1_000 }
    }

    func effectiveScheduleMode(at date: Date = .now) -> WorkScheduleMode {
        guard usesTodayOverride(at: date),
              let raw = todayOverride?.scheduleMode,
              let mode = WorkScheduleMode(rawValue: raw)
        else { return scheduleMode }
        return mode
    }

    func effectiveStartMinutes(at date: Date) -> Int {
        if isStartedEarly(at: date), let earlyStartAtMs {
            return minutes(from: Date(timeIntervalSince1970: earlyStartAtMs / 1_000))
        }
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.startMinutes
        }
        return startMinutes
    }

    func effectiveEndMinutes(at date: Date) -> Int {
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.endMinutes
        }
        return endMinutes
    }

    func effectiveWorkdays(at date: Date) -> Set<Int> {
        if usesTodayOverride(at: date), let todayOverride {
            return Set(todayOverride.workdays)
        }
        return workdays
    }

    func effectiveLunchEnabled(at date: Date) -> Bool {
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.lunchEnabled
        }
        return lunchEnabled
    }

    func effectiveLunchStartMinutes(at date: Date) -> Int {
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.lunchStartMinutes
        }
        return lunchStartMinutes
    }

    func effectiveLunchDurationMinutes(at date: Date) -> Int {
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.lunchDurationMinutes
        }
        return lunchDurationMinutes
    }

    /// Remaining milliseconds until the next clock-in the screen is counting to.
    func countdownToClockInMs(snapshot: NativeShiftSnapshot, at date: Date) -> Double {
        let nowMs = date.timeIntervalSince1970 * 1_000
        if snapshot.isWorkday || isForcedWorkday(snapshot), snapshot.isBeforeStart(at: date) {
            return snapshot.heroRemainingMs(at: date)
        }
        if let next = snapshot.nextShiftStartAtMs {
            return max(0, next - nowMs)
        }
        return snapshot.heroRemainingMs(at: date)
    }

    func countdownToClockInDate(snapshot: NativeShiftSnapshot, at date: Date) -> Date? {
        if snapshot.isWorkday || isForcedWorkday(snapshot), snapshot.isBeforeStart(at: date) {
            return snapshot.startDate
        }
        return snapshot.nextShiftStartDate
    }

    /// Fill that empties as remaining shrinks. Denominator is midnight of the
    /// current calendar day to the target clock-in.
    func countdownToClockInFill(snapshot: NativeShiftSnapshot, at date: Date) -> Double {
        guard let target = countdownToClockInDate(snapshot: snapshot, at: date) else { return 0 }
        let remaining = countdownToClockInMs(snapshot: snapshot, at: date)
        let dayStart = Calendar.current.startOfDay(for: date)
        let total = max(1, target.timeIntervalSince(dayStart) * 1_000)
        return min(100, max(0, remaining / total * 100))
    }

    func shareCopy(at date: Date = .now) -> String {
        let phase = visualPhase(at: date)
        guard let shift = shouldQuerySnapshot(at: date) ? snapshot(at: date) : nil else {
            return t("shareOffWorkText")
        }
        switch phase {
        case .completed, .unscheduled, .rest, .rulesError:
            return t("shareOffWorkText")
        case .lunch:
            return t("shareLunchText", values: [
                "time": formatRelativeDuration(shift.heroRemainingMs(at: date)),
            ])
        case .overtime, .running:
            if shift.isBeforeStart(at: date) {
                return t("shareUntilStartText", values: [
                    "time": formatRelativeDuration(shift.heroRemainingMs(at: date)),
                ])
            }
            return t("shareText", values: [
                "time": formatRelativeDuration(shift.heroRemainingMs(at: date)),
            ])
        }
    }

    func shareHeroText(at date: Date = .now) -> String {
        let phase = visualPhase(at: date)
        guard let shift = shouldQuerySnapshot(at: date) ? snapshot(at: date) : nil else {
            return t("shareDone")
        }
        if phase == .completed || isShiftComplete(shift) {
            return t("shareDone")
        }
        return formatRelativeDuration(shift.heroRemainingMs(at: date))
    }

    func shareProgress(at date: Date = .now) -> Double {
        let phase = visualPhase(at: date)
        guard let shift = shouldQuerySnapshot(at: date) ? snapshot(at: date) : nil else { return 100 }
        let finished = clockOffSnapshot(for: shift)
        if phase == .completed || isShiftComplete(shift) {
            return isEndedEarly(shift) ? finished.progress : 100
        }
        if shift.isBeforeStart(at: date) || phase == .rest {
            return countdownToClockInFill(snapshot: shift, at: date)
        }
        return shift.progress
    }

    private func clearEarlyClockOffRecord() {
        earlyOffAtMs = nil
        earlyOffShiftEndAtMs = nil
        earlyOffSnapshot = nil
    }

    private func clearEarlyClockInRecord() {
        earlyStartAtMs = nil
        earlyStartUntilMs = nil
    }

    private func persistTodayOverride() {
        if let todayOverride, let data = try? JSONEncoder().encode(todayOverride) {
            defaults.set(data, forKey: Key.todayScheduleOverride)
        } else {
            defaults.removeObject(forKey: Key.todayScheduleOverride)
        }
    }

    private static func decodeTodayOverride(from defaults: UserDefaults) -> TodayScheduleOverride? {
        guard let data = defaults.data(forKey: Key.todayScheduleOverride) else { return nil }
        return try? JSONDecoder().decode(TodayScheduleOverride.self, from: data)
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
        guard effectiveScheduleMode(at: asOf) != .off else { return nil }
        var summaryWorkdays = effectiveWorkdays(at: asOf)
        if isForcedWorkday(snapshot) {
            summaryWorkdays.insert(Calendar.current.component(.weekday, from: snapshot.startDate) - 1)
        }
        do {
            let result = try CountdownRules.shared.summarize(input: .init(
                period: period,
                asOfMs: asOf.timeIntervalSince1970 * 1_000,
                workdays: summaryWorkdays.sorted(),
                schedule: nativeSchedule(at: asOf),
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

    private static func floorToMinute(_ date: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: parts) ?? date
    }

    private static func startOfCurrentWeek() -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let day = calendar.startOfDay(for: .now)
        return calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    }
}
