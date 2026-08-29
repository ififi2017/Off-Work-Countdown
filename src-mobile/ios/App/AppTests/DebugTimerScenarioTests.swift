#if DEBUG
import Foundation
import Testing
@testable import App

@Test(
    "Debug capture scenarios resolve through the shared countdown rules",
    arguments: [
        (DebugTimerScenario.working, TimerVisualPhase.running),
        (DebugTimerScenario.lunch, TimerVisualPhase.lunch),
        (DebugTimerScenario.overtime, TimerVisualPhase.overtime),
        (DebugTimerScenario.completed, TimerVisualPhase.completed),
        (DebugTimerScenario.restDay, TimerVisualPhase.rest),
        (DebugTimerScenario.manualSchedule, TimerVisualPhase.unscheduled),
    ]
)
@MainActor
func debugCaptureScenarioResolvesPhase(
    scenario: DebugTimerScenario,
    expectedPhase: TimerVisualPhase
) {
    withDebugStore { store in
        let realAnchor = Date(timeIntervalSince1970: 1_700_000_000)
        store.activateDebugTimerScenario(scenario, at: realAnchor)
        let now = store.timerDate(from: realAnchor)
        let snapshot = store.shouldQuerySnapshot(at: now) ? store.snapshot(at: now) : nil

        #expect(store.visualPhase(snapshot: snapshot, at: now) == expectedPhase)
        #expect(store.effectiveStartMinutes(at: now) == 9 * 60)
        #expect(store.presentationNotificationMode == .milestones)
        #expect(store.presentationMicroBreakEnabled)
        #expect(store.presentationLunchStartReminderEnabled)
        #expect(store.presentationLunchEndReminderEnabled)
    }
}

@Test("Debug capture clock starts on Friday, August 23 at 14:22")
@MainActor
func debugCaptureClockHasStableAnchor() {
    let date = DebugTimerScenario.virtualStartDate
    let components = Calendar.current.dateComponents(
        [.year, .month, .day, .weekday, .hour, .minute, .second],
        from: date
    )

    #expect(components.year == 2024)
    #expect(components.month == 8)
    #expect(components.day == 23)
    #expect(components.weekday == 6)
    #expect(components.hour == 14)
    #expect(components.minute == 22)
    #expect(components.second == 0)
}

@Test(
    "Debug capture scenarios publish the same phase to the widget",
    arguments: [
        (DebugTimerScenario.working, WidgetTimelinePhase.working),
        (DebugTimerScenario.lunch, WidgetTimelinePhase.break),
        (DebugTimerScenario.overtime, WidgetTimelinePhase.working),
        (DebugTimerScenario.completed, WidgetTimelinePhase.done),
        (DebugTimerScenario.restDay, WidgetTimelinePhase.before),
        (DebugTimerScenario.manualSchedule, WidgetTimelinePhase.idle),
    ]
)
@MainActor
func debugCaptureScenarioReachesTheWidget(
    scenario: DebugTimerScenario,
    expectedPhase: WidgetTimelinePhase
) {
    withDebugStore { store in
        store.onboardingComplete = true
        let realAnchor = Date(timeIntervalSince1970: 1_700_000_000)
        store.activateDebugTimerScenario(scenario, at: realAnchor)

        let published = WidgetSnapshotPublisher.shared.publishedSnapshot(
            store: store,
            now: realAnchor
        )
        let logicalNow = store.timerDate(from: realAnchor)
        let logicalNowMs = Int64(logicalNow.timeIntervalSince1970 * 1_000)
        let realNowMs = Int64(realAnchor.timeIntervalSince1970 * 1_000)

        #expect(published.clockOffsetMs == realNowMs - logicalNowMs)
        #expect(published.entry(atMs: logicalNowMs)?.phase == expectedPhase)
        #expect(published.entry(atMs: realNowMs) == nil)
    }
}

@Test("Completed capture points to the following day and rest capture points to Monday")
@MainActor
func debugCaptureNextShiftDatesAreDeterministic() throws {
    try withDebugStore { store in
        let realAnchor = Date(timeIntervalSince1970: 1_700_000_000)

        store.activateDebugTimerScenario(.completed, at: realAnchor)
        var now = store.timerDate(from: realAnchor)
        var snapshot = try #require(store.snapshot(at: now))
        var next = try #require(snapshot.nextShiftStartDate)
        #expect(Calendar.current.component(.day, from: next) == 24)

        store.activateDebugTimerScenario(.restDay, at: realAnchor)
        now = store.timerDate(from: realAnchor)
        snapshot = try #require(store.snapshot(at: now))
        next = try #require(snapshot.nextShiftStartDate)
        #expect(Calendar.current.component(.weekday, from: next) == 2)
        #expect(store.timeString(store.minutes(from: next)) == "09:00")
    }
}

@Test("A scheduled debug reset clears settings on the next store launch")
@MainActor
func debugResetRunsOnNextLaunch() {
    let suiteName = "DebugTimerScenarioTests.reset.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = OffWorkStore(defaults: defaults)
    first.onboardingComplete = true
    first.startMinutes = 7 * 60
    first.salaryAmount = "99999"
    first.salaryEnabled = true
    first.notificationMode = .milestones
    first.languageOverride = "ja"
    first.scheduleDebugResetOnNextLaunch()

    let relaunched = OffWorkStore(defaults: defaults)
    #expect(relaunched.debugDidResetOnLaunch)
    #expect(!relaunched.onboardingComplete)
    #expect(relaunched.startMinutes == 9 * 60)
    #expect(relaunched.salaryAmount == "0")
    #expect(!relaunched.salaryEnabled)
    #expect(relaunched.notificationMode == .off)
    #expect(relaunched.languageOverride == nil)
}

@MainActor
private func withDebugStore(
    _ body: (OffWorkStore) throws -> Void
) rethrows {
    let suiteName = "DebugTimerScenarioTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(OffWorkStore(defaults: defaults))
}
#endif
