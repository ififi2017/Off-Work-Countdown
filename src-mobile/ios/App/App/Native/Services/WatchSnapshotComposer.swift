import Foundation

/// Maps the salary-free TypeScript Watch projection into the transport contract.
/// The caller owns revision persistence; TypeScript owns every shift boundary
/// and the content-validity boundary.
enum WatchSnapshotComposer {
    struct Metadata: Sendable {
        let sourceGeneration: String
        let revision: UInt64
        let accessRevision: UInt64
        let generatedAt: Date
        let accessVerifiedAt: Date
    }

    struct Presentation: Sendable {
        let localeIdentifier: String
        let timeZoneIdentifier: String
        let workingLabel: String
        let lunchLabel: String
        let restingLabel: String
        let overtimeLabel: String
        let finishedLabel: String

        var projection: WatchPresentationV1 {
            WatchPresentationV1(
                localeIdentifier: localeIdentifier,
                timeZoneIdentifier: timeZoneIdentifier,
                workingLabel: workingLabel,
                lunchLabel: lunchLabel,
                restingLabel: restingLabel,
                overtimeLabel: overtimeLabel,
                finishedLabel: finishedLabel
            )
        }
    }

    /// `authorization` is the verified value produced by `PlusEntitlement`.
    /// `nil` means verification has not produced a result; it is not a denial.
    static func compose(
        metadata: Metadata,
        authorization: PlusAuthorization?,
        rules: NativeWatchRulesProjection?,
        presentation: Presentation
    ) -> WatchSnapshotPackageV1? {
        guard let generatedAtMs = milliseconds(metadata.generatedAt),
              let verifiedAtMs = milliseconds(metadata.accessVerifiedAt) else { return nil }

        let access = accessProjection(
            authorization,
            revision: metadata.accessRevision,
            verifiedAtMs: verifiedAtMs,
            generatedAtMs: generatedAtMs
        )
        let grantsAccess = access.status == .active || access.status == .lifetime
        let projectedExpiry = rules.flatMap { integerMilliseconds($0.contentExpiresAtMs) }
        let expiresAtMs: Int64
        if grantsAccess {
            guard let projectedExpiry, generatedAtMs < projectedExpiry else { return nil }
            expiresAtMs = projectedExpiry
        } else {
            expiresAtMs = projectedExpiry.map { max($0, generatedAtMs + 1) } ?? generatedAtMs + 1
        }
        let package = WatchSnapshotPackageV1(
            schemaVersion: WatchSnapshotContract.schemaVersion,
            sourceGeneration: metadata.sourceGeneration,
            revision: metadata.revision,
            generatedAtMs: generatedAtMs,
            expiresAtMs: expiresAtMs,
            access: access,
            content: grantsAccess ? rules.flatMap { contentProjection($0, presentation: presentation.projection) } : nil
        )
        return package.isValid ? package : nil
    }

    private static func accessProjection(
        _ authorization: PlusAuthorization?,
        revision: UInt64,
        verifiedAtMs: Int64,
        generatedAtMs: Int64
    ) -> WatchAccessProjectionV1 {
        let status: WatchAccessProjectionV1.Status
        let validUntilMs: Int64?
        switch authorization {
        case .authorized(.lifetime):
            status = .lifetime
            validUntilMs = nil
        case .authorized(.subscribed(let expiresAt)),
             .authorized(.inGracePeriod(let expiresAt)):
            if let deadline = milliseconds(expiresAt), deadline > generatedAtMs {
                status = .active
                validUntilMs = deadline
            } else {
                status = .locked
                validUntilMs = nil
            }
        case .pendingAskToBuy:
            status = .pending
            let lifetimeMs = Int64(PlusEntitlementSnapshot.askToBuyLifetimeSeconds * 1_000)
            let (deadline, overflow) = verifiedAtMs.addingReportingOverflow(lifetimeMs)
            validUntilMs = overflow || deadline > WatchSnapshotContract.maximumJSONTimestamp
                ? nil
                : deadline
        case .unauthorized:
            status = .locked
            validUntilMs = nil
        case nil:
            status = .unknown
            validUntilMs = nil
        }
        return WatchAccessProjectionV1(
            schemaVersion: WatchSnapshotContract.schemaVersion,
            revision: revision,
            verifiedAtMs: verifiedAtMs,
            status: status,
            validUntilMs: validUntilMs
        )
    }

    private static func contentProjection(
        _ rules: NativeWatchRulesProjection,
        presentation: WatchPresentationV1
    ) -> WatchShiftContentV1? {
        guard let scheduleState = WatchShiftContentV1.ScheduleState(rawValue: rules.scheduleState) else {
            return nil
        }
        let shift = rules.shift.flatMap { source -> WatchShiftProjectionV1? in
            let segments = source.segments.compactMap { segment -> WatchShiftSegmentV1? in
                guard let start = integerMilliseconds(segment.startAtMs),
                      let end = integerMilliseconds(segment.endAtMs) else { return nil }
                return .init(startAtMs: start, endAtMs: end)
            }
            let transitions = source.transitions.compactMap { transition -> WatchStateTransitionV1? in
                guard let at = integerMilliseconds(transition.atMs),
                      let state = WatchStateTransitionV1.State(rawValue: transition.state) else { return nil }
                return .init(atMs: at, state: state)
            }
            guard segments.count == source.segments.count,
                  transitions.count == source.transitions.count,
                  let plannedEnd = integerMilliseconds(source.plannedEndAtMs) else { return nil }
            let overtimeEnd = source.overtimeEndAtMs.flatMap(integerMilliseconds)
            let finishedAt = source.finishedAtMs.flatMap(integerMilliseconds)
            guard source.overtimeEndAtMs == nil || overtimeEnd != nil,
                  source.finishedAtMs == nil || finishedAt != nil else { return nil }
            return .init(
                segments: segments,
                plannedEndAtMs: plannedEnd,
                overtimeEndAtMs: overtimeEnd,
                finishedAtMs: finishedAt,
                isRunning: source.isRunning,
                transitions: transitions
            )
        }
        let nextShift = rules.nextShift.flatMap { source -> WatchNextShiftV1? in
            guard let start = integerMilliseconds(source.startAtMs),
                  let validUntil = integerMilliseconds(source.validUntilMs) else { return nil }
            return .init(startAtMs: start, validUntilMs: validUntil)
        }
        guard rules.shift == nil || shift != nil,
              rules.nextShift == nil || nextShift != nil else { return nil }
        return .init(
            scheduleState: scheduleState,
            shift: shift,
            nextShift: nextShift,
            presentation: presentation
        )
    }

    private static func milliseconds(_ date: Date) -> Int64? {
        integerMilliseconds(date.timeIntervalSince1970 * 1_000)
    }

    private static func integerMilliseconds(_ value: Double) -> Int64? {
        guard value.isFinite, value >= 0,
              value <= Double(WatchSnapshotContract.maximumJSONTimestamp) else { return nil }
        return Int64(value.rounded(.towardZero))
    }
}
