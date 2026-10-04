import Foundation
import Testing
@testable import App

@Suite("Holiday templates")
struct HolidayTemplateTests {
    private static let work = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private static let rest = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private static let alternate = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!

    private static let workType = ShiftType(
        id: work, name: "Day", kind: .work,
        startMinutes: 9 * 60, endMinutes: 17 * 60,
        breakEnabled: false, breakStartMinutes: 12 * 60, breakDurationMinutes: 0,
        colorHex: "#FF7A00", isArchived: false
    )
    private static let restType = ShiftType(
        id: rest, name: "Rest", kind: .rest,
        startMinutes: 9 * 60, endMinutes: 17 * 60,
        breakEnabled: false, breakStartMinutes: 12 * 60, breakDurationMinutes: 0,
        colorHex: "#777777", isArchived: false
    )
    private static let alternateType = ShiftType(
        id: alternate, name: "Night", kind: .work,
        startMinutes: 22 * 60, endMinutes: 6 * 60,
        breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
        colorHex: "#3366FF", isArchived: false
    )

    @Test("Bundled calendars use published coverage and names")
    func bundledCalendar() throws {
        let calendar = HolidayCalendar.shared
        #expect(calendar.covers(year: 2026, regionIdentifier: "CN"))
        #expect(!calendar.covers(year: 2027, regionIdentifier: "CN"))
        #expect(calendar.day(dayKey: "2027-01-01", regionIdentifier: "CN") == nil)

        let cnRest = try #require(calendar.day(dayKey: "2026-01-01", regionIdentifier: "CN"))
        let cnMakeup = try #require(calendar.day(dayKey: "2026-01-04", regionIdentifier: "CN"))
        #expect(!cnRest.isWorkday)
        #expect(cnMakeup.isWorkday)

        let japan = try #require(calendar.day(dayKey: "2026-02-11", regionIdentifier: "JP"))
        #expect(!japan.isWorkday)
        #expect(japan.name(language: "ja") == "建国記念の日")
        #expect(calendar.defaultRegionIdentifier(locale: Locale(identifier: "en_US")) == "US")
    }

    @Test("Taiwan's Traditional Chinese name follows the app language",
          arguments: ["zh-TW", "zh_TW", "zh-HK", "zh-Hant", "zh-Hant-TW", "zh-Hant-CN"])
    func traditionalChineseRegionName(language: String) {
        #expect(HolidayCalendar.shared.regionName("TW", locale: Locale(identifier: language)) == "台灣")
    }

    @Test("Other region names retain Foundation localization",
          arguments: ["zh-CN", "en", "ja", "ko", "de", "es", "fr", "it", "pt", "ru",
                      "ar", "hi-IN", "mr-IN", "id", "th", "tr", "vi"])
    func otherRegionNames(language: String) {
        let locale = Locale(identifier: language)
        for region in ["TW", "CN", "HK", "JP", "US"] {
            #expect(HolidayCalendar.shared.regionName(region, locale: locale)
                    == (locale.localizedString(forRegionCode: region) ?? region))
        }
    }

    @Test("Holiday names fall back to English")
    func englishNameFallback() throws {
        let json = #"{"schemaVersion":1,"datasetVersion":"test","names":[{"en":"Founders Day"}],"regions":{"US":{"coveredFromYear":2026,"coveredThroughYear":2026,"days":[[20260102,0,0]]}}}"#
        let calendar = try HolidayCalendar(data: Data(json.utf8))
        let day = try #require(calendar.day(dayKey: "2026-01-02", regionIdentifier: "US"))
        #expect(day.name(language: "fr") == "Founders Day")
    }

    @Test("Disabled and legacy plans retain the old resolution path")
    func disabledAndLegacyPlans() throws {
        let rule = ShiftCycleRule(preset: .rotation, anchorDayKey: "2026-01-01", days: [Self.work])
        let legacy = ExtendedSchedulePlan(
            shiftTypes: [Self.workType, Self.restType], rule: rule, handSetDays: [:]
        )
        let disabled = ExtendedSchedulePlan(
            shiftTypes: [Self.workType, Self.restType], rule: rule, handSetDays: [:],
            holidayRegionIdentifier: ""
        )
        let newYear = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-01-01"))
        #expect(ExtendedScheduleResolver(plan: legacy).day(dayNumber: newYear).source == .rule)
        #expect(ExtendedScheduleResolver(plan: disabled).day(dayNumber: newYear).source == .rule)

        let oldJSON = #"{"shiftTypes":[],"rule":null}"#
        let oldContent = try JSONDecoder().decode(ExtendedScheduleContent.self, from: Data(oldJSON.utf8))
        #expect(oldContent.holidayRegionIdentifier == nil)
    }

    @Test("Explicit and frozen assignments outrank holidays")
    func explicitAssignmentsWin() throws {
        let day = "2026-01-01"
        let number = try #require(ExtendedScheduleResolver.dayNumber(dayKey: day))
        let handSet = ExtendedSchedulePlan(
            shiftTypes: [Self.workType, Self.restType, Self.alternateType], rule: nil,
            handSetDays: [day: Self.alternate], holidayRegionIdentifier: "CN"
        )
        let handResult = ExtendedScheduleResolver(plan: handSet).day(dayNumber: number)
        #expect(handResult.source == .handSet)
        #expect(handResult.shiftTypeID == Self.alternate)

        var frozenType = Self.alternateType
        frozenType.name = "Frozen night"
        let frozen = ExtendedSchedulePlan(
            shiftTypes: [Self.workType, Self.restType], rule: nil,
            handSetDays: [day: Self.work], holidayRegionIdentifier: "CN",
            frozenShiftTypes: [day: frozenType]
        )
        let frozenResult = ExtendedScheduleResolver(plan: frozen).day(dayNumber: number)
        #expect(frozenResult.source == .handSet)
        #expect(frozenResult.hours?.startTime == "22:00")
    }

    @Test("Holidays override cycles and makeup days select the first active work type")
    func holidaysOverrideCycles() throws {
        var archived = Self.alternateType
        archived.isArchived = true
        let plan = ExtendedSchedulePlan(
            shiftTypes: [archived, Self.workType, Self.restType],
            rule: ShiftCycleRule(preset: .rotation, anchorDayKey: "2026-01-01", days: [Self.work, Self.rest, Self.rest, Self.rest]),
            handSetDays: [:], holidayRegionIdentifier: "CN"
        )
        let resolver = ExtendedScheduleResolver(plan: plan)
        let restHoliday = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-01-01"))
        let makeupDay = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-01-04"))
        let restResult = resolver.day(dayNumber: restHoliday)
        let makeupResult = resolver.day(dayNumber: makeupDay)
        #expect(restResult.source == .holiday)
        #expect(!restResult.isWorkday)
        #expect(makeupResult.source == .holiday)
        #expect(makeupResult.shiftTypeID == Self.work)
        #expect(makeupResult.isWorkday)
    }

    @Test("Overnight shifts keep their hours across the year boundary")
    func overnightYearBoundary() throws {
        let plan = ExtendedSchedulePlan(
            shiftTypes: [Self.alternateType, Self.restType],
            rule: ShiftCycleRule(preset: .rotation, anchorDayKey: "2025-12-31", days: [Self.alternate]),
            handSetDays: [:], holidayRegionIdentifier: "JP"
        )
        let resolver = ExtendedScheduleResolver(plan: plan)
        let december = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2025-12-31"))
        let january = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-01-01"))
        #expect(resolver.day(dayNumber: december).hours?.startTime == "22:00")
        #expect(resolver.day(dayNumber: december).hours?.endTime == "06:00")
        #expect(resolver.day(dayNumber: january).source == .holiday)
        #expect(!resolver.day(dayNumber: january).isWorkday)
    }

    @Test("Backup DTOs round-trip regions and decode older payloads")
    func backupRoundTrip() throws {
        let schedule = ExtendedSchedule(
            isEnabled: true, shiftTypes: [Self.workType, Self.restType], rule: nil,
            holidayRegionIdentifier: "CN", timeZoneIdentifier: "Asia/Shanghai",
            editedAt: Date(timeIntervalSince1970: 1_700_000_000), editCount: 3,
            editTieBreaker: UUID(uuidString: "00000000-0000-0000-0000-000000000199")!
        )
        let encoded = try JSONEncoder().encode(ExtendedScheduleDTO(schedule))
        let decoded = try JSONDecoder().decode(ExtendedScheduleDTO.self, from: encoded)
        #expect(decoded.value()?.holidayRegionIdentifier == "CN")

        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "holidayRegionIdentifier")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let legacy = try JSONDecoder().decode(ExtendedScheduleDTO.self, from: legacyData)
        #expect(legacy.value()?.holidayRegionIdentifier == nil)
    }

    @Test("Snapshot configuration retains the holiday region")
    func snapshotContentRoundTrip() throws {
        let hours = ScheduleHoursConfiguration(
            startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: NativeWorkSchedule(
                mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                singleWeekendWorkday: nil, rotationAnchorMs: nil,
                rotationWorkDays: nil, rotationRestDays: nil
            ),
            breakStartTime: nil, breakDurationMinutes: 0,
            extendedContent: ExtendedScheduleContent(
                shiftTypes: [Self.workType, Self.restType], rule: nil,
                holidayRegionIdentifier: "JP"
            )
        )
        let configurationData = try JSONEncoder().encode(hours)
        let snapshot = ScheduleSnapshot(
            id: UUID(), periodID: UUID(), effectiveFrom: .now,
            configurationData: configurationData, fingerprint: "test",
            editedAt: .now, editCount: 1, editTieBreaker: UUID()
        )
        let decoded = try JSONDecoder().decode(ScheduleHoursConfiguration.self, from: snapshot.configurationData)
        #expect(decoded.extendedContent?.holidayRegionIdentifier == "JP")
    }
}
