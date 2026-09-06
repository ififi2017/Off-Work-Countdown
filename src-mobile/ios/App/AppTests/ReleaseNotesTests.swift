import Foundation
import Testing
@testable import App

@MainActor
struct ReleaseNotesTests {
    @Test func returningUserSeesUpdateUntilDismissed() throws {
        let suite = "release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")

        let firstLaunch = OffWorkStore(defaults: defaults, records: .inMemory())
        #expect(firstLaunch.showsReleaseNotes)
        let beforeDismissal = OffWorkStore(defaults: defaults, records: .inMemory())
        #expect(beforeDismissal.showsReleaseNotes)

        firstLaunch.dismissReleaseNotes()
        #expect(firstLaunch.showsReleaseNotes == false)
        #expect(firstLaunch.plus.hasSeenIntro)
        let nextLaunch = OffWorkStore(defaults: defaults, records: .inMemory())
        #expect(nextLaunch.showsReleaseNotes == false)
    }

    @Test func freshInstallDoesNotSeeAnUpgradeIntroduction() throws {
        let suite = "release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OffWorkStore(defaults: defaults, records: .inMemory())
        #expect(store.showsReleaseNotes == false)
        store.completeOnboarding(enableNotifications: false)
        let nextLaunch = OffWorkStore(defaults: defaults, records: .inMemory())
        #expect(nextLaunch.showsReleaseNotes == false)
        #expect(nextLaunch.plus.hasSeenIntro == false)
        #expect(ReleaseNotes.shouldPresent(onboardingComplete: true, seenRelease: "3.1.8"))
    }
}
