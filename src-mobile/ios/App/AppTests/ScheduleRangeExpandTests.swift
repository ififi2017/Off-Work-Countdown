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
}
