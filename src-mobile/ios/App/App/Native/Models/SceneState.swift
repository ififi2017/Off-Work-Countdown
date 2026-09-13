import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case timer
    case focus
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
    case appleWatch
    case about

    var id: String { rawValue }
}

enum TimerSheet: String, Identifiable {
    case share
    case overtime

    var id: String { rawValue }
}


/// Navigation, presentations and drafts belong to one scene. The runtime may
/// share records and timers, but never shares an instance of this object.
@MainActor
@Observable
final class SceneState {
    private struct TimerContext: Equatable {
        let segments: [NativeShiftSegment]
        let startAtMs: Double
        let endAtMs: Double
        let plannedEndAtMs: Double
        let overtimeEndAtMs: Double?
        let countdownStarted: Bool
        let sessionID: UUID
        let marks: TimerDayMarks

        init(snapshot: NativeShiftSnapshot, session: ShiftSession, at date: Date) {
            segments = snapshot.segments
            startAtMs = snapshot.startAtMs
            endAtMs = snapshot.endAtMs
            plannedEndAtMs = snapshot.plannedEndAtMs
            overtimeEndAtMs = snapshot.overtimeEndAtMs
            countdownStarted = session.countdownStarted
            sessionID = session.sessionID
            marks = session.timerDayMarks(at: date, workday: snapshot.isWorkday)
        }
    }

    private enum TimerConfirmationKind: Equatable {
        case clockIn
        case clockOff
        case cancelManualTiming
    }

    private struct TimerConfirmation: Equatable {
        let id: UUID
        let kind: TimerConfirmationKind
        let context: TimerContext
        let expiresAt: Date
    }

    let id = UUID()
    var selectedTab: AppTab = .timer {
        didSet { defaults?.set(selectedTab.rawValue, forKey: "ios.native.selectedTab") }
    }
    @ObservationIgnored private let defaults: UserDefaults?
    let records: RecordsSceneState
    let focus: FocusSceneState
    var presentedRoute: AppRoute?
    var timerPath: [AppRoute] = []
    var focusPath: [AppRoute] = []
    var recordsPath: [RecordsRoute] = []
    var settingsPath: [AppRoute] = []
    var paywallSheet: PlusPaywallReason?
    var timerSheet: TimerSheet? {
        didSet { if timerSheet != nil { presentAddFocus = false } }
    }
    var pendingPlusAction: PlusPendingAction?
    var dayEditor: RecordDayEditDraft?
    var showsFirstRunCloudChoice = false
    var showsReleaseNotes = false

    func dismissReleaseNotes(preferences: PreferencesStore, plus: PlusEntitlement) {
        preferences.markReleaseNotesSeen()
        plus.markIntroSeen()
        showsReleaseNotes = false
    }

    func enableCloudSync(using recovery: RecoveryStore) async {
        if await recovery.enableCloudSyncFromSettings() == .needsDataReview {
            showsFirstRunCloudChoice = true
        }
    }
    var presentAddFocus = false {
        didSet { if presentAddFocus { timerSheet = nil } }
    }
    var scheduleSettingsDraft = ScheduleFieldChange() {
        didSet { if oldValue != scheduleSettingsDraft { scheduleDraftGeneration &+= 1 } }
    }
    var lunchSettingsDraft = ScheduleFieldChange() {
        didSet { if oldValue != lunchSettingsDraft { lunchDraftGeneration &+= 1 } }
    }
    private var scheduleDraftGeneration: UInt64 = 0
    private var lunchDraftGeneration: UInt64 = 0
    var focusActivityRequest: FocusActivityRequest?
    private(set) var focusActivityPresentationReady = false
    private var queuedFocusActivityRequest: FocusActivityRequest?
    private var dismissingFocusActivitySheetID: String?
    var hasFocusActivityPresentation: Bool {
        focusActivityRequest != nil || dismissingFocusActivitySheetID != nil
    }
    var reviewPromptPresented = false

    func presentReviewPromptIfEligible(using shifts: ShiftSessionStore, isBlocked: Bool) {
        guard !isBlocked, !reviewPromptPresented, shifts.claimReviewPromptIfEligible() else { return }
        reviewPromptPresented = true
    }

    var lifeSetupOfferPresented = false
    var lifeSetupEditorPresented = false
    var onboardingPage = 0
    var shareMood: ShareMood = .happy
    var draftStartMinutes: Int? {
        didSet { if oldValue != draftStartMinutes { timeDraftGeneration &+= 1 } }
    }
    var draftEndMinutes: Int? {
        didSet { if oldValue != draftEndMinutes { timeDraftGeneration &+= 1 } }
    }
    private var timeDraftGeneration: UInt64 = 0
    private var timerConfirmation: TimerConfirmation?
    private var expandedTimelineContext: TimerContext?

    func timerSheetBinding(_ sheet: TimerSheet) -> Binding<Bool> {
        Binding(
            get: { self.timerSheet == sheet },
            set: { presented in
                if presented { self.timerSheet = sheet }
                else if self.timerSheet == sheet { self.timerSheet = nil }
            }
        )
    }

    func displayedStartMinutes(using preferences: PreferencesStore) -> Int { draftStartMinutes ?? preferences.startMinutes }
    func displayedEndMinutes(using preferences: PreferencesStore) -> Int { draftEndMinutes ?? preferences.endMinutes }

    func setDisplayedStartMinutes(_ minutes: Int, using preferences: PreferencesStore) {
        draftStartMinutes = minutes == preferences.startMinutes ? nil : minutes
    }

    func setDisplayedEndMinutes(_ minutes: Int, using preferences: PreferencesStore) {
        draftEndMinutes = minutes == preferences.endMinutes ? nil : minutes
    }

    func clearTimeDraft() {
        draftStartMinutes = nil
        draftEndMinutes = nil
    }

    @discardableResult
    func commitScheduleDraft(
        _ scope: ScheduleChangeScope,
        decision: ScheduleChangeDecision,
        using shifts: ShiftSessionStore
    ) -> RecordCommand<Bool> {
        let submitted = scope == .schedule ? scheduleSettingsDraft : lunchSettingsDraft
        let generation = scope == .schedule ? scheduleDraftGeneration : lunchDraftGeneration
        return shifts.records.submitCommand { [self] in
            guard shifts.applyScheduleChange(submitted, decision: decision).synchronousResult else { return false }
            switch scope {
            case .schedule:
                if generation == scheduleDraftGeneration { scheduleSettingsDraft = ScheduleFieldChange() }
            case .lunch:
                if generation == lunchDraftGeneration { lunchSettingsDraft = ScheduleFieldChange() }
            }
            return true
        }
    }

    @discardableResult
    func commitDisplayedHours(using shifts: ShiftSessionStore) -> RecordCommand<Bool> {
        let start = draftStartMinutes, end = draftEndMinutes
        let generation = timeDraftGeneration
        return shifts.records.submitCommand { [self] in
            guard !shifts.records.blocksWrites else { return false }
            let current = shifts.preferences.currentSyncedPreferences()
            var submitted = current
            if let start { submitted.startMinutes = start }
            if let end { submitted.endMinutes = end }
            guard submitted.isValid else { return false }
            let accepted = submitted.hasSameSettings(as: current)
                || shifts.preferences.applyPreferences {
                    if let start { $0.startMinutes = start }
                    if let end { $0.endMinutes = end }
                }.synchronousResult
            if accepted, generation == timeDraftGeneration { clearTimeDraft() }
            return accepted
        }
    }

    @discardableResult
    func startCountdown(force: Bool = false, at date: Date = .now, using shifts: ShiftSessionStore) -> RecordCommand<Bool> {
        let start = draftStartMinutes, end = draftEndMinutes
        let generation = timeDraftGeneration
        return shifts.records.submitCommand { [self] in
            guard !shifts.records.blocksWrites else { return false }
            let current = shifts.preferences.currentSyncedPreferences()
            var submitted = current
            if let start { submitted.startMinutes = start }
            if let end { submitted.endMinutes = end }
            guard submitted.isValid else { return false }
            let draftIsFulfilled = submitted.hasSameSettings(as: current)
            let accepted = shifts.startCountdown(
                force: force, startMinutes: start, endMinutes: end, at: date
            ).synchronousResult
            let fulfilled = accepted || (draftIsFulfilled && shifts.session.countdownStarted)
            if fulfilled, generation == timeDraftGeneration { clearTimeDraft() }
            return fulfilled
        }
    }

    private func timerContext(at date: Date, using shifts: ShiftSessionStore) -> TimerContext? {
        shifts.session.snapshot(at: date).map { TimerContext(snapshot: $0, session: shifts.session, at: date) }
    }

    private func confirmationID(
        for kind: TimerConfirmationKind,
        at date: Date,
        using shifts: ShiftSessionStore
    ) -> UUID? {
        guard let timerConfirmation,
              timerConfirmation.kind == kind,
              date < timerConfirmation.expiresAt,
              timerContext(at: date, using: shifts) == timerConfirmation.context
        else { return nil }
        return timerConfirmation.id
    }

    func isClockInConfirmationArmed(at date: Date, using shifts: ShiftSessionStore) -> Bool {
        clockInConfirmationID(at: date, using: shifts) != nil
    }

    func isClockOffConfirmationArmed(at date: Date, using shifts: ShiftSessionStore) -> Bool {
        clockOffConfirmationID(at: date, using: shifts) != nil
    }

    func isCancelManualTimingConfirmationArmed(at date: Date, using shifts: ShiftSessionStore) -> Bool {
        cancelManualTimingConfirmationID(at: date, using: shifts) != nil
    }

    func clockInConfirmationID(at date: Date, using shifts: ShiftSessionStore) -> UUID? {
        confirmationID(for: .clockIn, at: date, using: shifts)
    }

    func clockOffConfirmationID(at date: Date, using shifts: ShiftSessionStore) -> UUID? {
        confirmationID(for: .clockOff, at: date, using: shifts)
    }

    func cancelManualTimingConfirmationID(at date: Date, using shifts: ShiftSessionStore) -> UUID? {
        confirmationID(for: .cancelManualTiming, at: date, using: shifts)
    }

    @discardableResult
    func requestClockInEarly(at date: Date = .now, using shifts: ShiftSessionStore) -> RecordCommand<Bool> {
        guard let snapshot = shifts.session.snapshot(at: date), snapshot.isBeforeStart(at: date) else { return .immediate(false) }
        let context = TimerContext(snapshot: snapshot, session: shifts.session, at: date)
        guard let confirmationID = confirmationID(for: .clockIn, at: date, using: shifts) else {
            timerConfirmation = TimerConfirmation(
                id: UUID(), kind: .clockIn, context: context, expiresAt: date.addingTimeInterval(5)
            )
            return .immediate(false)
        }
        return shifts.records.submitCommand { [self] in
            guard timerContext(at: date, using: shifts) == context,
                  shifts.clockInEarly(at: date).synchronousResult else { return false }
            if timerConfirmation?.id == confirmationID { timerConfirmation = nil }
            return true
        }
    }

    @discardableResult
    func requestClockOffEarly(at date: Date = .now, using shifts: ShiftSessionStore) -> RecordCommand<Bool> {
        guard let snapshot = shifts.session.snapshot(at: date), !snapshot.isBeforeStart(at: date) else { return .immediate(false) }
        let context = TimerContext(snapshot: snapshot, session: shifts.session, at: date)
        guard let confirmationID = confirmationID(for: .clockOff, at: date, using: shifts) else {
            timerConfirmation = TimerConfirmation(
                id: UUID(), kind: .clockOff, context: context, expiresAt: date.addingTimeInterval(5)
            )
            return .immediate(false)
        }
        return shifts.records.submitCommand { [self] in
            guard timerContext(at: date, using: shifts) == context,
                  shifts.clockOffEarly(at: date).synchronousResult else { return false }
            if timerConfirmation?.id == confirmationID { timerConfirmation = nil }
            return true
        }
    }

    @discardableResult
    func requestCancelManualTiming(at date: Date = .now, using shifts: ShiftSessionStore) -> RecordCommand<Bool> {
        guard let context = timerContext(at: date, using: shifts) else { return .immediate(false) }
        guard let confirmationID = confirmationID(for: .cancelManualTiming, at: date, using: shifts) else {
            timerConfirmation = TimerConfirmation(
                id: UUID(), kind: .cancelManualTiming, context: context, expiresAt: date.addingTimeInterval(5)
            )
            return .immediate(false)
        }
        return shifts.records.submitCommand { [self] in
            guard timerContext(at: date, using: shifts) == context,
                  shifts.cancelManualTiming().synchronousResult else { return false }
            if timerConfirmation?.id == confirmationID { timerConfirmation = nil }
            return true
        }
    }

    func cancelTimerConfirmation(id: UUID) {
        guard timerConfirmation?.id == id else { return }
        timerConfirmation = nil
    }

    func timelineExpanded(for snapshot: NativeShiftSnapshot, at date: Date, session: ShiftSession) -> Bool {
        expandedTimelineContext == TimerContext(snapshot: snapshot, session: session, at: date)
    }

    func timelineExpandedBinding(
        for snapshot: NativeShiftSnapshot,
        at date: Date,
        session: ShiftSession
    ) -> Binding<Bool> {
        let context = TimerContext(snapshot: snapshot, session: session, at: date)
        return Binding(
            get: { self.expandedTimelineContext == context },
            set: { self.expandedTimelineContext = $0 ? context : nil }
        )
    }

    func setupSnapshot(at date: Date = .now, using shifts: ShiftSessionStore) -> NativeShiftSnapshot? {
        shifts.session.snapshot(
            at: date,
            startMinutes: displayedStartMinutes(using: shifts.preferences),
            endMinutes: displayedEndMinutes(using: shifts.preferences)
        )
    }

    func isLunchInsideShift(using shifts: ShiftSessionStore) -> Bool {
        shifts.session.isLunchInsideShift(
            startMinutes: displayedStartMinutes(using: shifts.preferences),
            endMinutes: displayedEndMinutes(using: shifts.preferences)
        )
    }

    var activePath: [AppRoute] {
        get {
            switch selectedTab {
            case .timer: timerPath
            case .focus: focusPath
            case .records: []
            case .settings: settingsPath
            }
        }
        set {
            switch selectedTab {
            case .timer: timerPath = newValue
            case .focus: focusPath = newValue
            case .records: break
            case .settings: settingsPath = newValue
            }
        }
    }

    init(defaults: UserDefaults? = nil, recordsScale: RecordsScale = .month, showsReleaseNotes: Bool = false) {
        self.defaults = defaults
        self.showsReleaseNotes = showsReleaseNotes
        records = RecordsSceneState(scale: recordsScale, defaults: defaults)
        focus = FocusSceneState(defaults: defaults)
        guard let defaults else { return }
        selectedTab = AppTab(rawValue: defaults.string(forKey: "ios.native.selectedTab") ?? "") ?? .timer
#if DEBUG
        if let route = AppRoute(rawValue: defaults.string(forKey: "ios.native.qaRoute") ?? "") {
            if route == .focus || route == .focusPlan { openFocusTab() }
            else { selectedTab = .settings; settingsPath = [route] }
        }
        if let route = RecordsRoute.debugRoute(defaults.string(forKey: "ios.native.qaRecordsRoute")) {
            selectedTab = .records
            recordsPath = [route]
        }
        if RecordsScale(rawValue: defaults.string(forKey: "ios.native.qaRecordsScale") ?? "") != nil {
            selectedTab = .records
        }
        if DebugTimerScenario(rawValue: defaults.string(forKey: "ios.native.qaDebugScenario") ?? "") != nil {
            openTimer()
        }
        for key in ["ios.native.qaRoute", "ios.native.qaRecordsRoute", "ios.native.qaDebugScenario"] {
            defaults.removeObject(forKey: key)
        }
#endif
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme == "offworkcountdown" else { return }
        if url.host == "timer" {
            settingsPath.removeAll()
            timerPath.removeAll()
            selectedTab = .timer
            presentedRoute = nil
            return
        }
        guard let route = AppRoute(rawValue: url.host ?? "") else { return }
        if route == .focus || route == .focusPlan {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let action = items.first(where: { $0.name == "action" })?.value.flatMap(FocusActivityRequest.Action.init(rawValue:)),
               let start = items.first(where: { $0.name == "start" })?.value.flatMap(Int64.init) {
                requestFocusActivityConfirmation(action, startAtMs: start)
                return
            }
            openFocusTab()
            return
        }
        settingsPath.removeAll()
        selectedTab = .settings
        presentedRoute = route
    }

    func openTimer() {
        presentedRoute = nil
        timerPath.removeAll()
        focusPath.removeAll()
        recordsPath.removeAll()
        settingsPath.removeAll()
        selectedTab = .timer
    }

    func openFocusTab() {
        focusPath.removeAll()
        presentedRoute = nil
        selectedTab = .focus
    }

    func requestFocusActivityConfirmation(_ action: FocusActivityRequest.Action, startAtMs: Int64) {
        let request = FocusActivityRequest(action: action, startAtMs: startAtMs)
        if focusActivityRequest != nil || dismissingFocusActivitySheetID != nil {
            queuedFocusActivityRequest = request
            return
        }
        focusActivityRequest = request
        focusActivityPresentationReady = false
    }

    func activateFocusActivityPresentationIfPossible(isBlocked: Bool) {
        guard !isBlocked, focusActivityRequest != nil, !focusActivityPresentationReady else { return }
        if selectedTab != .focus { openFocusTab() }
        focusActivityPresentationReady = true
    }

    func beginDismissingFocusActivitySheet() -> String? {
        guard focusActivityPresentationReady,
              let request = focusActivityRequest,
              request.action == .addPomodoros else { return nil }
        dismissingFocusActivitySheetID = request.id
        focusActivityRequest = nil
        focusActivityPresentationReady = false
        return request.id
    }

    func finishDismissingFocusActivitySheet(id: String) {
        guard dismissingFocusActivitySheetID == id else { return }
        dismissingFocusActivitySheetID = nil
        focusActivityRequest = queuedFocusActivityRequest
        queuedFocusActivityRequest = nil
        focusActivityPresentationReady = false
    }

    func dismissFocusActivityAlert() {
        guard focusActivityRequest?.action == .stop else { return }
        focusActivityRequest = queuedFocusActivityRequest
        queuedFocusActivityRequest = nil
        focusActivityPresentationReady = false
    }

    func presentLifeSetupOffer() {
        lifeSetupOfferPresented = true
    }

    func consumeLifeSetupOffer(preferences: PreferencesStore, opensEditor: Bool) {
        preferences.lifeSetupPromptDismissed = true
        lifeSetupOfferPresented = false
        lifeSetupEditorPresented = opensEditor
    }

    @discardableResult
    func startFocus(task: FocusTask, pomodoros: Int? = nil, using focus: FocusStore) -> RecordCommand<Bool> {
        guard focus.plus.isAuthorized else {
            pendingPlusAction = .startFocus(taskID: task.id, pomodoros: pomodoros)
            paywallSheet = .focus
            return .immediate(false)
        }
        if let pomodoros {
            return focus.updateAndStartFocusTaskAuthorized(taskID: task.id, pomodoros: pomodoros)
        }
        return focus.startFocus(task: task)
    }

    func requestEnableCloudSync(using recovery: RecoveryStore) {
        if recovery.plus.isAuthorized {
            Task { await enableCloudSync(using: recovery) }
        } else {
            pendingPlusAction = .enableSync
            paywallSheet = .sync
        }
    }

    /// The presenting scene consumes an action once, after the paywall closes.
    /// A later purchase cannot replay a previously declined action.
    func settlePaywallDismissal(plus: PlusEntitlement) -> PlusPendingAction? {
        let action = pendingPlusAction
        pendingPlusAction = nil
        guard plus.isAuthorized else { return nil }
        plus.markIntroSeen()
        paywallSheet = nil
        return action
    }

    func performPendingPlusAction(
        _ action: PlusPendingAction, focus: FocusStore, actions: RecordsActions,
        queries: RecordsQueries, recovery: RecoveryStore
    ) {
        switch action {
        case .historyEdit(let dayKey):
            openDayEditor(dayKey: dayKey, actions: actions, queries: queries)
        case .startFocus(let taskID, let pomodoros):
            if let pomodoros {
                _ = focus.updateAndStartFocusTaskAuthorized(taskID: taskID, pomodoros: pomodoros)
            } else if let task = actions.records.state.focusTasks.first(where: { $0.id == taskID }) {
                _ = focus.startFocusAuthorized(task)
            }
        case .addFocusTask(let title, let pomodoros, let icon, let isFavorite):
            focus.addFocusTaskAuthorized(
                title: title,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
        case .addFocusTaskInNextBlock(let title, let pomodoros, let icon, let isFavorite):
            _ = focus.createFocusTaskInNextEmptyBlock(
                title: title,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
        case .addAndStartFocus(let title, let pomodoros, let icon, let isFavorite):
            _ = focus.addAndStartFocusTaskAuthorized(
                title: title,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
        case .presentAddFocus:
            presentAddFocus = true
        case .openFocus:
            openFocusTab()
        case .enableCycleEndSummaryNotifications:
            actions.preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = true }
        case .enableSync:
            Task { await enableCloudSync(using: recovery) }
        }
    }

    func setCycleEndSummaryNotifications(
        _ enabled: Bool, preferences: PreferencesStore, plus: PlusEntitlement
    ) {
        if !enabled || plus.isAuthorized {
            preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = enabled }
        } else {
            pendingPlusAction = .enableCycleEndSummaryNotifications
            paywallSheet = .cycleEndSummaryNotifications
        }
    }

    func openDayEditor(dayKey: String, actions: RecordsActions, queries: RecordsQueries) {
        guard RecordJSON.date(fromDayKey: dayKey, calendar: actions.preferences.recordsCalendar) != nil else { return }
        if !RecordsAccess.allows(.recordsPageEdit, authorized: actions.plus.isAuthorized) {
            pendingPlusAction = .historyEdit(dayKey: dayKey)
            paywallSheet = .historyEdit
            return
        }
        guard actions.canMutateRecordedDay(dayKey) else { return }
        if dayEditor?.dayKey != dayKey {
            dayEditor = RecordDayEditDraft(dayKey: dayKey, queries: queries)
        }
    }

    func beginAddFocus(using focus: FocusStore) {
        if focus.plus.isAuthorized {
            presentAddFocus = true
        } else {
            pendingPlusAction = .presentAddFocus
            paywallSheet = .focus
        }
    }

    func addScheduledFocusTask(
        title: String,
        slot: FocusScheduleSlot,
        icon: FocusTaskIcon = .focus,
        isFavorite: Bool = false,
        using focus: FocusStore
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if focus.plus.isAuthorized {
            _ = focus.addFocusTaskAuthorized(
                title: trimmed,
                pomodoros: 1,
                plannedFor: slot.shiftAnchor,
                scheduledStartAt: slot.start,
                icon: icon,
                isFavorite: isFavorite
            )
        } else {
            pendingPlusAction = .addFocusTaskInNextBlock(
                title: trimmed,
                pomodoros: 1,
                icon: icon,
                isFavorite: isFavorite
            )
            paywallSheet = .focus
        }
    }

    @discardableResult
    func addAndStartFocusTask(
        title: String,
        pomodoros: Int = 1,
        icon: FocusTaskIcon = .focus,
        isFavorite: Bool = false,
        using focus: FocusStore
    ) -> RecordCommand<Bool> {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .immediate(false) }
        if focus.plus.isAuthorized {
            return focus.addAndStartFocusTaskAuthorized(
                title: trimmed,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
        } else {
            pendingPlusAction = .addAndStartFocus(
                title: trimmed,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
            paywallSheet = .focus
            return .immediate(false)
        }
    }

    func addFocusTask(
        title: String,
        pomodoros: Int,
        icon: FocusTaskIcon = .focus,
        isFavorite: Bool = false,
        using focus: FocusStore
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if focus.plus.isAuthorized {
            focus.addFocusTaskAuthorized(
                title: trimmed,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
        } else {
            pendingPlusAction = .addFocusTask(
                title: trimmed,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            )
            paywallSheet = .focus
        }
    }

#if DEBUG
    func qaSurfaceName(_ visibleSurface: String? = nil, onboardingComplete: Bool = true, hasSeenPlusIntro: Bool = true) -> String {
        if !onboardingComplete { return "onboarding" }
        if !hasSeenPlusIntro { return "plus-intro" }
        if paywallSheet != nil { return "paywall" }
        return visibleSurface ?? selectedTab.rawValue
    }

#endif

    // A mounted feature is already past the root's entry gates. The root
    // supplies its actual gate values while it presents onboarding or Plus.
    func writeQASurfaceMarker(_ visibleSurface: String? = nil, onboardingComplete: Bool = true, hasSeenPlusIntro: Bool = true) {
#if DEBUG
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let url = caches?.appendingPathComponent("qa-surface.txt") else { return }
        try? qaSurfaceName(visibleSurface, onboardingComplete: onboardingComplete, hasSeenPlusIntro: hasSeenPlusIntro)
            .write(to: url, atomically: true, encoding: .utf8)
#endif
    }
}

#if DEBUG
extension RecordsRoute {
    static func debugRoute(_ raw: String?) -> RecordsRoute? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count > 1 ? parts[1] : nil) {
        case ("allRecords", _): return .allRecords
        case ("conflicts", _): return .conflictCenter
        case ("day", let key?): return .day(key)
        default: return nil
        }
    }
}
#endif
