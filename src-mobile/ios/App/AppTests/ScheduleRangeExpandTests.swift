import Foundation
import Testing
@testable import App

@MainActor
@Test("Batch expand returns rest-day planned hours and overnight start-day keys")
func expandScheduleRangeCoversRestAndOvernight() throws {
    let configuration = ScheduleHoursConfiguration(
        startTime: "22:00",
        endTime: "06:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
    let friday = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 28))!
    let sunday = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 30))!
    let days = try CountdownRules.shared.expandScheduleRange(
        configuration: configuration,
        from: friday,
        through: sunday
    )
    #expect(days.map(\.dayKey) == ["2026-08-28", "2026-08-29", "2026-08-30"])
    #expect(days[0].isWorkday == true)
    #expect(days[1].isWorkday == false)
    #expect(days[0].segments.isEmpty == false)
    #expect(days[1].segments.isEmpty == false)
}

@MainActor
@Test("Ten-year weekday expand is measured on the main thread")
func expandScheduleRangeTenYearMeasurement() throws {
    let configuration = ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "18:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: "12:00",
        breakDurationMinutes: 60
    )
    let from = Calendar.current.date(from: DateComponents(year: 2016, month: 1, day: 1))!
    let through = Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 31))!
    let started = ContinuousClock.now
    let days = try CountdownRules.shared.expandScheduleRange(
        configuration: configuration,
        from: from,
        through: through
    )
    let elapsed = started.duration(to: .now)
    let milliseconds = elapsed.components.seconds * 1_000
        + elapsed.components.attoseconds / 1_000_000_000_000_000
    print("P0A expandScheduleRange 10y: \(days.count) days in \(milliseconds)ms")
    #expect(days.count >= 3650)
    #expect(milliseconds < 30_000)

    let yearFrom = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    let yearThrough = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31))!
    let yearStarted = ContinuousClock.now
    let yearDays = try CountdownRules.shared.expandScheduleRange(
        configuration: configuration,
        from: yearFrom,
        through: yearThrough
    )
    let yearElapsed = yearStarted.duration(to: .now)
    let yearMilliseconds = yearElapsed.components.seconds * 1_000
        + yearElapsed.components.attoseconds / 1_000_000_000_000_000
    print("P0A expandScheduleRange 1y: \(yearDays.count) days in \(yearMilliseconds)ms")
    #expect(yearDays.count >= 365)
}

@MainActor
@Test("Live snapshot expands clock times in the locked time zone")
func snapshotHonorsLockedTimeZone() throws {
    let now = ISO8601DateFormatter().date(from: "2026-08-24T17:00:00Z")!
    let schedule = NativeWorkSchedule(
        mode: "classic",
        referenceWeekStartMs: nil,
        referenceWeekType: nil,
        singleWeekendWorkday: nil,
        rotationAnchorMs: nil,
        rotationWorkDays: nil,
        rotationRestDays: nil
    )
    func input(_ timeZone: String) -> NativeRulesInput {
        NativeRulesInput(
            startTime: "09:00",
            endTime: "17:00",
            nowMs: now.timeIntervalSince1970 * 1_000,
            workdays: [1, 2, 3, 4, 5],
            schedule: schedule,
            breakStartTime: nil,
            breakDurationMinutes: 0,
            overtimeEndAtMs: nil,
            salaryAmount: "",
            salaryType: "monthly",
            monthlyWorkingDays: 22,
            annualBonusMonths: 0,
            forcedWorkdayStartMs: nil,
            timeZoneIdentifier: timeZone
        )
    }
    let shanghai = try CountdownRules.shared.snapshot(input: input("Asia/Shanghai"))
    let losAngeles = try CountdownRules.shared.snapshot(input: input("America/Los_Angeles"))
    let shanghaiStart = ISO8601DateFormatter().date(from: "2026-08-25T01:00:00Z")!
    let losAngelesStart = ISO8601DateFormatter().date(from: "2026-08-24T16:00:00Z")!
    #expect(shanghai.startAtMs == shanghaiStart.timeIntervalSince1970 * 1_000)
    #expect(losAngeles.startAtMs == losAngelesStart.timeIntervalSince1970 * 1_000)
}
