import Foundation
import Testing
@testable import App

struct AppReviewPromptTests {
    private static let dayMs = 24.0 * 60 * 60 * 1_000

    private func finished(days: Int) -> AppReviewPromptState {
        var state = AppReviewPromptState()
        for day in 1...days { state.noteCompletion(dayKey: "2026-10-0\(day)") }
        return state
    }

    @Test func oneDayIsNotYetAHabit() {
        let state = finished(days: AppReviewPromptState.minimumCompletedDays - 1)
        #expect(!state.isDue(currentVersion: "3.2.1", nowMs: 1_000))
    }

    @Test func enoughDifferentDaysMakeItDue() {
        let state = finished(days: AppReviewPromptState.minimumCompletedDays)
        #expect(state.isDue(currentVersion: "3.2.1", nowMs: 1_000))
    }

    @Test func theSameDayCountsOnce() {
        var state = AppReviewPromptState()
        for _ in 0..<5 { state.noteCompletion(dayKey: "2026-10-01") }
        #expect(state.completedDays == 1)
    }

    @Test func continuingWorkRevokesThatDay() {
        var state = finished(days: 2)
        state.revokeCompletion(dayKey: "2026-10-02")
        #expect(state.completedDays == 1)
        state.noteCompletion(dayKey: "2026-10-02")
        #expect(state.completedDays == 2)
    }

    @Test func neverCannotBeRearmed() {
        var state = AppReviewPromptState()
        state.disable()
        for day in 1...5 { state.noteCompletion(dayKey: "2026-10-0\(day)") }
        #expect(!state.isDue(currentVersion: "3.2.1", nowMs: 1_000))
    }

    @Test func aRequestStartsTheCountAgain() {
        var state = finished(days: 3)
        state.recordTrigger(version: "3.2.1", atMs: 2_000)
        #expect(state.completedDays == 0)
        #expect(state.lastTriggeredVersion == "3.2.1")
        #expect(state.lastTriggeredAtMs == 2_000)
    }

    @Test func notTwiceInOneVersion() {
        var state = finished(days: 3)
        state.recordTrigger(version: "3.2.1", atMs: 2_000)
        for day in 4...6 { state.noteCompletion(dayKey: "2026-10-0\(day)") }
        let later = 2_000 + Double(AppReviewPromptState.minimumIntervalDays + 1) * Self.dayMs
        #expect(!state.isDue(currentVersion: "3.2.1", nowMs: later))
        #expect(state.isDue(currentVersion: "3.2.2", nowMs: later))
    }

    @Test func notWithinTheMinimumInterval() {
        var state = finished(days: 3)
        state.recordTrigger(version: "3.2.1", atMs: 2_000)
        for day in 4...6 { state.noteCompletion(dayKey: "2026-10-0\(day)") }
        let tooSoon = 2_000 + Double(AppReviewPromptState.minimumIntervalDays - 1) * Self.dayMs
        #expect(!state.isDue(currentVersion: "3.2.2", nowMs: tooSoon))
    }

    /// State saved by 3.2.0 and earlier: a completion armed for the next
    /// launch. It decodes, and does not prompt on the upgrade's first launch.
    @Test func legacyLaunchArmedStateDoesNotPromptAfterUpdate() throws {
        let legacy = #"{"phase":"readyForNextLaunch","readyCompletionAtMs":1000}"#
        let state = try JSONDecoder().decode(AppReviewPromptState.self, from: Data(legacy.utf8))
        #expect(state.phase == .readyForNextLaunch)
        #expect(!state.isDue(currentVersion: "3.2.1", nowMs: 2_000))
        #expect(state.lastAttemptDayKey == nil)
    }

    private func open(
        nowMs: Double = 10_000,
        todayKey: String = "2026-10-21",
        offWorkAtMs: Double? = 5_000,
        finishedShiftDayKey: String? = nil,
        blocker: ReviewPromptBlocker = .none
    ) -> ReviewForeground {
        ReviewForeground(
            nowMs: nowMs, todayKey: todayKey, offWorkAtMs: offWorkAtMs,
            finishedShiftDayKey: finishedShiftDayKey, blocker: blocker
        )
    }

    @Test func twoFinishedDaysAreDueAndOneIsNot() {
        #expect(AppReviewPromptState.minimumCompletedDays == 2)
        var one = finished(days: 1)
        #expect(!one.onForeground(open(finishedShiftDayKey: "2026-10-01"), currentVersion: "3.2.1"))
        #expect(one.lastAttemptDayKey == nil)
        #expect(one.completedDays == 1)
        var two = finished(days: 2)
        #expect(two.onForeground(open(finishedShiftDayKey: "2026-10-02"), currentVersion: "3.2.1"))
        #expect(two.lastAttemptDayKey == "2026-10-21")
        #expect(two.completedDays == 0)
    }

    @Test func theFirstForegroundAfterOffWorkAsksAndTheNextOpenThatDayDoesNot() {
        var state = finished(days: 2)
        #expect(!state.onForeground(open(nowMs: 4_999, offWorkAtMs: 5_000, finishedShiftDayKey: nil), currentVersion: "3.2.1"))
        #expect(state.lastAttemptDayKey == nil)
        #expect(state.onForeground(open(nowMs: 5_000, offWorkAtMs: 5_000), currentVersion: "3.2.1"))
        #expect(!state.onForeground(open(nowMs: 20_000), currentVersion: "3.2.1"))
    }

    @Test func aMorningOpenDoesNotUseUpTheForegroundAfterOffWork() {
        var state = finished(days: 2)
        #expect(!state.onForeground(open(nowMs: 1_000, offWorkAtMs: 8_000, finishedShiftDayKey: nil), currentVersion: "3.2.1"))
        #expect(state.lastAttemptDayKey == nil)
        #expect(state.onForeground(open(nowMs: 8_000, offWorkAtMs: 8_000), currentVersion: "3.2.1"))
    }

    @Test func aBlockingLayerDefersWithoutConsumingTheDaysAttempt() {
        for blocker in [ReviewPromptBlocker.paywall, .lifetimeGift, .whatsNew] {
            var state = finished(days: 2)
            #expect(!state.onForeground(open(blocker: blocker), currentVersion: "3.2.1"))
            #expect(state.lastAttemptDayKey == nil)
            #expect(state.completedDays == 2)
            #expect(state.onForeground(open(nowMs: 12_000), currentVersion: "3.2.1"))
        }
    }

    @Test func theFinishingOpenCountsThatDayBeforeTheThreshold() {
        var one = finished(days: 1)
        #expect(one.onForeground(open(finishedShiftDayKey: "2026-10-02", todayKey: "2026-10-02"), currentVersion: "3.2.1"))
        var none = AppReviewPromptState()
        #expect(!none.onForeground(open(finishedShiftDayKey: "2026-10-01"), currentVersion: "3.2.1"))
        #expect(none.completedDays == 1)
        #expect(none.lastAttemptDayKey == nil)
    }

    @Test func aRestDayDoesNotAsk() {
        var state = finished(days: 2)
        #expect(!state.onForeground(open(offWorkAtMs: nil, finishedShiftDayKey: nil), currentVersion: "3.2.1"))
        #expect(state.lastAttemptDayKey == nil)
    }

#if DEBUG
    @Test func ignoringThresholdsStillWaitsForOffWorkAndAClearOpen() {
        var state = AppReviewPromptState()
        #expect(!state.onForegroundIgnoringThresholds(open(nowMs: 1_000, offWorkAtMs: 5_000, finishedShiftDayKey: nil)))
        #expect(state.lastAttemptDayKey == nil)
        #expect(!state.onForegroundIgnoringThresholds(open(blocker: .whatsNew)))
        #expect(state.lastTriggeredVersion == nil)
        #expect(state.onForegroundIgnoringThresholds(open()))
        #expect(state.lastAttemptDayKey == "2026-10-21")
        #expect(state.lastTriggeredVersion == nil)
        #expect(!state.onForegroundIgnoringThresholds(open(nowMs: 11_000)))
    }

    @Test func aManualOptOutStillBlocksTheThresholdOverride() {
        var state = finished(days: 2)
        state.disable()
        #expect(!state.onForegroundIgnoringThresholds(open()))
    }
#endif
}
