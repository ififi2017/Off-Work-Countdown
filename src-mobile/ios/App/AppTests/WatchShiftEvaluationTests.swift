import Testing
@testable import App

@Suite("Watch absolute-segment evaluation")
struct WatchShiftEvaluationTests {
    @Test("Swift matches TypeScript-generated projections", arguments: WatchShiftEvaluationFixtures.all)
    func matchesSharedRules(_ fixture: WatchShiftEvaluationFixture) throws {
        let result = try #require(WatchShiftEvaluator.evaluate(fixture.shift, nowMs: fixture.nowMs))
        #expect(result.phase == fixture.expected.phase)
        #expect(result.totalMs == fixture.expected.totalMs)
        #expect(result.elapsedMs == fixture.expected.elapsedMs)
        #expect(result.remainingMs == fixture.expected.remainingMs)
        #expect(abs(result.progress - fixture.expected.progress) < 0.000_001)
        #expect(result.nextBoundaryAtMs == fixture.expected.nextBoundaryAtMs)
    }

    @Test("Malformed absolute segments fail closed")
    func rejectsMalformedSegments() {
        let malformed = WatchShiftProjectionV1(
            segments: [.init(startAtMs: 200, endAtMs: 400), .init(startAtMs: 300, endAtMs: 500)],
            plannedEndAtMs: 500,
            overtimeEndAtMs: nil,
            finishedAtMs: nil,
            isRunning: true,
            transitions: []
        )
        #expect(WatchShiftEvaluator.evaluate(malformed, nowMs: 350) == nil)
        #expect(WatchShiftEvaluator.evaluate(malformed, nowMs: -1) == nil)
    }
}
