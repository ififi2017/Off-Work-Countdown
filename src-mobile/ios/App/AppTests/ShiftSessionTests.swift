import Foundation
import Testing
@testable import App

@MainActor
@Suite("Shift state and projections")
struct ShiftSessionTests {
    @Test("A standalone session queries shared rules and restores its frozen early finish")
    func standaloneSession() throws {
        let suite = "ShiftSession.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        let records = RecordCoordinator.inMemory()
        let preferences = PreferencesStore(defaults: defaults, records: records)
        let text = AppText(preferences: preferences)
        let session = ShiftSession(defaults: defaults, preferences: preferences, text: text)
        let date = try #require(preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        let initial = records.state
        let shift = try #require(session.snapshot(at: date))
        let expected = try CountdownRules.shared.snapshot(input: session.rulesInput(at: date))
        #expect(shift.segments == expected.segments)
        #expect(shift.isWorkday)
        session.earlyOffAtMs = date.timeIntervalSince1970 * 1_000
        session.earlyOffShiftEndAtMs = shift.endAtMs
        session.earlyOffSnapshot = shift
        let restored = ShiftSession(defaults: defaults, preferences: preferences, text: text)
        let later = try #require(restored.snapshot(at: date.addingTimeInterval(2 * 3600)))
        #expect(restored.isEndedEarly(later))
        #expect(restored.clockOffSnapshot(for: later).remainingMs == shift.remainingMs)
        #expect(restored.clockOffSnapshot(for: later).progress == shift.progress)
        #expect(later.remainingMs < shift.remainingMs)
        #expect(records.state == initial)
    }

    @Test("Automatic countdown migration arms a configured device once and preserves an explicit stop")
    func legacyMigration() throws {
        let suite = "ShiftSessionMigration.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let preferences = PreferencesStore(defaults: defaults, records: .inMemory())
        let text = AppText(preferences: preferences)
        let session = ShiftSession(defaults: defaults, preferences: preferences, text: text)
        #expect(session.countdownStarted)
        session.countdownStarted = false
        let reopened = ShiftSession(defaults: defaults, preferences: preferences, text: text)
        #expect(!reopened.countdownStarted)
    }

    @Test("Feature readers retain their real inputs without retaining the old application store")
    func readerOwnership() throws {
        let suite = "ShiftSessionOwnership.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        var application: AppRuntime? = AppRuntime(defaults: defaults, records: .inMemory())
        weak var oldOwner: AppRuntime?
        oldOwner = application
        let preferences = try #require(application?.preferences)
        let queries = try #require(application?.queries)
        let life = try #require(application?.life)
        let focus = try #require(application?.focus)
        let date = try #require(preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        application = nil
        #expect(oldOwner == nil)
        preferences.applyPreferences { $0.endMinutes = 19 * 60 }
        #expect(queries.rulesInput(at: date)?.endTime == "19:00")
        #expect(life.lifeSummaryRefreshInput(now: date).hours.endTime == "19:00")
        let expectedEnd = try #require(preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 19)))
        #expect(focus.snapshot(at: date)?.endAtMs == expectedEnd.timeIntervalSince1970 * 1_000)
    }
}
