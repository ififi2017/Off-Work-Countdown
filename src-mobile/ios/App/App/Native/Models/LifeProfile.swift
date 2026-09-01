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

/// One life-view archive per store. The id is a constant so two offline
/// devices first-write the same row. Matches 002 §6 and 010 LifeProfile v2.
struct LifeProfile: Equatable, Sendable {
    static let schemaVersion = 2
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
        if averageSleepMinutes == nil, let averageSleepHours {
            averageSleepMinutes = Int((averageSleepHours * 60).rounded())
        }
        if sleepSource == nil, averageSleepMinutes != nil || averageSleepHours != nil {
            sleepSource = .manual
        }
    }
}
