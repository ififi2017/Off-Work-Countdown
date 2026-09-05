import Foundation

/// Only a deliberate cluster of taps reveals the easter egg. Unrelated taps
/// over a long visit should not accumulate into an unexpected celebration.
struct BrandTapSequence {
    private var count = 0
    private var lastTap: TimeInterval?

    mutating func register(at time: TimeInterval) -> Bool {
        if let lastTap, time - lastTap > 1.2 || time < lastTap { count = 0 }
        lastTap = time
        count += 1
        guard count == 5 else { return false }
        count = 0
        return true
    }
}
