import Testing
@testable import App

struct AppReviewPromptTests {
    @Test func completionOnlyArmsTheNextLaunch() {
        var state = AppReviewPromptState()
        state.noteCompletion(atMs: 1_000)

        #expect(state.phase == .readyForNextLaunch)
        let eligible = state.isEligibleOnLaunch(trackedCompletionAtMs: nil, nowMs: 1_100)
        #expect(eligible)
    }

    @Test func laterRequiresANewerCompletion() {
        var state = AppReviewPromptState()
        state.noteCompletion(atMs: 1_000)
        state.deferUntilNextCompletion()
        state.noteCompletion(atMs: 1_000)
        #expect(state.phase == .waitingForCompletion)

        state.noteCompletion(atMs: 2_000)
        #expect(state.phase == .readyForNextLaunch)
    }

    @Test func aCompletionWhileClosedIsEligibleAtLaunch() {
        var state = AppReviewPromptState()
        let eligible = state.isEligibleOnLaunch(trackedCompletionAtMs: 1_000, nowMs: 2_000)
        #expect(eligible)
    }

    @Test func neverCannotBeRearmed() {
        var state = AppReviewPromptState()
        state.disable()
        state.noteCompletion(atMs: 2_000)
        let eligible = state.isEligibleOnLaunch(trackedCompletionAtMs: 2_000, nowMs: 3_000)
        #expect(!eligible)
    }

    @Test func continuingWorkRevokesThePendingCompletion() {
        var state = AppReviewPromptState()
        state.noteCompletion(atMs: 1_000)
        state.revokeCompletion(atMs: 1_000)
        #expect(state.phase == .waitingForCompletion)
    }
}
