import Foundation
import Testing
@testable import App

/// Plan 021 C1: the minimal provenance of adopted workplace times as a
/// record — JSON schema 8, iCloud payloads, edit stamps and tombstones.
@MainActor
@Suite("Work time provenance data contract")
struct WorkTimeProvenanceTests {
    private static let base = Date(timeIntervalSince1970: 1_794_211_200) // 2026-11-09 08:00 UTC

    private static func entry(
        _ boundary: WorkTimeBoundary = .start,
        minutes: Double = 70,
        source: WorkTimeProvenance.Source = .nativeGeofence
    ) -> WorkTimeProvenance.Boundary {
        .init(
            boundary: boundary,
            time: base.addingTimeInterval(minutes * 60),
            source: source,
            observedAt: source == .nativeGeofence ? base.addingTimeInterval(minutes * 60) : nil,
            receivedAt: base.addingTimeInterval(minutes * 60 + 30),
            appliedAt: base.addingTimeInterval(12 * 3_600),
            appliedBy: .reviewed,
            batchID: UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!,
            rulesVersion: 1,
            evidenceLevel: source == .nativeGeofence ? .systemObservation : .externalAction,
            reasons: ["automaticApplyOff"]
        )
    }

    private static func row(_ dayKey: String = "2026-11-09", editCount: Int = 1) -> WorkTimeProvenance {
        WorkTimeProvenance(
            dayKey: dayKey,
            boundaries: [entry(), entry(.end, minutes: 600, source: .appIntentAutomation)],
            timeZoneIdentifier: "Asia/Shanghai",
            editedAt: base,
            editCount: editCount,
            editTieBreaker: UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!
        )
    }

    private static func exportedDocument(_ state: RecordState) throws -> RecordJSONDocument {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return try RecordJSON.decode(RecordJSON.export(
            state, exportedAt: Date(timeIntervalSince1970: 0), timeZone: calendar.timeZone, calendar: calendar
        ))
    }

    @Test("A backup carries the provenance exactly at schema 8")
    func backupRoundTrip() throws {
        var state = RecordState()
        state.workTimeProvenance = [Self.row()]
        let document = try Self.exportedDocument(state)
        #expect(document.schemaVersion == 8)
        #expect(document.workTimeProvenance?.count == 1)

        var restored = RecordState()
        let report = try RecordJSON.apply(document, to: &restored, mode: .skipErased)
        #expect(report.rejected.isEmpty)
        #expect(restored.workTimeProvenance == [Self.row()])
    }

    @Test("Malformed rows are rejected one by one, including a source from a newer build")
    func invalidRowsAreRejected() throws {
        var state = RecordState()
        state.workTimeProvenance = [Self.row("2026-11-09"), Self.row("2026-11-10")]
        var document = try Self.exportedDocument(state)
        document.workTimeProvenance?[1].boundaries[0].source = "wifiFromANewerBuild"
        var duplicate = WorkTimeProvenanceDTO(Self.row("2026-11-11"))
        duplicate.boundaries[1].boundary = "start"
        var empty = WorkTimeProvenanceDTO(Self.row("2026-11-12"))
        empty.boundaries = []
        document.workTimeProvenance?.append(contentsOf: [duplicate, empty])

        var restored = RecordState()
        let report = try RecordJSON.apply(document, to: &restored, mode: .skipErased)
        #expect(restored.workTimeProvenance.map(\.dayKey) == ["2026-11-09"])
        #expect(Set(report.rejected.map(\.logicalKey)) == ["2026-11-10", "2026-11-11", "2026-11-12"])
        #expect(report.rejected.allSatisfy { $0.entityType == .workTimeProvenance })
    }

    @Test("An erased row is not resurrected by a plain import but returns on restore")
    func tombstonesHoldAgainstImport() throws {
        var source = RecordState()
        source.workTimeProvenance = [Self.row()]
        let document = try Self.exportedDocument(source)

        var state = RecordState()
        state.erase(.workTimeProvenance, key: "2026-11-09", at: Self.base)
        _ = try RecordJSON.apply(document, to: &state, mode: .skipErased)
        #expect(state.workTimeProvenance.isEmpty)

        _ = try RecordJSON.apply(document, to: &state, mode: .restoreErased)
        #expect(state.workTimeProvenance.map(\.dayKey) == ["2026-11-09"])
    }

    @Test("iCloud payloads round-trip as prov.<dayKey>, whole-row, under revision 4")
    func syncPayloads() throws {
        var state = RecordState()
        state.workTimeProvenance = [Self.row()]
        let calendar = RecordsSyncPayload.fileCalendar(for: state)
        let payload = try #require(RecordsSyncPayload.encode(type: .workTimeProvenance, key: "2026-11-09", from: state))
        #expect(RecordsSyncPayload.incoming(from: payload, type: .workTimeProvenance, calendar: calendar)
            == .workTimeProvenance(Self.row()))
        #expect(RecordsSyncPayload.incoming(from: Data("{}".utf8), type: .workTimeProvenance, calendar: calendar) == nil)

        #expect(RecordsSyncIdentity.recordName(type: .workTimeProvenance, key: "2026-11-09") == "prov.2026-11-09")
        #expect(RecordsSyncIdentity.recordName(type: .dayOverride, key: "2026-11-09") == "day.2026-11-09")
        let names = RecordEntityType.allCases.map { RecordsSyncIdentity.recordName(type: $0, key: "key") }
        #expect(Set(names).count == names.count)
        #expect(RecordsSyncIdentity.entityTypeRevision == 4)
        #expect(RecordsSyncIdentity.needsFullRefetch(storedRevision: 3))
        #expect(!RecordsSyncIdentity.needsFullRefetch(storedRevision: 4))

        let copy = SyncConflictCopy(
            entityType: .workTimeProvenance, logicalKey: "2026-11-09", payload: payload, lostAtMs: 0,
            localPayload: payload, incomingPayload: payload
        )
        #expect(!copy.supportsFieldMerge)
    }

    @Test("Writing a summary stamps it once, skips no-op writes and revives above its tombstone")
    func coordinatorStamps() throws {
        let records = RecordCoordinator.inMemory()
        records.upsertWorkTimeProvenance(Self.row(editCount: 0))
        let first = try #require(records.state.workTimeProvenance.first)
        #expect(first.editCount == 1)
        records.upsertWorkTimeProvenance(first)
        #expect(records.state.workTimeProvenance.first?.editCount == 1)

        records.erase(.workTimeProvenance, key: "2026-11-09")
        #expect(records.state.workTimeProvenance.isEmpty)
        #expect(records.state.isErased(.workTimeProvenance, key: "2026-11-09"))
        records.upsertWorkTimeProvenance(Self.row())
        let revived = try #require(records.state.workTimeProvenance.first)
        #expect(!records.state.isErased(.workTimeProvenance, key: "2026-11-09"))
        #expect(revived.editCount > first.editCount)
        #expect(records.state.hasUnpairedRecords)

        var invalid = Self.row("2026-11-10")
        invalid.boundaries = []
        records.upsertWorkTimeProvenance(invalid)
        #expect(records.state.workTimeProvenance.count == 1)
    }

    @Test("Adopting a boundary replaces only that boundary, start first")
    func adoptingReplacesOneBoundary() {
        let start = WorkTimeProvenance(dayKey: "2026-11-09", boundaries: [Self.entry()], timeZoneIdentifier: "UTC")
        let both = start.adopting(Self.entry(.end, minutes: 600))
        #expect(both.boundaries.map(\.boundary) == [.start, .end])
        let corrected = both.adopting(Self.entry(minutes: 75))
        #expect(corrected.boundaries.map(\.boundary) == [.start, .end])
        #expect(corrected.boundary(.start)?.time == Self.base.addingTimeInterval(75 * 60))
    }
}
