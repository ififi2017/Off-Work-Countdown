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

    // MARK: - Throttling

    @Test func shouldTriggerWhenNoThrottlingRecorded() {
        var state = AppReviewPromptState()
        state.noteCompletion(atMs: 1_000)
        #expect(state.shouldTriggerSystemReview(currentVersion: "3.2.1", nowMs: 2_000))
    }

    @Test func shouldNotTriggerWhenNotReadyForLaunch() {
        let state = AppReviewPromptState()
        #expect(!state.shouldTriggerSystemReview(currentVersion: "3.2.1", nowMs: 2_000))
    }

    @Test func shouldNotTriggerForSameVersion() {
        var state = AppReviewPromptState()
        state.noteCompletion(atMs: 1_000)
        state.recordTrigger(version: "3.2.1", atMs: 2_000)
        state.noteCompletion(atMs: 3_000)
        #expect(!state.shouldTriggerSystemReview(currentVersion: "3.2.1", nowMs: 4_000))
    }

    @Test func shouldTriggerForNewVersion() {
        var state = AppReviewPromptState()
        state.noteCompletion(atMs: 1_000)
        state.recordTrigger(version: "3.2.1", atMs: 2_000)
        state.noteCompletion(atMs: 3_000)
        let oldEnoughMs = 2_000 + Double(AppReviewPromptState.minimumIntervalDays) * 24 * 60 * 60 * 1_000 + 1_000
        #expect(state.shouldTriggerSystemReview(currentVersion: "3.2.2", nowMs: oldEnoughMs))
    }

    @Test func shouldNotTriggerWithinMinimumInterval() {
        var state = AppReviewPromptState()
        state.noteCompletion(atMs: 1_000)
        state.recordTrigger(version: "3.2.1", atMs: 2_000)
        state.noteCompletion(atMs: 3_000)
        let tooSoonMs = 2_000 + Double(AppReviewPromptState.minimumIntervalDays - 1) * 24 * 60 * 60 * 1_000
        #expect(!state.shouldTriggerSystemReview(currentVersion: "3.2.2", nowMs: tooSoonMs))
    }

    @Test func shouldTriggerAfterMinimumInterval() {
        var state = AppReviewPromptState()
        state.noteCompletion(atMs: 1_000)
        state.recordTrigger(version: "3.2.1", atMs: 2_000)
        state.noteCompletion(atMs: 3_000)
        let oldEnoughMs = 2_000 + Double(AppReviewPromptState.minimumIntervalDays) * 24 * 60 * 60 * 1_000 + 1_000
        #expect(state.shouldTriggerSystemReview(currentVersion: "3.2.2", nowMs: oldEnoughMs))
    }

    @Test func recordTriggerResetsToWaitingForCompletion() {
        var state = AppReviewPromptState()
        state.noteCompletion(atMs: 1_000)
        #expect(state.phase == .readyForNextLaunch)
        state.recordTrigger(version: "3.2.1", atMs: 2_000)
        #expect(state.phase == .waitingForCompletion)
        #expect(state.lastTriggeredVersion == "3.2.1")
        #expect(state.lastTriggeredAtMs == 2_000)
    }
}
