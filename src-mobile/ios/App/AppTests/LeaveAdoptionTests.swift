import Foundation
import Testing
@testable import App

/// Plan 020 P2c: adopting a proposal writes its leave days in one go, only
/// while it still fits, and undoing it gives everything back.
@MainActor
@Suite("Leave adoption")
struct LeaveAdoptionTests {
    private static let annual = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
    private static let inLieu = UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!
    private static let zone = "UTC"

    private static func ms(_ key: String, hour: Int) throws -> Double {
        let parts = try key.split(separator: "-").map { try #require(Int($0)) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return try #require(calendar.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: hour
        ))).timeIntervalSince1970 * 1_000
    }

    private static func balance(_ id: UUID = annual, entitled: Int = 20, through: String? = nil) -> LeaveBalance {
        LeaveBalance(
            id: id, kind: .annual, name: nil, entitledHalfDays: entitled, usedHalfDays: 0,
            validFromDayKey: nil, validThroughDayKey: through
        )
    }

    private static func item(_ dayKey: String, _ portion: LeavePortion = .whole, uses: [LeaveBudgetUse]? = nil) throws -> LeavePlanItem {
        LeavePlanItem(
            dayNumber: try #require(ExtendedScheduleResolver.dayNumber(dayKey: dayKey)),
            dayKey: dayKey,
            portion: portion,
            segments: [NativeShiftSegment(startAtMs: try ms(dayKey, hour: portion == .firstHalf ? 9 : 13),
                                          endAtMs: try ms(dayKey, hour: 18))],
            uses: uses ?? [LeaveBudgetUse(budgetID: annual, halfDays: portion.halfDays)],
            role: .bridge
        )
    }

    /// Monday through Wednesday off, bridging two weekends.
    private static func proposal() throws -> LeavePlanProposal {
        let items = [try item("2026-10-19"), try item("2026-10-20"), try item("2026-10-21", .firstHalf)]
        return LeavePlanProposal(
            firstRestDayNumber: try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-10-17")),
            lastRestDayNumber: try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-10-20")),
            firstRestDayKey: "2026-10-17",
            lastRestDayKey: "2026-10-20",
            items: items,
            uses: [LeaveBudgetUse(budgetID: annual, halfDays: 5)],
            lastShiftEndAtMs: nil,
            nextShiftStartAtMs: nil,
            dayKinds: [.rest, .rest, .leave, .leave],
            caveats: []
        )
    }

    private static func rows(
        _ proposal: LeavePlanProposal,
        now: String = "2026-10-10",
        balances: [LeaveBalance] = [balance()],
        leaveDays: [LeaveDay] = []
    ) throws -> Result<[LeaveDay], LeaveAdoptionError> {
        LeaveAdoption.rows(
            for: proposal, planID: UUID(), timeZoneIdentifier: zone,
            nowMs: try ms(now, hour: 12), balances: balances, leaveDays: leaveDays
        )
    }

    private func actions(defaults: UserDefaults, records: RecordCoordinator) -> RecordsActions {
        defaults.set(Self.zone, forKey: "ios.native.recordsTimeZone")
        let preferences = PreferencesStore(defaults: defaults, records: records)
        // Deliberately not authorized: adoption has no Plus gate.
        let plus = PlusEntitlement(defaults: defaults)
        return RecordsActions(records: records, preferences: preferences, plus: plus,
            text: AppText(preferences: preferences), currentHours: { _ in
                ScheduleHoursConfiguration(
                    startTime: "09:00", endTime: "18:00", workdays: [1, 2, 3, 4, 5],
                    schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                        singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
                    breakStartTime: "12:00", breakDurationMinutes: 60)
            })
    }

    @Test("A proposal that still fits becomes one leave day per item under one plan")
    func rowsForAFittingProposal() throws {
        let rows = try Self.rows(Self.proposal()).get()
        #expect(rows.map(\.dayKey) == ["2026-10-19", "2026-10-20", "2026-10-21"])
        #expect(rows.map(\.portion) == [.whole, .whole, .firstHalf])
        #expect(Set(rows.compactMap(\.planID)).count == 1)
        #expect(rows.allSatisfy { $0.isValid })
    }

    @Test("A proposal that no longer fits is refused whole, with its reason")
    func staleProposalsAreRefused() throws {
        let proposal = try Self.proposal()
        let otherLeave = LeaveDay(dayKey: "2026-10-20", portion: .whole, uses: [], planID: nil, timeZoneIdentifier: Self.zone)
        #expect(try Self.rows(proposal, leaveDays: [otherLeave]) == .failure(.dayAlreadyOnLeave("2026-10-20")))
        #expect(try Self.rows(proposal, now: "2026-10-20") == .failure(.alreadyStarted("2026-10-19")))
        #expect(try Self.rows(proposal, balances: []) == .failure(.unknownBalance(Self.annual)))
        #expect(try Self.rows(proposal, balances: [Self.balance(through: "2026-10-20")])
            == .failure(.balanceOutsideValidity(Self.annual, "2026-10-21")))
        #expect(try Self.rows(proposal, balances: [Self.balance(entitled: 4)]) == .failure(.insufficientBalance(Self.annual)))
        // Leave adopted elsewhere counts against the same balance.
        let spent = LeaveDay(dayKey: "2026-11-02", portion: .whole,
                             uses: [LeaveBudgetUse(budgetID: Self.annual, halfDays: 2)], planID: UUID(), timeZoneIdentifier: Self.zone)
        #expect(try Self.rows(proposal, balances: [Self.balance(entitled: 6)], leaveDays: [spent])
            == .failure(.insufficientBalance(Self.annual)))
        let emptied = LeavePlanProposal(
            firstRestDayNumber: proposal.firstRestDayNumber, lastRestDayNumber: proposal.lastRestDayNumber,
            firstRestDayKey: proposal.firstRestDayKey, lastRestDayKey: proposal.lastRestDayKey,
            items: [], uses: [], lastShiftEndAtMs: nil, nextShiftStartAtMs: nil, dayKinds: [], caveats: []
        )
        #expect(try Self.rows(emptied) == .failure(.nothingToAdopt))
    }

    @Test("Adopting without Plus writes the days, spends the balance and reaches the live plan; undo gives it back")
    func adoptAndUndo() async throws {
        let suite = "LeaveAdoption.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = RecordCoordinator.inMemory()
        let actions = actions(defaults: defaults, records: records)
        records.upsertLeaveBalance(Self.balance())
        records.upsertLeaveBalance(Self.balance(Self.inLieu, entitled: 4))
        // A day the user took by hand, outside any plan.
        records.upsertLeaveDay(LeaveDay(dayKey: "2026-11-02", portion: .whole,
                                        uses: [LeaveBudgetUse(budgetID: Self.inLieu, halfDays: 2)],
                                        planID: nil, timeZoneIdentifier: Self.zone))

        let now = Date(timeIntervalSince1970: try Self.ms("2026-10-10", hour: 12) / 1_000)
        let planID = try await actions.adoptLeavePlan(try Self.proposal(), at: now).value.get()
        #expect(records.state.leaveDays.filter { $0.planID == planID }.map(\.dayKey)
            == ["2026-10-19", "2026-10-20", "2026-10-21"])
        let budgets = LeaveAdoption.budgets(balances: records.state.leaveBalances, leaveDays: records.state.leaveDays)
        #expect(budgets.map(\.availableHalfDays) == [15, 2])

        let hours = ExtendedScheduleDayHours(startTime: "09:00", endTime: "18:00", breakStartTime: "12:00", breakDurationMinutes: 60)
        let live = try #require(records.extendedSchedulePlan(nil, applyingLeaveOver: hours))
        #expect(live.leaveDays == ["2026-10-19": .whole, "2026-10-20": .whole, "2026-10-21": .firstHalf, "2026-11-02": .whole])

        // Adopting the same plan again finds its own days taken.
        #expect(await actions.adoptLeavePlan(try Self.proposal(), at: now).value
            == .failure(.dayAlreadyOnLeave("2026-10-19")))

        #expect(await actions.undoLeavePlan(planID, at: now).value == 3)
        #expect(records.state.leaveDays.map(\.dayKey) == ["2026-11-02"])
        #expect(records.state.isErased(.leaveDay, key: "2026-10-20"))
        let restored = LeaveAdoption.budgets(balances: records.state.leaveBalances, leaveDays: records.state.leaveDays)
        #expect(restored.map(\.availableHalfDays) == [20, 2])
        #expect(records.extendedSchedulePlan(nil, applyingLeaveOver: hours)?.leaveDays == ["2026-11-02": .whole])

        // The same days can be adopted again, above their tombstones.
        let again = try await actions.adoptLeavePlan(try Self.proposal(), at: now).value.get()
        #expect(again != planID)
        #expect(!records.state.isErased(.leaveDay, key: "2026-10-20"))
    }
}

/// Plan 020 P3: the free-plan count stays on the device and counts each
/// distinct request once.
@MainActor
@Suite("Leave planner free plans")
struct LeavePlannerTrialTests {
    @Test("Three free plans, each request counted once and kept on this device only")
    func trialCount() throws {
        let suite = "LeavePlannerTrial.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults, records: RecordCoordinator.inMemory())
        #expect(preferences.leavePlannerTrialsLeft == 3)
        preferences.countLeavePlannerTrial(request: "a")
        preferences.countLeavePlannerTrial(request: "a")
        #expect(preferences.leavePlannerTrialsLeft == 2)
        preferences.countLeavePlannerTrial(request: "b")
        preferences.countLeavePlannerTrial(request: "c")
        preferences.countLeavePlannerTrial(request: "d")
        #expect(preferences.leavePlannerTrialsLeft == 0)

        // A relaunch reads the same count back; nothing reaches synced settings.
        let reopened = PreferencesStore(defaults: defaults, records: RecordCoordinator.inMemory())
        #expect(reopened.leavePlannerTrialsLeft == 0)
        #expect(reopened.leavePlannerTrialsUsed == 4)
    }

    @Test("A request's fingerprint ignores the order balances were picked in")
    func fingerprint() {
        let first = UUID(), second = UUID()
        let one = ShiftSessionStore.LeavePlanRequest(goal: .restAtLeast(days: 7), fromDayNumber: 1, throughDayNumber: 9,
                                                     budgetIDs: [first, second])
        var other = one
        other.budgetIDs = [second, first]
        #expect(one.fingerprint == other.fingerprint)
        other.goal = .leaveAtMost(halfDays: 7)
        #expect(one.fingerprint != other.fingerprint)
    }
}
