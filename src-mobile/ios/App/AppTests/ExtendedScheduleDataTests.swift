import Foundation
import Testing
@testable import App

/// Plan 018 P8-a: the extended schedule's data contract — JSON schema 6,
/// backup import, iCloud payloads and the coordinator's edit stamps. Nothing
/// resolves a shift from these rows yet; that is P8-b.
@MainActor
@Suite("Extended schedule data contract")
struct ExtendedScheduleDataTests {
    private static let early = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
    private static let night = UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!
    private static let rest = UUID(uuidString: "00000000-0000-0000-0000-00000000D003")!

    private static func schedule(editCount: Int = 1) -> ExtendedSchedule {
        ExtendedSchedule(
            isEnabled: true,
            shiftTypes: [
                ShiftType(
                    id: early, name: "早班", kind: .work,
                    startMinutes: 8 * 60, endMinutes: 16 * 60,
                    breakEnabled: true, breakStartMinutes: 12 * 60, breakDurationMinutes: 30,
                    colorHex: "#F28C28", isArchived: false
                ),
                ShiftType(
                    id: night, name: "Night", kind: .work,
                    startMinutes: 22 * 60, endMinutes: 6 * 60,
                    breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
                    colorHex: "#3a6ea5", isArchived: false
                ),
                ShiftType(
                    id: rest, name: "休息", kind: .rest,
                    startMinutes: 0, endMinutes: 0,
                    breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
                    colorHex: "#9E9E9E", isArchived: true
                ),
            ],
            rule: ShiftCycleRule(preset: .rotation, anchorDayKey: "2026-10-01", days: [early, early, night, rest]),
            timeZoneIdentifier: "Asia/Shanghai",
            editedAt: Date(timeIntervalSince1970: 1_790_000_000),
            editCount: editCount,
            editTieBreaker: UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!
        )
    }

    private static func rosterDay(
        _ dayKey: String,
        _ shiftTypeID: UUID,
        assignedShiftType: ShiftType? = nil,
        editCount: Int = 1
    ) -> RosterDay {
        RosterDay(
            dayKey: dayKey,
            shiftTypeID: shiftTypeID,
            assignedShiftType: assignedShiftType,
            timeZoneIdentifier: "Asia/Shanghai",
            editedAt: Date(timeIntervalSince1970: 1_790_000_060),
            editCount: editCount,
            editTieBreaker: UUID(uuidString: "00000000-0000-0000-0000-00000000E002")!
        )
    }

    private static func exportedDocument(_ state: RecordState) throws -> RecordJSONDocument {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return try RecordJSON.decode(RecordJSON.export(
            state,
            exportedAt: Date(timeIntervalSince1970: 0),
            timeZone: calendar.timeZone,
            calendar: calendar
        ))
    }

    @Test("A backup carries the shift types, the rule and hand-set days exactly")
    func backupRoundTrip() throws {
        var state = RecordState()
        state.extendedSchedule = Self.schedule()
        state.rosterDays = [
            Self.rosterDay("2026-10-03", Self.night, assignedShiftType: Self.schedule().shiftTypes[1]),
            Self.rosterDay("2026-10-04", Self.rest),
        ]
        let document = try Self.exportedDocument(state)
        #expect(document.schemaVersion == 6)

        var imported = RecordState()
        let report = try RecordJSON.apply(document, to: &imported, mode: .skipErased)
        #expect(report.rejected.isEmpty)
        #expect(imported.extendedSchedule == state.extendedSchedule)
        #expect(imported.rosterDays == state.rosterDays)

        let again = try RecordJSON.apply(document, to: &imported, mode: .skipErased)
        #expect(again.inserted.isEmpty && again.conflicts.isEmpty && again.rejected.isEmpty)
    }

    @Test("An invalid schedule and a malformed day are rejected without dropping other rows")
    func invalidRowsAreRejected() throws {
        var state = RecordState()
        state.extendedSchedule = Self.schedule()
        state.rosterDays = [Self.rosterDay("2026-10-03", Self.night)]
        var document = try Self.exportedDocument(state)
        var schedule = try #require(document.extendedSchedule)
        schedule.rule?.days.append(UUID())  // a shift type the schedule does not define
        document.extendedSchedule = schedule
        document.rosterDays?.append(RosterDayDTO(Self.rosterDay("not-a-day", Self.early)))

        var imported = RecordState()
        let report = try RecordJSON.apply(document, to: &imported, mode: .skipErased)
        #expect(imported.extendedSchedule == nil)
        #expect(imported.rosterDays.map(\.dayKey) == ["2026-10-03"])
        #expect(Set(report.rejected.map(\.entityType)) == [.extendedSchedule, .rosterDay])
    }

    @Test("Shift types and rules validate what they store")
    func validation() {
        let valid = Self.schedule().shiftTypes[0]
        #expect(valid.isValid)
        var blank = valid
        blank.name = "  "
        #expect(!blank.isValid)
        var long = valid
        long.name = String(repeating: "班", count: ShiftType.maximumNameLength + 1)
        #expect(!long.isValid)
        var clock = valid
        clock.endMinutes = 1_440
        #expect(!clock.isValid)
        var emptyBreak = valid
        emptyBreak.breakDurationMinutes = 0
        #expect(!emptyBreak.isValid)
        emptyBreak.breakEnabled = false
        #expect(emptyBreak.isValid)
        var colour = valid
        colour.colorHex = "orange"
        #expect(!colour.isValid)

        var duplicate = Self.schedule()
        duplicate.shiftTypes.append(valid)
        #expect(!duplicate.isValid)
        var emptyRule = Self.schedule()
        emptyRule.rule?.days = []
        #expect(!emptyRule.isValid)
        var badAnchor = Self.schedule()
        badAnchor.rule?.anchorDayKey = "2026-02-30"
        #expect(!badAnchor.isValid)
        var freeCalendar = Self.schedule()
        freeCalendar.rule = nil
        #expect(freeCalendar.isValid)
    }

    @Test("iCloud payloads round-trip under stable, distinct record names")
    func syncPayloads() throws {
        var state = RecordState()
        state.extendedSchedule = Self.schedule()
        state.rosterDays = [Self.rosterDay("2026-10-03", Self.night)]
        let calendar = RecordsSyncPayload.fileCalendar(for: state)

        let schedulePayload = try #require(
            RecordsSyncPayload.encode(type: .extendedSchedule, key: ExtendedSchedule.logicalKey, from: state)
        )
        #expect(RecordsSyncPayload.incoming(from: schedulePayload, type: .extendedSchedule, calendar: calendar)
            == .extendedSchedule(Self.schedule()))
        let dayPayload = try #require(RecordsSyncPayload.encode(type: .rosterDay, key: "2026-10-03", from: state))
        #expect(RecordsSyncPayload.incoming(from: dayPayload, type: .rosterDay, calendar: calendar)
            == .rosterDay(state.rosterDays[0]))

        #expect(RecordsSyncIdentity.recordName(type: .extendedSchedule, key: ExtendedSchedule.logicalKey) == "extended-schedule")
        #expect(RecordsSyncIdentity.recordName(type: .rosterDay, key: "2026-10-03") == "roster.2026-10-03")
        let names = RecordEntityType.allCases.map { RecordsSyncIdentity.recordName(type: $0, key: "key") }
        #expect(Set(names).count == names.count)
    }

    @Test("Editing a day stamps it once, skips no-op edits and revives above its tombstone")
    func coordinatorRosterDays() throws {
        let records = RecordCoordinator.inMemory()
        records.upsertRosterDay(Self.rosterDay("2026-10-03", Self.night, editCount: 0))
        let first = try #require(records.state.rosterDays.first)
        #expect(first.editCount == 1)
        records.upsertRosterDay(first)
        #expect(records.state.rosterDays.first?.editCount == 1)

        records.upsertRosterDay(Self.rosterDay("2026-10-03", Self.early))
        let edited = try #require(records.state.rosterDays.first)
        #expect(edited.editCount == 2)
        #expect(edited.shiftTypeID == Self.early)

        // Back to the rule, then set by hand again.
        records.erase(.rosterDay, key: "2026-10-03")
        #expect(records.state.rosterDays.isEmpty)
        #expect(records.state.isErased(.rosterDay, key: "2026-10-03"))
        records.upsertRosterDay(Self.rosterDay("2026-10-03", Self.night))
        let revived = try #require(records.state.rosterDays.first)
        #expect(!records.state.isErased(.rosterDay, key: "2026-10-03"))
        #expect(revived.editCount > edited.editCount)
    }

    @Test("An invalid schedule never reaches the archive")
    func coordinatorRejectsInvalidSchedule() {
        let records = RecordCoordinator.inMemory()
        var invalid = Self.schedule()
        invalid.timeZoneIdentifier = "Not/A_Zone"
        records.upsertExtendedSchedule(invalid)
        #expect(records.state.extendedSchedule == nil)

        records.upsertExtendedSchedule(Self.schedule(editCount: 0))
        #expect(records.state.extendedSchedule?.editCount == 1)
        records.upsertExtendedSchedule(Self.schedule(editCount: 0))
        #expect(records.state.extendedSchedule?.editCount == 1)
        #expect(records.state.hasUnpairedRecords)
    }

    @Test("A build that learns new entity types refetches iCloud once")
    func refetchWhenEntityTypesGrow() throws {
        #expect(RecordsSyncIdentity.needsFullRefetch(storedRevision: nil))
        #expect(RecordsSyncIdentity.needsFullRefetch(storedRevision: 1))
        #expect(!RecordsSyncIdentity.needsFullRefetch(storedRevision: RecordsSyncIdentity.entityTypeRevision))

        // Archives written before the field existed still decode.
        let legacy = try JSONEncoder().encode(SyncLocalState.empty)
        #expect(!String(decoding: legacy, as: UTF8.self).contains("entityTypeRevision"))
        #expect(try JSONDecoder().decode(SyncLocalState.self, from: legacy) == .empty)
    }
}
