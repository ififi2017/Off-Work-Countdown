import Foundation
import Testing
@testable import App

@MainActor
@Test("A day with no career period has no conclusion")
func noPeriodResolvesToNone() {
    let day = startOf(2026, 8, 24)
    let resolution = DayRecordResolver.resolve(
        dayKey: "2026-08-24",
        shiftAnchorDate: day,
        periods: [],
        snapshots: [],
        exceptions: [],
        overrides: [],
        expand: { _ in ScheduleExpansion(isWorkday: false, segments: []) }
    )
    #expect(resolution.layer == .none)
    #expect(resolution.isScheduledWorkday == false)
    #expect(resolution.segments.isEmpty)
}

@MainActor
@Test("An ended period does not occupy later days")
func endedPeriodDoesNotCoverLaterDays() {
    let period = period(
        id: id(1),
        startsOn: startOf(2024, 1, 1),
        endsBefore: startOf(2026, 8, 1),
        createdAt: startOf(2024, 1, 1)
    )
    #expect(DayRecordResolver.period(on: startOf(2026, 7, 31), from: [period])?.id == id(1))
    #expect(DayRecordResolver.period(on: startOf(2026, 8, 1), from: [period]) == nil)
    #expect(DayRecordResolver.period(on: startOf(2026, 8, 24), from: [period]) == nil)
}

@MainActor
@Test("Overlapping periods keep both rows and pick the later start")
func overlappingPeriodsPickLaterStart() {
    let older = period(
        id: id(1),
        startsOn: startOf(2020, 1, 1),
        createdAt: startOf(2020, 1, 1)
    )
    let newer = period(
        id: id(2),
        startsOn: startOf(2025, 6, 1),
        createdAt: startOf(2025, 6, 1)
    )
    let day = startOf(2026, 8, 24)
    #expect(DayRecordResolver.period(on: day, from: [older, newer])?.id == id(2))
    #expect(DayRecordResolver.period(on: startOf(2024, 1, 1), from: [older, newer])?.id == id(1))
}

@MainActor
@Test("Equal period starts break ties by createdAt, then id")
func overlappingPeriodsBreakTies() {
    let start = startOf(2024, 1, 1)
    let earlier = period(id: id(2), startsOn: start, createdAt: startOf(2024, 1, 1))
    let laterCreated = period(id: id(1), startsOn: start, createdAt: startOf(2025, 1, 1))
    #expect(DayRecordResolver.period(on: startOf(2026, 8, 24), from: [earlier, laterCreated])?.id == id(1))

    let low = period(id: id(1), startsOn: start, createdAt: start)
    let high = period(id: id(2), startsOn: start, createdAt: start)
    #expect(DayRecordResolver.period(on: startOf(2026, 8, 24), from: [low, high])?.id == id(2))
}

@MainActor
@Test("A future snapshot does not apply, and the latest effectiveFrom wins")
func latestEffectiveSnapshotWins() {
    let period = period(id: id(1), startsOn: startOf(2024, 1, 1), createdAt: startOf(2024, 1, 1))
    let first = snapshot(id: id(10), periodID: id(1), from: startOf(2024, 1, 1), fingerprint: "old")
    let second = snapshot(id: id(11), periodID: id(1), from: startOf(2026, 7, 1), fingerprint: "new")
    let future = snapshot(id: id(12), periodID: id(1), from: startOf(2026, 9, 1), fingerprint: "future")
    let day = startOf(2026, 8, 24)

    #expect(DayRecordResolver.snapshot(on: day, in: period, from: [first, second, future])?.id == id(11))
    #expect(DayRecordResolver.snapshot(on: startOf(2025, 1, 1), in: period, from: [first, second])?.id == id(10))
}

@MainActor
@Test("Two snapshots in the same slot resolve by editCount, then tie-breaker, then id")
func sameSlotSnapshotPicksEditStamp() {
    let period = period(id: id(1), startsOn: startOf(2024, 1, 1), createdAt: startOf(2024, 1, 1))
    let from = startOf(2026, 7, 1)
    let losing = snapshot(
        id: id(10),
        periodID: id(1),
        from: from,
        fingerprint: "a",
        editCount: 1,
        tie: id(1)
    )
    let winningCount = snapshot(
        id: id(9),
        periodID: id(1),
        from: from,
        fingerprint: "b",
        editCount: 2,
        tie: id(1)
    )
    #expect(
        DayRecordResolver.snapshot(on: startOf(2026, 8, 24), in: period, from: [losing, winningCount])?.id
            == id(9)
    )

    let lowTie = snapshot(id: id(20), periodID: id(1), from: from, fingerprint: "c", editCount: 3, tie: id(1))
    let highTie = snapshot(id: id(19), periodID: id(1), from: from, fingerprint: "d", editCount: 3, tie: id(2))
    #expect(
        DayRecordResolver.snapshot(on: startOf(2026, 8, 24), in: period, from: [lowTie, highTie])?.id
            == id(19)
    )
}

@MainActor
@Test("Custom segments beat a holiday and the schedule")
func customOverrideBeatsExceptionAndSchedule() throws {
    let monday = startOf(2026, 8, 24)
    let custom = [
        NativeShiftSegment(startAtMs: ms(monday, hour: 10), endAtMs: ms(monday, hour: 19)),
    ]
    let resolution = resolve(
        day: monday,
        exceptions: [holiday(monday, effect: .rest, origin: .user)],
        overrides: [DayOverride(dayKey: "2026-08-24", shiftAnchorDate: monday, kind: .customSegments, segments: custom)]
    )
    #expect(resolution.layer == .override)
    #expect(resolution.isScheduledWorkday)
    #expect(resolution.segments == custom)
}

@MainActor
@Test("Leave is an override, not a calendar rest, and hours go to zero")
func leaveOverrideIsNotAHoliday() {
    let friday = startOf(2026, 8, 28)
    let resolution = resolve(
        day: friday,
        exceptions: [holiday(friday, effect: .work, origin: .user)],
        overrides: [DayOverride(dayKey: "2026-08-28", shiftAnchorDate: friday, kind: .notWorking, segments: [])]
    )
    #expect(resolution.layer == .override)
    #expect(resolution.isScheduledWorkday == false)
    #expect(resolution.segments.isEmpty)
}

@MainActor
@Test("Clearing an override falls through with no leftover cleared layer")
func clearedOverrideFallsThrough() {
    let monday = startOf(2026, 8, 24)
    let resolution = resolve(
        day: monday,
        overrides: [DayOverride(dayKey: "2026-08-24", shiftAnchorDate: monday, kind: .cleared, segments: [])]
    )
    #expect(resolution.layer == .schedule)
    #expect(resolution.isScheduledWorkday)
    #expect(DayRecordResolver.dayOverride(
        matching: "2026-08-24",
        from: [DayOverride(dayKey: "2026-08-24", shiftAnchorDate: monday, kind: .cleared, segments: [])]
    ) == nil)
}

@MainActor
@Test("Confirming a day keeps the override layer and the schedule hours")
func confirmedOverrideKeepsScheduleHours() {
    let monday = startOf(2026, 8, 24)
    let resolution = resolve(
        day: monday,
        overrides: [DayOverride(
            dayKey: "2026-08-24",
            shiftAnchorDate: monday,
            kind: .confirmedAsScheduled,
            segments: []
        )]
    )
    #expect(resolution.layer == .override)
    #expect(resolution.isScheduledWorkday)
    #expect(resolution.segments == weekdaySegments(monday))
}

@MainActor
@Test("A user holiday beats the weekday schedule")
func userHolidayBeatsSchedule() {
    let monday = startOf(2026, 8, 24)
    let resolution = resolve(
        day: monday,
        exceptions: [holiday(monday, effect: .rest, origin: .user)]
    )
    #expect(resolution.layer == .calendarException)
    #expect(resolution.isScheduledWorkday == false)
    #expect(resolution.segments.isEmpty)
}

@MainActor
@Test("A makeup Saturday becomes a workday with the snapshot hours")
func makeupSaturdayUsesScheduleHours() {
    let saturday = startOf(2026, 8, 29)
    let weekend = snapshot(
        id: id(11),
        periodID: id(1),
        from: startOf(2024, 1, 1),
        fingerprint: "rest"
    )
    let resolution = resolve(
        day: saturday,
        snapshots: [weekend],
        exceptions: [holiday(saturday, effect: .work, origin: .user)]
    )
    #expect(resolution.layer == .calendarException)
    #expect(resolution.isScheduledWorkday)
    #expect(resolution.segments == weekdaySegments(saturday))
}

@MainActor
@Test("A user exception beats bundled data, and a cleared exception falls through")
func userExceptionBeatsBundledAndClearedFallsThrough() {
    let monday = startOf(2026, 8, 24)
    let bundledRest = holiday(monday, effect: .rest, origin: .bundled, version: "2026.1")
    let userWork = holiday(monday, effect: .work, origin: .user)
    #expect(DayRecordResolver.exception(matching: "2026-08-24", from: [bundledRest, userWork])?.origin == .user)

    var cleared = bundledRest
    cleared.isCleared = true
    #expect(DayRecordResolver.exception(matching: "2026-08-24", from: [cleared]) == nil)

    let resolution = resolve(day: monday, exceptions: [cleared])
    #expect(resolution.layer == .schedule)
    #expect(resolution.isScheduledWorkday)
}

@MainActor
@Test("Newer bundled dataset wins among holidays")
func newerBundledDatasetWins() {
    let monday = startOf(2026, 8, 24)
    let old = holiday(monday, effect: .rest, origin: .bundled, version: "2025.1")
    let new = holiday(monday, effect: .work, origin: .bundled, version: "2026.2")
    #expect(DayRecordResolver.exception(matching: "2026-08-24", from: [old, new])?.datasetVersion == "2026.2")
}

@MainActor
@Test("A period without a snapshot does not invent a schedule layer")
func periodWithoutSnapshotIsNone() {
    let monday = startOf(2026, 8, 24)
    let resolution = DayRecordResolver.resolve(
        dayKey: "2026-08-24",
        shiftAnchorDate: monday,
        periods: [period(id: id(1), startsOn: startOf(2024, 1, 1), createdAt: startOf(2024, 1, 1))],
        snapshots: [],
        exceptions: [],
        overrides: [],
        expand: { _ in ScheduleExpansion(isWorkday: false, segments: []) }
    )
    #expect(resolution.layer == .none)
    #expect(resolution.snapshotID == nil)
    #expect(resolution.isScheduledWorkday == false)
}

@MainActor
@Test("A rest snapshot without an exception is a scheduled rest day")
func restSnapshotWithoutExceptionIsRest() {
    let saturday = startOf(2026, 8, 29)
    let weekend = snapshot(
        id: id(11),
        periodID: id(1),
        from: startOf(2024, 1, 1),
        fingerprint: "rest"
    )
    let resolution = resolve(day: saturday, snapshots: [weekend])
    #expect(resolution.layer == .schedule)
    #expect(resolution.isScheduledWorkday == false)
    #expect(resolution.segments.isEmpty)
}

@MainActor
private func resolve(
    day: Date,
    snapshots: [ScheduleSnapshot]? = nil,
    exceptions: [CalendarException] = [],
    overrides: [DayOverride] = []
) -> DayResolution {
    let job = period(id: id(1), startsOn: startOf(2024, 1, 1), createdAt: startOf(2024, 1, 1))
    let weekday = snapshot(id: id(10), periodID: id(1), from: startOf(2024, 1, 1), fingerprint: "weekday")
    return DayRecordResolver.resolve(
        dayKey: OffWorkStore.dayKey(for: day),
        shiftAnchorDate: day,
        periods: [job],
        snapshots: snapshots ?? [weekday],
        exceptions: exceptions,
        overrides: overrides,
        expand: { snapshot in
            ScheduleExpansion(
                isWorkday: snapshot.fingerprint != "rest",
                segments: weekdaySegments(day)
            )
        }
    )
}

@MainActor
private func weekdaySegments(_ day: Date) -> [NativeShiftSegment] {
    [NativeShiftSegment(startAtMs: ms(day, hour: 9), endAtMs: ms(day, hour: 17))]
}

@MainActor
private func holiday(
    _ day: Date,
    effect: CalendarEffect,
    origin: CalendarExceptionOrigin,
    version: String? = nil
) -> CalendarException {
    let dateKey = OffWorkStore.dayKey(for: day)
    return CalendarException(
        dayKey: CalendarException.dayKey(dateKey: dateKey, origin: origin),
        date: day,
        effect: effect,
        origin: origin,
        isCleared: false,
        regionIdentifier: origin == .bundled ? "CN" : nil,
        datasetVersion: version,
        label: nil,
        editedAt: day,
        editCount: 1,
        editTieBreaker: id(1)
    )
}

@MainActor
private func period(
    id: UUID,
    startsOn: Date,
    endsBefore: Date? = nil,
    createdAt: Date
) -> CareerPeriod {
    CareerPeriod(
        id: id,
        startsOn: startsOn,
        endsBefore: endsBefore,
        label: nil,
        timeZoneIdentifier: "Asia/Shanghai",
        calendarIdentifier: "gregorian",
        createdAt: createdAt,
        editedAt: createdAt,
        editCount: 1,
        editTieBreaker: id
    )
}

@MainActor
private func snapshot(
    id: UUID,
    periodID: UUID,
    from: Date,
    fingerprint: String,
    editCount: Int = 1,
    tie: UUID? = nil
) -> ScheduleSnapshot {
    ScheduleSnapshot(
        id: id,
        periodID: periodID,
        effectiveFrom: from,
        configurationData: Data(),
        fingerprint: fingerprint,
        editedAt: from,
        editCount: editCount,
        editTieBreaker: tie ?? id
    )
}

@MainActor
private func startOf(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
}

@MainActor
private func ms(_ day: Date, hour: Int) -> Double {
    let date = Calendar.current.date(byAdding: .hour, value: hour, to: day) ?? day
    return date.timeIntervalSince1970 * 1_000
}

@MainActor
private func id(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
}
