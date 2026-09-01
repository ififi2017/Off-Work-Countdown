import Testing
@testable import App

struct AppReviewAndCycleSummaryTests {
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

    @Test func summaryUsesTheContiguousWorkRunBeforeRest() {
        let days = [
            ScheduleCycleDay(dayKey: "2026-08-30", isWorkday: false, workMs: 0, overtimeMs: 0),
            ScheduleCycleDay(dayKey: "2026-08-31", isWorkday: true, workMs: 8, overtimeMs: 1),
            ScheduleCycleDay(dayKey: "2026-09-01", isWorkday: true, workMs: 7, overtimeMs: 2),
            ScheduleCycleDay(dayKey: "2026-09-02", isWorkday: false, workMs: 0, overtimeMs: 0),
        ]

        #expect(
            ScheduleCycleSummaryCalculator.summary(endingAt: "2026-09-01", in: days)
                == ScheduleCycleSummary(workdayCount: 2, workMs: 15, overtimeMs: 3)
        )
    }

    @Test func summaryOnlyExistsAtTheEndOfACycle() {
        let days = [
            ScheduleCycleDay(dayKey: "2026-08-31", isWorkday: true, workMs: 8, overtimeMs: 0),
            ScheduleCycleDay(dayKey: "2026-09-01", isWorkday: true, workMs: 8, overtimeMs: 0),
            ScheduleCycleDay(dayKey: "2026-09-02", isWorkday: false, workMs: 0, overtimeMs: 0),
        ]

        #expect(ScheduleCycleSummaryCalculator.summary(endingAt: "2026-08-31", in: days) == nil)
    }

    @Test func unresolvedFollowingDayDoesNotPretendToEndACycle() {
        let days = [
            ScheduleCycleDay(dayKey: "2026-09-01", isWorkday: true, workMs: 8, overtimeMs: 0),
            ScheduleCycleDay(
                dayKey: "2026-09-02",
                isWorkday: false,
                workMs: 0,
                overtimeMs: 0,
                isComplete: false
            ),
        ]

        #expect(ScheduleCycleSummaryCalculator.summary(endingAt: "2026-09-01", in: days) == nil)
    }
}
