import Foundation

enum LifeWeekKind: String, Sendable {
    case childhood
    case study
    case workEstimated
    case workProjected
    case workOverride
    case retirement
    case none
}

struct LifeWeekCell: Equatable, Sendable, Identifiable {
    var id: String { "\(year)-\(weekIndex)" }
    var year: Int
    var weekIndex: Int
    var start: Date
    var kind: LifeWeekKind
    var outsidePeriodTimeZone: Bool
}

struct LifeViewModel: Equatable, Sendable {
    var cells: [LifeWeekCell]
    var workShare: Double
    var ownAwakeShare: Double
}

enum LifeViewCalculator {
    static func build(
        profile: LifeProfile,
        periods _: [CareerPeriod],
        overrideDays: Set<String>,
        outsideZoneDays: Set<String>,
        now: Date,
        calendar: Calendar
    ) -> LifeViewModel {
        guard let birthYear = profile.birthYear,
              let retirementAge = profile.retirementAge
        else {
            return LifeViewModel(cells: [], workShare: 0, ownAwakeShare: 0)
        }
        let startYear = birthYear
        let endYear = birthYear + retirementAge
        let workStart = profile.workStartedOn ?? calendar.date(
            from: DateComponents(year: birthYear + 22, month: 1, day: 1)
        ) ?? now
        var cursor = calendar.date(from: DateComponents(year: startYear, month: 1, day: 1)) ?? now
        let end = calendar.date(from: DateComponents(year: endYear + 1, month: 1, day: 1)) ?? now
        var cells: [LifeWeekCell] = []
        var weekIndex = 0
        while cursor < end {
            let year = calendar.component(.year, from: cursor)
            let kind: LifeWeekKind
            if year >= endYear {
                kind = .retirement
            } else if cursor < workStart {
                kind = year < birthYear + 6 ? .childhood : .study
            } else if cursor > now {
                kind = .workProjected
            } else {
                let key = RecordJSON.dayKey(cursor, calendar: calendar)
                kind = overrideDays.contains(key) ? .workOverride : .workEstimated
            }
            let dayKey = RecordJSON.dayKey(cursor, calendar: calendar)
            cells.append(
                LifeWeekCell(
                    year: year,
                    weekIndex: weekIndex,
                    start: cursor,
                    kind: kind,
                    outsidePeriodTimeZone: outsideZoneDays.contains(dayKey)
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
            weekIndex += 1
        }
        let workCells = cells.filter {
            $0.kind == .workEstimated || $0.kind == .workProjected || $0.kind == .workOverride
        }
        let sleep = profile.averageSleepHours ?? 8
        let workShare = cells.isEmpty ? 0 : Double(workCells.count) / Double(cells.count)
        let ownAwakeShare = max(0, 1 - workShare) * max(0, (24 - sleep) / 24)
        return LifeViewModel(cells: cells, workShare: workShare, ownAwakeShare: ownAwakeShare)
    }
}
