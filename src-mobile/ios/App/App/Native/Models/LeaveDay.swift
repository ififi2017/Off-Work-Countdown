import Foundation

/// A shift, or half of one, the user takes as leave (plan 020 §2): what an
/// adopted leave plan writes, one row per day so two devices adopting on
/// different days never conflict.
///
/// `dayKey` is the day the shift starts, as everywhere else: an overnight
/// Friday 22:00–Saturday 06:00 keys as Friday. The portion names a half of
/// whatever shift the schedule gives that day, so the row keeps meaning "the
/// afternoon off" when the shift's hours change later.
///
/// `uses` records which balances pay for it. Balances are never decremented;
/// what an adopted plan has spent is the sum of these rows, so erasing a row
/// (undoing a plan) gives the half days back on every device.
nonisolated struct LeaveDay: Equatable, Sendable {
    static let schemaVersion = 1

    var dayKey: String
    var portion: LeavePortion
    /// Empty for leave the user did not charge to a balance; otherwise the
    /// half days sum to `portion.halfDays`, each balance listed once.
    var uses: [LeaveBudgetUse]
    /// The adopted plan that wrote the row, so undoing it can leave rows the
    /// user wrote or edited separately alone. `nil` for leave set by hand.
    var planID: UUID?
    /// Civil day this row was recorded in. Travel does not rewrite it.
    var timeZoneIdentifier: String
    var editedAt: Date = .distantPast
    var editCount: Int = 0
    var editTieBreaker: UUID = WorkObservation.unsetTieBreaker

    var isValid: Bool {
        let total = uses.reduce(0) { $0 + $1.halfDays }
        return ExtendedScheduleResolver.parse(dayKey: dayKey) != nil
            && TimeZone(identifier: timeZoneIdentifier) != nil
            && uses.allSatisfy { $0.halfDays > 0 }
            && Set(uses.map(\.budgetID)).count == uses.count
            && (total == 0 || total == portion.halfDays)
            && editCount >= 0
    }
}

extension Array where Element == LeaveDay {
    /// Half days adopted plans have spent from each balance.
    nonisolated func adoptedHalfDays() -> [UUID: Int] {
        reduce(into: [:]) { spent, day in
            for use in day.uses { spent[use.budgetID, default: 0] += use.halfDays }
        }
    }
}
