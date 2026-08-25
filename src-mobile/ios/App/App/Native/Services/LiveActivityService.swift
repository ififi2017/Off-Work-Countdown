@preconcurrency import ActivityKit
import Foundation

@MainActor
@Observable
final class LiveActivityService {
    private(set) var lastError: String?
    private var completionTask: Task<Void, Never>?

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
        guard store.countdownStarted else {
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
            recordDebugStatus("no-active-shift")
            await performEndAll()
            return
        }
        guard snapshot.remainingMs > 0 else {
            await finishAll(store: store, snapshot: snapshot, now: now, generation: generation)
            return
        }

        let scheduledStart = snapshot.plannedEndDate.addingTimeInterval(Double(-store.liveActivityLeadMinutes * 60))
        let displaySnapshot = scheduledStart > now ? (store.snapshot(at: scheduledStart) ?? snapshot) : snapshot
        let attributes = OffWorkActivityAttributes(
            shiftStartAtMs: Int64(snapshot.startAtMs),
            plannedEndAtMs: Int64(snapshot.plannedEndAtMs)
        )
        let state = OffWorkActivityAttributes.ContentState(
            endAtMs: Int64(snapshot.endAtMs),
            progress: displaySnapshot.progress,
            phase: snapshot.overtimeEndAtMs == nil ? "working" : "overtime",
            locale: store.languageCode,
            appTitle: store.t("appShortName"),
            caption: store.t("timeLeftCaption"),
            completedCaption: store.t("offWorkTime"),
            completedNote: store.t("offWorkWellDone")
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

    private func performEndAll() async {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
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
            phase: "complete",
            locale: store.languageCode,
            appTitle: store.t("appShortName"),
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
