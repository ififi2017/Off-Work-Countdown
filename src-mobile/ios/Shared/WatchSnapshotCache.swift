import Foundation

nonisolated enum WatchSnapshotCacheReceiveResult: Equatable, Sendable {
    case accepted
    case duplicate
    case rejected(WatchSnapshotOrderDecision)
    case persistenceFailed
    case pairingResetRequired
}

nonisolated enum WatchSnapshotCacheLoadState: Equatable, Sendable {
    case empty
    case ready
    case corrupt
    case incompatible
}

private nonisolated struct WatchSnapshotCacheEnvelope: Codable, Sendable {
    let pairingSession: String
    let package: WatchSnapshotPackageV1?
    let order: WatchSnapshotOrderState
    var pendingBaseline: WatchSourceBaselineV1? = nil
    var pendingRevision: UInt64? = nil

    var isValid: Bool {
        guard !pairingSession.isEmpty
            && pairingSession.utf8.count <= WatchSnapshotContract.maximumIdentifierBytes
            && order.isValid else { return false }
        if let baseline = pendingBaseline {
            guard baseline.schemaVersion == WatchSnapshotContract.schemaVersion,
                  baseline.pairingSession == pairingSession,
                  !baseline.sourceGeneration.isEmpty,
                  baseline.sourceGeneration.utf8.count <= WatchSnapshotContract.maximumIdentifierBytes,
                  baseline.replacesGeneration.map({
                      !$0.isEmpty && $0.utf8.count <= WatchSnapshotContract.maximumIdentifierBytes
                  }) ?? true,
                  pendingRevision.map({ $0 <= WatchSnapshotContract.maximumJSONInteger }) == true
            else { return false }
        } else if pendingRevision != nil {
            return false
        }
        guard let package else {
            return order == WatchSnapshotOrderState()
        }
        return package.isValid
            && order.currentGeneration == package.sourceGeneration
            && order.revision == package.revision
            && order.acceptedAccess == package.access
    }
}

actor WatchSnapshotCache {
    typealias Writer = @Sendable (Data, URL) throws -> Void

    private static let maximumCacheBytes = WatchSnapshotContract.maximumEncodedBytes + 16 * 1_024
    static let appGroupIdentifier = "group.com.rainif.offworkcountdown.macappstore.watch"

    nonisolated static func appGroupFileURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appending(path: "WatchSnapshot/snapshot.json")
    }

    private let fileURL: URL
    private let writer: Writer
    private var pairingSession: String
    private var package: WatchSnapshotPackageV1?
    private var order: WatchSnapshotOrderState
    private var pendingBaseline: WatchSourceBaselineV1?
    private var pendingRevision: UInt64?
    private var pendingPairingHello: WatchPairingHelloV1?
    private var currentLoadState: WatchSnapshotCacheLoadState

    private init(fileURL: URL, writer: Writer? = nil, pairingSession: String,
                 loadState: WatchSnapshotCacheLoadState) {
        self.fileURL = fileURL
        self.writer = writer ?? { data, destination in
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
        }
        self.pairingSession = pairingSession
        currentLoadState = loadState
        package = nil
        order = WatchSnapshotOrderState()
        pendingPairingHello = nil
    }

    nonisolated static func open(
        fileURL: URL,
        writer: Writer? = nil,
        newPairingSession: String? = nil
    ) async -> WatchSnapshotCache {
        let loaded = Self.loadEnvelope(from: fileURL)
        let envelope = loaded.envelope
        let session = envelope?.pairingSession ?? newPairingSession ?? UUID().uuidString
        let cache = WatchSnapshotCache(fileURL: fileURL, writer: writer, pairingSession: session,
                                       loadState: loaded.state)
        await cache.restore(envelope)
        return cache
    }

    private func restore(_ envelope: WatchSnapshotCacheEnvelope?) {
        if let envelope {
            package = envelope.package
            order = envelope.order
            pendingBaseline = envelope.pendingBaseline
            pendingRevision = envelope.pendingRevision
        } else {
            package = nil
            order = WatchSnapshotOrderState()
        }
    }

    func currentPackage() -> WatchSnapshotPackageV1? { package }
    func loadState() -> WatchSnapshotCacheLoadState { currentLoadState }

    func makePairingHello(nonce: String? = nil) -> WatchPairingHelloV1 {
        let nextNonce = nonce ?? UUID().uuidString
        precondition(!nextNonce.isEmpty && nextNonce.utf8.count <= WatchSnapshotContract.maximumIdentifierBytes)
        let hello = WatchPairingHelloV1(
            schemaVersion: WatchPairingContract.schemaVersion,
            pairingSession: pairingSession,
            nonce: nextNonce,
            acceptedGeneration: order.currentGeneration
        )
        pendingPairingHello = hello
        return hello
    }

    func cancelPairing() {
        pendingPairingHello = nil
    }

    func receiveApplicationContext(_ data: Data) -> WatchSnapshotCacheReceiveResult {
        receivePackage(data, trustedBaseline: nil)
    }

    func receivePairingReply(_ data: Data) -> WatchSnapshotCacheReceiveResult {
        guard let reply = WatchPairingWireDecoder.decodeReply(data),
              let hello = pendingPairingHello,
              reply.pairingSession == hello.pairingSession,
              reply.nonce == hello.nonce,
              baselineMatchesChallenge(reply.baseline, hello: hello) else {
            return .rejected(.rejectBaseline)
        }
        if let deferredRevision = reply.deferredRevision, reply.packageData.isEmpty {
            if reply.baseline.sourceGeneration == order.currentGeneration,
               let acceptedRevision = order.revision {
                if deferredRevision == acceptedRevision {
                    pendingPairingHello = nil
                    return .duplicate
                }
                guard deferredRevision > acceptedRevision else {
                    return .rejected(.rejectStaleRevision)
                }
            }
            let envelope = WatchSnapshotCacheEnvelope(pairingSession: pairingSession, package: package,
                                                       order: order, pendingBaseline: reply.baseline,
                                                       pendingRevision: deferredRevision)
            guard envelope.isValid, let encoded = try? JSONEncoder().encode(envelope) else {
                return .rejected(.rejectBaseline)
            }
            do { try writer(encoded, fileURL) } catch { return .persistenceFailed }
            pendingBaseline = reply.baseline
            pendingRevision = deferredRevision
            pendingPairingHello = nil
            return .accepted
        }
        let result = receivePackage(reply.packageData, trustedBaseline: reply.baseline)
        if result == .accepted || result == .duplicate {
            pendingPairingHello = nil
        }
        return result
    }

    private func baselineMatchesChallenge(
        _ baseline: WatchSourceBaselineV1,
        hello: WatchPairingHelloV1
    ) -> Bool {
        if baseline.sourceGeneration == hello.acceptedGeneration {
            guard let replaced = baseline.replacesGeneration else { return true }
            return order.retiredGenerations.contains(replaced)
        }
        return baseline.replacesGeneration == hello.acceptedGeneration
    }

    private func receivePackage(
        _ data: Data,
        trustedBaseline: WatchSourceBaselineV1?
    ) -> WatchSnapshotCacheReceiveResult {
        let candidate: WatchSnapshotPackageV1
        do {
            candidate = try WatchSnapshotDecoderV1.decode(data)
        } catch let error as WatchSnapshotDecodeError {
            if package == nil {
                currentLoadState = error == .unsupportedSchema ? .incompatible : .corrupt
            }
            return .rejected(.rejectInvalidPackage)
        } catch {
            if package == nil { currentLoadState = .corrupt }
            return .rejected(.rejectInvalidPackage)
        }

        if let package, candidate.sourceGeneration == package.sourceGeneration,
           candidate.schemaVersion < package.schemaVersion {
            return .rejected(.rejectInvalidPackage)
        }
        if trustedBaseline == nil, let pendingRevision, candidate.revision != pendingRevision {
            return .rejected(candidate.revision < pendingRevision ? .rejectStaleRevision : .rejectBaseline)
        }

        let evaluation = WatchSnapshotOrderEvaluator.evaluate(
            candidate,
            baseline: trustedBaseline ?? pendingBaseline,
            pairingSession: pairingSession,
            state: order
        )
        switch evaluation.decision {
        case .duplicate:
            return .duplicate
        case .accept:
            guard let proposedOrder = evaluation.proposedState else {
                return .rejected(.rejectInvalidState)
            }
            let envelope = WatchSnapshotCacheEnvelope(
                pairingSession: pairingSession,
                package: candidate,
                order: proposedOrder
            )
            guard envelope.isValid,
                  let encoded = try? JSONEncoder().encode(envelope),
                  encoded.count <= Self.maximumCacheBytes else {
                return .rejected(.rejectInvalidPackage)
            }
            do {
                try writer(encoded, fileURL)
            } catch {
                return .persistenceFailed
            }
            package = candidate
            order = proposedOrder
            currentLoadState = .ready
            pendingBaseline = nil
            pendingRevision = nil
            return .accepted
        case .rejectInvalidState where trustedBaseline != nil
            && order.retiredGenerations.count == WatchSnapshotContract.maximumRetiredGenerations:
            return resetPairingAfterRetirementLimit()
        default:
            return .rejected(evaluation.decision)
        }
    }

    private func resetPairingAfterRetirementLimit() -> WatchSnapshotCacheReceiveResult {
        let replacementSession = UUID().uuidString
        let emptyOrder = WatchSnapshotOrderState()
        let envelope = WatchSnapshotCacheEnvelope(
            pairingSession: replacementSession,
            package: nil,
            order: emptyOrder
        )
        guard let encoded = try? JSONEncoder().encode(envelope),
              encoded.count <= Self.maximumCacheBytes else {
            return .rejected(.rejectInvalidState)
        }
        do {
            try writer(encoded, fileURL)
        } catch {
            return .persistenceFailed
        }
        package = nil
        order = emptyOrder
        pendingBaseline = nil
        pendingRevision = nil
        pendingPairingHello = nil
        pairingSession = replacementSession
        return .pairingResetRequired
    }

    private nonisolated static func loadEnvelope(
        from fileURL: URL
    ) -> (envelope: WatchSnapshotCacheEnvelope?, state: WatchSnapshotCacheLoadState) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return (nil, .empty) }
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= maximumCacheBytes,
              let data = try? Data(contentsOf: fileURL), data.count <= maximumCacheBytes else {
            return (nil, .corrupt)
        }
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let package = object["package"] as? [String: Any],
           let schema = package["schemaVersion"] as? Int,
           ![1, 2, 3, 4].contains(schema) {
            return (nil, .incompatible)
        }
        guard let envelope = try? JSONDecoder().decode(WatchSnapshotCacheEnvelope.self, from: data),
              envelope.isValid else { return (nil, .corrupt) }
        return (envelope, .ready)
    }
}
