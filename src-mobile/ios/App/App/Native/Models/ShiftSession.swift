import Foundation
import Observation

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
    /// Plan 018 P8. Separate from `scheduleMode`, which is synced to builds
    /// that would fail to decode a new mode.
    var extendedScheduleEnabled: Bool?
    /// Plan 018 P8's shift types and rule, replaced as a whole.
    var extendedContent: ExtendedScheduleContent?
    /// Plan 018 P8's calendar: days given a shift by hand, or put back on the
    /// pattern, keyed by civil day.
    var rosterEdits: [String: RosterDayEdit]?
    /// Draft-only provenance for days expanded when trying free scheduling.
    /// Returning to a pattern drops these, never the user's explicit edits.
    var materializedRosterDays: Set<String> = []
}

/// One day changed in the extended schedule's calendar.
nonisolated enum RosterDayEdit: Hashable, Sendable {
    case shift(UUID)
    /// Drops the hand-set shift, so the pattern or the carried-over month
    /// decides the day again.
    case followPattern
}

/// The hand-set shift one day had before a save, kept so "from the next shift
/// only" leaves the shift in progress alone. `nil` when the day was not set by
/// hand.
nonisolated struct KeptRosterDay: Codable, Equatable, Sendable {
    var dayKey: String
    var shiftTypeID: UUID?
}

/// Hours and calendar in force until the current shift's settlement seam.
/// The committed fields already hold the future schedule.
struct TodayScheduleOverride: Codable, Equatable {
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
    /// Whether today still runs on the extended schedule. `nil` in overrides
    /// saved before it existed, which then follow the current setting.
    var extendedScheduleEnabled: Bool? = nil
    /// The shift types and rule today keeps. `nil` without an extended
    /// schedule, and in overrides saved before this existed, which then follow
    /// the stored ones.
    var extendedContent: ExtendedScheduleContent? = nil
    /// The current shift's day as the calendar had it.
    var extendedKeptDay: KeptRosterDay? = nil
}

/// Current session state and rule-backed read projections. It owns no record
/// archive, Focus object, application, or scene. Feature actions can share this
/// state with readers without creating a reference cycle through Focus.
@MainActor
@Observable
final class ShiftSession {
    let preferences: PreferencesStore
    let text: AppText
    private let defaults: UserDefaults

    private enum Key {
        static let countdownStarted = "ios.native.countdownStarted"
        static let automaticCountdownMigrationCompleted = "ios.native.automaticCountdownMigrationCompleted"
        static let earlyOffAtMs = "ios.native.earlyOffAtMs"
        static let earlyOffShiftEndAtMs = "ios.native.earlyOffShiftEndAtMs"
        static let earlyOffSnapshot = "ios.native.earlyOffSnapshot"
        static let legacyForceToday = "ios.native.forceToday"
        static let forcedWorkdayDate = "ios.native.forcedWorkdayDate"
        static let overtimeEndAtMs = "ios.native.overtimeEndAtMs"
        static let earlyStartAtMs = "ios.native.earlyStartAtMs"
        static let earlyStartUntilMs = "ios.native.earlyStartUntilMs"
        static let todayScheduleOverride = "ios.native.todayScheduleOverride"
        static let sessionTimeZone = "ios.native.sessionTimeZone"
        static let sessionTimeZoneUntilMs = "ios.native.sessionTimeZoneUntilMs"
    }
    /// One running session can span several layouts. A new manual start has a
    /// new identity even when the hours are identical and no view rendered in between.
    private(set) var sessionID = UUID()
    var countdownStarted: Bool {
        didSet {
            guard countdownStarted != oldValue else { return }
            if countdownStarted { sessionID = UUID() }
            defaults.set(countdownStarted, forKey: Key.countdownStarted)
        }
    }
    /// An explicit start also creates a new rest-day run when the automatic
    /// schedule was already armed. Rejected/repeated commands never call this.
    func beginSession() {
        if countdownStarted { sessionID = UUID() }
        countdownStarted = true
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
    var sessionTimeZoneUntilMs: Double? {
        didSet {
            if let sessionTimeZoneUntilMs {
                defaults.set(sessionTimeZoneUntilMs, forKey: Key.sessionTimeZoneUntilMs)
            } else {
                defaults.removeObject(forKey: Key.sessionTimeZoneUntilMs)
            }
        }
    }
    /// Timezone the running countdown and auto-follow snapshot must use.
    var countdownTimeZoneIdentifier: String {
        sessionTimeZoneIdentifier ?? preferences.recordsTimeZoneIdentifier
    }
    var countdownTimeZone: TimeZone {
        TimeZone(identifier: countdownTimeZoneIdentifier) ?? preferences.recordsTimeZone
    }
    var countdownCalendar: Calendar {
        var calendar = preferences.recordsCalendar
        calendar.timeZone = countdownTimeZone
        return calendar
    }
    /// Always make the civil schedule zone explicit. The rules fall back to
    /// `TimeZone.current` without one, and a session can be locked to a zone
    /// the device has since left.
    var rulesTimeZoneIdentifier: String? {
        countdownTimeZoneIdentifier
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
    var earlyOffSnapshot: NativeShiftSnapshot? {
        didSet { persistEarlyOffSnapshot() }
    }
    /// Clocked in before the planned start. Bound to the settlement seam of
    /// that shift so a leftover 08:00 does not become tomorrow's start.
    var earlyStartAtMs: Double? {
        didSet {
            if let earlyStartAtMs { defaults.set(earlyStartAtMs, forKey: Key.earlyStartAtMs) }
            else { defaults.removeObject(forKey: Key.earlyStartAtMs) }
        }
    }
    var earlyStartUntilMs: Double? {
        didSet {
            if let earlyStartUntilMs { defaults.set(earlyStartUntilMs, forKey: Key.earlyStartUntilMs) }
            else { defaults.removeObject(forKey: Key.earlyStartUntilMs) }
        }
    }
    var todayOverride: TodayScheduleOverride? {
        didSet { persistTodayOverride() }
    }
    var forcedWorkdayDate: String? {
        didSet {
            if let forcedWorkdayDate { defaults.set(forcedWorkdayDate, forKey: Key.forcedWorkdayDate) }
            else { defaults.removeObject(forKey: Key.forcedWorkdayDate) }
        }
    }
    var overtimeEndAtMs: Double? {
        didSet {
            if let overtimeEndAtMs { defaults.set(overtimeEndAtMs, forKey: Key.overtimeEndAtMs) }
            else { defaults.removeObject(forKey: Key.overtimeEndAtMs) }
        }
    }
    var debugPresentationToken: String {
#if DEBUG
        debugTimerSession?.scenario.rawValue ?? ""
#else
        ""
#endif
    }
    /// Part of the schedule signature. Forcing a rest day changes what the
    /// widget and the notification list should say, and once the schedule arms
    /// itself nothing else in that signature moves when the button is pressed —
    /// `countdownStarted` was already true, so the widget kept publishing
    /// "rest day" while the app counted the shift down.
    var forcedWorkdayKey: String? { forcedWorkdayDate }
    var presentationNotificationMode: OffWorkNotificationMode {
#if DEBUG
        if debugTimerSession != nil { return .milestones }
#endif
        return preferences.notificationMode
    }
    var presentationLunchStartReminderEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return true }
#endif
        return preferences.lunchStartReminderEnabled
    }
    var presentationLunchEndReminderEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return true }
#endif
        return preferences.lunchEndReminderEnabled
    }
    var presentationMicroBreakEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return true }
#endif
        return preferences.microBreakEnabled
    }
    var presentationMicroBreakIntervalMinutes: Int {
#if DEBUG
        if debugTimerSession != nil { return 60 }
#endif
        return preferences.microBreakIntervalMinutes
    }
    var presentationLiveActivityEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return false }
#endif
        return preferences.liveActivityEnabled
    }
    var presentationSalaryEnabled: Bool {
#if DEBUG
        if debugTimerSession != nil { return false }
#endif
        return preferences.salaryEnabled
    }
    var publishesLiveSurfaces: Bool {
#if DEBUG
        if debugTimerSession != nil { return false }
#endif
        return preferences.onboardingComplete && (followsSchedule || countdownStarted)
    }
    var followsSchedule: Bool { followsSchedule(at: .now) }
    var nativeSchedule: NativeWorkSchedule { nativeSchedule(at: .now) }
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
#if DEBUG
    var debugTimerSession: DebugTimerScenario.Session?
#endif

    init(defaults: UserDefaults, preferences: PreferencesStore, text: AppText) {
        self.defaults = defaults
        self.preferences = preferences
        self.text = text
        countdownStarted = defaults.bool(forKey: Key.countdownStarted)
        sessionTimeZoneIdentifier = defaults.string(forKey: Key.sessionTimeZone)
        sessionTimeZoneUntilMs = defaults.object(forKey: Key.sessionTimeZoneUntilMs) as? Double
        let storedForcedDate = defaults.string(forKey: Key.forcedWorkdayDate)
        forcedWorkdayDate = storedForcedDate ?? (defaults.bool(forKey: Key.legacyForceToday) ? Self.dayKey(for: .now) : nil)
        overtimeEndAtMs = defaults.object(forKey: Key.overtimeEndAtMs) as? Double
        earlyOffAtMs = defaults.object(forKey: Key.earlyOffAtMs) as? Double
        earlyOffShiftEndAtMs = defaults.object(forKey: Key.earlyOffShiftEndAtMs) as? Double
        earlyOffSnapshot = Self.decodeEarlyOffSnapshot(from: defaults)
        earlyStartAtMs = defaults.object(forKey: Key.earlyStartAtMs) as? Double
        earlyStartUntilMs = defaults.object(forKey: Key.earlyStartUntilMs) as? Double
        todayOverride = Self.decodeTodayOverride(from: defaults)

        // Before automatic scheduled countdowns, a completed shift cleared
        // `countdownStarted` at the following midnight. Arm existing configured
        // schedules once on upgrade so they do not need another manual start.
        // The marker preserves an explicit Stop after this migration.
        if defaults.object(forKey: Key.automaticCountdownMigrationCompleted) == nil {
            defaults.set(true, forKey: Key.automaticCountdownMigrationCompleted)
            if preferences.onboardingComplete, preferences.scheduleMode != .off {
                countdownStarted = true
            }
        }
    }

    func timerDate(from realDate: Date) -> Date {
#if DEBUG
        debugTimerSession?.date(for: realDate) ?? realDate
#else
        realDate
#endif
    }
    /// Salary-free hours for a schedule snapshot. Overtime and "now" stay off.
    func hoursConfiguration(at date: Date = .now) -> ScheduleHoursConfiguration {
        let input = rulesInput(at: date, using: .base)
        return ScheduleHoursConfiguration(
            startTime: input.startTime,
            endTime: input.endTime,
            workdays: input.workdays,
            schedule: input.schedule,
            breakStartTime: input.breakStartTime,
            breakDurationMinutes: input.breakDurationMinutes,
            extendedContent: input.extendedSchedule == nil ? nil : preferences.extendedScheduleContent,
            extendedSchedule: input.extendedSchedule
        )
    }
    func timeZoneIdentifierForWriting(startingNewSession: Bool = false) -> String {
        if startingNewSession, preferences.systemTimeZoneDiffersFromRecords {
            return TimeZone.current.identifier
        }
        return countdownTimeZoneIdentifier
    }
    func writingTimeZone(startingNewSession: Bool = false) -> TimeZone {
        TimeZone(identifier: timeZoneIdentifierForWriting(startingNewSession: startingNewSession))
            ?? preferences.recordsTimeZone
    }
    func lockSessionTimeZone(to identifier: String, at date: Date) {
        sessionTimeZoneIdentifier = identifier
        sessionTimeZoneUntilMs = snapshot(at: date)?.endAtMs
    }
    func clearSessionTimeZone() {
        sessionTimeZoneIdentifier = nil
        sessionTimeZoneUntilMs = nil
    }
    @discardableResult
    func expireSessionTimeZone(at date: Date) -> Bool {
        guard let until = sessionTimeZoneUntilMs,
              date.timeIntervalSince1970 * 1_000 >= until
        else { return false }
        clearSessionTimeZone()
        return true
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
    func scheduleStartMinutes(at date: Date) -> Int {
        if usesExtendedSchedule(at: date) {
            // The current shift's own start, not the fixed hours it replaces.
            let planned = ScheduleRules.snapshot(input: rulesInput(at: date, pinsEarlyStart: false))
            return minutes(from: planned.startDate, calendar: countdownCalendar)
        }
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.startMinutes
        }
        return preferences.startMinutes
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
    func snapshot(
        at date: Date = .now,
        startMinutes: Int? = nil,
        endMinutes: Int? = nil
    ) -> NativeShiftSnapshot? {
        var result = ScheduleRules.snapshot(input: rulesInput(
            at: date,
            startMinutes: startMinutes,
            endMinutes: endMinutes
        ))
        if startMinutes == nil, endMinutes == nil, projectsFutureFromBase(at: date) {
            result = result.withProjectedFuture(from: ScheduleRules.snapshot(input: rulesInput(at: date, using: .base)))
        }
        return result
    }
    /// Whether the rules follow the extended schedule at `date`. Today keeps
    /// the setting it had when a change was saved "from the next shift only".
    func usesExtendedSchedule(at date: Date = .now, using source: RulesScheduleSource = .effective) -> Bool {
#if DEBUG
        if debugTimerSession != nil { return false }
#endif
        if source == .effective, usesTodayOverride(at: date),
           let captured = todayOverride?.extendedScheduleEnabled {
            return captured
        }
        return preferences.isExtendedScheduleEnabled
    }
    func extendedSchedulePlan(at date: Date = .now, using source: RulesScheduleSource = .effective) -> ExtendedSchedulePlan? {
        guard usesExtendedSchedule(at: date, using: source) else { return nil }
        guard source == .effective, usesTodayOverride(at: date), let todayOverride else {
            return preferences.extendedSchedulePlan
        }
        let plan = todayOverride.extendedContent.map(preferences.extendedSchedulePlan(for:))
            ?? preferences.extendedSchedulePlan
        guard let plan, let day = todayOverride.extendedKeptDay else { return plan }
        return preferences.extendedSchedulePlan(plan, keeping: day)
    }
    /// Under an extended schedule an assigned day brings its own clock
    /// readings, which would replace the ones a caller or an early clock-in
    /// fixed for the current shift. Fix that shift's day instead; the rest of
    /// the roster resolves as before, and nothing is stored.
    private func pinningCurrentShift(
        _ input: NativeRulesInput,
        fixesStart: Bool,
        fixesEnd: Bool
    ) -> NativeRulesInput {
        guard let plan = input.extendedSchedule, fixesStart || fixesEnd else { return input }
        let planned = ScheduleRules.snapshot(input: input)
        let dayKey = Self.dayKey(for: planned.startDate, timeZone: countdownTimeZone)
        // A rest day already takes the fixed readings through its fallback hours.
        guard var hours = plan.hours(onDayKey: dayKey) else { return input }
        if fixesStart { hours.startTime = input.startTime }
        if fixesEnd { hours.endTime = input.endTime }
        var pinned = input
        pinned.extendedSchedule = plan.pinning(dayKey: dayKey, to: hours)
        return pinned
    }
    func rulesInput(
        at date: Date = .now,
        startMinutes: Int? = nil,
        endMinutes: Int? = nil,
        using source: RulesScheduleSource = .effective,
        pinsEarlyStart: Bool = true
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
                salaryType: preferences.salaryType.rawValue,
                monthlyWorkingDays: preferences.monthlyWorkingDays,
                annualBonusMonths: 0,
                forcedWorkdayStartMs: nil,
                timeZoneIdentifier: rulesTimeZoneIdentifier
            )
        }
#endif
        let applyOverride = source == .effective
        let earlyStart = pinsEarlyStart && applyOverride && startMinutes == nil && isStartedEarly(at: date)
        let start = startMinutes ?? (applyOverride ? effectiveStartMinutes(at: date) : self.preferences.startMinutes)
        let end = endMinutes ?? (applyOverride ? effectiveEndMinutes(at: date) : self.preferences.endMinutes)
        let lunchOn = applyOverride ? effectiveLunchEnabled(at: date) : preferences.lunchEnabled
        let input = NativeRulesInput(
            startTime: timeString(start),
            endTime: timeString(end),
            nowMs: date.timeIntervalSince1970 * 1_000,
            workdays: (applyOverride ? effectiveWorkdays(at: date) : preferences.workdays).sorted(),
            schedule: nativeSchedule(at: date, using: source),
            breakStartTime: lunchOn
                ? timeString(applyOverride ? effectiveLunchStartMinutes(at: date) : preferences.lunchStartMinutes)
                : nil,
            breakDurationMinutes: lunchOn
                ? (applyOverride ? effectiveLunchDurationMinutes(at: date) : preferences.lunchDurationMinutes)
                : 0,
            overtimeEndAtMs: applyOverride ? overtimeEndAtMs : nil,
            salaryAmount: preferences.salaryEnabled ? preferences.salaryAmount : "",
            salaryType: preferences.salaryType.rawValue,
            monthlyWorkingDays: preferences.monthlyWorkingDays,
            annualBonusMonths: preferences.annualBonusEnabled ? preferences.annualBonusMonths : 0,
            forcedWorkdayStartMs: applyOverride ? forcedWorkdayStartMs : nil,
            timeZoneIdentifier: rulesTimeZoneIdentifier,
            extendedSchedule: extendedSchedulePlan(at: date, using: source)
        )
        return pinningCurrentShift(
            input,
            fixesStart: startMinutes != nil || earlyStart,
            fixesEnd: endMinutes != nil
        )
    }
    /// Salary-free Watch input using the session's frozen early-finish snapshot.
    func watchProjection(at date: Date = .now) -> NativeWatchRulesProjection {
        let source = rulesInput(at: date)
        let input = NativeRulesInput(
            startTime: source.startTime, endTime: source.endTime, nowMs: source.nowMs,
            workdays: source.workdays, schedule: source.schedule,
            breakStartTime: source.breakStartTime, breakDurationMinutes: source.breakDurationMinutes,
            overtimeEndAtMs: source.overtimeEndAtMs,
            salaryAmount: "", salaryType: "", monthlyWorkingDays: 0, annualBonusMonths: 0,
            forcedWorkdayStartMs: source.forcedWorkdayStartMs,
            timeZoneIdentifier: source.timeZoneIdentifier,
            extendedSchedule: source.extendedSchedule
        )
        let live = shouldQuerySnapshot(at: date) ? snapshot(at: date) : nil
        let finishedAtMs = live.flatMap { isEndedEarly($0) ? earlyOffAtMs : nil }
        let suppliesSessionSnapshot = finishedAtMs != nil
            || (countdownStarted && effectiveScheduleMode(at: date) == .off)
        let frozen = (suppliesSessionSnapshot ? live : nil).map(clockOffSnapshot).map {
            NativeWatchCurrentShift(
                segments: $0.segments,
                plannedEndAtMs: $0.plannedEndAtMs,
                overtimeEndAtMs: $0.overtimeEndAtMs
            )
        }
        return ScheduleRules.watchProjection(
            input: input,
            scheduleConfigured: preferences.onboardingComplete,
            isRunning: countdownStarted,
            currentShift: frozen,
            finishedAtMs: finishedAtMs
        )
    }
    func rulesInput(
        applying change: ScheduleFieldChange,
        at date: Date
    ) -> NativeRulesInput {
        let start = change.startMinutes ?? preferences.startMinutes
        let end = change.endMinutes ?? preferences.endMinutes
        let lunchOn = change.lunchEnabled ?? preferences.lunchEnabled
        let lunchStart = change.lunchStartMinutes ?? preferences.lunchStartMinutes
        let lunchDuration = change.lunchDurationMinutes ?? preferences.lunchDurationMinutes
        return .init(
            startTime: timeString(start),
            endTime: timeString(end),
            nowMs: date.timeIntervalSince1970 * 1_000,
            workdays: (change.workdays ?? preferences.workdays).sorted(),
            schedule: nativeSchedule(applying: change, at: date),
            breakStartTime: lunchOn ? timeString(lunchStart) : nil,
            breakDurationMinutes: lunchOn ? lunchDuration : 0,
            // Applying a settings draft to today deliberately clears overtime.
            overtimeEndAtMs: nil,
            salaryAmount: preferences.salaryEnabled ? preferences.salaryAmount : "",
            salaryType: preferences.salaryType.rawValue,
            monthlyWorkingDays: preferences.monthlyWorkingDays,
            annualBonusMonths: preferences.annualBonusEnabled ? preferences.annualBonusMonths : 0,
            forcedWorkdayStartMs: forcedWorkdayStartMs,
            timeZoneIdentifier: rulesTimeZoneIdentifier,
            extendedSchedule: (change.extendedScheduleEnabled ?? preferences.isExtendedScheduleEnabled)
                ? preferences.extendedSchedulePlan(
                    for: change.extendedContent ?? preferences.extendedScheduleContent,
                    applying: change.rosterEdits
                )
                : nil
        )
    }
    /// Whether the explicit Save action needs the second choice about today.
    /// Swift assembles the current and proposed inputs; `ScheduleRules`
    /// decides. `scope` does not narrow the answer: a lunch edit revises
    /// today's row as much as an hours edit does.
    func shouldPromptApplyingToToday(
        _ change: ScheduleFieldChange,
        scope: ScheduleChangeScope,
        at date: Date = .now
    ) -> Bool {
        ScheduleRules.shouldPromptApplyToday(
            current: rulesInput(at: date),
            candidate: rulesInput(applying: change, at: date)
        )
    }
    func nativeSchedule(
        applying change: ScheduleFieldChange,
        at date: Date
    ) -> NativeWorkSchedule {
        let mode = change.scheduleMode ?? preferences.scheduleMode
        let weekType = change.alternatingWeekType ?? preferences.alternatingWeekType
        let weekendDay = change.alternatingWeekendWorkday ?? preferences.alternatingWeekendWorkday
        let weekWasReanchored = change.scheduleMode == .alternating
            || change.alternatingWeekType != nil
        let weekStart = weekWasReanchored
            ? PreferencesStore.startOfWeek(containing: date, timeZone: preferences.recordsTimeZone).timeIntervalSince1970 * 1_000
            : preferences.alternatingReferenceWeekStartMs

        let rotationWork = change.rotationWorkDays ?? preferences.rotationWorkDays
        let rotationRest = change.rotationRestDays ?? preferences.rotationRestDays
        var rotationAnchor = change.scheduleMode == .rotation
            ? preferences.recordsCalendar.startOfDay(for: date).timeIntervalSince1970 * 1_000
            : preferences.rotationAnchorMs
        if let cycleDay = change.rotationCycleDay {
            let length = max(2, rotationWork + rotationRest)
            let normalized = min(length, max(1, cycleDay))
            let today = preferences.recordsCalendar.startOfDay(for: date)
            if let anchor = preferences.recordsCalendar.date(
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
        let mode = applyOverride ? effectiveScheduleMode(at: date) : preferences.scheduleMode
        let weekType = applyOverride
            ? (todayOverride.flatMap { AlternatingWeekType(rawValue: $0.alternatingWeekType) } ?? preferences.alternatingWeekType)
            : preferences.alternatingWeekType
        let weekendDay = applyOverride
            ? (todayOverride?.alternatingWeekendWorkday ?? preferences.alternatingWeekendWorkday)
            : preferences.alternatingWeekendWorkday
        let weekStart = applyOverride
            ? (todayOverride?.alternatingReferenceWeekStartMs ?? preferences.alternatingReferenceWeekStartMs)
            : preferences.alternatingReferenceWeekStartMs
        let rotWork = applyOverride
            ? (todayOverride?.rotationWorkDays ?? preferences.rotationWorkDays)
            : preferences.rotationWorkDays
        let rotRest = applyOverride
            ? (todayOverride?.rotationRestDays ?? preferences.rotationRestDays)
            : preferences.rotationRestDays
        let rotAnchor = applyOverride
            ? (todayOverride?.rotationAnchorMs ?? preferences.rotationAnchorMs)
            : preferences.rotationAnchorMs
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
    func isStartedEarly(at date: Date = .now) -> Bool {
        guard let earlyStartAtMs, let earlyStartUntilMs else { return false }
        let nowMs = date.timeIntervalSince1970 * 1_000
        return nowMs >= earlyStartAtMs && nowMs < earlyStartUntilMs
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
        return text.t("clockedOffEarlyNote", values: ["time": text.formatTime(at)])
    }
    func earlyClockOffNote(at date: Date = .now) -> String? {
        guard let shift = snapshot(at: date) else { return nil }
        return earlyClockOffNote(for: shift)
    }
    func earlyClockInNote(at date: Date = .now) -> String? {
        guard isStartedEarly(at: date), let earlyStartAtMs else { return nil }
        let at = Date(timeIntervalSince1970: earlyStartAtMs / 1_000)
        return text.t("clockedInEarlyNote", values: ["time": text.formatTime(at)])
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
    func followsSchedule(at date: Date = .now) -> Bool {
#if DEBUG
        if let scenario = debugTimerSession?.scenario {
            return scenario.scheduleMode != .off
        }
#endif
        return preferences.onboardingComplete && effectiveScheduleMode(at: date) != .off
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
    func isLunchInsideShift(startMinutes: Int? = nil, endMinutes: Int? = nil) -> Bool {
        // Each shift type carries its own break, validated where it is edited.
        guard !usesExtendedSchedule() else { return true }
        return !preferences.lunchEnabled || ScheduleRules.validateBreak(input: rulesInput(
            startMinutes: startMinutes,
            endMinutes: endMinutes
        ))
    }
    func captureSchedule(untilMs: Double, at date: Date = .now) -> TodayScheduleOverride {
        var kept: KeptRosterDay?
        if usesExtendedSchedule(at: date), let plan = preferences.extendedSchedulePlan {
            let shift = ScheduleRules.snapshot(input: rulesInput(at: date, pinsEarlyStart: false))
            let dayKey = Self.dayKey(for: shift.startDate, timeZone: countdownTimeZone)
            kept = KeptRosterDay(dayKey: dayKey, shiftTypeID: plan.handSetDays[dayKey])
        }
        return .init(
            startMinutes: preferences.startMinutes,
            endMinutes: preferences.endMinutes,
            workdays: preferences.workdays.sorted(),
            scheduleMode: preferences.scheduleMode.rawValue,
            lunchEnabled: preferences.lunchEnabled,
            lunchStartMinutes: preferences.lunchStartMinutes,
            lunchDurationMinutes: preferences.lunchDurationMinutes,
            alternatingWeekType: preferences.alternatingWeekType.rawValue,
            alternatingWeekendWorkday: preferences.alternatingWeekendWorkday,
            alternatingReferenceWeekStartMs: preferences.alternatingReferenceWeekStartMs,
            rotationWorkDays: preferences.rotationWorkDays,
            rotationRestDays: preferences.rotationRestDays,
            rotationAnchorMs: preferences.rotationAnchorMs,
            untilMs: untilMs,
            extendedScheduleEnabled: preferences.isExtendedScheduleEnabled,
            extendedContent: preferences.extendedScheduleContent,
            extendedKeptDay: kept
        )
    }
    func overrideExpiry(at date: Date) -> Double? {
        let calendar = preferences.recordsCalendar
        if let shift = snapshot(at: date) {
            let inShiftContext = shift.isWorkday
                || isForcedWorkday(shift)
                || isEndedEarly(shift)
                || (countdownStarted && preferences.scheduleMode == .off)
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
    func effectiveScheduleMode(at date: Date = .now) -> WorkScheduleMode {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.scheduleMode }
#endif
        guard usesTodayOverride(at: date),
              let raw = todayOverride?.scheduleMode,
              let mode = WorkScheduleMode(rawValue: raw)
        else { return preferences.scheduleMode }
        return mode
    }
    func effectiveStartMinutes(at date: Date) -> Int {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.startMinutes }
#endif
        if isStartedEarly(at: date), let earlyStartAtMs {
            return minutes(from: Date(timeIntervalSince1970: earlyStartAtMs / 1_000), calendar: countdownCalendar)
        }
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.startMinutes
        }
        return preferences.startMinutes
    }
    func effectiveEndMinutes(at date: Date) -> Int {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.endMinutes }
#endif
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.endMinutes
        }
        return preferences.endMinutes
    }
    func effectiveWorkdays(at date: Date) -> Set<Int> {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.workdays }
#endif
        if usesTodayOverride(at: date), let todayOverride {
            return Set(todayOverride.workdays)
        }
        return preferences.workdays
    }
    func effectiveLunchEnabled(at date: Date) -> Bool {
#if DEBUG
        if debugTimerSession != nil { return true }
#endif
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.lunchEnabled
        }
        return preferences.lunchEnabled
    }
    func effectiveLunchStartMinutes(at date: Date) -> Int {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.lunchStartMinutes }
#endif
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.lunchStartMinutes
        }
        return preferences.lunchStartMinutes
    }
    func effectiveLunchDurationMinutes(at date: Date) -> Int {
#if DEBUG
        if let scenario = debugTimerSession?.scenario { return scenario.lunchDurationMinutes }
#endif
        if usesTodayOverride(at: date), let todayOverride {
            return todayOverride.lunchDurationMinutes
        }
        return preferences.lunchDurationMinutes
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
    /// Elapsed progress toward the next clock-in, supplied by the schedule
    /// rules so every iOS timer surface uses the same stable anchor.
    func countdownToClockInProgress(snapshot: NativeShiftSnapshot) -> Double {
        min(100, max(0, snapshot.countdownProgress))
    }
    func shareCopy(at date: Date = .now) -> String {
        let phase = visualPhase(at: date)
        guard let shift = shouldQuerySnapshot(at: date) ? snapshot(at: date) : nil else {
            return text.t("shareOffWorkText")
        }
        switch phase {
        case .completed, .unscheduled, .rest, .rulesError:
            return text.t("shareOffWorkText")
        case .lunch:
            return text.t("shareLunchText", values: [
                "time": text.formatRelativeDuration(shift.heroRemainingMs(at: date)),
            ])
        case .clockIn:
            return text.t("shareUntilStartText", values: [
                "time": text.formatRelativeDuration(countdownToClockInMs(snapshot: shift, at: date)),
            ])
        case .overtime, .running:
            return text.t("shareText", values: [
                "time": text.formatRelativeDuration(shift.heroRemainingMs(at: date)),
            ])
        }
    }
    func shareHeroText(at date: Date = .now) -> String {
        let phase = visualPhase(at: date)
        guard let shift = shouldQuerySnapshot(at: date) ? snapshot(at: date) : nil else {
            return text.t("shareDone")
        }
        if phase == .completed || isShiftComplete(shift) {
            return text.t("shareDone")
        }
        return text.formatRelativeDuration(shift.heroRemainingMs(at: date))
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
    func clearEarlyClockOffRecord() {
        earlyOffAtMs = nil
        earlyOffShiftEndAtMs = nil
        earlyOffSnapshot = nil
    }
    func clearEarlyClockInRecord() {
        earlyStartAtMs = nil
        earlyStartUntilMs = nil
    }
    func persistTodayOverride() {
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
    func persistEarlyOffSnapshot() {
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
    func timeString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
    func dateForMinutes(_ minutes: Int, base: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: base) ?? base
    }
    func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    func shareURL() -> URL {
        let compactStart = timeString(preferences.startMinutes).replacingOccurrences(of: ":", with: "")
        let compactEnd = timeString(preferences.endMinutes).replacingOccurrences(of: ":", with: "")
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
    ///   their own boundary — the Records tab, whose grids follow the preferences.locale's
    ///   first weekday — pass it so the summary covers the window on screen.
    ///   Omit it and the window comes from `period`.
    func periodSummary(
        _ period: String,
        asOf: Date,
        snapshot: NativeShiftSnapshot,
        periodStartMs: Double? = nil
    ) -> NativePeriodSummary? {
        let usesExtended = usesExtendedSchedule(at: asOf)
        guard usesExtended || effectiveScheduleMode(at: asOf) != .off else { return nil }
        var summaryWorkdays = effectiveWorkdays(at: asOf)
        var plan = usesExtended ? extendedSchedulePlan(at: asOf) : nil
        if isForcedWorkday(snapshot) {
            summaryWorkdays.insert(Calendar.current.component(.weekday, from: snapshot.startDate) - 1)
            // A rest day worked anyway counts under the roster too, with the
            // hours it was actually worked on.
            if let current = plan {
                let dayKey = Self.dayKey(for: snapshot.startDate, timeZone: countdownTimeZone)
                if current.hours(onDayKey: dayKey) == nil {
                    let input = rulesInput(at: asOf)
                    plan = current.pinning(dayKey: dayKey, to: ExtendedScheduleDayHours(
                        startTime: input.startTime,
                        endTime: input.endTime,
                        breakStartTime: input.breakStartTime,
                        breakDurationMinutes: input.breakDurationMinutes
                    ))
                }
            }
        }
        return SummaryRules.summarize(input: .init(
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
            timeZoneIdentifier: preferences.recordsTimeZoneIdentifier,
            extendedSchedule: plan
        ))
    }
    static func dayKey(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

extension ShiftSession {
    /// Only current/future roster rows and the last authored prior month are
    /// needed to reproduce forward carry-over. Salary and history stay here.
    func watchSchedule(at date: Date = .now, presentation: WatchPresentationV1) -> WatchScheduleV2 {
        let source = rulesInput(at: date, using: .base, pinsEarlyStart: false).scheduleInput
        let plan = source.extendedSchedule.map { plan in
            let today = extendedTodayKey(at: date)
            let month = String(today.prefix(7))
            let prior = plan.handSetDays.keys.map { String($0.prefix(7)) }.filter { $0 < month }.max()
            let days = plan.handSetDays.filter { key, _ in String(key.prefix(7)) >= month || String(key.prefix(7)) == prior }
            let used = Set(days.values).union(plan.rule?.days ?? []).union(
                plan.holidayRegionIdentifier?.isEmpty == false
                    ? plan.shiftTypes.filter { !$0.isArchived }.map(\.id) : []
            )
            return ExtendedSchedulePlan(shiftTypes: plan.shiftTypes.filter { used.contains($0.id) },
                                        rule: plan.rule, handSetDays: days,
                                        holidayRegionIdentifier: plan.holidayRegionIdentifier,
                                        holidayOverrides: plan.holidayRegionIdentifier.flatMap { region in
                                            region.isEmpty ? nil : HolidayCalendar.shared.workdayOverrides(regionIdentifier: region)
                                        },
                                        frozenShiftTypes: plan.frozenShiftTypes.filter { days[$0.key] == $0.value.id },
                                        fallsBackToBaseSchedule: plan.fallsBackToBaseSchedule,
                                        revision: plan.revision)
        }
        let input = ScheduleRuleInput(startTime: source.startTime, endTime: source.endTime, nowMs: 0,
                                      workdays: source.workdays, schedule: source.schedule,
                                      breakStartTime: source.breakStartTime, breakDurationMinutes: source.breakDurationMinutes,
                                      overtimeEndAtMs: nil, forcedWorkdayStartMs: nil,
                                      timeZoneIdentifier: source.timeZoneIdentifier, extendedSchedule: plan)
        let current = watchProjection(at: date).shift.map(WatchScheduleV2.shift)
        let zone = CivilZone(identifier: source.timeZoneIdentifier)
        let currentEnd = current.map { Double($0.overtimeEndAtMs ?? $0.plannedEndAtMs) } ?? source.nowMs
        // A saved "next shift only" change must keep the current absolute
        // shift, then resume the new base rule. Never carry today's override.
        let nextZone = CivilZone(identifier: source.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: plan))
        let next = nextZone.nextShiftTimeline(source.startTime, source.endTime, source.workdays, source.schedule,
                                              afterMs: max(source.nowMs, currentEnd), options: ShiftOptions(input))
        let until = min(zone.addCivilDaysMs(zone.startOfCivilDayMs(currentEnd), 1), next?.startAtMs ?? .infinity)
        return WatchScheduleV2(configuration: input,
                               automaticallyRuns: countdownStarted && source.schedule.mode != "off",
                               isConfigured: preferences.onboardingComplete,
                               currentShift: current, currentUntilMs: Int64(until),
                               resumeAtMs: current.flatMap { _ in next.map { Int64($0.startAtMs) } },
                               presentation: presentation)
    }
}
