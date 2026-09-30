import Foundation

/// Bounds summarize scheduled dates; gaps between them can be rest days.
nonisolated struct ShiftTypeDateCoverage: Equatable, Sendable {
    var firstDayKey: String
    var lastDayKey: String
    var dayCount: Int
}

nonisolated enum ShiftTypeScheduleOverview {
    /// Resolve the coming calendar year through the same rules as the countdown.
    static func coverage(plan: ExtendedSchedulePlan, fromDayKey: String) -> [UUID: ShiftTypeDateCoverage] {
        guard let start = ExtendedScheduleResolver.dayNumber(dayKey: fromDayKey),
              let parts = ExtendedScheduleResolver.parse(dayKey: fromDayKey) else { return [:] }
        let anniversaryDay = min(parts.day, ExtendedScheduleEditing.daysIn(year: parts.year + 1, month: parts.month))
        let end = CivilZone.dayNumber(year: parts.year + 1, month: parts.month, day: anniversaryDay)
        let resolver = ExtendedScheduleResolver(plan: plan)
        var coverage: [UUID: ShiftTypeDateCoverage] = [:]
        for number in start..<end {
            guard let id = resolver.day(dayNumber: number).shiftTypeID else { continue }
            let key = ExtendedScheduleEditing.dayKey(dayNumber: number)
            if var bounds = coverage[id] {
                bounds.lastDayKey = key
                bounds.dayCount += 1
                coverage[id] = bounds
            } else {
                coverage[id] = ShiftTypeDateCoverage(firstDayKey: key, lastDayKey: key, dayCount: 1)
            }
        }
        return coverage
    }
}
