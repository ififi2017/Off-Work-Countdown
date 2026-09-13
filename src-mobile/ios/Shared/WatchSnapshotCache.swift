import Foundation

nonisolated enum WatchSnapshotCacheReceiveResult: Equatable, Sendable {
    case accepted
    case duplicate
    case rejected(WatchSnapshotOrderDecision)
    case persistenceFailed
    case pairingResetRequired
}

private nonisolated struct WatchSnapshotCacheEnvelope: Codable, Sendable {
    let pairingSession: String
    let package: WatchSnapshotPackageV1?
    let order: WatchSnapshotOrderState

    var isValid: Bool {
        guard !pairingSession.isEmpty
            && pairingSession.utf8.count <= WatchSnapshotContract.maximumIdentifierBytes
            && order.isValid else { return false }
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
    private var pendingPairingHello: WatchPairingHelloV1?

    private init(fileURL: URL, writer: Writer? = nil, pairingSession: String) {
        self.fileURL = fileURL
        self.writer = writer ?? { data, destination in
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
        }
        self.pairingSession = pairingSession
        package = nil
        order = WatchSnapshotOrderState()
        pendingPairingHello = nil
    }

    nonisolated static func open(
        fileURL: URL,
        writer: Writer? = nil,
        newPairingSession: String? = nil
    ) async -> WatchSnapshotCache {
        let envelope = Self.loadEnvelope(from: fileURL)
        let session = envelope?.pairingSession ?? newPairingSession ?? UUID().uuidString
        let cache = WatchSnapshotCache(fileURL: fileURL, writer: writer, pairingSession: session)
        await cache.restore(envelope)
        return cache
    }

    private func restore(_ envelope: WatchSnapshotCacheEnvelope?) {
        if let envelope {
            package = envelope.package
            order = envelope.order
        } else {
            package = nil
            order = WatchSnapshotOrderState()
        }
    }

    func currentPackage() -> WatchSnapshotPackageV1? { package }

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
        } catch {
            return .rejected(.rejectInvalidPackage)
        }

        let evaluation = WatchSnapshotOrderEvaluator.evaluate(
            candidate,
            baseline: trustedBaseline,
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
        pendingPairingHello = nil
        pairingSession = replacementSession
        return .pairingResetRequired
    }

    private nonisolated static func loadEnvelope(from fileURL: URL) -> WatchSnapshotCacheEnvelope? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= maximumCacheBytes,
              let data = try? Data(contentsOf: fileURL),
              data.count <= maximumCacheBytes,
              let envelope = try? JSONDecoder().decode(WatchSnapshotCacheEnvelope.self, from: data),
              envelope.isValid else { return nil }
        return envelope
    }
}
