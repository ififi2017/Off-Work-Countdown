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

    let metrics = RecordsMetrics.summarize(
        days: [work, rest],
        observations: [],
        sleepHours: 8,
        calendar: calendar
    )
    #expect(metrics.workdayCount == 1)
    #expect(metrics.workDurationMs == Int64(8 * hourMs))
    #expect(metrics.longestStreak == 1)
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
@Test("Expanded year rows sum only recorded days and keep projections separate")
func yearMonthBarsSeparateRecordsFromProjection() throws {
    let calendar = utcCalendar()
    let cells = [
        yearCell("2026-03-02", try date(2026, 3, 2, calendar: calendar), .recorded, workHours: 8, overtimeHours: 1),
        yearCell("2026-03-03", try date(2026, 3, 3, calendar: calendar), .corrected, workHours: 4, overtimeHours: 0),
        yearCell("2026-03-07", try date(2026, 3, 7, calendar: calendar), .rest),
        yearCell("2026-03-08", try date(2026, 3, 8, calendar: calendar), .unrecorded),
        yearCell("2026-04-01", try date(2026, 4, 1, calendar: calendar), .planned, workHours: 8, isProjection: true),
        yearCell("2026-04-02", try date(2026, 4, 2, calendar: calendar), .planned, workHours: 8)
    ]

    let months = RecordsYearMonthSampler.months(cells: cells, calendar: calendar)
    #expect(months.map(\.month) == [3, 4])

    let march = try #require(months.first)
    #expect(march.workdays == 2)
    #expect(march.workMs == Int64(12 * hourMs))
    #expect(march.overtimeMs == Int64(hourMs))
    #expect(march.projectedMs == 0)

    // Both saved future schedules and life projections stay separate from
    // recorded totals and remain visible as the pale projected segment.
    let april = try #require(months.last)
    #expect(april.workdays == 0)
    #expect(april.totalMs == 0)
    #expect(april.projectedMs == Int64(16 * hourMs))
}

@MainActor
@Test("Collapsed year draws historical projections as estimated work")
func yearBucketsKeepHistoricalProjectionVisible() throws {
    let calendar = utcCalendar()
    let start = try date(2026, 3, 1, calendar: calendar)
    let end = try date(2026, 4, 1, calendar: calendar)
    let cells = [
        yearCell(
            "2026-03-02",
            try date(2026, 3, 2, calendar: calendar),
            .unrecorded,
            workHours: 8,
            isProjection: true
        )
    ]

    let bucket = try #require(
        RecordsYearSampler.buckets(
            from: start,
            to: end,
            count: 1,
            cells: cells,
            calendar: calendar
        ).first
    )

    #expect(bucket.kind == .planned)
    #expect(bucket.isProjection)
    #expect(bucket.hasEstimatedWork)
    #expect(bucket.workMs == Int64(8 * hourMs))
}

@MainActor
@Test("Year hatching distinguishes estimated work from recorded work and projected rest")
func yearBucketsHatchOnlyEstimatedWork() throws {
    let calendar = utcCalendar()
    let start = try date(2026, 3, 1, calendar: calendar)
    let end = try date(2026, 3, 6, calendar: calendar)
    let cells = [
        yearCell("2026-03-01", start, .recorded, workHours: 8),
        yearCell("2026-03-02", try date(2026, 3, 2, calendar: calendar), .planned, workHours: 8),
        yearCell("2026-03-03", try date(2026, 3, 3, calendar: calendar), .unrecorded, isProjection: true),
        yearCell("2026-03-04", try date(2026, 3, 4, calendar: calendar), .unrecorded, overtimeHours: 2, isProjection: true),
        yearCell("2026-03-05", try date(2026, 3, 5, calendar: calendar), .planned)
    ]
    let buckets = RecordsYearSampler.buckets(from: start, to: end, count: 5, cells: cells, calendar: calendar)
    #expect(buckets.map(\.hasEstimatedWork) == [false, true, false, true, false])
}

@MainActor
@Test("A locked month contributes no numbers to the expanded year")
func yearMonthBarsRevealNothingForLockedDays() throws {
    let calendar = utcCalendar()
    let cells = [
        yearCell("2026-01-05", try date(2026, 1, 5, calendar: calendar), .locked, workHours: 8, overtimeHours: 2),
        yearCell("2026-01-06", try date(2026, 1, 6, calendar: calendar), .locked)
    ]

    let january = try #require(RecordsYearMonthSampler.months(cells: cells, calendar: calendar).first)
    #expect(january.workdays == 0)
    #expect(january.workMs == 0)
    #expect(january.overtimeMs == 0)
    #expect(january.projectedMs == 0)
    #expect(january.hasLockedDays)
}

@MainActor
@Test("Every month row is drawn against one ceiling that covers the longest row")
func yearMonthBarsShareOneAxisCeiling() throws {
    let calendar = utcCalendar()
    let cells = [
        yearCell("2026-05-04", try date(2026, 5, 4, calendar: calendar), .recorded, workHours: 30, overtimeHours: 0),
        yearCell("2026-06-01", try date(2026, 6, 1, calendar: calendar), .recorded, workHours: 150, overtimeHours: 12),
        yearCell("2026-07-01", try date(2026, 7, 1, calendar: calendar), .planned, workHours: 90, isProjection: true)
    ]
    let months = RecordsYearMonthSampler.months(cells: cells, calendar: calendar)
    let ceiling = RecordsYearMonthSampler.axisCeiling(for: months)

    #expect(ceiling == Int64(200 * hourMs))
    for month in months {
        #expect(month.drawnMs <= ceiling)
    }

    #expect(RecordsYearMonthSampler.axisCeiling(for: []) == Int64(hourMs))
}

@MainActor
private func yearCell(
    _ dayKey: String,
    _ date: Date,
    _ appearance: RecordsDayAppearance,
    workHours: Double = 0,
    overtimeHours: Double = 0,
    isProjection: Bool = false
) -> RecordsDayCell {
    RecordsDayCell(
        dayKey: dayKey,
        date: date,
        appearance: appearance,
        workMs: Int64(workHours * hourMs),
        overtimeMs: Int64(overtimeHours * hourMs),
        breakMs: 0,
        freeMs: 0,
        observationCount: 0,
        isToday: false,
        isFuture: false,
        isProjection: isProjection,
        hasConflict: false
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


@MainActor
@Test("Overtime color uses a stable daily scale and never darkens future work")
func overtimeHeatUsesDailyLoad() throws {
    let strengths = [0, 1, 2, 4, 8].map {
        RecordsWorkIntensity.opacity(overtimeMs: Int64($0) * 3_600_000, estimated: false)
    }
    #expect(zip(strengths, strengths.dropFirst()).allSatisfy { $0 < $1 })
    #expect(RecordsWorkIntensity.opacity(overtimeMs: 12 * 3_600_000, estimated: false) == strengths.last)
    #expect(RecordsWorkIntensity.opacity(overtimeMs: 8 * 3_600_000, estimated: true) < strengths[0])
    let calendar = utcCalendar()
    let start = try date(2026, 3, 1, calendar: calendar)
    let end = try date(2026, 3, 4, calendar: calendar)
    let cells = [
        yearCell("2026-03-01", start, .recorded, workHours: 12, overtimeHours: 0),
        yearCell("2026-03-02", try date(2026, 3, 2, calendar: calendar), .recorded, workHours: 8, overtimeHours: 2),
        yearCell("2026-03-03", try date(2026, 3, 3, calendar: calendar), .corrected, workHours: 8, overtimeHours: 1)
    ]
    let individual = RecordsYearSampler.buckets(from: start, to: end, count: 3, cells: cells, calendar: calendar)
    let combined = try #require(RecordsYearSampler.buckets(from: start, to: end, count: 1, cells: cells, calendar: calendar).first)
    #expect(individual.map(\.peakOvertimeMs) == [0, 2 * 3_600_000, 3_600_000])
    #expect(combined.peakOvertimeMs == 2 * 3_600_000)
    var future = cells[1]
    future.isFuture = true
    future.appearance = .corrected
    let futureBucket = try #require(RecordsYearSampler.buckets(from: start, to: end, count: 1, cells: [future], calendar: calendar).first)
    #expect(futureBucket.isFuture)
    #expect(futureBucket.hasEstimatedWork)
    #expect(futureBucket.peakOvertimeMs == 0)
    #expect(RecordsDayMarks.isEstimated(future))
    let futureMonth = try #require(RecordsYearMonthSampler.months(cells: [future], calendar: calendar).first)
    #expect(futureMonth.totalMs == 0)
    #expect(futureMonth.projectedMs == 10 * 3_600_000)

}
