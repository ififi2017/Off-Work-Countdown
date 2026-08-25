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

    func reschedule(store: OffWorkStore, now: Date = .now) async {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        guard store.countdownStarted else {
            recordDebugStatus("countdown-not-started")
            await endAll()
            return
        }
        guard store.liveActivityEnabled else {
            recordDebugStatus("disabled-in-app")
            await endAll()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            recordDebugStatus("disabled-by-system")
            await endAll()
            return
        }
        guard let snapshot = store.snapshot(at: now) else {
            recordDebugStatus("no-active-shift")
            await endAll()
            return
        }
        guard snapshot.remainingMs > 0 else {
            await finishAll(store: store, snapshot: snapshot, now: now)
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
            // An `end()` already in flight when the update landed can still take
            // this activity down afterwards; the token cannot recall a call that
            // has left. If that happened, fall through and request a fresh one
            // rather than hand the session an activity that is on its way out.
            if existing.activityState != .ended, existing.activityState != .dismissed {
                recordDebugStatus("updated:\(existing.activityState)")
                scheduleCompletion(store: store, snapshot: snapshot)
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
            scheduleCompletion(store: store, snapshot: snapshot)
        } catch {
            lastError = error.localizedDescription
            recordDebugStatus("error:\(error.localizedDescription)")
        }
    }

    func endAll() async {
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

    private func scheduleCompletion(store: OffWorkStore, snapshot: NativeShiftSnapshot) {
        completionTask?.cancel()
        let delay = max(0, snapshot.endDate.timeIntervalSinceNow)
        completionTask = Task { @MainActor [weak self, weak store] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let store else { return }
            await self.finishAll(store: store, snapshot: snapshot, now: .now)
        }
    }

    private func finishAll(store: OffWorkStore, snapshot: NativeShiftSnapshot, now: Date) async {
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
