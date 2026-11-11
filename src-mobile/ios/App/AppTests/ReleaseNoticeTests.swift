import Testing
@testable import App

/// 3.3.0: one "see what's new" notice for someone who updated but has not
/// opened the app; opening it shows the page instead.
@Suite("Release notice") @MainActor
struct ReleaseNoticeTests {
    @Test func postsOnceForAnUnopenedUpdate() {
        // Test builds show the automation settings, so 3.3.0 is current.
        #expect(ReleaseNotes.current == "3.3.0")
        #expect(ReleaseNotes.shouldPostNotice(onboardingComplete: true, seenRelease: "3.2.3", noticeSent: nil))
        #expect(!ReleaseNotes.shouldPostNotice(onboardingComplete: true, seenRelease: "3.2.3", noticeSent: "3.3.0"))
        #expect(!ReleaseNotes.shouldPostNotice(onboardingComplete: true, seenRelease: "3.3.0", noticeSent: nil))
        // A new install mid-onboarding has nothing to be told about.
        #expect(!ReleaseNotes.shouldPostNotice(onboardingComplete: false, seenRelease: nil, noticeSent: nil))
    }
}
