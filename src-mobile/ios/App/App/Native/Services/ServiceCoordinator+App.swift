import Foundation

extension ServiceCoordinator.Operations {
    /// Installs real feature actions; the coordinator owns lifecycle and queues.
    static func app(
        shifts: ShiftSessionStore,
        recovery: RecoveryStore,
        notifications: NotificationService,
        liveActivities: LiveActivityService,
        watchSnapshots: WatchSnapshotPublisher,
        debugDidResetOnLaunch: Bool = false
    ) -> Self {
        Self(
            input: {
                .init(
                    onboardingComplete: shifts.preferences.onboardingComplete,
                    authorized: shifts.plus.isAuthorized,
                    watchEvidence: shifts.plus.watchEvidence,
                    countdownStarted: shifts.session.countdownStarted,
                    debugToken: shifts.session.debugPresentationToken,
                    schedule: ServiceScheduleSignal(shifts: shifts),
                    persistenceFailed: shifts.records.persistenceError != nil
                )
            },
            prepare: {
                // Let SwiftUI commit its first frame before rules and system
                // services start, even though their owner is process-scoped.
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                LaunchTrace.endAppInit()
                CountdownRules.warmUp()
#if DEBUG
                if debugDidResetOnLaunch {
                    WidgetSnapshotPublisher.shared.clear()
                    await notifications.clearShiftNotifications()
                    await liveActivities.endAll()
                }
#endif
            },
            begin: {
                shifts.plus.start()
                watchSnapshots.start()
                recovery.cloudSync.startIfEnabled()
            },
            activate: { completingOnboarding in
                if completingOnboarding {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    await shifts.finishOnboardingLaunch().value
                } else {
                    _ = await LaunchTrace.interval("launchReconcile") { await shifts.reconcileCountdownSession().value }
                    _ = await LaunchTrace.interval("launchRecordSchedule") { await shifts.reconcileRecordSchedule().value }
                    _ = await LaunchTrace.interval("launchFocusTemplate") { await shifts.focus.applyDefaultFocusTemplateIfNeeded().value }
                }
                shifts.preferences.refreshSystemLanguage()
                shifts.preferences.refreshSystemTimeZone()
                await notifications.refresh()
                guard !Task.isCancelled else { return }
                await recovery.resumeRestoredSyncIfNeeded()
            },
            resumeSync: {
                _ = await shifts.focus.applyDefaultFocusTemplateIfNeeded().value
                await recovery.resumeRestoredSyncIfNeeded()
            },
            flush: { try await shifts.records.flush() },
            publish: {
                await watchSnapshots.publish(shifts: shifts)
                _ = await LaunchTrace.interval("launchFocusSchedule") { await shifts.focus.refreshScheduledFocus().value }
                if let snapshot = await WidgetSnapshotComposer.shared.prepare(shifts: shifts) {
                    guard !Task.isCancelled else { return }
                    LaunchTrace.interval("widgetPublish") { WidgetSnapshotPublisher.shared.publish(snapshot) }
                }
                guard !Task.isCancelled else { return }
                if !shifts.session.publishesLiveSurfaces {
                    await notifications.clearShiftNotifications()
                } else {
                    await LaunchTrace.interval("shiftNotifications") { await notifications.reschedule(shifts: shifts) }
                }
                guard !Task.isCancelled else { return }
                await LaunchTrace.interval("focusNotifications") { await shifts.focus.refreshFocusNotifications() }
                guard !Task.isCancelled else { return }
                await LaunchTrace.interval("liveActivities") { await liveActivities.reschedule(shifts: shifts) }
            }
        )
    }
}
