import Foundation
import Testing
@testable import App

@MainActor
@Test("Timer marks never project to confirm, leave, or cleared")
func timerMarksNeverInventRecordsKinds() {
    let monday = date(2026, 8, 24, 9)
    let planned = [
        segment(date(2026, 8, 24, 9), date(2026, 8, 24, 17)),
    ]
    let marks = TimerDayMarks(
        earlyStartAtMs: ms(date(2026, 8, 24, 8)),
        earlyOffAtMs: ms(date(2026, 8, 24, 15)),
        forcedWorkdayDate: "2026-08-24",
        hasTodayOverride: true,
        hasUnscheduledSession: true,
        isWorkday: true
    )

    let override = DayOverrideProjection.project(
        marks: marks,
        dayKey: "2026-08-24",
        shiftAnchorDate: Calendar.current.startOfDay(for: monday),
        plannedSegments: planned
    )

    #expect(override?.kind == .customSegments)
    #expect(override?.kind != .confirmedAsScheduled)
    #expect(override?.kind != .notWorking)
    #expect(override?.kind != .cleared)
}

@MainActor
@Test("No timer marks means no day override")
func noMarksMeansNoOverride() {
    let monday = date(2026, 8, 24, 9)
    let planned = [
        segment(date(2026, 8, 24, 9), date(2026, 8, 24, 17)),
    ]
    let marks = TimerDayMarks(
        earlyStartAtMs: nil,
        earlyOffAtMs: nil,
        forcedWorkdayDate: nil,
        hasTodayOverride: false,
        hasUnscheduledSession: false,
        isWorkday: true
    )

    #expect(
        DayOverrideProjection.project(
            marks: marks,
            dayKey: "2026-08-24",
            shiftAnchorDate: Calendar.current.startOfDay(for: monday),
            plannedSegments: planned
        ) == nil
    )
}

@MainActor
@Test("A today overlay on a rest day is not a day override")
func todayOverlayOnRestDayIsNotAnOverride() {
    let saturday = date(2026, 8, 29, 11)
    let marks = TimerDayMarks(
        earlyStartAtMs: nil,
        earlyOffAtMs: nil,
        forcedWorkdayDate: nil,
        hasTodayOverride: true,
        hasUnscheduledSession: false,
        isWorkday: false
    )

    #expect(
        DayOverrideProjection.project(
            marks: marks,
            dayKey: "2026-08-29",
            shiftAnchorDate: Calendar.current.startOfDay(for: saturday),
            plannedSegments: []
        ) == nil
    )
}

@MainActor
@Test("Early start extends the first fragment and keeps the planned end")
func earlyStartExtendsFirstSegment() throws {
    let planned = [
        segment(date(2026, 8, 24, 9), date(2026, 8, 24, 17)),
    ]
    let start = date(2026, 8, 24, 8)
    let marks = TimerDayMarks(
        earlyStartAtMs: ms(start),
        earlyOffAtMs: nil,
        forcedWorkdayDate: nil,
        hasTodayOverride: false,
        hasUnscheduledSession: false,
        isWorkday: true
    )

    let override = try #require(DayOverrideProjection.project(
        marks: marks,
        dayKey: "2026-08-24",
        shiftAnchorDate: Calendar.current.startOfDay(for: start),
        plannedSegments: planned
    ))
    #expect(override.kind == .customSegments)
    #expect(override.dayKey == "2026-08-24")
    #expect(override.segments == [
        segment(start, date(2026, 8, 24, 17)),
    ])
}

@MainActor
@Test("Early clock-off clips the last fragment and is not leave")
func earlyOffClipsLastSegment() throws {
    let planned = [
        segment(date(2026, 8, 24, 9), date(2026, 8, 24, 17)),
    ]
    let end = date(2026, 8, 24, 15)
    let marks = TimerDayMarks(
        earlyStartAtMs: nil,
        earlyOffAtMs: ms(end),
        forcedWorkdayDate: nil,
        hasTodayOverride: false,
        hasUnscheduledSession: false,
        isWorkday: true
    )

    let override = try #require(DayOverrideProjection.project(
        marks: marks,
        dayKey: "2026-08-24",
        shiftAnchorDate: Calendar.current.startOfDay(for: date(2026, 8, 24, 9)),
        plannedSegments: planned
    ))
    #expect(override.kind == .customSegments)
    #expect(override.segments == [
        segment(date(2026, 8, 24, 9), end),
    ])
}

@MainActor
@Test("Early start and early off compose on one day")
func earlyStartAndOffCompose() throws {
    let planned = [
        segment(date(2026, 8, 24, 9), date(2026, 8, 24, 17)),
    ]
    let start = date(2026, 8, 24, 8)
    let end = date(2026, 8, 24, 15)
    let marks = TimerDayMarks(
        earlyStartAtMs: ms(start),
        earlyOffAtMs: ms(end),
        forcedWorkdayDate: nil,
        hasTodayOverride: false,
        hasUnscheduledSession: false,
        isWorkday: true
    )

    let override = try #require(DayOverrideProjection.project(
        marks: marks,
        dayKey: "2026-08-24",
        shiftAnchorDate: Calendar.current.startOfDay(for: start),
        plannedSegments: planned
    ))
    #expect(override.segments == [segment(start, end)])
}

@MainActor
@Test("A lunch gap stays when the clock-off is after it")
func lunchGapSurvivesClockOffAfterBreak() throws {
    let planned = [
        segment(date(2026, 8, 24, 9), date(2026, 8, 24, 12)),
        segment(date(2026, 8, 24, 13), date(2026, 8, 24, 17)),
    ]
    let end = date(2026, 8, 24, 14)
    let marks = TimerDayMarks(
        earlyStartAtMs: nil,
        earlyOffAtMs: ms(end),
        forcedWorkdayDate: nil,
        hasTodayOverride: false,
        hasUnscheduledSession: false,
        isWorkday: true
    )

    let override = try #require(DayOverrideProjection.project(
        marks: marks,
        dayKey: "2026-08-24",
        shiftAnchorDate: Calendar.current.startOfDay(for: date(2026, 8, 24, 9)),
        plannedSegments: planned
    ))
    #expect(override.segments == [
        segment(date(2026, 8, 24, 9), date(2026, 8, 24, 12)),
        segment(date(2026, 8, 24, 13), end),
    ])
}

@MainActor
@Test("Clocking off during lunch drops the afternoon fragment")
func clockOffDuringLunchDropsAfternoon() throws {
    let planned = [
        segment(date(2026, 8, 24, 9), date(2026, 8, 24, 12)),
        segment(date(2026, 8, 24, 13), date(2026, 8, 24, 17)),
    ]
    let end = date(2026, 8, 24, 12, 30)
    let marks = TimerDayMarks(
        earlyStartAtMs: nil,
        earlyOffAtMs: ms(end),
        forcedWorkdayDate: nil,
        hasTodayOverride: false,
        hasUnscheduledSession: false,
        isWorkday: true
    )

    let override = try #require(DayOverrideProjection.project(
        marks: marks,
        dayKey: "2026-08-24",
        shiftAnchorDate: Calendar.current.startOfDay(for: date(2026, 8, 24, 9)),
        plannedSegments: planned
    ))
    #expect(override.segments == [
        segment(date(2026, 8, 24, 9), date(2026, 8, 24, 12)),
    ])
}

@MainActor
@Test("Overnight clock-off keeps the start-day key")
func overnightClockOffKeepsStartDayKey() throws {
    let planned = [
        segment(date(2026, 8, 21, 22), date(2026, 8, 22, 6)),
    ]
    let end = date(2026, 8, 22, 1)
    let marks = TimerDayMarks(
        earlyStartAtMs: nil,
        earlyOffAtMs: ms(end),
        forcedWorkdayDate: nil,
        hasTodayOverride: false,
        hasUnscheduledSession: false,
        isWorkday: true
    )

    let override = try #require(DayOverrideProjection.project(
        marks: marks,
        dayKey: "2026-08-21",
        shiftAnchorDate: Calendar.current.startOfDay(for: date(2026, 8, 21, 22)),
        plannedSegments: planned
    ))
    #expect(override.dayKey == "2026-08-21")
    #expect(override.segments == [
        segment(date(2026, 8, 21, 22), end),
    ])
}

@MainActor
@Test("A scheduled day with no marks does not project")
func storeWithoutMarksProjectsNothing() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let monday = date(2026, 8, 24, 11)
    let store = scheduledStore(defaults: defaults)
    store.startCountdown(at: monday)

    #expect(store.projectedDayOverride(at: monday) == nil)
}

@MainActor
@Test("Clocking in early projects custom segments from now to the planned end")
func storeEarlyStartProjectsCustomSegments() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let beforeStart = date(2026, 8, 24, 8)
    let store = scheduledStore(defaults: defaults)
    store.startCountdown(at: beforeStart)
    store.clockInEarly(at: beforeStart)

    let override = try #require(store.projectedDayOverride(at: beforeStart))
    #expect(override.kind == .customSegments)
    #expect(override.dayKey == "2026-08-24")
    #expect(override.segments.first?.startAtMs == ms(beforeStart))
    #expect(override.segments.last?.endAtMs == ms(date(2026, 8, 24, 17)))

    store.undoEarlyClockIn()
    #expect(store.projectedDayOverride(at: beforeStart) == nil)
}

@MainActor
@Test("Clocking off early projects custom segments and is not leave")
func storeEarlyOffProjectsCustomSegments() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let atWork = date(2026, 8, 24, 15)
    let store = scheduledStore(defaults: defaults)
    store.startCountdown(at: atWork)
    store.clockOffEarly(at: atWork)

    let override = try #require(store.projectedDayOverride(at: atWork))
    #expect(override.kind == .customSegments)
    #expect(override.kind != .notWorking)
    #expect(override.dayKey == "2026-08-24")
    #expect(override.segments.last?.endAtMs == ms(atWork))

    store.undoEarlyClockOff()
    #expect(store.projectedDayOverride(at: atWork) == nil)
}

@MainActor
@Test("Rest-day manual timing projects the planned hours onto that start day")
func storeForcedWorkdayProjectsCustomSegments() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let saturday = date(2026, 8, 29, 11)
    let store = scheduledStore(defaults: defaults)
    store.startCountdown(force: true, at: saturday)

    let override = try #require(store.projectedDayOverride(at: saturday))
    #expect(override.kind == .customSegments)
    #expect(override.dayKey == store.forcedWorkdayKey)
    #expect(override.segments.first?.startAtMs == ms(date(2026, 8, 29, 9)))
    #expect(override.segments.last?.endAtMs == ms(date(2026, 8, 29, 17)))

    store.cancelManualTiming()
    #expect(store.projectedDayOverride(at: saturday) == nil)
}

@MainActor
@Test("Unscheduled manual timing projects a session, not a forced workday")
func storeUnscheduledSessionProjectsCustomSegments() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let monday = date(2026, 8, 24, 11)
    let store = scheduledStore(defaults: defaults)
    store.scheduleMode = .off
    store.startCountdown(at: monday)

    #expect(store.forcedWorkdayKey == nil)
    let override = try #require(store.projectedDayOverride(at: monday))
    #expect(override.kind == .customSegments)
    #expect(override.dayKey == "2026-08-24")
}

@MainActor
@Test("Keeping today's hours while the schedule moves projects those hours")
func storeTodayOverlayProjectsCustomSegments() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let monday = date(2026, 8, 24, 11)
    let store = scheduledStore(defaults: defaults)
    store.startCountdown(at: monday)
    store.applyScheduleChange(
        ScheduleFieldChange(endMinutes: 18 * 60),
        decision: .nextShiftOnly,
        at: monday
    )

    #expect(store.endMinutes == 18 * 60)
    #expect(store.effectiveEndMinutes(at: monday) == 17 * 60)
    let override = try #require(store.projectedDayOverride(at: monday))
    #expect(override.kind == .customSegments)
    #expect(override.segments.last?.endAtMs == ms(date(2026, 8, 24, 17)))
}

@MainActor
@Test("Applying hours to today is a schedule revision, not a day override")
func storeApplyToTodayDoesNotProject() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let monday = date(2026, 8, 24, 11)
    let store = scheduledStore(defaults: defaults)
    store.startCountdown(at: monday)
    store.applyScheduleChange(
        ScheduleFieldChange(endMinutes: 18 * 60),
        decision: .applyToToday,
        at: monday
    )

    #expect(store.endMinutes == 18 * 60)
    #expect(store.projectedDayOverride(at: monday) == nil)
}

@MainActor
@Test("Overtime alone does not project a day override")
func storeOvertimeAloneDoesNotProject() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let monday = date(2026, 8, 24, 16)
    let overtimeEnd = date(2026, 8, 24, 18)
    let store = scheduledStore(defaults: defaults)
    store.startCountdown(at: monday)
    store.applyOvertime(date: overtimeEnd)

    #expect(store.projectedDayOverride(at: monday) == nil)
}

@MainActor
@Test("Overnight early clock-off keys the Friday start, not Saturday")
func storeOvernightEarlyOffUsesStartDayKey() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let fridayNight = date(2026, 8, 21, 23)
    let saturdayMorning = date(2026, 8, 22, 1)
    let store = scheduledStore(defaults: defaults)
    store.startMinutes = 22 * 60
    store.endMinutes = 6 * 60
    store.workdays = [5]
    store.startCountdown(at: fridayNight)
    store.clockOffEarly(at: saturdayMorning)

    let override = try #require(store.projectedDayOverride(at: saturdayMorning))
    #expect(override.dayKey == "2026-08-21")
    #expect(override.segments.last?.endAtMs == ms(saturdayMorning))
}

@MainActor
@Test("Forced workday then clock-off stays one custom day")
func storeForcedWorkdayThenClockOffComposes() throws {
    let (defaults, suite) = try isolatedProjectionDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let saturday = date(2026, 8, 29, 15)
    let store = scheduledStore(defaults: defaults)
    store.startCountdown(force: true, at: saturday)
    store.clockOffEarly(at: saturday)

    let override = try #require(store.projectedDayOverride(at: saturday))
    #expect(override.kind == .customSegments)
    #expect(override.dayKey == "2026-08-29")
    #expect(override.segments.last?.endAtMs == ms(saturday))
}

@MainActor
private func scheduledStore(defaults: UserDefaults) -> OffWorkStore {
    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    return store
}

private func isolatedProjectionDefaults() throws -> (UserDefaults, String) {
    let suite = "DayOverrideProjectionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    )) ?? .distantPast
}

private func ms(_ date: Date) -> Double {
    date.timeIntervalSince1970 * 1_000
}

private func segment(_ start: Date, _ end: Date) -> NativeShiftSegment {
    NativeShiftSegment(startAtMs: ms(start), endAtMs: ms(end))
}
