import Foundation

/// Plan 024 phase 4: one past day's overtime as the Records day editor shows
/// and saves it. A save writes a new `overtimeDeclared` observation (the latest
/// one counts); earlier observations are never changed.
nonisolated struct RecordOvertimeState: Equatable, Sendable {
    static let countedStepMs = 15.0 * 60_000

    /// Whether the day already has an overtime declaration.
    var hasDeclaration: Bool
    var startAtMs: Double
    var endAtMs: Double
    /// The hours that count, when they differ from the period. `nil` counts the
    /// period.
    var countedMs: Double?
    /// 0 is unpaid overtime; see `OvertimePay`.
    var payMultiplier: Double
    /// Where the day's regular work ends: overtime before it is not overtime.
    var regularEndAtMs: Double?
    /// The planned clock-off the declaration is recorded against.
    var plannedEndAtMs: Double?

    /// The period's length outside regular work, which is what Records measures.
    var measuredMs: Double {
        max(0, endAtMs - max(startAtMs, regularEndAtMs ?? startAtMs))
    }

    /// What statistics and pay use.
    var effectiveCountedMs: Double { countedMs ?? measuredMs }

    var isValid: Bool { startAtMs.isFinite && endAtMs.isFinite && endAtMs > startAtMs }

    /// One 15-minute step from the counted hours, from the nearest step.
    func steppedCountedMs(by direction: Int) -> Double {
        let step = Self.countedStepMs
        let current = (effectiveCountedMs / step).rounded() * step
        let next = current + Double(direction) * step
        return min(CountedOvertime.maximumMs, max(0, next))
    }

    /// Moves the period's start to the clock time of `date`, on the day the
    /// period starts, and keeps the end's clock time after it.
    mutating func setStart(timeOf date: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: startAtMs / 1_000))
        guard let start = calendar.date(
            bySettingHour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date), second: 0, of: day
        ) else { return }
        let endTime = Date(timeIntervalSince1970: endAtMs / 1_000)
        startAtMs = start.timeIntervalSince1970 * 1_000
        setEnd(timeOf: endTime, calendar: calendar)
    }

    /// Moves the period's end to the clock time of `date`: the first such time
    /// after the start, so an end past midnight stays one period.
    mutating func setEnd(timeOf date: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: startAtMs / 1_000))
        guard var end = calendar.date(
            bySettingHour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date), second: 0, of: day
        ) else { return }
        if end.timeIntervalSince1970 * 1_000 <= startAtMs {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(86_400)
        }
        endAtMs = end.timeIntervalSince1970 * 1_000
    }

    /// The declaration observation's payload.
    var payload: OvertimeDeclarationPayload {
        OvertimeDeclarationPayload(
            overtimeEndAtMs: endAtMs,
            plannedEndAtMs: plannedEndAtMs,
            payMultiplier: payMultiplier == 1 ? nil : payMultiplier,
            overtimeStartAtMs: startAtMs,
            countedMs: countedMs
        )
    }

    /// The day's overtime as the records show it now, or a one-hour starting
    /// point after the regular work for a day with none.
    @MainActor
    static func load(dayKey: String, queries: RecordsQueries) -> RecordOvertimeState {
        let resolution = queries.resolvedDay(dayKey: dayKey)
        let regularEnd = resolution?.segments.map(\.endAtMs).max()
        let plannedEnd = resolution?.baseScheduleSegments.map(\.endAtMs).max()
        if let resolution, let segment = queries.overtimeSegments(on: resolution).first {
            return RecordOvertimeState(
                hasDeclaration: true,
                startAtMs: segment.startAtMs,
                endAtMs: segment.endAtMs,
                countedMs: queries.overtimeCountedMs(on: resolution),
                payMultiplier: queries.overtimePayMultiplier(on: resolution),
                regularEndAtMs: regularEnd,
                plannedEndAtMs: plannedEnd
            )
        }
        let calendar = queries.recordsCalendar
        let dayStart = RecordJSON.date(fromDayKey: dayKey, calendar: calendar)
            .map { calendar.startOfDay(for: $0).timeIntervalSince1970 * 1_000 } ?? 0
        let start = regularEnd ?? plannedEnd ?? dayStart + 18 * 3_600_000
        return RecordOvertimeState(
            hasDeclaration: false,
            startAtMs: start,
            endAtMs: start + 3_600_000,
            countedMs: nil,
            payMultiplier: OvertimePay.defaultMultiplier,
            regularEndAtMs: regularEnd,
            plannedEndAtMs: plannedEnd
        )
    }
}
