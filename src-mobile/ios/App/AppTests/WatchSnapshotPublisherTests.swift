import Foundation
import Testing
import WatchConnectivity

@testable import App

@MainActor
@Suite("Watch snapshot publisher")
struct WatchSnapshotPublisherTests {
  @Test("Persists before context, restores latest context, and pairs with replacement baseline")
  func persistenceAndPairing() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var contexts: [Data] = []
    let publisher = WatchSnapshotPublisher(
      fileURL: file, connectivity: connected,
      contextSender: {
        contexts.append(try #require($0["watchSnapshotV1"] as? Data))
      })
    await publisher.reconcileConnectivity()
    await publisher.publish(
      rules: rules(), evidence: evidence(.authorized(.lifetime)), presentation: presentation())
    #expect(contexts.isEmpty)

    let hello = WatchPairingHelloV1(
      schemaVersion: 1, pairingSession: "watch-a", nonce: "n1", acceptedGeneration: "old-phone")
    let replyData = try #require(await publisher.handlePairingHello(try JSONEncoder().encode(hello)))
    let reply = try #require(WatchPairingWireDecoder.decodeReply(replyData))
    #expect(reply.baseline.replacesGeneration == "old-phone")
    #expect(contexts.count == 1)
    #expect(try Data(contentsOf: file).isEmpty == false)

    var restoredContexts: [Data] = []
    let restored = WatchSnapshotPublisher(
      fileURL: file, connectivity: connected,
      contextSender: {
        restoredContexts.append(try #require($0["watchSnapshotV1"] as? Data))
      })
    await restored.reconcileConnectivity()
    #expect(restoredContexts == contexts)
  }

  @Test("Failed state save sends nothing and the same evidence retries")
  func persistenceRetry() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let writer = FailingWriter(failures: [2])
    var contexts = 0
    let publisher = WatchSnapshotPublisher(
      fileURL: file, writer: writer.write, connectivity: connected,
      contextSender: { _ in contexts += 1 })
    await publisher.reconcileConnectivity()
    await publisher.publish(
      rules: rules(), evidence: evidence(.unauthorized), presentation: presentation())
    let hello = WatchPairingHelloV1(
      schemaVersion: 1, pairingSession: "watch-a", nonce: "n", acceptedGeneration: nil)
    #expect(await publisher.handlePairingHello(try JSONEncoder().encode(hello)) == nil)
    #expect(contexts == 0)
    #expect(await publisher.handlePairingHello(try JSONEncoder().encode(hello)) != nil)
    #expect(contexts == 1)
  }

  @Test("Entitlement-only change advances access and package revisions")
  func entitlementUpdate() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let publisher = WatchSnapshotPublisher(
      fileURL: file, connectivity: connected, contextSender: { _ in })
    await publisher.reconcileConnectivity()
    let hello = WatchPairingHelloV1(
      schemaVersion: 1, pairingSession: "watch-a", nonce: "n", acceptedGeneration: nil)
    await publisher.publish(
      rules: rules(), evidence: evidence(.authorized(.lifetime)), presentation: presentation())
    _ = await publisher.handlePairingHello(try JSONEncoder().encode(hello))
    let first = try #require(publisher.currentPackage)
    await publisher.publish(
      rules: rules(), evidence: evidence(.unauthorized, verifiedAt: 200),
      presentation: presentation())
    let second = try #require(publisher.currentPackage)
    #expect(second.revision > first.revision)
    #expect(second.access.revision > first.access.revision)
    #expect(second.access.status == .locked)
  }

  @Test("Failed context delivery remains pending and identical input retries")
  func contextRetry() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var attempts = 0
    let projection = rules()
    let publisher = WatchSnapshotPublisher(
      fileURL: file, connectivity: connected,
      contextSender: { _ in
        attempts += 1
        if attempts == 1 { throw CocoaError(.fileWriteUnknown) }
      })
    await publisher.reconcileConnectivity()
    await publisher.publish(
      rules: projection, evidence: evidence(.authorized(.lifetime)), presentation: presentation())
    let hello = WatchPairingHelloV1(
      schemaVersion: 1, pairingSession: "watch-a", nonce: "n", acceptedGeneration: nil)
    _ = await publisher.handlePairingHello(try JSONEncoder().encode(hello))
    let revision = publisher.currentPackage?.revision
    #expect(attempts == 1)
    await publisher.publish(
      rules: projection, evidence: evidence(.authorized(.lifetime)), presentation: presentation())
    #expect(attempts == 2)
    #expect(publisher.currentPackage?.revision == revision)
  }

  @Test("Identical ordinary publications perform no writes or sends")
  func identicalPublicationNoOp() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let writer = FailingWriter(failures: [])
    var sends = 0
    let publisher = WatchSnapshotPublisher(
      fileURL: file, writer: writer.write, connectivity: connected,
      contextSender: { _ in sends += 1 })
    await publisher.reconcileConnectivity()
    let projection = rules()
    let access = evidence(.authorized(.lifetime))
    await publisher.publish(rules: projection, evidence: access, presentation: presentation())
    let hello = WatchPairingHelloV1(
      schemaVersion: 1, pairingSession: "watch-a", nonce: "n", acceptedGeneration: nil)
    _ = await publisher.handlePairingHello(try JSONEncoder().encode(hello))
    let writes = writer.callCount
    let sent = sends

    for _ in 0..<5 {
      await publisher.publish(rules: projection, evidence: access, presentation: presentation())
    }
    #expect(writer.callCount == writes)
    #expect(sends == sent)

    await publisher.reconcileConnectivity()
    #expect(sends == sent + 1)
  }

  @Test("Connectivity gate and selected Watch epoch prevent stale delivery")
  func connectivityEpoch() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var link = WatchSnapshotPublisher.Connectivity(
      activated: false, paired: true, installed: true, sourceEpoch: "watch-a")
    var contexts = 0
    let publisher = WatchSnapshotPublisher(
      fileURL: file, connectivity: { link }, contextSender: { _ in contexts += 1 })
    await publisher.publish(
      rules: rules(), evidence: evidence(.authorized(.lifetime)), presentation: presentation())
    let firstHello = WatchPairingHelloV1(
      schemaVersion: 1, pairingSession: "pair-a", nonce: "a", acceptedGeneration: nil)
    #expect(await publisher.handlePairingHello(try JSONEncoder().encode(firstHello)) == nil)
    #expect(contexts == 0)

    link = .init(activated: true, paired: true, installed: true, sourceEpoch: "watch-a")
    await publisher.reconcileConnectivity()
    let firstReply = try #require(
      await publisher.handlePairingHello(try JSONEncoder().encode(firstHello)))
    let firstGeneration = try #require(WatchPairingWireDecoder.decodeReply(firstReply)).baseline
      .sourceGeneration
    link = .init(activated: true, paired: true, installed: true, sourceEpoch: "watch-b")
    await publisher.reconcileConnectivity()
    #expect(publisher.currentPackage == nil)
    let secondHello = WatchPairingHelloV1(
      schemaVersion: 1, pairingSession: "pair-b", nonce: "b", acceptedGeneration: firstGeneration)
    let secondReply = try #require(
      await publisher.handlePairingHello(try JSONEncoder().encode(secondHello)))
    let decoded = try #require(WatchPairingWireDecoder.decodeReply(secondReply))
    #expect(decoded.baseline.sourceGeneration != firstGeneration)
    #expect(decoded.baseline.replacesGeneration == firstGeneration)
  }

  @Test("A provider completion from the previous Watch epoch is discarded")
  func staleProviderCompletion() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var link = WatchSnapshotPublisher.Connectivity(
      activated: true, paired: true, installed: true, sourceEpoch: "watch-a")
    let gate = WatchPublisherGate()
    let publisher = WatchSnapshotPublisher(
      fileURL: file, connectivity: { link }, contextSender: { _ in })
    await publisher.reconcileConnectivity()
    let projection = rules()
    let access = evidence(.authorized(.lifetime))
    let labels = presentation()
    publisher.setPayloadProviderForTesting {
      await gate.wait()
      return (projection, access, labels)
    }
    let hello = WatchPairingHelloV1(
      schemaVersion: 1, pairingSession: "pair-a", nonce: "n", acceptedGeneration: nil)
    let helloBytes = try JSONEncoder().encode(hello)
    let task = Task { await publisher.handlePairingHello(helloBytes) }
    await gate.waitUntilStarted()
    link = .init(activated: true, paired: true, installed: true, sourceEpoch: "watch-b")
    await gate.release()
    #expect(await task.value == nil)
    #expect(publisher.currentPackage == nil)
  }

  @Test("Delegate hello waits for a payload, supersedes once, and resets on a new Watch")
  func delegateHelloLifecycle() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var link = WatchSnapshotPublisher.Connectivity(
      activated: true, paired: true, installed: true, sourceEpoch: "watch-a")
    var contexts = 0
    let publisher = WatchSnapshotPublisher(
      fileURL: file, connectivity: { link }, contextSender: { _ in contexts += 1 })
    await publisher.reconcileConnectivity()

    // Cold launch: nothing has been published yet, so the request waits.
    let first = ReplyRecorder()
    await publisher.receivePairingHello(try helloData("n1"), reply: first.handler())
    #expect(first.replies.isEmpty)

    let second = ReplyRecorder()
    await publisher.receivePairingHello(try helloData("n2"), reply: second.handler())
    #expect(first.replies == [Data()])
    #expect(second.replies.isEmpty)

    await publisher.publish(
      rules: rules(), evidence: evidence(.authorized(.lifetime)), presentation: presentation())
    #expect(second.replies.count == 1)
    let answerData = try #require(second.replies.first)
    let answer = try #require(WatchPairingWireDecoder.decodeReply(answerData))
    #expect(answer.nonce == "n2")
    #expect(first.replies.count == 1)
    #expect(contexts == 1)

    let malformed = ReplyRecorder()
    await publisher.receivePairingHello(Data("{}".utf8), reply: malformed.handler())
    #expect(malformed.replies == [Data()])

    // A request parked under one Watch must not be answered with the next one's baseline.
    publisher.setPayloadProviderForTesting { nil }
    let parked = ReplyRecorder()
    await publisher.receivePairingHello(try helloData("n3"), reply: parked.handler())
    #expect(parked.replies.isEmpty)
    link = .init(activated: true, paired: true, installed: true, sourceEpoch: "watch-b")
    await publisher.reconcileConnectivity()
    #expect(parked.replies == [Data()])
    #expect(publisher.currentPackage == nil)
    #expect(contexts == 1)
  }

  @Test("The WatchConnectivity delegate entry answers through the system reply block")
  func delegateCallbackAnswersHello() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let publisher = WatchSnapshotPublisher(
      fileURL: file, connectivity: connected, contextSender: { _ in })
    await publisher.reconcileConnectivity()
    await publisher.publish(
      rules: rules(), evidence: evidence(.authorized(.lifetime)), presentation: presentation())
    let hello = try helloData("delegate")

    // The production nonisolated method, not the MainActor helper it forwards to.
    let answer: Data = await withCheckedContinuation { continuation in
      publisher.session(WCSession.default, didReceiveMessageData: hello) {
        continuation.resume(returning: $0)
      }
    }
    #expect(try #require(WatchPairingWireDecoder.decodeReply(answer)).nonce == "delegate")

    let rejected: Data = await withCheckedContinuation { continuation in
      publisher.session(WCSession.default, didReceiveMessageData: Data("{}".utf8)) {
        continuation.resume(returning: $0)
      }
    }
    #expect(rejected.isEmpty)
  }

  @Test("A hello is answered under the last Watch epoch while WatchConnectivity still reports no install")
  func helloWhileInstallStateLags() async throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var link = WatchSnapshotPublisher.Connectivity(
      activated: true, paired: true, installed: true, sourceEpoch: "watch-a")
    var contexts = 0
    let publisher = WatchSnapshotPublisher(
      fileURL: file, connectivity: { link }, contextSender: { _ in contexts += 1 })
    await publisher.reconcileConnectivity()
    await publisher.publish(
      rules: rules(), evidence: evidence(.authorized(.lifetime)), presentation: presentation())

    // Relaunched phone: activated, but the session has not caught up on the Watch app yet.
    link = .init(activated: true, paired: true, installed: false, sourceEpoch: nil)
    let answer = try #require(await publisher.handlePairingHello(try helloData("lagging")))
    let decoded = try #require(WatchPairingWireDecoder.decodeReply(answer))
    #expect(decoded.nonce == "lagging")
    #expect(decoded.packageData.isEmpty == false)
    #expect(contexts == 0)

    // Once the session reports the same Watch, the pending context goes out.
    link = .init(activated: true, paired: true, installed: true, sourceEpoch: "watch-a")
    await publisher.reconcileConnectivity()
    #expect(contexts == 1)

    // A phone that has never recorded a Watch epoch cannot bind a baseline.
    let freshFile = temporaryFile()
    defer { try? FileManager.default.removeItem(at: freshFile.deletingLastPathComponent()) }
    let fresh = WatchSnapshotPublisher(
      fileURL: freshFile,
      connectivity: { .init(activated: true, paired: true, installed: false, sourceEpoch: nil) },
      contextSender: { _ in })
    await fresh.publish(
      rules: rules(), evidence: evidence(.authorized(.lifetime)), presentation: presentation())
    #expect(await fresh.handlePairingHello(try helloData("unbound")) == nil)
  }

  @Test("A Watch reply block is consumed at most once under concurrent callers")
  func replyHandlerConsumedOnce() async {
    let recorder = ReplyRecorder()
    let reply = recorder.handler()
    await withTaskGroup(of: Void.self) { group in
      for index in 0..<32 {
        group.addTask { reply(Data([UInt8(index)])) }
      }
    }
    #expect(recorder.replies.count == 1)
  }

  @Test("Production publishes free V2 without Plus, excludes salary, and commits foreground schedule changes")
  func productionInputPrivacyAndDeduplication() async throws {
    let suite = "WatchPublisherProduction.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "ios.native.onboardingComplete")
    defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
    let runtime = AppRuntime(defaults: defaults, records: .inMemory())
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let writer = FailingWriter(failures: [])
    var contexts: [Data] = []
    let publisher = WatchSnapshotPublisher(
      fileURL: file, writer: writer.write, connectivity: connected,
      contextSender: { contexts.append(try #require($0[WatchPairingContract.snapshotContextKey] as? Data)) })
    await publisher.reconcileConnectivity()
    let direct = runtime.session.watchSchedule(presentation: presentation().projection)
    #expect(direct.isValid)
    #expect(direct.currentShift == nil || direct.resumeAtMs != nil)
    runtime.preferences.onboardingComplete = false
    #expect(runtime.session.watchSchedule(presentation: presentation().projection).isValid)
    runtime.preferences.onboardingComplete = true
    #expect(runtime.preferences.applyPreferences { $0.scheduleMode = .off }.synchronousResult)
    #expect(runtime.session.watchSchedule(presentation: presentation().projection).isValid)
    #expect(runtime.preferences.applyPreferences { $0.scheduleMode = .classic }.synchronousResult)
    await publisher.publish(shifts: runtime.shifts)
    let hello = WatchPairingHelloV1(
      schemaVersion: 1, pairingSession: "watch-a", nonce: "n", acceptedGeneration: nil)
    _ = await publisher.handlePairingHello(try JSONEncoder().encode(hello))
    let initial = try #require(publisher.currentPackage)
    #expect(runtime.plus.isAuthorized == false)
    #expect(initial.schemaVersion == 2)
    #expect(initial.access.status == .free)
    #expect(initial.content == nil)
    #expect(initial.schedule != nil)
    #expect(contexts.count == 1)
    let writes = writer.callCount
    let sends = contexts.count

    let applied = runtime.preferences.applyPreferences {
      $0.salaryEnabled = true
      $0.salaryAmount = "SALARY-SENTINEL-918273"
      $0.theme = .dark
    }.synchronousResult
    #expect(applied)
    await publisher.publish(shifts: runtime.shifts)

    #expect(writer.callCount == writes)
    #expect(contexts.count == sends)
    let raw = contexts.map { String(decoding: $0, as: UTF8.self) }.joined()
    #expect(!raw.contains("SALARY-SENTINEL-918273"))
    #expect(!raw.localizedCaseInsensitiveContains("salary"))

    let changed = runtime.preferences.applyPreferences { $0.endMinutes = 18 * 60 }.synchronousResult
    #expect(changed)
    await publisher.publish(shifts: runtime.shifts)
    let committed = try #require(publisher.currentPackage)
    #expect(committed.revision == initial.revision + 1)
    #expect(committed.schedule?.configuration.endTime == "18:00")
    #expect(contexts.count == sends + 1)
  }

  private func evidence(_ authorization: PlusAuthorization, verifiedAt: TimeInterval = 100)
    -> PlusWatchEvidence
  {
    .init(authorization: authorization, verifiedAt: Date(timeIntervalSince1970: verifiedAt))
  }

  private func rules() -> NativeWatchRulesProjection {
    .init(
      scheduleState: "scheduled", shift: nil, nextShift: nil,
      contentExpiresAtMs: Date.now.timeIntervalSince1970 * 1_000 + 86_400_000)
  }

  private func presentation() -> WatchSnapshotComposer.Presentation {
    .init(
      localeIdentifier: "en", timeZoneIdentifier: "UTC", workingLabel: "Working",
      lunchLabel: "Lunch", restingLabel: "Rest", overtimeLabel: "Overtime",
      finishedLabel: "Finished")
  }

  private func helloData(_ nonce: String) throws -> Data {
    try JSONEncoder().encode(
      WatchPairingHelloV1(
        schemaVersion: 1, pairingSession: "watch-a", nonce: nonce, acceptedGeneration: nil))
  }

  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "WatchPublisher-\(UUID())/state.json")
  }

  private var connected: () -> WatchSnapshotPublisher.Connectivity {
    { .init(activated: true, paired: true, installed: true, sourceEpoch: "watch-directory-a") }
  }
}

private actor WatchPublisherGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var started = false
  func wait() async {
    started = true
    await withCheckedContinuation { continuation = $0 }
  }
  func waitUntilStarted() async {
    while !started { await Task.yield() }
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private final class ReplyRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Data] = []
  var replies: [Data] { lock.withLock { values } }
  func handler() -> WatchReplyHandler {
    WatchReplyHandler { [self] data in lock.withLock { values.append(data) } }
  }
}

private final class FailingWriter: @unchecked Sendable {
  private let lock = NSLock()
  private var call = 0
  private let failures: Set<Int>
  init(failures: Set<Int>) { self.failures = failures }
  var callCount: Int { lock.withLock { call } }
  func write(_ data: Data, _ url: URL) throws {
    let fails = lock.withLock {
      call += 1
      return failures.contains(call)
    }
    if fails { throw CocoaError(.fileWriteUnknown) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }
}
