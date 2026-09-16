import Foundation
import Testing
@testable import App

/// Plan 018 P8-b: which shift each civil day gets, and what the countdown,
/// range expansion, reminders and summaries then do with it.
///
/// Extended scheduling is iOS-only, so it is held by these Swift tests alone —
/// plan 019's contract leaves it out of the TypeScript oracle deliberately.
/// `ScheduleRuleFixtureTests` still holds every shared rule, and a plan-free
/// input must keep taking exactly the path it took before: the last test here
/// pins that, and the fixtures prove the rest of it.
@Suite("Extended schedule resolution")
struct ExtendedScheduleRulesTests {
    private static let early = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
    private static let night = UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!
    private static let rest = UUID(uuidString: "00000000-0000-0000-0000-0000000000E3")!
    private static let zoneIdentifier = "Asia/Shanghai"

    // MARK: Fixtures

    private static func shiftType(
        _ id: UUID,
        _ name: String,
        _ kind: ShiftType.Kind,
        start: Int,
        end: Int,
        breakStart: Int = 0,
        breakMinutes: Int = 0,
        archived: Bool = false
    ) -> ShiftType {
        ShiftType(
            id: id, name: name, kind: kind,
            startMinutes: start, endMinutes: end,
            breakEnabled: breakMinutes > 0, breakStartMinutes: breakStart,
            breakDurationMinutes: breakMinutes,
            colorHex: "#F28C28", isArchived: archived
        )
    }

    /// 08:00–16:00 with a half-hour break, so it is 7.5 effective hours and not
    /// the 8 a single planned-daily figure would assume.
    private static var earlyType: ShiftType {
        shiftType(early, "早班", .work, start: 8 * 60, end: 16 * 60, breakStart: 12 * 60, breakMinutes: 30)
    }
    /// 20:00–06:00, ten hours across midnight.
    private static var nightType: ShiftType {
        shiftType(night, "Night", .work, start: 20 * 60, end: 6 * 60)
    }
    private static var restType: ShiftType {
        shiftType(rest, "休息", .rest, start: 0, end: 0, archived: true)
    }

    private static func plan(
        rule: ShiftCycleRule? = nil,
        handSet: [String: UUID] = [:],
        types: [ShiftType]? = nil,
        enabled: Bool = true
    ) -> ExtendedSchedulePlan? {
        let schedule = ExtendedSchedule(
            isEnabled: enabled,
            shiftTypes: types ?? [earlyType, nightType, restType],
            rule: rule,
            timeZoneIdentifier: zoneIdentifier,
            editedAt: Date(timeIntervalSince1970: 1_790_000_000),
            editCount: 1,
            editTieBreaker: UUID()
        )
        let days = handSet.map {
            RosterDay(
                dayKey: $0.key, shiftTypeID: $0.value, timeZoneIdentifier: zoneIdentifier,
                editedAt: Date(timeIntervalSince1970: 1_790_000_060), editCount: 1, editTieBreaker: UUID()
            )
        }
        return ExtendedSchedulePlan(schedule: schedule, rosterDays: days)
    }

    private static func resolver(
        rule: ShiftCycleRule? = nil,
        handSet: [String: UUID] = [:],
        types: [ShiftType]? = nil
    ) throws -> ExtendedScheduleResolver {
        ExtendedScheduleResolver(plan: try #require(plan(rule: rule, handSet: handSet, types: types)))
    }

    private static func dayNumber(_ key: String) throws -> Int {
        let parts = key.split(separator: "-").map { Int($0) }
        try #require(parts.count == 3)
        return CivilZone.dayNumber(
            year: try #require(parts[0]), month: try #require(parts[1]), day: try #require(parts[2])
        )
    }

    private static func resolved(_ resolver: ExtendedScheduleResolver, _ key: String) throws -> ExtendedScheduleDay {
        resolver.day(dayNumber: try dayNumber(key))
    }

    /// An instant built from a civil date, never a raw epoch: the simulator
    /// follows the Mac's zone, so a literal instant lands on a different hour —
    /// and sometimes a different day — on another machine.
    private static func instant(_ key: String, hour: Int, minute: Int = 0) throws -> Double {
        // Unwrapped here rather than inside `DateComponents(year:…)`: its
        // parameters are optional, so a `#require` there checks an `Int??`
        // that can never be nil and lets a malformed key through.
        let parts = try key.split(separator: "-").map { try #require(Int($0)) }
        try #require(parts.count == 3)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zoneIdentifier))
        let date = try #require(calendar.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2],
            hour: hour, minute: minute
        )))
        return date.timeIntervalSince1970 * 1_000
    }

    private static let classicSchedule = NativeWorkSchedule(
        mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
        singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil
    )

    private static func input(
        nowMs: Double,
        plan: ExtendedSchedulePlan?,
        startTime: String = "09:00",
        endTime: String = "17:00",
        workdays: [Int] = [1, 2, 3, 4, 5]
    ) -> NativeRulesInput {
        NativeRulesInput(
            startTime: startTime, endTime: endTime, nowMs: nowMs,
            workdays: workdays, schedule: classicSchedule,
            breakStartTime: nil, breakDurationMinutes: 0, overtimeEndAtMs: nil,
            salaryAmount: "", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 0,
            forcedWorkdayStartMs: nil, timeZoneIdentifier: zoneIdentifier,
            extendedSchedule: plan
        )
    }

    // MARK: The priority chain

    @Test("A day the user set by hand wins over the cycle rule")
    func handSetWinsOverRule() throws {
        let rule = ShiftCycleRule(
            preset: .rotation, anchorDayKey: "2026-10-01", days: [Self.early, Self.early, Self.night, Self.rest]
        )
        let resolver = try Self.resolver(rule: rule, handSet: ["2026-10-02": Self.night])

        let first = try Self.resolved(resolver, "2026-10-01")
        #expect(first.shiftTypeID == Self.early)
        #expect(first.source == .rule)

        let handSet = try Self.resolved(resolver, "2026-10-02")
        #expect(handSet.shiftTypeID == Self.night)
        #expect(handSet.source == .handSet)

        #expect(try Self.resolved(resolver, "2026-10-03").shiftTypeID == Self.night)
        #expect(try Self.resolved(resolver, "2026-10-04").shiftTypeID == Self.rest)
    }

    @Test("The cycle repeats in both directions from its anchor")
    func ruleRepeatsAroundTheAnchor() throws {
        let rule = ShiftCycleRule(
            preset: .rotation, anchorDayKey: "2026-10-01", days: [Self.early, Self.early, Self.night, Self.rest]
        )
        let resolver = try Self.resolver(rule: rule)

        // One day before the anchor is the last day of the cycle, not the first.
        #expect(try Self.resolved(resolver, "2026-09-30").shiftTypeID == Self.rest)
        #expect(try Self.resolved(resolver, "2026-09-29").shiftTypeID == Self.night)
        // And it keeps repeating forward.
        #expect(try Self.resolved(resolver, "2026-10-05").shiftTypeID == Self.early)
        #expect(try Self.resolved(resolver, "2026-10-07").shiftTypeID == Self.night)
    }

    @Test("A month nobody filled in copies the nearest earlier one by day number")
    func monthsCarryOverByDayNumber() throws {
        let resolver = try Self.resolver(handSet: [
            "2026-10-01": Self.early,
            "2026-10-02": Self.night,
            "2026-10-31": Self.early,
        ])

        let november = try Self.resolved(resolver, "2026-11-01")
        #expect(november.shiftTypeID == Self.early)
        #expect(november.source == .carriedOver)
        #expect(try Self.resolved(resolver, "2026-11-02").shiftTypeID == Self.night)
        // October's 3rd was never assigned, so the copy has nothing to carry.
        #expect(try Self.resolved(resolver, "2026-11-03").source == .unassigned)
        // December is not adjacent to October and still copies it, because
        // November was never filled in either.
        #expect(try Self.resolved(resolver, "2026-12-02").shiftTypeID == Self.night)
    }

    @Test("Day numbers the source month does not have are rest")
    func missingDayNumbersAreRest() throws {
        let resolver = try Self.resolver(handSet: [
            "2026-02-01": Self.early,
            "2026-02-28": Self.night,
        ])
        #expect(try Self.resolved(resolver, "2026-03-01").shiftTypeID == Self.early)
        #expect(try Self.resolved(resolver, "2026-03-28").shiftTypeID == Self.night)
        for day in ["2026-03-29", "2026-03-30", "2026-03-31"] {
            let resolved = try Self.resolved(resolver, day)
            #expect(resolved.source == .unassigned)
            #expect(resolved.isWorkday == false)
        }
    }

    @Test("A month the user touched keeps its own unset days on rest")
    func authoredMonthsDoNotBlendWithTheOneBefore() throws {
        let resolver = try Self.resolver(handSet: [
            "2026-10-01": Self.early,
            "2026-10-02": Self.night,
            "2026-11-05": Self.night,
        ])
        #expect(try Self.resolved(resolver, "2026-11-05").source == .handSet)
        // November is authored, so its 1st is rest rather than October's early.
        #expect(try Self.resolved(resolver, "2026-11-01").source == .unassigned)
    }

    @Test("An archived type still resolves and an unknown one does not")
    func archivedAndUnknownTypes() throws {
        let unknown = UUID()
        let resolver = try Self.resolver(handSet: [
            "2026-10-01": Self.rest,
            "2026-10-02": unknown,
        ])
        // Archived: a past day keeps the shift it was actually worked as.
        let archived = try Self.resolved(resolver, "2026-10-01")
        #expect(archived.shiftTypeID == Self.rest)
        #expect(archived.isWorkday == false)
        // Unknown: sync can deliver a day before the type that names it.
        #expect(try Self.resolved(resolver, "2026-10-02").source == .unassigned)
    }

    // MARK: What the rules do with it

    @Test("The countdown runs the shift the extended schedule assigns that day")
    func snapshotUsesTheAssignedShift() throws {
        let plan = Self.plan(handSet: ["2026-10-01": Self.early])
        let snapshot = ScheduleRules.snapshot(input: Self.input(
            nowMs: try Self.instant("2026-10-01", hour: 10), plan: plan
        ))
        #expect(snapshot.isWorkday)
        #expect(snapshot.startAtMs == (try Self.instant("2026-10-01", hour: 8)))
        #expect(snapshot.plannedEndAtMs == (try Self.instant("2026-10-01", hour: 16)))
        // The type's own break splits the day, not the preferences' lunch.
        #expect(snapshot.segments.count == 2)
        #expect(snapshot.durationMs == 7.5 * 3_600_000)
    }

    @Test("A night shift still running after midnight belongs to the day it started")
    func overnightShiftSurvivesMidnight() throws {
        // The fixed-hours path finds a running overnight shift by walking today's
        // own clocks back a day. That cannot work here: today is an early shift.
        let plan = Self.plan(handSet: ["2026-10-03": Self.night, "2026-10-04": Self.early])
        let snapshot = ScheduleRules.snapshot(input: Self.input(
            nowMs: try Self.instant("2026-10-04", hour: 3), plan: plan
        ))
        #expect(snapshot.startAtMs == (try Self.instant("2026-10-03", hour: 20)))
        #expect(snapshot.plannedEndAtMs == (try Self.instant("2026-10-04", hour: 6)))
        #expect(snapshot.isWorkday)
    }

    @Test("A rest day counts down to the next assigned shift")
    func restDayLooksAhead() throws {
        let plan = Self.plan(handSet: ["2026-10-04": Self.rest, "2026-10-05": Self.early])
        let snapshot = ScheduleRules.snapshot(input: Self.input(
            nowMs: try Self.instant("2026-10-04", hour: 10), plan: plan
        ))
        #expect(snapshot.isWorkday == false)
        #expect(snapshot.nextShiftStartAtMs == (try Self.instant("2026-10-05", hour: 8)))
    }

    @Test("Range expansion gives each day the hours it actually works")
    func expansionFollowsTheRoster() throws {
        let configuration = ScheduleHoursConfiguration(
            startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: Self.classicSchedule, breakStartTime: nil, breakDurationMinutes: 0,
            extendedSchedule: Self.plan(handSet: [
                "2026-10-05": Self.early,
                "2026-10-06": Self.night,
                "2026-10-07": Self.rest,
            ])
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: Self.zoneIdentifier))
        let from = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        let through = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7)))
        let days = ScheduleRules.expandScheduleRange(
            configuration: configuration, from: from, through: through, timeZone: calendar.timeZone
        )

        #expect(days.map(\.dayKey) == ["2026-10-05", "2026-10-06", "2026-10-07"])
        #expect(days.map(\.isWorkday) == [true, true, false])
        func effectiveMs(_ day: NativeScheduleDayExpansion) -> Double {
            day.segments.reduce(0) { $0 + $1.endAtMs - $1.startAtMs }
        }
        #expect(effectiveMs(days[0]) == 7.5 * 3_600_000)
        #expect(effectiveMs(days[1]) == 10 * 3_600_000)
    }

    @Test("Reminders follow the assigned shift, not the configured hours")
    func remindersFollowTheAssignedShift() throws {
        let messages = NativeMilestoneMessages(
            milestone50: ["50"], milestone75: ["75"], milestone90: ["90"],
            milestone95: ["95"], milestone100: ["100"]
        )
        let reminderInputs = NativeReminderInputs(
            mode: "all", fallbackTitle: "下班提醒", breakTitle: "休息提醒",
            milestoneTitles: NativeMilestoneTitles(
                milestone50: "50", milestone75: "75", milestone90: "90",
                milestone95: "95", milestone100: "100"
            ),
            milestoneMessages: messages,
            lunchStartEnabled: false, lunchStartBody: "",
            lunchEndEnabled: false, lunchEndBody: "",
            microBreakEnabled: false, microBreakTitle: "", microBreakIntervalMinutes: 0,
            microBreakMessages: [], cycleEndSummaryBody: nil
        )
        let nowMs = try Self.instant("2026-10-03", hour: 21)
        // The same night shift, once assigned by the roster and once configured
        // as fixed hours. The current shift's reminders must be identical.
        let extended = ScheduleRules.reminders(
            input: Self.input(nowMs: nowMs, plan: Self.plan(handSet: [
                "2026-10-03": Self.night, "2026-10-04": Self.early,
            ])),
            reminderInputs: reminderInputs
        )
        let fixed = ScheduleRules.reminders(
            input: Self.input(
                nowMs: nowMs, plan: nil,
                startTime: "20:00", endTime: "06:00", workdays: [0, 1, 2, 3, 4, 5, 6]
            ),
            reminderInputs: reminderInputs
        )
        let current = { (list: [NativeReminder]) in list.filter { $0.id.hasPrefix("current:") } }
        #expect(current(extended).isEmpty == false)
        #expect(current(extended) == current(fixed))
    }

    @Test("A week of mixed shifts reports the hours it actually works")
    func summaryAddsUpEachDaysOwnHours() throws {
        let plan = Self.plan(handSet: [
            "2026-10-05": Self.early,
            "2026-10-06": Self.early,
            "2026-10-07": Self.night,
            "2026-10-08": Self.rest,
            "2026-10-09": Self.rest,
            "2026-10-10": Self.rest,
        ])
        let summary = SummaryRules.summarize(input: NativeSummaryInput(
            period: "week",
            periodStartMs: try Self.instant("2026-10-05", hour: 0),
            asOfMs: try Self.instant("2026-10-10", hour: 12),
            workdays: [1, 2, 3, 4, 5],
            schedule: Self.classicSchedule,
            currentShiftStartMs: try Self.instant("2026-10-10", hour: 9),
            currentShiftEndMs: try Self.instant("2026-10-10", hour: 17),
            plannedDailyHours: 8,
            todayProgress: 0,
            dailySalary: nil,
            todayEffectiveHours: 8,
            todayPayRatio: 0,
            timeZoneIdentifier: Self.zoneIdentifier,
            extendedSchedule: plan
        ))
        #expect(summary.days == 3)
        // 7.5 + 7.5 + 10, not three times the one planned daily figure.
        #expect(abs(summary.hours - 25) < 0.000_1)
    }

    // MARK: The path everyone else is still on

    @Test("A schedule switched off leaves the classic rules exactly as they were")
    func disabledScheduleChangesNothing() throws {
        // A disabled schedule produces no plan at all, so the weekday rules run.
        #expect(Self.plan(handSet: ["2026-10-03": Self.night], enabled: false) == nil)

        let nowMs = try Self.instant("2026-10-05", hour: 10)
        let withoutPlan = ScheduleRules.snapshot(input: Self.input(nowMs: nowMs, plan: nil))
        let disabled = ScheduleRules.snapshot(input: Self.input(
            nowMs: nowMs,
            plan: Self.plan(handSet: ["2026-10-05": Self.night], enabled: false)
        ))
        #expect(disabled == withoutPlan)
        #expect(withoutPlan.startAtMs == (try Self.instant("2026-10-05", hour: 9)))
    }

    // The codec is main-actor isolated, unlike the pure rules above it.
    @MainActor
    @Test("Hours saved before extended scheduling existed still encode unchanged")
    func hoursWithoutAPlanEncodeAsBefore() throws {
        // The configuration is persisted as a schedule snapshot and fingerprinted,
        // so a new field must stay off the wire when nobody uses it.
        let configuration = ScheduleHoursConfiguration(
            startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: Self.classicSchedule, breakStartTime: nil, breakDurationMinutes: 0
        )
        let encoded = try ScheduleHoursCodec.encode(configuration)
        let json = try #require(String(data: encoded.data, encoding: .utf8))
        #expect(json.contains("extendedSchedule") == false)
    }
}
