import Foundation

/// Versioned, bundled national calendars. No runtime network or date prediction.
nonisolated struct HolidayCalendar: Sendable {
    struct Day: Sendable {
        let isWorkday: Bool
        let names: [String: String]

        func name(language: String) -> String {
            let normalized = language.replacingOccurrences(of: "_", with: "-")
            return names[normalized] ?? names[String(normalized.prefix(2))]
                ?? names["en"] ?? names.sorted(by: { $0.key < $1.key }).first?.value ?? ""
        }
    }

    private struct Payload: Decodable {
        let schemaVersion: Int
        let datasetVersion: String
        let names: [[String: String]]
        let regions: [String: RegionPayload]
    }

    private struct RegionPayload: Decodable {
        let coveredFromYear: Int
        let coveredThroughYear: Int
        let days: [[Int]]
    }

    private struct Region: Sendable {
        let years: ClosedRange<Int>
        let days: [Int: Day]
    }

    enum LoadError: Error { case invalidDataset }

    static let shared: HolidayCalendar = {
        guard let url = Bundle.main.url(forResource: "HolidayTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let calendar = try? HolidayCalendar(data: data)
        else { return HolidayCalendar() }
        return calendar
    }()

    let datasetVersion: String
    private let regions: [String: Region]
    var regionIdentifiers: [String] { regions.keys.sorted() }

    private init() {
        datasetVersion = ""
        regions = [:]
    }

    init(data: Data) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.schemaVersion == 1, !payload.datasetVersion.isEmpty else {
            throw LoadError.invalidDataset
        }
        var parsed: [String: Region] = [:]
        for (identifier, source) in payload.regions {
            guard Self.isValidRegionIdentifier(identifier), !identifier.isEmpty,
                  source.coveredFromYear <= source.coveredThroughYear else { throw LoadError.invalidDataset }
            var days: [Int: Day] = [:]
            for row in source.days {
                guard row.count == 3, (0...1).contains(row[1]),
                      payload.names.indices.contains(row[2]), days[row[0]] == nil,
                      Self.isValidDateCode(row[0]),
                      (source.coveredFromYear...source.coveredThroughYear).contains(row[0] / 10_000)
                else { throw LoadError.invalidDataset }
                days[row[0]] = Day(isWorkday: row[1] == 1, names: payload.names[row[2]])
            }
            parsed[identifier] = Region(years: source.coveredFromYear...source.coveredThroughYear, days: days)
        }
        datasetVersion = payload.datasetVersion
        regions = parsed
    }

    static func isValidRegionIdentifier(_ identifier: String?) -> Bool {
        guard let identifier, !identifier.isEmpty else { return true }
        return identifier.utf8.count == 2 && identifier.utf8.allSatisfy { (65...90).contains($0) }
    }

    static func isValidDateCode(_ value: Int) -> Bool {
        let year = value / 10_000
        let month = value / 100 % 100
        let day = value % 100
        guard (1...9_999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return false }
        let civil = CivilZone.civilDate(dayNumber: CivilZone.dayNumber(year: year, month: month, day: day))
        return civil.year == year && civil.month == month && civil.day == day
    }

    func defaultRegionIdentifier(locale: Locale = .current) -> String? {
        guard let code = locale.region?.identifier, regions[code] != nil else { return nil }
        return code
    }

    func regionName(_ identifier: String, locale: Locale) -> String {
        // Foundation's region aliases can vary with device configuration even
        // for an explicit locale. Keep the Traditional Chinese display name
        // tied to the app language, including zh-TW and zh-HK overrides.
        if identifier == "TW", locale.language.languageCode?.identifier == "zh",
           locale.language.script?.identifier == "Hant" {
            return "台灣"
        }
        return locale.localizedString(forRegionCode: identifier) ?? identifier
    }

    func coveredThroughYear(regionIdentifier: String) -> Int? {
        regions[regionIdentifier]?.years.upperBound
    }

    /// Transport effects, not names, so paired devices use the same source
    /// revision even when their installed bundles differ.
    func workdayOverrides(regionIdentifier: String) -> [Int: Bool] {
        regions[regionIdentifier]?.days.mapValues(\.isWorkday) ?? [:]
    }

    func covers(year: Int, regionIdentifier: String) -> Bool {
        regions[regionIdentifier]?.years.contains(year) == true
    }

    func day(dayKey: String, regionIdentifier: String) -> Day? {
        guard let parts = ExtendedScheduleResolver.parse(dayKey: dayKey) else { return nil }
        return regions[regionIdentifier]?.days[parts.year * 10_000 + parts.month * 100 + parts.day]
    }

    func day(dayNumber: Int, regionIdentifier: String) -> Day? {
        let civil = CivilZone.civilDate(dayNumber: dayNumber)
        return regions[regionIdentifier]?.days[civil.year * 10_000 + civil.month * 100 + civil.day]
    }
}
