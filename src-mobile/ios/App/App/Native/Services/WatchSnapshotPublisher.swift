import Foundation
import WatchConnectivity

@MainActor
final class WatchSnapshotPublisher: NSObject {
  typealias Writer = @Sendable (Data, URL) throws -> Void
  typealias ContextSender = ([String: Any]) throws -> Void
  struct Connectivity: Equatable {
    let activated, paired, installed: Bool
    let sourceEpoch: String?
  }
  private struct Evidence: Codable, Equatable {
    let status: String, expiry: Double?, verified: Double?
    init(_ value: PlusWatchEvidence) {
      verified = value.verifiedAt?.timeIntervalSince1970
      switch value.authorization {
      case nil:
        status = "unknown"
        expiry = nil
      case .unauthorized:
        status = "locked"
        expiry = nil
      case .pendingAskToBuy:
        status = "pending"
        expiry = nil
      case .authorized(.lifetime):
        status = "lifetime"
        expiry = nil
      case .authorized(.subscribed(let d)):
        status = "active"
        expiry = d.timeIntervalSince1970
      case .authorized(.inGracePeriod(let d)):
        status = "grace"
        expiry = d.timeIntervalSince1970
      }
    }
  }
  private struct Envelope: Codable {
    var pairing, epoch: String?
    var generation: String
    var revision, accessRevision: UInt64
    var evidence: Evidence?
    var package: WatchSnapshotPackageV1?
    var pending: Bool
    var valid: Bool {
      guard !generation.isEmpty, generation.utf8.count <= 128,
        pairing.map({ !$0.isEmpty && $0.utf8.count <= 128 }) ?? true,
        revision <= WatchSnapshotContract.maximumJSONInteger,
        accessRevision <= WatchSnapshotContract.maximumJSONInteger
      else { return false }
      guard let package else { return revision == 0 && accessRevision == 0 }
      return package.isValid && package.sourceGeneration == generation
        && package.revision == revision && package.access.revision == accessRevision
    }
  }
  private struct Payload {
    let rules: NativeWatchRulesProjection?
    let evidence: PlusWatchEvidence
    let presentation: WatchSnapshotComposer.Presentation
    var schedule: WatchScheduleV2? = nil
  }
  private static let maxBytes = WatchSnapshotContract.maximumEncodedBytes + 16 * 1_024
  /// JSON object key order is otherwise unspecified, so replaying the same
  /// package would send different bytes. The Watch decodes either way; stable
  /// bytes keep a replay a replay.
  private static let wireEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return encoder
  }()
  private let session: WCSession, url: URL, writer: Writer
  private let connectivity: () -> Connectivity, send: ContextSender
  private var state: Envelope
  private var provider: (() async -> Payload?)?
  private var providerRevision: UInt64 = 0
  private var pendingHello: (WatchPairingHelloV1, String, WatchReplyHandler)?

  init(
    session: WCSession = .default, fileURL: URL? = nil, writer: Writer? = nil,
    connectivity: (() -> Connectivity)? = nil, contextSender: ContextSender? = nil
  ) {
    self.session = session
    url = fileURL ?? Self.defaultURL()
    self.writer = writer ?? Self.write
    self.connectivity =
      connectivity ?? {
        // Reading pairing properties before activation completes only logs
        // "WCSession has not been activated"; the answer is "not ready" anyway.
        guard session.activationState == .activated else {
          return .init(activated: false, paired: false, installed: false, sourceEpoch: nil)
        }
        return .init(
          activated: true, paired: session.isPaired, installed: session.isWatchAppInstalled,
          sourceEpoch: session.watchDirectoryURL?.path)
      }
    send = contextSender ?? { try session.updateApplicationContext($0) }
    state = Self.load(fileURL ?? Self.defaultURL()) ?? Self.empty()
    super.init()
  }
  func start() {
    guard WCSession.isSupported() else { return }
    session.delegate = self
    session.activate()
    Task { await reconcileConnectivity() }
  }
  func publish(shifts: ShiftSessionStore) async {
    providerRevision &+= 1
    provider = { [weak shifts] in
      guard let shifts else { return nil }
      do {
        try await shifts.records.flush()
      } catch {
        return nil
      }
      guard !Task.isCancelled else { return nil }
      let text = shifts.text
      let presentation = WatchSnapshotComposer.Presentation(
          localeIdentifier: shifts.preferences.languageCode,
          timeZoneIdentifier: shifts.preferences.recordsTimeZoneIdentifier,
          workingLabel: text.t("widgetWorking"), lunchLabel: text.t(shifts.preferences.isExtendedScheduleEnabled ? "extendedBreak" : "lunchShort"),
          restingLabel: text.t("recordsRestDay"), overtimeLabel: text.t("overtime"),
          finishedLabel: text.t("offWorkToday"))
      return Payload(rules: nil, evidence: .init(authorization: nil, verifiedAt: nil), presentation: presentation,
                     schedule: shifts.session.watchSchedule(presentation: presentation.projection))
    }
    await refresh(forceReplay: false)
  }
  func publish(
    rules: NativeWatchRulesProjection?, evidence: PlusWatchEvidence,
    presentation: WatchSnapshotComposer.Presentation
  ) async {
    providerRevision &+= 1
    provider = { Payload(rules: rules, evidence: evidence, presentation: presentation) }
    await refresh(forceReplay: false)
  }
  func setPayloadProviderForTesting(
    _ value:
      @escaping () async -> (
        NativeWatchRulesProjection?, PlusWatchEvidence, WatchSnapshotComposer.Presentation
      )?
  ) {
    providerRevision &+= 1
    provider = {
      guard let value = await value() else { return nil }
      return Payload(rules: value.0, evidence: value.1, presentation: value.2)
    }
  }
  var currentPackage: WatchSnapshotPackageV1? { state.package }
  func handlePairingHello(_ data: Data) async -> Data? {
    guard data.count <= WatchPairingContract.maximumEncodedBytes,
      let hello = try? JSONDecoder().decode(WatchPairingHelloV1.self, from: data),
      hello.isValid, let payload = await currentPayload()
    else { return nil }
    return reply(hello, payload)
  }
  /// The delegate path: a hello waits in one slot for a payload bound to the
  /// Watch epoch it arrived under. A newer hello or an epoch change answers the
  /// waiting one empty, so the Watch retries instead of trusting a stale baseline.
  func receivePairingHello(_ data: Data, reply: WatchReplyHandler) async {
    guard data.count <= WatchPairingContract.maximumEncodedBytes,
      let hello = try? JSONDecoder().decode(WatchPairingHelloV1.self, from: data), hello.isValid,
      let epoch = helloEpoch()
    else {
      reply(Data())
      return
    }
    pendingHello?.2(Data())
    pendingHello = (hello, epoch, reply)
    await answerPendingHello()
  }
  func reconcileConnectivity() async {
    let link = connectivity()
    guard link.activated, link.paired, link.installed, let epoch = link.sourceEpoch else { return }
    if state.epoch != epoch {
      providerRevision &+= 1
      pendingHello?.2(Data())
      pendingHello = nil
      let next = Self.empty(epoch)
      guard persist(next) else { return }
      state = next
    }
    if provider == nil {
      republishLatestContext()
    } else {
      await refresh(forceReplay: true)
    }
  }
  func republishLatestContext() {
    guard let data = state.package.flatMap({ try? Self.wireEncoder.encode($0) }) else { return }
    if !state.pending {
      var next = state
      next.pending = true
      guard persist(next) else { return }
      state = next
    }
    if sendContext(data) {
      var next = state
      next.pending = false
      if persist(next) { state = next }
    }
  }
  private func refresh(forceReplay: Bool) async {
    guard let payload = await currentPayload() else { return }
    if let waiting = pendingHello {
      pendingHello = nil
      guard waiting.1 == helloEpoch() else {
        waiting.2(Data())
        return
      }
      waiting.2(reply(waiting.0, payload) ?? Data())
    }
    guard state.pairing != nil else { return }
    _ = package(payload, forceReplay: forceReplay)
  }
  private func currentPayload() async -> Payload? {
    guard let provider else { return nil }
    let expectedRevision = providerRevision
    let expectedLink = connectivity()
    let payload = await provider()
    guard expectedRevision == providerRevision,
      expectedLink == connectivity()
    else { return nil }
    return payload
  }
  private func answerPendingHello() async {
    guard let request = pendingHello else { return }
    guard let payload = await currentPayload() else { return }
    guard let current = pendingHello,
      current.0.nonce == request.0.nonce,
      current.1 == request.1,
      current.1 == helloEpoch()
    else { return }
    pendingHello = nil
    current.2(reply(current.0, payload) ?? Data())
  }
  private func package(_ payload: Payload, forceReplay: Bool) -> Data? {
    let evidence = Evidence(payload.evidence)
    let nextAccess: UInt64 = payload.schedule != nil ? 0 : (evidence == state.evidence ? state.accessRevision : state.accessRevision + 1)
    guard state.revision < WatchSnapshotContract.maximumJSONInteger,
      nextAccess <= WatchSnapshotContract.maximumJSONInteger
    else { return nil }
    let now = Date.now
    let verified = payload.evidence.verifiedAt ?? Date(timeIntervalSince1970: 0)
    guard let probe = compose(payload, metadata: .init(
        sourceGeneration: state.generation, revision: state.revision, accessRevision: nextAccess,
        generatedAt: now, accessVerifiedAt: verified)) else { return nil }
    let changed =
      state.package.map { old in
        old.schedule != probe.schedule || old.content != probe.content || old.access != probe.access
          || (old.content != nil && old.expiresAtMs != probe.expiresAtMs)
      } ?? true
    if changed {
      guard let value = compose(payload, metadata: .init(
          sourceGeneration: state.generation, revision: state.revision + 1, accessRevision: nextAccess,
          generatedAt: now, accessVerifiedAt: verified)) else { return nil }
      var next = state
      next.revision += 1
      next.accessRevision = nextAccess
      next.evidence = evidence
      next.package = value
      next.pending = true
      guard persist(next) else { return nil }
      state = next
    } else if forceReplay && !state.pending {
      var next = state
      next.pending = true
      guard persist(next) else { return nil }
      state = next
    }
    guard let data = state.package.flatMap({ try? Self.wireEncoder.encode($0) }) else { return nil }
    if state.pending && sendContext(data) {
      var next = state
      next.pending = false
      if persist(next) { state = next }
    }
    return data
  }
  private func compose(_ payload: Payload, metadata: WatchSnapshotComposer.Metadata) -> WatchSnapshotPackageV1? {
    if let schedule = payload.schedule {
      let value = WatchSnapshotPackageV1(schemaVersion: 2, sourceGeneration: metadata.sourceGeneration,
          revision: metadata.revision, generatedAtMs: Int64(metadata.generatedAt.timeIntervalSince1970 * 1_000),
          expiresAtMs: WatchSnapshotContract.maximumJSONTimestamp,
          access: .init(schemaVersion: 1, revision: 0, verifiedAtMs: 0, status: .free, validUntilMs: nil),
          content: nil, schedule: schedule)
      return value.isValid ? value : nil
    }
    // Decoder/fixture compatibility for V1; production publishes only V2.
    return WatchSnapshotComposer.compose(metadata: metadata, authorization: payload.evidence.authorization,
                                          rules: payload.rules, presentation: payload.presentation)
  }

  private func sendContext(_ data: Data) -> Bool {
    let link = connectivity()
    guard link.activated, link.paired, link.installed, link.sourceEpoch == state.epoch else {
      return false
    }
    do {
      if data.count <= WatchSnapshotContract.maximumContextBytes {
        try send([WatchPairingContract.snapshotContextKey: data])
      } else {
        let revision = String(state.revision)
        if session.outstandingFileTransfers.contains(where: {
          $0.file.metadata?["watchScheduleV2"] as? Bool == true
            && $0.file.metadata?["revision"] as? String == revision
        }) { return true }
        for transfer in session.outstandingFileTransfers
        where transfer.file.metadata?["watchScheduleV2"] as? Bool == true {
          transfer.cancel()
        }
        let directory = url.deletingLastPathComponent().appending(path: "Transfers")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(state.generation)-\(state.revision).json")
        try data.write(to: file, options: .atomic)
        let metadata: [String: Any] = ["watchScheduleV2": true, "revision": revision]
        session.transferFile(file, metadata: metadata)
      }
      return true
    } catch { return false }
  }
  /// The Watch epoch a received hello is answered under. A hello can only come
  /// from an installed, reachable Watch app, yet after launch WatchConnectivity
  /// can keep reporting `isWatchAppInstalled == false` — and so no
  /// `watchDirectoryURL` — for minutes. Rather than leave the Watch without a
  /// baseline, answer under the last epoch this phone recorded; a different
  /// Watch still gets a fresh generation through its own pairing session, and
  /// `reconcileConnectivity` switches epochs once a real directory appears.
  private func helloEpoch() -> String? {
    let link = connectivity()
    guard link.activated else { return nil }
    return link.sourceEpoch ?? state.epoch
  }
  private func reply(_ hello: WatchPairingHelloV1, _ payload: Payload) -> Data? {
    // Receiving the hello already proves pairing and installation; the reply
    // carries the package itself, so it does not wait for the context channel.
    guard let epoch = helloEpoch(), epoch == state.epoch else { return nil }
    if state.pairing != hello.pairingSession {
      var next = Self.empty(state.epoch)
      next.pairing = hello.pairingSession
      guard persist(next) else { return nil }
      state = next
    }
    guard let bytes = package(payload, forceReplay: true), let value = state.package else {
      return nil
    }
    let baseline = WatchSourceBaselineV1(
      schemaVersion: 1, pairingSession: hello.pairingSession,
      sourceGeneration: value.sourceGeneration,
      replacesGeneration: hello.acceptedGeneration == value.sourceGeneration
        ? nil : hello.acceptedGeneration)
    return try? JSONEncoder().encode(
      WatchPairingReplyV1(
        schemaVersion: 1, pairingSession: hello.pairingSession,
        nonce: hello.nonce, baseline: baseline,
        packageData: bytes.count <= WatchSnapshotContract.maximumContextBytes ? bytes : Data(),
        deferredRevision: bytes.count > WatchSnapshotContract.maximumContextBytes ? value.revision : nil))
  }
  private func persist(_ value: Envelope) -> Bool {
    guard value.valid, let data = try? JSONEncoder().encode(value), data.count <= Self.maxBytes
    else { return false }
    do {
      try writer(data, url)
      return true
    } catch { return false }
  }
  private static func empty(_ epoch: String? = nil) -> Envelope {
    .init(
      pairing: nil, epoch: epoch, generation: UUID().uuidString, revision: 0, accessRevision: 0,
      evidence: nil, package: nil, pending: false)
  }
  private static func defaultURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(
      path: "WatchPublisher/state.json")
  }
  private static func load(_ url: URL) -> Envelope? {
    guard let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
      rv.isRegularFile == true,
      let size = rv.fileSize, size <= maxBytes, let data = try? Data(contentsOf: url),
      data.count <= maxBytes,
      let value = try? JSONDecoder().decode(Envelope.self, from: data), value.valid
    else { return nil }
    return value
  }
  private nonisolated static func write(_ data: Data, _ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var directory = url.deletingLastPathComponent()
    var rv = URLResourceValues()
    rv.isExcludedFromBackup = true
    try directory.setResourceValues(rv)
    try data.write(to: url, options: .atomic)
  }
}

extension WatchSnapshotPublisher: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: (any Error)?
  ) { Task { @MainActor [weak self] in await self?.reconcileConnectivity() } }
  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
  nonisolated func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
    Task { @MainActor [weak self] in await self?.reconcileConnectivity() }
  }
  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor [weak self] in await self?.reconcileConnectivity() }
  }
  nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
    Task { @MainActor [weak self] in await self?.reconcileConnectivity() }
  }
  nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
    guard fileTransfer.file.metadata?["watchScheduleV2"] as? Bool == true else { return }
    let file = fileTransfer.file.fileURL
    let revision = (fileTransfer.file.metadata?["revision"] as? String).flatMap(UInt64.init)
    let failed = error != nil
    Task { @MainActor [weak self] in
      try? FileManager.default.removeItem(at: file)
      guard let self, failed, revision == state.revision,
            !state.pending else { return }
      var next = state
      next.pending = true
      if persist(next) { state = next }
    }
  }
  nonisolated func session(
    _ session: WCSession, didReceiveMessageData data: Data,
    replyHandler: @escaping (Data) -> Void
  ) {
    let reply = WatchReplyHandler(replyHandler)
    Task { @MainActor [weak self] in
      guard let self else {
        reply(Data())
        return
      }
      await self.receivePairingHello(data, reply: reply)
    }
  }
}

/// WatchConnectivity hands the delegate an unannotated Objective-C reply block
/// on its own queue and requires it to be answered at most once; the system
/// accepts that answer from any thread. The block is only ever read inside the
/// lock, which also clears it, so a superseded, reset and late answer cannot
/// all reach the same Watch request.
nonisolated final class WatchReplyHandler: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: ((Data) -> Void)?

  init(_ handler: @escaping (Data) -> Void) { self.handler = handler }

  func callAsFunction(_ data: Data) {
    let pending = lock.withLock {
      defer { handler = nil }
      return handler
    }
    pending?(data)
  }
}
