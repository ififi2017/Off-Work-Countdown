import Foundation
import Testing
@testable import App

@Suite("Annual shift date ranges")
struct AnnualShiftDateRangeTests {
    private static let summer = ShiftType(
        id: UUID(), name: "Summer", kind: .work, startMinutes: 8 * 60, endMinutes: 16 * 60,
        breakEnabled: true, breakStartMinutes: 12 * 60, breakDurationMinutes: 30,
        colorHex: "#FF7A00", isArchived: false,
        annualDateRange: .init(startMonth: 5, startDay: 1, endMonth: 9, endDay: 30)
    )
    private static let winter = ShiftType(
        id: UUID(), name: "Winter", kind: .work, startMinutes: 9 * 60, endMinutes: 17 * 60,
        breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
        colorHex: "#3366FF", isArchived: false,
        annualDateRange: .init(startMonth: 10, startDay: 1, endMonth: 4, endDay: 30)
    )
    private static let rest = ShiftType(
        id: UUID(), name: "Rest", kind: .rest, startMinutes: 0, endMinutes: 0,
        breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
        colorHex: "#777777", isArchived: false
    )
    private static var content: ExtendedScheduleContent {
        .init(shiftTypes: [summer, winter, rest],
              rule: .init(preset: .weekly, anchorDayKey: "2026-04-27",
                          days: [winter.id, winter.id, winter.id, winter.id, winter.id, rest.id, rest.id]))
    }
    private static func plan(
        content: ExtendedScheduleContent = Self.content,
        handSet: [String: UUID] = [:], frozen: [String: ShiftType] = [:],
        holidays: [Int: Bool]? = nil
    ) -> ExtendedSchedulePlan {
        .init(shiftTypes: content.shiftTypes, rule: content.rule, handSetDays: handSet,
              holidayRegionIdentifier: holidays == nil ? nil : "CN", holidayOverrides: holidays,
              frozenShiftTypes: frozen)
    }
    private static func day(_ key: String, in plan: ExtendedSchedulePlan = Self.plan()) throws -> ExtendedScheduleDay {
        let number = try #require(ExtendedScheduleResolver.dayNumber(dayKey: key))
        return ExtendedScheduleResolver(plan: plan).day(dayNumber: number)
    }
    private static func timestamp(_ instant: String) throws -> Int64 {
        let date = try #require(ISO8601DateFormatter().date(from: instant))
        return Int64(date.timeIntervalSince1970 * 1_000)
    }

    @Test("May and October boundaries repeat across future years",
          arguments: [2026, 2027, 2036])
    func annualBoundaries(year: Int) throws {
        // Work every day here so a weekend cannot hide a date boundary.
        var content = Self.content
        content.rule?.days = [Self.winter.id]
        let plan = Self.plan(content: content)
        for (suffix, type) in [("04-30", Self.winter), ("05-01", Self.summer),
                               ("09-30", Self.summer), ("10-01", Self.winter),
                               ("12-31", Self.winter), ("01-01", Self.winter)] {
            let resolved = try Self.day("\(year)-\(suffix)", in: plan)
            #expect(resolved.shiftTypeID == type.id)
            #expect(resolved.source == .annualRange)
            #expect(resolved.hours?.startTime == ExtendedScheduleResolver.timeString(type.startMinutes))
            #expect(resolved.hours?.breakDurationMinutes == (type.breakEnabled ? type.breakDurationMinutes : 0))
        }
    }

    @Test("Work/rest pattern and unassigned dates remain intact")
    func preservesDays() throws {
        let saturday = try Self.day("2026-05-02")
        #expect(saturday.isWorkday == false)
        #expect(saturday.shiftTypeID == Self.rest.id)
        #expect(saturday.source == .rule)
        let empty = Self.plan(content: .init(shiftTypes: [Self.summer, Self.winter], rule: nil))
        #expect(try Self.day("2026-05-01", in: empty) == .unassigned)
    }

    @Test("Manual and frozen assignments outrank annual ranges and holidays")
    func explicitAssignmentsWin() throws {
        var frozen = Self.winter
        frozen.startMinutes = 11 * 60
        let plan = Self.plan(handSet: ["2026-05-01": Self.winter.id, "2026-05-04": Self.rest.id,
                                      "2026-05-05": frozen.id],
                             frozen: ["2026-05-05": frozen],
                             holidays: [20260501: false, 20260504: true, 20260505: false])
        let manual = try Self.day("2026-05-01", in: plan)
        #expect(manual.shiftTypeID == Self.winter.id)
        #expect(manual.hours?.startTime == "09:00")
        #expect(manual.source == .handSet)
        #expect(try Self.day("2026-05-04", in: plan).isWorkday == false)
        let historical = try Self.day("2026-05-05", in: plan)
        #expect(historical.hours?.startTime == "11:00")
        #expect(historical.source == .handSet)
    }

    @Test("Holiday rest remains rest and makeup days receive seasonal hours")
    func seasonalMakeupDays() throws {
        let plan = Self.plan(holidays: [20260501: false, 20260502: true, 20261003: true])
        let rest = try Self.day("2026-05-01", in: plan)
        #expect(rest.isWorkday == false)
        #expect(rest.source == .holiday)
        let summer = try Self.day("2026-05-02", in: plan)
        #expect(summer.shiftTypeID == Self.summer.id)
        #expect(summer.hours?.startTime == "08:00")
        #expect(summer.source == .holiday)
        let winter = try Self.day("2026-10-03", in: plan)
        #expect(winter.shiftTypeID == Self.winter.id)
        #expect(winter.hours?.startTime == "09:00")
        #expect(winter.source == .holiday)
    }

    @Test("Only active work ranges participate in overlap checks")
    func overlappingRanges() throws {
        let zone = try #require(TimeZone(identifier: "UTC"))
        #expect(Self.content.hasOverlappingAnnualDateRanges == false)
        #expect(Self.content.isValid(in: zone))
        var overlapping = Self.content
        overlapping.shiftTypes[0].annualDateRange?.endMonth = 10
        overlapping.shiftTypes[0].annualDateRange?.endDay = 1
        #expect(overlapping.hasOverlappingAnnualDateRanges)
        #expect(overlapping.isValid(in: zone) == false)
        overlapping.shiftTypes[0].isArchived = true
        #expect(overlapping.hasOverlappingAnnualDateRanges == false)
        #expect(overlapping.isValid(in: zone))
        #expect(try Self.day("2026-05-01", in: Self.plan(content: overlapping)).source == .rule)
        var rest = Self.rest
        rest.annualDateRange = Self.summer.annualDateRange
        #expect(rest.isValid == false)
    }

    @Test("Month/day validation accepts leap dates and rejects impossible dates")
    func leapDates() throws {
        let leap = AnnualShiftDateRange(startMonth: 2, startDay: 29, endMonth: 2, endDay: 29)
        #expect(leap.isValid)
        #expect(leap.contains(month: 2, day: 29))
        #expect(leap.contains(month: 2, day: 28) == false)
        #expect(leap.contains(month: 3, day: 1) == false)
        #expect(AnnualShiftDateRange(startMonth: 4, startDay: 31, endMonth: 5, endDay: 1).isValid == false)
        #expect(AnnualShiftDateRange(startMonth: 0, startDay: 1, endMonth: 13, endDay: 1).isValid == false)
        #expect(Self.winter.annualDateRange?.contains(month: 2, day: 30) == false)
        var type = Self.summer
        type.annualDateRange = leap
        var content = Self.content
        content.shiftTypes = [type, Self.rest]
        content.rule?.days = [type.id]
        let plan = Self.plan(content: content)
        #expect(try Self.day("2028-02-29", in: plan).source == .annualRange)
        #expect(try Self.day("2027-02-28", in: plan).source == .rule)
        #expect(try Self.day("2027-03-01", in: plan).source == .rule)
    }

    @Test("Wrapped and nested ranges share inclusive overlap semantics")
    func overlapBoundaries() throws {
        let winter = try #require(Self.winter.annualDateRange)
        let summer = try #require(Self.summer.annualDateRange)
        #expect(winter.overlaps(summer) == false)
        #expect(winter.overlaps(.init(startMonth: 12, startDay: 1, endMonth: 1, endDay: 31)))
        #expect(winter.overlaps(.init(startMonth: 4, startDay: 30, endMonth: 5, endDay: 1)))
        #expect(winter.overlaps(.init(startMonth: 1, startDay: 1, endMonth: 12, endDay: 31)))
        #expect(summer.overlaps(.init(startMonth: 6, startDay: 1, endMonth: 6, endDay: 1)))
    }

    @Test("Plans without annual ranges keep their original resolution")
    func legacyTypes() throws {
        let bytes = try JSONEncoder().encode(Self.winter)
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object.removeValue(forKey: "annualDateRange")
        let legacy = try JSONDecoder().decode(ShiftType.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.annualDateRange == nil)
        let plan = Self.plan(content: .init(shiftTypes: [legacy],
            rule: .init(preset: .rotation, anchorDayKey: "2026-01-01", days: [legacy.id])))
        let day = try Self.day("2026-05-01", in: plan)
        #expect(day.hours?.startTime == "09:00")
        #expect(day.source == .rule)
    }

    @Test("Backup and Records snapshot content retain annual ranges")
    func persistentContent() throws {
        let schedule = ExtendedSchedule(isEnabled: true, shiftTypes: Self.content.shiftTypes,
            rule: Self.content.rule, timeZoneIdentifier: "UTC", editedAt: Date(timeIntervalSince1970: 0),
            editCount: 1, editTieBreaker: UUID())
        let dto = try JSONDecoder().decode(ExtendedScheduleDTO.self,
                                          from: JSONEncoder().encode(ExtendedScheduleDTO(schedule)))
        #expect(dto.value() == schedule)
        let hours = ScheduleHoursConfiguration(startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: NativeWorkSchedule(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: nil, breakDurationMinutes: 0, extendedContent: Self.content)
        let snapshot = ScheduleSnapshot(id: UUID(), periodID: UUID(), effectiveFrom: .now,
            configurationData: try JSONEncoder().encode(hours), fingerprint: "annual", editedAt: .now,
            editCount: 1, editTieBreaker: UUID())
        let decoded = try JSONDecoder().decode(ScheduleHoursConfiguration.self, from: snapshot.configurationData)
        #expect(decoded.extendedContent == Self.content)
    }

    @Test("Serialized Watch configuration switches hours offline in later years")
    func offlineWatch() async throws {
        let configuration = ScheduleRuleInput(startTime: "09:00", endTime: "17:00", nowMs: 0,
            workdays: [1, 2, 3, 4, 5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                            singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: nil, breakDurationMinutes: 0, overtimeEndAtMs: nil,
            forcedWorkdayStartMs: nil, timeZoneIdentifier: "UTC", extendedSchedule: Self.plan())
        let watch = WatchScheduleV2(configuration: configuration, automaticallyRuns: true, isConfigured: true,
            currentShift: nil, currentUntilMs: 0,
            presentation: .init(localeIdentifier: "en", timeZoneIdentifier: "UTC", workingLabel: "Working",
                                lunchLabel: "Break", restingLabel: "Rest", overtimeLabel: "Overtime", finishedLabel: "Finished"))
        func package(schema: Int, schedule: WatchScheduleV2, revision: UInt64 = 1) -> WatchSnapshotPackageV1 {
            .init(schemaVersion: schema, sourceGeneration: "phone", revision: revision,
                  generatedAtMs: 1, expiresAtMs: WatchSnapshotContract.maximumJSONTimestamp,
                  access: .init(schemaVersion: 1, revision: 0, verifiedAtMs: 0, status: .free, validUntilMs: nil),
                  content: nil, schedule: schedule)
        }
        #expect(package(schema: 4, schedule: watch).isValid == false)
        #expect(throws: WatchSnapshotDecodeError.invalidPackage) {
            try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(package(schema: 4, schedule: watch)))
        }
        let bytes = try JSONEncoder().encode(package(schema: 5, schedule: watch))
        let decodedPackage = try WatchSnapshotDecoderV1.decode(bytes)
        let decoded = try #require(decodedPackage.schedule)
        #expect(decoded == watch)
        for (day, end) in [("2037-05-01", "16:00:00Z"), ("2037-10-01", "17:00:00Z")] {
            let now = try Self.timestamp(day + "T10:00:00Z")
            let end = try Self.timestamp(day + "T" + end)
            let shift = try #require(decoded.content(at: now).shift)
            #expect(shift.plannedEndAtMs == end)
        }

        var classic = configuration
        classic.extendedSchedule = nil
        let legacy = WatchScheduleV2(configuration: classic, automaticallyRuns: true, isConfigured: true,
            currentShift: nil, currentUntilMs: 0, presentation: watch.presentation)
        for schema in 2...4 {
            let value = package(schema: schema, schedule: legacy)
            #expect(try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(value)) == value)
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "watch.json")
        let cache = await WatchSnapshotCache.open(fileURL: url)
        let hello = await cache.makePairingHello()
        let reply = WatchPairingReplyV1(schemaVersion: 1, pairingSession: hello.pairingSession, nonce: hello.nonce,
            baseline: .init(schemaVersion: 1, pairingSession: hello.pairingSession,
                            sourceGeneration: "phone", replacesGeneration: nil), packageData: bytes)
        let replyBytes = try JSONEncoder().encode(reply)
        #expect(await cache.receivePairingReply(replyBytes) == .accepted)
        let reopened = await WatchSnapshotCache.open(fileURL: url)
        #expect(await reopened.currentPackage() == decodedPackage)
        let downgrade = try JSONEncoder().encode(package(schema: 4, schedule: legacy, revision: 2))
        #expect(await reopened.receiveApplicationContext(downgrade) == .rejected(.rejectInvalidPackage))
    }
}
