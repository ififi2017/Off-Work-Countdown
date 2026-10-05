import Testing
@testable import App

@MainActor
@Suite struct OnboardingJourneyTests {
@Test("Six pages: setup first, then the free surfaces, then Plus last")
func onboardingSequenceEndsWithPlus() {
    #expect(OnboardingPages.sequence == [
        OnboardingPages.landing, OnboardingPages.schedule, OnboardingPages.reminders,
        OnboardingPages.ready, OnboardingPages.glance, OnboardingPages.plus,
    ])
    #expect(OnboardingPages.count == OnboardingPages.sequence.count)
    #expect(OnboardingPages.sequence.last == OnboardingPages.plus)
}

}
