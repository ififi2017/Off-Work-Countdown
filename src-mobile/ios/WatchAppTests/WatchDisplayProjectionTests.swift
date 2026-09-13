import Testing
@testable import DoneAtWatchApp

@Suite("Watch display availability")
struct WatchDisplayProjectionTests {
    @Test("Missing and unusable cache values stay neutral")
    func unavailableValues() {
        #expect(WatchLocalizations.text("watchWaitingForIPhone", localeIdentifier: "en") == "Waiting for iPhone")
        #expect(WatchDisplayProjection.project(nil, nowMs: 100) == .waiting)
        let malformed = WatchSnapshotPackageV1(
            schemaVersion: 1, sourceGeneration: "phone", revision: 1,
            generatedAtMs: 500, expiresAtMs: 500,
            access: .init(schemaVersion: 1, revision: 1, verifiedAtMs: 100,
                          status: .lifetime, validUntilMs: nil),
            content: nil
        )
        #expect(WatchDisplayProjection.project(malformed, nowMs: 500) == .invalid)
    }
}
