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
@Test("Recorded overtime remains work in every life conclusion")
func lifeViewIncludesRecordedOvertime() {
    let calendar = lifeTestCalendar()
    let profile = LifeProfile(
        averageSleepHours: 8,
        bornOn: .exact(year: 2026, month: 1, day: 1),
        workStartedPartial: .exact(year: 2026, month: 1, day: 1),
        retirementOn: .exact(year: 2026, month: 1, day: 2),
        editedAt: Date(timeIntervalSince1970: 0),
        editCount: 1,
        editTieBreaker: UUID()
    )
    let day = lifeScheduleDay(
        periodID: UUID(),
        date: lifeTestDate(year: 2026, month: 1, day: 1, calendar: calendar),
        startHour: 9,
        durationHours: 8,
        overtimeHours: 2,
        calendar: calendar
    )
    let model = LifeViewCalculator.build(
        profile: profile,
        scheduleDays: [day],
        outsideZoneDays: [],
        now: lifeTestDate(year: 2026, month: 1, day: 2, calendar: calendar),
        calendar: calendar
    )

    #expect(model.allocation.workMs == 8 * 3_600_000)
    #expect(model.allocation.overtimeMs == 2 * 3_600_000)
    #expect(abs(model.workShare - 10.0 / 24) < 0.000_000_1)
    #expect(abs(model.ownAwakeShare - 6.0 / 24) < 0.000_000_1)
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
    overtimeHours: Int = 0,
    calendar: Calendar,
    isOverride: Bool = false
) -> LifeScheduleDay {
    let start = calendar.date(byAdding: .hour, value: startHour, to: date)!
    let end = calendar.date(byAdding: .hour, value: durationHours, to: start)!
    let overtimeEnd = calendar.date(byAdding: .hour, value: overtimeHours, to: end)!
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
        overtimeSegments: overtimeHours > 0
            ? [
                NativeShiftSegment(
                    startAtMs: end.timeIntervalSince1970 * 1_000,
                    endAtMs: overtimeEnd.timeIntervalSince1970 * 1_000
                ),
            ]
            : [],
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

/// The life model is now cached, because rebuilding it expands a career's
/// worth of schedule and that was happening on every visit to the Records tab.
/// A cache that misses an edit is worse than no cache: the grid would keep
/// showing a retirement date the user has already changed.
@MainActor
@Test("The cached life model is rebuilt when the archive changes")
func lifeViewModelCacheFollowsTheArchive() async {
    let defaults = UserDefaults(suiteName: "owc.lifecache.\(UUID().uuidString)")!
    let store = OffWorkStore(defaults: defaults, records: .inMemory())
    store.saveLifeProfile(
        birthYear: 1992,
        workStartedYear: 2014,
        retirementAge: 60,
        sleepHours: 8,
        hidesExactAges: false
    )

    // Asking twice for the same archive on the same day has to give the same
    // answer, whether or not the second one came out of the cache.
    let first = await store.prepareLifeViewModel()
    let repeated = await store.prepareLifeViewModel()
    #expect(first != nil)
    #expect(first == repeated)

    // Retiring five years later is more weeks of life, so the cache must not
    // hand back the shorter timeline.
    store.saveLifeProfile(
        birthYear: 1992,
        workStartedYear: 2014,
        retirementAge: 65,
        sleepHours: 8,
        hidesExactAges: false
    )
    let afterEdit = await store.prepareLifeViewModel()
    #expect(afterEdit != nil)
    #expect(afterEdit != first)
    #expect((afterEdit?.cells.count ?? 0) > (first?.cells.count ?? 0))
}
