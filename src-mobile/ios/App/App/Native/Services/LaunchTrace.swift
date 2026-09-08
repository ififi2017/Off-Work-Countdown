import Foundation
import os

/// Signposts for cold launch. The first frame must not wait on StoreKit,
/// CloudKit, or the rules bundle — these intervals show which of those
/// still ran, and when.
nonisolated enum LaunchTrace {
    static let signposter = OSSignposter(
        subsystem: "com.rainif.offworkcountdown.macappstore",
        category: .pointsOfInterest
    )

    @MainActor
    private static var appInit: OSSignpostIntervalState?

    @MainActor private static var appInitStarted: ContinuousClock.Instant?

    @MainActor
    static func beginAppInit() {
        appInit = signposter.beginInterval("appInit")
        appInitStarted = .now
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-owcLaunchProfile") else { return }
        Task { @MainActor in
            let start = ContinuousClock.now
            var previous = start
            var maximum = Duration.zero
            for _ in 0..<3_000 {
                try? await Task.sleep(for: .milliseconds(20))
                let now = ContinuousClock.now
                let gap = previous.duration(to: now)
                maximum = max(maximum, gap)
                if gap > .milliseconds(100) {
                    print("[LaunchWork] main actor gap: \(gap), at \(start.duration(to: now))")
                }
                previous = now
            }
            print("[LaunchWork] largest main actor gap: \(maximum)")
        }
#endif
    }

    @MainActor
    static func endAppInit() {
        if let appInit {
            signposter.endInterval("appInit", appInit)
            self.appInit = nil
        }
        signposter.emitEvent("rootFirstFrame")
        if let appInitStarted {
            report("appInitToRootTask", since: appInitStarted)
            self.appInitStarted = nil
        }
    }

    static func report(_ name: StaticString, since started: ContinuousClock.Instant) {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-owcLaunchProfile") else { return }
        let elapsed = started.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        print("[LaunchWork] \(name): \(milliseconds) ms")
#endif
    }

    static func interval<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let started = ContinuousClock.now
        let state = signposter.beginInterval(name)
        defer {
            signposter.endInterval(name, state)
            report(name, since: started)
        }
        return try work()
    }

    static func interval<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let started = ContinuousClock.now
        let state = signposter.beginInterval(name)
        defer {
            signposter.endInterval(name, state)
            report(name, since: started)
        }
        return try await work()
    }
}
