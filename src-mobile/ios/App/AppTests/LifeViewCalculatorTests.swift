import Foundation
import Testing
@testable import App

@MainActor
@Test("Life view weeks run to retirement, not a fixed 52-week year")
func lifeViewUsesContinuousWeeks() {
    let calendar = lifeTestCalendar()
    let profile = LifeProfile(
        birthYear: 1990,
        workStartedOn: calendar.date(from: DateComponents(year: 2012, month: 1, day: 1)),
        retirementAge: 60,
        averageSleepHours: 8,
        hidesExactAges: false,
        editedAt: Date(timeIntervalSince1970: 0),
        editCount: 1,
        editTieBreaker: UUID()
    )
    let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
    let periodID = UUID()
    let model = LifeViewCalculator.build(
        profile: profile,
        scheduleDays: [
            lifeScheduleDay(
                periodID: periodID,
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!,
                startHour: 9,
                durationHours: 8,
                calendar: calendar
            ),
            lifeScheduleDay(
                periodID: periodID,
                date: calendar.date(from: DateComponents(year: 2030, month: 8, day: 26))!,
                startHour: 9,
                durationHours: 8,
                calendar: calendar
            ),
        ],
        outsideZoneDays: [],
        now: now,
        calendar: calendar
    )
    #expect(!model.cells.isEmpty)
    #expect(model.cells.contains { $0.kind == .workEstimated || $0.kind == .workProjected })
    #expect(model.cells.last?.year == 2050)
}

@MainActor
@Test("Ended career periods leave a real gap instead of projecting work through it")
func lifeViewKeepsCareerPeriodGapsEmpty() {
    let calendar = lifeTestCalendar()
    let profile = LifeProfile(
        averageSleepHours: 8,
        bornOn: .exact(year: 2026, month: 1, day: 1),
        workStartedPartial: .exact(year: 2026, month: 1, day: 1),
        retirementOn: .exact(year: 2026, month: 1, day: 22),
        editedAt: Date(timeIntervalSince1970: 0),
        editCount: 1,
        editTieBreaker: UUID()
    )
    let firstPeriodID = UUID()
    let secondPeriodID = UUID()
    let now = lifeTestDate(year: 2026, month: 1, day: 10, calendar: calendar)
    let model = LifeViewCalculator.build(
        profile: profile,
        scheduleDays: [
            lifeScheduleDay(
                periodID: firstPeriodID,
                date: lifeTestDate(year: 2026, month: 1, day: 1, calendar: calendar),
                startHour: 9,
                durationHours: 4,
                calendar: calendar
            ),
            lifeScheduleDay(
                periodID: firstPeriodID,
                date: lifeTestDate(year: 2026, month: 1, day: 2, calendar: calendar),
                startHour: 9,
                durationHours: 4,
                calendar: calendar
            ),
            lifeScheduleDay(
                periodID: secondPeriodID,
                date: lifeTestDate(year: 2026, month: 1, day: 15, calendar: calendar),
                startHour: 9,
                durationHours: 8,
                calendar: calendar
            ),
            lifeScheduleDay(
                periodID: secondPeriodID,
                date: lifeTestDate(year: 2026, month: 1, day: 16, calendar: calendar),
                startHour: 9,
                durationHours: 8,
                calendar: calendar
            ),
        ],
        outsideZoneDays: [],
        now: now,
        calendar: calendar
    )
    #expect(model.cells.map(\.kind) == [.workEstimated, .none, .workProjected])

    let expectedWorkShare = 24.0 / (21 * 24)
    let expectedOwnAwakeShare = (21 * 16.0 - 24) / (21 * 24)
    #expect(abs(model.workShare - expectedWorkShare) < 0.000_000_1)
    #expect(abs(model.ownAwakeShare - expectedOwnAwakeShare) < 0.000_000_1)
}

@MainActor
@Test("Different effective segment lengths produce different life work shares")
func lifeViewUsesEffectiveSegmentDuration() {
    let calendar = lifeTestCalendar()
    let profile = LifeProfile(
        averageSleepHours: 8,
        bornOn: .exact(year: 2026, month: 1, day: 1),
        workStartedPartial: .exact(year: 2026, month: 1, day: 1),
        retirementOn: .exact(year: 2026, month: 1, day: 8),
        editedAt: Date(timeIntervalSince1970: 0),
        editCount: 1,
        editTieBreaker: UUID()
    )
    let periodID = UUID()
    let date = lifeTestDate(year: 2026, month: 1, day: 2, calendar: calendar)
    let fourHourDay = lifeScheduleDay(
        periodID: periodID,
        date: date,
        startHour: 9,
        durationHours: 4,
        calendar: calendar
    )
    let eightHourDay = lifeScheduleDay(
        periodID: periodID,
        date: date,
        startHour: 9,
        durationHours: 8,
        calendar: calendar
    )
    let shortModel = LifeViewCalculator.build(
        profile: profile,
        scheduleDays: [fourHourDay, fourHourDay],
        outsideZoneDays: [],
        now: lifeTestDate(year: 2026, month: 1, day: 4, calendar: calendar),
        calendar: calendar
    )
    let longModel = LifeViewCalculator.build(
        profile: profile,
        scheduleDays: [eightHourDay],
        outsideZoneDays: [],
        now: lifeTestDate(year: 2026, month: 1, day: 4, calendar: calendar),
        calendar: calendar
    )

    // The duplicate four-hour segment is intentionally supplied twice: the
    // absolute interval union must not count it twice.
    #expect(abs(shortModel.workShare - (4.0 / (7 * 24))) < 0.000_000_1)
    #expect(abs(longModel.workShare - (8.0 / (7 * 24))) < 0.000_000_1)
    #expect(abs(longModel.workShare - shortModel.workShare * 2) < 0.000_000_1)
    #expect(longModel.ownAwakeShare < shortModel.ownAwakeShare)
}

@MainActor
@Test("Leave is not work, and a mid-week correction is still visible")
func lifeViewDoesNotCountLeaveAsWork() {
    let calendar = lifeTestCalendar()
    let profile = LifeProfile(
        averageSleepHours: 8,
        bornOn: .exact(year: 2026, month: 1, day: 1),
        workStartedPartial: .exact(year: 2026, month: 1, day: 1),
        retirementOn: .exact(year: 2026, month: 1, day: 15),
        editedAt: Date(timeIntervalSince1970: 0),
        editCount: 1,
        editTieBreaker: UUID()
    )
    let periodID = UUID()
    let correctedDate = lifeTestDate(year: 2026, month: 1, day: 3, calendar: calendar)
    let corrected = lifeScheduleDay(
        periodID: periodID,
        date: correctedDate,
        startHour: 10,
        durationHours: 9,
        calendar: calendar,
        isOverride: true
    )
    let leaveWeek = (8...14).map { day in
        LifeScheduleDay(
            periodID: periodID,
            dayKey: RecordJSON.dayKey(
                lifeTestDate(year: 2026, month: 1, day: day, calendar: calendar),
                calendar: calendar
            ),
            shiftAnchorDate: lifeTestDate(year: 2026, month: 1, day: day, calendar: calendar),
            segments: [],
            isOverride: false
        )
    }

    let model = LifeViewCalculator.build(
        profile: profile,
        scheduleDays: [corrected] + leaveWeek,
        outsideZoneDays: [leaveWeek[2].dayKey],
        now: lifeTestDate(year: 2026, month: 1, day: 15, calendar: calendar),
        calendar: calendar
    )
    #expect(model.cells.map(\.kind) == [.workOverride, .none])
    #expect(model.cells[1].outsidePeriodTimeZone)
}

private func lifeTestCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func lifeTestDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

@MainActor
private func lifeScheduleDay(
    periodID: UUID,
    date: Date,
    startHour: Int,
    durationHours: Int,
    calendar: Calendar,
    isOverride: Bool = false
) -> LifeScheduleDay {
    let start = calendar.date(byAdding: .hour, value: startHour, to: date)!
    let end = calendar.date(byAdding: .hour, value: durationHours, to: start)!
    return LifeScheduleDay(
        periodID: periodID,
        dayKey: RecordJSON.dayKey(date, calendar: calendar),
        shiftAnchorDate: date,
        segments: [
            NativeShiftSegment(
                startAtMs: start.timeIntervalSince1970 * 1_000,
                endAtMs: end.timeIntervalSince1970 * 1_000
            ),
        ],
        isOverride: isOverride
    )
}

@MainActor
@Test("Year-only life dates use mid-year, never the first of January")
func partialCivilDateYearUsesMidYear() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let year = PartialCivilDate.yearOnly(1990)
    let anchor = year.calculationAnchor(in: calendar)!
    #expect(calendar.component(.month, from: anchor) == 7)
    #expect(calendar.component(.day, from: anchor) == 1)
    #expect(PartialCivilDate.exact(year: 2026, month: 13, day: 1) == nil)
}

@MainActor
@Test("Overnight work splits across the two civil days and DST days still sum to 100%")
func timeAllocationSplitsOvernightAndDST() {
    let day = Date(timeIntervalSince1970: 1_787_529_600) // 2026-08-24 00:00 UTC
    let next = day.addingTimeInterval(86_400)
    let overnight = [
        NativeShiftSegment(
            startAtMs: (day.addingTimeInterval(20 * 3600).timeIntervalSince1970) * 1_000,
            endAtMs: (next.addingTimeInterval(4 * 3600).timeIntervalSince1970) * 1_000
        )
    ]
    let first = TimeAllocationCalculator.share(
        dayStart: day,
        nextDayStart: next,
        workSegments: overnight,
        sleepHours: 8
    )
    let second = TimeAllocationCalculator.share(
        dayStart: next,
        nextDayStart: next.addingTimeInterval(86_400),
        workSegments: overnight,
        sleepHours: 8
    )
    #expect(first.workMs == 4 * 3_600_000)
    #expect(second.workMs == 4 * 3_600_000)
    #expect(first.unclassifiedMs == 0)
    #expect(second.unclassifiedMs == 0)
    #expect(first.totalMs == first.dayLengthMs)
    #expect(second.totalMs == second.dayLengthMs)

    let shortDay = TimeAllocationCalculator.share(
        dayStart: day,
        nextDayStart: day.addingTimeInterval(23 * 3600),
        workSegments: [
            NativeShiftSegment(
                startAtMs: day.timeIntervalSince1970 * 1_000,
                endAtMs: day.addingTimeInterval(8 * 3600).timeIntervalSince1970 * 1_000
            )
        ],
        sleepHours: 8
    )
    #expect(shortDay.dayLengthMs == 23 * 3_600_000)
    #expect(shortDay.totalMs == shortDay.dayLengthMs)
    #expect(shortDay.freeMs >= 0)
}

@MainActor
@Test("Unclassified time is reserved for incomplete schedule expansion")
func unclassifiedTimeRequiresIncompleteSchedule() {
    let day = Date(timeIntervalSince1970: 1_787_529_600)
    let next = day.addingTimeInterval(86_400)
    let complete = TimeAllocationCalculator.share(
        dayStart: day,
        nextDayStart: next,
        workSegments: [],
        sleepHours: 8
    )
    let incomplete = TimeAllocationCalculator.share(
        dayStart: day,
        nextDayStart: next,
        workSegments: [],
        sleepHours: 8,
        incomplete: true
    )

    #expect(complete.unclassifiedMs == 0)
    #expect(complete.freeMs == 16 * 3_600_000)
    #expect(incomplete.unclassifiedMs == 16 * 3_600_000)
    #expect(incomplete.freeMs == 0)
    #expect(incomplete.totalMs == incomplete.dayLengthMs)
}

@MainActor
@Test("Life stages use mid-year anchors and do not invent a lifespan")
func lifeStagesStopAtRetirement() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var profile = LifeProfile(
        birthYear: 1990,
        retirementAge: 60,
        editedAt: Date(timeIntervalSince1970: 0),
        editCount: 1,
        editTieBreaker: UUID()
    )
    profile.workStartedPartial = .yearOnly(2012)
    profile.migrateLegacyFields(calendar: calendar)
    let stages = LifeStageCalculator.stages(profile: profile, calendar: calendar)
    #expect(stages.contains(where: { $0.kind == .work && $0.start != nil && $0.end != nil }))
    let bounds = LifeStageCalculator.timelineBounds(stages: stages, now: Date(timeIntervalSince1970: 1_787_529_600))
    #expect(bounds != nil)
    #expect(calendar.component(.year, from: bounds!.1) == 2050)
    let buckets = LifeStageCalculator.buckets(
        stages: stages,
        from: bounds!.0,
        to: bounds!.1,
        count: 20,
        now: Date(timeIntervalSince1970: 1_787_529_600)
    )
    #expect(buckets.count == 20)
    #expect(Set(buckets.map(\.kind)).contains(.childhood))
    #expect(Set(buckets.map(\.kind)).contains(.work))
}

@MainActor
@Test("The current life stage follows future school, work, and retirement boundaries")
func currentLifeStageUsesEveryConfiguredBoundary() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date: (Int, Int, Int) throws -> Date = { year, month, day in
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
    let stages = [
        LifeStageSpan(kind: .childhood, start: try date(2010, 1, 1), end: try date(2022, 9, 1), startPrecision: .day, endPrecision: .day),
        LifeStageSpan(kind: .study, start: try date(2022, 9, 1), end: try date(2030, 7, 1), startPrecision: .day, endPrecision: .day),
        LifeStageSpan(kind: .work, start: try date(2030, 7, 1), end: try date(2070, 1, 1), startPrecision: .day, endPrecision: .day),
        LifeStageSpan(kind: .retirement, start: try date(2070, 1, 1), end: nil, startPrecision: .day, endPrecision: nil),
    ]

    #expect(LifeStageCalculator.kind(at: try date(2018, 1, 1), stages: stages) == .childhood)
    #expect(LifeStageCalculator.kind(at: try date(2026, 8, 31), stages: stages) == .study)
    #expect(LifeStageCalculator.kind(at: try date(2040, 1, 1), stages: stages) == .work)
    #expect(LifeStageCalculator.kind(at: try date(2075, 1, 1), stages: stages) == .retirement)
}

@MainActor
@Test("Life progress is clamped and advances through the configured span")
func lifeProgressIsClamped() {
    let start = Date(timeIntervalSince1970: 1_000)
    let end = Date(timeIntervalSince1970: 2_000)
    #expect(LifeStageCalculator.progress(from: start, to: end, at: Date(timeIntervalSince1970: 0)) == 0)
    #expect(LifeStageCalculator.progress(from: start, to: end, at: Date(timeIntervalSince1970: 1_500)) == 0.5)
    #expect(LifeStageCalculator.progress(from: start, to: end, at: Date(timeIntervalSince1970: 3_000)) == 1)
}
