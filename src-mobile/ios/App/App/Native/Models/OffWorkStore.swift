import Foundation
import SwiftUI
import UserNotifications

/// A findable user-authored record day. It is intentionally not a metrics
/// model: manual leave and rest entries belong here even though they must not
/// inflate workday totals.
struct RecordDayIndexEntry: Equatable, Sendable, Identifiable {
    var dayKey: String
    var observations: [WorkObservation] = []
    var dayOverride: DayOverride?
    var calendarException: CalendarException?

    var id: String { dayKey }
    var hasWorkObservation: Bool { !observations.isEmpty }
    var hasManualOverride: Bool { dayOverride != nil }
    var hasUserCalendarException: Bool { calendarException != nil }
}

enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case timer
    case records
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
    case recordsTimeZone
    case plus
    case iCloudSync
    case recordsData
    case recordsConflicts
    case focus
    case focusPlan
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

enum ScheduleChangeScope: String {
    case schedule
    case lunch
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

    var changesSchedulePattern: Bool {
        workdays != nil
            || scheduleMode != nil
            || alternatingWeekType != nil
            || alternatingWeekendWorkday != nil
            || rotationWorkDays != nil
            || rotationRestDays != nil
            || rotationCycleDay != nil
    }
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
        static let debugResetNextLaunch = "ios.native.debugResetNextLaunch"
        static let qaDebugScenario = "ios.native.qaDebugScenario"
        static let qaRoute = "ios.native.qaRoute"
        static let qaRecordsRoute = "ios.native.qaRecordsRoute"
        static let qaRecordsScale = "ios.native.qaRecordsScale"
        static let qaFocusScenario = "ios.native.qaFocusScenario"
#endif
        static let selectedTab = "ios.native.selectedTab"
        static let countdownStarted = "ios.native.countdownStarted"
        static let automaticCountdownMigrationCompleted = "ios.native.automaticCountdownMigrationCompleted"
        static let earlyOffAtMs = "ios.native.earlyOffAtMs"
        static let earlyOffShiftEndAtMs = "ios.native.earlyOffShiftEndAtMs"
        static let earlyOffSnapshot = "ios.native.earlyOffSnapshot"
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
        static let cycleEndSummaryNotificationEnabled = "ios.native.cycleEndSummaryNotificationEnabled"
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
        static let recordsTimeZone = "ios.native.recordsTimeZone"
        static let sessionTimeZone = "ios.native.sessionTimeZone"
        static let sessionTimeZoneUntilMs = "ios.native.sessionTimeZoneUntilMs"
        static let lifeSetupPromptDismissed = "ios.native.lifeSetupPromptDismissed"
        static let focusPlanning = "ios.native.focusPlanning.v1"
        static let focusTimerSettings = "ios.native.focusTimerSettings.v1"
        static let appReviewPrompt = "ios.native.appReviewPrompt.v1"
    }

    static let allowedLiveActivityLeadMinutes = [5, 15, 30]

    let localizer = NativeLocalizer()
    let records: RecordCoordinator
    let plus: PlusEntitlement
    let cloudSync = RecordsCloudSync()
    private let defaults: UserDefaults
    /// Outside observation on purpose. Writing a cache from a getter would
    /// invalidate every view that asked for a calendar.
    @ObservationIgnored
    private let civilCalendars = CivilCalendarCache()
    @ObservationIgnored
    private var observationIndexCache: (revision: UInt64, byDay: [String: [WorkObservation]])?
    private var recordedDayKeysCache: (revision: UInt64, keys: Set<String>)?
    @ObservationIgnored
    private var resolvedDaysCache: (revision: UInt64, from: Date, through: Date, days: [DayResolution])?
#if DEBUG
    var debugTimerSession: DebugTimerScenario.Session?
    private(set) var debugDidResetOnLaunch = false
#endif

    var selectedTab: AppTab {
        didSet {
            defaults.set(selectedTab.rawValue, forKey: Key.selectedTab)
            writeQASurfaceMarker()
        }
    }
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
    var recordsPath: [RecordsRoute] = []
    var settingsPath: [AppRoute] = []
    /// The paywall a gated action asked for, presented as a sheet by the root
    /// view so it appears over the current stack whichever one that is.
    var paywallSheet: PlusPaywallReason? { didSet { writeQASurfaceMarker() } }
    var pendingPlusAction: PlusPendingAction?
    var editingDayKey: String?
    var presentAddFocus = false
    private var focusExpiryTask: Task<Void, Never>?
    /// Unsaved settings drafts survive rotation because portrait and landscape
    /// use separate navigation view trees. They are intentionally not persisted
    /// across launches.
    var scheduleSettingsDraft = ScheduleFieldChange()
    var lunchSettingsDraft = ScheduleFieldChange()

    /// Landscape drives a single `NavigationStack` for both tabs, where
    /// portrait has one per tab; this projects whichever is current.
    var activePath: [AppRoute] {
        get {
            switch selectedTab {
            case .timer: timerPath
            case .records: []
            case .settings: settingsPath
            }
        }
        set {
            switch selectedTab {
            case .timer: timerPath = newValue
            case .records: break
            case .settings: settingsPath = newValue
            }
        }
    }
    var onboardingPage = 0
    /// In-memory: the reminders page applies lunch-on and simple clock-off
    /// once per launch. Persisting it would rewrite a user who turned those
    /// off, went back, and came in again.
    var didApplyOnboardingReminderDefaults = false
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

    /// Locked civil-day timezone. Travel does not rewrite the year view.
    var recordsTimeZoneIdentifier: String {
        didSet { defaults.set(recordsTimeZoneIdentifier, forKey: Key.recordsTimeZone) }
    }

    /// Timezone of the running countdown session. Nil when following the
    /// schedule without a manual start.
    var sessionTimeZoneIdentifier: String? {
        didSet {
            if let sessionTimeZoneIdentifier {
                defaults.set(sessionTimeZoneIdentifier, forKey: Key.sessionTimeZone)
            } else {
                defaults.removeObject(forKey: Key.sessionTimeZone)
            }
        }
    }

    /// Instant after which a locked session timezone can fall back to records.
    private var sessionTimeZoneUntilMs: Double? {
        didSet {
            if let sessionTimeZoneUntilMs {
                defaults.set(sessionTimeZoneUntilMs, forKey: Key.sessionTimeZoneUntilMs)
            } else {
                defaults.removeObject(forKey: Key.sessionTimeZoneUntilMs)
            }
        }
    }

    var recordsTimeZone: TimeZone {
        civilCalendars.timeZone(identifier: recordsTimeZoneIdentifier)
    }

    /// Timezone the running countdown and auto-follow snapshot must use.
    var countdownTimeZoneIdentifier: String {
        sessionTimeZoneIdentifier ?? recordsTimeZoneIdentifier
    }

    var countdownTimeZone: TimeZone {
        TimeZone(identifier: countdownTimeZoneIdentifier) ?? recordsTimeZone
    }

    /// Calendar used for records and schedule civil math. It remains anchored
    /// to the persisted records zone rather than the device's travel zone.
    var recordsCalendar: Calendar {
        civilCalendars.recordsCalendar(timeZoneIdentifier: recordsTimeZoneIdentifier)
    }

    /// Always make the civil schedule zone explicit. JavaScriptCore's default
    /// zone is not guaranteed to match Foundation's `TimeZone.current`, even
    /// when the records zone is the device zone.
    var rulesTimeZoneIdentifier: String? {
        countdownTimeZoneIdentifier
    }

    var systemTimeZoneDiffersFromRecords: Bool {
        systemTimeZoneIdentifier != recordsTimeZoneIdentifier
    }

    var recordsTimeZoneLabel: String {
        recordsTimeZone.localizedName(for: .generic, locale: locale)
            ?? recordsTimeZoneIdentifier
    }

    var systemTimeZone: TimeZone {
        TimeZone(identifier: systemTimeZoneIdentifier) ?? .current
    }

    var systemTimeZoneLabel: String {
        systemTimeZone.localizedName(for: .generic, locale: locale)
            ?? systemTimeZoneIdentifier
    }

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
    var lifeSetupPromptDismissed: Bool {
        didSet { defaults.set(lifeSetupPromptDismissed, forKey: Key.lifeSetupPromptDismissed) }
    }
    private(set) var focusPlanning = FocusPlanningState()
    /// Synced with the planning configuration. Existing sessions carry their
    /// own fixed `plannedEndAt`, so a remote preference never rewrites a timer
    /// already in flight.
    private(set) var focusTimerSettings = FocusTimerSettings.default
    /// Cheap invalidation token for Widget / notification publication. The
    /// plan itself can contain hundreds of assignments, so RootView observes
    /// this instead of comparing or encoding the complete value on every frame.
    private(set) var focusPlanningRevision: UInt64 = 0
    /// Import, CloudKit and conflict resolution can replace an active focus
    /// row without changing local preferences. RootView observes this token to
    /// rebuild the one Live Activity and notification channel immediately.
    private(set) var focusRuntimeRevision: UInt64 = 0
    var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    /// The language iOS would give us, kept as stored state so a change while
    /// the app is backgrounded invalidates the views that read it.
    private(set) var systemLanguageCode: String
    /// Same reason as `systemLanguageCode`: `TimeZone.current` does not
    /// invalidate SwiftUI by itself, so a trip through Settings would leave
    /// the records-timezone page looking like nothing changed.
    private(set) var systemTimeZoneIdentifier: String

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
    var cycleEndSummaryNotificationEnabled: Bool {
        didSet {
            defaults.set(
                cycleEndSummaryNotificationEnabled,
                forKey: Key.cycleEndSummaryNotificationEnabled
            )
        }
    }
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

    var presentationNotificationMode: OffWorkNotificationMode {
#if DEBUG
        if debugTimerSession != nil { return .milestones }
#endif
        return notificationMode
    }

    var presentationLunchStartReminderEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return true }
#endif
        return lunchStartReminderEnabled
    }

    var presentationLunchEndReminderEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return true }
#endif
        return lunchEndReminderEnabled
    }

    var presentationMicroBreakEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return true }
#endif
        return microBreakEnabled
    }

    var presentationMicroBreakIntervalMinutes: Int {
#if DEBUG
        if debugTimerSession != nil { return 60 }
#endif
        return microBreakIntervalMinutes
    }

    var presentationLiveActivityEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return false }
#endif
        return liveActivityEnabled
    }

    var presentationSalaryEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return false }
#endif
        return salaryEnabled
    }
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
    /// In-memory only: neither tab switches nor a background/foreground cycle
    /// may replay the same completed shift. A true cold launch constructs a
    /// fresh store, so that launch may celebrate the already-completed shift
    /// once without persisting a permanent suppression flag.
    var lastCelebratedEndAtMs: Double = 0
    var reviewPromptPresented = false
    private var reviewPromptState = AppReviewPromptState()
    private var reviewPromptEligibleThisLaunch = false

    init(defaults: UserDefaults = .standard, records: RecordCoordinator? = nil) {
#if DEBUG
        let shouldReset = defaults.bool(forKey: Key.debugResetNextLaunch)
        if shouldReset {
            for key in defaults.dictionaryRepresentation().keys {
                defaults.removeObject(forKey: key)
            }
        }
        debugDidResetOnLaunch = shouldReset
        let debugRoute = AppRoute(rawValue: defaults.string(forKey: Key.qaRoute) ?? "")
        let debugRecordsRoute = Self.debugRecordsRoute(
            defaults.string(forKey: Key.qaRecordsRoute)
        )
        let debugRecordsScale = RecordsScale(
            rawValue: defaults.string(forKey: Key.qaRecordsScale) ?? ""
        )
        let debugScenario = DebugTimerScenario(
            rawValue: defaults.string(forKey: Key.qaDebugScenario) ?? ""
        )
        let debugFocusScenario = defaults.string(forKey: Key.qaFocusScenario)
#else
        let debugRoute: AppRoute? = nil
        let debugRecordsRoute: RecordsRoute? = nil
        let debugRecordsScale: RecordsScale? = nil
#endif
        self.defaults = defaults
        self.records = records ?? RecordCoordinator.inMemory()
        self.plus = PlusEntitlement(defaults: defaults)
        if let data = defaults.data(forKey: Key.focusPlanning),
           let stored = try? JSONDecoder().decode(FocusPlanningState.self, from: data) {
            focusPlanning = stored
        }
        if let data = defaults.data(forKey: Key.focusTimerSettings),
           let stored = try? JSONDecoder().decode(FocusTimerSettings.self, from: data) {
            focusTimerSettings = stored.normalized
        }
        if debugRoute != nil {
            selectedTab = .settings
        } else if debugRecordsRoute != nil || debugRecordsScale != nil {
            selectedTab = .records
        } else {
            selectedTab = AppTab(rawValue: defaults.string(forKey: Key.selectedTab) ?? "timer") ?? .timer
        }
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
        let initialRecordsTimeZoneIdentifier = defaults.string(forKey: Key.recordsTimeZone)
            ?? self.records.state.periods.first?.timeZoneIdentifier
            ?? TimeZone.current.identifier
        recordsTimeZoneIdentifier = initialRecordsTimeZoneIdentifier
        let initialRecordsTimeZone = TimeZone(identifier: initialRecordsTimeZoneIdentifier) ?? .current
        sessionTimeZoneIdentifier = defaults.string(forKey: Key.sessionTimeZone)
        sessionTimeZoneUntilMs = defaults.object(forKey: Key.sessionTimeZoneUntilMs) as? Double
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
            ? Self.startOfCurrentWeek(timeZone: initialRecordsTimeZone).timeIntervalSince1970 * 1_000
            : defaults.double(forKey: Key.alternatingReferenceWeekStartMs)
        rotationWorkDays = defaults.object(forKey: Key.rotationWorkDays) == nil ? 2 : max(1, defaults.integer(forKey: Key.rotationWorkDays))
        rotationRestDays = defaults.object(forKey: Key.rotationRestDays) == nil ? 2 : max(1, defaults.integer(forKey: Key.rotationRestDays))
        rotationAnchorMs = defaults.object(forKey: Key.rotationAnchorMs) == nil
            ? Self.startOfDay(for: .now, timeZone: initialRecordsTimeZone).timeIntervalSince1970 * 1_000
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
        lifeSetupPromptDismissed = defaults.bool(forKey: Key.lifeSetupPromptDismissed)
        theme = AppTheme(rawValue: defaults.string(forKey: Key.theme) ?? "auto") ?? .auto
        systemLanguageCode = NativeLocalizer.systemLanguage()
        systemTimeZoneIdentifier = TimeZone.current.identifier
        // Only honour a code this build still ships; a language dropped between
        // versions must fall back rather than leave the UI on missing keys.
        languageOverride = defaults.string(forKey: Key.languageOverride).flatMap { stored in
            NativeLocalizer.supportedLanguages.contains { $0.id == stored } ? stored : nil
        }
        notificationMode = OffWorkNotificationMode(rawValue: defaults.string(forKey: Key.notificationMode) ?? "off") ?? .off
        cycleEndSummaryNotificationEnabled = defaults.bool(forKey: Key.cycleEndSummaryNotificationEnabled)
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
        activeCountdownEndAtMs = defaults.object(forKey: Key.activeCountdownEndAtMs) as? Double
        reviewPromptState = defaults.data(forKey: Key.appReviewPrompt)
            .flatMap { try? JSONDecoder().decode(AppReviewPromptState.self, from: $0) }
            ?? AppReviewPromptState()
        reviewPromptEligibleThisLaunch = reviewPromptState.isEligibleOnLaunch(
            trackedCompletionAtMs: activeCountdownEndAtMs,
            nowMs: Date.now.timeIntervalSince1970 * 1_000
        )
        persistReviewPromptState()
        defaults.removeObject(forKey: Key.lastCelebratedEndAtMs)
        lastCelebratedEndAtMs = 0

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
        // Carryover is lifecycle work, never a rendering side effect. The
        // Focus page may be evaluated repeatedly by SwiftUI without mutating
        // the archive or producing a cloud write.
        if let configuration = self.records.state.focusPlanningConfiguration {
            focusPlanning = configuration.planning
            focusTimerSettings = configuration.timerSettings.normalized
            mirrorFocusConfigurationToLegacyDefaults()
        } else {
            let legacy = FocusPlanningConfiguration(
                planning: focusPlanning,
                timerSettings: focusTimerSettings,
                editedAt: .now,
                editCount: 0,
                editTieBreaker: UUID()
            )
            if legacy.hasUserContent {
                self.records.upsertFocusPlanningConfiguration(legacy)
            }
        }
        cloudSync.attach(records: self.records)
        carryIncompleteFocusTasks(at: .now)
#if DEBUG
        if let debugRoute {
            if debugRoute == .focus || debugRoute == .focusPlan {
                // Focus QA uses the same realistic sample archive as Records.
                // Keep this behind DEBUG so release launches never synthesize
                // user tasks or history.
                _ = debugSeedSampleRecords()
                selectedTab = .settings
            }
            defaults.removeObject(forKey: Key.qaRoute)
            settingsPath = [debugRoute]
        }
        if let debugRecordsRoute {
            defaults.removeObject(forKey: Key.qaRecordsRoute)
            // Charts, Life and day detail all render from stored records, so a
            // route with an empty store would only ever screenshot empty states.
            _ = debugSeedSampleRecords()
            if case .conflictCenter = debugRecordsRoute {
                debugSeedSampleConflict(at: .now)
            }
            recordsPath = [debugRecordsRoute]
        }
        if debugRecordsScale != nil {
            _ = debugSeedSampleRecords()
            selectedTab = .records
        }
        if let debugScenario {
            defaults.removeObject(forKey: Key.qaDebugScenario)
            activateDebugTimerScenario(debugScenario)
        }
        if let debugFocusScenario, !debugFocusScenario.isEmpty {
            defaults.removeObject(forKey: Key.qaFocusScenario)
            activateDebugFocusScenario(debugFocusScenario, at: .now)
        }
        if shouldReset {
            self.records.deleteAllLocalData()
        }
#endif
        self.records.onExternalStateApplied = { [weak self] in
            self?.reconcileExternallyAppliedRecordState()
        }
    }

    var debugPresentationToken: String {
#if DEBUG
        debugTimerSession?.scenario.rawValue ?? ""
#else
        ""
#endif
    }

    func timerDate(from realDate: Date) -> Date {
#if DEBUG
        debugTimerSession?.date(for: realDate) ?? realDate
#else
        realDate
#endif
    }

#if DEBUG
    /// `RecordsRoute` carries associated values, so it cannot be a raw-value
    /// enum like `AppRoute`. The QA screenshot matrix has to reach the Plus
    /// surfaces (charts, Life, Focus, day detail, day edit) without a tap
    /// script, hence a small hand-written parser for `week`, `month`, `year`,
    /// `life`, `focus`, `day:<dayKey>` and `editDay:<dayKey>`.
    private static func debugRecordsRoute(_ raw: String?) -> RecordsRoute? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count > 1 ? parts[1] : nil) {
        case ("allRecords", _): return .allRecords
        case ("conflicts", _): return .conflictCenter
        case ("day", let key?): return .day(key)
        default: return nil
        }
    }

    /// Names what is on screen, in the app container, for `qa:ios-shots`.
    ///
    /// A screenshot tool cannot see a screen: the first version of that sweep
    /// reported eight green captures of a paywall and a Timer tab, because a
    /// running process and a PNG of the right size is all it could check. This
    /// is the missing half — the app says where it actually is, and the script
    /// refuses any shot that does not match what it asked for. Debug only;
    /// nothing in the shipping build reads it.
    func writeQASurfaceMarker(_ visibleSurface: String? = nil) {
#if DEBUG
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let url = caches?.appendingPathComponent("qa-surface.txt") else { return }
        try? qaSurfaceName(visibleSurface).write(to: url, atomically: true, encoding: .utf8)
#endif
    }

#if DEBUG
    /// One exclusive visible surface. Navigation paths express intent; only a
    /// destination view's `onAppear` is proof that the push actually landed.
    func qaSurfaceName(_ visibleSurface: String? = nil) -> String {
        if !onboardingComplete { return "onboarding" }
        if !plus.hasSeenIntro { return "plus-intro" }
        if paywallSheet != nil { return "paywall" }
        return visibleSurface ?? selectedTab.rawValue
    }
#endif

    func scheduleDebugResetOnNextLaunch() {
        defaults.set(true, forKey: Key.debugResetNextLaunch)
    }

    /// Temporary archive for records / charts / life / focus QA. Idempotent.
    @discardableResult
    func debugSeedSampleRecords(now: Date = .now) -> Bool {
        let marker = Self.debugSeedID(0)
        if records.state.observations.contains(where: { $0.eventID == marker }) {
            return false
        }
        records.ensureSeeded(hours: hoursConfiguration(at: now), at: now, timeZone: recordsTimeZone)
        let calendar = recordsCalendar
        let zone = recordsTimeZone
        let today = calendar.startOfDay(for: now)
        guard let snapshotID = records.currentSnapshotID(on: today) ?? records.state.snapshots.first?.id else {
            return false
        }
        var cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var index = 0
        for _ in 0..<32 {
            let weekday = calendar.component(.weekday, from: cursor)
            if (2...6).contains(weekday) {
                seedSampleWorkday(
                    cursor,
                    index: index,
                    snapshotID: snapshotID,
                    calendar: calendar,
                    zone: zone
                )
                index += 1
            }
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        saveLifeProfile(
            birthYear: 1992,
            workStartedYear: 2015,
            retirementAge: 60,
            sleepHours: 7.5,
            hidesExactAges: false
        )
        records.upsertFocusTask(
            FocusTask(
                id: Self.debugSeedID(800),
                createdAt: now,
                plannedForDate: today,
                scheduledStartAt: nil,
                title: "Weekly notes",
                estimatedPomodoros: 1,
                completedAt: nil,
                sortIndex: 0,
                editedAt: now,
                editCount: 0,
                editTieBreaker: Self.debugSeedID(801)
            )
        )
        records.upsertFocusTask(
            FocusTask(
                id: Self.debugSeedID(802),
                createdAt: now,
                plannedForDate: today,
                scheduledStartAt: nil,
                title: "Review last month",
                estimatedPomodoros: 2,
                completedAt: now,
                sortIndex: 1,
                editedAt: now,
                editCount: 0,
                editTieBreaker: Self.debugSeedID(803)
            )
        )
        selectedTab = .records
        return true
    }

    private func seedSampleWorkday(
        _ day: Date,
        index: Int,
        snapshotID: UUID,
        calendar: Calendar,
        zone: TimeZone
    ) {
        let dayKey = RecordJSON.dayKey(day, calendar: calendar)
        let startMinutes: Int
        let stopMinutes: Int
        switch index {
        case 2:
            startMinutes = 8 * 60 + 25
            stopMinutes = 18 * 60
        case 5:
            markDayNotWorking(dayKey: dayKey)
            return
        case 8:
            startMinutes = 9 * 60
            stopMinutes = 16 * 60 + 10
            saveCustomHours(dayKey: dayKey, startMinutes: startMinutes, endMinutes: stopMinutes)
        default:
            startMinutes = 9 * 60 + (index % 7)
            stopMinutes = 18 * 60 + (index % 5)
        }
        let started = calendar.date(bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: day) ?? day
        let stopped = calendar.date(bySettingHour: stopMinutes / 60, minute: stopMinutes % 60, second: 0, of: day) ?? day
        records.recordObservation(
            kind: .countdownStarted,
            eventID: index == 0 ? Self.debugSeedID(0) : Self.debugSeedID(100 + index * 2),
            shiftAnchorDate: day,
            occurredAt: started,
            snapshotID: snapshotID,
            timeZoneIdentifier: zone.identifier
        )
        records.recordObservation(
            kind: .countdownStopped,
            eventID: Self.debugSeedID(100 + index * 2 + 1),
            shiftAnchorDate: day,
            occurredAt: stopped,
            snapshotID: snapshotID,
            timeZoneIdentifier: zone.identifier
        )
        if index == 11 {
            let overtimeEnd = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: day) ?? day
            let plannedEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? stopped
            let payload = try? JSONEncoder().encode(OvertimeDeclarationPayload(
                overtimeEndAtMs: overtimeEnd.timeIntervalSince1970 * 1_000,
                plannedEndAtMs: plannedEnd.timeIntervalSince1970 * 1_000
            ))
            records.recordObservation(
                kind: .overtimeDeclared,
                eventID: Self.debugSeedID(700),
                shiftAnchorDate: day,
                occurredAt: stopped,
                snapshotID: snapshotID,
                valueData: payload,
                timeZoneIdentifier: zone.identifier
            )
        }
    }

    private static func debugSeedID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0026-4000-a000-%012x", n))!
    }

    /// Deterministic, DEBUG-only states for the release-blocking Focus visual
    /// matrix. These hooks never ship and avoid pretending that waiting through
    /// four real Pomodoros is meaningful UI verification.
    private func activateDebugFocusScenario(_ raw: String, at now: Date) {
        guard var task = records.state.focusTasks.first(where: { $0.id == Self.debugSeedID(800) })
            ?? records.state.focusTasks.first(where: { $0.deletedAt == nil })
        else { return }

        func seedCompletedSession(kind: FocusSessionKind, index: Int, endedAt: Date) {
            let minutes = switch kind {
            case .focus: focusTimerSettings.focusMinutes
            case .shortBreak: focusTimerSettings.shortBreakMinutes
            case .longBreak: focusTimerSettings.longBreakMinutes
            }
            let startedAt = endedAt.addingTimeInterval(-Double(minutes * 60))
            records.upsertFocusSession(FocusSession(
                id: Self.debugSeedID(820 + index),
                taskID: task.id,
                shiftAnchorDate: recordsCalendar.startOfDay(for: now),
                startedAt: startedAt,
                plannedEndAt: endedAt,
                endedAt: endedAt,
                endReason: .completed,
                editedAt: endedAt,
                editCount: 0,
                editTieBreaker: Self.debugSeedID(840 + index),
                kind: kind,
                timeZoneIdentifier: recordsTimeZone.identifier,
                actualDurationSeconds: minutes * 60,
                plannedEndReason: .completed
            ), at: endedAt)
        }

        switch raw {
        case "shortBreakOffer":
            seedCompletedSession(kind: .focus, index: 0, endedAt: now.addingTimeInterval(-60))
            focusLastNextAction = .startShortBreak
        case "longBreakOffer":
            for index in 0..<4 {
                seedCompletedSession(
                    kind: .focus,
                    index: index,
                    endedAt: now.addingTimeInterval(Double((index - 4) * 60))
                )
            }
            focusLastNextAction = .startLongBreak
        case "nextFocus":
            seedCompletedSession(kind: .shortBreak, index: 0, endedAt: now.addingTimeInterval(-60))
            focusLastNextAction = .startNextFocus
        case "future":
            let tomorrow = recordsCalendar.date(byAdding: .day, value: 1, to: now) ?? now
            task.plannedForDate = recordsCalendar.startOfDay(for: tomorrow)
            task.scheduledStartAt = recordsCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
            task.editedAt = now
            task.editCount += 1
            task.editTieBreaker = UUID()
            records.upsertFocusTask(task, at: now)
        case "overflow":
            task.estimatedPomodoros = 99
            task.editedAt = now
            task.editCount += 1
            task.editTieBreaker = UUID()
            records.upsertFocusTask(task, at: now)
        case "notificationDenied":
            focusNotificationIssue = .permissionDenied
        case "notificationFailed":
            activateDebugFocusScenario("runningFocus", at: now)
            focusNotificationIssue = .schedulingFailed
        case "runningShortBreak", "runningLongBreak", "runningFocus":
            let kind: FocusSessionKind = switch raw {
            case "runningShortBreak": .shortBreak
            case "runningLongBreak": .longBreak
            default: .focus
            }
            let minutes = switch kind {
            case .focus: focusTimerSettings.focusMinutes
            case .shortBreak: focusTimerSettings.shortBreakMinutes
            case .longBreak: focusTimerSettings.longBreakMinutes
            }
            records.upsertFocusSession(FocusSession(
                id: Self.debugSeedID(raw == "runningShortBreak" ? 810 : raw == "runningLongBreak" ? 811 : 812),
                taskID: task.id,
                shiftAnchorDate: recordsCalendar.startOfDay(for: now),
                startedAt: now,
                plannedEndAt: now.addingTimeInterval(Double(minutes * 60)),
                endedAt: nil,
                endReason: nil,
                editedAt: now,
                editCount: 0,
                editTieBreaker: Self.debugSeedID(813),
                kind: kind,
                timeZoneIdentifier: recordsTimeZone.identifier,
                plannedEndReason: .completed
            ), at: now)
        default:
            break
        }
    }

    private func debugSeedSampleConflict(at date: Date) {
        guard records.state.sync.conflicts.isEmpty,
              let local = records.state.overrides.first(where: { $0.kind == .notWorking })
        else { return }

        var incoming = local
        incoming.kind = .confirmedAsScheduled
        incoming.note = "Imported correction"
        incoming.editedAt = local.editedAt
        incoming.editCount = local.editCount
        incoming.editTieBreaker = Self.debugSeedID(900)

        let calendar = RecordsSyncPayload.fileCalendar(for: records.state)
        guard let localPayload = RecordsSyncPayload.encode(.override(local), calendar: calendar),
              let incomingPayload = RecordsSyncPayload.encode(.override(incoming), calendar: calendar)
        else { return }

        var sync = records.state.sync
        sync.conflicts = [
            SyncConflictCopy(
                id: Self.debugSeedID(901),
                entityType: .dayOverride,
                logicalKey: local.dayKey,
                payload: incomingPayload,
                lostAtMs: date.timeIntervalSince1970 * 1_000,
                source: nil,
                localPayload: localPayload,
                incomingPayload: incomingPayload,
                localEditedAtMs: local.editedAt.timeIntervalSince1970 * 1_000,
                incomingEditedAtMs: incoming.editedAt.timeIntervalSince1970 * 1_000,
                currentWinner: .local
            )
        ]
        _ = records.replaceSyncState(sync)
    }
#endif

    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var layoutDirection: LayoutDirection { languageCode == "ar" ? .rightToLeft : .leftToRight }
    var locale: Locale { civilCalendars.locale(identifier: languageCode) }
    /// Part of the schedule signature. Forcing a rest day changes what the
    /// widget and the notification list should say, and once the schedule arms
    /// itself nothing else in that signature moves when the button is pressed —
    /// `countdownStarted` was already true, so the widget kept publishing
    /// "rest day" while the app counted the shift down.
    var forcedWorkdayKey: String? { forcedWorkdayDate }

    /// Salary-free hours for a schedule snapshot. Overtime and "now" stay off.
    func hoursConfiguration(at date: Date = .now) -> ScheduleHoursConfiguration {
        let input = rulesInput(at: date, using: .base)
        return ScheduleHoursConfiguration(
            startTime: input.startTime,
            endTime: input.endTime,
            workdays: input.workdays,
            schedule: input.schedule,
            breakStartTime: input.breakStartTime,
            breakDurationMinutes: input.breakDurationMinutes
        )
    }

    /// Keeps the current/future schedule projection aligned with this device's
    /// local preferences while preserving every earlier schedule snapshot.
    /// A next-shift-only edit deliberately leaves today's snapshot untouched.
    @discardableResult
    func reconcileRecordSchedule(at date: Date = .now) -> Bool {
        guard onboardingComplete, !records.state.periods.isEmpty else { return false }
        let today = recordsCalendar.startOfDay(for: date)
        let effectiveFrom: Date
        if usesTodayOverride(at: date),
           let tomorrow = recordsCalendar.date(byAdding: .day, value: 1, to: today) {
            effectiveFrom = tomorrow
        } else {
            effectiveFrom = today
        }
        return records.reconcileExistingHours(
            hoursConfiguration(at: date),
            effectiveFrom: effectiveFrom,
            at: date
        )
    }

    /// First visit to the timer surface today. Not "started work".
    func resolvedDays(from: Date, through: Date, now: Date = .now) -> [DayResolution] {
        // Merely opening an old month must not backdate the durable archive.
        // Records starts when the product first observes the current schedule;
        // historical life estimates use a separate in-memory archive below.
        records.ensureSeeded(hours: hoursConfiguration(at: now), at: now, timeZone: recordsTimeZone)
        _ = reconcileRecordSchedule(at: now)
        return resolveDays(
            from: from,
            through: through,
            periods: records.state.periods,
            snapshots: records.state.snapshots,
            usesSharedCache: true
        )
    }

    /// Expands an explicit career timeline through the same shared-rule and
    /// three-layer resolver used by Records. Life can add an in-memory
    /// backfill period without mutating or duplicating the user's archive.
    private func resolveDays(
        from: Date,
        through: Date,
        periods: [CareerPeriod],
        snapshots: [ScheduleSnapshot],
        usesSharedCache: Bool
    ) -> [DayResolution] {
        let calendar = recordsCalendar
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return [] }
        if usesSharedCache,
           let cached = resolvedDaysCache,
           cached.revision == records.revision,
           cached.from == start,
           cached.through == end {
            return cached.days
        }

        var expansions: [UUID: [String: ScheduleExpansion]] = [:]
        var expansionFailures: Set<UUID> = []
        var periodCalendars: [UUID: Calendar] = [:]
        var cursor = start
        var result: [DayResolution] = []
        while cursor <= end {
            let covering = DayRecordResolver.period(on: cursor, from: periods)
            let dayCalendar: Calendar
            if let covering {
                if let cached = periodCalendars[covering.id] {
                    dayCalendar = cached
                } else {
                    let next = covering.civilCalendar()
                    periodCalendars[covering.id] = next
                    dayCalendar = next
                }
            } else {
                dayCalendar = calendar
            }
            let dayKey = RecordJSON.dayKey(cursor, calendar: dayCalendar)
            let snapshot = covering.flatMap {
                DayRecordResolver.snapshot(on: cursor, in: $0, from: snapshots)
            }
            if let snapshot, expansions[snapshot.id] == nil, !expansionFailures.contains(snapshot.id) {
                let expansionFrom = dayCalendar.startOfDay(for: from)
                let expansionThrough = dayCalendar.startOfDay(for: through)
                if let configuration = try? JSONDecoder().decode(
                    ScheduleHoursConfiguration.self,
                    from: snapshot.configurationData
                ),
                   let days = try? CountdownRules.shared.expandScheduleRange(
                    configuration: configuration,
                    from: expansionFrom,
                    through: expansionThrough,
                    timeZone: covering?.timeZone
                   ) {
                    // First day wins. A civil calendar that skips a date (a
                    // zone crossing the date line) can hand back two rows under
                    // one dayKey, and `uniqueKeysWithValues` would trap on it.
                    expansions[snapshot.id] = Dictionary(
                        days.map {
                            ($0.dayKey, ScheduleExpansion(isWorkday: $0.isWorkday, segments: $0.segments))
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                } else {
                    expansionFailures.insert(snapshot.id)
                    lastRulesError = "scheduleExpandFailed"
                }
            }
            let expansion: ScheduleExpansion
            if let snapshot, expansionFailures.contains(snapshot.id) {
                expansion = .failed
            } else {
                expansion = snapshot.flatMap { expansions[$0.id]?[dayKey] }
                    ?? ScheduleExpansion(isWorkday: false, segments: [])
            }
            result.append(
                DayRecordResolver.resolve(
                    dayKey: dayKey,
                    shiftAnchorDate: dayCalendar.startOfDay(for: cursor),
                    periods: periods,
                    snapshots: snapshots,
                    exceptions: records.state.exceptions,
                    overrides: records.state.overrides,
                    expand: { _ in expansion }
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        if usesSharedCache, !result.contains(where: \.expansionFailed) {
            resolvedDaysCache = (records.revision, start, end, result)
        }
        return result
    }

    /// Same result as `resolvedDays`, but the JavaScriptCore walk runs off the
    /// main actor. Opening the year chart used to expand 365 days during the
    /// navigation push and freeze the Records list.
    func prepareResolvedDays(from: Date, through: Date, now: Date = .now) async -> [DayResolution] {
        records.ensureSeeded(hours: hoursConfiguration(at: now), at: now, timeZone: recordsTimeZone)
        _ = reconcileRecordSchedule(at: now)
        let calendar = recordsCalendar
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return [] }

        await prefetchScheduleExpansions(
            from: start,
            through: end,
            periods: records.state.periods,
            snapshots: records.state.snapshots
        )
        return resolvedDays(from: from, through: through, now: now)
    }

    /// Records month/year projection. This reuses the generated TypeScript
    /// schedule rules and Life's in-memory history backfill; it never creates
    /// durable observations, overrides, periods or snapshots for estimated
    /// days.
    func prepareRecordsDisplayDays(
        from: Date,
        through: Date,
        now: Date = .now
    ) async -> [DayResolution] {
        records.ensureSeeded(hours: hoursConfiguration(at: now), at: now, timeZone: recordsTimeZone)
        _ = reconcileRecordSchedule(at: now)
        guard let bounds = lifeWorkProjectionBounds(now: now) else {
            return await prepareResolvedDays(from: from, through: through, now: now)
        }
        let archive = lifeScheduleArchive(workStart: bounds.start, now: now)
        await prefetchScheduleExpansions(
            from: from,
            through: through,
            periods: archive.periods,
            snapshots: archive.snapshots
        )
        return resolveDays(
            from: from,
            through: through,
            periods: archive.periods,
            snapshots: archive.snapshots,
            usesSharedCache: false
        )
    }

    private func prefetchScheduleExpansions(
        from: Date,
        through: Date,
        periods: [CareerPeriod],
        snapshots: [ScheduleSnapshot]
    ) async {
        let calendar = recordsCalendar
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return }

        var seen: Set<UUID> = []
        var cursor = start
        while cursor <= end {
            let covering = DayRecordResolver.period(on: cursor, from: periods)
            let snapshot = covering.flatMap {
                DayRecordResolver.snapshot(on: cursor, in: $0, from: snapshots)
            }
            if let snapshot, seen.insert(snapshot.id).inserted,
               let configuration = try? JSONDecoder().decode(
                ScheduleHoursConfiguration.self,
                from: snapshot.configurationData
               ) {
                let dayCalendar = covering?.civilCalendar() ?? calendar
                try? await CountdownRules.shared.prefetchExpansion(
                    configuration: configuration,
                    from: dayCalendar.startOfDay(for: from),
                    through: dayCalendar.startOfDay(for: through),
                    timeZone: covering?.timeZone
                )
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
    }

    func observations(on day: Date) -> [WorkObservation] {
        observationIndex()[RecordJSON.dayKey(day, calendar: recordsCalendar)] ?? []
    }

    /// Observations grouped by the records-zone civil day. Chart metrics used
    /// to scan the whole archive once per day of the window.
    private func observationIndex() -> [String: [WorkObservation]] {
        let revision = records.revision
        if let cached = observationIndexCache, cached.revision == revision {
            return cached.byDay
        }
        var byDay: [String: [WorkObservation]] = [:]
        var calendars: [String: Calendar] = [:]
        for observation in records.state.observations {
            let zoneID = observation.timeZoneIdentifier
            let calendar: Calendar
            if let cached = calendars[zoneID] {
                calendar = cached
            } else {
                var next = Calendar(identifier: .gregorian)
                next.timeZone = TimeZone(identifier: zoneID) ?? recordsTimeZone
                calendars[zoneID] = next
                calendar = next
            }
            let key = RecordJSON.dayKey(observation.shiftAnchorDate, calendar: calendar)
            byDay[key, default: []].append(observation)
        }
        for key in byDay.keys {
            byDay[key]?.sort { $0.occurredAt < $1.occurredAt }
        }
        observationIndexCache = (revision, byDay)
        return byDay
    }

    /// Every civil day that has a user-authored Records fact. This deliberately
    /// has broader semantics than `recordedWorkDays()`: the latter remains the
    /// timer-only work metric, while the All Records navigation must also let a
    /// person find a manual correction, leave day, makeup day, or rest day.
    ///
    /// The key is a civil `YYYY-MM-DD`, never an absolute `Date`. An archive can
    /// contain rows written while travelling, so formatting a stored midnight in
    /// the device's current zone is not a valid way to recover its calendar day.
    func recordDayIndex() -> [RecordDayIndexEntry] {
        var entries: [String: RecordDayIndexEntry] = [:]

        for observation in records.state.observations where observation.kind.isWorkSessionRecord {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: observation.timeZoneIdentifier) ?? recordsTimeZone
            let key = RecordJSON.dayKey(observation.shiftAnchorDate, calendar: calendar)
            var entry = entries[key] ?? RecordDayIndexEntry(dayKey: key)
            entry.observations.append(observation)
            entries[key] = entry
        }

        for override in records.state.overrides where override.kind != .cleared {
            var entry = entries[override.dayKey] ?? RecordDayIndexEntry(dayKey: override.dayKey)
            entry.dayOverride = override
            entries[override.dayKey] = entry
        }

        for exception in records.state.exceptions where exception.origin == .user && !exception.isCleared {
            let key = Self.civilDayKey(fromExceptionKey: exception.dayKey)
            guard Self.isCivilDayKey(key) else { continue }
            var entry = entries[key] ?? RecordDayIndexEntry(dayKey: key)
            entry.calendarException = exception
            entries[key] = entry
        }

        return entries.values
            .map { entry in
                var sorted = entry
                sorted.observations.sort { $0.occurredAt < $1.occurredAt }
                return sorted
            }
            .sorted { $0.dayKey > $1.dayKey }
    }

    /// Days the user actually started, stopped, or logged overtime.
    ///
    /// The free list is this, not a year of schedule expansion. Opening the
    /// timer does not create a row. Life view can still project the schedule
    /// later without stuffing those days in here first.
    func recordedWorkDays() -> [RecordedWorkDay] {
        var groups: [String: [WorkObservation]] = [:]
        var anchors: [String: Date] = [:]
        var calendars: [String: Calendar] = [:]
        for observation in records.state.observations where observation.kind.isWorkSessionRecord {
            let zoneID = observation.timeZoneIdentifier
            let calendar: Calendar
            if let cached = calendars[zoneID] {
                calendar = cached
            } else {
                var next = Calendar(identifier: .gregorian)
                next.timeZone = TimeZone(identifier: zoneID) ?? recordsTimeZone
                calendars[zoneID] = next
                calendar = next
            }
            let key = RecordJSON.dayKey(observation.shiftAnchorDate, calendar: calendar)
            groups[key, default: []].append(observation)
            if anchors[key] == nil {
                anchors[key] = calendar.startOfDay(for: observation.shiftAnchorDate)
            }
        }
        return groups.keys.map { key in
            RecordedWorkDay(
                dayKey: key,
                shiftAnchorDate: anchors[key] ?? .distantPast,
                observations: (groups[key] ?? []).sorted { $0.occurredAt < $1.occurredAt }
            )
        }
        .sorted { $0.shiftAnchorDate > $1.shiftAnchorDate }
    }

    /// Formats an archive civil key in the records calendar. Keep this separate
    /// from the `Date` overload: callers with an archival key must not first
    /// construct an instant and accidentally move it to an adjacent day.
    func formatRecordsDayTitle(dayKey: String) -> String {
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else {
            return dayKey
        }
        return formatRecordsDayTitle(date)
    }

    /// The sync conflict recorded against a civil day, if any. Conflict keys
    /// carry a `#user` suffix, so the day page's exact string comparison never
    /// matched one the month grid had already flagged.
    func recordsConflict(forDayKey dayKey: String) -> SyncConflictCopy? {
        records.state.sync.conflicts.first {
            Self.civilDayKey(fromExceptionKey: $0.logicalKey) == dayKey
        }
    }

    private static func civilDayKey(fromExceptionKey key: String) -> String {
        String(key.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    private static func isCivilDayKey(_ key: String) -> Bool {
        key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    func timeZoneIdentifierForWriting(startingNewSession: Bool = false) -> String {
        if startingNewSession, systemTimeZoneDiffersFromRecords {
            return TimeZone.current.identifier
        }
        return countdownTimeZoneIdentifier
    }

    func writingTimeZone(startingNewSession: Bool = false) -> TimeZone {
        TimeZone(identifier: timeZoneIdentifierForWriting(startingNewSession: startingNewSession))
            ?? recordsTimeZone
    }

    func migrateRecordsTimeZone(to timeZone: TimeZone = .current, at date: Date = .now) {
        if countdownStarted {
            lockSessionTimeZone(to: recordsTimeZoneIdentifier, at: date)
        }
        records.migrateCalendarTimeZone(to: timeZone.identifier, at: date)
        recordsTimeZoneIdentifier = timeZone.identifier
    }

    private func lockSessionTimeZone(to identifier: String, at date: Date) {
        sessionTimeZoneIdentifier = identifier
        sessionTimeZoneUntilMs = snapshot(at: date)?.endAtMs
    }

    private func clearSessionTimeZone() {
        sessionTimeZoneIdentifier = nil
        sessionTimeZoneUntilMs = nil
    }

    @discardableResult
    private func expireSessionTimeZone(at date: Date) -> Bool {
        guard let until = sessionTimeZoneUntilMs,
              date.timeIntervalSince1970 * 1_000 >= until
        else { return false }
        clearSessionTimeZone()
        return true
    }

    func daysRecordedOutsidePeriodTimeZone() -> [String] {
        let periodZones = Set(records.state.periods.map(\.timeZoneIdentifier))
        var calendars: [String: Calendar] = [:]
        var tagged: [(String, String)] = records.state.overrides.map { ($0.dayKey, $0.timeZoneIdentifier) }
        tagged.append(contentsOf: records.state.exceptions.map { ($0.dayKey, $0.timeZoneIdentifier) })
        for observation in records.state.observations {
            let zoneID = observation.timeZoneIdentifier
            let calendar: Calendar
            if let cached = calendars[zoneID] {
                calendar = cached
            } else {
                var next = Calendar(identifier: .gregorian)
                next.timeZone = TimeZone(identifier: zoneID) ?? recordsTimeZone
                calendars[zoneID] = next
                calendar = next
            }
            tagged.append((RecordJSON.dayKey(observation.shiftAnchorDate, calendar: calendar), zoneID))
        }
        return Set(
            tagged.compactMap { dayKey, zone in
                periodZones.contains(zone) ? nil : dayKey
            }
        ).sorted()
    }

    func exportRecordsFile(at date: Date = .now, includeLifeProfile: Bool = true) throws -> URL {
        let data = try records.exportJSON(
            exportedAt: date,
            timeZone: recordsTimeZone,
            includeLifeProfile: includeLifeProfile
        )
        let name = includeLifeProfile ? "doneat-records.json" : "doneat-records-without-life.json"
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func previewRecordsImport(_ data: Data) throws -> RecordImportReport {
        let document = try RecordJSON.decode(data)
        var candidate = records.state
        return try RecordJSON.apply(document, to: &candidate, mode: .skipErased)
    }

    func confirmRecordsOwnerIfNeeded(reasonKey: String) async -> Bool {
        guard hideEarnings else { return true }
        return await BiometricGate.confirmOwner(reason: t(reasonKey))
    }

    var recordsDataStatusLabel: String {
        if !records.state.sync.conflicts.isEmpty {
            return t("recordsConflictCount", values: ["count": "\(records.state.sync.conflicts.count)"])
        }
        if records.state.sync.syncEnabled {
            return t("syncStatusReady")
        }
        return t("syncStatusOff")
    }

    func noteTimerSurfaceVisible(at date: Date = .now) {
        guard plus.shouldCollectObservations else { return }
        // The first-seen row is one per civil day. Calling this on every tab
        // switch used to rebuild a JavaScriptCore snapshot just to write nothing.
        let dayKey = RecordJSON.dayKey(date, calendar: recordsCalendar)
        if (observationIndex()[dayKey] ?? []).contains(where: { $0.kind == .timerSurfaceFirstSeen }) {
            return
        }
        writeObservation(.timerSurfaceFirstSeen, at: date, eventID: UUID())
    }

    func writeObservation(
        _ kind: WorkObservationKind,
        at date: Date,
        eventID: UUID
    ) {
        guard plus.shouldCollectObservations else { return }
        records.ensureSeeded(hours: hoursConfiguration(at: date), at: date, timeZone: recordsTimeZone)
        let shift = snapshot(at: date)
        let anchor = shift?.startDate ?? date
        var valueData: Data?
        if kind == .overtimeDeclared, let overtimeEndAtMs {
            valueData = try? JSONEncoder().encode(OvertimeDeclarationPayload(
                overtimeEndAtMs: overtimeEndAtMs,
                plannedEndAtMs: shift?.plannedEndAtMs
            ))
        }
        let zone = writingTimeZone()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        records.recordObservation(
            kind: kind,
            eventID: eventID,
            shiftAnchorDate: calendar.startOfDay(for: anchor),
            occurredAt: date,
            snapshotID: records.currentSnapshotID(on: anchor) ?? UUID(),
            valueData: valueData,
            timeZoneIdentifier: zone.identifier
        )
    }

    /// 002 P0A first cut: the live timer marks as a `DayOverride`, or `nil`
    /// when today still falls through to the schedule.
    func projectedDayOverride(at date: Date = .now) -> DayOverride? {
        let useBaseStart = isStartedEarly(at: date)
        let shift = snapshot(
            at: date,
            startMinutes: useBaseStart ? scheduleStartMinutes(at: date) : nil
        )
        let marks = timerDayMarks(at: date, workday: shift?.isWorkday == true)
        guard let shift else { return nil }
        let zone = writingTimeZone()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return DayOverrideProjection.project(
            marks: marks,
            dayKey: Self.dayKey(for: shift.startDate, timeZone: zone),
            shiftAnchorDate: calendar.startOfDay(for: shift.startDate),
            plannedSegments: shift.segments,
            timeZoneIdentifier: zone.identifier
        )
    }

    func timerDayMarks(at date: Date = .now, workday: Bool? = nil) -> TimerDayMarks {
        let current = snapshot(at: date)
        let endedEarly = current.map(isEndedEarly) ?? false
        return TimerDayMarks(
            earlyStartAtMs: isStartedEarly(at: date) ? earlyStartAtMs : nil,
            earlyOffAtMs: endedEarly ? earlyOffAtMs : nil,
            forcedWorkdayDate: forcedWorkdayDate,
            hasTodayOverride: usesTodayOverride(at: date),
            hasUnscheduledSession: countdownStarted && effectiveScheduleMode(at: date) == .off,
            isWorkday: workday ?? (current?.isWorkday == true)
        )
    }

    /// Hours without an early clock-in, so the projector can apply that bound
    /// itself instead of baking it into the rules snapshot twice.
    private func scheduleStartMinutes(at date: Date) -> Int {
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.startMinutes
        }
        return startMinutes
    }

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
#if DEBUG
        if debugTimerSession != nil { return false }
#endif
        guard let forcedWorkdayDate else { return false }
        return forcedWorkdayDate == Self.dayKey(for: shift.startDate, timeZone: countdownTimeZone)
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

    func refreshSystemTimeZone() {
        let current = TimeZone.current.identifier
        if systemTimeZoneIdentifier != current {
            systemTimeZoneIdentifier = current
        }
    }

    func t(_ key: String, values: [String: String] = [:]) -> String {
        localizer.string(key, locale: languageCode, values: values)
    }

    /// Plural-aware lookup. `count` picks the grammatical variant and, unless
    /// the caller supplies its own, also fills `{{count}}` with the
    /// locale-formatted number. Keeping both on one argument is the point:
    /// when a call site formatted the number itself and left the lookup
    /// countless, German rendered a single recorded day as "1 Arbeitstage".
    func t(_ key: String, count: Int, values: [String: String] = [:]) -> String {
        var merged = values
        if merged["count"] == nil { merged["count"] = formatCount(count) }
        return localizer.string(key, locale: languageCode, count: count, values: merged)
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
#if DEBUG
        if let scenario = debugTimerSession?.scenario {
            let start = startMinutes ?? scenario.startMinutes
            let end = endMinutes ?? scenario.endMinutes
            return .init(
                startTime: timeString(start),
                endTime: timeString(end),
                nowMs: date.timeIntervalSince1970 * 1_000,
                workdays: scenario.workdays.sorted(),
                schedule: nativeSchedule(at: date, using: source),
                breakStartTime: timeString(scenario.lunchStartMinutes),
                breakDurationMinutes: scenario.lunchDurationMinutes,
                overtimeEndAtMs: scenario.overtimeEndAtMs(on: date),
                // Marketing captures must never expose the tester's salary.
                salaryAmount: "",
                salaryType: salaryType.rawValue,
                monthlyWorkingDays: monthlyWorkingDays,
                annualBonusMonths: 0,
                forcedWorkdayStartMs: nil,
                timeZoneIdentifier: rulesTimeZoneIdentifier
            )
        }
#endif
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
            forcedWorkdayStartMs: applyOverride ? forcedWorkdayStartMs : nil,
            timeZoneIdentifier: rulesTimeZoneIdentifier
        )
    }

    /// Whether the explicit Save action needs the second choice about today.
    /// Swift assembles the current and proposed inputs; the generated
    /// TypeScript bundle decides whether either timeline still has a relevant
    /// boundary today.
    func shouldPromptApplyingToToday(
        _ change: ScheduleFieldChange,
        scope: ScheduleChangeScope,
        at date: Date = .now
    ) -> Bool {
        CountdownRules.shared.shouldPromptApplyToday(
            current: rulesInput(at: date),
            candidate: rulesInput(applying: change, at: date),
            kind: scope.rawValue,
            schedulePatternChanged: change.changesSchedulePattern
        )
    }

    private func rulesInput(
        applying change: ScheduleFieldChange,
        at date: Date
    ) -> NativeRulesInput {
        let start = change.startMinutes ?? startMinutes
        let end = change.endMinutes ?? endMinutes
        let lunchOn = change.lunchEnabled ?? lunchEnabled
        let lunchStart = change.lunchStartMinutes ?? lunchStartMinutes
        let lunchDuration = change.lunchDurationMinutes ?? lunchDurationMinutes
        return .init(
            startTime: timeString(start),
            endTime: timeString(end),
            nowMs: date.timeIntervalSince1970 * 1_000,
            workdays: (change.workdays ?? workdays).sorted(),
            schedule: nativeSchedule(applying: change, at: date),
            breakStartTime: lunchOn ? timeString(lunchStart) : nil,
            breakDurationMinutes: lunchOn ? lunchDuration : 0,
            // Applying a settings draft to today deliberately clears overtime.
            overtimeEndAtMs: nil,
            salaryAmount: salaryEnabled ? salaryAmount : "",
            salaryType: salaryType.rawValue,
            monthlyWorkingDays: monthlyWorkingDays,
            annualBonusMonths: annualBonusEnabled ? annualBonusMonths : 0,
            forcedWorkdayStartMs: forcedWorkdayStartMs,
            timeZoneIdentifier: rulesTimeZoneIdentifier
        )
    }

    private func nativeSchedule(
        applying change: ScheduleFieldChange,
        at date: Date
    ) -> NativeWorkSchedule {
        let mode = change.scheduleMode ?? scheduleMode
        let weekType = change.alternatingWeekType ?? alternatingWeekType
        let weekendDay = change.alternatingWeekendWorkday ?? alternatingWeekendWorkday
        let weekWasReanchored = change.scheduleMode == .alternating
            || change.alternatingWeekType != nil
        let weekStart = weekWasReanchored
            ? Self.startOfWeek(containing: date, timeZone: recordsTimeZone).timeIntervalSince1970 * 1_000
            : alternatingReferenceWeekStartMs

        let rotationWork = change.rotationWorkDays ?? rotationWorkDays
        let rotationRest = change.rotationRestDays ?? rotationRestDays
        var rotationAnchor = change.scheduleMode == .rotation
            ? recordsCalendar.startOfDay(for: date).timeIntervalSince1970 * 1_000
            : rotationAnchorMs
        if let cycleDay = change.rotationCycleDay {
            let length = max(2, rotationWork + rotationRest)
            let normalized = min(length, max(1, cycleDay))
            let today = recordsCalendar.startOfDay(for: date)
            if let anchor = recordsCalendar.date(
                byAdding: .day,
                value: -(normalized - 1),
                to: today
            ) {
                rotationAnchor = anchor.timeIntervalSince1970 * 1_000
            }
        }

        return .init(
            mode: mode.rawValue,
            referenceWeekStartMs: mode == .alternating ? weekStart : nil,
            referenceWeekType: mode == .alternating ? weekType.rawValue : nil,
            singleWeekendWorkday: mode == .alternating ? weekendDay : nil,
            rotationAnchorMs: mode == .rotation ? rotationAnchor : nil,
            rotationWorkDays: mode == .rotation ? rotationWork : nil,
            rotationRestDays: mode == .rotation ? rotationRest : nil
        )
    }

    func shiftReminders(at date: Date = .now) throws -> [NativeReminder] {
        let currentSnapshot = snapshot(at: date)
        let inputs = reminderInputs(
            cycleEndSummaryBody: currentSnapshot.flatMap {
                cycleEndSummaryNotificationBody(for: $0, at: date)
            }
        )
        let effective = try CountdownRules.shared.reminders(
            input: rulesInput(at: date),
            reminderInputs: inputs
        )
        let current = effective.filter { $0.id.hasPrefix("current:") }
        let nextSnapshot = currentSnapshot?.nextShiftStartDate.flatMap {
            snapshot(at: $0.addingTimeInterval(1))
        }
        let nextInputs = reminderInputs(
            cycleEndSummaryBody: nextSnapshot.flatMap {
                cycleEndSummaryNotificationBody(for: $0, at: $0.startDate)
            }
        )
        let next = try CountdownRules.shared.reminders(
            input: rulesInput(
                at: date,
                using: projectsFutureFromBase(at: date) ? .base : .effective
            ),
            reminderInputs: nextInputs
        ).filter { $0.id.hasPrefix("next:") }
        guard let snapshot = currentSnapshot else { return current + next }
        // Rest days and settlement both still produce a `current:` window from
        // `getShiftBounds` — Saturday 09:00–17:00 on a weekend, or Saturday
        // 22:00 after a Friday overnight ended at 06:00. Those are not a shift
        // the user is in, so they must not be scheduled.
        let includeCurrent = (snapshot.isWorkday || isForcedWorkday(snapshot))
            && !isShiftComplete(snapshot)
        return (includeCurrent ? current : []) + next
    }

    func reminderInputs(cycleEndSummaryBody: String? = nil) -> NativeReminderInputs {
        func title(_ remaining: Int) -> String {
            t("notificationMilestoneTitle", values: ["percent": "\(remaining)"])
        }
        return .init(
            mode: presentationNotificationMode.rawValue,
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
            lunchStartEnabled: presentationLunchStartReminderEnabled,
            lunchStartBody: t("lunchStartNotification"),
            lunchEndEnabled: presentationLunchEndReminderEnabled,
            lunchEndBody: t("lunchEndNotification"),
            microBreakEnabled: presentationMicroBreakEnabled,
            microBreakTitle: t("microBreakReminder"),
            microBreakIntervalMinutes: presentationMicroBreakIntervalMinutes,
            microBreakMessages: strings("microBreakMessages"),
            cycleEndSummaryBody: cycleEndSummaryBody
        )
    }

    var cycleEndSummaryNotificationsAreActive: Bool {
        cycleEndSummaryNotificationEnabled && plus.isAuthorized
    }

    func setCycleEndSummaryNotifications(_ enabled: Bool) {
        guard enabled else {
            cycleEndSummaryNotificationEnabled = false
            return
        }
        openPaidOrRun(
            .cycleEndSummaryNotifications,
            action: .enableCycleEndSummaryNotifications
        )
    }

    /// Builds the body only for the last resolved workday before a rest day.
    /// Work/rest classification has already come from the shared TypeScript
    /// expansion and then passed through calendar exceptions and manual edits.
    func cycleEndSummaryNotificationBody(
        for snapshot: NativeShiftSnapshot,
        at date: Date = .now
    ) -> String? {
        guard cycleEndSummaryNotificationsAreActive,
              scheduleMode != .off,
              snapshot.isWorkday || isForcedWorkday(snapshot)
        else { return nil }

        let calendar = recordsCalendar
        let anchor = calendar.startOfDay(for: snapshot.startDate)
        guard let from = calendar.date(byAdding: .day, value: -31, to: anchor),
              let through = calendar.date(byAdding: .day, value: 1, to: anchor)
        else { return nil }
        let resolved = resolvedDays(from: from, through: through, now: date)
        let days = resolved.map { day in
            ScheduleCycleDay(
                dayKey: day.dayKey,
                isWorkday: day.isScheduledWorkday,
                workMs: day.segments.reduce(0) { partial, segment in
                    partial + Int64(max(0, segment.endAtMs - segment.startAtMs).rounded())
                },
                overtimeMs: overtimeSegments(on: day).reduce(0) { partial, segment in
                    partial + Int64(max(0, segment.endAtMs - segment.startAtMs).rounded())
                },
                isComplete: !day.expansionFailed
            )
        }
        let dayKey = RecordJSON.dayKey(snapshot.startDate, calendar: calendar)
        guard let summary = ScheduleCycleSummaryCalculator.summary(endingAt: dayKey, in: days) else {
            return nil
        }
        return t("cycleEndSummaryNotificationBody", values: [
            "days": formatCount(summary.workdayCount),
            "work": formatDuration(Double(summary.workMs), includeSeconds: false),
            "overtime": formatDuration(Double(summary.overtimeMs), includeSeconds: false),
        ])
    }

    func noteCountdownCompleted(endAtMs: Double) {
        let previous = reviewPromptState
        reviewPromptState.noteCompletion(atMs: endAtMs)
        if reviewPromptState != previous { persistReviewPromptState() }
    }

    func presentReviewPromptIfEligible() {
        guard reviewPromptEligibleThisLaunch,
              onboardingComplete,
              plus.hasSeenIntro,
              !reviewPromptPresented
        else { return }
        reviewPromptEligibleThisLaunch = false
        reviewPromptPresented = true
    }

    func acceptReviewPrompt() {
        reviewPromptState.disable()
        reviewPromptPresented = false
        persistReviewPromptState()
    }

    func deferReviewPrompt() {
        reviewPromptState.deferUntilNextCompletion()
        reviewPromptPresented = false
        persistReviewPromptState()
    }

    func disableAutomaticReviewPrompt() {
        reviewPromptEligibleThisLaunch = false
        reviewPromptState.disable()
        reviewPromptPresented = false
        persistReviewPromptState()
    }

    private func revokeCountdownCompletion(endAtMs: Double?) {
        guard let endAtMs else { return }
        let previous = reviewPromptState
        reviewPromptState.revokeCompletion(atMs: endAtMs)
        if reviewPromptState != previous { persistReviewPromptState() }
    }

    private func persistReviewPromptState() {
        guard let data = try? JSONEncoder().encode(reviewPromptState) else { return }
        defaults.set(data, forKey: Key.appReviewPrompt)
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
        if presentationMicroBreakEnabled,
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
                detail: t("minutesShort", values: ["count": "\(presentationMicroBreakIntervalMinutes)"])
            ))
        }

        if plus.isAuthorized {
            if let session = activeFocusSession(), session.plannedEndAt > now {
                let icon = session.taskID
                    .flatMap { id in records.state.focusTasks.first(where: { $0.id == id }) }
                    .map { $0.icon.systemName }
                events.append(.init(
                    id: "focus-session-\(session.id.uuidString)",
                    kind: .focus,
                    date: session.plannedEndAt,
                    title: t("focusRunning"),
                    detail: t("focusEndsAt", values: ["time": formatTime(session.plannedEndAt)]),
                    symbolName: icon
                ))
            }

            let horizon = now.addingTimeInterval(2 * 86_400)
            let planned = focusPlanAssignments(for: snapshot).filter {
                $0.block.start > now && $0.block.start <= horizon
            }
            let plannedTaskIDs = Set(planned.compactMap { $0.assignment.taskID })
            for item in planned {
                let isBreak = item.assignment.kind == .breakTime
                events.append(.init(
                    id: "focus-plan-\(item.assignment.blockStartAtMs)",
                    kind: isBreak ? .focusBreak : .focus,
                    date: item.block.start,
                    title: isBreak
                        ? t("focusBreak")
                        : (item.assignment.taskTitle ?? t("focusTitle")),
                    detail: t(
                        "focusPomodoroSummary",
                        values: [
                            "count": formatCount(1),
                            "minutes": formatCount(item.block.durationMinutes),
                        ]
                    ),
                    symbolName: isBreak ? "cup.and.saucer.fill" : item.assignment.taskIcon?.systemName
                ))
            }

            for task in records.state.focusTasks where task.completedAt == nil && task.deletedAt == nil {
                guard !plannedTaskIDs.contains(task.id),
                      let start = task.scheduledStartAt,
                      start > now,
                      start <= horizon
                else { continue }
                events.append(.init(
                    id: "focus-task-\(task.id.uuidString)",
                    kind: .focus,
                    date: start,
                    title: task.title,
                    detail: t(
                        "focusPomodoroSummary",
                        values: [
                            "count": formatCount(max(1, task.estimatedPomodoros)),
                            "minutes": formatCount(focusTimerSettings.normalized.focusMinutes),
                        ]
                    ),
                    symbolName: task.icon.systemName
                ))
            }
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
        if presentationNotificationMode == .milestones {
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

    func startCountdown(force: Bool = false, at date: Date = .now) {
        if scheduleMode == .off {
            // Manual "start" is a new session. A leftover early-off from a
            // scheduled day that was then switched to off would otherwise pin
            // this button to settlement: ended-early never runs.
            clearEarlyClockOffRecord()
            clearEarlyClockInRecord()
        }
        commitDisplayedHours()
        let wasRunning = countdownStarted
        countdownStarted = true
        if force || scheduleMode == .off, !wasRunning || sessionTimeZoneIdentifier == nil {
            lockSessionTimeZone(
                to: timeZoneIdentifierForWriting(startingNewSession: true),
                at: date
            )
        }
        let shift = snapshot(at: date)
        // The day the shift starts, not the day the button was pressed. They
        // differ for an overnight shift forced after midnight, and marking the
        // press day there would mark a run nobody is looking at.
        forcedWorkdayDate = force
            ? Self.dayKey(for: shift?.startDate ?? date, timeZone: countdownTimeZone)
            : nil
        if let shift, isEndedEarly(shift) {
            // Same shift, possibly with nudged hours. Keep the early-off
            // record so settlement stays on this run.
        } else {
            clearEarlyClockOffRecord()
        }
        recordActiveCountdownBoundary(at: date)
        writeObservation(.countdownStarted, at: date, eventID: UUID())
        persistProjectedDayOverride(at: date)
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
    var clockInConfirmPending = false
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
        if clockInConfirmPending { clockInConfirmPending = false }
        if cancelManualTimingConfirmPending { cancelManualTimingConfirmPending = false }
    }

    /// First press arms, second press commits. Starting the day early is the
    /// same kind of one-way door as clocking off early.
    func requestClockInEarly(at date: Date = .now) {
        guard let shift = snapshot(at: date), shift.isBeforeStart(at: date) else { return }
        guard clockInConfirmPending else {
            clockInConfirmPending = true
            return
        }
        clockInConfirmPending = false
        clockInEarly(at: date)
    }

    func clockOffEarly(at date: Date = .now) {
        guard let shift = snapshot(at: date), !shift.isBeforeStart(at: date) else { return }
        earlyOffAtMs = date.timeIntervalSince1970 * 1_000
        earlyOffShiftEndAtMs = shift.endAtMs
        earlyOffSnapshot = shift
        clockOffConfirmPending = false
        timelineExpanded = false
        // Leave a forced rest-day run in place until settlement: cancelling
        // manual timing is a different action. Clocking off still ends the day.
        forcedWorkdayDate = isForcedWorkday(shift) ? forcedWorkdayDate : nil
        // Keep the session boundary so an unscheduled midnight reset still
        // knows which calendar day this run belonged to. Overtime stays too:
        // clearing it here would shrink the window and settlement would lose
        // the extra hours.
        writeObservation(.countdownStopped, at: date, eventID: UUID())
        persistProjectedDayOverride(at: date)
        noteCountdownCompleted(endAtMs: earlyOffAtMs ?? date.timeIntervalSince1970 * 1_000)
    }

    /// Takes it back. Deliberately its own action rather than a side effect of
    /// editing the schedule: changing tomorrow's hours must never quietly
    /// resurrect today, or every settings visit becomes a coin toss.
    func undoEarlyClockOff() {
        let revokedCompletionAtMs = earlyOffAtMs
        clearEarlyClockOffRecord()
        revokeCountdownCompletion(endAtMs: revokedCompletionAtMs)
        recordActiveCountdownBoundary()
    }

    func clockInEarly(at date: Date = .now) {
        guard let shift = snapshot(at: date), shift.isBeforeStart(at: date) else { return }
        let floored = Self.floorToMinute(date)
        earlyStartAtMs = floored.timeIntervalSince1970 * 1_000
        let endDay = Calendar.current.startOfDay(for: shift.endDate)
        earlyStartUntilMs = Calendar.current.date(byAdding: .day, value: 1, to: endDay)
            .map { $0.timeIntervalSince1970 * 1_000 }
        clockInConfirmPending = false
        writeObservation(.countdownStarted, at: date, eventID: UUID())
        persistProjectedDayOverride(at: date)
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
        clockInConfirmPending = false
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

    /// Live Activity + notifications-off still needs a clock-off ping, but
    /// only for a shift the user is actually in. Rest-day dummy windows must
    /// not go through this side door.
    func shouldScheduleLiveActivityEndFallback(
        snapshot: NativeShiftSnapshot?,
        at date: Date = .now
    ) -> Bool {
        guard liveActivityEnabled, notificationMode == .off else { return false }
        guard publishesLiveSurfaces else { return false }
        guard let snapshot else { return false }
        guard cycleEndSummaryNotificationBody(for: snapshot, at: date) == nil else { return false }
        guard snapshot.endAtMs > date.timeIntervalSince1970 * 1_000 else { return false }
        guard !isEndedEarly(snapshot) else { return false }
        return (snapshot.isWorkday || isForcedWorkday(snapshot)) && !isShiftComplete(snapshot)
    }

    var publishesLiveSurfaces: Bool {
#if DEBUG
        if debugTimerSession != nil { return false }
#endif
        return onboardingComplete && (followsSchedule || countdownStarted)
    }

    var followsSchedule: Bool { followsSchedule(at: .now) }

    func followsSchedule(at date: Date = .now) -> Bool {
#if DEBUG
        if let scenario = debugTimerSession?.scenario {
            return scenario.scheduleMode != .off
        }
#endif
        return onboardingComplete && effectiveScheduleMode(at: date) != .off
    }

    func shouldQuerySnapshot(at date: Date = .now) -> Bool {
#if DEBUG
        if let scenario = debugTimerSession?.scenario {
            return scenario.scheduleMode != .off || scenario.sessionActive
        }
#endif
        return followsSchedule(at: date) || countdownStarted
    }

    func visualPhase(snapshot: NativeShiftSnapshot?, at date: Date = .now) -> TimerVisualPhase {
#if DEBUG
        if let scenario = debugTimerSession?.scenario {
            return TimerVisualPhase.resolve(
                followsSchedule: scenario.scheduleMode != .off,
                sessionActive: scenario.sessionActive,
                snapshot: snapshot,
                forceToday: false,
                endedEarly: false,
                now: date
            )
        }
#endif
        return TimerVisualPhase.resolve(
            followsSchedule: followsSchedule(at: date),
            sessionActive: countdownStarted,
            snapshot: snapshot,
            forceToday: snapshot.map(isForcedWorkday) ?? false,
            endedEarly: snapshot.map(isEndedEarly) ?? false,
            now: date
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

    func stopCountdown(at date: Date = .now, recordObservation: Bool = true) {
        // A schedule has no session to stop. Unscheduled midnight still
        // tears down today's manual run.
        guard !followsSchedule else {
            clockOffConfirmPending = false
            clockInConfirmPending = false
            cancelManualTimingConfirmPending = false
            return
        }
        clockOffConfirmPending = false
        clockInConfirmPending = false
        cancelManualTimingConfirmPending = false
        countdownStarted = false
        timelineExpanded = false
        forcedWorkdayDate = nil
        activeCountdownEndAtMs = nil
        draftStartMinutes = nil
        draftEndMinutes = nil
        clearOvertime()
        clearEarlyClockInRecord()
        clearEarlyClockOffRecord()
        if recordObservation {
            writeObservation(.countdownStopped, at: date, eventID: UUID())
        }
        clearSessionTimeZone()
    }

    /// Scheduled countdowns stay armed across calendar days. The concrete
    /// boundary still scopes one-off state such as overtime and a forced rest-
    /// day run to the shift that created it. Manual (`scheduleMode == .off`)
    /// countdowns retain their one-session behavior and reset after the end day.
    @discardableResult
    func reconcileCountdownSession(at date: Date = .now) -> Bool {
        var changed = false
        carryIncompleteFocusTasks(at: date)
        reconcileOpenFocusSessions(at: date)
        if !finishElapsedFocusSession(at: date), let session = activeFocusSession() {
            scheduleFocusExpiry(for: session)
        }
        expireSessionTimeZone(at: date)
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
                    stopCountdown(at: date, recordObservation: false)
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
                stopCountdown(at: date, recordObservation: false)
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

        stopCountdown(at: date, recordObservation: false)
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
        clearSessionTimeZone()
    }

    /// First visit to the onboarding reminders page. Lunch on with edge
    /// notifications, clock-off in simple mode. Later visits — including
    /// back — keep whatever the user already chose.
    func applyOnboardingReminderDefaultsIfNeeded() {
        guard !didApplyOnboardingReminderDefaults else { return }
        didApplyOnboardingReminderDefaults = true
        lunchEnabled = true
        lunchStartReminderEnabled = true
        lunchEndReminderEnabled = true
        if notificationMode == .off {
            notificationMode = .simple
        }
    }

    func completeOnboarding(enableNotifications: Bool) {
        onboardingComplete = true
        // Deliberately does NOT reset onboardingPage. The welcome view is still
        // on screen for the length of the cross-fade, and resetting the page
        // snapped it back to the first slide mid-transition. `onboardingPage` is
        // not persisted, so a replay starts at 0 on its own.
        if enableNotifications { notificationMode = .simple }
        // Starting the countdown here blocked the welcome → Plus intro
        // transition on a JavaScriptCore snapshot and an archive write.
        // `finishOnboardingLaunch()` runs after that first frame commits.
    }

    /// Arms the schedule and records first-seen after onboarding's next frame.
    func finishOnboardingLaunch(at date: Date = .now) {
        if scheduleMode != .off, !countdownStarted {
            startCountdown(at: date)
        }
        if selectedTab == .timer {
            noteTimerSurfaceVisible(at: date)
        }
    }

    func toggleWorkday(_ day: Int) {
        if workdays.contains(day) {
            guard workdays.count > 1 else { return }
            workdays.remove(day)
        } else {
            workdays.insert(day)
        }
    }

    var nativeSchedule: NativeWorkSchedule { nativeSchedule(at: .now) }

    func nativeSchedule(at date: Date, using source: RulesScheduleSource = .effective) -> NativeWorkSchedule {
#if DEBUG
        if let scenario = debugTimerSession?.scenario {
            return .init(
                mode: scenario.scheduleMode.rawValue,
                referenceWeekStartMs: nil,
                referenceWeekType: nil,
                singleWeekendWorkday: nil,
                rotationAnchorMs: nil,
                rotationWorkDays: nil,
                rotationRestDays: nil
            )
        }
#endif
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

    func anchorAlternatingWeekToToday(at date: Date = .now) {
        alternatingReferenceWeekStartMs = Self.startOfWeek(containing: date, timeZone: recordsTimeZone).timeIntervalSince1970 * 1_000
    }

    func anchorRotationToToday(at date: Date = .now) {
        rotationAnchorMs = recordsCalendar.startOfDay(for: date).timeIntervalSince1970 * 1_000
    }

    var rotationCycleLength: Int {
        max(2, rotationWorkDays + rotationRestDays)
    }

    /// Returns today's one-based position in the existing shared rotation
    /// schedule. Choosing another position only moves the schedule anchor; the
    /// TypeScript rules remain responsible for deciding work and rest days.
    var rotationCycleDay: Int {
        let calendar = recordsCalendar
        let anchor = calendar.startOfDay(for: Date(timeIntervalSince1970: rotationAnchorMs / 1_000))
        let today = calendar.startOfDay(for: .now)
        let offset = calendar.dateComponents([.day], from: anchor, to: today).day ?? 0
        return ((offset % rotationCycleLength) + rotationCycleLength) % rotationCycleLength + 1
    }

    func setRotationCycleDay(_ day: Int, at date: Date = .now) {
        let normalizedDay = min(rotationCycleLength, max(1, day))
        let today = recordsCalendar.startOfDay(for: date)
        let anchor = recordsCalendar.date(byAdding: .day, value: -(normalizedDay - 1), to: today) ?? today
        rotationAnchorMs = anchor.timeIntervalSince1970 * 1_000
    }

    func toggleQuickTheme() {
        switch theme {
        case .auto: theme = .light
        case .light: theme = .dark
        case .dark: theme = .auto
        }
    }

    func applyOvertime(date: Date, declaredAt: Date = .now) {
        let revokedCompletionAtMs = earlyOffAtMs ?? activeCountdownEndAtMs
        overtimeEndAtMs = date.timeIntervalSince1970 * 1_000
        countdownStarted = true
        activeCountdownEndAtMs = overtimeEndAtMs
        if sessionTimeZoneIdentifier != nil {
            sessionTimeZoneUntilMs = overtimeEndAtMs
        }
        // Overtime after an early clock-off is "I wasn't done".
        clearEarlyClockOffRecord()
        revokeCountdownCompletion(endAtMs: revokedCompletionAtMs)
        // Declaring overtime creates a new completion boundary. If the normal
        // clock-off already celebrated during this warm session, let the new
        // boundary celebrate as well — including a retrospective declaration
        // whose end is the current device time.
        lastCelebratedEndAtMs = 0
        writeObservation(.overtimeDeclared, at: declaredAt, eventID: UUID())
    }

    func applyScheduleChange(
        _ change: ScheduleFieldChange,
        decision: ScheduleChangeDecision,
        at date: Date = .now
    ) {
        // Applying a change to today removes timer-only adjustments. Capture
        // their projection before mutating the schedule so a matching durable
        // override can be removed as well. Otherwise that old custom row keeps
        // winning over the new schedule snapshot in Records indefinitely.
        let replacedTimerProjection = decision == .applyToToday
            ? projectedDayOverride(at: date)
            : nil

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
            if scheduleMode == .alternating { anchorAlternatingWeekToToday(at: date) }
            if scheduleMode == .rotation { anchorRotationToToday(at: date) }
        }
        if let lunchEnabled = change.lunchEnabled { self.lunchEnabled = lunchEnabled }
        if let lunchStartMinutes = change.lunchStartMinutes { self.lunchStartMinutes = lunchStartMinutes }
        if let lunchDurationMinutes = change.lunchDurationMinutes {
            self.lunchDurationMinutes = lunchDurationMinutes
        }
        if let alternatingWeekType = change.alternatingWeekType {
            self.alternatingWeekType = alternatingWeekType
            anchorAlternatingWeekToToday(at: date)
        }
        if let alternatingWeekendWorkday = change.alternatingWeekendWorkday {
            self.alternatingWeekendWorkday = alternatingWeekendWorkday
        }
        if let rotationWorkDays = change.rotationWorkDays { self.rotationWorkDays = rotationWorkDays }
        if let rotationRestDays = change.rotationRestDays { self.rotationRestDays = rotationRestDays }
        if let rotationCycleDay = change.rotationCycleDay {
            setRotationCycleDay(rotationCycleDay, at: date)
        }

        if decision == .applyToToday {
            todayOverride = nil
            clearTodayAdjustments()
            // Hours and lunch must not cancel rest-day manual timing. Once
            // today is a scheduled workday the forced mark is redundant.
            if snapshot(at: date)?.isWorkday == true {
                forcedWorkdayDate = nil
            }
            if self.scheduleMode == .off {
                stopUnscheduledSession(at: date)
            } else if onboardingComplete {
                countdownStarted = true
                recordActiveCountdownBoundary(at: date)
            }
        } else if onboardingComplete, effectiveScheduleMode(at: date) != .off {
            countdownStarted = true
        }

        let effectiveFrom: Date
        if decision == .applyToToday {
            effectiveFrom = recordsCalendar.startOfDay(for: date)
        } else if let next = recordsCalendar.date(byAdding: .day, value: 1, to: recordsCalendar.startOfDay(for: date)) {
            effectiveFrom = next
        } else {
            effectiveFrom = date
        }
        records.commitHours(
            hoursConfiguration(at: date),
            effectiveFrom: effectiveFrom,
            at: date,
            timeZone: recordsTimeZone
        )
        if decision == .applyToToday {
            replaceProjectedDayOverride(replacing: replacedTimerProjection, at: date)
        }
    }

    private func clearTodayAdjustments() {
        clearEarlyClockOffRecord()
        clearEarlyClockInRecord()
        clearOvertime()
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
        let calendar = recordsCalendar
        if let shift = snapshot(at: date) {
            let inShiftContext = shift.isWorkday
                || isForcedWorkday(shift)
                || isEndedEarly(shift)
                || (countdownStarted && scheduleMode == .off)
            if inShiftContext {
                let endDay = calendar.startOfDay(for: shift.endDate)
                return calendar.date(byAdding: .day, value: 1, to: endDay)
                    .map { $0.timeIntervalSince1970 * 1_000 }
            }
        }
        // Rest days and unscheduled idle still need a seam, otherwise
        // "from the next shift only" cannot keep today as it is.
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: today)
            .map { $0.timeIntervalSince1970 * 1_000 }
    }

    func usesTodayOverride(at date: Date) -> Bool {
        guard let todayOverride else { return false }
        return date.timeIntervalSince1970 * 1_000 < todayOverride.untilMs
    }

    /// Future projections must not inherit today's early clock-in or overlay.
    func projectsFutureFromBase(at date: Date) -> Bool {
#if DEBUG
        if debugTimerSession != nil { return false }
#endif
        return usesTodayOverride(at: date) || isStartedEarly(at: date)
    }

    var forcedWorkdayStartMs: Double? {
        guard let forcedWorkdayDate else { return nil }
        let parts = forcedWorkdayDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = countdownTimeZone
        return calendar.date(from: components)
            .map { calendar.startOfDay(for: $0).timeIntervalSince1970 * 1_000 }
    }

    func effectiveScheduleMode(at date: Date = .now) -> WorkScheduleMode {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.scheduleMode }
#endif
        guard usesTodayOverride(at: date),
              let raw = todayOverride?.scheduleMode,
              let mode = WorkScheduleMode(rawValue: raw)
        else { return scheduleMode }
        return mode
    }

    func effectiveStartMinutes(at date: Date) -> Int {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.startMinutes }
#endif
        if isStartedEarly(at: date), let earlyStartAtMs {
            return minutes(from: Date(timeIntervalSince1970: earlyStartAtMs / 1_000))
        }
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.startMinutes
        }
        return startMinutes
    }

    func effectiveEndMinutes(at date: Date) -> Int {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.endMinutes }
#endif
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.endMinutes
        }
        return endMinutes
    }

    func effectiveWorkdays(at date: Date) -> Set<Int> {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.workdays }
#endif
        if usesTodayOverride(at: date), let todayOverride {
            return Set(todayOverride.workdays)
        }
        return workdays
    }

    func effectiveLunchEnabled(at date: Date) -> Bool {
#if DEBUG
        if debugTimerSession != nil { return true }
#endif
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.lunchEnabled
        }
        return lunchEnabled
    }

    func effectiveLunchStartMinutes(at date: Date) -> Int {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.lunchStartMinutes }
#endif
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.lunchStartMinutes
        }
        return lunchStartMinutes
    }

    func effectiveLunchDurationMinutes(at date: Date) -> Int {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.lunchDurationMinutes }
#endif
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

    /// Elapsed progress toward the next clock-in, supplied by the generated
    /// rules bundle so every iOS timer surface uses the same stable anchor.
    func countdownToClockInProgress(snapshot: NativeShiftSnapshot) -> Double {
        min(100, max(0, snapshot.countdownProgress))
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
        case .clockIn:
            return t("shareUntilStartText", values: [
                "time": formatRelativeDuration(countdownToClockInMs(snapshot: shift, at: date)),
            ])
        case .overtime, .running:
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
            return countdownToClockInProgress(snapshot: shift)
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

    /// A calendar date in the app's language and the device's own zone — for
    /// things that belong to the device rather than to the records archive,
    /// such as when a subscription renews.
    func formatDate(_ date: Date) -> String {
        RecordsDateFormatters.shared
            .formatter(template: "yMMMd", locale: locale, timeZone: .current)
            .string(from: date)
    }

    // MARK: - Records dates
    //
    // `Date.formatted()` reads `Locale.autoupdatingCurrent` and
    // `TimeZone.current`. Neither is right here: the language is a user choice
    // the root view injects into the SwiftUI environment, and these strings are
    // built before SwiftUI sees them — a German UI on a Chinese device printed
    // Chinese weekdays. Records also keep their own civil zone, which the
    // travelling device zone must not shift a date across midnight. Every
    // records surface formats through these.

    /// "Wed, 26 Aug" — a day's identity in a list.
    func formatRecordsDayTitle(_ date: Date) -> String {
        recordsDateString(date, template: "EEEMMMd")
    }

    /// "26 Aug" — a day heading, where the weekday is already implied.
    func formatRecordsMonthDay(_ date: Date) -> String {
        recordsDateString(date, template: "MMMd")
    }

    /// "M" — one column of a month or week grid.
    func formatRecordsWeekdayNarrow(_ date: Date) -> String {
        recordsDateString(date, template: "EEEEE")
    }

    /// "August 2026" — a chart's window.
    func formatRecordsMonthYear(_ date: Date) -> String {
        recordsDateString(date, template: "MMMMy")
    }

    /// "August" — a compact month control where the year is already visible.
    func formatRecordsMonth(_ date: Date) -> String {
        recordsDateString(date, template: "MMMM")
    }

    /// The expanded year lists all twelve months in one narrow column beside a
    /// bar. "Dezember" and "листопада" do not fit there at full length.
    func formatRecordsMonthShort(_ date: Date) -> String {
        recordsDateString(date, template: "MMM")
    }

    /// A clock time as read in the records zone, not the device's.
    func formatRecordsTime(_ date: Date) -> String {
        recordsDateString(date, template: "jm")
    }

    /// Narrow weekday initials in the order the grid columns run.
    func recordsWeekdayGridSymbols() -> [String] {
        let calendar = recordsGridCalendar
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { offset in
            symbols[(calendar.firstWeekday - 1 + offset) % 7]
        }
    }

    /// How many blank cells a month grid needs before its first day, so the
    /// dates land in the right columns.
    func recordsGridLeadingBlanks(before date: Date) -> Int {
        let calendar = recordsGridCalendar
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// Records time zone for the dates, app language for where the week starts.
    /// A German reader expects a month grid that begins on Monday, and
    /// `Calendar(identifier:)` alone always starts on Sunday.
    var recordsGridCalendar: Calendar {
        civilCalendars.gridCalendar(timeZoneIdentifier: recordsTimeZoneIdentifier, localeIdentifier: languageCode)
    }

    fileprivate static func firstWeekdayIndex(of locale: Locale) -> Int {
        switch locale.firstDayOfWeek {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        @unknown default: 1
        }
    }

    private func recordsDateString(_ date: Date, template: String) -> String {
        RecordsDateFormatters.shared
            .formatter(template: template, locale: locale, timeZone: recordsTimeZone)
            .string(from: date)
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

    /// A plain count. Interpolating an `Int` into a string skips the locale's
    /// digits and grouping separator entirely.
    func formatCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// A calendar year is a label, not a quantity: grouping separators turn
    /// 1992 into "1,992", which then wraps to two lines in the Life grid gutter.
    func formatYear(_ value: Int) -> String {
        value.formatted(.number.grouping(.never).locale(locale))
    }

    func formatMoney(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    /// The only way money should reach the screen.
    ///
    /// `hideEarnings` is one switch for the whole product, so every amount has
    /// to consult it. Spelling the mask out at each call site meant the next
    /// screen to show an amount simply forgot — which is how the Records tab
    /// shipped an income figure the eye toggle could not hide. Ask for the
    /// text here and the mask cannot be left out.
    func moneyText(_ value: Double?) -> String {
        hideEarnings ? "••••" : formatMoney(value)
    }

    func formatPercent(_ value: Double, fractionDigits: Int = 1) -> String {
        (value / 100).formatted(
            .percent.precision(.fractionLength(fractionDigits)).locale(locale)
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

    func persistProjectedDayOverride(at date: Date = .now) {
        guard let override = projectedDayOverride(at: date) else { return }
        records.upsertOverride(override, at: date)
    }

    /// Reconciles only the timer projection that existed before an explicit
    /// “change today too” decision. A Records-tab edit with different business
    /// content remains intact; it is not timer housekeeping.
    private func replaceProjectedDayOverride(
        replacing previous: DayOverride?,
        at date: Date
    ) {
        if let override = projectedDayOverride(at: date) {
            records.upsertOverride(override, at: date)
            return
        }
        guard let previous,
              let stored = records.state.overrides.first(where: { $0.dayKey == previous.dayKey }),
              Self.hasSameDayOverrideContent(stored, previous)
        else { return }
        records.erase(.dayOverride, key: previous.dayKey, at: date)
    }

    private static func hasSameDayOverrideContent(_ lhs: DayOverride, _ rhs: DayOverride) -> Bool {
        lhs.dayKey == rhs.dayKey
            && lhs.shiftAnchorDate == rhs.shiftAnchorDate
            && lhs.kind == rhs.kind
            && lhs.segments == rhs.segments
            && lhs.note == rhs.note
            && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
    }

    func resolvedDay(dayKey: String) -> DayResolution? {
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else { return nil }
        return resolvedDays(from: date, through: date).first
    }

    func recordsWindow(for scale: RecordsScale, anchor: Date, now: Date = .now) -> (Date, Date) {
        let calendar = recordsGridCalendar
        let day = calendar.startOfDay(for: anchor)
        switch scale {
        case .week:
            let start = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
            ) ?? day
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? day
            return (start, end)
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? day
            return (start, end)
        case .year:
            let year = calendar.component(.year, from: day)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? day
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? day
            return (start, end)
        case .life:
            return (day, day)
        }
    }

    func shiftRecordsAnchor(_ anchor: Date, scale: RecordsScale, by offset: Int) -> Date {
        let calendar = recordsGridCalendar
        switch scale {
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: offset, to: anchor) ?? anchor
        case .month:
            return calendar.date(byAdding: .month, value: offset, to: anchor) ?? anchor
        case .year:
            return calendar.date(byAdding: .year, value: offset, to: anchor) ?? anchor
        case .life:
            return anchor
        }
    }

    /// Cached against the archive revision. Drawing a month asks this twice
    /// per cell — once for the day, once for the night before it — and
    /// rebuilding the whole index each time made a calendar cost hundreds of
    /// passes over every observation, override and exception on file.
    func isRecordedDay(_ dayKey: String) -> Bool {
        if let cached = recordedDayKeysCache, cached.revision == records.revision {
            return cached.keys.contains(dayKey)
        }
        let keys = Set(recordDayIndex().map(\.dayKey))
        recordedDayKeysCache = (records.revision, keys)
        return keys.contains(dayKey)
    }

    func recordsDayCell(
        for resolution: DayResolution,
        previous: DayResolution? = nil,
        now: Date = .now,
        includesLifeProjection: Bool = false
    ) -> RecordsDayCell {
        let today = recordsCalendar.startOfDay(for: now)
        let date = recordsCalendar.startOfDay(for: resolution.shiftAnchorDate)
        let authorized = plus.isAuthorized
        let revealed = RecordsAccess.canRevealDay(
            dayKey: resolution.dayKey,
            today: now,
            calendar: recordsCalendar,
            authorized: authorized
        )
        let future = date > today
        let recorded = isRecordedDay(resolution.dayKey)
        let corrected = records.state.overrides.contains {
            $0.dayKey == resolution.dayKey && $0.kind != .cleared
        }
        let projected = includesLifeProjection
            && !recorded
            && !corrected
            && isInsideLifeWorkProjection(date, now: now)
        let appearance: RecordsDayAppearance
        if !revealed {
            appearance = .locked
        } else if future && !recorded {
            appearance = resolution.isScheduledWorkday ? .planned : .rest
        } else if corrected {
            appearance = .corrected
        } else if recorded {
            appearance = .recorded
        } else if !resolution.isScheduledWorkday {
            appearance = .rest
        } else {
            appearance = .unrecorded
        }
        // A 22:00–06:00 shift is two hours of its anchor day and six of the
        // next one. Reading only this day's own resolution dropped the morning
        // half from the cell, the summary and every total above them.
        let contributors = contributingShifts(
            for: resolution,
            previous: previous,
            now: now,
            includesLifeProjection: includesLifeProjection
        )
        let share = revealed && !contributors.isEmpty
            ? dayAllocation(resolution, contributedBy: contributors, now: now)
            : TimeAllocationShare(workMs: 0, overtimeMs: 0, sleepMs: 0, freeMs: 0, dayLengthMs: 0)
        return RecordsDayCell(
            dayKey: resolution.dayKey,
            date: date,
            appearance: appearance,
            workMs: share.workMs,
            overtimeMs: share.overtimeMs,
            breakMs: share.breakMs,
            freeMs: share.freeMs,
            observationCount: (observationIndex()[resolution.dayKey] ?? []).count,
            isToday: recordsCalendar.isDate(date, inSameDayAs: today),
            isFuture: future,
            isProjection: projected,
            hasConflict: records.state.sync.conflicts.contains {
                Self.civilDayKey(fromExceptionKey: $0.logicalKey) == resolution.dayKey
            }
        )
    }

    func recordsHeadline(
        cells: [RecordsDayCell],
        days: [DayResolution],
        now: Date = .now
    ) -> RecordsHeadlineSummary? {
        guard plus.isAuthorized else { return nil }
        let recordedKeys = Set(cells.filter { $0.appearance == .recorded || $0.appearance == .corrected }.map(\.dayKey))
        guard !recordedKeys.isEmpty else { return nil }
        // Only recorded and corrected days contribute hours — a schedule-only
        // estimate is still not a fact. A day that merely *receives* those
        // hours after midnight is counted for its time, never as a workday.
        // `days` may reach one day either side of the window so an overnight
        // shift at the edge can still be found; the totals stay on `cells`.
        let byKey = Dictionary(days.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
        let counted = Set(
            days
                .filter { contributesHours($0, now: now, includesLifeProjection: false) }
                .map(\.dayKey)
        )
        let shares = cells.compactMap { cell -> TimeAllocationShare? in
            guard let day = byKey[cell.dayKey] else { return nil }
            let contributors = [previousDay(before: day, in: byKey), day]
                .compactMap { $0 }
                .filter { counted.contains($0.dayKey) }
            guard !contributors.isEmpty else { return nil }
            return dayAllocation(day, contributedBy: contributors, now: now)
        }
        let combined = TimeAllocationCalculator.combining(shares)
        let today = recordsCalendar.startOfDay(for: now)
        let completedScheduledWorkdays = days.filter { day in
            guard day.baseScheduleIsWorkday else { return false }
            let date = RecordJSON.date(fromDayKey: day.dayKey, calendar: recordsCalendar)
                ?? day.shiftAnchorDate
            return recordsCalendar.startOfDay(for: date) < today
        }.count
        let sleepKey = records.state.lifeProfile?.sleepSource == .healthSuggested
            ? "recordsSleepFromHealth"
            : "recordsSleepEstimated"
        return RecordsHeadlineSummary(
            workdays: recordedKeys.count,
            regularWorkMs: combined.workMs,
            overtimeMs: combined.overtimeMs,
            wakingFreeMs: combined.wakingFreeMs,
            estimatedIncome: recordsIncome(
                completedWorkdays: completedScheduledWorkdays,
                at: now
            ),
            allocation: combined,
            sleepSourceKey: sleepKey
        )
    }

    /// One civil day's numbers, cut from the shifts allowed to contribute to
    /// it. Both the month cell and the day canvas read this, so a day cannot
    /// print one total in the calendar and a different one on its own page.
    func dayAllocation(
        _ resolution: DayResolution,
        contributedBy shifts: [DayResolution],
        now: Date = .now
    ) -> TimeAllocationShare {
        dayCanvasModel(
            for: resolution,
            contributedBy: shifts,
            source: .scheduleEstimate,
            now: now
        ).allocation
    }

    func dayAllocation(
        _ resolution: DayResolution,
        previous: DayResolution? = nil,
        now: Date = .now
    ) -> TimeAllocationShare {
        dayAllocation(
            resolution,
            contributedBy: [previous, resolution].compactMap { $0 },
            now: now
        )
    }

    /// Whether a day's own hours may be shown as something that happened. A
    /// schedule expansion on its own is not a record; a life projection is
    /// shown, but always labelled as one.
    private func contributesHours(
        _ resolution: DayResolution,
        now: Date,
        includesLifeProjection: Bool
    ) -> Bool {
        if isRecordedDay(resolution.dayKey) { return true }
        if records.state.overrides.contains(where: {
            $0.dayKey == resolution.dayKey && $0.kind != .cleared
        }) { return true }
        guard includesLifeProjection else { return false }
        return isInsideLifeWorkProjection(
            recordsCalendar.startOfDay(for: resolution.shiftAnchorDate),
            now: now
        )
    }

    /// The shifts allowed to put hours on a civil day: the day itself and the
    /// night before, each only if its own record, correction or life projection
    /// lets it count. Every surface that prints a per-day number reads this, so
    /// the calendar cell, the compact summary and the day canvas cannot
    /// disagree — the cell used to filter and the other two did not, which put
    /// "not recorded, 0 h" in the grid above a solid eight-hour day.
    func contributingShifts(
        for resolution: DayResolution,
        previous: DayResolution?,
        now: Date = .now,
        includesLifeProjection: Bool
    ) -> [DayResolution] {
        [previous, resolution]
            .compactMap { $0 }
            .filter { contributesHours($0, now: now, includesLifeProjection: includesLifeProjection) }
    }

    private func previousDay(
        before day: DayResolution,
        in index: [String: DayResolution]
    ) -> DayResolution? {
        guard let date = RecordJSON.date(fromDayKey: day.dayKey, calendar: recordsCalendar),
              let earlier = recordsCalendar.date(byAdding: .day, value: -1, to: date)
        else { return nil }
        return index[RecordJSON.dayKey(earlier, calendar: recordsCalendar)]
    }

    /// The whole civil day, ready to draw. Views never intersect shifts, clip
    /// overtime, derive a lunch gap or decide what a source is.
    func dayCanvasModel(
        for resolution: DayResolution,
        contributedBy shifts: [DayResolution],
        source: RecordsDaySource,
        now: Date = .now,
        editableAnchors: Set<String> = []
    ) -> RecordsDayCanvasModel {
        let start = recordsCalendar.startOfDay(for: resolution.shiftAnchorDate)
        let next = recordsCalendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        let sleepKey = records.state.lifeProfile?.sleepSource == .healthSuggested
            ? "recordsSleepFromHealth"
            : "recordsSleepEstimated"
        var canvasShifts = shifts.map { shift in
            RecordsDayShift(
                anchorDayKey: shift.dayKey,
                segments: shift.segments,
                overtimeSegments: overtimeSegments(on: shift),
                source: shift.dayKey == resolution.dayKey
                    ? source
                    : shiftSource(of: shift, now: now),
                isEditable: editableAnchors.contains(shift.dayKey)
            )
        }
        // A past rest or unrecorded day has no contributing hours, but it is
        // still a real edit anchor. Keep that anchor without feeding its
        // scheduled estimate into the factual allocation.
        if editableAnchors.contains(resolution.dayKey),
           !canvasShifts.contains(where: { $0.anchorDayKey == resolution.dayKey }) {
            canvasShifts.append(
                RecordsDayShift(
                    anchorDayKey: resolution.dayKey,
                    segments: [],
                    source: source,
                    isEditable: true
                )
            )
        }
        return RecordsDayCanvasModel.build(
            RecordsDayCanvasModel.Input(
                dayKey: resolution.dayKey,
                dayStart: start,
                dayEnd: next,
                source: source,
                shifts: canvasShifts,
                sleepHours: records.state.lifeProfile?.averageSleepHours ?? 8,
                sleepSourceKey: sleepKey,
                isToday: recordsCalendar.isDate(start, inSameDayAs: now),
                now: now,
                // Any contributing shift, not just this day's. When last
                // night's expansion failed its overnight tail is missing, and
                // the hole it leaves here is unaccounted for rather than free.
                rulesFailed: resolution.expansionFailed
                    || shifts.contains(where: \.expansionFailed)
            )
        )
    }

    /// The source of a neighbouring shift reaching into the day on screen.
    private func shiftSource(of resolution: DayResolution, now: Date) -> RecordsDaySource {
        if records.state.overrides.contains(where: {
            $0.dayKey == resolution.dayKey && $0.kind != .cleared
        }) { return .corrected }
        if isRecordedDay(resolution.dayKey) {
            return resolution.layer == .calendarException ? .exception : .recorded
        }
        let date = recordsCalendar.startOfDay(for: resolution.shiftAnchorDate)
        if date > recordsCalendar.startOfDay(for: now) { return .planned }
        return isInsideLifeWorkProjection(date, now: now) ? .lifeProjection : .scheduleEstimate
    }

    private func overtimeSegments(on resolution: DayResolution) -> [NativeShiftSegment] {
        (observationIndex()[resolution.dayKey] ?? []).compactMap { item in
            RecordsMetrics.declaredOvertimeSegment(
                observation: item,
                day: resolution,
                avoidingRegularWork: true
            )
        }
    }

    func recordsDayDetail(
        for resolution: DayResolution,
        previous: DayResolution? = nil,
        now: Date = .now,
        includesLifeProjection: Bool = false
    ) -> RecordsDayDetail? {
        let cell = recordsDayCell(
            for: resolution,
            previous: previous,
            now: now,
            includesLifeProjection: includesLifeProjection
        )
        guard cell.appearance != .locked else { return nil }
        // The same qualified inputs the cell above it used, so the calendar and
        // the summary under it cannot print two different days.
        let canvas = dayCanvasModel(
            for: resolution,
            contributedBy: contributingShifts(
                for: resolution,
                previous: previous,
                now: now,
                includesLifeProjection: includesLifeProjection
            ),
            source: recordsDaySource(cell: cell, resolution: resolution),
            now: now
        )
        // The same words the day canvas uses. Two mappings meant the compact
        // summary could call a day one thing and its own page another.
        let sourceKey = canvas.source.titleKey
        let sleepKey = records.state.lifeProfile?.sleepSource == .healthSuggested
            ? "recordsSleepFromHealth"
            : "recordsSleepEstimated"
        let notes = observations(on: resolution.shiftAnchorDate).map { item in
            let time = formatRecordsTime(item.occurredAt)
            let kind: String
            switch item.kind {
            case .timerSurfaceFirstSeen: kind = t("recordsObservedFirstSeen")
            case .countdownStarted: kind = t("recordsObservedStarted")
            case .countdownStopped: kind = t("recordsObservedStopped")
            case .overtimeDeclared: kind = t("recordsObservedOvertime")
            }
            return "\(time) · \(kind)"
        }
        return RecordsDayDetail(
            dayKey: resolution.dayKey,
            date: resolution.shiftAnchorDate,
            appearance: cell.appearance,
            sourceKey: sourceKey,
            regularWorkMs: canvas.allocation.workMs,
            overtimeMs: canvas.allocation.overtimeMs,
            breakMs: canvas.allocation.breakMs,
            sleepMs: canvas.allocation.sleepMs,
            freeMs: canvas.allocation.freeMs,
            sleepSourceKey: sleepKey,
            observations: notes,
            isPlanned: cell.appearance == .planned,
            isProjection: cell.isProjection
        )
    }

    /// The day canvas for one civil day, including the part of the night
    /// before that runs into it. A locked day resolves to a model that carries
    /// no interval, duration, source or anchor at all — there is nothing to
    /// blur, because nothing real was ever built.
    func recordsDayCanvas(dayKey: String, now: Date = .now) async -> RecordsDayCanvasModel? {
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else {
            return nil
        }
        let start = recordsCalendar.startOfDay(for: date)
        let end = recordsCalendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        guard RecordsAccess.canRevealDay(
            dayKey: dayKey,
            today: now,
            calendar: recordsCalendar,
            authorized: plus.isAuthorized
        ) else {
            return .locked(dayKey: dayKey, dayStart: start, dayEnd: end)
        }
        let earlier = recordsCalendar.date(byAdding: .day, value: -1, to: start) ?? start
        let resolved = await prepareRecordsDisplayDays(from: earlier, through: start, now: now)
        guard let resolution = resolved.first(where: { $0.dayKey == dayKey }) else { return nil }
        let previous = resolved.last(where: { $0.dayKey != dayKey })
        let cell = recordsDayCell(
            for: resolution,
            previous: previous,
            now: now,
            includesLifeProjection: true
        )
        // Records edits a day that has already happened. A future day is
        // changed by moving the schedule or by running the timer, not by
        // writing history forward — and a day the life profile merely projects
        // has no original input to open, so it gets no editor either.
        let today = recordsCalendar.startOfDay(for: now)
        let editableAnchors: Set<String> = plus.isAuthorized
            ? Set(
                resolved
                    .filter { candidate in
                        let anchor = recordsCalendar.startOfDay(for: candidate.shiftAnchorDate)
                        guard anchor <= today else { return false }
                        if contributesHours(candidate, now: now, includesLifeProjection: false) {
                            return true
                        }
                        return !isInsideLifeWorkProjection(anchor, now: now)
                    }
                    .map(\.dayKey)
            )
            : []
        return dayCanvasModel(
            for: resolution,
            contributedBy: contributingShifts(
                for: resolution,
                previous: previous,
                now: now,
                includesLifeProjection: true
            ),
            source: recordsDaySource(cell: cell, resolution: resolution),
            now: now,
            editableAnchors: editableAnchors
        )
    }

    /// One mapping from a day's appearance to the words that describe it, so
    /// the calendar cell, the compact summary and the day canvas cannot each
    /// invent their own vocabulary for the same day.
    func recordsDaySource(cell: RecordsDayCell, resolution: DayResolution) -> RecordsDaySource {
        if cell.appearance == .locked { return .locked }
        if cell.isProjection { return .lifeProjection }
        switch cell.appearance {
        case .planned: return .planned
        case .rest: return .rest
        case .unrecorded: return .unrecorded
        case .corrected: return .corrected
        case .locked: return .locked
        case .recorded:
            switch resolution.layer {
            case .override: return .corrected
            case .calendarException: return .exception
            case .schedule: return .recorded
            case .none: return .unrecorded
            }
        }
    }

    func focusScheduleSlots(at date: Date = .now) -> [FocusScheduleSlot] {
        var slots: [FocusScheduleSlot] = []
        if let current = snapshot(at: date) {
            for segment in current.segments where segment.endAtMs > date.timeIntervalSince1970 * 1_000 {
                slots.append(
                    FocusScheduleSlot(
                        start: Date(timeIntervalSince1970: max(segment.startAtMs, date.timeIntervalSince1970 * 1_000) / 1_000),
                        end: Date(timeIntervalSince1970: segment.endAtMs / 1_000),
                        shiftAnchor: recordsCalendar.startOfDay(for: current.startDate),
                        isCurrentShift: true
                    )
                )
            }
        }
        if let nextStart = snapshot(at: date)?.nextShiftStartDate {
            if let upcoming = snapshot(at: nextStart.addingTimeInterval(60)) {
                for segment in upcoming.segments {
                    slots.append(
                        FocusScheduleSlot(
                            start: Date(timeIntervalSince1970: segment.startAtMs / 1_000),
                            end: Date(timeIntervalSince1970: segment.endAtMs / 1_000),
                            shiftAnchor: recordsCalendar.startOfDay(for: upcoming.startDate),
                            isCurrentShift: false
                        )
                    )
                }
            }
        }
        return slots
    }

    func focusWorkBlocks(at date: Date = .now) -> [FocusWorkBlock] {
        guard let current = snapshot(at: date) else { return [] }
        return FocusPlanner.workBlocks(
            segments: current.segments,
            settings: focusTimerSettings,
            extraBoundaries: focusMicroBreakBoundaries(at: date)
        )
    }

    /// Absolute micro-break boundaries are generated by the shared JS rules
    /// bundle. Swift only consumes them as hard stops; it never recreates the
    /// interval or schedule policy.
    private func focusMicroBreakBoundaries(at date: Date) -> [Date] {
        (try? shiftReminders(at: date))?.compactMap { reminder in
            guard reminder.kind == "microBreak", reminder.atMs > date.timeIntervalSince1970 * 1_000 else { return nil }
            return Date(timeIntervalSince1970: reminder.atMs / 1_000)
        } ?? []
    }

    @discardableResult
    func updateFocusTimerSettings(_ settings: FocusTimerSettings) -> Bool {
        // Template slots are indexed against the current focus/break cycle.
        // Rejecting a cadence change is safer than silently mapping a saved
        // task slot onto a recovery block.
        guard focusPlanning.templates.isEmpty else { return false }
        let normalized = settings.normalized
        guard normalized != focusTimerSettings else { return true }
        focusTimerSettings = normalized
        persistFocusConfiguration()
        return true
    }

    func focusAssignment(for block: FocusWorkBlock, at date: Date = .now) -> FocusPlanAssignment? {
        guard let current = snapshot(at: date) else { return nil }
        if block.kind == .breakTime {
            return FocusPlanAssignment(
                blockStartAtMs: block.startAtMs,
                kind: .breakTime,
                taskID: nil,
                taskTitle: nil,
                taskIcon: nil
            )
        }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        return focusPlanning.plans[key]?.assignments.first { $0.blockStartAtMs == block.startAtMs }
    }

    func assignFocusBlock(_ block: FocusWorkBlock, to task: FocusTask, at date: Date = .now) {
        guard block.kind == .task, plus.isAuthorized, task.deletedAt == nil,
              let current = snapshot(at: date)
        else { return }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        let replacedTaskID = focusPlanning.plans[key]?.assignments
            .first(where: { $0.blockStartAtMs == block.startAtMs })?.taskID
        let assignment = FocusPlanAssignment(
            blockStartAtMs: block.startAtMs,
            kind: .task,
            taskID: task.id,
            taskTitle: task.title,
            taskIcon: task.icon
        )
        updateFocusPlan(assignment, dayKey: key, shiftStartAtMs: Int64(current.startAtMs))
        var next = task
        next.scheduledStartAt = earliestFocusAssignment(for: task.id)
        if next.templateID != nil { next.estimatedPomodoros = templateTaskEstimate(for: task.id) }
        records.upsertFocusTask(next)
        if let replacedTaskID, replacedTaskID != task.id {
            releaseTemplateTasks([replacedTaskID], at: date)
        }
    }

    func assignFocusBreak(_ block: FocusWorkBlock, at date: Date = .now) {
        guard block.kind == .task, plus.isAuthorized, let current = snapshot(at: date) else { return }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        let replacedTaskID = focusPlanning.plans[key]?.assignments
            .first(where: { $0.blockStartAtMs == block.startAtMs })?.taskID
        updateFocusPlan(
            FocusPlanAssignment(
                blockStartAtMs: block.startAtMs,
                kind: .breakTime,
                taskID: nil,
                taskTitle: nil,
                taskIcon: nil
            ),
            dayKey: key,
            shiftStartAtMs: Int64(current.startAtMs)
        )
        if let replacedTaskID {
            releaseTemplateTasks([replacedTaskID], at: date)
        }
    }

    func clearFocusBlock(_ block: FocusWorkBlock, at date: Date = .now) {
        guard let current = snapshot(at: date) else { return }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        let removedTaskID = focusPlanning.plans[key]?.assignments
            .first(where: { $0.blockStartAtMs == block.startAtMs })?.taskID
        focusPlanning.plans[key]?.assignments.removeAll { $0.blockStartAtMs == block.startAtMs }
        // Clearing even one slot means this is no longer an untouched copy of
        // the template.  Keeping the old marker made a later Apply appear to
        // succeed while silently leaving the cleared slot empty.
        focusPlanning.plans[key]?.appliedTemplateID = nil
        focusPlanning.autoAppliedDayKeys.insert(key)
        if let removedTaskID { releaseTemplateTasks([removedTaskID], at: date) }
        persistFocusPlanning()
    }

    @discardableResult
    func saveFocusTemplate(name: String, at date: Date = .now) -> FocusTemplate? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plus.isAuthorized, !trimmed.isEmpty,
              let current = snapshot(at: date)
        else { return nil }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        let assignments = focusPlanning.plans[key]?.assignments ?? []
        let blocks = focusWorkBlocks(at: date)
        var taskKeys: [UUID: UUID] = [:]
        let slots = blocks.compactMap { block -> FocusTemplateSlot? in
            let assignment = assignments.first(where: { $0.blockStartAtMs == block.startAtMs })
                ?? (block.kind == .breakTime
                    ? FocusPlanAssignment(blockStartAtMs: block.startAtMs, kind: .breakTime, taskID: nil, taskTitle: nil, taskIcon: nil)
                    : nil)
            guard let assignment, assignment.kind == block.kind else { return nil }
            let taskKey = assignment.taskID.map { taskID in
                if let existing = taskKeys[taskID] { return existing }
                let created = UUID()
                taskKeys[taskID] = created
                return created
            }
            return FocusTemplateSlot(
                blockIndex: block.index,
                kind: assignment.kind,
                taskKey: taskKey,
                taskTitle: assignment.taskTitle,
                taskIcon: assignment.taskIcon
            )
        }
        guard !slots.isEmpty else { return nil }
        let now = Date.now
        let template = FocusTemplate(id: UUID(), name: trimmed, slots: slots, createdAt: now, updatedAt: now)
        focusPlanning.templates.append(template)
        persistFocusPlanning()
        return template
    }

    @discardableResult
    func applyFocusTemplate(_ template: FocusTemplate, at date: Date = .now) -> Bool {
        guard plus.isAuthorized, let current = snapshot(at: date) else { return false }
        let blocks = focusWorkBlocks(at: date)
        guard !blocks.isEmpty else { return false }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        // The template identifier alone is insufficient: a user can clear or
        // replace a slot while the old plan still points at that template.  A
        // genuine repeat application is a no-op only when every rendered
        // assignment and its task provenance still matches the template.
        if focusTemplatePlanMatches(template, blocks: blocks, dayKey: key, anchor: current.startDate) {
            return true
        }
        let previousTaskIDs = Set(focusPlanning.plans[key]?.assignments.compactMap(\.taskID) ?? [])
        var materializedTasks: [String: FocusTask] = [:]
        var assignments: [FocusPlanAssignment] = []

        for slot in template.slots.sorted(by: { $0.blockIndex < $1.blockIndex }) {
            guard blocks.indices.contains(slot.blockIndex) else { continue }
            let block = blocks[slot.blockIndex]
            // A template is indexed against a specific phase timeline. Never
            // reinterpret a stale task slot as a break (or vice versa) after
            // the shared schedule produced a different shape.
            guard slot.kind == block.kind else { continue }
            if block.kind == .breakTime {
                assignments.append(FocusPlanAssignment(
                    blockStartAtMs: block.startAtMs,
                    kind: .breakTime,
                    taskID: nil,
                    taskTitle: nil,
                    taskIcon: nil
                ))
                continue
            }

            // Current templates persist a task key.  The slot-index fallback
            // keeps old key-less templates from collapsing multiple task slots
            // into one task during migration.
            let groupID = slot.taskKey?.uuidString ?? "legacy-slot-\(slot.blockIndex)"
            let task: FocusTask
            if let existing = materializedTasks[groupID] {
                task = existing
            } else {
                let matching = slot.taskKey.map { taskKey in
                    template.slots.count { $0.kind == .task && $0.taskKey == taskKey }
                } ?? 1
                if var reusable = reusableTemplateTask(
                    template,
                    slot: slot,
                    anchor: current.startDate,
                    block: block
                ) {
                    reusable.deletedAt = nil
                    reusable.plannedForDate = recordsCalendar.startOfDay(for: current.startDate)
                    reusable.scheduledStartAt = block.start
                    reusable.estimatedPomodoros = max(
                        1,
                        matching,
                        completedFocusBlocks(for: reusable)
                    )
                    records.upsertFocusTask(reusable)
                    materializedTasks[groupID] = reusable
                    task = reusable
                } else {
                    var created = addFocusTaskAuthorized(
                        title: slot.taskTitle ?? t("focusTitle"),
                        pomodoros: max(1, matching),
                        plannedFor: current.startDate,
                        scheduledStartAt: block.start,
                        icon: slot.taskIcon ?? .focus
                    )
                    created.templateID = template.id
                    created.templateTaskKey = slot.taskKey
                    records.upsertFocusTask(created)
                    materializedTasks[groupID] = created
                    task = created
                }
            }
            assignments.append(FocusPlanAssignment(
                blockStartAtMs: block.startAtMs,
                kind: .task,
                taskID: task.id,
                taskTitle: task.title,
                taskIcon: task.icon
            ))
        }
        focusPlanning.plans[key] = FocusDayPlan(
            dayKey: key,
            shiftStartAtMs: Int64(current.startAtMs),
            assignments: assignments.sorted { $0.blockStartAtMs < $1.blockStartAtMs },
            appliedTemplateID: template.id
        )
        focusPlanning.autoAppliedDayKeys.insert(key)
        let materializedTaskIDs = Set(assignments.compactMap(\.taskID))
        releaseTemplateTasks(
            previousTaskIDs,
            preserving: materializedTaskIDs,
            at: date
        )
        for taskID in previousTaskIDs.union(materializedTaskIDs) where records.state.focusTasks
            .first(where: { $0.id == taskID })?.deletedAt == nil {
            refreshFocusTaskSchedule(for: taskID)
        }
        persistFocusPlanning()
        return !assignments.isEmpty
    }

    func setDefaultFocusTemplate(_ template: FocusTemplate?) {
        focusPlanning.defaultTemplateID = template?.id
        persistFocusPlanning()
    }

    func deleteFocusTemplate(_ template: FocusTemplate) {
        focusPlanning.templates.removeAll { $0.id == template.id }
        if focusPlanning.defaultTemplateID == template.id { focusPlanning.defaultTemplateID = nil }
        persistFocusPlanning()
    }

    @discardableResult
    func applyDefaultFocusTemplateIfNeeded(at date: Date = .now) -> Bool {
        guard plus.isAuthorized,
              let current = snapshot(at: date)
        else { return false }
        let key = RecordJSON.dayKey(current.startDate, calendar: recordsCalendar)
        guard !focusPlanning.autoAppliedDayKeys.contains(key) else { return false }
        if focusPlanning.plans[key]?.assignments.isEmpty == false {
            focusPlanning.autoAppliedDayKeys.insert(key)
            persistFocusPlanning()
            return false
        }
        guard let id = focusPlanning.defaultTemplateID,
              let template = focusPlanning.templates.first(where: { $0.id == id })
        else { return false }
        return applyFocusTemplate(template, at: date)
    }

    /// Stored assignments, or a non-mutating projection of the default
    /// template for a future widget shift that the app has not opened yet.
    func focusPlanAssignments(
        for snapshot: NativeShiftSnapshot
    ) -> [(block: FocusWorkBlock, assignment: FocusPlanAssignment)] {
        let blocks = focusPlanningBlocks(for: snapshot)
        let key = RecordJSON.dayKey(snapshot.startDate, calendar: recordsCalendar)
        if let plan = focusPlanning.plans[key], !plan.assignments.isEmpty {
            return blocks.compactMap { block in
                if block.kind == .breakTime {
                    return (block, FocusPlanAssignment(blockStartAtMs: block.startAtMs, kind: .breakTime, taskID: nil, taskTitle: nil, taskIcon: nil))
                }
                return plan.assignments.first(where: { $0.blockStartAtMs == block.startAtMs }).map { (block, $0) }
            }
        }
        guard let id = focusPlanning.defaultTemplateID,
              let template = focusPlanning.templates.first(where: { $0.id == id })
        else { return [] }
        return template.slots.compactMap { slot in
            guard blocks.indices.contains(slot.blockIndex) else { return nil }
            let block = blocks[slot.blockIndex]
            guard slot.kind == block.kind else { return nil }
            return (block, FocusPlanAssignment(
                blockStartAtMs: block.startAtMs,
                kind: block.kind,
                taskID: nil,
                taskTitle: slot.taskTitle,
                taskIcon: slot.taskIcon
            ))
        }
    }

    func focusPlanningBlocks(for snapshot: NativeShiftSnapshot) -> [FocusWorkBlock] {
        FocusPlanner.workBlocks(
            segments: snapshot.segments,
            settings: focusTimerSettings,
            extraBoundaries: focusMicroBreakBoundaries(at: snapshot.startDate)
        )
    }

    /// Widget range expansion deliberately carries a salary-free snapshot.
    /// It still needs the same planner inputs and shared-rule boundaries as
    /// the foreground view, so keep the projection-specific conversion here.
    func focusPlanningBlocks(for snapshot: NativeWidgetShiftSnapshot) -> [FocusWorkBlock] {
        FocusPlanner.workBlocks(
            segments: snapshot.segments,
            settings: focusTimerSettings,
            extraBoundaries: focusMicroBreakBoundaries(
                at: Date(timeIntervalSince1970: snapshot.startAtMs / 1_000)
            )
        )
    }

    private func updateFocusPlan(
        _ assignment: FocusPlanAssignment,
        dayKey: String,
        shiftStartAtMs: Int64
    ) {
        var plan = focusPlanning.plans[dayKey] ?? FocusDayPlan(
            dayKey: dayKey,
            shiftStartAtMs: shiftStartAtMs,
            assignments: [],
            appliedTemplateID: nil
        )
        plan.assignments.removeAll { $0.blockStartAtMs == assignment.blockStartAtMs }
        plan.assignments.append(assignment)
        plan.assignments.sort { $0.blockStartAtMs < $1.blockStartAtMs }
        plan.appliedTemplateID = nil
        focusPlanning.plans[dayKey] = plan
        focusPlanning.autoAppliedDayKeys.insert(dayKey)
        persistFocusPlanning()
    }

    private func earliestFocusAssignment(for taskID: UUID) -> Date? {
        focusPlanning.plans.values
            .flatMap(\.assignments)
            .filter { $0.taskID == taskID }
            .map { Date(timeIntervalSince1970: Double($0.blockStartAtMs) / 1_000) }
            .min()
    }

    private func refreshFocusTaskSchedule(for taskID: UUID) {
        guard var task = records.state.focusTasks.first(where: { $0.id == taskID }) else { return }
        task.scheduledStartAt = earliestFocusAssignment(for: taskID)
        if task.templateID != nil {
            task.estimatedPomodoros = templateTaskEstimate(for: taskID)
        }
        records.upsertFocusTask(task)
    }

    /// A template task's estimate follows the live plan, but a restored
    /// history can already contain more completed rounds than that plan.
    /// Never make a completed task look unfinished by shrinking below either
    /// its durable completion count or one visible Pomodoro.
    private func templateTaskEstimate(for taskID: UUID) -> Int {
        max(
            1,
            records.state.focusSessions.count {
                $0.taskID == taskID && $0.kind == .focus && $0.endReason == .completed
            },
            focusPlanning.plans.values.flatMap(\.assignments).count { $0.taskID == taskID }
        )
    }

    private func focusTemplatePlanMatches(
        _ template: FocusTemplate,
        blocks: [FocusWorkBlock],
        dayKey: String,
        anchor: Date
    ) -> Bool {
        guard let plan = focusPlanning.plans[dayKey], plan.appliedTemplateID == template.id else {
            return false
        }
        let expected = template.slots.sorted(by: { $0.blockIndex < $1.blockIndex }).compactMap { slot -> (FocusTemplateSlot, FocusWorkBlock)? in
            guard blocks.indices.contains(slot.blockIndex) else { return nil }
            let block = blocks[slot.blockIndex]
            return slot.kind == block.kind ? (slot, block) : nil
        }
        guard !expected.isEmpty, plan.assignments.count == expected.count else { return false }

        for (slot, block) in expected {
            guard let assignment = plan.assignments.first(where: { $0.blockStartAtMs == block.startAtMs }),
                  assignment.kind == slot.kind
            else { return false }
            guard slot.kind == .task else {
                if assignment.taskID != nil { return false }
                continue
            }
            guard let taskID = assignment.taskID,
                  let task = records.state.focusTasks.first(where: { $0.id == taskID }),
                  task.deletedAt == nil,
                  task.templateID == template.id,
                  task.templateTaskKey == slot.taskKey,
                  let plannedForDate = task.plannedForDate,
                  recordsCalendar.isDate(plannedForDate, inSameDayAs: anchor)
            else { return false }
            guard assignment.taskTitle == task.title,
                  assignment.taskIcon == task.icon,
                  slot.taskTitle.map({ $0 == task.title }) ?? true,
                  slot.taskIcon.map({ $0 == task.icon }) ?? true
            else { return false }
        }
        return true
    }

    /// Finds the task materialized by this template for this specific shift.
    /// Reusing a soft-deleted row preserves its CloudKit identity and makes a
    /// clear followed by Apply reversible.  Templates applied on another day
    /// deliberately receive their own tasks.
    private func reusableTemplateTask(
        _ template: FocusTemplate,
        slot: FocusTemplateSlot,
        anchor: Date,
        block: FocusWorkBlock
    ) -> FocusTask? {
        records.state.focusTasks
            .filter { task in
                guard task.templateID == template.id,
                      task.completedAt == nil,
                      let plannedForDate = task.plannedForDate,
                      recordsCalendar.isDate(plannedForDate, inSameDayAs: anchor)
                else { return false }
                if let taskKey = slot.taskKey {
                    return task.templateTaskKey == taskKey
                }
                // Key-less v1 templates had one task per slot.  A soft-deleted
                // row retains its original scheduled slot so it can still be
                // recovered without conflating neighbouring legacy slots.
                return task.templateTaskKey == nil && task.scheduledStartAt == block.start
            }
            .sorted { lhs, rhs in
                if (lhs.deletedAt == nil) != (rhs.deletedAt == nil) { return lhs.deletedAt == nil }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    /// Turns a removed template assignment into either a reversible soft
    /// deletion or an ordinary user task.  Durable history, a favourite, or a
    /// remaining plan reference is evidence that the task has meaning beyond
    /// this template and must never disappear with it.
    private func releaseTemplateTasks(
        _ taskIDs: Set<UUID>,
        preserving preservedTaskIDs: Set<UUID> = [],
        at date: Date
    ) {
        for taskID in taskIDs where !preservedTaskIDs.contains(taskID) {
            guard var task = records.state.focusTasks.first(where: { $0.id == taskID }),
                  task.templateID != nil
            else { continue }
            let hasSessionHistory = records.state.focusSessions.contains { $0.taskID == taskID }
            let hasPlanReference = focusPlanning.plans.values.contains {
                $0.assignments.contains { $0.taskID == taskID }
            }
            if hasSessionHistory || task.isFavorite || hasPlanReference {
                task.templateID = nil
                task.templateTaskKey = nil
                task.scheduledStartAt = earliestFocusAssignment(for: taskID)
            } else if task.deletedAt == nil {
                // Keep the old slot on a tombstone.  It is invisible to the
                // user, while allowing a legacy key-less template to revive
                // the exact task if they immediately apply it again.
                task.deletedAt = date
            } else {
                continue
            }
            records.upsertFocusTask(task, at: date)
        }
    }

    private func persistFocusPlanning() {
        persistFocusConfiguration()
    }

    private func persistFocusConfiguration(at date: Date = .now) {
        let current = records.state.focusPlanningConfiguration
        records.upsertFocusPlanningConfiguration(
            FocusPlanningConfiguration(
                planning: focusPlanning,
                timerSettings: focusTimerSettings.normalized,
                editedAt: current?.editedAt ?? date,
                editCount: current?.editCount ?? 0,
                editTieBreaker: current?.editTieBreaker ?? UUID()
            ),
            at: date
        )
        mirrorFocusConfigurationToLegacyDefaults()
        focusPlanningRevision &+= 1
    }

    private func mirrorFocusConfigurationToLegacyDefaults() {
        if let planningData = try? JSONEncoder().encode(focusPlanning) {
            defaults.set(planningData, forKey: Key.focusPlanning)
        }
        if let settingsData = try? JSONEncoder().encode(focusTimerSettings.normalized) {
            defaults.set(settingsData, forKey: Key.focusTimerSettings)
        }
    }

    func addScheduledFocusTask(
        title: String,
        slot: FocusScheduleSlot,
        icon: FocusTaskIcon = .focus,
        isFavorite: Bool = false
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if plus.isAuthorized {
            _ = addFocusTaskAuthorized(
                title: trimmed,
                pomodoros: 1,
                plannedFor: slot.shiftAnchor,
                scheduledStartAt: slot.start,
                icon: icon,
                isFavorite: isFavorite
            )
        } else {
            openPaidOrRun(
                .focus,
                action: .addFocusTask(
                    title: trimmed,
                    pomodoros: 1,
                    icon: icon,
                    isFavorite: isFavorite
                )
            )
        }
    }

    func addAndStartFocusTask(
        title: String,
        icon: FocusTaskIcon = .focus,
        isFavorite: Bool = false
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        openPaidOrRun(
            .focus,
            action: .addAndStartFocus(
                title: trimmed,
                pomodoros: 1,
                icon: icon,
                isFavorite: isFavorite
            )
        )
    }

    func recordsMetrics(for days: [DayResolution]) -> RecordsPeriodMetrics {
        let sleep = records.state.lifeProfile?.averageSleepHours ?? 8
        let items = days.flatMap { observations(on: $0.shiftAnchorDate) }
        return RecordsMetrics.summarize(
            days: days,
            observations: items,
            sleepHours: sleep,
            calendar: recordsCalendar
        )
    }

    /// Records and the timer intentionally answer different questions. Records
    /// counts completed base-schedule workdays; the bundle applies the current
    /// salary while excluding today's partial shift and declared overtime.
    func recordsIncome(completedWorkdays: Int, at date: Date = .now) -> Double? {
        guard presentationSalaryEnabled else { return nil }
        do {
            let result = try CountdownRules.shared.recordsIncome(input: .init(
                completedWorkdays: completedWorkdays,
                rules: rulesInput(at: date)
            ))
            if lastRulesError != nil { lastRulesError = nil }
            return result.earnings
        } catch {
            lastRulesError = error.localizedDescription
            return nil
        }
    }

    /// Gates an action behind Plus, presenting the paywall over whatever the
    /// user is actually looking at.
    ///
    /// This used to append to `recordsPath`. Gating iCloud sync lives in the
    /// Settings stack, so the push landed on a stack that was not on screen and
    /// the tap did nothing visible at all.
    func openPaidOrRun(_ reason: PlusPaywallReason, action: PlusPendingAction) {
        if plus.isAuthorized {
            performPendingPlusAction(action)
        } else {
            pendingPlusAction = action
            paywallSheet = reason
        }
    }

    func resumePendingPlusActionIfAuthorized() {
        guard plus.isAuthorized, let action = pendingPlusAction else { return }
        pendingPlusAction = nil
        paywallSheet = nil
        performPendingPlusAction(action)
    }

    func performPendingPlusAction(_ action: PlusPendingAction) {
        switch action {
        case .historyEdit(let dayKey):
            editingDayKey = dayKey
        case .startFocus(let taskID):
            if let task = records.state.focusTasks.first(where: { $0.id == taskID }) {
                _ = startFocusAuthorized(task)
            }
        case .addFocusTask(let title, let pomodoros, let icon, let isFavorite):
            addFocusTaskAuthorized(
                title: title,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
        case .addAndStartFocus(let title, let pomodoros, let icon, let isFavorite):
            let task = addFocusTaskAuthorized(
                title: title,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
            _ = startFocusAuthorized(task)
        case .presentAddFocus:
            presentAddFocus = true
        case .openFocus:
            presentedRoute = .focus
        case .enableCycleEndSummaryNotifications:
            cycleEndSummaryNotificationEnabled = true
        case .enableSync:
            Task { await cloudSync.enable(authorized: plus.isAuthorized) }
        }
    }

    func openDayEditor(dayKey: String) {
        guard RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) != nil else { return }
        if !RecordsAccess.allows(.recordsPageEdit, authorized: plus.isAuthorized) {
            pendingPlusAction = .historyEdit(dayKey: dayKey)
            paywallSheet = .historyEdit
            return
        }
        editingDayKey = dayKey
    }

    func beginAddFocus() {
        if plus.isAuthorized {
            presentAddFocus = true
        } else {
            pendingPlusAction = .presentAddFocus
            paywallSheet = .focus
        }
    }

    func canMutateRecordedDay(_ dayKey: String) -> Bool {
        guard RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) != nil else { return false }
        if !RecordsAccess.allows(.recordsPageEdit, authorized: plus.isAuthorized) {
            pendingPlusAction = .historyEdit(dayKey: dayKey)
            paywallSheet = .historyEdit
            return false
        }
        return true
    }

    func applyDayWrite(
        _ write: DayRecordWrite,
        dayKey: String,
        startMinutes: Int = 9 * 60,
        endMinutes: Int = 18 * 60
    ) {
        guard canMutateRecordedDay(dayKey) else { return }
        switch DayRecordLayers.plan(for: write) {
        case .overrideOnly(let kind):
            switch kind {
            case .customSegments:
                saveCustomHours(dayKey: dayKey, startMinutes: startMinutes, endMinutes: endMinutes)
            case .confirmedAsScheduled:
                confirmDayAsScheduled(dayKey: dayKey)
            case .notWorking:
                markDayNotWorking(dayKey: dayKey)
            case .cleared:
                clearDayOverride(dayKey: dayKey)
            }
        case .exception(let overrideKind, let effect, let exceptionCleared):
            writeDayLayers(
                dayKey: dayKey,
                overrideKind: overrideKind,
                effect: effect,
                exceptionCleared: exceptionCleared
            )
        }
    }

    private func writeDayLayers(
        dayKey: String,
        overrideKind: DayOverrideKind,
        effect: CalendarEffect,
        exceptionCleared: Bool
    ) {
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else { return }
        let override = DayOverride(
            dayKey: dayKey,
            shiftAnchorDate: date,
            kind: overrideKind,
            segments: [],
            timeZoneIdentifier: recordsTimeZoneIdentifier
        )
        var exception: CalendarException?
        if exceptionCleared {
            if let existing = records.state.exceptions.first(where: { $0.matches(dateKey: dayKey) && $0.origin == .user }) {
                var next = existing
                next.isCleared = true
                exception = next
            }
        } else {
            exception = CalendarException(
                dayKey: CalendarException.dayKey(dateKey: dayKey, origin: .user),
                date: date,
                effect: effect,
                origin: .user,
                isCleared: false,
                regionIdentifier: nil,
                datasetVersion: nil,
                label: nil,
                editedAt: .now,
                editCount: 0,
                editTieBreaker: UUID(),
                timeZoneIdentifier: recordsTimeZoneIdentifier
            )
        }
        records.applyDayLayers(override: override, exception: exception)
    }

    func saveCustomHours(dayKey: String, startMinutes: Int, endMinutes: Int) {
        guard canMutateRecordedDay(dayKey) else { return }
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else { return }
        records.ensureSeeded(hours: hoursConfiguration(at: date), at: date, timeZone: recordsTimeZone)
        let period = DayRecordResolver.period(on: date, from: records.state.periods)
        let snapshot = period.flatMap {
            DayRecordResolver.snapshot(on: date, in: $0, from: records.state.snapshots)
        }
        var planned: [NativeShiftSegment] = []
        if let snapshot,
           let configuration = try? JSONDecoder().decode(
            ScheduleHoursConfiguration.self,
            from: snapshot.configurationData
           ),
           let days = try? CountdownRules.shared.expandScheduleRange(
            configuration: configuration,
            from: date,
            through: date,
            timeZone: period?.timeZone
           ) {
            planned = days.first?.segments ?? []
        }
        let start = recordsCalendar.date(
            bySettingHour: startMinutes / 60,
            minute: startMinutes % 60,
            second: 0,
            of: date
        ) ?? date
        var end = recordsCalendar.date(
            bySettingHour: endMinutes / 60,
            minute: endMinutes % 60,
            second: 0,
            of: date
        ) ?? date
        if end <= start {
            end = recordsCalendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        if planned.isEmpty {
            planned = [
                NativeShiftSegment(
                    startAtMs: start.timeIntervalSince1970 * 1_000,
                    endAtMs: end.timeIntervalSince1970 * 1_000
                )
            ]
        }
        records.upsertOverride(
            DayOverride(
                dayKey: dayKey,
                shiftAnchorDate: date,
                kind: .customSegments,
                segments: DayOverrideProjection.applyTimeBounds(
                    to: planned,
                    startAtMs: start.timeIntervalSince1970 * 1_000,
                    endAtMs: end.timeIntervalSince1970 * 1_000
                ),
                timeZoneIdentifier: recordsTimeZoneIdentifier
            )
        )
    }

    func confirmDayAsScheduled(dayKey: String) {
        guard canMutateRecordedDay(dayKey) else { return }
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else { return }
        records.upsertOverride(
            DayOverride(
                dayKey: dayKey,
                shiftAnchorDate: date,
                kind: .confirmedAsScheduled,
                segments: [],
                timeZoneIdentifier: recordsTimeZoneIdentifier
            )
        )
    }

    func markDayNotWorking(dayKey: String) {
        guard canMutateRecordedDay(dayKey) else { return }
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else { return }
        records.upsertOverride(
            DayOverride(
                dayKey: dayKey,
                shiftAnchorDate: date,
                kind: .notWorking,
                segments: [],
                timeZoneIdentifier: recordsTimeZoneIdentifier
            )
        )
    }

    func clearDayOverride(dayKey: String) {
        guard canMutateRecordedDay(dayKey) else { return }
        writeDayLayers(dayKey: dayKey, overrideKind: .cleared, effect: .rest, exceptionCleared: true)
    }

    func markCalendarException(dayKey: String, effect: CalendarEffect) {
        guard canMutateRecordedDay(dayKey) else { return }
        writeDayLayers(
            dayKey: dayKey,
            overrideKind: .cleared,
            effect: effect,
            exceptionCleared: false
        )
    }

    func saveLifeProfile(
        birthYear: Int?,
        workStartedYear: Int?,
        retirementAge: Int?,
        sleepHours: Double?,
        hidesExactAges: Bool
    ) {
        saveLifeProfileV2(
            bornOn: birthYear.map { .yearOnly($0) },
            schoolStartedOn: nil,
            workStartedOn: workStartedYear.flatMap { year in
                PartialCivilDate.exact(year: year, month: 7, day: 1) ?? .yearOnly(year)
            },
            retirementOn: {
                guard let birthYear, let retirementAge else { return nil }
                return .yearOnly(birthYear + retirementAge)
            }(),
            sleepHours: sleepHours
        )
    }

    func saveLifeProfileV2(
        bornOn: PartialCivilDate?,
        schoolStartedOn: PartialCivilDate?,
        workStartedOn: PartialCivilDate?,
        retirementOn: PartialCivilDate?,
        sleepHours: Double?
    ) {
        var profile = records.state.lifeProfile ?? LifeProfile(
            editedAt: .now,
            editCount: 0,
            editTieBreaker: UUID()
        )
        profile.bornOn = bornOn
        profile.schoolStartedOn = schoolStartedOn
        profile.workStartedPartial = workStartedOn
        profile.retirementOn = retirementOn
        profile.birthYear = bornOn?.year
        profile.workStartedOn = workStartedOn?.calculationAnchor(in: recordsCalendar)
        if let born = bornOn?.year, let retire = retirementOn?.year {
            profile.retirementAge = retire - born
        } else {
            profile.retirementAge = nil
        }
        profile.averageSleepHours = sleepHours
        if let sleepHours {
            profile.averageSleepMinutes = Int((sleepHours * 60).rounded())
            profile.sleepSource = .manual
            profile.sleepSourceUpdatedAt = .now
        }
        records.updateLifeProfile(profile)
    }

    /// One name for the current Plus state, so the settings row, the Plus page
    /// and the paywall cannot disagree.
    ///
    /// The settings row used to print "Plus" for every authorized state, so a
    /// lifetime purchase, a trial and a failed-payment grace period all read
    /// the same — including to someone about to lose access in three days.
    var plusStatusLabel: String {
        switch plus.authorization {
        case .authorized(.lifetime):
            return t("plusStatusLifetime")
        case .authorized(.subscribed):
            return t(plus.isInTrial ? "plusStatusTrial" : "plusStatusSubscribed")
        case .authorized(.inGracePeriod):
            return t("plusStatusGrace")
        case .pendingAskToBuy:
            return t("plusStatusPending")
        case .unauthorized, .unverified:
            return t("plusStatusNone")
        }
    }

    /// Whether the life grid may print years on screen.
    var hidesLifeAges: Bool {
        records.state.lifeProfile?.hidesExactAges ?? false
    }

    private func lifeWorkProjectionBounds(now: Date) -> (start: Date, end: Date)? {
        guard var profile = records.state.lifeProfile else { return nil }
        let calendar = recordsCalendar
        profile.migrateLegacyFields(calendar: calendar)
        guard let start = profile.workStartedPartial?.calculationAnchor(in: calendar)
            ?? profile.workStartedOn,
            let end = profile.retirementOn?.calculationAnchor(in: calendar),
            start < end
        else { return nil }
        return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
    }

    private func isInsideLifeWorkProjection(_ date: Date, now: Date) -> Bool {
        guard let bounds = lifeWorkProjectionBounds(now: now) else { return false }
        let day = recordsCalendar.startOfDay(for: date)
        return day >= bounds.start && day < bounds.end
    }

    func lifeViewModel(now: Date = .now) -> LifeViewModel? {
        guard var profile = records.state.lifeProfile else { return nil }
        let calendar = recordsCalendar
        profile.migrateLegacyFields(calendar: calendar)
        guard let lifeStart = profile.bornOn?.calculationAnchor(in: calendar),
              let lifeEnd = profile.retirementOn?.calculationAnchor(in: calendar),
              lifeEnd > lifeStart
        else { return nil }
        let configuredWorkStart = profile.workStartedPartial?.calculationAnchor(in: calendar)
            ?? profile.workStartedOn
            ?? calendar.date(byAdding: .year, value: 22, to: lifeStart)
            ?? now
        let workStart = max(lifeStart, configuredWorkStart)
        guard workStart < lifeEnd else {
            return LifeViewCalculator.build(
                profile: profile,
                scheduleDays: [],
                outsideZoneDays: Set(daysRecordedOutsidePeriodTimeZone()),
                now: now,
                calendar: calendar
            )
        }

        let archive = lifeScheduleArchive(workStart: workStart, now: now)
        let finalDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: lifeEnd))
            ?? lifeEnd
        let scheduleDays = resolveDays(
            from: workStart,
            through: finalDay,
            periods: archive.periods,
            snapshots: archive.snapshots,
            usesSharedCache: false
        ).compactMap { resolution in
            LifeScheduleDay(
                resolution: resolution,
                overtimeSegments: overtimeSegments(on: resolution)
            )
        }
        return LifeViewCalculator.build(
            profile: profile,
            scheduleDays: scheduleDays,
            outsideZoneDays: Set(daysRecordedOutsidePeriodTimeZone()),
            now: now,
            calendar: calendar
        )
    }

    /// Warms every shared-rule expansion needed by Life on the background
    /// ScheduleRangeEngine. The synchronous builder then only walks cached
    /// results and assembles week cells on the main actor.
    func prepareLifeViewModel(now: Date = .now) async -> LifeViewModel? {
        guard var profile = records.state.lifeProfile else { return nil }
        let calendar = recordsCalendar
        profile.migrateLegacyFields(calendar: calendar)
        guard let lifeStart = profile.bornOn?.calculationAnchor(in: calendar),
              let lifeEnd = profile.retirementOn?.calculationAnchor(in: calendar),
              lifeEnd > lifeStart
        else { return nil }
        let configuredWorkStart = profile.workStartedPartial?.calculationAnchor(in: calendar)
            ?? profile.workStartedOn
            ?? calendar.date(byAdding: .year, value: 22, to: lifeStart)
            ?? now
        let workStart = max(lifeStart, configuredWorkStart)
        guard workStart < lifeEnd else { return lifeViewModel(now: now) }
        let finalDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: lifeEnd))
            ?? lifeEnd
        let archive = lifeScheduleArchive(workStart: workStart, now: now)

        for snapshot in archive.snapshots {
            guard let period = archive.periods.first(where: { $0.id == snapshot.periodID }),
                  period.startsOn <= finalDay,
                  period.endsBefore.map({ $0 > workStart }) ?? true,
                  snapshot.effectiveFrom <= finalDay,
                  let configuration = try? JSONDecoder().decode(
                    ScheduleHoursConfiguration.self,
                    from: snapshot.configurationData
                  )
            else { continue }
            let periodCalendar = period.civilCalendar()
            try? await CountdownRules.shared.prefetchExpansion(
                configuration: configuration,
                from: periodCalendar.startOfDay(for: workStart),
                through: periodCalendar.startOfDay(for: finalDay),
                timeZone: period.timeZone
            )
        }
        return lifeViewModel(now: now)
    }

    private func lifeScheduleArchive(
        workStart: Date,
        now: Date
    ) -> (periods: [CareerPeriod], snapshots: [ScheduleSnapshot]) {
        var periods = records.state.periods
        var snapshots = records.state.snapshots
        addLifeScheduleIfArchiveIsEmpty(
            workStart: workStart,
            now: now,
            periods: &periods,
            snapshots: &snapshots
        )
        addLifeHistoryBackfillIfNeeded(
            workStart: workStart,
            now: now,
            periods: &periods,
            snapshots: &snapshots
        )
        return (periods, snapshots)
    }

    /// Life's minimum input includes the current schedule even when Records
    /// has never been opened. Keep that estimate in memory: merely viewing the
    /// life grid must not backdate the durable Records archive by decades.
    private func addLifeScheduleIfArchiveIsEmpty(
        workStart: Date,
        now: Date,
        periods: inout [CareerPeriod],
        snapshots: inout [ScheduleSnapshot]
    ) {
        guard periods.isEmpty,
              let encoded = try? ScheduleHoursCodec.encode(hoursConfiguration(at: now))
        else { return }
        let periodID = UUID()
        periods.append(
            CareerPeriod(
                id: periodID,
                startsOn: workStart,
                endsBefore: nil,
                label: nil,
                timeZoneIdentifier: recordsTimeZoneIdentifier,
                calendarIdentifier: "gregorian",
                createdAt: now,
                editedAt: now,
                editCount: 1,
                editTieBreaker: UUID()
            )
        )
        snapshots.append(
            ScheduleSnapshot(
                id: UUID(),
                periodID: periodID,
                effectiveFrom: workStart,
                configurationData: encoded.data,
                fingerprint: encoded.fingerprint,
                editedAt: now,
                editCount: 1,
                editTieBreaker: UUID()
            )
        )
    }

    /// The current open-ended schedule is the fallback for the otherwise
    /// unknown history between workStart and the first explicit career period.
    /// Gaps between real periods and time after an ended period stay uncovered.
    private func addLifeHistoryBackfillIfNeeded(
        workStart: Date,
        now: Date,
        periods: inout [CareerPeriod],
        snapshots: inout [ScheduleSnapshot]
    ) {
        guard let firstStart = periods.map(\.startsOn).min(), workStart < firstStart,
              let currentPeriod = DayRecordResolver.period(on: now, from: periods),
              currentPeriod.endsBefore == nil,
              let encoded = try? ScheduleHoursCodec.encode(hoursConfiguration(at: now))
        else { return }
        let backfillPeriodID = UUID()
        var backfillPeriod = currentPeriod
        backfillPeriod.id = backfillPeriodID
        backfillPeriod.startsOn = workStart
        backfillPeriod.endsBefore = firstStart
        let backfillSnapshot = ScheduleSnapshot(
            id: UUID(),
            periodID: backfillPeriodID,
            effectiveFrom: workStart,
            configurationData: encoded.data,
            fingerprint: encoded.fingerprint,
            editedAt: now,
            editCount: 1,
            editTieBreaker: UUID()
        )
        periods.append(backfillPeriod)
        snapshots.append(backfillSnapshot)
    }

    @discardableResult
    func restoreConflict(_ copy: SyncConflictCopy) -> Bool {
        records.restoreConflict(copy)
    }

    @discardableResult
    func keepCurrentConflict(_ copy: SyncConflictCopy) -> Bool {
        records.keepCurrentConflict(copy)
    }

    @discardableResult
    func resolveConflict(_ copy: SyncConflictCopy, fieldsFromAlternate: Set<String>) -> Bool {
        records.resolveConflict(copy, fieldsFromAlternate: fieldsFromAlternate)
    }

    /// External state is a lifecycle boundary, not just an archive refresh.
    /// Carry first so a yesterday task imported today remains findable; then
    /// converge open sessions before any system timer is republished.
    private func reconcileExternallyAppliedRecordState(at date: Date = .now) {
        let syncedPlanning = records.state.focusPlanningConfiguration?.planning ?? FocusPlanningState()
        let syncedSettings = records.state.focusPlanningConfiguration?.timerSettings.normalized ?? .default
        if syncedPlanning != focusPlanning || syncedSettings != focusTimerSettings.normalized {
            focusPlanning = syncedPlanning
            focusTimerSettings = syncedSettings
            mirrorFocusConfigurationToLegacyDefaults()
            focusPlanningRevision &+= 1
        }
        carryIncompleteFocusTasks(at: date)
        reconcileOpenFocusSessions(at: date)
        focusRuntimeRevision &+= 1
    }

    private func carryIncompleteFocusTasks(at date: Date) {
        let today = recordsCalendar.startOfDay(for: date)
        for task in records.state.focusTasks where task.completedAt == nil && task.deletedAt == nil {
            guard let planned = task.plannedForDate, planned < today else { continue }
            var next = task
            next.plannedForDate = today
            next.scheduledStartAt = nil
            records.upsertFocusTask(next)
        }
    }

    func addFocusTask(
        title: String,
        pomodoros: Int,
        icon: FocusTaskIcon = .focus,
        isFavorite: Bool = false
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        openPaidOrRun(
            .focus,
            action: .addFocusTask(
                title: trimmed,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
        )
    }

    @discardableResult
    private func addFocusTaskAuthorized(
        title: String,
        pomodoros: Int,
        plannedFor: Date? = nil,
        scheduledStartAt: Date? = nil,
        icon: FocusTaskIcon = .focus,
        isFavorite: Bool = false
    ) -> FocusTask {
        let nextIndex = (records.state.focusTasks.map(\.sortIndex).max() ?? -1) + 1
        let task = FocusTask(
            id: UUID(),
            createdAt: .now,
            plannedForDate: recordsCalendar.startOfDay(for: plannedFor ?? .now),
            scheduledStartAt: scheduledStartAt,
            title: title,
            estimatedPomodoros: max(1, pomodoros),
            icon: icon,
            isFavorite: isFavorite,
            completedAt: nil,
            sortIndex: nextIndex,
            editedAt: .now,
            editCount: 0,
            editTieBreaker: UUID()
        )
        records.upsertFocusTask(task)
        return task
    }

    func focusTasksForToday(at date: Date = .now) -> [FocusTask] {
        let today = recordsCalendar.startOfDay(for: date)
        return FocusTaskOrder.sorted(records.state.focusTasks.filter { task in
            guard task.deletedAt == nil else { return false }
            guard let planned = task.plannedForDate else { return true }
            return recordsCalendar.isDate(planned, inSameDayAs: today)
        })
    }

    /// The Focus page includes the next scheduled task as well as today's
    /// work. A task created for tomorrow used to disappear immediately after
    /// the add sheet pushed this page, because the page only queried today.
    func focusTasksForFocusPage(at date: Date = .now) -> [FocusTask] {
        let today = recordsCalendar.startOfDay(for: date)
        return records.state.focusTasks.filter { task in
            guard task.deletedAt == nil else { return false }
            if task.completedAt == nil {
                return task.plannedForDate.map { $0 >= today } ?? true
            }
            return task.completedAt.map { recordsCalendar.isDate($0, inSameDayAs: today) } ?? false
        }.sorted { lhs, rhs in
            let lhsDate = lhs.scheduledStartAt ?? lhs.plannedForDate ?? lhs.createdAt
            let rhsDate = rhs.scheduledStartAt ?? rhs.plannedForDate ?? rhs.createdAt
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Blocks finished for a task, so the estimate the user typed has something
    /// to be measured against on screen.
    func completedFocusBlocks(for task: FocusTask) -> Int {
        records.state.focusSessions.count(where: {
            $0.taskID == task.id && $0.kind == .focus && $0.endReason == .completed
        })
    }

    func focusSessions(forDayKey dayKey: String) -> [FocusSession] {
        records.state.focusSessions
            .filter {
                ($0.anchorDayKey ?? RecordJSON.dayKey($0.shiftAnchorDate, calendar: recordsCalendar)) == dayKey
            }
            .sorted {
                if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func favoriteFocusTasks() -> [FocusTask] {
        records.state.focusTasks
            .filter { $0.deletedAt == nil && $0.isFavorite }
            .sorted {
                if $0.editedAt != $1.editedAt { return $0.editedAt > $1.editedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func toggleFocusFavorite(_ task: FocusTask) {
        guard task.deletedAt == nil else { return }
        var next = task
        next.isFavorite.toggle()
        records.upsertFocusTask(next)
    }

    @discardableResult
    func applyFavoriteFocusTask(_ task: FocusTask, at date: Date = .now) -> FocusTask? {
        guard plus.isAuthorized, task.deletedAt == nil else { return nil }
        return addFocusTaskAuthorized(
            title: task.title,
            pomodoros: task.estimatedPomodoros,
            plannedFor: date,
            icon: task.icon
        )
    }

    @discardableResult
    func deleteFocusTask(_ task: FocusTask, at date: Date = .now) -> Bool {
        guard task.deletedAt == nil,
              activeFocusSession()?.taskID != task.id
        else { return false }
        var next = task
        next.deletedAt = date
        records.upsertFocusTask(next, at: date)
        for key in focusPlanning.plans.keys {
            focusPlanning.plans[key]?.assignments.removeAll { $0.taskID == task.id }
        }
        persistFocusPlanning()
        return true
    }

    func focusOverflow() -> [FocusTask] {
        let remaining = Int64(snapshot(at: .now)?.remainingMs ?? 0)
        return FocusPlanner.remainingPomodoros(
            tasks: focusTasksForToday(),
            remainingWorkMs: remaining,
            completedBlocks: { completedFocusBlocks(for: $0) },
            settings: focusTimerSettings
        ).overflow
    }

    /// Deterministic even before reconciliation completes. CloudKit can
    /// briefly deliver two open rows; selecting by stable keys avoids each
    /// device showing a different timer.
    func activeFocusSession() -> FocusSession? {
        records.state.focusSessions.filter { $0.endedAt == nil }.min {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var focusRejectedNoRoom = false
    private(set) var focusLastNextAction: FocusNextAction = .none
    private(set) var focusNotificationIssue: FocusNotificationIssue?
    @ObservationIgnored private var focusNotificationGeneration: UInt64 = 0
    @ObservationIgnored private var isReconcilingFocusSessions = false

    /// Same room check `startFocus` uses, so the button can disable before
    /// a tap that would only be rejected.
    func hasFocusRoom(at date: Date = .now) -> Bool {
        guard shouldQuerySnapshot(at: date) else { return false }
        let current = snapshot(at: date)
        let segments = current?.segments ?? []
        guard FocusPlanner.isInsideWork(
            at: date,
            segments: segments,
            overtimeEndAtMs: overtimeEndAtMs
        ) else { return false }
        if (current?.remainingMs ?? 0) < 60_000 { return false }
        let planned = FocusPlanner.plannedEnd(
            from: date,
            segments: segments,
            overtimeEndAtMs: overtimeEndAtMs,
            durationMinutes: focusTimerSettings.normalized.focusMinutes,
            extraBoundaries: focusMicroBreakBoundaries(at: date)
        )
        return planned.timeIntervalSince(date) >= 60
    }

    /// Both current UI and imported legacy tasks may have a planned civil day
    /// without an exact slot. Treat that day as a real start boundary rather
    /// than allowing an unslotted tomorrow task to start today.
    private func focusTaskUnavailableUntil(_ task: FocusTask, at date: Date) -> Date? {
        // An exact slot is stronger than its containing civil day. Checking
        // the day first made a task planned for tomorrow at 09:00 available at
        // 00:00, and the UI exposed that wrong boundary as “During 12:00 AM”.
        if let scheduled = task.scheduledStartAt, scheduled > date { return scheduled }
        let today = recordsCalendar.startOfDay(for: date)
        if let planned = task.plannedForDate {
            let plannedDay = recordsCalendar.startOfDay(for: planned)
            if plannedDay > today { return plannedDay }
        }
        return nil
    }

    private func breakDurationMinutes(_ kind: FocusSessionKind) -> Int {
        kind == .shortBreak
            ? focusTimerSettings.normalized.shortBreakMinutes
            : focusTimerSettings.normalized.longBreakMinutes
    }

    /// Uses exactly the same segment and micro-break constraints as an actual
    /// break start. Keeping this separate lets the completed-focus state avoid
    /// advertising a recovery phase that cannot be entered.
    private func plannedFocusBreakEnd(kind: FocusSessionKind, at date: Date) -> Date? {
        guard kind == .shortBreak || kind == .longBreak else { return nil }
        let current = snapshot(at: date)
        guard FocusPlanner.isInsideWork(
            at: date,
            segments: current?.segments ?? [],
            overtimeEndAtMs: overtimeEndAtMs
        ) else { return nil }
        let planned = FocusPlanner.plannedEnd(
            from: date,
            segments: current?.segments ?? [],
            overtimeEndAtMs: overtimeEndAtMs,
            durationMinutes: breakDurationMinutes(kind),
            extraBoundaries: focusMicroBreakBoundaries(at: date)
        )
        return planned.timeIntervalSince(date) >= 60 ? planned : nil
    }

    func focusStartAvailability(_ task: FocusTask, at date: Date = .now) -> FocusStartAvailability {
        if task.completedAt != nil || task.deletedAt != nil { return .completed }
        if let unavailableUntil = focusTaskUnavailableUntil(task, at: date) {
            return .notYetAvailable(unavailableUntil)
        }
        if let session = activeFocusSession() {
            return session.taskID == task.id ? .running : .blockedByOther
        }
        return hasFocusRoom(at: date) ? .ready : .noRoom
    }

    /// Returns whether a block actually started. The view fires haptics from
    /// this, not from the tap — a disabled-looking Start that still buzzed
    /// and then did nothing was the previous behaviour.
    @discardableResult
    func startFocus(task: FocusTask) -> Bool {
        if plus.isAuthorized {
            return startFocusAuthorized(task)
        }
        pendingPlusAction = .startFocus(taskID: task.id)
        paywallSheet = .focus
        return false
    }

    @discardableResult
    private func startFocusAuthorized(_ task: FocusTask) -> Bool {
        guard activeFocusSession() == nil, task.completedAt == nil, task.deletedAt == nil else { return false }
        let start = Date.now
        guard focusTaskUnavailableUntil(task, at: start) == nil else { return false }
        guard hasFocusRoom(at: start) else {
            focusRejectedNoRoom = true
            return false
        }
        focusRejectedNoRoom = false
        let current = snapshot(at: start)
        let planned = FocusPlanner.plannedEnd(
            from: start,
            segments: current?.segments ?? [],
            overtimeEndAtMs: overtimeEndAtMs,
            durationMinutes: focusTimerSettings.normalized.focusMinutes,
            extraBoundaries: focusMicroBreakBoundaries(at: start)
        )
        let timeZone = recordsCalendar.timeZone
        let session = FocusSession(
            id: UUID(),
            taskID: task.id,
            shiftAnchorDate: recordsCalendar.startOfDay(for: start),
            startedAt: start,
            plannedEndAt: planned,
            endedAt: nil,
            endReason: nil,
            editedAt: start,
            editCount: 0,
            editTieBreaker: UUID(),
            kind: .focus,
            timeZoneIdentifier: timeZone.identifier,
            anchorDayKey: RecordJSON.dayKey(start, calendar: recordsCalendar),
            actualDurationSeconds: nil,
            plannedEndReason: FocusPlanner.endReason(
                startedAt: start,
                plannedEndAt: planned,
                expectedDurationMinutes: focusTimerSettings.normalized.focusMinutes
            )
        )
        records.upsertFocusSession(session)
        scheduleFocusTimerNotification(for: session)
        scheduleFocusExpiry(for: session)
        return true
    }

    @discardableResult
    func startBreak(kind: FocusSessionKind, at start: Date = .now) -> Bool {
        let requiredAction: FocusNextAction = kind == .shortBreak ? .startShortBreak : .startLongBreak
        guard (kind == .shortBreak || kind == .longBreak),
              focusLastNextAction == requiredAction,
              activeFocusSession() == nil,
              let planned = plannedFocusBreakEnd(kind: kind, at: start)
        else { return false }
        let duration = breakDurationMinutes(kind)
        let session = FocusSession(
            id: UUID(), taskID: nil,
            shiftAnchorDate: recordsCalendar.startOfDay(for: start),
            startedAt: start, plannedEndAt: planned, endedAt: nil, endReason: nil,
            editedAt: start, editCount: 0, editTieBreaker: UUID(), kind: kind,
            timeZoneIdentifier: recordsCalendar.timeZone.identifier,
            anchorDayKey: RecordJSON.dayKey(start, calendar: recordsCalendar),
            actualDurationSeconds: nil,
            plannedEndReason: FocusPlanner.endReason(
                startedAt: start, plannedEndAt: planned, expectedDurationMinutes: duration
            )
        )
        records.upsertFocusSession(session)
        scheduleFocusTimerNotification(for: session)
        scheduleFocusExpiry(for: session)
        return true
    }

    func skipFocusPhase() {
        guard let session = activeFocusSession() else { return }
        stopFocus(reason: .stoppedByUser)
        if session.kind == .shortBreak || session.kind == .longBreak {
            focusLastNextAction = .startNextFocus
        }
    }

    /// Skips a proposed recovery phase without manufacturing an immediately
    /// stopped break. This remains useful when a focus block ended at a lunch
    /// or clock-off boundary and there is no valid break interval to start.
    @discardableResult
    func skipSuggestedFocusBreak() -> Bool {
        guard activeFocusSession() == nil,
              focusLastNextAction == .startShortBreak || focusLastNextAction == .startLongBreak
        else { return false }
        focusLastNextAction = .startNextFocus
        return true
    }

    private func scheduleFocusTimerNotification(for session: FocusSession) {
        let reason = session.plannedEndReason ?? .stoppedAtBoundary
        focusNotificationGeneration &+= 1
        let generation = focusNotificationGeneration
        Task { @MainActor [weak self] in
            let result = await NotificationService.scheduleFocusTimer(
                id: session.id,
                endAt: session.plannedEndAt,
                title: self?.t("focusTitle") ?? "Focus",
                body: self?.t(reason == .completed ? "focusEndedNaturally" : "focusEndedAtBoundary") ?? "",
                isCurrent: { [weak self] in
                    guard let self else { return false }
                    return NotificationService.mayMutateFocusNotificationChannel(
                        requestGeneration: generation,
                        currentGeneration: self.focusNotificationGeneration,
                        requestID: session.id,
                        activeSessionID: self.activeFocusSession()?.id
                    )
                }
            )
            guard let self else { return }
            guard NotificationService.shouldKeepFocusNotification(
                requestGeneration: generation,
                currentGeneration: self.focusNotificationGeneration,
                requestID: session.id,
                activeSessionID: self.activeFocusSession()?.id
            ) else {
                NotificationService.cancelFocusTimer(id: session.id)
                return
            }
            self.applyFocusNotificationResult(result, for: session.id)
        }
    }

    /// Applies a system scheduling result only while the phase that requested
    /// it still owns the visible timer. Keeping this state transition separate
    /// makes the user-facing denied/failed/recovered states directly testable
    /// without prompting for real notification permission in a unit test.
    func applyFocusNotificationResult(
        _ result: NotificationService.FocusScheduleResult,
        for sessionID: UUID
    ) {
        guard activeFocusSession()?.id == sessionID else { return }
        switch result {
        case .scheduled: focusNotificationIssue = nil
        case .permissionDenied: focusNotificationIssue = .permissionDenied
        case .failed: focusNotificationIssue = .schedulingFailed
        case .superseded: break
        }
    }

    /// A visible, actionable retry for a denied/failed focus notification.
    /// It resubmits the current phase instead of merely refreshing OS status.
    func retryFocusNotification() {
        guard let session = activeFocusSession() else { return }
        scheduleFocusTimerNotification(for: session)
    }

    func scheduleFocusExpiry(for session: FocusSession) {
        focusExpiryTask?.cancel()
        let end = session.plannedEndAt
        focusExpiryTask = Task { [weak self] in
            let delay = end.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                _ = self?.finishElapsedFocusSession()
            }
        }
    }

    func stopFocus(reason: FocusEndReason, at date: Date = .now) {
        guard var session = activeFocusSession() else { return }
        focusExpiryTask?.cancel()
        focusExpiryTask = nil
        focusNotificationGeneration &+= 1
        NotificationService.cancelFocusTimer(id: session.id)
        session.endedAt = date
        if let endedAt = session.endedAt {
            session.actualDurationSeconds = max(0, Int(endedAt.timeIntervalSince(session.startedAt)))
        }
        session.endReason = reason
        records.upsertFocusSession(session)
        if reason == .completed, session.kind != .focus {
            focusLastNextAction = .startNextFocus
            return
        }
        // A finished block is one completed session, not the whole task.
        // Marking `completedAt` on the first 25 minutes of a 2–12 block
        // estimate made the "1 / 2" row and the Done chip disagree.
        guard reason == .completed, session.kind == .focus, let taskID = session.taskID,
              var task = records.state.focusTasks.first(where: { $0.id == taskID })
        else { return }
        if completedFocusBlocks(for: task) >= max(1, task.estimatedPomodoros) {
            task.completedAt = date
            records.upsertFocusTask(task)
        }
        let dayKey = session.anchorDayKey ?? RecordJSON.dayKey(session.shiftAnchorDate, calendar: recordsCalendar)
        let round = records.state.focusSessions.count {
            $0.kind == .focus && $0.endReason == .completed
                && ($0.anchorDayKey ?? RecordJSON.dayKey($0.shiftAnchorDate, calendar: recordsCalendar)) == dayKey
        }
        let suggestedKind: FocusSessionKind = round % focusTimerSettings.normalized.longBreakEvery == 0
            ? .longBreak : .shortBreak
        let suggestedAction: FocusNextAction = suggestedKind == .longBreak
            ? .startLongBreak : .startShortBreak
        // Do not surface a break CTA that cannot start because this block just
        // reached lunch or clock-off. There is no phase to skip in that case.
        focusLastNextAction = plannedFocusBreakEnd(kind: suggestedKind, at: date) == nil
            ? .none
            : suggestedAction
    }

    /// Ends a block whose planned end has already passed, with the reason that
    /// actually applies.
    ///
    /// The one place a block ends by itself. A phone spends most of a pomodoro
    /// suspended, so this cannot depend on a view ticking once a second — that
    /// only ran while the Focus page was on screen, and it reported every end
    /// as a boundary cut, so finishing a pomodoro never completed its task.
    /// Called on launch, on foreground, at day change, and by the Focus page
    /// when its countdown reaches zero.
    @discardableResult
    func finishElapsedFocusSession(at date: Date = .now) -> Bool {
        guard let session = activeFocusSession(), session.plannedEndAt <= date else { return false }
        let reason = session.plannedEndReason ?? FocusPlanner.endReason(
            startedAt: session.startedAt,
            plannedEndAt: session.plannedEndAt,
            // v1 sessions were always 25-minute focus blocks. Preferences are
            // intentionally local and must not rewrite historical outcomes.
            expectedDurationMinutes: FocusPlanner.pomodoroMinutes
        )
        stopFocus(reason: reason, at: date)
        return true
    }

    private func restoreFocusNextActionFromHistory() {
        guard activeFocusSession() == nil else { return }
        guard let latest = records.state.focusSessions
            .filter({ $0.endedAt != nil })
            .max(by: { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) })
        else {
            focusLastNextAction = .none
            return
        }
        if latest.kind == .shortBreak || latest.kind == .longBreak {
            focusLastNextAction = .startNextFocus
            return
        }
        guard latest.kind == .focus, latest.endReason == .completed else {
            focusLastNextAction = .none
            return
        }
        let dayKey = latest.anchorDayKey ?? RecordJSON.dayKey(latest.shiftAnchorDate, calendar: recordsCalendar)
        let rounds = records.state.focusSessions.count {
            $0.kind == .focus
                && $0.endReason == .completed
                && ($0.anchorDayKey ?? RecordJSON.dayKey($0.shiftAnchorDate, calendar: recordsCalendar)) == dayKey
        }
        focusLastNextAction = rounds % focusTimerSettings.normalized.longBreakEvery == 0
            ? .startLongBreak : .startShortBreak
    }

    /// Called after a CloudKit batch/import and on lifecycle restore. Exactly
    /// one open session survives; losing rows remain audit history and sync.
    func reconcileOpenFocusSessions(at date: Date = .now) {
        guard !isReconcilingFocusSessions else { return }
        isReconcilingFocusSessions = true
        defer { isReconcilingFocusSessions = false }
        let open = records.state.focusSessions.filter { $0.endedAt == nil }.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let winner = open.first else {
            focusExpiryTask?.cancel()
            focusExpiryTask = nil
            focusNotificationGeneration &+= 1
            Task { await NotificationService.cancelAllFocusTimers() }
            restoreFocusNextActionFromHistory()
            return
        }
        for var losing in open.dropFirst() {
            losing.endedAt = date
            losing.endReason = .supersededBySync
            losing.actualDurationSeconds = max(0, Int(date.timeIntervalSince(losing.startedAt)))
            records.upsertFocusSession(losing, at: date)
        }
        if winner.plannedEndAt <= date {
            _ = finishElapsedFocusSession(at: date)
            restoreFocusNextActionFromHistory()
        } else {
            focusLastNextAction = .none
            scheduleFocusExpiry(for: winner)
            scheduleFocusTimerNotification(for: winner)
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

    /// - Parameter periodStartMs: An explicit window start. Callers that drew
    ///   their own boundary — the Records tab, whose grids follow the locale's
    ///   first weekday — pass it so the summary covers the window on screen.
    ///   Omit it and the rules bundle derives the window from `period`.
    func periodSummary(
        _ period: String,
        asOf: Date,
        snapshot: NativeShiftSnapshot,
        periodStartMs: Double? = nil
    ) -> NativePeriodSummary? {
        guard effectiveScheduleMode(at: asOf) != .off else { return nil }
        var summaryWorkdays = effectiveWorkdays(at: asOf)
        if isForcedWorkday(snapshot) {
            summaryWorkdays.insert(Calendar.current.component(.weekday, from: snapshot.startDate) - 1)
        }
        do {
            let result = try CountdownRules.shared.summarize(input: .init(
                period: period,
                periodStartMs: periodStartMs,
                asOfMs: asOf.timeIntervalSince1970 * 1_000,
                workdays: summaryWorkdays.sorted(),
                schedule: nativeSchedule(at: asOf),
                currentShiftStartMs: snapshot.startAtMs,
                currentShiftEndMs: snapshot.endAtMs,
                plannedDailyHours: snapshot.plannedDurationMs / 3_600_000,
                todayProgress: min(100, snapshot.progress),
                dailySalary: snapshot.dailySalary,
                todayEffectiveHours: snapshot.durationMs / 3_600_000,
                todayPayRatio: snapshot.payRatio,
                timeZoneIdentifier: recordsTimeZoneIdentifier
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

    /// Debug capture scenarios may explicitly clear this in-memory token.
    /// Normal warm-session lifecycle never does: only constructing a fresh
    /// store on cold launch makes the completed shift celebrate again.
    func resetCelebratedSession() {
        lastCelebratedEndAtMs = 0
    }

    static func dayKey(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: parts) ?? date
    }

    private static func startOfDay(for date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    private static func startOfCurrentWeek(timeZone: TimeZone) -> Date {
        startOfWeek(containing: .now, timeZone: timeZone)
    }

    private static func startOfWeek(containing date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        let day = calendar.startOfDay(for: date)
        return calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    }
}

/// Civil calendars for the records zone. Same reason as the date formatters:
/// caching them on the observable store would invalidate every reader.
@MainActor
final class CivilCalendarCache {
    private var timeZoneIdentifier = ""
    private var localeIdentifier = ""
    private var cachedTimeZone = TimeZone.current
    private var cachedLocale = Locale.current
    private var cachedRecordsCalendar = Calendar(identifier: .gregorian)
    private var cachedGridCalendar = Calendar(identifier: .gregorian)

    func timeZone(identifier: String) -> TimeZone {
        prepare(timeZoneIdentifier: identifier, localeIdentifier: localeIdentifier)
        return cachedTimeZone
    }

    func locale(identifier: String) -> Locale {
        prepare(timeZoneIdentifier: timeZoneIdentifier, localeIdentifier: identifier)
        return cachedLocale
    }

    func recordsCalendar(timeZoneIdentifier: String) -> Calendar {
        prepare(timeZoneIdentifier: timeZoneIdentifier, localeIdentifier: localeIdentifier)
        return cachedRecordsCalendar
    }

    func gridCalendar(timeZoneIdentifier: String, localeIdentifier: String) -> Calendar {
        prepare(timeZoneIdentifier: timeZoneIdentifier, localeIdentifier: localeIdentifier)
        return cachedGridCalendar
    }

    private func prepare(timeZoneIdentifier: String, localeIdentifier: String) {
        if timeZoneIdentifier == self.timeZoneIdentifier, localeIdentifier == self.localeIdentifier {
            return
        }
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localeIdentifier = localeIdentifier
        cachedTimeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        cachedLocale = Locale(identifier: localeIdentifier)
        var records = Calendar(identifier: .gregorian)
        records.timeZone = cachedTimeZone
        cachedRecordsCalendar = records
        var grid = Calendar(identifier: .gregorian)
        grid.timeZone = cachedTimeZone
        grid.locale = cachedLocale
        grid.firstWeekday = OffWorkStore.firstWeekdayIndex(of: cachedLocale)
        cachedGridCalendar = grid
    }
}

/// Skeleton-based date formatters, kept alive between rows.
///
/// Deliberately outside the observable store: caching in a stored property
/// there would register a mutation on every formatted date and invalidate the
/// views that asked for it.
@MainActor
final class RecordsDateFormatters {
    static let shared = RecordsDateFormatters()

    private var cache: [String: DateFormatter] = [:]

    func formatter(template: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(timeZone.identifier)"
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        // A template, not a format string: ICU reorders the fields per locale,
        // so the same call gives "Aug 26" and "8月26日".
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[key] = formatter
        return formatter
    }
}
