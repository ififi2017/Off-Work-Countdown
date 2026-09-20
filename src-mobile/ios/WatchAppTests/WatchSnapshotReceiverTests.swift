import Foundation
import Testing
@testable import DoneAtWatchApp

@MainActor
@Suite("Watch snapshot receiver")
struct WatchSnapshotReceiverTests {
    @Test("A phone reply to the Watch's own hello publishes, reloads widgets once and survives restart")
    func pairingReplyLifecycle() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let transport = RecordingTransport()
        let model = WatchAppModel()
        let receiver = WatchSnapshotReceiver(model: model, cacheURL: file, transport: transport.value)
        await receiver.start()
        #expect(model.connectionState == .waiting)
        #expect(model.package == nil)

        // Before any pairing baseline, a context cannot establish a source.
        await receiver.receiveContext(encoded(package(revision: 1)))
        #expect(model.package == nil)
        #expect(transport.reloads == 0)

        // Receiving an unbound source now starts pairing automatically, even
        // when no foreground view has requested it.
        #expect(transport.sent.count == 1)
        let request = try #require(transport.sent.first)
        let hello = try JSONDecoder().decode(WatchPairingHelloV1.self, from: request.data)
        // The system reply block: called off the main actor in production.
        request.reply(pairingReply(package(revision: 1), hello: hello))
        // Admission is synchronous, before the main-actor cache task can run.
        #expect(receiver.pendingDeliveryCountForTesting == 1)
        await waitUntil { model.connectionState == .ready && receiver.pendingDeliveryCountForTesting == 0 }
        #expect(receiver.pendingDeliveryCountForTesting == 0)
        #expect(model.package == package(revision: 1))
        #expect(transport.reloads == 1)

        await receiver.receiveContext(encoded(package(revision: 1)))
        #expect(transport.reloads == 1)

        await receiver.receiveContext(encoded(package(revision: 2)))
        #expect(model.package?.revision == 2)
        #expect(transport.reloads == 2)

        await receiver.receiveContext(Data("{}".utf8))
        #expect(model.package?.revision == 2)
        #expect(transport.reloads == 2)

        let restoredModel = WatchAppModel()
        let restoredTransport = RecordingTransport()
        let restored = WatchSnapshotReceiver(
            model: restoredModel, cacheURL: file, transport: restoredTransport.value)
        await restored.start()
        #expect(restoredModel.connectionState == .ready)
        #expect(restoredModel.package?.revision == 2)
        #expect(restoredTransport.reloads == 1)
        restored.refreshWidgets()
        #expect(restoredTransport.reloads == 2)
    }

    @Test("A paired V1 cache upgrades to free V2 and cannot be downgraded by a late V1 package")
    func v1ToV2Upgrade() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let transport = RecordingTransport()
        let model = WatchAppModel()
        let receiver = WatchSnapshotReceiver(model: model, cacheURL: file, transport: transport.value)
        await receiver.start()

        await receiver.receiveContext(encoded(package(revision: 1)))
        let request = try #require(transport.sent.first)
        let hello = try JSONDecoder().decode(WatchPairingHelloV1.self, from: request.data)
        request.reply(pairingReply(package(revision: 1), hello: hello))
        await waitUntil { model.package?.revision == 1 && receiver.pendingDeliveryCountForTesting == 0 }

        let upgrade = v2Package(revision: 3)
        await receiver.receiveContext(encoded(upgrade))
        #expect(model.package == upgrade)
        #expect(model.package?.access.status == .free)

        let restoredModel = WatchAppModel()
        let restored = WatchSnapshotReceiver(
            model: restoredModel, cacheURL: file, transport: RecordingTransport().value)
        await restored.start()
        #expect(restoredModel.package == upgrade)
        #expect(restoredModel.package?.schemaVersion == 2)

        await restored.receiveContext(encoded(package(revision: 4)))
        #expect(restoredModel.package == upgrade)
        #expect(restoredModel.package?.access.status == .free)
    }

    @Test("An unreachable phone receives no pairing request")
    func unreachablePhoneSendsNothing() async {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let transport = RecordingTransport(ready: false)
        let receiver = WatchSnapshotReceiver(model: WatchAppModel(), cacheURL: file, transport: transport.value)
        await receiver.start()
        await receiver.requestPairing()
        #expect(transport.sent.isEmpty)
    }

    @Test("First launch, damaged cache and future schema have distinct states")
    func cacheLoadStates() async throws {
        let transport = RecordingTransport()
        defer { withExtendedLifetime(transport) {} }
        let directory = FileManager.default.temporaryDirectory.appending(path: "WatchReceiver-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let emptyURL = directory.appending(path: "empty.json")
        let emptyModel = WatchAppModel()
        await WatchSnapshotReceiver(model: emptyModel, cacheURL: emptyURL,
                                    transport: transport.value).start()
        #expect(emptyModel.connectionState == .waiting)

        let corruptURL = directory.appending(path: "corrupt.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("bad".utf8).write(to: corruptURL)
        let corruptModel = WatchAppModel()
        await WatchSnapshotReceiver(model: corruptModel, cacheURL: corruptURL,
                                    transport: transport.value).start()
        #expect(corruptModel.connectionState == .cacheCorrupt)

        let futureURL = directory.appending(path: "future.json")
        let future: [String: Any] = [
            "pairingSession": "pair", "package": ["schemaVersion": 99],
            "order": ["retiredGenerations": []]
        ]
        try JSONSerialization.data(withJSONObject: future).write(to: futureURL)
        let futureModel = WatchAppModel()
        await WatchSnapshotReceiver(model: futureModel, cacheURL: futureURL,
                                    transport: transport.value).start()
        #expect(futureModel.connectionState == .cacheIncompatible)

        let incomingModel = WatchAppModel()
        let incoming = WatchSnapshotReceiver(
            model: incomingModel, cacheURL: directory.appending(path: "incoming.json"),
            transport: transport.value)
        await incoming.start()
        var futurePackage = try #require(JSONSerialization.jsonObject(with: encoded(package(revision: 1))) as? [String: Any])
        futurePackage["schemaVersion"] = 99
        await incoming.receiveContext(try JSONSerialization.data(withJSONObject: futurePackage))
        #expect(incomingModel.connectionState == .cacheIncompatible)
    }

    @Test("An empty phone answer or a send failure retries a bounded number of times, then stops")
    func unusableAnswersRetryWithinBound() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let transport = RecordingTransport()
        let model = WatchAppModel()
        let receiver = WatchSnapshotReceiver(
            model: model, cacheURL: file, transport: transport.value, retryDelays: [.zero, .zero])
        await receiver.start()

        await receiver.requestPairing()
        try #require(transport.sent.count == 1)
        transport.sent[0].reply(Data())          // phone reachable but could not bind a baseline
        await waitUntil { transport.sent.count == 2 }
        transport.sent[1].failed()               // the message itself failed
        await waitUntil { transport.sent.count == 3 }
        transport.sent[2].reply(Data())
        await settle()
        #expect(transport.sent.count == 3)       // two retries allowed, then it waits for a new trigger
        #expect(model.package == nil)

        // A new trigger starts over, and a usable answer ends the retries.
        await receiver.requestPairing()
        try #require(transport.sent.count == 4)
        let hello = try JSONDecoder().decode(WatchPairingHelloV1.self, from: transport.sent[3].data)
        transport.sent[3].reply(pairingReply(package(revision: 1), hello: hello))
        await waitUntil { model.connectionState == .ready }
        await settle()
        #expect(transport.sent.count == 4)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Condition was not met")
    }

    /// Gives any scheduled zero-delay retry the chance to run before asserting none did.
    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
        for _ in 0..<200 { await Task.yield() }
    }

    private func pairingReply(_ value: WatchSnapshotPackageV1, hello: WatchPairingHelloV1) -> Data {
        encoded(WatchPairingReplyV1(
            schemaVersion: 1,
            pairingSession: hello.pairingSession,
            nonce: hello.nonce,
            baseline: .init(
                schemaVersion: 1, pairingSession: hello.pairingSession,
                sourceGeneration: value.sourceGeneration, replacesGeneration: nil),
            packageData: encoded(value)
        ))
    }

    private func encoded<T: Encodable>(_ value: T) -> Data { try! JSONEncoder().encode(value) }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "WatchReceiver-\(UUID().uuidString)/snapshot.json")
    }

    private func package(revision: UInt64) -> WatchSnapshotPackageV1 {
        .init(
            schemaVersion: 1, sourceGeneration: "phone", revision: revision, generatedAtMs: 100, expiresAtMs: 2_000,
            access: .init(schemaVersion: 1, revision: revision, verifiedAtMs: 100, status: .lifetime, validUntilMs: nil),
            content: .init(
                scheduleState: .notConfigured, shift: nil, nextShift: nil,
                presentation: .init(
                    localeIdentifier: "en", timeZoneIdentifier: "UTC", workingLabel: "Working",
                    lunchLabel: "Lunch", restingLabel: "Resting", overtimeLabel: "Overtime",
                    finishedLabel: "Finished"))
        )
    }

    private func v2Package(revision: UInt64) -> WatchSnapshotPackageV1 {
        let presentation = WatchPresentationV1(
            localeIdentifier: "en", timeZoneIdentifier: "UTC", workingLabel: "Working",
            lunchLabel: "Break", restingLabel: "Resting", overtimeLabel: "Overtime",
            finishedLabel: "Finished")
        let schedule = WatchScheduleV2(
            configuration: .init(
                startTime: "09:00", endTime: "17:00", nowMs: 0,
                workdays: [1, 2, 3, 4, 5],
                schedule: .init(
                    mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                    singleWeekendWorkday: nil, rotationAnchorMs: nil,
                    rotationWorkDays: nil, rotationRestDays: nil),
                breakStartTime: nil, breakDurationMinutes: 0, overtimeEndAtMs: nil,
                forcedWorkdayStartMs: nil, timeZoneIdentifier: "UTC"),
            automaticallyRuns: true, isConfigured: true,
            currentShift: nil, currentUntilMs: 0, presentation: presentation)
        return .init(
            schemaVersion: 2, sourceGeneration: "phone", revision: revision,
            generatedAtMs: 100, expiresAtMs: WatchSnapshotContract.maximumJSONTimestamp,
            access: .init(
                schemaVersion: 1, revision: 0, verifiedAtMs: 0,
                status: .free, validUntilMs: nil),
            content: nil, schedule: schedule)
    }
}

@MainActor
private final class RecordingTransport {
    struct Request {
        let data: Data
        let reply: @Sendable (Data) -> Void
        let failed: @Sendable () -> Void
    }

    private let ready: Bool
    private(set) var sent: [Request] = []
    private(set) var reloads = 0

    init(ready: Bool = true) { self.ready = ready }

    var value: WatchSnapshotReceiver.Transport {
        .init(
            isReady: { [ready] in ready },
            sendHello: { [weak self] data, reply, failed in
                self?.sent.append(.init(data: data, reply: reply, failed: failed))
            },
            reloadWidgets: { [weak self] in self?.reloads += 1 }
        )
    }
}
