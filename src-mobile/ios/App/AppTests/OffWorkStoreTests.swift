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

private func isolatedDefaults() throws -> (UserDefaults, String) {
    let suite = "OffWorkStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}
