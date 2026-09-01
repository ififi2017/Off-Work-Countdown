import Foundation
import Testing
@testable import App

private let hourMs = 3_600_000.0

@MainActor
@Test("Metrics use resolved work days and ignore empty rest days")
func recordsMetricsCountWorkdays() throws {
    let calendar = utcCalendar()
    let monday = try date(2026, 8, 24, calendar: calendar)
    let workSegments = [segment(on: monday, fromHour: 9, toHour: 17, calendar: calendar)]
    let work = resolution(
        on: monday,
        dayKey: "2026-08-24",
        isWorkday: true,
        segments: workSegments,
        baseIsWorkday: true,
        baseSegments: workSegments
    )
    let tuesday = try date(2026, 8, 25, calendar: calendar)
    let rest = resolution(on: tuesday, dayKey: "2026-08-25")
    let asOf = try date(2026, 8, 26, hour: 12, calendar: calendar)

    let metrics = RecordsMetrics.summarize(
        days: [work, rest],
        observations: [],
        sleepHours: 8,
        dailySalary: 100,
        salaryEnabled: true,
        asOf: asOf,
        calendar: calendar
    )
    #expect(metrics.workdayCount == 1)
    #expect(metrics.workDurationMs == Int64(8 * hourMs))
    #expect(metrics.longestStreak == 1)
    #expect(metrics.estimatedIncome == 100)
}

@MainActor
@Test("Income uses completed base schedule days, not overrides, today, or future days")
func recordsIncomeUsesCompletedBaseSchedule() throws {
    let calendar = utcCalendar()
    let scheduledSegments = { (day: Date) in
        [segment(on: day, fromHour: 9, toHour: 17, calendar: calendar)]
    }
    let monday = try date(2026, 8, 24, calendar: calendar)
    let tuesday = try date(2026, 8, 25, calendar: calendar)
    let wednesday = try date(2026, 8, 26, calendar: calendar)
    let thursday = try date(2026, 8, 27, calendar: calendar)
    let custom = [segment(on: tuesday, fromHour: 10, toHour: 19, calendar: calendar)]
    let days = [
        // A leave override has no resolved work hours, but its base scheduled
        // day remains a paid completed day.
        resolution(
            on: monday,
            dayKey: "2026-08-24",
            layer: .override,
            baseIsWorkday: true,
            baseSegments: scheduledSegments(monday)
        ),
        // A custom shift on a base rest day contributes work time, not income.
        resolution(
            on: tuesday,
            dayKey: "2026-08-25",
            layer: .override,
            isWorkday: true,
            segments: custom
        ),
        resolution(
            on: wednesday,
            dayKey: "2026-08-26",
            isWorkday: true,
            segments: scheduledSegments(wednesday),
            baseIsWorkday: true,
            baseSegments: scheduledSegments(wednesday)
        ),
        resolution(
            on: thursday,
            dayKey: "2026-08-27",
            isWorkday: true,
            segments: scheduledSegments(thursday),
            baseIsWorkday: true,
            baseSegments: scheduledSegments(thursday)
        ),
    ]

    let metrics = RecordsMetrics.summarize(
        days: days,
        observations: [],
        sleepHours: 8,
        dailySalary: 100,
        salaryEnabled: true,
        asOf: try date(2026, 8, 26, hour: 12, calendar: calendar),
        calendar: calendar
    )

    #expect(metrics.estimatedIncome == 100)
}

@MainActor
@Test("Overtime starts at the captured planned end, not declaration time")
func recordsOvertimeUsesPlannedEnd() throws {
    let calendar = utcCalendar()
    let day = try date(2026, 8, 24, calendar: calendar)
    let regular = [segment(on: day, fromHour: 9, toHour: 17, calendar: calendar)]
    let resolution = resolution(
        on: day,
        dayKey: "2026-08-24",
        isWorkday: true,
        segments: regular,
        baseIsWorkday: true,
        baseSegments: regular
    )
    let plannedEndAtMs = ms(try date(2026, 8, 24, hour: 17, calendar: calendar))
    let overtimeEndAtMs = ms(try date(2026, 8, 24, hour: 18, calendar: calendar))
    let payload = try JSONEncoder().encode(OvertimeDeclarationPayload(
        overtimeEndAtMs: overtimeEndAtMs,
        plannedEndAtMs: plannedEndAtMs
    ))
    let observation = WorkObservation(
        eventID: UUID(),
        shiftAnchorDate: day,
        occurredAt: try date(2026, 8, 24, hour: 16, calendar: calendar),
        kind: .overtimeDeclared,
        valueData: payload,
        scheduleSnapshotID: UUID(),
        timeZoneIdentifier: calendar.timeZone.identifier
    )

    let metrics = RecordsMetrics.summarize(
        days: [resolution],
        observations: [observation],
        sleepHours: 8,
        dailySalary: 0,
        salaryEnabled: false,
        asOf: try date(2026, 8, 25, calendar: calendar),
        calendar: calendar
    )

    #expect(metrics.declaredOvertimeMs == Int64(hourMs))
}

@MainActor
@Test("Legacy overtime falls back to base schedule and allocation never overlaps regular work")
func legacyOvertimeUsesBaseScheduleWithoutOverlap() throws {
    let calendar = utcCalendar()
    let day = try date(2026, 8, 24, calendar: calendar)
    let base = [segment(on: day, fromHour: 9, toHour: 17, calendar: calendar)]
    let corrected = [segment(on: day, fromHour: 9, toHour: 17.5, calendar: calendar)]
    let resolution = resolution(
        on: day,
        dayKey: "2026-08-24",
        layer: .override,
        isWorkday: true,
        segments: corrected,
        baseIsWorkday: true,
        baseSegments: base
    )
    let overtimeEndAtMs = ms(try date(2026, 8, 24, hour: 18, calendar: calendar))
    let legacyData = try JSONEncoder().encode(["overtimeEndAtMs": overtimeEndAtMs])
    let observation = WorkObservation(
        eventID: UUID(),
        shiftAnchorDate: day,
        occurredAt: try date(2026, 8, 24, hour: 16, calendar: calendar),
        kind: .overtimeDeclared,
        valueData: legacyData,
        scheduleSnapshotID: UUID(),
        timeZoneIdentifier: calendar.timeZone.identifier
    )

    let segment = try #require(RecordsMetrics.declaredOvertimeSegment(
        observation: observation,
        day: resolution,
        avoidingRegularWork: true
    ))
    #expect(segment.startAtMs == ms(try date(2026, 8, 24, hour: 17, minute: 30, calendar: calendar)))
    #expect(segment.endAtMs == overtimeEndAtMs)
}

@MainActor
@Test("Metrics denominators use 23 and 25 hour civil days across DST")
func recordsMetricsUsesCivilDayLengthAcrossDST() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))

    let spring = try date(2026, 3, 8, calendar: calendar)
    let fall = try date(2026, 11, 1, calendar: calendar)
    let springMetrics = metricsForDSTDay(spring, dayKey: "2026-03-08", calendar: calendar)
    let fallMetrics = metricsForDSTDay(fall, dayKey: "2026-11-01", calendar: calendar)

    #expect(abs(springMetrics.shareOfDay - 8.0 / 23.0) < 0.000_001)
    #expect(abs(springMetrics.shareOfAwake - 8.0 / 15.0) < 0.000_001)
    #expect(springMetrics.ownAwakeMs == Int64(7 * hourMs))
    #expect(abs(fallMetrics.shareOfDay - 8.0 / 25.0) < 0.000_001)
    #expect(abs(fallMetrics.shareOfAwake - 8.0 / 17.0) < 0.000_001)
    #expect(fallMetrics.ownAwakeMs == Int64(9 * hourMs))
}

@MainActor
@Test("A broken streak resets")
func recordsMetricsStreakResets() {
    let start = Date(timeIntervalSince1970: 1_787_529_600)
    let days = (0..<4).map { offset in
        let work = offset != 2
        return DayResolution(
            dayKey: "2026-08-2\(4 + offset)",
            shiftAnchorDate: start.addingTimeInterval(Double(offset) * 86_400),
            layer: .schedule,
            periodID: nil,
            snapshotID: nil,
            isScheduledWorkday: work,
            segments: work ? [NativeShiftSegment(startAtMs: 0, endAtMs: 1)] : []
        )
    }
    #expect(RecordsMetrics.longestStreak(in: days) == 2)
}

@MainActor
private func metricsForDSTDay(
    _ day: Date,
    dayKey: String,
    calendar: Calendar
) -> RecordsPeriodMetrics {
    let work = [segment(on: day, fromHour: 9, toHour: 17, calendar: calendar)]
    return RecordsMetrics.summarize(
        days: [resolution(on: day, dayKey: dayKey, isWorkday: true, segments: work)],
        observations: [],
        sleepHours: 8,
        dailySalary: 0,
        salaryEnabled: false,
        asOf: calendar.date(byAdding: .day, value: 1, to: day) ?? day,
        calendar: calendar
    )
}

@MainActor
private func resolution(
    on day: Date,
    dayKey: String,
    layer: DayResolutionLayer = .schedule,
    isWorkday: Bool = false,
    segments: [NativeShiftSegment] = [],
    baseIsWorkday: Bool = false,
    baseSegments: [NativeShiftSegment] = []
) -> DayResolution {
    DayResolution(
        dayKey: dayKey,
        shiftAnchorDate: day,
        layer: layer,
        periodID: nil,
        snapshotID: nil,
        isScheduledWorkday: isWorkday,
        segments: segments,
        baseScheduleIsWorkday: baseIsWorkday,
        baseScheduleSegments: baseSegments
    )
}

@MainActor
private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

@MainActor
private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0,
    calendar: Calendar
) throws -> Date {
    try #require(calendar.date(from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    )))
}

@MainActor
private func segment(
    on day: Date,
    fromHour: Double,
    toHour: Double,
    calendar: Calendar
) -> NativeShiftSegment {
    let startHour = Int(fromHour)
    let startMinute = Int((fromHour - Double(startHour)) * 60)
    let endHour = Int(toHour)
    let endMinute = Int((toHour - Double(endHour)) * 60)
    let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day) ?? day
    let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: day) ?? day
    return NativeShiftSegment(startAtMs: ms(start), endAtMs: ms(end))
}

private func ms(_ date: Date) -> Double {
    date.timeIntervalSince1970 * 1_000
}
