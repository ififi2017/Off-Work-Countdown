import Foundation
import Testing
@testable import App

@MainActor
struct ReleaseNotesTests {
    private func owners(_ defaults: UserDefaults) -> (PreferencesStore, PlusEntitlement) {
        (PreferencesStore(defaults: defaults, records: .inMemory()), PlusEntitlement(defaults: defaults))
    }

    @Test func returningUserSeesUpdateUntilDismissed() throws {
        let suite = "release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")

        let (firstPreferences, plus) = owners(defaults)
        let firstScene = SceneState(showsReleaseNotes: firstPreferences.shouldOfferReleaseNotes)
        #expect(firstScene.showsReleaseNotes)
        let (secondPreferences, _) = owners(defaults)
        let secondScene = SceneState(showsReleaseNotes: secondPreferences.shouldOfferReleaseNotes)
        #expect(secondScene.showsReleaseNotes)

        firstScene.dismissReleaseNotes(preferences: firstPreferences, plus: plus)
        #expect(!firstScene.showsReleaseNotes)
        #expect(plus.hasSeenIntro)
        let (nextPreferences, _) = owners(defaults)
        #expect(!nextPreferences.shouldOfferReleaseNotes)
        #expect(secondScene.showsReleaseNotes)
    }

    @Test func freshInstallDoesNotSeeAnUpgradeIntroduction() throws {
        let suite = "release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (preferences, plus) = owners(defaults)
        #expect(!preferences.shouldOfferReleaseNotes)
        preferences.completeSetup(enableNotifications: false)
        let (nextPreferences, _) = owners(defaults)
        #expect(!nextPreferences.shouldOfferReleaseNotes)
        #expect(!plus.hasSeenIntro)
        #expect(ReleaseNotes.shouldPresent(onboardingComplete: true, seenRelease: "3.1.8"))
    }
}
