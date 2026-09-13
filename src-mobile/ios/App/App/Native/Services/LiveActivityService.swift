@preconcurrency import ActivityKit
import Foundation

/// ActivityKit request is synchronous IPC. On device, scheduling a template’s
/// future rounds blocked MainActor for 3.17 s. Keep the existing serial lifecycle
/// queue, but await this blocking system call on the concurrent executor.
nonisolated enum LiveActivityRequestWorker {
    @concurrent
    static func request(
        attributes: OffWorkActivityAttributes,
        content: ActivityContent<OffWorkActivityAttributes.ContentState>,
        alertConfiguration: AlertConfiguration? = nil,
        start: Date? = nil
    ) async throws -> String {
        try LaunchTrace.interval("activityRequest") {
            let activity: Activity<OffWorkActivityAttributes>
            if let alertConfiguration, let start {
                activity = try Activity.request(attributes: attributes, content: content, pushType: nil,
                    style: .standard, alertConfiguration: alertConfiguration, start: start)
            } else {
                activity = try Activity.request(attributes: attributes, content: content, pushType: nil, style: .standard)
            }
            return String(describing: activity.activityState)
        }
    }
}

enum LiveActivitySurface: String, Codable, Equatable, Sendable {
    case work
    case focus
    case shortBreak
    case longBreak

    init(sessionKind: FocusSessionKind) {
        switch sessionKind {
        case .focus: self = .focus
        case .shortBreak: self = .shortBreak
        case .longBreak: self = .longBreak
        }
    }
}

/// Pure priority decision, deliberately independent of ActivityKit. A work
/// countdown uses the slot only when no focus or recovery phase is running.
/// An ongoing focus chain keeps priority even near clock-off.
struct LiveActivityDecision: Equatable, Sendable {
    var surface: LiveActivitySurface
    var endAt: Date

    static func choose(
        workEndAt: Date?,
        workDisplayStartsAt: Date?,
        focusSession: FocusSession?,
        now: Date
    ) -> LiveActivityDecision? {
        if let focusSession, focusSession.endedAt == nil, focusSession.plannedEndAt > now {
            return .init(surface: .init(sessionKind: focusSession.kind), endAt: focusSession.plannedEndAt)
        }
        if let workEndAt, let workDisplayStartsAt,
           now >= workDisplayStartsAt, now < workEndAt {
            return .init(surface: .work, endAt: workEndAt)
        }
        return nil
    }
}

/// ActivityKit-facing identity reduced to values we can exercise in ordinary
/// unit tests. Focus and recovery are phases of one ongoing activity, so a
/// phase/end-time change must update its content rather than request another.
struct LiveActivityIdentity: Equatable, Sendable {
    var plannedEndAtMs: Int64
    var surface: LiveActivitySurface

    func canUpdate(to desired: Self) -> Bool {
        self == desired || (surface != .work && desired.surface != .work)
    }
}

enum LiveActivityReconcileAction: Equatable, Sendable {
    case updateExisting(duplicates: Int)
    case replace
}

enum LiveActivityReconciler {
    static func action(
        existing: [LiveActivityIdentity],
        desired: LiveActivityIdentity
    ) -> LiveActivityReconcileAction {
        let matching = existing.filter { $0.canUpdate(to: desired) }
        return matching.isEmpty ? .replace : .updateExisting(duplicates: matching.count - 1)
    }

    /// A delayed completion may act only while its generation remains current.
    static func completionMayRun(scheduledGeneration: Int, currentGeneration: Int) -> Bool {
        scheduledGeneration == currentGeneration
    }
}

enum FocusLiveActivityWakePlan: Equatable, Sendable {
    case completionOnly
    case workHandoffAtCompletion
    case completionThenWorkHandoff

    static func make(
        focusEndsAt: Date,
        workDisplayStartsAt: Date?,
        now: Date
    ) -> Self {
        guard let workDisplayStartsAt else { return .completionOnly }
        return workDisplayStartsAt <= focusEndsAt
            ? .workHandoffAtCompletion
            : .completionThenWorkHandoff
    }
}

/// Timekeeping for the focus-to-work handoff. The clock is injectable so the
/// delayed transition can be exercised without waiting for wall-clock time or
/// touching ActivityKit in tests.
nonisolated struct LiveActivitySchedulingClock: Sendable {
    var now: @MainActor @Sendable () -> Date
    var sleep: @MainActor @Sendable (TimeInterval) async -> Bool

    @MainActor static let system = Self(
        now: { .now },
        sleep: { interval in
            do {
                try await Task.sleep(for: .seconds(max(0, interval)))
                return !Task.isCancelled
            } catch {
                return false
            }
        }
    )
}

/// Owns the one delayed re-arbitration while focus occupies the Lock Screen.
/// This is distinct from activity completion: clock-off can take over only
/// after the focus chain finishes, never at the start of its display window.
@MainActor
final class LiveActivityPriorityTransitionService {
    private let clock: LiveActivitySchedulingClock
    private var task: Task<Void, Never>?
    private var generation = 0

    private(set) var scheduledAt: Date?

    init(clock: LiveActivitySchedulingClock) {
        self.clock = clock
    }

    @discardableResult
    func schedule(at date: Date, action: @escaping () async -> Void) -> Task<Void, Never> {
        cancel()
        generation &+= 1
        let scheduledGeneration = generation
        scheduledAt = date
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = max(0, date.timeIntervalSince(self.clock.now()))
            guard await self.clock.sleep(delay), !Task.isCancelled,
                  scheduledGeneration == self.generation
            else { return }
            self.task = nil
            self.scheduledAt = nil
            await action()
        }
        self.task = task
        return task
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        scheduledAt = nil
    }
}

@MainActor
@Observable
final class LiveActivityService {
    private(set) var lastError: String?
    private var completionTask: Task<Void, Never>?
    private let schedulingClock: LiveActivitySchedulingClock
    private let focusPriorityTransition: LiveActivityPriorityTransitionService

    /// Which call owns the activity right now.
    ///
    /// `end` and `reschedule` both suspend while ActivityKit works, and the
    /// countdown can be stopped and restarted across those suspensions. Without
    /// a token the interleaving below lost the new session's activity outright:
    ///
    /// 1. the stop task passes its cancellation check and starts ending;
    /// 2. `activity.end()` suspends, and the user restarts;
    /// 3. the new task finds the not-yet-ended activity and updates it;
    /// 4. the old `end()` lands, and the restarted session has nothing.
    ///
    /// Cancelling the enclosing `Task` cannot fix this on its own — cancellation
    /// is cooperative and the `end()` was already in flight. Every awaited step
    /// re-checks that it is still the owner instead.
    private var lifecycleGeneration = 0

    /// The tail of the ActivityKit work queue.
    ///
    /// The generation alone could not close the stop-then-restart hole. Every
    /// re-read of `activityState` is a time-of-check that an `end()` already in
    /// flight can invalidate at its time-of-use, and ActivityKit documents no
    /// ordering between `update` and `end` — only that an ended activity
    /// ignores updates. So the operations are serialised instead: while one
    /// runs, no other touches the same activity, and the check-then-act windows
    /// stop existing rather than getting smaller.
    ///
    /// The generation still earns its place on top of this. Serialising decides
    /// *when* queued work runs, not whether it is still wanted — a teardown
    /// queued before a restart would otherwise run afterwards and undo it.
    private var pendingOperation: Task<Void, Never>?

    init() {
        let clock = LiveActivitySchedulingClock.system
        self.schedulingClock = clock
        self.focusPriorityTransition = .init(clock: clock)
    }

    init(schedulingClock: LiveActivitySchedulingClock) {
        self.schedulingClock = schedulingClock
        self.focusPriorityTransition = .init(clock: schedulingClock)
    }

    /// The task, not the phase. `timerLabel` says "Focus"; this says what you
    /// are focusing on, which is what the canvas made the subject.
    static func focusTaskTitle(
        session: FocusSession,
        surface: LiveActivitySurface,
        shifts: ShiftSessionStore
    ) -> String? {
        guard surface == .focus else { return nil }
        return session.taskID
            .flatMap { id in shifts.records.state.focusTasks.first(where: { $0.id == id }) }?
            .title
    }

    static func focusTaskIcon(
        session: FocusSession,
        surface: LiveActivitySurface,
        shifts: ShiftSessionStore
    ) -> String {
        guard surface == .focus else { return "cup.and.saucer.fill" }
        let icon = session.taskID
            .flatMap { id in shifts.records.state.focusTasks.first(where: { $0.id == id }) }?
            .icon
        return (icon ?? .focus).systemName
    }

    /// Turns the chain into the wire form the extension walks on its own.
    ///
    /// Every string is finished here. The extension renders whichever leg the
    /// clock is in, hours after the app last ran, and it cannot compose a
    /// sentence in the user's language at that point.
    static func focusLegs(
        _ chain: [FocusChainLeg],
        shifts: ShiftSessionStore
    ) -> [OffWorkActivityAttributes.ContentState.Leg] {
        chain.indices.map { index in
            let leg = chain[index]
            let following = index + 1 < chain.count ? chain[index + 1] : nil
            return .init(
                startAtMs: Int64(leg.start.timeIntervalSince1970 * 1_000),
                endAtMs: Int64(leg.end.timeIntervalSince1970 * 1_000),
                surface: LiveActivitySurface(sessionKind: leg.kind).rawValue,
                label: legLabel(leg, shifts: shifts),
                title: leg.taskTitle,
                icon: leg.icon?.systemName ?? "cup.and.saucer.fill",
                detail: legDetail(leg, shifts: shifts),
                finishNote: leg.taskFinishAt.map { finish in
                    shifts.text.t("focusActivityTaskDone", values: ["time": shifts.text.formatTime(finish)])
                },
                nextNote: following.map { legNextNote($0, shifts: shifts) },
                isPreview: leg.role == .upNext
            )
        }
    }

    private static func legLabel(_ leg: FocusChainLeg, shifts: ShiftSessionStore) -> String {
        if leg.role == .upNext { return shifts.text.t("focusNextBlock") }
        switch leg.kind {
        case .focus: return shifts.text.t("focusTitle")
        case .shortBreak: return shifts.text.t("focusShortBreak")
        case .longBreak: return shifts.text.t("focusLongBreak")
        }
    }

    private static func legDetail(_ leg: FocusChainLeg, shifts: ShiftSessionStore) -> String? {
        guard let index = leg.pomodoroIndex, let total = leg.pomodoroTotal else { return nil }
        return shifts.text.t("focusActivityPomodoro", values: [
            "index": shifts.text.formatCount(index),
            "total": shifts.text.formatCount(total),
        ])
    }

    /// Read from the leg that follows, so a phase always says what it hands
    /// over to — the one thing the cadence knows and the user does not.
    private static func legNextNote(_ next: FocusChainLeg, shifts: ShiftSessionStore) -> String {
        switch next.kind {
        case .shortBreak, .longBreak:
            let minutes = max(1, Int(next.end.timeIntervalSince(next.start) / 60))
            return shifts.text.t("focusActivityThenBreak", values: ["count": shifts.text.formatCount(minutes)])
        case .focus:
            return shifts.text.t("focusActivityNextUp", values: [
                "task": next.taskTitle ?? shifts.text.t("focusTitle"),
                "time": shifts.text.formatTime(next.start),
            ])
        }
    }

    /// A fixed clock-off time stays truthful while the app is suspended,
    /// including across lunch. Never format a ticking duration into a payload.
    static func shiftEndAtMs(shifts: ShiftSessionStore, at now: Date) -> Int64? {
        guard let snapshot = shifts.session.snapshot(at: now), snapshot.remainingMs > 0 else { return nil }
        return Int64(snapshot.endAtMs)
    }

    private func focusCopy(for surface: LiveActivitySurface, shifts: ShiftSessionStore) -> (
        title: String, caption: String, completedCaption: String, completedNote: String
    ) {
        switch surface {
        case .focus:
            return (
                shifts.text.t("focusTitle"), shifts.text.t("focusTitle"),
                shifts.text.t("focusPhaseComplete"), shifts.text.t("focusEndedNaturally")
            )
        case .shortBreak:
            return (
                shifts.text.t("focusShortBreak"), shifts.text.t("focusShortBreak"),
                shifts.text.t("focusPhaseComplete"), shifts.text.t("focusNextFocusBody")
            )
        case .longBreak:
            return (
                shifts.text.t("focusLongBreak"), shifts.text.t("focusLongBreak"),
                shifts.text.t("focusPhaseComplete"), shifts.text.t("focusNextFocusBody")
            )
        case .work:
            return (
                OWCBrand.shortName, shifts.text.t("timeLeftCaption"),
                shifts.text.t("offWorkTime"), shifts.text.t("offWorkWellDone")
            )
        }
    }

    /// Pending focus starts belong to the system scheduler, not to teardown of
    /// the currently visible phase. They are reconciled separately below.
    private var currentActivities: [Activity<OffWorkActivityAttributes>] {
        Activity<OffWorkActivityAttributes>.activities.filter {
            $0.activityState != .pending || $0.content.state.scheduledSessionID == nil
        }
    }
    private var queuedFocus: [FocusSession] = []

    /// Runs after everything already queued, and is itself awaited, so callers
    /// keep the straight-line semantics they had before.
    func reschedule(shifts: ShiftSessionStore, now: Date = .now) async {
        let previous = pendingOperation
        let task = Task { @MainActor in
            await previous?.value
            let scheduled = await shifts.focus.refreshScheduledFocus(at: now).value
            self.queuedFocus = shifts.preferences.focusLiveActivityEnabled ? scheduled : []
            await self.performReschedule(shifts: shifts, now: now)
            guard shifts.records.persistenceError == nil,
                  shifts.records.durableRevision == shifts.records.revision else { return }
            await self.reconcileScheduledActivities(shifts: shifts, now: now)
        }
        pendingOperation = task
        await task.value
    }

    func endAll() async {
        let previous = pendingOperation
        let task = Task { @MainActor in
            await previous?.value
            await self.performEndAll()
            for activity in Activity<OffWorkActivityAttributes>.activities where activity.activityState == .pending {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        pendingOperation = task
        await task.value
    }

    private func performReschedule(shifts: ShiftSessionStore, now: Date = .now) async {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        // A foreground reschedule supersedes any delayed handoff based on the
        // previous shift or focus session.
        focusPriorityTransition.cancel()
        _ = await shifts.focus.finishElapsedFocusSession(at: now).value
        do { try await shifts.records.flush() }
        catch { return }
        guard generation == lifecycleGeneration else { return }
        let focusSession = shifts.preferences.focusLiveActivityEnabled ? shifts.focus.activeFocusSession() : nil
        guard shifts.session.publishesLiveSurfaces || focusSession != nil else {
            recordDebugStatus("countdown-not-started")
            await performEndAll()
            return
        }
        guard shifts.preferences.liveActivityEnabled || focusSession != nil else {
            recordDebugStatus("disabled-in-app")
            await performEndAll()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            recordDebugStatus("disabled-by-system")
            await performEndAll()
            return
        }
        guard let snapshot = shifts.session.snapshot(at: now) else {
            if let decision = LiveActivityDecision.choose(
                workEndAt: nil,
                workDisplayStartsAt: nil,
                focusSession: focusSession,
                now: now
            ) {
                await performFocusReschedule(
                    shifts: shifts,
                    session: focusSession!,
                    decision: decision,
                    workDisplayStartsAt: nil,
                    now: now,
                    generation: generation
                )
                return
            }
            recordDebugStatus("no-active-shift")
            await performEndAll()
            return
        }
        let scheduledStart = snapshot.plannedEndDate.addingTimeInterval(Double(-shifts.preferences.liveActivityLeadMinutes * 60))
        let workEligible = shifts.preferences.liveActivityEnabled && shifts.session.publishesLiveSurfaces
            && !shifts.session.isEndedEarly(snapshot)
            && (snapshot.isWorkday || shifts.session.isForcedWorkday(snapshot))
            && !snapshot.isBeforeStart(at: now)
            && snapshot.remainingMs > 0
        let decision = LiveActivityDecision.choose(
            workEndAt: workEligible ? snapshot.endDate : nil,
            workDisplayStartsAt: workEligible ? scheduledStart : nil,
            focusSession: focusSession,
            now: now
        )
        if let decision, decision.surface != .work, let focusSession {
            await performFocusReschedule(
                shifts: shifts,
                session: focusSession,
                decision: decision,
                workDisplayStartsAt: workEligible ? scheduledStart : nil,
                now: now,
                generation: generation
            )
            return
        }
        guard shifts.preferences.liveActivityEnabled else {
            await performEndAll()
            return
        }
        // An assigned focus day owns upcoming system presentations. Do not
        // leave an independently scheduled clock-off activity that can preempt it
        // while the app is suspended and cannot arbitrate.
        if !queuedFocus.isEmpty {
            await performEndAll()
            return
        }
        if shifts.session.isEndedEarly(snapshot) {
            await finishAll(shifts: shifts, snapshot: snapshot, now: now, generation: generation)
            return
        }
        if !snapshot.isWorkday, !shifts.session.isForcedWorkday(snapshot) {
            recordDebugStatus("rest-day")
            await performEndAll()
            return
        }
        if snapshot.isBeforeStart(at: now) {
            recordDebugStatus("before-clock-in")
            await performEndAll()
            return
        }
        guard snapshot.remainingMs > 0 else {
            await finishAll(shifts: shifts, snapshot: snapshot, now: now, generation: generation)
            return
        }

        let displaySnapshot = scheduledStart > now ? (shifts.session.snapshot(at: scheduledStart) ?? snapshot) : snapshot
        let attributes = OffWorkActivityAttributes(
            shiftStartAtMs: Int64(snapshot.startAtMs),
            plannedEndAtMs: Int64(snapshot.plannedEndAtMs)
        )
        let state = OffWorkActivityAttributes.ContentState(
            endAtMs: Int64(snapshot.endAtMs),
            progress: displaySnapshot.progress,
            segments: snapshot.segments.map {
                .init(startAtMs: Int64($0.startAtMs), endAtMs: Int64($0.endAtMs))
            },
            phase: snapshot.overtimeEndAtMs == nil ? "working" : "overtime",
            locale: shifts.preferences.languageCode,
            appTitle: OWCBrand.shortName,
            caption: shifts.text.t("timeLeftCaption"),
            completedCaption: shifts.text.t("offWorkTime"),
            completedNote: shifts.text.t("offWorkWellDone"),
            surface: LiveActivitySurface.work.rawValue,
            timerLabel: nil,
            destination: "offworkcountdown://timer",
            displayStartAtMs: Int64(scheduledStart.timeIntervalSince1970 * 1_000)
        )
        let content = ActivityContent(
            state: state,
            staleDate: snapshot.endDate,
            relevanceScore: 100
        )

        let matching = currentActivities.filter {
            $0.attributes.plannedEndAtMs == Int64(snapshot.plannedEndAtMs)
                && $0.activityState != .ended
                && $0.activityState != .dismissed
        }
        if let existing = matching.first {
            await existing.update(content)
            guard generation == lifecycleGeneration else { return }
            for duplicate in matching.dropFirst() {
                await duplicate.end(content, dismissalPolicy: .immediate)
                guard generation == lifecycleGeneration else { return }
            }
            // Serialisation means no `end()` can be in flight here, so this is
            // a cheap belt-and-braces check rather than the guarantee it was
            // when it stood alone — an activity the system retired for its own
            // reasons still gets replaced instead of handed on.
            if existing.activityState != .ended, existing.activityState != .dismissed {
                recordDebugStatus("updated:\(existing.activityState)")
                scheduleCompletion(shifts: shifts, snapshot: snapshot, generation: generation)
                return
            }
        }

        for stale in currentActivities {
            guard generation == lifecycleGeneration else { return }
            await stale.end(nil, dismissalPolicy: .immediate)
        }
        guard generation == lifecycleGeneration else { return }

        do {
            if scheduledStart > now {
                let title = LocalizedStringResource(String.LocalizationValue(shifts.text.t("offWorkReminder")), locale: shifts.preferences.locale)
                let body = LocalizedStringResource(String.LocalizationValue(shifts.text.t("liveActivityScheduleNote")), locale: shifts.preferences.locale)
                let activity = try await LiveActivityRequestWorker.request(
                    attributes: attributes,
                    content: content,
                    alertConfiguration: AlertConfiguration(title: title, body: body, sound: .default),
                    start: scheduledStart
                )
                recordDebugStatus("scheduled:\(activity)")
            } else {
                let activity = try await LiveActivityRequestWorker.request(
                    attributes: attributes,
                    content: content
                )
                recordDebugStatus("requested:\(activity)")
            }
            lastError = nil
            scheduleCompletion(shifts: shifts, snapshot: snapshot, generation: generation)
        } catch {
            lastError = error.localizedDescription
            recordDebugStatus("error:\(error.localizedDescription)")
        }
    }

    private func focusState(shifts: ShiftSessionStore, session: FocusSession, now: Date) -> OffWorkActivityAttributes.ContentState {
        let surface = LiveActivitySurface(sessionKind: session.kind)
        let copy = focusCopy(for: surface, shifts: shifts)
        let chain = shifts.focus.focusChain(for: session, at: now)
        let legs = Self.focusLegs(chain, shifts: shifts)
        let canAdd = surface == .focus && shifts.focus.canAddFocusPomodoro(at: now)
        return OffWorkActivityAttributes.ContentState(
            endAtMs: Int64(session.plannedEndAt.timeIntervalSince1970 * 1_000),
            progress: 0,
            segments: [.init(
                startAtMs: Int64(session.startedAt.timeIntervalSince1970 * 1_000),
                endAtMs: Int64(session.plannedEndAt.timeIntervalSince1970 * 1_000)
            )],
            phase: surface.rawValue,
            locale: shifts.preferences.languageCode,
            appTitle: OWCBrand.shortName,
            caption: copy.caption,
            completedCaption: copy.completedCaption,
            completedNote: copy.completedNote,
            surface: surface.rawValue,
            timerLabel: copy.title,
            destination: "offworkcountdown://focus",
            taskTitle: Self.focusTaskTitle(session: session, surface: surface, shifts: shifts),
            taskIcon: Self.focusTaskIcon(session: session, surface: surface, shifts: shifts),
            nextLabel: legs.first?.nextNote,
            shiftEndAtMs: Self.shiftEndAtMs(shifts: shifts, at: now),
            shiftEndLabel: shifts.text.t("endTime"),
            legs: legs,
            chainDoneCaption: shifts.text.t(shifts.focus.completesFocusDay(after: session, at: now) ? "focusActivityDayDone" : "focusActivityChainDone"),
            // Offered only where it means something: a running focus block
            // with a task behind it. A break has no estimate to raise.
            addPomodoroLabel: surface == .focus && session.taskID != nil
                ? shifts.text.t("focusActivityAddPomodoro")
                : nil,
            addPomodoroEnabled: canAdd,
            stopFocusLabel: shifts.text.t("focusStop")
        )
    }

    private func reconcileScheduledActivities(shifts: ShiftSessionStore, now: Date) async {
        let enabled = shifts.preferences.focusLiveActivityEnabled && ActivityAuthorizationInfo().areActivitiesEnabled
        var requests: [(key: String, start: Date, state: OffWorkActivityAttributes.ContentState)] = []
        if enabled {
            for session in queuedFocus {
                var state = focusState(shifts: shifts, session: session, now: session.startedAt)
                state.scheduledSessionID = session.id.uuidString
                requests.append((session.id.uuidString, session.startedAt, state))
            }
            // A timer reaching zero does not wake the extension to replace its
            // text. Schedule the final message through ActivityKit as well.
            if let last = queuedFocus.last ?? shifts.focus.activeFocusSession(),
               shifts.focus.completesFocusDay(after: last, at: now) {
                let chain = shifts.focus.focusChain(for: last, at: last.startedAt)
                let end = chain.last?.end ?? last.plannedEndAt
                if end > now {
                    let key = "done:" + last.id.uuidString
                    let copy = shifts.text.t("focusActivityDayDone")
                    let state = OffWorkActivityAttributes.ContentState(
                        endAtMs: Int64(end.timeIntervalSince1970 * 1_000), progress: 100,
                        segments: [], phase: "complete", locale: shifts.preferences.languageCode,
                        appTitle: OWCBrand.shortName, caption: "", completedCaption: copy,
                        completedNote: "", surface: "focus", destination: "offworkcountdown://focus",
                        chainDoneCaption: copy, scheduledSessionID: key
                    )
                    requests.append((key, end, state))
                }
            }
        }
        let ids = Set(requests.map(\.key))
        let pending = Activity<OffWorkActivityAttributes>.activities.filter { $0.activityState == .pending && $0.content.state.scheduledSessionID != nil }
        for activity in pending where !ids.contains(activity.content.state.scheduledSessionID ?? "") {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for request in requests {
            // Newer blocks outrank stale cards without asking the suspended app
            // to run. The next foreground reconciliation removes those cards.
            let content = ActivityContent(state: request.state,
                staleDate: Date(timeIntervalSince1970: Double(request.state.chainEndAtMs) / 1_000),
                relevanceScore: request.start.timeIntervalSince1970)
            if let existing = pending.first(where: { $0.content.state.scheduledSessionID == request.key }) {
                await existing.update(content)
                continue
            }
            do {
                _ = try await LiveActivityRequestWorker.request(
                    attributes: .init(shiftStartAtMs: Int64(request.start.timeIntervalSince1970 * 1_000),
                                      plannedEndAtMs: request.state.endAtMs),
                    content: content,
                    alertConfiguration: .init(
                        title: LocalizedStringResource(String.LocalizationValue(request.state.taskTitle ?? request.state.appTitle), locale: shifts.preferences.locale),
                        body: LocalizedStringResource(String.LocalizationValue(request.state.phase == "complete"
                            ? request.state.completedCaption
                            : shifts.text.t("focusEndsAt", values: ["time": shifts.text.formatTime(Date(timeIntervalSince1970: Double(request.state.endAtMs) / 1_000))])), locale: shifts.preferences.locale),
                        sound: .default
                    ),
                    start: request.start
                )
            } catch {
                lastError = error.localizedDescription
                recordDebugStatus("focus-schedule-error:\(error.localizedDescription)")
            }
        }
    }

    private func performFocusReschedule(
        shifts: ShiftSessionStore,
        session: FocusSession,
        decision: LiveActivityDecision,
        workDisplayStartsAt: Date?,
        now: Date,
        generation: Int
    ) async {
        let chain = shifts.focus.focusChain(for: session, at: now)
        let chainEnd = chain.last?.end ?? session.plannedEndAt
        let attributes = OffWorkActivityAttributes(
            shiftStartAtMs: Int64(session.startedAt.timeIntervalSince1970 * 1_000),
            plannedEndAtMs: Int64(session.plannedEndAt.timeIntervalSince1970 * 1_000)
        )
        let state = focusState(shifts: shifts, session: session, now: now)
        // The first boundary already needs a new layout. Do not advertise the
        // frozen current phase as fresh until the entire chain has ended.
        let content = ActivityContent(state: state, staleDate: session.plannedEndAt, relevanceScore: session.startedAt.timeIntervalSince1970)
        let desired = LiveActivityIdentity(
            plannedEndAtMs: attributes.plannedEndAtMs,
            surface: decision.surface
        )
        let active = currentActivities.filter {
            $0.activityState != .ended && $0.activityState != .dismissed
        }.sorted { $0.attributes.shiftStartAtMs > $1.attributes.shiftStartAtMs }
        let existing = active.map {
            LiveActivityIdentity(
                plannedEndAtMs: $0.attributes.plannedEndAtMs,
                surface: LiveActivitySurface(rawValue: $0.content.state.surface ?? "work") ?? .work
            )
        }
        let action = LiveActivityReconciler.action(existing: existing, desired: desired)
        let matching = active.filter {
            LiveActivityIdentity(
                plannedEndAtMs: $0.attributes.plannedEndAtMs,
                surface: LiveActivitySurface(rawValue: $0.content.state.surface ?? "work") ?? .work
            ).canUpdate(to: desired)
        }
        if case .updateExisting = action, let activity = matching.first {
            await activity.update(content)
            guard generation == lifecycleGeneration else { return }
            for duplicate in matching.dropFirst() {
                await duplicate.end(content, dismissalPolicy: .immediate)
                guard generation == lifecycleGeneration else { return }
            }
            for stale in active where !matching.contains(where: { $0.id == stale.id }) {
                await stale.end(nil, dismissalPolicy: .immediate)
                guard generation == lifecycleGeneration else { return }
            }
            lastError = nil
            recordDebugStatus("updated:\(decision.surface.rawValue)")
            scheduleFocusWake(
                shifts: shifts,
                chainEnd: chainEnd,
                workDisplayStartsAt: workDisplayStartsAt,
                now: now,
                generation: generation
            )
            return
        }
        for activity in active {
            guard generation == lifecycleGeneration else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard generation == lifecycleGeneration else { return }
        do {
            _ = try await LiveActivityRequestWorker.request(
                attributes: attributes,
                content: content
            )
            lastError = nil
            recordDebugStatus("requested:\(decision.surface.rawValue)")
            scheduleFocusWake(
                shifts: shifts,
                chainEnd: chainEnd,
                workDisplayStartsAt: workDisplayStartsAt,
                now: now,
                generation: generation
            )
        } catch {
            lastError = error.localizedDescription
            recordDebugStatus("error:\(error.localizedDescription)")
        }
    }

    /// The next event for a focus surface is either the end of its chain or
    /// the instant work gains priority. Scheduling only the earlier event
    /// ensures that a focus completion from an older generation cannot end the
    /// work activity selected at the handoff.
    ///
    /// The chain end, not the running block's end: the payload already carries
    /// the break and the block queued behind it, and retiring the activity at
    /// the first boundary would take the rest of it off the Lock Screen.
    private func scheduleFocusWake(
        shifts: ShiftSessionStore,
        chainEnd: Date,
        workDisplayStartsAt: Date?,
        now: Date,
        generation: Int
    ) {
        switch FocusLiveActivityWakePlan.make(
            focusEndsAt: chainEnd,
            workDisplayStartsAt: workDisplayStartsAt,
            now: now
        ) {
        case .completionOnly:
            focusPriorityTransition.cancel()
            scheduleFocusCompletion(at: chainEnd, generation: generation)
        case .workHandoffAtCompletion:
            completionTask?.cancel()
            scheduleWorkHandoff(
                at: chainEnd,
                shifts: shifts,
                generation: generation
            )
        case .completionThenWorkHandoff:
            guard let workDisplayStartsAt else { return }
            // End the focus surface at its own boundary, but preserve the
            // later wake that makes the work surface appear even if the user
            // does not foreground the app in between.
            scheduleWorkHandoff(
                at: workDisplayStartsAt,
                shifts: shifts,
                generation: generation
            )
            scheduleFocusCompletion(
                at: chainEnd,
                generation: generation,
                preservingPriorityTransition: true
            )
        }
    }

    private func scheduleWorkHandoff(at date: Date, shifts: ShiftSessionStore, generation: Int) {
        focusPriorityTransition.schedule(at: date) { [weak self, weak shifts] in
            guard let self, let shifts,
                  LiveActivityReconciler.completionMayRun(
                    scheduledGeneration: generation,
                    currentGeneration: self.lifecycleGeneration
                  )
            else { return }
            await self.reschedule(shifts: shifts, now: self.schedulingClock.now())
        }
    }

    private func scheduleFocusCompletion(
        at end: Date,
        generation: Int,
        preservingPriorityTransition: Bool = false
    ) {
        if !preservingPriorityTransition { focusPriorityTransition.cancel() }
        completionTask?.cancel()
        completionTask = Task { @MainActor [weak self] in
            let delay = max(0, end.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self,
                  LiveActivityReconciler.completionMayRun(
                    scheduledGeneration: generation,
                    currentGeneration: self.lifecycleGeneration
                  )
            else { return }
            // Exactly the same serial tail as work completion. A foreground
            // reschedule that already owns the queue cannot be interleaved by
            // this delayed end, and a newer generation re-checks before end.
            let previous = self.pendingOperation
            let task = Task { @MainActor in
                await previous?.value
                guard LiveActivityReconciler.completionMayRun(
                    scheduledGeneration: generation,
                    currentGeneration: self.lifecycleGeneration
                ) else { return }
                if preservingPriorityTransition {
                    for activity in currentActivities {
                        guard LiveActivityReconciler.completionMayRun(
                            scheduledGeneration: generation,
                            currentGeneration: self.lifecycleGeneration
                        ) else { return }
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                } else {
                    await self.performEndAll()
                }
            }
            self.pendingOperation = task
            await task.value
        }
    }

    private func performEndAll() async {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        focusPriorityTransition.cancel()
        completionTask?.cancel()
        for activity in currentActivities {
            // A restart during the previous `end()` has already claimed the
            // token; whatever it put on screen is newer than this teardown.
            guard generation == lifecycleGeneration else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends the activity when the shift it belongs to is over.
    ///
    /// Carries the generation it was scheduled under. This task sleeps for
    /// hours and `Task.isCancelled` is not enough on its own: once it is past
    /// that check a later `cancel()` cannot stop it, and it would go on to
    /// finish an activity a restart or an added stretch of overtime had since
    /// handed to a newer session.
    private func scheduleCompletion(
        shifts: ShiftSessionStore,
        snapshot: NativeShiftSnapshot,
        generation: Int
    ) {
        completionTask?.cancel()
        let delay = max(0, snapshot.endDate.timeIntervalSinceNow)
        completionTask = Task { @MainActor [weak self, weak shifts] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let shifts else { return }
            guard generation == self.lifecycleGeneration else { return }
            // Through the same queue as everything else, so it cannot land in
            // the middle of a reschedule.
            let previous = self.pendingOperation
            let task = Task { @MainActor in
                await previous?.value
                guard generation == self.lifecycleGeneration else { return }
                await self.finishAll(
                    shifts: shifts,
                    snapshot: snapshot,
                    now: .now,
                    generation: generation
                )
            }
            self.pendingOperation = task
            await task.value
        }
    }

    private func finishAll(
        shifts: ShiftSessionStore,
        snapshot: NativeShiftSnapshot,
        now: Date,
        generation: Int
    ) async {
        completionTask?.cancel()
        let finalState = OffWorkActivityAttributes.ContentState(
            endAtMs: Int64(snapshot.endAtMs),
            progress: 100,
            segments: snapshot.segments.map {
                .init(startAtMs: Int64($0.startAtMs), endAtMs: Int64($0.endAtMs))
            },
            phase: "complete",
            locale: shifts.preferences.languageCode,
            appTitle: OWCBrand.shortName,
            caption: shifts.text.t("timeLeftCaption"),
            completedCaption: shifts.text.t("offWorkTime"),
            completedNote: shifts.text.t("offWorkWellDone")
        )
        let finalContent = ActivityContent(
            state: finalState,
            staleDate: nil,
            relevanceScore: 100
        )
        let dismissal = ActivityUIDismissalPolicy.after(now.addingTimeInterval(4 * 60 * 60))
        for activity in currentActivities {
            // Re-checked per activity, not once up front: ending several of
            // them suspends between each, and overtime added in that gap makes
            // the rest somebody else's to finish.
            guard generation == lifecycleGeneration else { return }
            await activity.end(finalContent, dismissalPolicy: dismissal)
        }
        recordDebugStatus("completed")
    }

    private func recordDebugStatus(_ value: String) {
#if DEBUG
        UserDefaults.standard.set(value, forKey: "ios.native.qaLiveActivityStatus")
#endif
    }
}
