import Foundation
import Testing
@testable import App

/// Plan 021 §3.11: the "Location verified" label is derived on display and
/// never claims more than the evidence behind each adopted boundary.
@Suite("Work time verification label")
nonisolated struct WorkTimeVerificationTests {
    private static let base = Date(timeIntervalSince1970: 1_794_211_200) // 2026-11-09 08:00 UTC
    private static let dayKey = "2026-11-09"

    private static func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    private static func entry(
        _ boundary: WorkTimeBoundary,
        minutes: Double,
        source: WorkTimeProvenance.Source = .nativeGeofence,
        evidence: WorkTimeProvenance.EvidenceLevel = .systemObservation,
        observed: Bool = true,
        reasons: [String] = ["automaticApplyOff"]
    ) -> WorkTimeProvenance.Boundary {
        .init(
            boundary: boundary, time: at(minutes), source: source,
            observedAt: observed ? at(minutes) : nil, receivedAt: at(minutes + 1),
            appliedAt: at(720), appliedBy: .reviewed, batchID: nil, rulesVersion: 1,
            evidenceLevel: evidence, reasons: reasons
        )
    }

    private static func provenance(_ boundaries: [WorkTimeProvenance.Boundary]) -> WorkTimeProvenance {
        WorkTimeProvenance(dayKey: dayKey, boundaries: boundaries, timeZoneIdentifier: "UTC")
    }

    private static func override(from start: Double, to end: Double) -> DayOverride {
        DayOverride(
            dayKey: dayKey, shiftAnchorDate: base, kind: .customSegments,
            segments: [NativeShiftSegment(startAtMs: at(start).timeIntervalSince1970 * 1_000,
                                          endAtMs: at(end).timeIntervalSince1970 * 1_000)]
        )
    }

    private static func summary(
        _ boundaries: [WorkTimeProvenance.Boundary],
        override: DayOverride? = override(from: 66, to: 600),
        local: Bool = true
    ) -> WorkTimeVerificationSummary? {
        .make(provenance: provenance(boundaries), override: override) { _, _ in local }
    }

    @Test("Both ends system-observed and unchanged: the day is location verified")
    func fullyVerified() throws {
        let result = try #require(Self.summary([Self.entry(.start, minutes: 66), Self.entry(.end, minutes: 600)]))
        #expect(result.headline == .verified)
        #expect(result.items.map(\.mark) == [.locationVerified, .locationVerified])
        #expect(!result.isHistorical)
    }

    @Test("Only one end has evidence: partly verified, never the whole day")
    func oneEnd() throws {
        let result = try #require(Self.summary([Self.entry(.start, minutes: 66)]))
        #expect(result.headline == .partial)
        #expect(result.items.map(\.boundary) == [.start])
    }

    @Test("A hand edit drops that boundary to adjusted and keeps the detection visible")
    func adjusted() throws {
        let result = try #require(Self.summary(
            [Self.entry(.start, minutes: 66), Self.entry(.end, minutes: 600)],
            override: Self.override(from: 60, to: 600)
        ))
        #expect(result.items.map(\.mark) == [.adjusted, .locationVerified])
        #expect(result.items[0].entry.time == Self.at(66))
        #expect(result.headline == .partial)
    }

    @Test("A cleared day keeps no verified boundary")
    func cleared() throws {
        let result = try #require(Self.summary([Self.entry(.start, minutes: 66)], override: nil))
        #expect(result.items.map(\.mark) == [.adjusted])
        #expect(result.headline == .sources)
    }

    @Test("Weak timing evidence is detected, not verified", arguments: ["staleEvent", "unknownObservationTime", "beyondAutomaticWindow"])
    func weakReasons(_ reason: String) throws {
        let result = try #require(Self.summary([Self.entry(.start, minutes: 66, reasons: [reason])]))
        #expect(result.items.map(\.mark) == [.systemDetected])
        #expect(result.headline == .sources)
    }

    @Test("A callback time only, or no observed time, is detected, not verified")
    func callbackOnly() {
        #expect(WorkTimeVerificationSummary.mark(for: Self.entry(.start, minutes: 66, evidence: .callbackReceipt)) == .systemDetected)
        #expect(WorkTimeVerificationSummary.mark(for: Self.entry(.start, minutes: 66, observed: false)) == .systemDetected)
    }

    @Test("Procedural reasons do not weaken the evidence")
    func proceduralReasons() {
        let entry = Self.entry(.start, minutes: 66, reasons: ["automaticApplyOff", "earlyStartNeedsConfirmation", "recordChangedByPerson"])
        #expect(WorkTimeVerificationSummary.mark(for: entry) == .locationVerified)
    }

    @Test("Shortcuts and personal statements never become location verified")
    func otherSources() {
        #expect(WorkTimeVerificationSummary.mark(for: Self.entry(.end, minutes: 600, source: .appIntentAutomation, evidence: .externalAction)) == .shortcutAction)
        #expect(WorkTimeVerificationSummary.mark(for: Self.entry(.end, minutes: 600, source: .userConfirmation, evidence: .personStatement)) == .personConfirmed)
        // A mismatched pair still never rises above its source.
        #expect(WorkTimeVerificationSummary.mark(for: Self.entry(.end, minutes: 600, source: .appIntentAutomation)) == .shortcutAction)
    }

    @Test("A day restored without this device's detection is a historical source")
    func historical() throws {
        let result = try #require(Self.summary([Self.entry(.start, minutes: 66), Self.entry(.end, minutes: 600)], local: false))
        #expect(result.headline == .verified)
        #expect(result.isHistorical)
    }

    @Test("Only unverified sources never show as historical")
    func historicalNeedsVerified() throws {
        let result = try #require(Self.summary(
            [Self.entry(.start, minutes: 66, source: .appIntentAutomation, evidence: .externalAction)], local: false
        ))
        #expect(!result.isHistorical)
    }

    @Test("No provenance, no card")
    func none() {
        #expect(WorkTimeVerificationSummary.make(provenance: nil, override: Self.override(from: 66, to: 600)) { _, _ in true } == nil)
    }

    @MainActor
    @Test("This device's adopted detection is matched by day, boundary and time")
    func localDetection() {
        let shift = AutomationShift(
            shiftKey: "\(Self.dayKey)#a", anchorDayKey: Self.dayKey,
            plannedStart: Self.at(60), plannedEnd: Self.at(600), segments: []
        )
        var state = WorkplaceAutomationState()
        var proposal = WorkTimeProposal(
            id: UUID(), shift: shift, boundary: .start, proposedTime: Self.at(66), sourceEventIDs: [],
            status: .manuallyApplied, reasons: [], createdAt: Self.at(66), resolvedAt: Self.at(720)
        )
        state.upsert(proposal)
        #expect(state.hasAdoptedDetection(dayKey: Self.dayKey, boundary: .start, at: Self.at(66)))
        #expect(!state.hasAdoptedDetection(dayKey: Self.dayKey, boundary: .end, at: Self.at(66)))
        #expect(!state.hasAdoptedDetection(dayKey: Self.dayKey, boundary: .start, at: Self.at(60)))
        proposal.status = .dismissed
        state.upsert(proposal)
        #expect(!state.hasAdoptedDetection(dayKey: Self.dayKey, boundary: .start, at: Self.at(66)))
    }

    // MARK: Records label

    private static func planned(from start: Double, to end: Double) -> [NativeShiftSegment] {
        [NativeShiftSegment(startAtMs: at(start).timeIntervalSince1970 * 1_000, endAtMs: at(end).timeIntervalSince1970 * 1_000)]
    }

    @Test("A day only automation wrote is not called the person's change")
    func automationOnlyDay() {
        // Planned 09:00–18:00 (60–600); automation adopted a 19:30 end (690).
        let plan = Self.planned(from: 60, to: 600)
        let adopted = Self.provenance([Self.entry(.end, minutes: 690)])
        #expect(WorkTimeProvenance.isAutomationOnly(provenance: adopted, override: Self.override(from: 60, to: 690), plannedSegments: plan))
        // The person moved the adopted end: their change.
        #expect(!WorkTimeProvenance.isAutomationOnly(provenance: adopted, override: Self.override(from: 60, to: 700), plannedSegments: plan))
        // The person moved the start automation never touched: their change.
        #expect(!WorkTimeProvenance.isAutomationOnly(provenance: adopted, override: Self.override(from: 45, to: 690), plannedSegments: plan))
        // No summary at all: an ordinary edit.
        #expect(!WorkTimeProvenance.isAutomationOnly(provenance: nil, override: Self.override(from: 60, to: 690), plannedSegments: plan))
    }
}
