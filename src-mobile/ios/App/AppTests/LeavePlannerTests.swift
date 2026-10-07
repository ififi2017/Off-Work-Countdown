import Foundation
import Testing
@testable import App

@Suite("Leave planner")
struct LeavePlannerTests {
    private static let shanghai = "Asia/Shanghai"
    private static let office = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private static let rest = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    private static let night = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
    private static let annual = UUID(uuidString: "00000000-0000-0000-0000-000000000211")!
    private static let inLieu = UUID(uuidString: "00000000-0000-0000-0000-000000000212")!

    private static let officeType = ShiftType(
        id: office, name: "Office", kind: .work,
        startMinutes: 9 * 60, endMinutes: 18 * 60,
        breakEnabled: true, breakStartMinutes: 12 * 60, breakDurationMinutes: 60,
        colorHex: "#FF7A00", isArchived: false
    )
    private static let restType = ShiftType(
        id: rest, name: "Rest", kind: .rest,
        startMinutes: 9 * 60, endMinutes: 18 * 60,
        breakEnabled: false, breakStartMinutes: 12 * 60, breakDurationMinutes: 0,
        colorHex: "#777777", isArchived: false
    )
    private static let nightType = ShiftType(
        id: night, name: "Night", kind: .work,
        startMinutes: 22 * 60, endMinutes: 6 * 60,
        breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
        colorHex: "#3366FF", isArchived: false
    )
    private static let classicSchedule = NativeWorkSchedule(
        mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
        singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil
    )

    // MARK: - Fixtures

    private static func dayNumber(_ key: String) throws -> Int {
        try #require(ExtendedScheduleResolver.dayNumber(dayKey: key))
    }

    private static func instant(_ key: String, hour: Int, minute: Int = 0, zone: String = shanghai) throws -> Double {
        let parts = try key.split(separator: "-").map { try #require(Int($0)) }
        try #require(parts.count == 3)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let date = try #require(calendar.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute
        )))
        return date.timeIntervalSince1970 * 1_000
    }

    /// Monday–Friday of `workType`, weekends off, optionally on a holiday region.
    private static func weeklyPlan(
        workType: ShiftType = officeType,
        region: String? = nil,
        handSet: [String: UUID] = [:]
    ) -> ExtendedSchedulePlan {
        ExtendedSchedulePlan(
            shiftTypes: [workType, restType],
            rule: ShiftCycleRule(
                preset: .weekly, anchorDayKey: "2026-09-21",
                days: [workType.id, workType.id, workType.id, workType.id, workType.id, rest, rest]
            ),
            handSetDays: handSet,
            holidayRegionIdentifier: region
        )
    }

    private static func configuration(plan: ExtendedSchedulePlan?) -> ScheduleHoursConfiguration {
        ScheduleHoursConfiguration(
            startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: classicSchedule, breakStartTime: nil, breakDurationMinutes: 0,
            extendedSchedule: plan
        )
    }

    private static func proposals(
        plan: ExtendedSchedulePlan?,
        goal: LeavePlanner.Goal,
        from: String,
        through: String,
        now: Double,
        budgets: [LeaveBudget],
        zone: String = shanghai
    ) throws -> [LeavePlanProposal] {
        let range = try dayNumber(from)...dayNumber(through)
        let days = LeavePlannerSchedule.days(
            configuration: configuration(plan: plan),
            range: range,
            timeZone: try #require(TimeZone(identifier: zone))
        )
        return LeavePlanner.proposals(days: days, query: .init(
            goal: goal, fromDayNumber: range.lowerBound, throughDayNumber: range.upperBound,
            nowMs: now, budgets: budgets
        ))
    }

    private static func budget(
        _ id: UUID = annual, halfDays: Int, from: String? = nil, through: String? = nil
    ) throws -> LeaveBudget {
        LeaveBudget(
            id: id, availableHalfDays: halfDays,
            validFromDayNumber: try from.map(dayNumber),
            validThroughDayNumber: try through.map(dayNumber)
        )
    }

    // MARK: - Halves

    @Test("Halves split effective time and skip the break")
    func halvesSkipTheBreak() throws {
        let segments = [
            NativeShiftSegment(startAtMs: try Self.instant("2026-09-24", hour: 9), endAtMs: try Self.instant("2026-09-24", hour: 12)),
            NativeShiftSegment(startAtMs: try Self.instant("2026-09-24", hour: 13), endAtMs: try Self.instant("2026-09-24", hour: 18)),
        ]
        let halves = LeaveShiftHalves(segments: segments)
        #expect(halves.first == [
            segments[0],
            NativeShiftSegment(startAtMs: try Self.instant("2026-09-24", hour: 13), endAtMs: try Self.instant("2026-09-24", hour: 14)),
        ])
        #expect(halves.second == [
            NativeShiftSegment(startAtMs: try Self.instant("2026-09-24", hour: 14), endAtMs: try Self.instant("2026-09-24", hour: 18)),
        ])
        #expect(halves.remaining(after: .firstHalf) == halves.second)
        #expect(halves.remaining(after: .whole).isEmpty)
    }

    // MARK: - Mid-Autumn and National Day 2026

    @Test("Three days bridge Mid-Autumn to National Day for thirteen off")
    func midAutumnBridge() throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"), goal: .restAtLeast(days: 13),
            from: "2026-09-21", through: "2026-10-31",
            now: try Self.instant("2026-09-20", hour: 10),
            budgets: [try Self.budget(halfDays: 20)]
        )
        let best = try #require(result.first)
        #expect(best.firstRestDayKey == "2026-09-25")
        #expect(best.lastRestDayKey == "2026-10-07")
        #expect(best.fullRestDays == 13)
        #expect(best.costHalfDays == 6)
        #expect(best.items.map(\.dayKey) == ["2026-09-28", "2026-09-29", "2026-09-30"])
        #expect(best.items.allSatisfy { $0.portion == .whole && $0.role == .bridge })
        #expect(best.dayKinds == Array(repeating: .holiday, count: 3) + Array(repeating: .leave, count: 3)
            + Array(repeating: .holiday, count: 7))
        #expect(best.lastShiftEndAtMs == (try Self.instant("2026-09-24", hour: 18)))
        #expect(best.nextShiftStartAtMs == (try Self.instant("2026-10-08", hour: 9)))
        #expect(best.uses == [LeaveBudgetUse(budgetID: Self.annual, halfDays: 6)])
        #expect(best.caveats.isEmpty)
    }

    @Test("Seven days off during National Day costs nothing")
    func nationalDayAloneIsFree() throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"), goal: .restAtLeast(days: 7),
            from: "2026-09-21", through: "2026-10-31",
            now: try Self.instant("2026-09-20", hour: 10),
            budgets: [try Self.budget(halfDays: 20)]
        )
        let best = try #require(result.first)
        #expect(best.firstRestDayKey == "2026-10-01")
        #expect(best.lastRestDayKey == "2026-10-07")
        #expect(best.costHalfDays == 0)
        // A shorter plan inside this free week adds no alternative.
        #expect(!result.dropFirst().contains {
            $0.firstRestDayNumber >= best.firstRestDayNumber && $0.lastRestDayNumber <= best.lastRestDayNumber
        })
    }

    @Test("Shared weekends preserve every weekly nine-day alternative", arguments: [false, true])
    func overlappingWeeklyAlternatives(budgetGoal: Bool) throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"),
            goal: budgetGoal ? .leaveAtMost(halfDays: 10) : .restAtLeast(days: 9),
            from: "2026-10-05", through: "2026-12-06",
            now: try Self.instant("2026-10-05", hour: 8),
            budgets: [try Self.budget(halfDays: 10)]
        )
        for (start, end) in [
            ("2026-10-17", "2026-10-25"), ("2026-10-24", "2026-11-01"),
            ("2026-10-31", "2026-11-08"), ("2026-11-07", "2026-11-15"),
            ("2026-11-14", "2026-11-22"), ("2026-11-21", "2026-11-29"),
            ("2026-11-28", "2026-12-06"),
        ] {
            let plan = try #require(result.first { $0.firstRestDayKey == start && $0.lastRestDayKey == end })
            #expect(plan.fullRestDays == 9)
            #expect(plan.costHalfDays == 10)
            #expect(plan.items.count == 5)
        }
        #expect(result.count > 5)
        let ranges = result.map { "\($0.firstRestDayKey)/\($0.lastRestDayKey)" }
        #expect(Set(ranges).count == result.count)
        let best = result.filter { $0.fullRestDays == 9 && $0.costHalfDays == 10 }
        #expect(best.map(\.firstRestDayNumber) == best.map(\.firstRestDayNumber).sorted())
    }

    @Test("A spare half day leaves early on the last working afternoon")
    func spareHalfDayLeavesEarly() throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"), goal: .leaveAtMost(halfDays: 7),
            from: "2026-09-21", through: "2026-10-31",
            now: try Self.instant("2026-09-20", hour: 10),
            budgets: [try Self.budget(halfDays: 20)]
        )
        let best = try #require(result.first)
        #expect(best.firstRestDayKey == "2026-09-25")
        #expect(best.lastRestDayKey == "2026-10-07")
        #expect(best.bridgeHalfDays == 6)
        #expect(best.costHalfDays == 7)
        let early = try #require(best.items.first)
        #expect(early.dayKey == "2026-09-24")
        #expect(early.portion == .secondHalf)
        #expect(early.role == .earlyDeparture)
        #expect(early.segments == [NativeShiftSegment(
            startAtMs: try Self.instant("2026-09-24", hour: 14), endAtMs: try Self.instant("2026-09-24", hour: 18)
        )])
        #expect(best.lastShiftEndAtMs == (try Self.instant("2026-09-24", hour: 14)))
    }

    @Test("A makeup Saturday is not a free day off")
    func makeupSaturdayCostsLeave() throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"), goal: .restAtLeast(days: 2),
            from: "2026-10-08", through: "2026-10-18",
            now: try Self.instant("2026-09-20", hour: 10),
            budgets: [try Self.budget(halfDays: 20)]
        )
        let best = try #require(result.first)
        #expect(best.firstRestDayKey == "2026-10-17")
        #expect(best.costHalfDays == 0)
        let makeupDay = try Self.dayNumber("2026-10-10")
        for proposal in result where (proposal.firstRestDayNumber...proposal.lastRestDayNumber).contains(makeupDay) {
            #expect(proposal.items.contains { $0.dayKey == "2026-10-10" })
        }
    }

    @Test("A holiday the roster still works has to be taken as leave")
    func workedHolidayNeedsLeave() throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN", handSet: ["2026-10-03": Self.office]),
            goal: .restAtLeast(days: 7),
            from: "2026-09-21", through: "2026-10-31",
            now: try Self.instant("2026-09-20", hour: 10),
            budgets: [try Self.budget(halfDays: 20)]
        )
        let best = try #require(result.first)
        #expect(best.firstRestDayKey == "2026-10-01")
        #expect(best.lastRestDayKey == "2026-10-07")
        #expect(best.items.map(\.dayKey) == ["2026-10-03"])
        #expect(best.costHalfDays == 2)
    }

    // MARK: - Balances

    @Test("Leave is spent from the balance that expires first")
    func earliestExpiryFirst() throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"), goal: .restAtLeast(days: 13),
            from: "2026-09-21", through: "2026-10-31",
            now: try Self.instant("2026-09-20", hour: 10),
            budgets: [
                try Self.budget(Self.inLieu, halfDays: 4),
                try Self.budget(Self.annual, halfDays: 4, through: "2026-09-29"),
            ]
        )
        let best = try #require(result.first)
        #expect(best.fullRestDays == 13)
        #expect(best.items.map(\.uses) == [
            [LeaveBudgetUse(budgetID: Self.annual, halfDays: 2)],
            [LeaveBudgetUse(budgetID: Self.annual, halfDays: 2)],
            [LeaveBudgetUse(budgetID: Self.inLieu, halfDays: 2)],
        ])
        #expect(best.uses == [
            LeaveBudgetUse(budgetID: Self.inLieu, halfDays: 2),
            LeaveBudgetUse(budgetID: Self.annual, halfDays: 4),
        ])
    }

    @Test("An expired balance cannot pay for later days")
    func expiredBalanceIsNotSpent() throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"), goal: .restAtLeast(days: 13),
            from: "2026-09-21", through: "2026-10-31",
            now: try Self.instant("2026-09-20", hour: 10),
            budgets: [
                try Self.budget(Self.inLieu, halfDays: 4),
                try Self.budget(Self.annual, halfDays: 4, through: "2026-09-27"),
            ]
        )
        #expect(result.isEmpty)
    }

    @Test("Three and a half days are seven half days")
    func halfDayBalance() throws {
        var balance = LeaveBalance(
            id: Self.annual, kind: .annual, name: nil,
            entitledHalfDays: 10, usedHalfDays: 3,
            validFromDayKey: nil, validThroughDayKey: "2027-03-31"
        )
        #expect(balance.remainingHalfDays == 7)
        #expect(balance.budget(adoptedHalfDays: 2)?.availableHalfDays == 5)
        #expect(balance.budget()?.validThroughDayNumber == (try Self.dayNumber("2027-03-31")))
        balance.validThroughDayKey = "2027-02-30"
        #expect(!balance.isValid)
        balance.validThroughDayKey = nil
        balance.kind = .custom
        #expect(!balance.isValid)
        balance.name = "Marriage leave"
        #expect(balance.isValid)
    }

    // MARK: - Time

    @Test("A shift that has started cannot be taken off")
    func startedShiftStays() throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"), goal: .restAtLeast(days: 13),
            from: "2026-09-28", through: "2026-10-31",
            now: try Self.instant("2026-09-28", hour: 10),
            budgets: [try Self.budget(halfDays: 20)]
        )
        // Today's shift is under way, so thirteen days now start tomorrow and
        // reach past National Day through the makeup Saturday instead.
        let best = try #require(result.first)
        #expect(best.firstRestDayKey == "2026-09-29")
        #expect(best.lastRestDayKey == "2026-10-11")
        #expect(best.items.map(\.dayKey) == ["2026-09-29", "2026-09-30", "2026-10-08", "2026-10-09", "2026-10-10"])
        #expect(!result.contains { $0.items.contains { $0.dayKey == "2026-09-28" } })
    }

    @Test("Half an overnight shift frees the evening it starts")
    func overnightHalfShift() throws {
        let result = try Self.proposals(
            plan: Self.weeklyPlan(workType: Self.nightType), goal: .restAtLeast(days: 2),
            from: "2026-10-05", through: "2026-10-25",
            now: try Self.instant("2026-10-01", hour: 10),
            budgets: [try Self.budget(halfDays: 20)]
        )
        let best = try #require(result.first)
        // Saturday still carries Friday night's shift until 06:00, so the
        // cheap pair is Sunday plus Monday, whose shift starts at 22:00.
        #expect(best.firstRestDayKey == "2026-10-11")
        #expect(best.lastRestDayKey == "2026-10-12")
        #expect(best.items.map(\.portion) == [.firstHalf])
        #expect(best.items.map(\.dayKey) == ["2026-10-12"])
        #expect(best.lastShiftEndAtMs == (try Self.instant("2026-10-10", hour: 6)))
        #expect(best.nextShiftStartAtMs == (try Self.instant("2026-10-13", hour: 2)))
    }

    @Test("Across a DST change days are civil days, not 24 hours")
    func daylightSavingWeekend() throws {
        let zone = "America/New_York"
        let range = try Self.dayNumber("2026-10-26")...Self.dayNumber("2026-11-15")
        let days = LeavePlannerSchedule.days(
            configuration: Self.configuration(plan: nil), range: range,
            timeZone: try #require(TimeZone(identifier: zone))
        )
        let fallBack = try #require(days.first { $0.dayKey == "2026-11-01" })
        #expect(fallBack.endAtMs - fallBack.startAtMs == 25 * 3_600_000)

        let weekend = try Self.proposals(
            plan: nil, goal: .restAtLeast(days: 2), from: "2026-10-26", through: "2026-11-15",
            now: try Self.instant("2026-10-20", hour: 10, zone: zone),
            budgets: [try Self.budget(halfDays: 20)], zone: zone
        )
        #expect(weekend.first?.firstRestDayKey == "2026-10-31")
        #expect(weekend.first?.lastRestDayKey == "2026-11-01")
        #expect(weekend.first?.costHalfDays == 0)

        let nine = try Self.proposals(
            plan: nil, goal: .restAtLeast(days: 9), from: "2026-10-26", through: "2026-11-15",
            now: try Self.instant("2026-10-20", hour: 10, zone: zone),
            budgets: [try Self.budget(halfDays: 20)], zone: zone
        )
        #expect(nine.first?.fullRestDays == 9)
        #expect(nine.first?.costHalfDays == 10)
    }

    // MARK: - Planning window and data coverage

    @Test("The planning year rolls from today and never stops at New Year")
    func rollingYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: Self.shanghai))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 15)))
        #expect(LeavePlannerSchedule.rollingYear(containing: today, calendar: calendar)
            == (try Self.dayNumber("2026-09-27"))...(try Self.dayNumber("2027-09-26")))
        let leapDay = try #require(calendar.date(from: DateComponents(year: 2028, month: 2, day: 29, hour: 8)))
        #expect(LeavePlannerSchedule.rollingYear(containing: leapDay, calendar: calendar)
            == (try Self.dayNumber("2028-02-29"))...(try Self.dayNumber("2029-02-27")))
    }

    @Test("A year this build has no holidays for follows the ordinary schedule")
    func uncoveredYearUsesTheRoster() throws {
        let range = try Self.dayNumber("2027-12-20")...Self.dayNumber("2028-01-31")
        let days = LeavePlannerSchedule.days(
            configuration: Self.configuration(plan: Self.weeklyPlan(region: "CN")), range: range,
            timeZone: try #require(TimeZone(identifier: Self.shanghai))
        )
        let newYearsEve = try #require(days.first { $0.dayKey == "2027-12-31" })
        let newYearsDay = try #require(days.first { $0.dayKey == "2028-01-03" })
        #expect(newYearsEve.caveats == [.holidaysEstimated(year: 2027)])
        // An uncovered Monday follows the roster; no holiday is guessed.
        #expect(!newYearsDay.segments.isEmpty)
        #expect(!newYearsDay.isHoliday)
        #expect(newYearsDay.caveats == [.holidaysNotIncluded(year: 2028)])

        let covered = LeavePlannerSchedule.days(
            configuration: Self.configuration(plan: Self.weeklyPlan(region: "CN")), range: range,
            timeZone: try #require(TimeZone(identifier: Self.shanghai)),
            holidayCoverage: { _, _ in true }, holidayEstimation: { _, _ in false }
        )
        #expect(covered.allSatisfy { $0.caveats.isEmpty })

        let proposals = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"), goal: .restAtLeast(days: 9),
            from: "2028-01-04", through: "2028-01-31",
            now: try Self.instant("2027-12-20", hour: 10),
            budgets: [try Self.budget(halfDays: 20)]
        )
        let best = try #require(proposals.first)
        #expect(best.costHalfDays == 10)
        #expect(best.caveats == [.holidaysNotIncluded(year: 2028)])
    }

    @Test("Predicted holidays drive planning with a distinct warning, including makeup days")
    func predictedHolidaysAreIncludedAndLabelled() throws {
        let range = try Self.dayNumber("2027-02-01")...Self.dayNumber("2027-02-20")
        let configuration = Self.configuration(plan: Self.weeklyPlan(region: "CN"))
        let zone = try #require(TimeZone(identifier: Self.shanghai))
        let days = LeavePlannerSchedule.days(configuration: configuration, range: range, timeZone: zone)
        let first = try #require(days.first { $0.dayKey == "2027-02-05" })
        #expect(first.segments.isEmpty && first.isHoliday)
        #expect(first.caveats == [.holidaysEstimated(year: 2027)])
        let makeup = try #require(days.first { $0.dayKey == "2027-02-14" })
        #expect(!makeup.segments.isEmpty && !makeup.isHoliday)
        #expect(makeup.caveats == [.holidaysEstimated(year: 2027)])
        let proposals = try Self.proposals(
            plan: Self.weeklyPlan(region: "CN"), goal: .restAtLeast(days: 9),
            from: "2027-02-05", through: "2027-02-13", now: Self.instant("2027-02-01", hour: 10),
            budgets: [Self.budget(halfDays: 20)]
        )
        let best = try #require(proposals.first)
        #expect(best.fullRestDays == 9 && best.costHalfDays == 0)
        #expect(best.caveats == [.holidaysEstimated(year: 2027)])
        let official = LeavePlannerSchedule.days(
            configuration: configuration, range: range, timeZone: zone,
            holidayEstimation: { _, _ in false }
        )
        #expect(official.allSatisfy { $0.caveats.isEmpty })
        let disabled = LeavePlannerSchedule.days(
            configuration: Self.configuration(plan: Self.weeklyPlan()), range: range, timeZone: zone
        )
        #expect(disabled.allSatisfy { $0.caveats.isEmpty })
        #expect(!(try #require(disabled.first { $0.dayKey == "2027-02-05" })).segments.isEmpty)
        let handSet = LeavePlannerSchedule.days(
            configuration: Self.configuration(plan: Self.weeklyPlan(region: "CN", handSet: ["2027-02-05": Self.office])),
            range: range, timeZone: zone
        )
        #expect(!(try #require(handSet.first { $0.dayKey == "2027-02-05" })).segments.isEmpty)
    }

    @Test("Adopted leave over fixed hours is not an estimate")
    func leaveOverFixedHoursIsKnown() throws {
        let plan = ExtendedSchedulePlan.applying(
            leave: ["2026-10-12": .whole], to: nil,
            baseHours: ExtendedScheduleDayHours(startTime: "09:00", endTime: "17:00", breakStartTime: nil, breakDurationMinutes: 0),
            revision: 0
        )
        let days = LeavePlannerSchedule.days(
            configuration: Self.configuration(plan: plan),
            range: try Self.dayNumber("2026-10-01")...Self.dayNumber("2026-10-31"),
            timeZone: try #require(TimeZone(identifier: Self.shanghai))
        )
        #expect(days.allSatisfy { $0.caveats.isEmpty })
        #expect(try #require(days.first { $0.dayKey == "2026-10-12" }).segments.isEmpty)
        #expect(!(try #require(days.first { $0.dayKey == "2026-10-13" }).segments.isEmpty))
    }

    @Test("A whole rolling year is searched for both goals")
    func wholeYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: Self.shanghai))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 8)))
        let range = try #require(LeavePlannerSchedule.rollingYear(containing: today, calendar: calendar))
        let days = LeavePlannerSchedule.days(
            configuration: Self.configuration(plan: Self.weeklyPlan(region: "CN")),
            range: range, timeZone: calendar.timeZone
        )
        let budgets = [try Self.budget(halfDays: 30)]
        for goal in [LeavePlanner.Goal.restAtLeast(days: 10), .leaveAtMost(halfDays: 30)] {
            let result = LeavePlanner.proposals(days: days, query: .init(
                goal: goal, fromDayNumber: range.lowerBound, throughDayNumber: range.upperBound,
                nowMs: today.timeIntervalSince1970 * 1_000, budgets: budgets
            ))
            #expect(!result.isEmpty)
            #expect(result.allSatisfy { $0.costHalfDays <= 30 })
            #expect(result.allSatisfy { range.contains($0.firstRestDayNumber) && range.contains($0.lastRestDayNumber) })
        }
    }
}
