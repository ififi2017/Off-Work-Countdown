import Foundation
import Testing
@testable import App

@Suite("Watch snapshot pairing cache")
struct WatchSnapshotCacheTests {
    @Test("Only a live pairing challenge may establish or replace a generation")
    func challengeAdmission() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let cache = await WatchSnapshotCache.open(fileURL: file, newPairingSession: "pair")
        #expect(await cache.receiveApplicationContext(encoded(package())) == .rejected(.rejectWrongGeneration))

        let old = await cache.makePairingHello(nonce: "old")
        let current = await cache.makePairingHello(nonce: "current")
        #expect(await cache.receivePairingReply(reply(package(), hello: old)) == .rejected(.rejectBaseline))
        #expect(await cache.receivePairingReply(reply(package(), hello: current, session: "wrong")) == .rejected(.rejectBaseline))
        #expect(await cache.receivePairingReply(reply(package(), hello: current)) == .accepted)
        #expect(await cache.receivePairingReply(reply(package(), hello: current)) == .rejected(.rejectBaseline))

        let cancelled = await cache.makePairingHello(nonce: "cancelled")
        await cache.cancelPairing()
        #expect(await cache.receivePairingReply(reply(package(generation: "b"), hello: cancelled, replaces: "a")) == .rejected(.rejectBaseline))

        let wrongSource = await cache.makePairingHello(nonce: "wrong-source")
        #expect(await cache.receivePairingReply(reply(package(generation: "b"), hello: wrongSource, baselineGeneration: "c", replaces: "a")) == .rejected(.rejectBaseline))
        let wrongReplacement = await cache.makePairingHello(nonce: "wrong-replacement")
        #expect(wrongReplacement.acceptedGeneration == "a")
        #expect(await cache.receivePairingReply(reply(package(generation: "b"), hello: wrongReplacement)) == .rejected(.rejectBaseline))
        let replacement = await cache.makePairingHello(nonce: "replacement")
        #expect(await cache.receivePairingReply(reply(package(generation: "b", revision: 0), hello: replacement, replaces: "a")) == .accepted)
        #expect(await cache.receiveApplicationContext(encoded(package(generation: "a", revision: 99))) == .rejected(.rejectWrongGeneration))
    }

    @Test("Failed persistence retains the challenge and old package for retry")
    func failedWriteRetry() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let writer = RecordingWriter(failingCalls: [2])
        let cache = await WatchSnapshotCache.open(fileURL: file, writer: writer.write, newPairingSession: "pair")
        #expect(await pair(package(), cache: cache) == .accepted)
        let oldBytes = try Data(contentsOf: file)
        let hello = await cache.makePairingHello(nonce: "retry")
        let data = reply(package(generation: "b", revision: 0), hello: hello, replaces: "a")
        #expect(await cache.receivePairingReply(data) == .persistenceFailed)
        #expect(await cache.currentPackage() == package())
        #expect(try Data(contentsOf: file) == oldBytes)
        #expect(await cache.receivePairingReply(data) == .accepted)
        #expect(writer.callCount == 3)
    }

    @Test("Restart rejects the old nonce and restores the accepted session")
    func restartInvalidatesChallenge() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let cache = await WatchSnapshotCache.open(fileURL: file, newPairingSession: "pair")
        #expect(await pair(package(), cache: cache) == .accepted)
        let oldHello = await cache.makePairingHello(nonce: "old")
        let oldReply = reply(package(generation: "b", revision: 0), hello: oldHello, replaces: "a")

        let reopened = await WatchSnapshotCache.open(fileURL: file, newPairingSession: "ignored")
        #expect(await reopened.receivePairingReply(oldReply) == .rejected(.rejectBaseline))
        let newHello = await reopened.makePairingHello(nonce: "new")
        #expect(newHello.pairingSession == "pair")
        #expect(await reopened.receivePairingReply(reply(package(generation: "b", revision: 0), hello: newHello, replaces: "a")) == .accepted)
    }

    @Test("Duplicate and stale context deliveries never rewrite the cache")
    func orderingDoesNotRewrite() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let writer = RecordingWriter()
        let cache = await WatchSnapshotCache.open(fileURL: file, writer: writer.write, newPairingSession: "pair")
        let first = package(revision: 4)
        #expect(await pair(first, cache: cache) == .accepted)
        #expect(await cache.receiveApplicationContext(encoded(first)) == .duplicate)
        #expect(await cache.receiveApplicationContext(encoded(package(revision: 3))) == .rejected(.rejectStaleRevision))
        #expect(writer.callCount == 1)
    }

    @Test("A fresh challenge accepts a newer package from the current generation")
    func sameGenerationPairingRefresh() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let cache = await WatchSnapshotCache.open(fileURL: file, newPairingSession: "pair")
        #expect(await pair(package(revision: 4), cache: cache) == .accepted)
        let hello = await cache.makePairingHello(nonce: "refresh")
        #expect(hello.acceptedGeneration == "a")
        #expect(await cache.receiveApplicationContext(encoded(package(revision: 5))) == .accepted)
        #expect(await cache.receivePairingReply(reply(package(revision: 6), hello: hello)) == .accepted)
        #expect(await cache.currentPackage() == package(revision: 6))
    }

    @Test("A new phone install replaces the generation named by the Watch hello")
    func phoneReinstallReplacement() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let cache = await WatchSnapshotCache.open(fileURL: file, newPairingSession: "pair")
        #expect(await pair(package(generation: "phone-install-a"), cache: cache) == .accepted)
        let hello = await cache.makePairingHello(nonce: "phone-reinstall")
        #expect(hello.acceptedGeneration == "phone-install-a")
        #expect(await cache.receivePairingReply(reply(
            package(generation: "phone-install-b", revision: 0),
            hello: hello,
            replaces: "unrelated-generation"
        )) == .rejected(.rejectBaseline))
        #expect(await cache.receivePairingReply(reply(
            package(generation: "phone-install-b", revision: 0),
            hello: hello,
            replaces: "phone-install-a"
        )) == .accepted)
    }

    @Test("Retirement saturation atomically rotates pairing and survives restart")
    func retirementSaturationRecovery() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let cache = await WatchSnapshotCache.open(fileURL: file, newPairingSession: "pair")
        let initialHello = await cache.makePairingHello(nonce: "initial")
        #expect(await cache.receivePairingReply(reply(package(generation: "g0", revision: 0), hello: initialHello)) == .accepted)

        for index in 1...WatchSnapshotContract.maximumRetiredGenerations {
            let hello = await cache.makePairingHello(nonce: "rotation-\(index)")
            #expect(await cache.receivePairingReply(reply(
                package(generation: "g\(index)", revision: 0),
                hello: hello,
                replaces: "g\(index - 1)"
            )) == .accepted)
        }
        let saturatedHello = await cache.makePairingHello(nonce: "saturated")
        #expect(await cache.receivePairingReply(reply(
            package(generation: "g65", revision: 0),
            hello: saturatedHello,
            replaces: "g64"
        )) == .pairingResetRequired)
        #expect(await cache.currentPackage() == nil)

        let reopened = await WatchSnapshotCache.open(fileURL: file, newPairingSession: "ignored")
        #expect(await reopened.receiveApplicationContext(encoded(package(generation: "g65", revision: 0))) == .rejected(.rejectWrongGeneration))
        let freshHello = await reopened.makePairingHello(nonce: "fresh")
        #expect(freshHello.pairingSession != "pair")
        #expect(await reopened.receivePairingReply(reply(package(generation: "g65", revision: 0), hello: freshHello)) == .accepted)
        #expect(await reopened.receiveApplicationContext(encoded(package(generation: "g0", revision: 99))) == .rejected(.rejectWrongGeneration))
    }

    @Test("A corrupt cache starts empty and requires a fresh challenge")
    func corruptRecovery() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bad".utf8).write(to: file)
        let cache = await WatchSnapshotCache.open(fileURL: file, newPairingSession: "fresh")
        #expect(await cache.receiveApplicationContext(encoded(package())) == .rejected(.rejectWrongGeneration))
        #expect(await pair(package(), cache: cache) == .accepted)
    }

    @Test("Unknown salary fields never reach the persisted cache")
    func salarySentinelIsDiscarded() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let cache = await WatchSnapshotCache.open(fileURL: file, newPairingSession: "pair")
        let hello = await cache.makePairingHello(nonce: "salary")
        var object = try #require(JSONSerialization.jsonObject(with: encoded(package())) as? [String: Any])
        object["salary"] = "SALARY-SENTINEL-918273"
        let packageData = try JSONSerialization.data(withJSONObject: object)
        let pairingReply = WatchPairingReplyV1(
            schemaVersion: 1,
            pairingSession: hello.pairingSession,
            nonce: hello.nonce,
            baseline: .init(schemaVersion: 1, pairingSession: hello.pairingSession, sourceGeneration: "a", replacesGeneration: nil),
            packageData: packageData
        )
        #expect(await cache.receivePairingReply(encoded(pairingReply)) == .accepted)
        #expect(!String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("SALARY-SENTINEL-918273"))
    }

    private func pair(_ value: WatchSnapshotPackageV1, cache: WatchSnapshotCache) async -> WatchSnapshotCacheReceiveResult {
        let hello = await cache.makePairingHello(nonce: "nonce-\(value.sourceGeneration)-\(value.revision)")
        return await cache.receivePairingReply(reply(value, hello: hello))
    }

    private func reply(_ value: WatchSnapshotPackageV1, hello: WatchPairingHelloV1, session: String? = nil, baselineGeneration: String? = nil, replaces: String? = nil) -> Data {
        let pairingSession = session ?? hello.pairingSession
        return encoded(WatchPairingReplyV1(
            schemaVersion: 1,
            pairingSession: pairingSession,
            nonce: hello.nonce,
            baseline: .init(schemaVersion: 1, pairingSession: pairingSession, sourceGeneration: baselineGeneration ?? value.sourceGeneration, replacesGeneration: replaces),
            packageData: encoded(value)
        ))
    }

    private func encoded<T: Encodable>(_ value: T) -> Data { try! JSONEncoder().encode(value) }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "WatchCache-\(UUID().uuidString)/snapshot.json")
    }

    private func package(generation: String = "a", revision: UInt64 = 1) -> WatchSnapshotPackageV1 {
        .init(
            schemaVersion: 1, sourceGeneration: generation, revision: revision, generatedAtMs: 100, expiresAtMs: 2_000,
            access: .init(schemaVersion: 1, revision: revision, verifiedAtMs: 100, status: .lifetime, validUntilMs: nil),
            content: .init(scheduleState: .notConfigured, shift: nil, nextShift: nil, presentation: .init(localeIdentifier: "en", timeZoneIdentifier: "UTC", workingLabel: "Working", lunchLabel: "Lunch", restingLabel: "Resting", overtimeLabel: "Overtime", finishedLabel: "Finished"))
        )
    }
}

private final class RecordingWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let failingCalls: Set<Int>
    private var calls = 0

    init(failingCalls: Set<Int> = []) { self.failingCalls = failingCalls }
    var callCount: Int { lock.withLock { calls } }

    func write(_ data: Data, to url: URL) throws {
        let fails = lock.withLock { calls += 1; return failingCalls.contains(calls) }
        if fails { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
