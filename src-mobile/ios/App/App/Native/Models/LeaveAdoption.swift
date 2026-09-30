import Foundation

/// Why a proposal can no longer be adopted as it stands (plan 020 §2).
nonisolated enum LeaveAdoptionError: Error, Equatable, Sendable {
    /// The records archive is damaged and blocks writes.
    case archiveUnavailable
    /// The break needs no leave, so there is nothing to write.
    case nothingToAdopt
    /// Another plan or the user already took leave on this day.
    case dayAlreadyOnLeave(String)
    /// Time passed since the plan was made and this shift has begun.
    case alreadyStarted(String)
    /// The balance was removed or is no longer valid.
    case unknownBalance(UUID)
    /// The balance cannot be spent on this day any more.
    case balanceOutsideValidity(UUID, String)
    /// Other leave or an edit left too little of this balance.
    case insufficientBalance(UUID)
}

/// Turning a proposal into leave days, and the balances left after adopted
/// plans. Pure, so both the planner and adoption read the same figures.
///
/// A plan is adopted whole or not at all: every check runs before anything is
/// written. Balances are never decremented; what adopted plans spent is the
/// sum of their days, so undoing a plan — erasing its days — gives the half
/// days back on every device.
nonisolated enum LeaveAdoption {
    /// What the planner may spend from each valid balance, after the leave
    /// already adopted.
    static func budgets(balances: [LeaveBalance], leaveDays: [LeaveDay]) -> [LeaveBudget] {
        let adopted = leaveDays.adoptedHalfDays()
        return balances.compactMap { $0.budget(adoptedHalfDays: adopted[$0.id] ?? 0) }
    }

    /// The rows adopting `proposal` under `planID`, or the first reason it no
    /// longer fits the archive.
    static func rows(
        for proposal: LeavePlanProposal,
        planID: UUID,
        timeZoneIdentifier: String,
        nowMs: Double,
        balances: [LeaveBalance],
        leaveDays existing: [LeaveDay]
    ) -> Result<[LeaveDay], LeaveAdoptionError> {
        guard !proposal.items.isEmpty else { return .failure(.nothingToAdopt) }
        let taken = Set(existing.map(\.dayKey))
        let valid = Dictionary(balances.filter(\.isValid).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var spending: [UUID: Int] = [:]
        for item in proposal.items {
            if taken.contains(item.dayKey) { return .failure(.dayAlreadyOnLeave(item.dayKey)) }
            guard let freed = item.segments.first, freed.startAtMs >= nowMs else {
                return .failure(.alreadyStarted(item.dayKey))
            }
            for use in item.uses {
                guard let balance = valid[use.budgetID], let budget = balance.budget() else {
                    return .failure(.unknownBalance(use.budgetID))
                }
                guard budget.covers(dayNumber: item.dayNumber) else {
                    return .failure(.balanceOutsideValidity(use.budgetID, item.dayKey))
                }
                spending[use.budgetID, default: 0] += use.halfDays
            }
        }
        let adopted = existing.adoptedHalfDays()
        for (id, halfDays) in spending where (adopted[id] ?? 0) + halfDays > valid[id]!.remainingHalfDays {
            return .failure(.insufficientBalance(id))
        }
        return .success(proposal.items.map { item in
            LeaveDay(
                dayKey: item.dayKey,
                portion: item.portion,
                uses: item.uses,
                planID: planID,
                timeZoneIdentifier: timeZoneIdentifier
            )
        })
    }
}

extension RecordCoordinator {
    /// Writes an adopted plan's days in one save. `rows` come from
    /// `LeaveAdoption.rows`, which has already checked them.
    func adoptLeave(_ rows: [LeaveDay], at date: Date = .now) {
        withBatchedWrites {
            for row in rows { upsertLeaveDay(row, at: date) }
        }
    }

    /// Erases the days an adopted plan wrote and returns their keys. A day the
    /// user has since set by hand no longer carries the plan's id and stays.
    @discardableResult
    func undoLeavePlan(_ planID: UUID, at date: Date = .now) -> [String] {
        let keys = state.leaveDays.filter { $0.planID == planID }.map(\.dayKey)
        withBatchedWrites {
            for key in keys { erase(.leaveDay, key: key, at: date) }
        }
        return keys
    }
}

extension RecordsActions {
    /// Adopts `proposal` as it stands now. No Plus gate: a free user's trial
    /// plans adopt fully, and adopted plans stay manageable after it ends.
    @discardableResult
    func adoptLeavePlan(
        _ proposal: LeavePlanProposal,
        at date: Date = .now
    ) -> RecordCommand<Result<UUID, LeaveAdoptionError>> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return .failure(.archiveUnavailable) }
            let planID = UUID()
            let rows = LeaveAdoption.rows(
                for: proposal,
                planID: planID,
                timeZoneIdentifier: preferences.recordsTimeZoneIdentifier,
                nowMs: date.timeIntervalSince1970 * 1_000,
                balances: records.state.leaveBalances,
                leaveDays: records.state.leaveDays
            )
            return rows.map { rows in
                records.adoptLeave(rows, at: date)
                return planID
            }
        }
    }

    /// Undoes an adopted plan and returns how many days it gave back.
    @discardableResult
    func undoLeavePlan(_ planID: UUID, at date: Date = .now) -> RecordCommand<Int> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return 0 }
            return records.undoLeavePlan(planID, at: date).count
        }
    }
}
