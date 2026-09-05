import Testing
@testable import App

@MainActor
struct BrandCelebrationTimingTests {
    @Test func detentsFollowTheHandsAndSlowDownTogether() {
        let times = OWCMotion.brandCelebrationTickTimes + [OWCMotion.brandCelebrationDuration]
        var previousTime = 0.0
        var previousInterval = 0.0
        for (index, time) in times.enumerated() {
            let interval = time - previousTime
            #expect(interval > 0)
            #expect(interval >= previousInterval - 0.001)
            let progress = OWCMotion.brandCelebrationCurve.value(
                at: time / OWCMotion.brandCelebrationDuration
            )
            let degrees = progress * OWCMotion.brandCelebrationDegrees
            #expect(abs(degrees - Double(index + 1) * 45) < 0.05)
            previousTime = time
            previousInterval = interval
        }
        #expect(times.first! > 0.06)
        #expect(OWCMotion.brandCelebrationDuration - times[times.count - 2] > 0.3)
    }
}
