import Foundation
import Testing
@testable import App

@MainActor
@Test("A fresh install uses the documented iOS defaults")
func freshInstallDefaults() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = OffWorkStore(defaults: defaults)
    #expect(store.onboardingComplete == false)
    #expect(store.startMinutes == 9 * 60)
    #expect(store.endMinutes == 17 * 60)
    #expect(store.lunchEnabled == false)
    #expect(store.lunchDurationMinutes == 60)
    #expect(store.notificationMode == .off)
    #expect(store.salaryEnabled == false)
}

@MainActor
@Test("Persisted settings survive store recreation")
func persistedSettingsSurviveRelaunch() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = OffWorkStore(defaults: defaults)
    first.onboardingComplete = true
    first.startMinutes = 7 * 60 + 30
    first.endMinutes = 16 * 60 + 45
    first.lunchEnabled = true
    first.lunchDurationMinutes = 45
    first.notificationMode = .milestones

    let reloaded = OffWorkStore(defaults: defaults)
    #expect(reloaded.onboardingComplete)
    #expect(reloaded.startMinutes == 7 * 60 + 30)
    #expect(reloaded.endMinutes == 16 * 60 + 45)
    #expect(reloaded.lunchEnabled)
    #expect(reloaded.lunchDurationMinutes == 45)
    #expect(reloaded.notificationMode == .milestones)
}

@MainActor
@Test("A completed countdown resets after its end day")
func completedCountdownResetsAcrossDayBoundary() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let calendar = Calendar.current
    let start = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 24,
        hour: 10
    )))
    let sameDayEvening = try #require(calendar.date(bySettingHour: 22, minute: 0, second: 0, of: start))
    let followingDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))

    let first = OffWorkStore(defaults: defaults)
    first.scheduleMode = .off
    first.startMinutes = 9 * 60
    first.endMinutes = 17 * 60
    first.startCountdown(at: start)

    #expect(first.reconcileCountdownSession(at: sameDayEvening) == false)
    #expect(first.countdownStarted)

    let relaunched = OffWorkStore(defaults: defaults)
    #expect(relaunched.reconcileCountdownSession(at: followingDay))
    #expect(relaunched.countdownStarted == false)
}

@MainActor
@Test("The upcoming timeline starts with clock-in and always ends with clock-off")
func upcomingTimelineIncludesShiftBoundaries() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let calendar = Calendar.current
    let beforeShift = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 24,
        hour: 8
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .off
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60
    store.lunchDurationMinutes = 60

    let snapshot = try #require(store.snapshot(at: beforeShift))
    let events = store.upcomingTimelineEvents(for: snapshot, at: beforeShift)

    #expect(events.map(\.kind) == [.shiftStart, .lunchStart, .lunchEnd, .shiftEnd])
    #expect(events.last?.date == snapshot.endDate)
}

/// One row of `relativeDurationFormatting`. A named struct rather than a tuple
/// literal: a heterogeneous tuple array this size defeated the type checker.
struct DurationCase: Sendable {
    let milliseconds: Double
    let language: String
    let expected: String
}

@Test("Whole hours drop the trailing zero-minute unit", arguments: [
    DurationCase(milliseconds: 43_200_000, language: "en", expected: "12 h"),
    DurationCase(milliseconds: 5_400_000, language: "en", expected: "1 h 30 m"),
    DurationCase(milliseconds: 2_700_000, language: "en", expected: "45 m"),
    DurationCase(milliseconds: 0, language: "en", expected: "0 m"),
    DurationCase(milliseconds: 43_200_000, language: "zh-CN", expected: "12小时"),
    DurationCase(milliseconds: 5_400_000, language: "zh-CN", expected: "1小时30分钟"),
    DurationCase(milliseconds: 0, language: "zh-CN", expected: "0分钟"),
])
func relativeDurationFormatting(_ testCase: DurationCase) {
    let formatted = RelativeDurationFormatter.string(
        milliseconds: testCase.milliseconds,
        languageCode: testCase.language
    )
    #expect(formatted == testCase.expected)
}

@MainActor
@Test("An overnight shift keeps its after-midnight events in the timeline")
func overnightTimelineKeepsEventsAfterMidnight() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    // 23:30, half an hour into a 23:00 → 07:00 shift. Lunch at 02:00 and the
    // shift's end are both on the following calendar day.
    let duringShift = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 23, minute: 30
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .off
    store.startMinutes = 23 * 60
    store.endMinutes = 7 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 2 * 60
    store.lunchDurationMinutes = 30

    let snapshot = try #require(store.snapshot(at: duringShift))
    let events = store.upcomingTimelineEvents(for: snapshot, at: duringShift)

    #expect(events.map(\.kind) == [.lunchStart, .lunchEnd, .shiftEnd])
}

@MainActor
@Test("The widget timeline has an entry covering the lunch break")
func widgetTimelineCoversLunchBreak() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    // 12:45, inside a 12:30-13:30 break in an 09:00-18:00 shift.
    let duringLunch = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 12, minute: 45
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .off
    store.startMinutes = 9 * 60
    store.endMinutes = 18 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60 + 30
    store.lunchDurationMinutes = 60
    store.countdownStarted = true

    let nowMs = Int64(duringLunch.timeIntervalSince1970 * 1_000)
    let snapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: duringLunch),
        active: true,
        nowMs: nowMs
    )

    // The entry WidgetKit would pick: the most recent one already due.
    let current = try #require(snapshot.entries.last { $0.dateMs <= nowMs })
    #expect(current.phase == .break)
    #expect(current.labelKey == "lunchInProgress")
    #expect(nowMs < current.validUntilMs)
}

private func isolatedDefaults() throws -> (UserDefaults, String) {
    let suite = "OffWorkStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}
