import Foundation
import Testing
@testable import App

/// Plan 020 P2b: adopted leave in the live rules (countdown, reminders,
/// summaries, the Watch) and as a Records layer, over both a fixed schedule
/// and an extended one.
@Suite("Leave in the schedule")
struct LeaveScheduleTests {
    private static let zone = "Asia/Shanghai"
    private static let office = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private static let rest = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
    private static let classicSchedule = NativeWorkSchedule(
        mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
        singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil
    )
    private static let fixedHours = ExtendedScheduleDayHours(
        startTime: "09:00", endTime: "18:00", breakStartTime: "12:00", breakDurationMinutes: 60
    )
    /// Wednesday off, Thursday's morning off, Friday's afternoon off, and a
    /// half day on Saturday, which the schedule already rests.
    private static let leave: [String: LeavePortion] = [
        "2026-10-14": .whole, "2026-10-15": .firstHalf, "2026-10-16": .secondHalf, "2026-10-17": .firstHalf,
    ]

    private static func instant(_ key: String, hour: Int, minute: Int = 0) throws -> Double {
        let parts = try key.split(separator: "-").map { try #require(Int($0)) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let date = try #require(calendar.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute
        )))
        return date.timeIntervalSince1970 * 1_000
    }

    private static func segment(_ key: String, _ from: Int, _ to: Int) throws -> NativeShiftSegment {
        NativeShiftSegment(startAtMs: try instant(key, hour: from), endAtMs: try instant(key, hour: to))
    }

    private static func input(nowMs: Double, plan: ExtendedSchedulePlan?) -> NativeRulesInput {
        NativeRulesInput(
            startTime: "09:00", endTime: "18:00", nowMs: nowMs,
            workdays: [1, 2, 3, 4, 5], schedule: classicSchedule,
            breakStartTime: "12:00", breakDurationMinutes: 60, overtimeEndAtMs: nil,
            salaryAmount: "", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 0,
            forcedWorkdayStartMs: nil, timeZoneIdentifier: zone, extendedSchedule: plan
        )
    }

    private static var fixedPlan: ExtendedSchedulePlan? {
        ExtendedSchedulePlan.applying(leave: leave, to: nil, baseHours: fixedHours, revision: 1)
    }

    private static var extendedPlan: ExtendedSchedulePlan? {
        let officeType = ShiftType(
            id: office, name: "Office", kind: .work, startMinutes: 9 * 60, endMinutes: 18 * 60,
            breakEnabled: true, breakStartMinutes: 12 * 60, breakDurationMinutes: 60,
            colorHex: "#FF7A00", isArchived: false
        )
        let restType = ShiftType(
            id: rest, name: "Rest", kind: .rest, startMinutes: 0, endMinutes: 0,
            breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
            colorHex: "#777777", isArchived: false
        )
        let plan = ExtendedSchedulePlan(
            shiftTypes: [officeType, restType],
            rule: ShiftCycleRule(preset: .weekly, anchorDayKey: "2026-10-12",
                                 days: [office, office, office, office, office, rest, rest]),
            handSetDays: [:]
        )
        return ExtendedSchedulePlan.applying(leave: leave, to: plan, baseHours: fixedHours, revision: 2)
    }

    // MARK: - Halves

    @Test("The remaining half keeps its share of the break",
          arguments: [
            // Break before the midpoint: the split moves past it.
            ("09:00", "18:00", "12:00", 60, "14:00", "18:00", nil as String?, "09:00", "14:00", "12:00" as String?),
            // Break after the midpoint stays with the afternoon.
            ("08:00", "17:00", "13:00", 60, "12:00", "17:00", "13:00", "08:00", "12:00", nil),
            // Break exactly at the midpoint belongs to neither half.
            ("08:00", "17:00", "12:00", 60, "13:00", "17:00", nil, "08:00", "12:00", nil),
            // Overnight, no break.
            ("22:00", "06:00", nil, 0, "02:00", "06:00", nil, "22:00", "02:00", nil),
          ])
    func remainingHalves(
        start: String, end: String, breakStart: String?, breakMinutes: Int,
        afterMorningStart: String, afterMorningEnd: String, afterMorningBreak: String?,
        afterAfternoonStart: String, afterAfternoonEnd: String, afterAfternoonBreak: String?
    ) throws {
        let hours = ExtendedScheduleDayHours(
            startTime: start, endTime: end, breakStartTime: breakStart, breakDurationMinutes: breakMinutes
        )
        #expect(hours.remaining(after: .whole) == nil)
        let morningOff = try #require(hours.remaining(after: .firstHalf))
        #expect(morningOff.startTime == afterMorningStart)
        #expect(morningOff.endTime == afterMorningEnd)
        #expect(morningOff.breakStartTime == afterMorningBreak)
        let afternoonOff = try #require(hours.remaining(after: .secondHalf))
        #expect(afternoonOff.startTime == afterAfternoonStart)
        #expect(afternoonOff.endTime == afterAfternoonEnd)
        #expect(afternoonOff.breakStartTime == afterAfternoonBreak)
    }

    // MARK: - Live rules

    @Test("No leave keeps the plan exactly as it was")
    func noLeaveKeepsThePlan() {
        #expect(ExtendedSchedulePlan.applying(leave: [:], to: nil, baseHours: Self.fixedHours, revision: 1) == nil)
        let plan = ExtendedSchedulePlan(shiftTypes: [], rule: nil, handSetDays: [:], revision: 7)
        #expect(ExtendedSchedulePlan.applying(leave: [:], to: plan, baseHours: Self.fixedHours, revision: 8) == plan)
    }

    @Test("Leave changes the countdown on a fixed and on an extended schedule",
          arguments: ["fixed", "extended"])
    func countdown(kind: String) throws {
        let plan = kind == "fixed" ? Self.fixedPlan : Self.extendedPlan

        // After Tuesday's shift, Wednesday is off and Thursday starts at 14:00.
        let tuesdayEvening = ScheduleRules.snapshot(input: Self.input(nowMs: try Self.instant("2026-10-13", hour: 20), plan: plan))
        #expect(tuesdayEvening.nextShiftStartAtMs == (try Self.instant("2026-10-15", hour: 14)))

        let wednesday = ScheduleRules.snapshot(input: Self.input(nowMs: try Self.instant("2026-10-14", hour: 10), plan: plan))
        #expect(!wednesday.isWorkday)
        #expect(wednesday.countdownTargetAtMs == (try Self.instant("2026-10-15", hour: 14)))

        let thursday = ScheduleRules.snapshot(input: Self.input(nowMs: try Self.instant("2026-10-15", hour: 15), plan: plan))
        #expect(thursday.isWorkday)
        #expect(thursday.segments == [try Self.segment("2026-10-15", 14, 18)])

        let friday = ScheduleRules.snapshot(input: Self.input(nowMs: try Self.instant("2026-10-16", hour: 10), plan: plan))
        #expect(friday.segments == [try Self.segment("2026-10-16", 9, 12), try Self.segment("2026-10-16", 13, 14)])
        #expect(friday.endAtMs == (try Self.instant("2026-10-16", hour: 14)))

        // Leave never turns a rest day into work.
        let saturday = ScheduleRules.snapshot(input: Self.input(nowMs: try Self.instant("2026-10-17", hour: 10), plan: plan))
        #expect(!saturday.isWorkday)
        #expect(saturday.nextShiftStartAtMs == (try Self.instant("2026-10-19", hour: 9)))
    }

    @Test("Reminders and the Widget skip a day off")
    func remindersAndWidget() throws {
        let messages = NativeMilestoneMessages(
            milestone50: ["50"], milestone75: ["75"], milestone90: ["90"], milestone95: ["95"], milestone100: ["100"]
        )
        let reminderInputs = NativeReminderInputs(
            mode: "all", fallbackTitle: "Off", breakTitle: "Break",
            milestoneTitles: NativeMilestoneTitles(
                milestone50: "50", milestone75: "75", milestone90: "90", milestone95: "95", milestone100: "100"
            ),
            milestoneMessages: messages,
            lunchStartEnabled: false, lunchStartBody: "",
            lunchEndEnabled: false, lunchEndBody: "",
            microBreakEnabled: false, microBreakTitle: "", microBreakIntervalMinutes: 0,
            microBreakMessages: [], cycleEndSummaryBody: nil
        )
        let wednesdayMorning = Self.input(nowMs: try Self.instant("2026-10-14", hour: 8), plan: Self.fixedPlan)
        // The rules list the resting day's own shift too, as on any rest day;
        // the scheduler drops it. The next shift is Thursday afternoon.
        let reminders = ScheduleRules.reminders(input: wednesdayMorning, reminderInputs: reminderInputs)
        let thursdayEnd = JavaScriptNumber.string(try Self.instant("2026-10-15", hour: 18))
        let next = reminders.filter { $0.id.hasPrefix("next:") }
        #expect(!next.isEmpty)
        #expect(next.allSatisfy { $0.id.hasPrefix("next:\(thursdayEnd):") })
        let thursdayStart = try Self.instant("2026-10-15", hour: 14)
        #expect(next.allSatisfy { $0.atMs > thursdayStart })

        let shifts = ScheduleRules.widgetShifts(input: wednesdayMorning, throughMs: try Self.instant("2026-10-20", hour: 0), maximumCount: 4)
        #expect(shifts.map(\.startAtMs) == [
            try Self.instant("2026-10-15", hour: 14),
            try Self.instant("2026-10-16", hour: 9),
            try Self.instant("2026-10-19", hour: 9),
            try Self.instant("2026-10-20", hour: 9),
        ])
    }

    @Test("A week summary counts leave days short on both kinds of schedule",
          arguments: ["fixed", "extended"])
    func weekSummary(kind: String) throws {
        let summary = SummaryRules.summarize(input: NativeSummaryInput(
            period: "week",
            periodStartMs: try Self.instant("2026-10-12", hour: 0),
            asOfMs: try Self.instant("2026-10-17", hour: 12),
            workdays: [1, 2, 3, 4, 5],
            schedule: Self.classicSchedule,
            currentShiftStartMs: try Self.instant("2026-10-16", hour: 9),
            currentShiftEndMs: try Self.instant("2026-10-16", hour: 14),
            plannedDailyHours: 8,
            todayProgress: 0,
            dailySalary: nil,
            todayEffectiveHours: 0,
            todayPayRatio: 0,
            timeZoneIdentifier: Self.zone,
            extendedSchedule: kind == "fixed" ? Self.fixedPlan : Self.extendedPlan
        ))
        // Monday and Tuesday in full, Wednesday off, four hours each on
        // Thursday and Friday.
        #expect(summary.days == 4)
        #expect(abs(summary.hours - 24) < 0.000_1)
    }

    // MARK: - Watch

    @Test("The Watch needs schedule schema 6 for leave and shows the day off")
    func watchContract() throws {
        let configuration = ScheduleRuleInput(
            startTime: "09:00", endTime: "18:00", nowMs: 0, workdays: [1, 2, 3, 4, 5],
            schedule: Self.classicSchedule, breakStartTime: "12:00", breakDurationMinutes: 60,
            overtimeEndAtMs: nil, forcedWorkdayStartMs: nil, timeZoneIdentifier: Self.zone,
            extendedSchedule: Self.fixedPlan
        )
        let schedule = WatchScheduleV2(
            configuration: configuration, automaticallyRuns: true, isConfigured: true,
            currentShift: nil, currentUntilMs: 0,
            presentation: .init(localeIdentifier: "en", timeZoneIdentifier: Self.zone, workingLabel: "Working",
                                lunchLabel: "Break", restingLabel: "Rest", overtimeLabel: "Overtime", finishedLabel: "Finished")
        )
        #expect(schedule.usesLeave)
        #expect(schedule.isValid)
        func package(_ version: Int) -> WatchSnapshotPackageV1 {
            .init(schemaVersion: version, sourceGeneration: "phone", revision: 1,
                  generatedAtMs: 1_780_000_000_000, expiresAtMs: WatchSnapshotContract.maximumJSONTimestamp,
                  access: .init(schemaVersion: 1, revision: 0, verifiedAtMs: 0, status: .free, validUntilMs: nil),
                  content: nil, schedule: schedule)
        }
        #expect(WatchSnapshotContract.scheduleSchemaVersion == 6)
        #expect(!package(5).isValid)
        let current = package(6)
        #expect(current.isValid)
        let decoded = try WatchSnapshotDecoderV1.decode(JSONEncoder().encode(current))
        #expect(decoded.schedule?.configuration.extendedSchedule?.leaveDays == Self.leave)

        guard case .content(let wednesday) = WatchDisplayProjection.project(
            decoded, nowMs: Int64(try Self.instant("2026-10-14", hour: 10))
        ) else { Issue.record("The Watch must still read a day off"); return }
        #expect(wednesday.phase == nil)
        #expect(wednesday.nextShiftStartAtMs == Int64(try Self.instant("2026-10-15", hour: 14)))
    }

    // MARK: - Records

    private static func resolution(
        _ dayKey: String,
        leave: [LeaveDay],
        overrides: [DayOverride] = [],
        exceptions: [CalendarException] = []
    ) throws -> DayResolution {
        let day = Date(timeIntervalSince1970: try instant(dayKey, hour: 0) / 1_000)
        let period = CareerPeriod(
            id: UUID(), startsOn: Date(timeIntervalSince1970: try instant("2026-01-01", hour: 0) / 1_000),
            endsBefore: nil, label: nil, timeZoneIdentifier: zone, calendarIdentifier: "gregorian",
            createdAt: .distantPast, editedAt: .distantPast, editCount: 1, editTieBreaker: UUID()
        )
        let snapshot = ScheduleSnapshot(
            id: UUID(), periodID: period.id, effectiveFrom: period.startsOn,
            configurationData: Data(), fingerprint: "", editedAt: .distantPast, editCount: 1, editTieBreaker: UUID()
        )
        let expansion = ScheduleExpansion(
            isWorkday: true, segments: [try segment(dayKey, 9, 12), try segment(dayKey, 13, 18)]
        )
        return DayRecordResolver.resolve(
            dayKey: dayKey, shiftAnchorDate: day, period: period, snapshot: snapshot,
            lookup: DayRecordLookup(exceptions: exceptions, overrides: overrides, leaveDays: leave),
            expansion: expansion
        )
    }

    private static func leaveDay(_ dayKey: String, _ portion: LeavePortion) -> LeaveDay {
        LeaveDay(dayKey: dayKey, portion: portion, uses: [], planID: nil, timeZoneIdentifier: zone)
    }

    @Test("Records shows leave as a correction and keeps the plan beneath for income")
    func recordsLayer() throws {
        let whole = try Self.resolution("2026-10-14", leave: [Self.leaveDay("2026-10-14", .whole)])
        #expect(whole.layer == .override)
        #expect(!whole.isScheduledWorkday)
        #expect(whole.segments.isEmpty)
        #expect(whole.baseScheduleIsWorkday)

        let morning = try Self.resolution("2026-10-15", leave: [Self.leaveDay("2026-10-15", .firstHalf)])
        #expect(morning.segments == [try Self.segment("2026-10-15", 14, 18)])
        let afternoon = try Self.resolution("2026-10-16", leave: [Self.leaveDay("2026-10-16", .secondHalf)])
        #expect(afternoon.segments == [try Self.segment("2026-10-16", 9, 12), try Self.segment("2026-10-16", 13, 14)])

        let untouched = try Self.resolution("2026-10-13", leave: [Self.leaveDay("2026-10-14", .whole)])
        #expect(untouched.layer == .schedule)
        #expect(untouched.segments.count == 2)
    }

    @Test("A day corrected by hand or rested by a holiday is not changed by leave")
    func recordsPrecedence() throws {
        let worked = DayOverride(
            dayKey: "2026-10-14",
            shiftAnchorDate: Date(timeIntervalSince1970: try Self.instant("2026-10-14", hour: 0) / 1_000),
            kind: .customSegments,
            segments: [try Self.segment("2026-10-14", 10, 16)]
        )
        let corrected = try Self.resolution("2026-10-14", leave: [Self.leaveDay("2026-10-14", .whole)], overrides: [worked])
        #expect(corrected.segments == worked.segments)

        let holiday = CalendarException(
            dayKey: "2026-10-14#user",
            date: Date(timeIntervalSince1970: try Self.instant("2026-10-14", hour: 0) / 1_000),
            effect: .rest, origin: .user, isCleared: false, regionIdentifier: nil, datasetVersion: nil,
            label: nil, editedAt: .distantPast, editCount: 1, editTieBreaker: UUID(), timeZoneIdentifier: Self.zone
        )
        let rested = try Self.resolution("2026-10-14", leave: [Self.leaveDay("2026-10-14", .firstHalf)], exceptions: [holiday])
        #expect(rested.layer == .calendarException)
        #expect(!rested.isScheduledWorkday)
    }
}
