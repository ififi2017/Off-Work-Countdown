import Foundation
import SwiftUI

/// Owns committed settings and their legacy device storage. Callers edit a
/// value through applyPreferences; no setting assignment saves the archive.
@MainActor
@Observable
final class PreferencesStore {
    private let defaults: UserDefaults
    private let records: RecordCoordinator
    var preferredRecordsScale: RecordsScale {
        get { RecordsScale(rawValue: defaults.string(forKey: "ios.native.recordsScale") ?? "") ?? .month }
        set { defaults.set(newValue.rawValue, forKey: "ios.native.recordsScale") }
    }
    private(set) var seenRelease: String?
    var shouldOfferReleaseNotes: Bool {
        ReleaseNotes.shouldPresent(onboardingComplete: onboardingComplete, seenRelease: seenRelease)
    }

    func markReleaseNotesSeen() {
        seenRelease = ReleaseNotes.current
        defaults.set(ReleaseNotes.current, forKey: ReleaseNotes.seenKey)
    }
    @ObservationIgnored private let civilCalendars = CivilCalendarCache()
    static let allowedLiveActivityLeadMinutes = [5, 15, 30]
    private enum Key {
        static let onboardingComplete = "ios.native.onboardingComplete"
#if DEBUG
        static let debugAlwaysOnboarding = "ios.native.debugAlwaysOnboarding"
#endif
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
        static let focusLiveActivityEnabled = "ios.native.focusLiveActivityEnabled"
        static let liveActivityEnabled = "ios.native.liveActivityEnabled"
        static let liveActivityLead = "ios.native.liveActivityLead"
        static let legacyLunchEdgesEnabled = "ios.native.lunchEdgesEnabled"
        static let lunchStartReminderEnabled = "ios.native.lunchStartReminderEnabled"
        static let lunchEndReminderEnabled = "ios.native.lunchEndReminderEnabled"
        static let microBreakEnabled = "ios.native.microBreakEnabled"
        static let microBreakInterval = "ios.native.microBreakInterval"
        static let recordsTimeZone = "ios.native.recordsTimeZone"
        static let lifeSetupPromptDismissed = "ios.native.lifeSetupPromptDismissed"
    }
    private(set) var startMinutes: Int
    private(set) var endMinutes: Int
    private(set) var workdays: Set<Int>
    private(set) var scheduleMode: WorkScheduleMode
    private(set) var alternatingWeekType: AlternatingWeekType
    private(set) var alternatingWeekendWorkday: Int
    private(set) var alternatingReferenceWeekStartMs: Double
    private(set) var rotationWorkDays: Int
    private(set) var rotationRestDays: Int
    private(set) var rotationAnchorMs: Double
    private(set) var lunchEnabled: Bool
    private(set) var lunchStartMinutes: Int
    private(set) var lunchDurationMinutes: Int
    private(set) var recordsTimeZoneIdentifier: String
    private(set) var salaryAmount: String
    private(set) var salaryEnabled: Bool
    private(set) var salaryType: SalaryType
    private(set) var monthlyWorkingDays: Double
    private(set) var annualBonusEnabled: Bool
    private(set) var annualBonusMonths: Double
    private(set) var notificationMode: OffWorkNotificationMode
    private(set) var cycleEndSummaryNotificationEnabled: Bool
    private(set) var lunchStartReminderEnabled: Bool
    private(set) var lunchEndReminderEnabled: Bool
    private(set) var microBreakEnabled: Bool
    private(set) var microBreakIntervalMinutes: Int
    private(set) var theme: AppTheme
    private(set) var languageOverride: String?
    var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: Key.onboardingComplete) } }
#if DEBUG
    /// Replay the welcome flow on every launch. The property and its storage
    /// key do not exist in Release builds.
    var debugAlwaysShowOnboarding: Bool {
        didSet { defaults.set(debugAlwaysShowOnboarding, forKey: Key.debugAlwaysOnboarding) }
    }
#endif
    var hideEarnings: Bool { didSet { defaults.set(hideEarnings, forKey: Key.hideEarnings) } }
    var lifeSetupPromptDismissed: Bool {
        didSet { defaults.set(lifeSetupPromptDismissed, forKey: Key.lifeSetupPromptDismissed) }
    }
    var focusLiveActivityEnabled: Bool {
        didSet { defaults.set(focusLiveActivityEnabled, forKey: Key.focusLiveActivityEnabled) }
    }
    var liveActivityEnabled: Bool { didSet { defaults.set(liveActivityEnabled, forKey: Key.liveActivityEnabled) } }
    var liveActivityLeadMinutes: Int { didSet { defaults.set(liveActivityLeadMinutes, forKey: Key.liveActivityLead) } }
    /// The language iOS would give us, kept as stored state so a change while
    /// the app is backgrounded invalidates the views that read it.
    private(set) var systemLanguageCode: String
    /// Same reason as `systemLanguageCode`: `TimeZone.current` does not
    /// invalidate SwiftUI by itself, so a trip through Settings would leave
    /// the records-timezone page looking like nothing changed.
    private(set) var systemTimeZoneIdentifier: String
    /// In-memory: the reminders page applies lunch-on and simple clock-off
    /// once per launch. Persisting it would rewrite a user who turned those
    /// off, went back, and came in again.
    var didApplyOnboardingReminderDefaults = false
    var recordsTimeZone: TimeZone {
        civilCalendars.timeZone(identifier: recordsTimeZoneIdentifier)
    }
    /// Calendar used for records and schedule civil math. It remains anchored
    /// to the persisted records zone rather than the device's travel zone.
    var recordsCalendar: Calendar {
        civilCalendars.recordsCalendar(timeZoneIdentifier: recordsTimeZoneIdentifier)
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
    /// What the UI actually renders in. Widgets, the Live Activity and the
    /// notification copy all read this, so pinning a language carries through
    /// without any of them knowing an override exists.
    var languageCode: String { languageOverride ?? systemLanguageCode }
    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var layoutDirection: LayoutDirection { languageCode == "ar" ? .rightToLeft : .leftToRight }
    var locale: Locale { civilCalendars.locale(identifier: languageCode) }
    var quickThemeIcon: String {
        switch theme {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
    /// Plan 018 P8. The extended schedule lives in the record archive, not in
    /// the synced preferences, but the session reads it through here like the
    /// rest of the schedule.
    var isExtendedScheduleEnabled: Bool { records.state.extendedSchedule?.isEnabled == true }

    /// The stored plan, switched on or not. Whether the countdown follows it
    /// is the session's call: today can keep the setting it had before a
    /// change saved "from the next shift only".
    var extendedSchedulePlan: ExtendedSchedulePlan? { records.extendedSchedulePlan }

    /// The stored shift types and rule, which the schedule page edits.
    var extendedScheduleContent: ExtendedScheduleContent? { records.state.extendedSchedule?.content }

    /// Shift types and a rule other than the stored ones, over the stored
    /// hand-set days: a draft being weighed, or today's kept schedule.
    func extendedSchedulePlan(for content: ExtendedScheduleContent) -> ExtendedSchedulePlan {
        records.extendedSchedulePlan(for: content)
    }

    /// A schedule page draft as the rules would read it once saved.
    func extendedSchedulePlan(
        for content: ExtendedScheduleContent?,
        applying edits: [String: RosterDayEdit]?
    ) -> ExtendedSchedulePlan? {
        records.extendedSchedulePlan(for: content, applying: edits)
    }

    /// `plan` with one day as it was before a save.
    func extendedSchedulePlan(_ plan: ExtendedSchedulePlan, keeping day: KeptRosterDay) -> ExtendedSchedulePlan {
        records.extendedSchedulePlan(plan, keeping: day)
    }

    /// The days the user gave a shift by hand, by civil day key.
    var handSetDays: [String: UUID] {
        records.extendedSchedulePlan?.handSetDays ?? ExtendedSchedulePlan.handSetDays(from: records.state.rosterDays)
    }

    var rotationCycleLength: Int {
        max(2, rotationWorkDays + rotationRestDays)
    }
    /// Returns today's one-based position in the existing shared rotation
    /// schedule. Choosing another position only moves the schedule anchor; the
    /// schedule rules remain responsible for deciding work and rest days.
    var rotationCycleDay: Int {
        rotationCycleDay(at: .now)
    }

    init(defaults: UserDefaults, records: RecordCoordinator) {
        self.defaults = defaults
        self.records = records
#if DEBUG
        let replayOnboarding = defaults.bool(forKey: Key.debugAlwaysOnboarding)
        debugAlwaysShowOnboarding = replayOnboarding
        onboardingComplete = replayOnboarding ? false : defaults.bool(forKey: Key.onboardingComplete)
#else
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
#endif
        let initialRecordsTimeZoneIdentifier = defaults.string(forKey: Key.recordsTimeZone)
            ?? records.state.periods.first?.timeZoneIdentifier
            ?? TimeZone.current.identifier
        recordsTimeZoneIdentifier = initialRecordsTimeZoneIdentifier
        let initialRecordsTimeZone = TimeZone(identifier: initialRecordsTimeZoneIdentifier) ?? .current
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
        focusLiveActivityEnabled = defaults.object(forKey: Key.focusLiveActivityEnabled) as? Bool ?? true
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
        seenRelease = defaults.string(forKey: ReleaseNotes.seenKey)
        if !onboardingComplete { markReleaseNotesSeen() }

        if scheduleMode == .classic, workdays.isEmpty {
            workdays = [1, 2, 3, 4, 5]
        }
        if let value = records.state.syncedPreferences {
            receive(value)
        } else if onboardingComplete {
            // An old device must not beat an established cloud row merely
            // because it just upgraded and read undated legacy defaults.
            records.upsertSyncedPreferences(currentSyncedPreferences(), at: .distantPast)
        }
    }

    /// An editing value has no record identity of its own. The coordinator
    /// assigns a stamp only when content changes; reading a control must not
    /// observe archive metadata or manufacture a new timestamp/UUID.
    func currentSyncedPreferences() -> SyncedPreferences {
        SyncedPreferences(
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            workdays: workdays.sorted(),
            scheduleMode: scheduleMode,
            alternatingWeekType: alternatingWeekType,
            alternatingWeekendWorkday: alternatingWeekendWorkday,
            alternatingReferenceWeekStartMs: alternatingReferenceWeekStartMs,
            rotationWorkDays: rotationWorkDays,
            rotationRestDays: rotationRestDays,
            rotationAnchorMs: rotationAnchorMs,
            lunchEnabled: lunchEnabled,
            lunchStartMinutes: lunchStartMinutes,
            lunchDurationMinutes: lunchDurationMinutes,
            recordsTimeZoneIdentifier: recordsTimeZoneIdentifier,
            salaryAmount: salaryAmount,
            salaryEnabled: salaryEnabled,
            salaryType: salaryType,
            monthlyWorkingDays: monthlyWorkingDays,
            annualBonusEnabled: annualBonusEnabled,
            annualBonusMonths: annualBonusMonths,
            notificationMode: notificationMode,
            cycleEndSummaryNotificationEnabled: cycleEndSummaryNotificationEnabled,
            lunchStartReminderEnabled: lunchStartReminderEnabled,
            lunchEndReminderEnabled: lunchEndReminderEnabled,
            microBreakEnabled: microBreakEnabled,
            microBreakIntervalMinutes: microBreakIntervalMinutes,
            theme: theme,
            languageOverride: languageOverride,
            editedAtMs: Date.distantPast.timeIntervalSince1970 * 1_000,
            editCount: 0,
            editTieBreaker: WorkObservation.unsetTieBreaker
        )
    }
    private func receive(_ preferences: SyncedPreferences) {
        guard preferences.isValid else { return }
        guard !currentSyncedPreferences().hasSameSettings(as: preferences) else { return }
        if startMinutes != preferences.startMinutes {
            startMinutes = preferences.startMinutes
            defaults.set(startMinutes, forKey: Key.startMinutes)
        }
        if endMinutes != preferences.endMinutes {
            endMinutes = preferences.endMinutes
            defaults.set(endMinutes, forKey: Key.endMinutes)
        }
        if workdays != Set(preferences.workdays) {
            workdays = Set(preferences.workdays)
            defaults.set(workdays.sorted(), forKey: Key.workdays)
        }
        if scheduleMode != preferences.scheduleMode {
            scheduleMode = preferences.scheduleMode
            defaults.set(scheduleMode.rawValue, forKey: Key.scheduleMode)
        }
        if alternatingWeekType != preferences.alternatingWeekType {
            alternatingWeekType = preferences.alternatingWeekType
            defaults.set(alternatingWeekType.rawValue, forKey: Key.alternatingWeekType)
        }
        if alternatingWeekendWorkday != preferences.alternatingWeekendWorkday {
            alternatingWeekendWorkday = preferences.alternatingWeekendWorkday
            defaults.set(alternatingWeekendWorkday, forKey: Key.alternatingWeekendWorkday)
        }
        if alternatingReferenceWeekStartMs != preferences.alternatingReferenceWeekStartMs {
            alternatingReferenceWeekStartMs = preferences.alternatingReferenceWeekStartMs
            defaults.set(alternatingReferenceWeekStartMs, forKey: Key.alternatingReferenceWeekStartMs)
        }
        if rotationWorkDays != preferences.rotationWorkDays {
            rotationWorkDays = preferences.rotationWorkDays
            defaults.set(rotationWorkDays, forKey: Key.rotationWorkDays)
        }
        if rotationRestDays != preferences.rotationRestDays {
            rotationRestDays = preferences.rotationRestDays
            defaults.set(rotationRestDays, forKey: Key.rotationRestDays)
        }
        if rotationAnchorMs != preferences.rotationAnchorMs {
            rotationAnchorMs = preferences.rotationAnchorMs
            defaults.set(rotationAnchorMs, forKey: Key.rotationAnchorMs)
        }
        if lunchEnabled != preferences.lunchEnabled {
            lunchEnabled = preferences.lunchEnabled
            defaults.set(lunchEnabled, forKey: Key.lunchEnabled)
        }
        if lunchStartMinutes != preferences.lunchStartMinutes {
            lunchStartMinutes = preferences.lunchStartMinutes
            defaults.set(lunchStartMinutes, forKey: Key.lunchStartMinutes)
        }
        if lunchDurationMinutes != preferences.lunchDurationMinutes {
            lunchDurationMinutes = preferences.lunchDurationMinutes
            defaults.set(lunchDurationMinutes, forKey: Key.lunchDuration)
        }
        if recordsTimeZoneIdentifier != preferences.recordsTimeZoneIdentifier {
            recordsTimeZoneIdentifier = preferences.recordsTimeZoneIdentifier
            defaults.set(recordsTimeZoneIdentifier, forKey: Key.recordsTimeZone)
        }
        if salaryAmount != preferences.salaryAmount {
            salaryAmount = preferences.salaryAmount
            defaults.set(salaryAmount, forKey: Key.salaryAmount)
        }
        if salaryEnabled != preferences.salaryEnabled {
            salaryEnabled = preferences.salaryEnabled
            defaults.set(salaryEnabled, forKey: Key.salaryEnabled)
        }
        if salaryType != preferences.salaryType {
            salaryType = preferences.salaryType
            defaults.set(salaryType.rawValue, forKey: Key.salaryType)
        }
        if monthlyWorkingDays != preferences.monthlyWorkingDays {
            monthlyWorkingDays = preferences.monthlyWorkingDays
            defaults.set(monthlyWorkingDays, forKey: Key.monthlyWorkingDays)
        }
        if annualBonusEnabled != preferences.annualBonusEnabled {
            annualBonusEnabled = preferences.annualBonusEnabled
            defaults.set(annualBonusEnabled, forKey: Key.annualBonusEnabled)
        }
        if annualBonusMonths != preferences.annualBonusMonths {
            annualBonusMonths = preferences.annualBonusMonths
            defaults.set(annualBonusMonths, forKey: Key.annualBonusMonths)
        }
        if notificationMode != preferences.notificationMode {
            notificationMode = preferences.notificationMode
            defaults.set(notificationMode.rawValue, forKey: Key.notificationMode)
        }
        if cycleEndSummaryNotificationEnabled != preferences.cycleEndSummaryNotificationEnabled {
            cycleEndSummaryNotificationEnabled = preferences.cycleEndSummaryNotificationEnabled
            defaults.set(cycleEndSummaryNotificationEnabled, forKey: Key.cycleEndSummaryNotificationEnabled)
        }
        if lunchStartReminderEnabled != preferences.lunchStartReminderEnabled {
            lunchStartReminderEnabled = preferences.lunchStartReminderEnabled
            defaults.set(lunchStartReminderEnabled, forKey: Key.lunchStartReminderEnabled)
        }
        if lunchEndReminderEnabled != preferences.lunchEndReminderEnabled {
            lunchEndReminderEnabled = preferences.lunchEndReminderEnabled
            defaults.set(lunchEndReminderEnabled, forKey: Key.lunchEndReminderEnabled)
        }
        if microBreakEnabled != preferences.microBreakEnabled {
            microBreakEnabled = preferences.microBreakEnabled
            defaults.set(microBreakEnabled, forKey: Key.microBreakEnabled)
        }
        if microBreakIntervalMinutes != preferences.microBreakIntervalMinutes {
            microBreakIntervalMinutes = preferences.microBreakIntervalMinutes
            defaults.set(microBreakIntervalMinutes, forKey: Key.microBreakInterval)
        }
        if theme != preferences.theme {
            theme = preferences.theme
            defaults.set(theme.rawValue, forKey: Key.theme)
        }
        if languageOverride != preferences.languageOverride {
            languageOverride = preferences.languageOverride
            defaults.set(languageOverride, forKey: Key.languageOverride)
        }
    }
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
    @discardableResult
    func toggleWorkday(_ day: Int) -> RecordCommand<Bool> {
        applyPreferences { preferences in
            if preferences.workdays.contains(day) {
                guard preferences.workdays.count > 1 else { return }
                preferences.workdays.removeAll { $0 == day }
            } else {
                preferences.workdays.append(day)
                preferences.workdays.sort()
            }
        }
    }
    @discardableResult
    func toggleQuickTheme() -> RecordCommand<Bool> {
        applyPreferences {
            $0.theme = switch $0.theme {
            case .auto: .light
            case .light: .dark
            case .dark: .auto
            }
        }
    }
    func rotationCycleDay(at date: Date) -> Int {
        let calendar = recordsCalendar
        let anchor = calendar.startOfDay(for: Date(timeIntervalSince1970: rotationAnchorMs / 1_000))
        let today = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: anchor, to: today).day ?? 0
        return ((offset % rotationCycleLength) + rotationCycleLength) % rotationCycleLength + 1
    }
    private static func startOfDay(for date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }
    private static func startOfCurrentWeek(timeZone: TimeZone) -> Date {
        startOfWeek(containing: .now, timeZone: timeZone)
    }
    static func startOfWeek(containing date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        let day = calendar.startOfDay(for: date)
        return calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    }
    /// Archive metadata is not an input to a setting. Reload compares the
    /// actual fields before publishing observations or writing legacy defaults.
    func reloadFromArchive() {
        if let value = records.state.syncedPreferences { receive(value) }
    }

    /// Patch the latest settings, preserving unrelated remote edits received
    /// while a scene had an editor open.
    @discardableResult
    func applyPreferences(
        _ edit: @escaping @MainActor (inout SyncedPreferences) -> Void
    ) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return false }
            let current = currentSyncedPreferences()
            var next = current
            edit(&next)
            guard next.isValid, !current.hasSameSettings(as: next) else { return false }
            receive(next)
            if onboardingComplete { records.upsertSyncedPreferences(next) }
            return true
        }
    }

    @discardableResult
    func completeSetup(enableNotifications: Bool) -> RecordCommand<Void> {
        records.submitCommand { [self] in
            records.withBatchedWrites {
                onboardingComplete = true
                if enableNotifications {
                    _ = applyPreferences { $0.notificationMode = .simple }.synchronousResult
                }
                records.upsertSyncedPreferences(currentSyncedPreferences())
            }
        }
    }

    @discardableResult
    func applyOnboardingReminderDefaultsIfNeeded() -> RecordCommand<Void> {
        records.submitCommand { [self] in
            guard !didApplyOnboardingReminderDefaults else { return }
            didApplyOnboardingReminderDefaults = true
            _ = applyPreferences {
                $0.lunchEnabled = true
                $0.lunchStartReminderEnabled = true
                $0.lunchEndReminderEnabled = true
                if $0.notificationMode == .off { $0.notificationMode = .simple }
            }.synchronousResult
        }
    }

    @discardableResult
    func anchorAlternatingWeekToToday(at date: Date = .now) -> RecordCommand<Bool> {
        applyPreferences { [self] in
            $0.alternatingReferenceWeekStartMs = Self.startOfWeek(containing: date, timeZone: recordsTimeZone).timeIntervalSince1970 * 1_000
        }
    }

    @discardableResult
    func anchorRotationToToday(at date: Date = .now) -> RecordCommand<Bool> {
        applyPreferences { [self] in $0.rotationAnchorMs = recordsCalendar.startOfDay(for: date).timeIntervalSince1970 * 1_000 }
    }

    @discardableResult
    func setRotationCycleDay(_ day: Int, at date: Date = .now) -> RecordCommand<Bool> {
        applyPreferences { [self] value in
            let length = max(2, value.rotationWorkDays + value.rotationRestDays)
            let normalizedDay = min(length, max(1, day))
            let today = recordsCalendar.startOfDay(for: date)
            let anchor = recordsCalendar.date(byAdding: .day, value: -(normalizedDay - 1), to: today) ?? today
            value.rotationAnchorMs = anchor.timeIntervalSince1970 * 1_000
        }
    }

    /// Standing schedule edits never manufacture attendance or start a timer.
    /// The shift action wraps this commit and its record/Focus changes in one batch.
    @discardableResult
    func applySetupScheduleChange(
        _ requestedChange: ScheduleFieldChange,
        at date: Date = .now
    ) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            let change = requestedChange.settled(against: self, at: date)
            guard !change.isEmpty else { return false }
            return applyPreferences { [self] value in
                if let startMinutes = change.startMinutes { value.startMinutes = startMinutes }
                if let endMinutes = change.endMinutes { value.endMinutes = endMinutes }
                if let workdays = change.workdays, !workdays.isEmpty { value.workdays = workdays.sorted() }
                if let scheduleMode = change.scheduleMode {
                    value.scheduleMode = scheduleMode
                    if scheduleMode == .alternating {
                        value.alternatingReferenceWeekStartMs = Self.startOfWeek(containing: date, timeZone: recordsTimeZone).timeIntervalSince1970 * 1_000
                    }
                    if scheduleMode == .rotation {
                        value.rotationAnchorMs = recordsCalendar.startOfDay(for: date).timeIntervalSince1970 * 1_000
                    }
                }
                if let lunchEnabled = change.lunchEnabled { value.lunchEnabled = lunchEnabled }
                if let lunchStartMinutes = change.lunchStartMinutes { value.lunchStartMinutes = lunchStartMinutes }
                if let lunchDurationMinutes = change.lunchDurationMinutes { value.lunchDurationMinutes = lunchDurationMinutes }
                if let alternatingWeekType = change.alternatingWeekType {
                    value.alternatingWeekType = alternatingWeekType
                    value.alternatingReferenceWeekStartMs = Self.startOfWeek(containing: date, timeZone: recordsTimeZone).timeIntervalSince1970 * 1_000
                }
                if let alternatingWeekendWorkday = change.alternatingWeekendWorkday { value.alternatingWeekendWorkday = alternatingWeekendWorkday }
                if let rotationWorkDays = change.rotationWorkDays { value.rotationWorkDays = rotationWorkDays }
                if let rotationRestDays = change.rotationRestDays { value.rotationRestDays = rotationRestDays }
                if let rotationCycleDay = change.rotationCycleDay {
                    let length = max(2, value.rotationWorkDays + value.rotationRestDays)
                    let day = min(length, max(1, rotationCycleDay))
                    let today = recordsCalendar.startOfDay(for: date)
                    let anchor = recordsCalendar.date(byAdding: .day, value: -(day - 1), to: today) ?? today
                    value.rotationAnchorMs = anchor.timeIntervalSince1970 * 1_000
                }
            }.synchronousResult
        }
    }
}
