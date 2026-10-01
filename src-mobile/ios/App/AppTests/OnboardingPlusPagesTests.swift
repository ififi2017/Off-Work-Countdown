import Testing
@testable import App

@MainActor
@Test("Plus previews sit between adaptive layout and the finale")
func onboardingSequenceIncludesPlusPreviews() {
    for includesAllSet in [false, true] {
        let pages = OnboardingPages.sequence(includesAllSet: includesAllSet)
        let adaptive = pages.firstIndex(of: OnboardingPages.adaptiveLayouts)
        let records = pages.firstIndex(of: OnboardingPages.plusRecords)
        let focus = pages.firstIndex(of: OnboardingPages.plusFocus)
        let leave = pages.firstIndex(of: OnboardingPages.plusLeave)
        let finale = pages.firstIndex(of: OnboardingPages.finale)

        #expect(records == adaptive.map { $0 + 1 })
        #expect(focus == records.map { $0 + 1 })
        #expect(leave == focus.map { $0 + 1 })
        #expect(finale == leave.map { $0 + 1 })
    }
    #expect(OnboardingPages.count == OnboardingPages.finale + 1)
}
