@preconcurrency import ActivityKit
import Foundation

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
/// countdown gets the one system slot only in its configured display window;
/// otherwise an open focus or break timer stays visible.
struct LiveActivityDecision: Equatable, Sendable {
    var surface: LiveActivitySurface
    var endAt: Date

    static func choose(
        workEndAt: Date?,
        workDisplayStartsAt: Date?,
        focusSession: FocusSession?,
        now: Date
    ) -> LiveActivityDecision? {
        if let workEndAt, let workDisplayStartsAt,
           now >= workDisplayStartsAt, now < workEndAt {
            return .init(surface: .work, endAt: workEndAt)
        }
        guard let focusSession, focusSession.endedAt == nil,
              focusSession.plannedEndAt > now else { return nil }
        return .init(surface: .init(sessionKind: focusSession.kind), endAt: focusSession.plannedEndAt)
    }
}

/// ActivityKit-facing identity reduced to values we can exercise in ordinary
/// unit tests. Matching identity updates in place; a changed session/surface
/// replaces the single system activity.
struct LiveActivityIdentity: Equatable, Sendable {
    var plannedEndAtMs: Int64
    var surface: LiveActivitySurface
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
        let matching = existing.filter { $0 == desired }
        return matching.isEmpty ? .replace : .updateExisting(duplicates: matching.count - 1)
    }

    /// A delayed completion may act only while its generation remains current.
    static func completionMayRun(scheduledGeneration: Int, currentGeneration: Int) -> Bool {
        scheduledGeneration == currentGeneration
    }
}

enum FocusLiveActivityWakePlan: Equatable, Sendable {
    case completionOnly
    case workHandoffBeforeCompletion
    case completionThenWorkHandoff

    static func make(
        focusEndsAt: Date,
        workDisplayStartsAt: Date?,
        now: Date
    ) -> Self {
        guard let workDisplayStartsAt, workDisplayStartsAt > now else {
            return .completionOnly
        }
        return workDisplayStartsAt <= focusEndsAt
            ? .workHandoffBeforeCompletion
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
/// This is intentionally distinct from activity completion: entering the work
/// window must choose work, rather than ending an otherwise valid focus phase.
@MainActor
final class LiveActivityPriorityTransitionService {
    private let clock: LiveActivitySchedulingClock
    private var task: Task<Void, Never>?
    private var generation = 0

    private(set) var scheduledAt: Date?

    init(clock: LiveActivitySchedulingClock) {
        self.clock = clock
    }

    func schedule(at date: Date, action: @escaping () async -> Void) {
        cancel()
        generation &+= 1
        let scheduledGeneration = generation
        scheduledAt = date
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = max(0, date.timeIntervalSince(self.clock.now()))
            guard await self.clock.sleep(delay), !Task.isCancelled,
                  scheduledGeneration == self.generation
            else { return }
            self.task = nil
            self.scheduledAt = nil
            await action()
        }
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
        store: OffWorkStore
    ) -> String? {
        guard surface == .focus else { return nil }
        return session.taskID
            .flatMap { id in store.records.state.focusTasks.first(where: { $0.id == id }) }?
            .title
    }

    static func focusTaskIcon(
        session: FocusSession,
        surface: LiveActivitySurface,
        store: OffWorkStore
    ) -> String {
        guard surface == .focus else { return "cup.and.saucer.fill" }
        let icon = session.taskID
            .flatMap { id in store.records.state.focusTasks.first(where: { $0.id == id }) }?
            .icon
        return (icon ?? .focus).systemName
    }

    /// Describe the next timer phase, not an unrelated future planning tile.
    static func focusNextLabel(session: FocusSession, store: OffWorkStore, now: Date) -> String? {
        guard session.kind == .focus else { return store.t("focusStartNextFocus") }
        guard session.plannedEndReason == .completed else { return nil }
        let kind = store.nextFocusBreakKind(after: session)
        guard store.hasFocusRoom(at: session.plannedEndAt) else { return nil }
        let settings = store.focusTimerSettings.normalized
        return store.t("focusActivityThenBreak", values: [
            "count": "\(kind == .longBreak ? settings.longBreakMinutes : settings.shortBreakMinutes)"
        ])
    }

    /// A fixed clock-off time stays truthful while the app is suspended,
    /// including across lunch. Never format a ticking duration into a payload.
    static func shiftEndAtMs(store: OffWorkStore, at now: Date) -> Int64? {
        guard let snapshot = store.snapshot(at: now), snapshot.remainingMs > 0 else { return nil }
        return Int64(snapshot.endAtMs)
    }

    private func focusCopy(for surface: LiveActivitySurface, store: OffWorkStore) -> (
        title: String, caption: String, completedCaption: String, completedNote: String
    ) {
        switch surface {
        case .focus:
            return (
                store.t("focusTitle"), store.t("focusTitle"),
                store.t("focusPhaseComplete"), store.t("focusEndedNaturally")
            )
        case .shortBreak:
            return (
                store.t("focusShortBreak"), store.t("focusShortBreak"),
                store.t("focusPhaseComplete"), store.t("focusNextFocusBody")
            )
        case .longBreak:
            return (
                store.t("focusLongBreak"), store.t("focusLongBreak"),
                store.t("focusPhaseComplete"), store.t("focusNextFocusBody")
            )
        case .work:
            return (
                OWCBrand.shortName, store.t("timeLeftCaption"),
                store.t("offWorkTime"), store.t("offWorkWellDone")
            )
        }
    }

    /// Runs after everything already queued, and is itself awaited, so callers
    /// keep the straight-line semantics they had before.
    func reschedule(store: OffWorkStore, now: Date = .now) async {
        let previous = pendingOperation
        let task = Task { @MainActor in
            await previous?.value
            await self.performReschedule(store: store, now: now)
        }
        pendingOperation = task
        await task.value
    }

    func endAll() async {
        let previous = pendingOperation
        let task = Task { @MainActor in
            await previous?.value
            await self.performEndAll()
        }
        pendingOperation = task
        await task.value
    }

    private func performReschedule(store: OffWorkStore, now: Date = .now) async {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        // A foreground reschedule supersedes any delayed handoff based on the
        // previous shift or focus session.
        focusPriorityTransition.cancel()
        let focusSession = store.activeFocusSession()
        guard store.publishesLiveSurfaces || focusSession != nil else {
            recordDebugStatus("countdown-not-started")
            await performEndAll()
            return
        }
        guard store.liveActivityEnabled else {
            recordDebugStatus("disabled-in-app")
            await performEndAll()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            recordDebugStatus("disabled-by-system")
            await performEndAll()
            return
        }
        guard let snapshot = store.snapshot(at: now) else {
            if let decision = LiveActivityDecision.choose(
                workEndAt: nil,
                workDisplayStartsAt: nil,
                focusSession: focusSession,
                now: now
            ) {
                await performFocusReschedule(
                    store: store,
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
        let scheduledStart = snapshot.plannedEndDate.addingTimeInterval(Double(-store.liveActivityLeadMinutes * 60))
        let workEligible = store.publishesLiveSurfaces
            && !store.isEndedEarly(snapshot)
            && (snapshot.isWorkday || store.isForcedWorkday(snapshot))
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
                store: store,
                session: focusSession,
                decision: decision,
                workDisplayStartsAt: workEligible && scheduledStart > now ? scheduledStart : nil,
                now: now,
                generation: generation
            )
            return
        }
        if store.isEndedEarly(snapshot) {
            await finishAll(store: store, snapshot: snapshot, now: now, generation: generation)
            return
        }
        if !snapshot.isWorkday, !store.isForcedWorkday(snapshot) {
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
            await finishAll(store: store, snapshot: snapshot, now: now, generation: generation)
            return
        }

        let displaySnapshot = scheduledStart > now ? (store.snapshot(at: scheduledStart) ?? snapshot) : snapshot
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
            locale: store.languageCode,
            appTitle: OWCBrand.shortName,
            caption: store.t("timeLeftCaption"),
            completedCaption: store.t("offWorkTime"),
            completedNote: store.t("offWorkWellDone"),
            surface: LiveActivitySurface.work.rawValue,
            timerLabel: nil,
            destination: "offworkcountdown://timer"
        )
        let content = ActivityContent(
            state: state,
            staleDate: snapshot.endDate,
            relevanceScore: 100
        )

        let matching = Activity<OffWorkActivityAttributes>.activities.filter {
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
                scheduleCompletion(store: store, snapshot: snapshot, generation: generation)
                return
            }
        }

        for stale in Activity<OffWorkActivityAttributes>.activities {
            guard generation == lifecycleGeneration else { return }
            await stale.end(nil, dismissalPolicy: .immediate)
        }
        guard generation == lifecycleGeneration else { return }

        do {
            if scheduledStart > now {
                let title = LocalizedStringResource(String.LocalizationValue(store.t("offWorkReminder")), locale: store.locale)
                let body = LocalizedStringResource(String.LocalizationValue(store.t("liveActivityScheduleNote")), locale: store.locale)
                let activity = try Activity<OffWorkActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard,
                    alertConfiguration: AlertConfiguration(title: title, body: body, sound: .default),
                    start: scheduledStart
                )
                recordDebugStatus("scheduled:\(activity.activityState)")
            } else {
                let activity = try Activity<OffWorkActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard
                )
                recordDebugStatus("requested:\(activity.activityState)")
            }
            lastError = nil
            scheduleCompletion(store: store, snapshot: snapshot, generation: generation)
        } catch {
            lastError = error.localizedDescription
            recordDebugStatus("error:\(error.localizedDescription)")
        }
    }

    private func performFocusReschedule(
        store: OffWorkStore,
        session: FocusSession,
        decision: LiveActivityDecision,
        workDisplayStartsAt: Date?,
        now: Date,
        generation: Int
    ) async {
        let copy = focusCopy(for: decision.surface, store: store)
        let attributes = OffWorkActivityAttributes(
            shiftStartAtMs: Int64(session.startedAt.timeIntervalSince1970 * 1_000),
            plannedEndAtMs: Int64(session.plannedEndAt.timeIntervalSince1970 * 1_000)
        )
        let state = OffWorkActivityAttributes.ContentState(
            endAtMs: Int64(session.plannedEndAt.timeIntervalSince1970 * 1_000),
            progress: 0,
            segments: [.init(
                startAtMs: Int64(session.startedAt.timeIntervalSince1970 * 1_000),
                endAtMs: Int64(session.plannedEndAt.timeIntervalSince1970 * 1_000)
            )],
            phase: decision.surface.rawValue,
            locale: store.languageCode,
            appTitle: OWCBrand.shortName,
            caption: copy.caption,
            completedCaption: copy.completedCaption,
            completedNote: copy.completedNote,
            surface: decision.surface.rawValue,
            timerLabel: copy.title,
            destination: "offworkcountdown://focus",
            taskTitle: Self.focusTaskTitle(session: session, surface: decision.surface, store: store),
            taskIcon: Self.focusTaskIcon(session: session, surface: decision.surface, store: store),
            nextLabel: Self.focusNextLabel(session: session, store: store, now: now),
            shiftEndAtMs: Self.shiftEndAtMs(store: store, at: now),
            shiftEndLabel: store.t("endTime")
        )
        let content = ActivityContent(state: state, staleDate: session.plannedEndAt, relevanceScore: 90)
        let desired = LiveActivityIdentity(
            plannedEndAtMs: attributes.plannedEndAtMs,
            surface: decision.surface
        )
        let active = Activity<OffWorkActivityAttributes>.activities.filter {
            $0.activityState != .ended && $0.activityState != .dismissed
        }
        let existing = active.map {
            LiveActivityIdentity(
                plannedEndAtMs: $0.attributes.plannedEndAtMs,
                surface: LiveActivitySurface(rawValue: $0.content.state.surface ?? "work") ?? .work
            )
        }
        let action = LiveActivityReconciler.action(existing: existing, desired: desired)
        let matching = active.filter {
            $0.attributes.plannedEndAtMs == desired.plannedEndAtMs
                && LiveActivitySurface(rawValue: $0.content.state.surface ?? "work") == desired.surface
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
                store: store,
                session: session,
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
            _ = try Activity<OffWorkActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil,
                style: .standard
            )
            lastError = nil
            recordDebugStatus("requested:\(decision.surface.rawValue)")
            scheduleFocusWake(
                store: store,
                session: session,
                workDisplayStartsAt: workDisplayStartsAt,
                now: now,
                generation: generation
            )
        } catch {
            lastError = error.localizedDescription
            recordDebugStatus("error:\(error.localizedDescription)")
        }
    }

    /// The next event for a focus surface is either its own completion or the
    /// instant work gains priority. Scheduling only the earlier event ensures
    /// that a focus completion from an older generation cannot end the work
    /// activity selected at the handoff.
    private func scheduleFocusWake(
        store: OffWorkStore,
        session: FocusSession,
        workDisplayStartsAt: Date?,
        now: Date,
        generation: Int
    ) {
        switch FocusLiveActivityWakePlan.make(
            focusEndsAt: session.plannedEndAt,
            workDisplayStartsAt: workDisplayStartsAt,
            now: now
        ) {
        case .completionOnly:
            focusPriorityTransition.cancel()
            scheduleFocusCompletion(at: session.plannedEndAt, generation: generation)
        case .workHandoffBeforeCompletion:
            guard let workDisplayStartsAt else { return }
            completionTask?.cancel()
            scheduleWorkHandoff(
                at: workDisplayStartsAt,
                store: store,
                generation: generation
            )
        case .completionThenWorkHandoff:
            guard let workDisplayStartsAt else { return }
            // End the focus surface at its own boundary, but preserve the
            // later wake that makes the work surface appear even if the user
            // does not foreground the app in between.
            scheduleWorkHandoff(
                at: workDisplayStartsAt,
                store: store,
                generation: generation
            )
            scheduleFocusCompletion(
                at: session.plannedEndAt,
                generation: generation,
                preservingPriorityTransition: true
            )
        }
    }

    private func scheduleWorkHandoff(at date: Date, store: OffWorkStore, generation: Int) {
        focusPriorityTransition.schedule(at: date) { [weak self, weak store] in
            guard let self, let store,
                  LiveActivityReconciler.completionMayRun(
                    scheduledGeneration: generation,
                    currentGeneration: self.lifecycleGeneration
                  )
            else { return }
            await self.reschedule(store: store, now: self.schedulingClock.now())
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
                    for activity in Activity<OffWorkActivityAttributes>.activities {
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
        for activity in Activity<OffWorkActivityAttributes>.activities {
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
        store: OffWorkStore,
        snapshot: NativeShiftSnapshot,
        generation: Int
    ) {
        completionTask?.cancel()
        let delay = max(0, snapshot.endDate.timeIntervalSinceNow)
        completionTask = Task { @MainActor [weak self, weak store] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let store else { return }
            guard generation == self.lifecycleGeneration else { return }
            // Through the same queue as everything else, so it cannot land in
            // the middle of a reschedule.
            let previous = self.pendingOperation
            let task = Task { @MainActor in
                await previous?.value
                guard generation == self.lifecycleGeneration else { return }
                await self.finishAll(
                    store: store,
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
        store: OffWorkStore,
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
            locale: store.languageCode,
            appTitle: OWCBrand.shortName,
            caption: store.t("timeLeftCaption"),
            completedCaption: store.t("offWorkTime"),
            completedNote: store.t("offWorkWellDone")
        )
        let finalContent = ActivityContent(
            state: finalState,
            staleDate: nil,
            relevanceScore: 100
        )
        let dismissal = ActivityUIDismissalPolicy.after(now.addingTimeInterval(4 * 60 * 60))
        for activity in Activity<OffWorkActivityAttributes>.activities {
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
