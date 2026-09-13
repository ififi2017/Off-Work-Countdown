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
        store.debug.activateDebugTimerScenario(scenario, at: realAnchor)
        let now = store.session.timerDate(from: realAnchor)
        let snapshot = store.session.shouldQuerySnapshot(at: now) ? store.session.snapshot(at: now) : nil

        #expect(store.session.visualPhase(snapshot: snapshot, at: now) == expectedPhase)
        #expect(store.session.effectiveStartMinutes(at: now) == 9 * 60)
        #expect(store.session.presentationNotificationMode == .milestones)
        #expect(store.session.presentationMicroBreakEnabled)
        #expect(store.session.presentationLunchStartReminderEnabled)
        #expect(store.session.presentationLunchEndReminderEnabled)
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
        store.preferences.onboardingComplete = true
        let realAnchor = Date(timeIntervalSince1970: 1_700_000_000)
        store.debug.activateDebugTimerScenario(scenario, at: realAnchor)

        let published = WidgetSnapshotComposer.shared.publishedSnapshot(
            shifts: store.shifts,
            now: realAnchor
        )
        let logicalNow = store.session.timerDate(from: realAnchor)
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

        store.debug.activateDebugTimerScenario(.completed, at: realAnchor)
        var now = store.session.timerDate(from: realAnchor)
        var snapshot = try #require(store.session.snapshot(at: now))
        var next = try #require(snapshot.nextShiftStartDate)
        #expect(Calendar.current.component(.day, from: next) == 24)

        store.debug.activateDebugTimerScenario(.restDay, at: realAnchor)
        now = store.session.timerDate(from: realAnchor)
        snapshot = try #require(store.session.snapshot(at: now))
        next = try #require(snapshot.nextShiftStartDate)
        #expect(Calendar.current.component(.weekday, from: next) == 2)
        #expect(store.session.timeString(store.session.minutes(from: next)) == "09:00")
    }
}

@Test("A scheduled debug reset clears settings on the next store launch")
@MainActor
func debugResetRunsOnNextLaunch() async throws {
    let suiteName = "DebugTimerScenarioTests.reset.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let root = FileManager.default.temporaryDirectory
        .appending(path: "DebugReset.\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "archive.json")
    let first = AppRuntime(defaults: defaults, records: RecordCoordinator(fileURL: file))
    first.preferences.onboardingComplete = true
    first.preferences.applyPreferences { $0.startMinutes = 7 * 60 }
    first.preferences.applyPreferences { $0.salaryAmount = "99999" }
    first.preferences.applyPreferences { $0.salaryEnabled = true }
    first.preferences.applyPreferences { $0.notificationMode = .milestones }
    first.preferences.applyPreferences { $0.languageOverride = "ja" }
    try await first.records.flush()
    first.debug.scheduleDebugResetOnNextLaunch()

    let relaunched = try await AppRuntime.load(
        defaults: defaults, archiveURL: file
    )
    #expect(relaunched.debugDidResetOnLaunch)
    #expect(!relaunched.preferences.onboardingComplete)
    #expect(relaunched.preferences.startMinutes == 9 * 60)
    #expect(relaunched.preferences.salaryAmount == "0")
    #expect(!relaunched.preferences.salaryEnabled)
    #expect(relaunched.preferences.notificationMode == .off)
    #expect(relaunched.preferences.languageOverride == nil)
    #expect(relaunched.records.state == RecordState())
    #expect(relaunched.debug.debugSeedSampleRecords().synchronousResult)
    try await relaunched.records.flush()
    #expect(!RecordCoordinator(fileURL: file).state.observations.isEmpty)
}

@Test("A failed debug reset preserves the archive and marker for retry")
@MainActor
func failedDebugResetCanRetry() async throws {
    let suite = "DebugResetRetry.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DebugResetRetry.\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "archive.json")
    let original = AppRuntime(defaults: defaults, records: RecordCoordinator(fileURL: file))
    original.preferences.onboardingComplete = true
    original.preferences.applyPreferences { $0.startMinutes = 7 * 60 }
    try await original.records.flush()
    original.debug.scheduleDebugResetOnNextLaunch()

    await #expect(throws: RecordPersistenceError.self) {
        _ = try await AppRuntime.load(defaults: defaults, archiveURL: file, archiveReset: { _ in
            throw RecordPersistenceError.writeFailed
        })
    }
    #expect(defaults.bool(forKey: DebugScenarioController.resetKey))
    #expect(RecordCoordinator(fileURL: file).state.syncedPreferences?.startMinutes == 7 * 60)

    let retried = try await AppRuntime.load(
        defaults: defaults, archiveURL: file
    )
    #expect(retried.debugDidResetOnLaunch)
    #expect(!defaults.bool(forKey: DebugScenarioController.resetKey))
    #expect(retried.records.state == RecordState())
}

@Test("Sample records fill the free list once and stay stable on a second tap")
@MainActor
func debugSeedSampleRecordsIsIdempotent() {
    withDebugStore { store in
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 15))!
        #expect(store.debug.debugSeedSampleRecords(now: now).synchronousResult)
        let days = store.queries.recordedWorkDays()
        #expect(!days.isEmpty)
        #expect(store.records.state.lifeProfile?.birthYear == 1992)
        #expect(store.focus.focusTasksForToday(at: now).count == 2)
        #expect(!store.debug.debugSeedSampleRecords(now: now).synchronousResult)
        #expect(store.queries.recordedWorkDays().count == days.count)
    }
}

@MainActor
private func withDebugStore(
    _ body: (AppRuntime) throws -> Void
) rethrows {
    let suiteName = "DebugTimerScenarioTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(AppRuntime(defaults: defaults))
}
#endif
