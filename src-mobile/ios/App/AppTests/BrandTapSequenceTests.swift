import Testing
@testable import App

@MainActor
struct BrandTapSequenceTests {
    @Test func requiresFiveNearbyTapsAndStartsANewSequenceAfterPlayback() {
        var taps = BrandTapSequence()
        for index in 0..<10 {
            let triggered = taps.register(at: Double(index) * 0.2)
            #expect(triggered == (index == 4 || index == 9))
        }
    }

    @Test func pauseOrClockChangeStartsANewSequence() {
        for nextTap in [3.0, -1.0] {
            var taps = BrandTapSequence()
            for index in 0..<4 {
                let triggered = taps.register(at: Double(index) * 0.2)
                #expect(!triggered)
            }
            for index in 0..<5 {
                let triggered = taps.register(at: nextTap + Double(index) * 0.2)
                #expect(triggered == (index == 4))
            }
        }
    }
}
