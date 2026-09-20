import Foundation

nonisolated enum WatchSnapshotContract {
    static let schemaVersion = 1
    /// V4 also requires the free-schedule clearing boundary; V1–V3 remain readable.
    static let scheduleSchemaVersion = 4
    static let maximumEncodedBytes = 2 * 1_024 * 1_024
    static let maximumContextBytes = 48 * 1_024
    static let maximumJSONInteger: UInt64 = 9_007_199_254_740_991
    static let maximumJSONTimestamp = Int64(maximumJSONInteger)
    static let maximumIdentifierBytes = 128
    static let maximumRetiredGenerations = 64
}

nonisolated struct WatchSnapshotPackageV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceGeneration: String
    let revision: UInt64
    let generatedAtMs: Int64
    let expiresAtMs: Int64
    let access: WatchAccessProjectionV1
    let content: WatchShiftContentV1?
    var schedule: WatchScheduleV2? = nil

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, sourceGeneration, revision, generatedAtMs, expiresAtMs, access, content, schedule
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
        try container.encode(revision, forKey: .revision)
        try container.encode(generatedAtMs, forKey: .generatedAtMs)
        try container.encode(expiresAtMs, forKey: .expiresAtMs)
        if (2...4).contains(schemaVersion) {
            try container.encodeIfPresent(schedule, forKey: .schedule)
        } else {
            try container.encode(access, forKey: .access)
            try container.encodeIfPresent(content, forKey: .content)
        }
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        sourceGeneration = try values.decode(String.self, forKey: .sourceGeneration)
        revision = try values.decode(UInt64.self, forKey: .revision)
        generatedAtMs = try values.decode(Int64.self, forKey: .generatedAtMs)
        expiresAtMs = try values.decode(Int64.self, forKey: .expiresAtMs)
        if (2...4).contains(schemaVersion) {
            access = .init(schemaVersion: 1, revision: 0, verifiedAtMs: 0, status: .free, validUntilMs: nil)
            content = nil
            schedule = try values.decode(WatchScheduleV2.self, forKey: .schedule)
        } else {
            access = try values.decode(WatchAccessProjectionV1.self, forKey: .access)
            content = try values.decodeIfPresent(WatchShiftContentV1.self, forKey: .content)
        }
    }

    init(schemaVersion: Int, sourceGeneration: String, revision: UInt64, generatedAtMs: Int64,
         expiresAtMs: Int64, access: WatchAccessProjectionV1, content: WatchShiftContentV1?, schedule: WatchScheduleV2? = nil) {
        self.schemaVersion = schemaVersion; self.sourceGeneration = sourceGeneration; self.revision = revision
        self.generatedAtMs = generatedAtMs; self.expiresAtMs = expiresAtMs; self.access = access
        self.content = content; self.schedule = schedule
    }

}

nonisolated struct WatchAccessProjectionV1: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case free
        case active
        case lifetime
        case locked
        case unknown
        case pending
    }

    let schemaVersion: Int
    let revision: UInt64
    let verifiedAtMs: Int64
    let status: Status
    let validUntilMs: Int64?
}

nonisolated struct WatchShiftContentV1: Codable, Equatable, Sendable {
    enum ScheduleState: String, Codable, Sendable {
        case notConfigured
        case stopped
        case scheduled
    }

    let scheduleState: ScheduleState
    let shift: WatchShiftProjectionV1?
    let nextShift: WatchNextShiftV1?
    let presentation: WatchPresentationV1
}

nonisolated struct WatchShiftProjectionV1: Codable, Equatable, Sendable {
    let segments: [WatchShiftSegmentV1]
    let plannedEndAtMs: Int64
    let overtimeEndAtMs: Int64?
    let finishedAtMs: Int64?
    let isRunning: Bool
    let transitions: [WatchStateTransitionV1]
}

nonisolated struct WatchShiftSegmentV1: Codable, Equatable, Sendable {
    let startAtMs: Int64
    let endAtMs: Int64
}

nonisolated struct WatchStateTransitionV1: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case working
        case lunch
        case resting
        case overtime
        case finished
    }

    let atMs: Int64
    let state: State
}

nonisolated struct WatchNextShiftV1: Codable, Equatable, Sendable {
    let startAtMs: Int64
    /// Expiry of this preview, not the end of the future shift. It can equal
    /// the start: that instant requires a fresh current-shift projection.
    let validUntilMs: Int64
}

nonisolated struct WatchPresentationV1: Codable, Equatable, Sendable {
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let workingLabel: String
    let lunchLabel: String
    let restingLabel: String
    let overtimeLabel: String
    let finishedLabel: String
}

nonisolated enum WatchSnapshotDecodeError: Error, Equatable, Sendable {
    case oversized
    case malformed
    case unsupportedSchema
    case invalidPackage
}

nonisolated enum WatchSnapshotDecoderV1 {
    static func decode(_ data: Data) throws -> WatchSnapshotPackageV1 {
        guard data.count <= WatchSnapshotContract.maximumEncodedBytes else { throw WatchSnapshotDecodeError.oversized }
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let schema = object["schemaVersion"] as? Int, ![1, 2, 3, 4].contains(schema) {
            throw WatchSnapshotDecodeError.unsupportedSchema
        }
        guard let package = try? JSONDecoder().decode(WatchSnapshotPackageV1.self, from: data) else {
            throw WatchSnapshotDecodeError.malformed
        }
        guard [1, 2, 3, 4].contains(package.schemaVersion),
              package.access.schemaVersion == WatchSnapshotContract.schemaVersion else {
            throw WatchSnapshotDecodeError.unsupportedSchema
        }
        guard package.isValid else { throw WatchSnapshotDecodeError.invalidPackage }
        return package
    }
}

nonisolated extension WatchSnapshotPackageV1 {
    var isValid: Bool {
        guard [1, 2, 3, 4].contains(schemaVersion),
              access.schemaVersion == WatchSnapshotContract.schemaVersion,
              sourceGeneration.isValidWatchIdentifier,
              revision <= WatchSnapshotContract.maximumJSONInteger,
              generatedAtMs >= 0, generatedAtMs < expiresAtMs,
              expiresAtMs <= WatchSnapshotContract.maximumJSONTimestamp,
              access.verifiedAtMs <= generatedAtMs,
              access.isValid else { return false }

        if (2...4).contains(schemaVersion) {
            if schemaVersion < 4, schedule?.configuration.extendedSchedule?.clearedFromDayKey != nil {
                return false
            }
            if schemaVersion == 2, schedule?.configuration.extendedSchedule?.holidayRegionIdentifier?.isEmpty == false {
                return false
            }
            return access.status == .free && content == nil && schedule?.isValid == true
                && schedule?.presentation.isValid == true
        }
        guard schedule == nil, access.status != .free else { return false }
        let grantsAccess = access.status == .active || access.status == .lifetime
        guard grantsAccess == (content != nil),
              access.status != .lifetime || access.validUntilMs == nil,
              access.status != .active || access.validUntilMs != nil else { return false }
        guard let content else { return true }
        return content.isValid(generatedAtMs: generatedAtMs, expiresAtMs: expiresAtMs)
    }
}

private nonisolated extension WatchAccessProjectionV1 {
    var isValid: Bool {
        guard schemaVersion == WatchSnapshotContract.schemaVersion,
              revision <= WatchSnapshotContract.maximumJSONInteger,
              verifiedAtMs >= 0,
              verifiedAtMs <= WatchSnapshotContract.maximumJSONTimestamp,
              validUntilMs.map({ $0 <= WatchSnapshotContract.maximumJSONTimestamp }) ?? true,
              validUntilMs.map({ $0 > verifiedAtMs }) ?? true else { return false }
        switch status {
        case .active: return validUntilMs != nil
        case .free, .lifetime: return validUntilMs == nil
        case .locked, .unknown: return validUntilMs == nil
        // Older pending packages did not carry a deadline. Keep them decodable
        // so availability can fail closed to confirmationRequired.
        case .pending: return true
        }
    }
}

private nonisolated extension String {
    var isValidWatchIdentifier: Bool {
        !isEmpty && utf8.count <= WatchSnapshotContract.maximumIdentifierBytes
    }
}

private nonisolated extension WatchShiftContentV1 {
    func isValid(generatedAtMs: Int64, expiresAtMs: Int64) -> Bool {
        guard presentation.isValid else { return false }
        switch scheduleState {
        case .notConfigured:
            guard shift == nil, nextShift == nil else { return false }
        case .stopped:
            guard shift == nil || shift?.isRunning == false else { return false }
        case .scheduled:
            // A valid schedule can contain no work in the producer's horizon.
            // This explicit rest state must replace an older running package.
            break
        }

        if let shift, !shift.isValid(expiresAtMs: expiresAtMs) { return false }
        if let nextShift {
            guard nextShift.startAtMs >= 0,
                  nextShift.startAtMs <= nextShift.validUntilMs,
                  nextShift.validUntilMs > generatedAtMs,
                  nextShift.validUntilMs <= WatchSnapshotContract.maximumJSONTimestamp,
                  nextShift.validUntilMs <= expiresAtMs else { return false }
        }
        return true
    }
}

private nonisolated extension WatchShiftProjectionV1 {
    func isValid(expiresAtMs: Int64) -> Bool {
        guard !segments.isEmpty, segments.count <= 64, transitions.count <= 128,
              plannedEndAtMs > 0,
              plannedEndAtMs <= WatchSnapshotContract.maximumJSONTimestamp,
              overtimeEndAtMs.map({ $0 <= WatchSnapshotContract.maximumJSONTimestamp }) ?? true,
              overtimeEndAtMs.map({ $0 >= plannedEndAtMs }) ?? true else { return false }

        var previousEnd: Int64?
        for segment in segments {
            guard segment.startAtMs >= 0, segment.startAtMs < segment.endAtMs,
                  segment.endAtMs <= WatchSnapshotContract.maximumJSONTimestamp,
                  previousEnd.map({ $0 <= segment.startAtMs }) ?? true else { return false }
            previousEnd = segment.endAtMs
        }
        let effectiveEndAtMs = overtimeEndAtMs ?? plannedEndAtMs
        guard let firstStart = segments.first?.startAtMs,
              let lastEnd = previousEnd, effectiveEndAtMs >= lastEnd,
              finishedAtMs.map({ $0 >= firstStart && $0 <= effectiveEndAtMs }) ?? true else { return false }

        var previousTransition: Int64?
        for transition in transitions {
            guard transition.atMs >= 0, transition.atMs < expiresAtMs,
                  transition.atMs <= WatchSnapshotContract.maximumJSONTimestamp,
                  previousTransition.map({ $0 < transition.atMs }) ?? true else { return false }
            previousTransition = transition.atMs
        }
        if let finishedAtMs {
            guard !isRunning,
                  transitions.last == WatchStateTransitionV1(atMs: finishedAtMs, state: .finished)
            else { return false }
        }
        return true
    }
}

private nonisolated extension WatchPresentationV1 {
    var isValid: Bool {
        let strings = [localeIdentifier, timeZoneIdentifier, workingLabel, lunchLabel,
                       restingLabel, overtimeLabel, finishedLabel]
        return strings.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128 }
    }
}

nonisolated struct WatchSnapshotOrderState: Codable, Equatable, Sendable {
    var currentGeneration: String?
    var revision: UInt64?
    var acceptedAccess: WatchAccessProjectionV1?
    var retiredGenerations: Set<String>

    init(currentGeneration: String? = nil, revision: UInt64? = nil, acceptedAccess: WatchAccessProjectionV1? = nil, retiredGenerations: Set<String> = []) {
        self.currentGeneration = currentGeneration
        self.revision = revision
        self.acceptedAccess = acceptedAccess
        self.retiredGenerations = retiredGenerations
    }


    var isValid: Bool {
        guard retiredGenerations.count <= WatchSnapshotContract.maximumRetiredGenerations,
              retiredGenerations.allSatisfy(\.isValidWatchIdentifier) else { return false }
        switch (currentGeneration, revision, acceptedAccess) {
        case (nil, nil, nil): return true
        case let (.some(generation), .some(revision), .some(access)):
            return generation.isValidWatchIdentifier
                && !retiredGenerations.contains(generation)
                && revision <= WatchSnapshotContract.maximumJSONInteger
                && access.isValid
        default: return false
        }
    }
}

nonisolated struct WatchSourceBaselineV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let pairingSession: String
    let sourceGeneration: String
    let replacesGeneration: String?
}

nonisolated enum WatchSnapshotOrderDecision: Equatable, Sendable {
    case accept
    /// The receiver keeps its existing package and order state unchanged.
    case duplicate
    case rejectInvalidPackage
    case rejectInvalidState
    case rejectWrongGeneration
    case rejectStaleRevision
    case rejectStaleAccessRevision
    case rejectBaseline
}

nonisolated struct WatchSnapshotOrderEvaluation: Equatable, Sendable {
    let decision: WatchSnapshotOrderDecision
    /// Persist this together with the accepted package before publishing either in memory.
    let proposedState: WatchSnapshotOrderState?
}

nonisolated enum WatchSnapshotOrderEvaluator {
    static func evaluate(
        _ package: WatchSnapshotPackageV1,
        baseline: WatchSourceBaselineV1? = nil,
        pairingSession: String,
        state: WatchSnapshotOrderState
    ) -> WatchSnapshotOrderEvaluation {
        guard package.isValid else { return .init(decision: .rejectInvalidPackage, proposedState: nil) }
        guard state.isValid else { return .init(decision: .rejectInvalidState, proposedState: nil) }
        if let baseline {
            guard baseline.isValid,
                  pairingSession.isValidWatchIdentifier,
                  baseline.pairingSession == pairingSession,
                  baseline.sourceGeneration == package.sourceGeneration else {
                return .init(decision: .rejectBaseline, proposedState: nil)
            }

            if baseline.sourceGeneration == state.currentGeneration {
                guard baseline.replacesGeneration.map(state.retiredGenerations.contains) ?? true else {
                    return .init(decision: .rejectBaseline, proposedState: nil)
                }
                return evaluateCurrentGeneration(package, state: state)
            }

            guard !state.retiredGenerations.contains(baseline.sourceGeneration),
                  baseline.sourceGeneration != state.currentGeneration,
                  baseline.replacesGeneration == state.currentGeneration else {
                return .init(decision: .rejectBaseline, proposedState: nil)
            }

            var proposedState = state
            if let oldGeneration = state.currentGeneration {
                guard proposedState.retiredGenerations.count < WatchSnapshotContract.maximumRetiredGenerations else {
                    return .init(decision: .rejectInvalidState, proposedState: nil)
                }
                proposedState.retiredGenerations.insert(oldGeneration)
            }
            proposedState.currentGeneration = package.sourceGeneration
            proposedState.revision = package.revision
            proposedState.acceptedAccess = package.access
            return .init(decision: .accept, proposedState: proposedState)
        }

        guard package.sourceGeneration == state.currentGeneration,
              !state.retiredGenerations.contains(package.sourceGeneration) else {
            return .init(decision: .rejectWrongGeneration, proposedState: nil)
        }
        return evaluateCurrentGeneration(package, state: state)
    }

    private static func evaluateCurrentGeneration(
        _ package: WatchSnapshotPackageV1,
        state: WatchSnapshotOrderState
    ) -> WatchSnapshotOrderEvaluation {
        if package.revision == state.revision, package.access == state.acceptedAccess {
            return .init(decision: .duplicate, proposedState: nil)
        }
        guard state.revision.map({ package.revision > $0 }) ?? false else {
            return .init(decision: .rejectStaleRevision, proposedState: nil)
        }
        if (2...4).contains(package.schemaVersion) {
            var proposed = state
            proposed.revision = package.revision
            proposed.acceptedAccess = package.access
            return .init(decision: .accept, proposedState: proposed)
        }
        guard state.acceptedAccess?.status != .free else {
            return .init(decision: .rejectStaleRevision, proposedState: nil)
        }
        guard let acceptedAccess = state.acceptedAccess,
              package.access.revision >= acceptedAccess.revision else {
            return .init(decision: .rejectStaleAccessRevision, proposedState: nil)
        }
        guard package.access.revision != acceptedAccess.revision || package.access == acceptedAccess else {
            return .init(decision: .rejectStaleAccessRevision, proposedState: nil)
        }
        var proposedState = state
        proposedState.revision = package.revision
        proposedState.acceptedAccess = package.access
        return .init(decision: .accept, proposedState: proposedState)
    }
}

private nonisolated extension WatchSourceBaselineV1 {
    var isValid: Bool {
        schemaVersion == WatchSnapshotContract.schemaVersion
            && pairingSession.isValidWatchIdentifier
            && sourceGeneration.isValidWatchIdentifier
            && (replacesGeneration?.isValidWatchIdentifier ?? true)
    }
}

nonisolated enum WatchSnapshotAvailability: Equatable, Sendable {
    case content(WatchShiftContentV1)
    case contentExpired
    case accessExpired
    case locked
    case confirmationRequired
    case pending
    case invalid
}

nonisolated enum WatchSnapshotAvailabilityEvaluator {
    static func evaluate(_ package: WatchSnapshotPackageV1, nowMs: Int64) -> WatchSnapshotAvailability {
        guard nowMs >= 0, nowMs <= WatchSnapshotContract.maximumJSONTimestamp,
              package.isValid else { return .invalid }
        if let schedule = package.schedule { return .content(schedule.content(at: nowMs)) }
        switch package.access.status {
        case .free: return .invalid
        case .locked: return .locked
        case .unknown: return .confirmationRequired
        case .pending where package.access.validUntilMs.map({ nowMs >= $0 }) ?? true:
            return .confirmationRequired
        case .pending: return .pending
        case .active where package.access.validUntilMs.map({ nowMs >= $0 }) ?? true: return .accessExpired
        case .active, .lifetime:
            guard nowMs < package.expiresAtMs, let content = package.content else { return .contentExpired }
            return .content(content)
        }
    }
}
