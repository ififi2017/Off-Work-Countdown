import Foundation
import Testing
@testable import App

@Suite("Watch snapshot transport contract")
struct WatchSnapshotContractTests {
    @Test("Locked packages serialize without shift content")
    func lockedPackageHasNoShiftPayload() throws {
        let package = makePackage(access: .init(schemaVersion: 1, revision: 4, verifiedAtMs: 100, status: .locked, validUntilMs: nil), content: nil)
        let data = try JSONEncoder().encode(package)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["content"] == nil)
        #expect(String(decoding: data, as: UTF8.self).contains("salary") == false)
        #expect(try WatchSnapshotDecoderV1.decode(data) == package)
    }

    @Test("Malformed, oversized, unsupported and invalid packages fail closed")
    func rejectsBadPackages() throws {
        #expect(throws: WatchSnapshotDecodeError.malformed) { try WatchSnapshotDecoderV1.decode(Data("{".utf8)) }
        #expect(throws: WatchSnapshotDecodeError.oversized) { try WatchSnapshotDecoderV1.decode(Data(repeating: 0, count: 65_537)) }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(makePackage())) as? [String: Any])
        object["schemaVersion"] = 2
        #expect(throws: WatchSnapshotDecodeError.unsupportedSchema) { try WatchSnapshotDecoderV1.decode(try JSONSerialization.data(withJSONObject: object)) }
        object["schemaVersion"] = 1
        object["expiresAtMs"] = 100
        #expect(throws: WatchSnapshotDecodeError.invalidPackage) { try WatchSnapshotDecoderV1.decode(try JSONSerialization.data(withJSONObject: object)) }
    }

    @Test("Two expiry boundaries remain distinguishable")
    func evaluatesIndependentExpiries() {
        let package = makePackage()
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(package, nowMs: 999) == .content(package.content!))
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(package, nowMs: 1_000) == .contentExpired)
        let accessFirst = makePackage(expiresAtMs: 2_000, access: .init(schemaVersion: 1, revision: 4, verifiedAtMs: 100, status: .active, validUntilMs: 900))
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(accessFirst, nowMs: 900) == .accessExpired)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(package, nowMs: -1) == .invalid)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(package, nowMs: WatchSnapshotContract.maximumJSONTimestamp + 1) == .invalid)
    }

    @Test("Pending access expires exactly and legacy pending fails closed")
    func pendingExpiry() {
        let pending = makePackage(access: .init(
            schemaVersion: 1, revision: 4, verifiedAtMs: 100,
            status: .pending, validUntilMs: 500
        ), content: nil)
        #expect(pending.isValid)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(pending, nowMs: 499) == .pending)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(pending, nowMs: 500) == .confirmationRequired)

        let legacy = makePackage(access: .init(
            schemaVersion: 1, revision: 4, verifiedAtMs: 100,
            status: .pending, validUntilMs: nil
        ), content: nil)
        #expect(legacy.isValid)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(legacy, nowMs: 101) == .confirmationRequired)
    }

    @Test("Future entitlement evidence is rejected")
    func rejectsFutureEvidence() {
        let future = makePackage(access: .init(
            schemaVersion: 1, revision: 4, verifiedAtMs: 101,
            status: .active, validUntilMs: 1_500
        ))
        #expect(!future.isValid)
    }

    @Test("Not-configured and stopped states need no invented shift")
    func explicitEmptyStates() throws {
        let presentation = makePackage().content!.presentation
        let notConfigured = makePackage(content: .init(scheduleState: .notConfigured, shift: nil, nextShift: nil, presentation: presentation))
        #expect(try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(notConfigured)) == notConfigured)
        let stopped = makePackage(content: .init(scheduleState: .stopped, shift: nil, nextShift: nil, presentation: presentation))
        #expect(try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(stopped)) == stopped)
        let rest = makePackage(content: .init(scheduleState: .scheduled, shift: nil, nextShift: nil, presentation: presentation))
        #expect(try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(rest)) == rest)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(rest, nowMs: 200) == .content(rest.content!))
    }

    @Test("A rest-day preview expires exactly when its next shift starts")
    func nextShiftPreviewBoundary() throws {
        let content = WatchShiftContentV1(
            scheduleState: .scheduled, shift: nil,
            nextShift: .init(startAtMs: 1_000, validUntilMs: 1_000),
            presentation: makePackage().content!.presentation
        )
        let package = makePackage(content: content)
        #expect(try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(package)) == package)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(package, nowMs: 999) == .content(content))
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(package, nowMs: 1_000) == .contentExpired)
        let stalePreview = makePackage(content: .init(
            scheduleState: .scheduled, shift: nil,
            nextShift: .init(startAtMs: 100, validUntilMs: 100),
            presentation: content.presentation
        ))
        #expect(stalePreview.isValid == false)
    }

    @Test("Only a current-session baseline can replace a source generation")
    func sourceGenerationHandshakeAndOrdering() {
        var state = WatchSnapshotOrderState()
        let first = makePackage(generation: "install-a", revision: 8)
        let initial = WatchSourceBaselineV1(schemaVersion: 1, pairingSession: "pair-1", sourceGeneration: "install-a", replacesGeneration: nil)
        let acceptedInitial = WatchSnapshotOrderEvaluator.evaluate(first, baseline: initial, pairingSession: "pair-1", state: state)
        #expect(acceptedInitial.decision == .accept)
        state = acceptedInitial.proposedState!
        #expect(WatchSnapshotOrderEvaluator.evaluate(makePackage(generation: "install-a", revision: 7), pairingSession: "pair-1", state: state).decision == .rejectStaleRevision)
        let rolledBackAccess = makePackage(generation: "install-a", revision: 9, access: .init(schemaVersion: 1, revision: 3, verifiedAtMs: 100, status: .active, validUntilMs: 1_500))
        #expect(WatchSnapshotOrderEvaluator.evaluate(rolledBackAccess, pairingSession: "pair-1", state: state).decision == .rejectStaleAccessRevision)

        let changedAtSameAccessRevision = makePackage(generation: "install-a", revision: 9, access: .init(schemaVersion: 1, revision: 4, verifiedAtMs: 100, status: .locked, validUntilMs: nil), content: nil)
        #expect(WatchSnapshotOrderEvaluator.evaluate(changedAtSameAccessRevision, pairingSession: "pair-1", state: state).decision == .rejectStaleAccessRevision)

        let replacement = WatchSourceBaselineV1(schemaVersion: 1, pairingSession: "pair-1", sourceGeneration: "install-b", replacesGeneration: "install-a")
        let replacementPackage = makePackage(generation: "install-b", revision: 0)
        #expect(WatchSnapshotOrderEvaluator.evaluate(replacementPackage, baseline: replacement, pairingSession: "wrong-pair", state: state).decision == .rejectBaseline)
        #expect(WatchSnapshotOrderEvaluator.evaluate(replacementPackage, baseline: replacement, pairingSession: "", state: state).decision == .rejectBaseline)
        let acceptedReplacement = WatchSnapshotOrderEvaluator.evaluate(replacementPackage, baseline: replacement, pairingSession: "pair-1", state: state)
        #expect(acceptedReplacement.decision == .accept)
        state = acceptedReplacement.proposedState!
        #expect(WatchSnapshotOrderEvaluator.evaluate(replacementPackage, baseline: replacement, pairingSession: "pair-1", state: state).decision == .duplicate)
        #expect(WatchSnapshotOrderEvaluator.evaluate(makePackage(generation: "install-a", revision: 99), pairingSession: "pair-1", state: state).decision == .rejectWrongGeneration)
        #expect(WatchSnapshotOrderEvaluator.evaluate(first, baseline: initial, pairingSession: "pair-1", state: state).decision == .rejectBaseline)
    }

    @Test("Invalid constructed packages and restored order state fail closed")
    func evaluatorTrustBoundaries() {
        let unsupported = WatchSnapshotPackageV1(schemaVersion: 2, sourceGeneration: "install-a", revision: 1, generatedAtMs: 100, expiresAtMs: 1_000, access: makePackage().access, content: makePackage().content)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(unsupported, nowMs: 200) == .invalid)
        #expect(WatchSnapshotOrderEvaluator.evaluate(unsupported, pairingSession: "pair-1", state: .init()).decision == .rejectInvalidPackage)

        let corrupt = WatchSnapshotOrderState(currentGeneration: "install-a", revision: 1, acceptedAccess: makePackage().access, retiredGenerations: ["install-a"])
        let baseline = WatchSourceBaselineV1(schemaVersion: 1, pairingSession: "pair-1", sourceGeneration: "install-b", replacesGeneration: "install-a")
        #expect(WatchSnapshotOrderEvaluator.evaluate(makePackage(generation: "install-b"), baseline: baseline, pairingSession: "pair-1", state: corrupt).decision == .rejectInvalidState)

        let oversizedBaseline = WatchSourceBaselineV1(schemaVersion: 1, pairingSession: String(repeating: "p", count: 129), sourceGeneration: "install-a", replacesGeneration: nil)
        #expect(WatchSnapshotOrderEvaluator.evaluate(makePackage(), baseline: oversizedBaseline, pairingSession: oversizedBaseline.pairingSession, state: .init()).decision == .rejectBaseline)
        let tooManyRetired = WatchSnapshotOrderState(retiredGenerations: Set((0 ... 64).map { "retired-\($0)" }))
        #expect(WatchSnapshotOrderEvaluator.evaluate(makePackage(), pairingSession: "pair-1", state: tooManyRetired).decision == .rejectInvalidState)
    }

    @Test("A proposed order state is inert until the receiver persists it")
    func acceptanceDoesNotMutateInputState() {
        let state = WatchSnapshotOrderState()
        let package = makePackage()
        let baseline = WatchSourceBaselineV1(schemaVersion: 1, pairingSession: "pair-1", sourceGeneration: "install-a", replacesGeneration: nil)
        let result = WatchSnapshotOrderEvaluator.evaluate(package, baseline: baseline, pairingSession: "pair-1", state: state)
        #expect(result.decision == .accept)
        #expect(result.proposedState?.currentGeneration == "install-a")
        #expect(state == WatchSnapshotOrderState())
        #expect(WatchSnapshotOrderEvaluator.evaluate(package, baseline: baseline, pairingSession: "pair-1", state: state).decision == .accept)
    }

    private func makePackage(
        generation: String = "install-a",
        revision: UInt64 = 4,
        expiresAtMs: Int64 = 1_000,
        access: WatchAccessProjectionV1 = .init(schemaVersion: 1, revision: 4, verifiedAtMs: 100, status: .active, validUntilMs: 1_500),
        content: WatchShiftContentV1? = WatchShiftContentV1(
            scheduleState: .scheduled,
            shift: .init(
                segments: [.init(startAtMs: 200, endAtMs: 500), .init(startAtMs: 600, endAtMs: 800)],
                plannedEndAtMs: 800,
                overtimeEndAtMs: nil,
                finishedAtMs: nil,
                isRunning: true,
                transitions: [.init(atMs: 200, state: .working), .init(atMs: 500, state: .lunch)]
            ),
            nextShift: nil,
            presentation: .init(localeIdentifier: "en", timeZoneIdentifier: "UTC", workingLabel: "Working", lunchLabel: "Lunch", restingLabel: "Resting", overtimeLabel: "Overtime", finishedLabel: "Finished")
        )
    ) -> WatchSnapshotPackageV1 {
        WatchSnapshotPackageV1(schemaVersion: 1, sourceGeneration: generation, revision: revision, generatedAtMs: 100, expiresAtMs: expiresAtMs, access: access, content: content)
    }
}
