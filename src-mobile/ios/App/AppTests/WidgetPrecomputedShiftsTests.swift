import Foundation
import Testing
@testable import App

@MainActor
@Test("Launch work composes the same widget snapshot from precomputed recurring shifts")
func precomputedRecurringShiftsMatchTheWidgetSnapshot() async throws {
    let suite = "WidgetPrecomputedShiftsTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AppRuntime(defaults: defaults, records: .inMemory())
    store.preferences.onboardingComplete = true
    store.plus.debugSetAuthorized(true)
    store.preferences.applyPreferences { $0.scheduleMode = .classic }
    store.preferences.applyPreferences { $0.workdays = [1, 2, 3, 4, 5] }
    store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
    store.preferences.applyPreferences { $0.endMinutes = 18 * 60 }
    let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 19)))
    #expect(store.session.snapshot(at: now) != nil)
    _ = store.shifts.reconcileCountdownSession(at: now)
    _ = store.focus.applyDefaultFocusTemplateIfNeeded(at: now)
    let expected = WidgetSnapshotComposer.shared.publishedSnapshot(shifts: store.shifts, now: now)
    #expect(!expected.entries.isEmpty)

    let input = store.session.rulesInput(at: now, using: .base)
    let horizon = try #require(Calendar.current.date(byAdding: .day, value: 370, to: now))
    let expanded = await ScheduleRules.widgetShiftsInBackground(
        input: input, throughMs: horizon.timeIntervalSince1970 * 1_000, maximumCount: 400
    )
    let actual = WidgetSnapshotComposer.shared.publishedSnapshot(shifts: store.shifts, now: now, recurringShifts: expanded)
    #expect(actual == expected)
}
