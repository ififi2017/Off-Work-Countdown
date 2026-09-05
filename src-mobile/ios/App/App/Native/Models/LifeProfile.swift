import Foundation

enum CivilDatePrecision: String, Codable, Sendable {
    case year
    case day
}

struct PartialCivilDate: Codable, Equatable, Sendable {
    var year: Int
    var month: Int?
    var day: Int?
    var precision: CivilDatePrecision

    static func yearOnly(_ year: Int) -> PartialCivilDate {
        PartialCivilDate(year: year, month: nil, day: nil, precision: .year)
    }

    static func exact(year: Int, month: Int, day: Int) -> PartialCivilDate? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == year, components.month == month, components.day == day else { return nil }
        return PartialCivilDate(year: year, month: month, day: day, precision: .day)
    }

    /// Stable calculation anchor. Year-only dates use mid-year, never 1 January.
    func calculationAnchor(in calendar: Calendar) -> Date? {
        switch precision {
        case .year:
            return calendar.date(from: DateComponents(year: year, month: 7, day: 1))
        case .day:
            guard let month, let day else { return nil }
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
    }
}

enum SleepSource: String, Codable, Sendable {
    case manual
    case healthSuggested
}

enum LifeWorkHistoryMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case rough
    case detailed

    var id: String { rawValue }
}

enum LifeSalaryCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case monthly
    case yearly

    var id: String { rawValue }
}

struct LifeSalary: Codable, Equatable, Sendable {
    var amount: Double
    var cadence: LifeSalaryCadence

    var isValid: Bool { amount.isFinite && amount > 0 }
}

struct LifeEmploymentPeriod: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var startsOn: PartialCivilDate
    var endsOn: PartialCivilDate?
    var salary: LifeSalary

    func isValid(in calendar: Calendar) -> Bool {
        guard startsOn.precision == .day,
              let start = startsOn.calculationAnchor(in: calendar),
              salary.isValid
        else { return false }
        guard let endsOn else { return true }
        return endsOn.precision == .day
            && endsOn.calculationAnchor(in: calendar).map { $0 > start } == true
    }
}

/// One life-view archive per store. The id is a constant so two offline
/// devices first-write the same row. Matches 002 §6 and 010 LifeProfile v2.
struct LifeProfile: Equatable, Sendable {
    static let schemaVersion = 3
    static let profileID = UUID(uuidString: "00000000-0000-0000-0000-00574F524B01")!

    var profileID: UUID = LifeProfile.profileID
    var birthYear: Int?
    var workStartedOn: Date?
    var retirementAge: Int?
    var averageSleepHours: Double?
    var hidesExactAges: Bool = false
    var bornOn: PartialCivilDate?
    var schoolStartedOn: PartialCivilDate?
    var workStartedPartial: PartialCivilDate?
    var retirementOn: PartialCivilDate?
    var averageSleepMinutes: Int?
    var sleepSource: SleepSource?
    var sleepSourceUpdatedAt: Date?
    var workHistoryMode: LifeWorkHistoryMode = .rough
    var roughCurrentSalary: LifeSalary?
    var employmentPeriods: [LifeEmploymentPeriod] = []
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID

    mutating func migrateLegacyFields(calendar: Calendar) {
        if bornOn == nil, let birthYear {
            bornOn = .yearOnly(birthYear)
        }
        if workStartedPartial == nil, let workStartedOn {
            let parts = calendar.dateComponents([.year, .month, .day], from: workStartedOn)
            if let year = parts.year, let month = parts.month, let day = parts.day {
                workStartedPartial = .exact(year: year, month: month, day: day)
            }
        }
        if retirementOn == nil, let birthYear, let retirementAge {
            retirementOn = .yearOnly(birthYear + retirementAge)
        }
        if retirementOn == nil, let birthYear = bornOn?.year ?? birthYear {
            retirementAge = 60
            retirementOn = .yearOnly(birthYear + 60)
        }
        if averageSleepMinutes == nil, let averageSleepHours {
            averageSleepMinutes = Int((averageSleepHours * 60).rounded())
        }
        if sleepSource == nil, averageSleepMinutes != nil || averageSleepHours != nil {
            sleepSource = .manual
        }
        if workHistoryMode == .detailed,
           let first = employmentPeriods.min(by: { lhs, rhs in
               if lhs.startsOn.year != rhs.startsOn.year {
                   return lhs.startsOn.year < rhs.startsOn.year
               }
               if lhs.startsOn.month != rhs.startsOn.month {
                   return (lhs.startsOn.month ?? 0) < (rhs.startsOn.month ?? 0)
               }
               return (lhs.startsOn.day ?? 0) < (rhs.startsOn.day ?? 0)
           }) {
            workStartedPartial = first.startsOn
            workStartedOn = first.startsOn.calculationAnchor(in: calendar)
        }
    }

    var suggestedSchoolYear: Int? { (bornOn?.year ?? birthYear).map { $0 + 6 } }
    var suggestedWorkYear: Int? { (bornOn?.year ?? birthYear).map { $0 + 22 } }
}
