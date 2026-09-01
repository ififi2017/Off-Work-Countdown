import os

/// Signposts for cold launch. The first frame must not wait on StoreKit,
/// CloudKit, or the rules bundle — these intervals show which of those
/// still ran, and when.
nonisolated enum LaunchTrace {
    static let signposter = OSSignposter(
        subsystem: "com.rainif.offworkcountdown.macappstore",
        category: "launch"
    )

    @MainActor
    private static var appInit: OSSignpostIntervalState?

    @MainActor
    static func beginAppInit() {
        appInit = signposter.beginInterval("appInit")
    }

    @MainActor
    static func endAppInit() {
        if let appInit {
            signposter.endInterval("appInit", appInit)
            self.appInit = nil
        }
        signposter.emitEvent("rootFirstFrame")
    }

    static func interval<T>(_ name: StaticString, _ work: () -> T) -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return work()
    }

    static func interval<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await work()
    }
}
