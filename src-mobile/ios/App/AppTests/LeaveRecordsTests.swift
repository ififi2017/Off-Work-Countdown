import Foundation
import Testing
@testable import App

/// Plan 020 P2a: leave balances and leave days as records — JSON schema 7,
/// backup import, iCloud payloads and the coordinator's edit stamps. Nothing
/// resolves a shift from these rows yet.
@MainActor
@Suite("Leave records data contract")
struct LeaveRecordsTests {
    private static let annual = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
    private static let inLieu = UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!
    private static let plan = UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!

    private static func balance(
        _ id: UUID = annual,
        kind: LeaveBalance.Kind = .annual,
        entitled: Int = 20,
        editCount: Int = 1
    ) -> LeaveBalance {
        LeaveBalance(
            id: id, kind: kind, name: kind == .custom ? "Marriage leave" : nil,
            entitledHalfDays: entitled, usedHalfDays: 3,
            validFromDayKey: nil, validThroughDayKey: "2027-03-31",
            editedAt: Date(timeIntervalSince1970: 1_790_000_000),
            editCount: editCount,
            editTieBreaker: UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
        )
    }

    private static func leaveDay(
        _ dayKey: String,
        portion: LeavePortion = .whole,
        uses: [LeaveBudgetUse]? = nil,
        editCount: Int = 1
    ) -> LeaveDay {
        LeaveDay(
            dayKey: dayKey,
            portion: portion,
            uses: uses ?? [LeaveBudgetUse(budgetID: annual, halfDays: portion.halfDays)],
            planID: plan,
            timeZoneIdentifier: "Asia/Shanghai",
            editedAt: Date(timeIntervalSince1970: 1_790_000_060),
            editCount: editCount,
            editTieBreaker: UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!
        )
    }

    private static func exportedDocument(_ state: RecordState) throws -> RecordJSONDocument {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return try RecordJSON.decode(RecordJSON.export(
            state, exportedAt: Date(timeIntervalSince1970: 0), timeZone: calendar.timeZone, calendar: calendar
        ))
    }

    @Test("A backup carries balances and leave days exactly")
    func backupRoundTrip() throws {
        var state = RecordState()
        state.leaveBalances = [Self.balance(), Self.balance(Self.inLieu, kind: .custom)]
        state.leaveDays = [
            Self.leaveDay("2026-10-08"),
            Self.leaveDay("2026-10-09", portion: .firstHalf, uses: [LeaveBudgetUse(budgetID: Self.inLieu, halfDays: 1)]),
            Self.leaveDay("2026-10-10", uses: []),
        ]
        let document = try Self.exportedDocument(state)
        #expect(document.schemaVersion == 7)

        var imported = RecordState()
        let report = try RecordJSON.apply(document, to: &imported, mode: .skipErased)
        #expect(report.rejected.isEmpty)
        #expect(imported.leaveBalances == state.leaveBalances)
        #expect(imported.leaveDays == state.leaveDays)

        let again = try RecordJSON.apply(document, to: &imported, mode: .skipErased)
        #expect(again.inserted.isEmpty && again.conflicts.isEmpty && again.rejected.isEmpty)
    }

    @Test("Malformed rows are rejected one by one, including a portion from a newer build")
    func invalidRowsAreRejected() throws {
        var state = RecordState()
        state.leaveBalances = [Self.balance()]
        state.leaveDays = [Self.leaveDay("2026-10-08")]
        var document = try Self.exportedDocument(state)
        var inverted = Self.balance(Self.inLieu)
        inverted.validFromDayKey = "2027-04-01"  // after its own end
        document.leaveBalances?.append(LeaveBalanceDTO(inverted))
        var future = LeaveDayDTO(Self.leaveDay("2026-10-09"))
        future.portion = "quarter"
        document.leaveDays?.append(future)
        document.leaveDays?.append(LeaveDayDTO(Self.leaveDay(
            "2026-10-12", portion: .whole, uses: [LeaveBudgetUse(budgetID: Self.annual, halfDays: 1)]
        )))

        var imported = RecordState()
        let report = try RecordJSON.apply(document, to: &imported, mode: .skipErased)
        #expect(imported.leaveBalances.map(\.id) == [Self.annual])
        #expect(imported.leaveDays.map(\.dayKey) == ["2026-10-08"])
        #expect(report.rejected.filter { $0.entityType == .leaveBalance }.count == 1)
        #expect(report.rejected.filter { $0.entityType == .leaveDay }.count == 2)
    }

    @Test("Restoring an erased balance moves the days that spend it to its new id")
    func restoredBalanceKeepsItsDays() throws {
        var source = RecordState()
        source.leaveBalances = [Self.balance()]
        source.leaveDays = [Self.leaveDay("2026-10-08")]
        let document = try Self.exportedDocument(source)

        var state = RecordState()
        state.leaveBalances = [Self.balance()]
        state.erase(.leaveBalance, key: Self.annual.uuidString, at: .now)
        let report = try RecordJSON.apply(document, to: &state, mode: .restoreErased)
        #expect(report.restored[.leaveBalance] == 1)
        let restored = try #require(state.leaveBalances.first)
        #expect(restored.id != Self.annual)
        #expect(state.leaveDays.first?.uses == [LeaveBudgetUse(budgetID: restored.id, halfDays: 2)])
    }

    @Test("iCloud payloads round-trip under stable, distinct record names")
    func syncPayloads() throws {
        var state = RecordState()
        state.leaveBalances = [Self.balance()]
        state.leaveDays = [Self.leaveDay("2026-10-08", portion: .secondHalf)]
        let calendar = RecordsSyncPayload.fileCalendar(for: state)

        let balancePayload = try #require(
            RecordsSyncPayload.encode(type: .leaveBalance, key: Self.annual.uuidString, from: state)
        )
        #expect(RecordsSyncPayload.incoming(from: balancePayload, type: .leaveBalance, calendar: calendar)
            == .leaveBalance(Self.balance()))
        let dayPayload = try #require(RecordsSyncPayload.encode(type: .leaveDay, key: "2026-10-08", from: state))
        #expect(RecordsSyncPayload.incoming(from: dayPayload, type: .leaveDay, calendar: calendar)
            == .leaveDay(state.leaveDays[0]))

        #expect(RecordsSyncIdentity.recordName(type: .leaveBalance, key: Self.annual.uuidString)
            == "leavebal.00000000-0000-0000-0000-00000000a001")
        #expect(RecordsSyncIdentity.recordName(type: .leaveDay, key: "2026-10-08") == "leave.2026-10-08")
        let names = RecordEntityType.allCases.map { RecordsSyncIdentity.recordName(type: $0, key: "key") }
        #expect(Set(names).count == names.count)
        #expect(RecordsSyncIdentity.needsFullRefetch(storedRevision: 2))
        #expect(!RecordsSyncIdentity.needsFullRefetch(storedRevision: 3))

        for type in [RecordEntityType.leaveBalance, .leaveDay] {
            let copy = SyncConflictCopy(
                entityType: type, logicalKey: "key", payload: dayPayload, lostAtMs: 0,
                localPayload: dayPayload, incomingPayload: dayPayload
            )
            #expect(!copy.supportsFieldMerge)
        }
    }

    @Test("Editing a leave day stamps it once, skips no-op edits and revives above its tombstone")
    func coordinatorLeaveDays() throws {
        let records = RecordCoordinator.inMemory()
        records.upsertLeaveDay(Self.leaveDay("2026-10-08", editCount: 0))
        let first = try #require(records.state.leaveDays.first)
        #expect(first.editCount == 1)
        records.upsertLeaveDay(first)
        #expect(records.state.leaveDays.first?.editCount == 1)

        records.upsertLeaveDay(Self.leaveDay("2026-10-08", portion: .firstHalf))
        let edited = try #require(records.state.leaveDays.first)
        #expect(edited.editCount == 2)
        #expect(edited.portion == .firstHalf)

        records.erase(.leaveDay, key: "2026-10-08")
        #expect(records.state.leaveDays.isEmpty)
        #expect(records.state.isErased(.leaveDay, key: "2026-10-08"))
        records.upsertLeaveDay(Self.leaveDay("2026-10-08"))
        let revived = try #require(records.state.leaveDays.first)
        #expect(!records.state.isErased(.leaveDay, key: "2026-10-08"))
        #expect(revived.editCount > edited.editCount)
        #expect(records.state.hasUnpairedRecords)
    }

    @Test("Balances are stamped like other records and invalid drafts never land")
    func coordinatorBalances() throws {
        let records = RecordCoordinator.inMemory()
        var invalid = Self.balance(kind: .custom)
        invalid.name = "  "
        records.upsertLeaveBalance(invalid)
        records.upsertLeaveDay(Self.leaveDay("2026-10-08", portion: .whole,
                                             uses: [LeaveBudgetUse(budgetID: Self.annual, halfDays: 1)]))
        #expect(records.state.leaveBalances.isEmpty)
        #expect(records.state.leaveDays.isEmpty)

        records.upsertLeaveBalance(Self.balance(editCount: 0))
        #expect(records.state.leaveBalances.first?.editCount == 1)
        records.upsertLeaveBalance(Self.balance(editCount: 0))
        #expect(records.state.leaveBalances.first?.editCount == 1)
        records.upsertLeaveBalance(Self.balance(entitled: 24))
        #expect(records.state.leaveBalances.first?.editCount == 2)
        #expect(records.state.leaveBalances.first?.entitledHalfDays == 24)

        records.erase(.leaveBalance, key: Self.annual.uuidString)
        #expect(records.state.leaveBalances.isEmpty)
        #expect(records.state.isErased(.leaveBalance, key: Self.annual.uuidString))
    }

    @Test("Adopted leave is the sum of the days, so erasing a day gives it back")
    func adoptedHalfDays() {
        let days = [
            Self.leaveDay("2026-10-08"),
            Self.leaveDay("2026-10-09", portion: .firstHalf),
            Self.leaveDay("2026-10-12", uses: [
                LeaveBudgetUse(budgetID: Self.annual, halfDays: 1),
                LeaveBudgetUse(budgetID: Self.inLieu, halfDays: 1),
            ]),
            Self.leaveDay("2026-10-13", uses: []),
        ]
        #expect(days.adoptedHalfDays() == [Self.annual: 4, Self.inLieu: 1])
        #expect(Self.balance().budget(adoptedHalfDays: days.adoptedHalfDays()[Self.annual] ?? 0)?.availableHalfDays == 13)
        #expect(Array(days.dropFirst()).adoptedHalfDays() == [Self.annual: 2, Self.inLieu: 1])
    }
}
