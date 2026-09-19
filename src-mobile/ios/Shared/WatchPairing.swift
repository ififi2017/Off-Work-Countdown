import Foundation

nonisolated enum WatchPairingContract {
    static let schemaVersion = 1
    static let maximumEncodedBytes = 96 * 1_024
    static let snapshotContextKey = "watchSnapshotV1"
}

nonisolated struct WatchPairingHelloV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let pairingSession: String
    let nonce: String
    let acceptedGeneration: String?

    var isValid: Bool {
        schemaVersion == WatchPairingContract.schemaVersion
            && pairingSession.isValidWatchPairingIdentifier
            && nonce.isValidWatchPairingIdentifier
            && (acceptedGeneration?.isValidWatchPairingIdentifier ?? true)
    }
}

nonisolated struct WatchPairingReplyV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let pairingSession: String
    let nonce: String
    let baseline: WatchSourceBaselineV1
    let packageData: Data
    var deferredRevision: UInt64? = nil

    var isValid: Bool {
        schemaVersion == WatchPairingContract.schemaVersion
            && pairingSession.isValidWatchPairingIdentifier
            && nonce.isValidWatchPairingIdentifier
            && baseline.schemaVersion == WatchSnapshotContract.schemaVersion
            && baseline.pairingSession == pairingSession
            && packageData.count <= WatchSnapshotContract.maximumEncodedBytes
            && (packageData.isEmpty == (deferredRevision != nil))
            && (deferredRevision.map { $0 <= WatchSnapshotContract.maximumJSONInteger } ?? true)
    }
}

nonisolated enum WatchPairingWireDecoder {
    static func decodeReply(_ data: Data) -> WatchPairingReplyV1? {
        guard data.count <= WatchPairingContract.maximumEncodedBytes,
              let reply = try? JSONDecoder().decode(WatchPairingReplyV1.self, from: data),
              reply.isValid else { return nil }
        return reply
    }
}

nonisolated extension String {
    fileprivate var isValidWatchPairingIdentifier: Bool {
        !isEmpty && utf8.count <= WatchSnapshotContract.maximumIdentifierBytes
    }
}
