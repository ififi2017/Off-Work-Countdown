import Foundation
import Testing
@testable import App

/// A schedule row an older build re-saved must not replace this device's copy:
/// it can be missing fields (pattern provenance, newer shift fields), and its
/// edit count says nothing about which copy is newer data.
@MainActor
@Suite("Schedule rows from older builds")
struct ScheduleSyncWriterTests {
    private static let zone = "Asia/Shanghai"
    private static let work = UUID(uuidString: "00000000-0000-0000-0000-000000000A01")!
    private static let rest = UUID(uuidString: "00000000-0000-0000-0000-000000000A02")!
    private static let other = UUID(uuidString: "00000000-0000-0000-0000-000000000A03")!
    private static let when = Date(timeIntervalSince1970: 1_790_000_000)

    private static func type(_ id: UUID, _ name: String, _ kind: ShiftType.Kind) -> ShiftType {
        ShiftType(id: id, name: name, kind: kind, startMinutes: 600, endMinutes: 1_140,
                  breakEnabled: false, breakStartMinutes: 720, breakDurationMinutes: 0,
                  colorHex: "#FF9500", isArchived: false)
    }

    private static func records() -> RecordCoordinator {
        let records = RecordCoordinator.inMemory()
        _ = records.updateExtendedSchedule(
            content: ExtendedScheduleContent(
                shiftTypes: [type(work, "Day", .work), type(rest, "Rest", .rest)],
                rule: ShiftCycleRule(preset: .weekly, anchorDayKey: "2026-09-28",
                                     days: [work, work, work, work, work, rest, rest])
            ),
            enabled: true, timeZoneIdentifier: zone, at: when
        )
        return records
    }

    private static func row(_ key: String, _ id: UUID, generated: Bool?, count: Int) -> RosterDay {
        RosterDay(dayKey: key, shiftTypeID: id, generatedFromPattern: generated, timeZoneIdentifier: zone,
                  editedAt: when.addingTimeInterval(600), editCount: count, editTieBreaker: UUID())
    }

    /// What a build without the writer stamp uploads: the bare DTO.
    private static func olderPayload(_ day: RosterDay) throws -> Data {
        try JSONEncoder().encode(RosterDayDTO(day))
    }

    private static func apply(_ records: RecordCoordinator, _ type: RecordEntityType, key: String,
                              payload: Data, count: Int) {
        records.applyRemotePayload(type: type, key: key, payload: payload, editCount: count,
                                   editTieBreaker: UUID().uuidString, systemFields: nil, generation: 1)
    }

    @Test("Uploads carry the stamp; identical content from an older build changes nothing")
    func stampAndSameContent() throws {
        let records = Self.records()
        records.applyRosterEdits(["2026-10-08": .shift(Self.work)], generatedDays: ["2026-10-08"],
                                 timeZoneIdentifier: Self.zone, at: Self.when)
        let local = try #require(records.state.rosterDays.first)
        let uploaded = try #require(RecordsSyncPayload.encode(type: .rosterDay, key: "2026-10-08", from: records.state))
        #expect(!RecordsSyncPayload.isFromOlderScheduleWriter(uploaded, type: .rosterDay))
        #expect(RecordsSyncPayload.isFromOlderScheduleWriter(try Self.olderPayload(local), type: .rosterDay))

        let before = records.state.rosterDays
        Self.apply(records, .rosterDay, key: local.dayKey, payload: try Self.olderPayload(local), count: local.editCount)
        #expect(records.state.rosterDays == before)
    }

    @Test("An older build's re-save cannot strip provenance or change the shift; this copy goes back above it")
    func olderRosterRowIsRefused() throws {
        let records = Self.records()
        records.applyRosterEdits(["2026-10-08": .shift(Self.work)], generatedDays: ["2026-10-08"],
                                 timeZoneIdentifier: Self.zone, at: Self.when)
        let local = try #require(records.state.rosterDays.first)
        #expect(local.generatedFromPattern == true)

        let stripped = Self.row("2026-10-08", Self.rest, generated: nil, count: local.editCount + 5)
        Self.apply(records, .rosterDay, key: stripped.dayKey, payload: try Self.olderPayload(stripped), count: stripped.editCount)

        let kept = try #require(records.state.rosterDays.first)
        #expect(kept.shiftTypeID == Self.work)
        #expect(kept.generatedFromPattern == true)
        #expect(kept.editCount > stripped.editCount)
        let name = RecordsSyncIdentity.recordName(type: .rosterDay, key: "2026-10-08")
        #expect(records.state.sync.rows[name]?.dirty == true)
    }

    @Test("A current build's edit still wins on edit count, and a day this device lacks is taken as it is")
    func currentWriterAndNewRows() throws {
        let records = Self.records()
        records.applyRosterEdits(["2026-10-08": .shift(Self.work)], timeZoneIdentifier: Self.zone, at: Self.when)
        let local = try #require(records.state.rosterDays.first)

        let newer = Self.row("2026-10-08", Self.rest, generated: nil, count: local.editCount + 1)
        let stamped = try #require(RecordsSyncPayload.encode(.rosterDay(newer), calendar: Calendar(identifier: .gregorian)))
        Self.apply(records, .rosterDay, key: newer.dayKey, payload: stamped, count: newer.editCount)
        #expect(records.state.rosterDays.first { $0.dayKey == "2026-10-08" }?.shiftTypeID == Self.rest)

        let fresh = Self.row("2026-10-09", Self.rest, generated: nil, count: 1)
        Self.apply(records, .rosterDay, key: fresh.dayKey, payload: try Self.olderPayload(fresh), count: 1)
        #expect(records.state.rosterDays.first { $0.dayKey == "2026-10-09" }?.shiftTypeID == Self.rest)
    }

    @Test("An older build's schedule with other shift types cannot replace this one")
    func olderScheduleIsRefused() throws {
        let records = Self.records()
        let local = try #require(records.state.extendedSchedule)
        var older = local
        older.shiftTypes = [Self.type(Self.other, "Day", .work)]
        older.rule = ShiftCycleRule(preset: .weekly, anchorDayKey: "2026-09-28", days: Array(repeating: Self.other, count: 7))
        older.editCount = local.editCount + 3
        let payload = try JSONEncoder().encode(ExtendedScheduleDTO(older))
        Self.apply(records, .extendedSchedule, key: ExtendedSchedule.logicalKey, payload: payload, count: older.editCount)

        let kept = try #require(records.state.extendedSchedule)
        #expect(kept.shiftTypes.map(\.id) == [Self.work, Self.rest])
        #expect(kept.editCount > older.editCount)
    }
}
