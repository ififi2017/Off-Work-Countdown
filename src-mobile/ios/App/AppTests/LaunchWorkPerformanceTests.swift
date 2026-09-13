import Foundation
import Testing
@testable import App

@MainActor
@Test("Measures shared launch work without a visible timer")
func launchWorkCost() async throws {
    let suite = "LaunchWorkPerformanceTests.\(UUID())"
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
    var lines: [String] = []
    func measure<T>(_ name: String, _ work: () -> T) -> T {
        let start = ContinuousClock.now
        let result = work()
        let duration = start.duration(to: .now).components
        let ms = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        lines.append("\(name): \(ms) ms")
        return result
    }
    for _ in 0..<3 {
        let snapshot = measure("snapshot") { store.session.snapshot(at: now) }
        #expect(snapshot != nil)
        _ = measure("reconcile") { store.shifts.reconcileCountdownSession(at: now) }
        _ = measure("default template") { store.focus.applyDefaultFocusTemplateIfNeeded(at: now) }
        let widget = measure("widget year") { WidgetSnapshotComposer.shared.publishedSnapshot(shifts: store.shifts, now: now) }
        #expect(!widget.entries.isEmpty)
    }
    let input = store.session.rulesInput(at: now, using: .base)
    let horizon = try #require(Calendar.current.date(byAdding: .day, value: 370, to: now))
    let expanded = await ScheduleRules.widgetShiftsInBackground(
        input: input, throughMs: horizon.timeIntervalSince1970 * 1_000, maximumCount: 400
    )
    let expected = WidgetSnapshotComposer.shared.publishedSnapshot(shifts: store.shifts, now: now)
    let actual = measure("compose precomputed widget") {
        WidgetSnapshotComposer.shared.publishedSnapshot(shifts: store.shifts, now: now, recurringShifts: expanded)
    }
    #expect(actual == expected)
    Attachment.record(lines.joined(separator: "\n"), named: "Launch work measurements")
}
