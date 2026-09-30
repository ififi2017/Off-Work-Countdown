import Foundation

/// A pot of personal leave the user tracks: annual leave, time off in lieu, or
/// a kind they name themselves (plan 020 §2).
///
/// Amounts are whole half days, so "three and a half days" is `7` and never a
/// floating-point sum. Nothing here is tied to the calendar year: the user
/// states the entitlement, what they had already used before DoneAt, and an
/// optional validity window, and the planner only spends what is left inside
/// that window. It never grants next year's allowance or extends an expired one.
nonisolated struct LeaveBalance: Codable, Equatable, Sendable, Identifiable {
    nonisolated enum Kind: String, Codable, Sendable {
        case annual
        /// Time off in lieu. The user states it; overtime is never converted.
        case compensatory
        case custom

        /// A kind a newer build added reads as custom instead of dropping the balance.
        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .custom
        }
    }

    static let maximumNameLength = 40
    /// Ten years of a generous allowance; anything larger is a typo.
    static let maximumHalfDays = 2 * 366 * 10

    var id: UUID
    var kind: Kind
    /// Shown instead of the kind's name when set; required for `.custom`.
    var name: String?
    var entitledHalfDays: Int
    /// Already taken, including leave from before the user started DoneAt.
    var usedHalfDays: Int
    /// Civil dates, `YYYY-MM-DD`, inclusive. `nil` is open-ended.
    var validFromDayKey: String?
    var validThroughDayKey: String?

    /// What the planner may still spend, before any adopted plan is deducted.
    var remainingHalfDays: Int { max(0, entitledHalfDays - usedHalfDays) }

    var isValid: Bool {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let from = validFromDayKey.flatMap(ExtendedScheduleResolver.dayNumber(dayKey:))
        let through = validThroughDayKey.flatMap(ExtendedScheduleResolver.dayNumber(dayKey:))
        guard (validFromDayKey == nil) == (from == nil),
              (validThroughDayKey == nil) == (through == nil)
        else { return false }
        if let from, let through, from > through { return false }
        return (0...Self.maximumHalfDays).contains(entitledHalfDays)
            && (0...Self.maximumHalfDays).contains(usedHalfDays)
            && trimmed.count <= Self.maximumNameLength
            && (kind != .custom || !trimmed.isEmpty)
    }

    /// The planner's view of this balance, less `adoptedHalfDays` already
    /// committed by adopted plans.
    func budget(adoptedHalfDays: Int = 0) -> LeaveBudget? {
        guard isValid else { return nil }
        return LeaveBudget(
            id: id,
            availableHalfDays: max(0, remainingHalfDays - adoptedHalfDays),
            validFromDayNumber: validFromDayKey.flatMap(ExtendedScheduleResolver.dayNumber(dayKey:)),
            validThroughDayNumber: validThroughDayKey.flatMap(ExtendedScheduleResolver.dayNumber(dayKey:))
        )
    }
}

/// Spendable half days and the civil days they may be spent on.
nonisolated struct LeaveBudget: Equatable, Sendable {
    var id: UUID
    var availableHalfDays: Int
    var validFromDayNumber: Int?
    var validThroughDayNumber: Int?

    func covers(dayNumber: Int) -> Bool {
        (validFromDayNumber.map { dayNumber >= $0 } ?? true)
            && (validThroughDayNumber.map { dayNumber <= $0 } ?? true)
    }
}
