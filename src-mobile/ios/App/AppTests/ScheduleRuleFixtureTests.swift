import CryptoKit
import Foundation
import Testing
@testable import App

/// Holds `ScheduleRules`, `ReminderRules` and `SummaryRules` to the TypeScript
/// oracle (plan 019 R1–R3).
///
/// `ScheduleRuleFixtures.generated.swift` comes from
/// `scripts/generate-ios-schedule-rule-fixtures.mjs`. A failure means the Swift
/// port and `lib/` disagree about behaviour both platforms share: decide which
/// one is right before regenerating, never regenerate to make this pass.
@Suite("Schedule rules match the TypeScript oracle")
struct ScheduleRuleFixtureTests {
    @Test("Snapshots")
    func snapshots() throws {
        let file = try Self.fixtures()
        var mismatches = 0
        for fixture in file.snapshots {
            let profile = file.profiles[fixture.p]
            let actual = ScheduleRules.snapshot(input: file.input(
                profile, nowMs: fixture.now, salary: file.salaries[fixture.s],
                overtimeEndAtMs: fixture.ot, forcedWorkdayStartMs: fixture.forced
            ))
            if actual != fixture.expected.value {
                mismatches += 1
                if mismatches <= 5 {
                    Issue.record("snapshot \(profile.id) at \(fixture.now)\nexpected \(fixture.expected.value)\nactual   \(actual)")
                }
            }
        }
        #expect(file.snapshots.count > 2_000)
        #expect(mismatches == 0)
    }

    @Test("Watch projections")
    func watchProjections() throws {
        let file = try Self.fixtures()
        var mismatches = 0
        for fixture in file.watch {
            let profile = file.profiles[fixture.p]
            let actual = ScheduleRules.watchProjection(
                input: file.input(profile, nowMs: fixture.now, overtimeEndAtMs: fixture.ot, forcedWorkdayStartMs: fixture.forced),
                scheduleConfigured: fixture.configured,
                isRunning: fixture.running,
                currentShift: fixture.current,
                finishedAtMs: fixture.finished
            )
            if actual != fixture.expected {
                mismatches += 1
                if mismatches <= 5 {
                    Issue.record("watch \(profile.id) at \(fixture.now)\nexpected \(fixture.expected)\nactual   \(actual)")
                }
            }
        }
        #expect(file.watch.count > 1_000)
        #expect(mismatches == 0)
    }

    @Test("Widget shifts, including a four-month horizon")
    func widgetShifts() throws {
        let file = try Self.fixtures()
        for fixture in file.widgetShifts {
            let profile = file.profiles[fixture.p]
            let actual = ScheduleRules.widgetShifts(
                input: file.input(profile, nowMs: fixture.now, overtimeEndAtMs: fixture.ot),
                throughMs: fixture.through,
                maximumCount: fixture.max
            )
            #expect(actual == fixture.expected, "widget \(profile.id) at \(fixture.now)")
        }
        for fixture in file.widgetDigests {
            let profile = file.profiles[fixture.p]
            let shifts = ScheduleRules.widgetShifts(
                input: file.input(profile, nowMs: fixture.now),
                throughMs: fixture.through,
                maximumCount: fixture.max
            )
            #expect(shifts.count == fixture.count, "widget horizon \(profile.id)")
            #expect(try Self.digest(shifts.map(Self.widgetLine)) == fixture.sha256, "widget horizon \(profile.id)")
        }
    }

    @Test("Range expansion, including two years of days")
    func expansions() throws {
        let file = try Self.fixtures()
        for fixture in file.expansions {
            let profile = file.profiles[fixture.p]
            let actual = ScheduleRules.expandScheduleRange(
                configuration: profile.configuration,
                from: Date(timeIntervalSince1970: fixture.from / 1_000),
                through: Date(timeIntervalSince1970: fixture.through / 1_000),
                timeZone: TimeZone(identifier: profile.timeZoneIdentifier)
            )
            #expect(actual == fixture.expected, "expansion \(profile.id)")
        }
        for fixture in file.expansionDigests {
            let profile = file.profiles[fixture.p]
            let days = ScheduleRules.expandScheduleRange(
                configuration: profile.configuration,
                from: Date(timeIntervalSince1970: fixture.from / 1_000),
                through: Date(timeIntervalSince1970: fixture.through / 1_000),
                timeZone: TimeZone(identifier: profile.timeZoneIdentifier)
            )
            #expect(days.count == fixture.count, "expansion years \(profile.id)")
            #expect(try Self.digest(days.map(Self.expansionLine)) == fixture.sha256, "expansion years \(profile.id)")
        }
    }

    @Test("Break validation")
    func breakValidation() throws {
        let file = try Self.fixtures()
        for fixture in file.validateBreak {
            let profile = file.profiles[fixture.p]
            var input = file.input(profile, nowMs: fixture.now, overtimeEndAtMs: fixture.ot)
            input = NativeRulesInput(
                startTime: input.startTime, endTime: input.endTime, nowMs: input.nowMs,
                workdays: input.workdays, schedule: input.schedule,
                breakStartTime: fixture.breakStartTime, breakDurationMinutes: fixture.breakDurationMinutes,
                overtimeEndAtMs: input.overtimeEndAtMs, salaryAmount: input.salaryAmount,
                salaryType: input.salaryType, monthlyWorkingDays: input.monthlyWorkingDays,
                annualBonusMonths: input.annualBonusMonths, forcedWorkdayStartMs: nil,
                timeZoneIdentifier: input.timeZoneIdentifier
            )
            #expect(ScheduleRules.validateBreak(input: input) == fixture.expected, "break \(profile.id) \(fixture.breakStartTime ?? "none")")
        }
    }

    @Test("Reminders for the current and next shift")
    func reminders() throws {
        let file = try Self.fixtures()
        var mismatches = 0
        for fixture in file.reminders {
            let profile = file.profiles[fixture.p]
            let actual = ScheduleRules.reminders(
                input: file.input(profile, nowMs: fixture.now, overtimeEndAtMs: fixture.ot, forcedWorkdayStartMs: fixture.forced),
                reminderInputs: file.reminderInputs[fixture.v]
            )
            let expected = fixture.expected?.map(\.value)
            let matches = actual.count == fixture.count
                && Self.hash(actual.map(Self.reminderLine)) == fixture.sha256
                && (expected == nil || actual == expected)
            if !matches {
                mismatches += 1
                if mismatches <= 5 {
                    let detail = expected.map { "expected \($0)" } ?? "expected \(fixture.count) reminders by digest"
                    Issue.record("reminders \(profile.id) inputs \(fixture.v) at \(fixture.now)\n\(detail)\nactual   \(actual)")
                }
            }
        }
        #expect(file.reminders.count >= 300)
        #expect(file.reminders.filter { $0.expected != nil }.count >= 50)
        #expect(mismatches == 0)
    }

    @Test("Whether a schedule edit asks about today")
    func applyToday() throws {
        let file = try Self.fixtures()
        for fixture in file.applyToday {
            let profile = file.profiles[fixture.p]
            let current = file.input(profile, nowMs: fixture.now, forcedWorkdayStartMs: fixture.forced)
            var candidate = file.input(file.profiles[fixture.c], nowMs: fixture.now, forcedWorkdayStartMs: fixture.forced)
            candidate.timeZoneIdentifier = profile.timeZoneIdentifier
            #expect(
                ScheduleRules.shouldPromptApplyToday(current: current, candidate: candidate) == fixture.expected,
                "apply today \(profile.id) → \(file.profiles[fixture.c].id) at \(fixture.now)"
            )
        }
        #expect(Set(file.applyToday.map(\.expected)) == [true, false])
    }

    @Test("Period summaries, including the \"This week\" incident")
    func summaries() throws {
        let file = try Self.fixtures()
        var mismatches = 0
        for fixture in file.summaries {
            let actual = SummaryRules.summarize(input: fixture.input)
            if actual != fixture.expected {
                mismatches += 1
                if mismatches <= 5 {
                    Issue.record("summary \(fixture.input.period) at \(fixture.input.asOfMs) in \(fixture.input.timeZoneIdentifier ?? "")\nexpected \(fixture.expected)\nactual   \(actual)")
                }
            }
        }
        #expect(file.summaries.count >= 300)
        #expect(mismatches == 0)
        // fa927fb: a Wednesday afternoon halfway through the shift is 2.5 days of
        // pay, not the 2 a second formula once showed; manual mode counts today.
        #expect(file.summaries[0].expected == NativePeriodSummary(days: 2.5, hours: 22.5, earnings: 2_500))
        #expect(file.summaries[1].expected == NativePeriodSummary(days: 0.5, hours: 4.5, earnings: 500))
    }

    @Test("Records income and the monthly salary equivalent")
    func salary() throws {
        let file = try Self.fixtures()
        let profile = file.profiles[0]
        for fixture in file.recordsIncome {
            let rules = file.input(profile, nowMs: 0, salary: file.salaries[fixture.s])
            #expect(
                SummaryRules.recordsIncome(completedWorkdays: fixture.n, rules: rules) == fixture.expected,
                "records income, salary \(fixture.s), \(fixture.n) days"
            )
        }
        for fixture in file.monthlyEquivalent {
            let rules = file.input(profile, nowMs: 0, salary: file.salaries[fixture.s], salaryType: fixture.type)
            #expect(
                SummaryRules.salaryMonthlyEquivalent(input: rules) == fixture.expected,
                "monthly equivalent, salary \(fixture.s) as \(fixture.type)"
            )
        }
        #expect(file.recordsIncome.contains { $0.expected != nil } && file.recordsIncome.contains { $0.expected == nil })
    }

    @Test("Lifetime income")
    func lifetimeIncome() throws {
        let file = try Self.fixtures()
        var mismatches = 0
        for (index, fixture) in file.lifetimeIncome.enumerated() {
            let actual = SummaryRules.lifetimeIncome(input: fixture.input)
            if actual != fixture.expected {
                mismatches += 1
                if mismatches <= 5 {
                    Issue.record("lifetime case \(index)\nexpected \(fixture.expected)\nactual   \(actual)")
                }
            }
        }
        #expect(file.lifetimeIncome.contains { $0.expected.totalGross > 0 })
        #expect(mismatches == 0)
    }

    @Test("Records actual and forecast")
    func actualForecast() throws {
        let file = try Self.fixtures()
        var mismatches = 0
        for (index, fixture) in file.actualForecast.enumerated() {
            let actual = SummaryRules.recordsActualForecast(input: fixture.input)
            if actual != fixture.expected {
                mismatches += 1
                if mismatches <= 5 {
                    Issue.record("actual/forecast case \(index) as of \(fixture.input.asOfMs)\nexpected \(fixture.expected)\nactual   \(actual)")
                }
            }
        }
        #expect(file.actualForecast.count >= 100)
        #expect(mismatches == 0)
    }

    @Test("An input without a zone resolves in the current zone")
    func missingZoneIsCurrentZone() throws {
        let file = try Self.fixtures()
        let profile = file.profiles[0]
        let nowMs = 1_788_000_000_000.0
        var zoned = file.input(profile, nowMs: nowMs)
        zoned.timeZoneIdentifier = TimeZone.current.identifier
        var unzoned = zoned
        unzoned.timeZoneIdentifier = nil
        #expect(ScheduleRules.snapshot(input: unzoned) == ScheduleRules.snapshot(input: zoned))

        let from = Date(timeIntervalSince1970: 1_780_000_000)
        let through = from.addingTimeInterval(40 * 86_400)
        #expect(
            ScheduleRules.expandScheduleRange(configuration: profile.configuration, from: from, through: through)
                == ScheduleRules.expandScheduleRange(configuration: profile.configuration, from: from, through: through, timeZone: .current)
        )
    }

    @Test("Scheduled-month daily pay: snapshots, summaries, Records income and month counts")
    func scheduledMonthBasis() throws {
        let file = try Self.fixtures()
        let basis = file.monthBasis
        var mismatches: [String] = []
        func record(_ message: @autoclosure () -> String) {
            if mismatches.count < 5 { mismatches.append(message()) }
        }

        for fixture in basis.snapshots {
            let scenario = basis.scenarios[fixture.sc]
            let actual = ScheduleRules.snapshot(input: basis.rules(scenario, nowMs: fixture.now, salary: basis.salaries[fixture.s]))
            let expected = fixture.expected
            if actual.dailySalary != expected.dailySalary || actual.earnedSoFar != expected.earnedSoFar
                || actual.payRatio != expected.payRatio || actual.startAtMs != expected.startAtMs
                || actual.isWorkday != expected.isWorkday {
                record("snapshot \(scenario.id) salary \(fixture.s) at \(fixture.now): expected \(expected), actual daily \(String(describing: actual.dailySalary)) earned \(String(describing: actual.earnedSoFar)) ratio \(actual.payRatio) start \(actual.startAtMs) workday \(actual.isWorkday)")
            }
        }
        for fixture in basis.summaries {
            let scenario = basis.scenarios[fixture.sc]
            var input = fixture.input
            input.extendedSchedule = scenario.plan
            let actual = SummaryRules.summarize(input: input)
            if actual != fixture.expected {
                record("summary \(scenario.id) \(input.period) at \(input.asOfMs)\nexpected \(fixture.expected)\nactual   \(actual)")
            }
        }
        for fixture in basis.recordsIncome {
            let scenario = basis.scenarios[fixture.sc]
            let rules = basis.rules(scenario, nowMs: 0, salary: basis.salaries[fixture.s])
            let actual = SummaryRules.recordsIncome(
                completedWorkdays: fixture.completedWorkdays, rules: rules, completedByMonth: fixture.completedByMonth
            )
            if actual != fixture.expected {
                record("records income \(scenario.id) salary \(fixture.s) months \(fixture.m): expected \(String(describing: fixture.expected)), actual \(String(describing: actual))")
            }
        }
        for fixture in basis.monthlyEquivalent {
            let rules = basis.rules(basis.scenarios[0], nowMs: 0, salary: basis.salaries[fixture.s], salaryType: fixture.type)
            if SummaryRules.salaryMonthlyEquivalent(input: rules) != fixture.expected {
                record("monthly equivalent salary \(fixture.s) as \(fixture.type)")
            }
        }
        for fixture in basis.monthCounts {
            let scenario = basis.scenarios[fixture.sc]
            let zone = CivilZone(identifier: scenario.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: scenario.plan))
            let actual = zone.scheduledWorkdaysInMonth(
                anchorMs: fixture.anchorMs, workdays: scenario.workdays, schedule: scenario.schedule
            )
            if actual != fixture.expected {
                record("month count \(scenario.id) at \(fixture.anchorMs): expected \(fixture.expected), actual \(actual)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n"))")
        #expect(basis.snapshots.count >= 400)
        #expect(basis.summaries.count >= 60)
        // The point of the basis: different months of one schedule pay differently,
        // a holiday run moves a month's count, and a manual schedule falls back.
        let counts = basis.monthCounts.filter { $0.sc == 0 }.map(\.expected)
        #expect(Set(counts).count > 1)
        let goldenWeek = try #require(basis.scenarios.firstIndex { $0.id == "shanghai-golden-week" })
        let plain = try #require(basis.scenarios.firstIndex { $0.id == "shanghai-weekdays" })
        func count(_ scenario: Int, month: Int) -> Int? {
            basis.monthCounts.filter { $0.sc == scenario }[month].expected
        }
        #expect(count(goldenWeek, month: 9) == 18 && count(plain, month: 9) == 22)
        #expect(count(goldenWeek, month: 8) == 23 && count(plain, month: 8) == 22)
        let manual = try #require(basis.scenarios.firstIndex { $0.id == "shanghai-manual" })
        #expect(basis.monthCounts.filter { $0.sc == manual }.allSatisfy { $0.expected == 0 })
    }

    @Test("Overtime pay multiplier: pay ratio, earned so far, elapsed overtime, unpaid comparison, Records")
    func overtimePay() throws {
        let file = try Self.fixtures()
        let pay = file.overtimePay
        var mismatches: [String] = []
        func record(_ message: @autoclosure () -> String) {
            if mismatches.count < 5 { mismatches.append(message()) }
        }

        for fixture in pay.normalize {
            let actual = OvertimePay.normalized(fixture.value)
            if actual != fixture.expected { record("normalize \(String(describing: fixture.value)): expected \(fixture.expected), actual \(actual)") }
        }
        for fixture in pay.snapshots {
            let scenario = pay.scenarios[fixture.sc]
            let actual = ScheduleRules.snapshot(input: pay.rules(scenario, nowMs: fixture.now, salary: pay.salaries[fixture.s],
                                                                 overtimeEndAtMs: fixture.ot, multiplier: fixture.m))
            let expected = fixture.expected
            let timeline = actual.timeline
            let elapsed = timeline.overtimeElapsedMs(at: fixture.now)
            let comparison = timeline.overtimeRateComparison(dailySalary: actual.dailySalary, at: fixture.now)
            let comparisonMatches: Bool
            if let expectedComparison = expected.comparison {
                comparisonMatches = comparison?.elapsedOvertimeMs == expectedComparison.elapsedOvertimeMs
                    && comparison?.unpaidHourlyRate == expectedComparison.unpaidHourlyRate
                    && comparison?.unpaidRateDecreasePercent == expectedComparison.unpaidRateDecreasePercent
            } else {
                comparisonMatches = comparison == nil
            }
            if actual.dailySalary != expected.dailySalary || actual.earnedSoFar != expected.earnedSoFar
                || actual.payRatio != expected.payRatio || elapsed != expected.overtimeElapsedMs || !comparisonMatches {
                record("snapshot \(scenario.id) salary \(fixture.s) m \(fixture.m) ot \(String(describing: fixture.ot)) at \(fixture.now): expected \(expected), actual earned \(String(describing: actual.earnedSoFar)) ratio \(actual.payRatio) elapsed \(elapsed) comparison \(String(describing: comparison))")
            }
        }
        for fixture in pay.forecasts {
            let actual = SummaryRules.recordsActualForecast(input: fixture.input)
            if actual != fixture.expected {
                record("records \(pay.scenarios[fixture.sc].id)\nexpected \(fixture.expected)\nactual   \(actual)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n"))")
        #expect(pay.snapshots.count >= 1_000)
        #expect(pay.forecasts.count >= 100)
        // The multiplier matters: the same overtime pays differently.
        let ratios = Set(pay.snapshots.filter { $0.sc == 1 && $0.s == 0 && $0.expected.overtimeElapsedMs > 0 }.map(\.expected.payRatio))
        #expect(ratios.count > 10)
    }

    // MARK: - Fixture file

    private static func fixtures() throws -> ScheduleRuleFixtureFile {
        let file = try JSONDecoder().decode(ScheduleRuleFixtureFile.self, from: Data(ScheduleRuleFixtureData.json.utf8))
        try #require(file.version == 3)
        return file
    }

    private static func digest(_ lines: [String?]) throws -> String {
        hash(try lines.map { try #require($0, "a digest value was not a whole millisecond") })
    }

    private static func hash(_ lines: [String]) -> String {
        SHA256.hash(data: Data(lines.joined().utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // Must write exactly what `reminderLine` in the generator writes.
    private static func reminderLine(_ reminder: NativeReminder) -> String {
        func number(_ value: Double?) -> String { value.map(JavaScriptNumber.string) ?? "" }
        return [
            reminder.id,
            reminder.kind,
            number(reminder.atMs),
            number(reminder.expiresAtMs),
            number(reminder.maxTickGapMs),
            reminder.collapseGroup ?? "",
            reminder.title ?? "∅",
            reminder.body ?? "∅",
        ].joined(separator: "|") + "\n"
    }

    private static func integer(_ value: Double) -> String? {
        value.rounded() == value && abs(value) < 9e15 ? String(Int64(value)) : nil
    }

    private static func segmentsText(_ segments: [NativeShiftSegment]) -> String? {
        var parts: [String] = []
        for segment in segments {
            guard let start = integer(segment.startAtMs), let end = integer(segment.endAtMs) else { return nil }
            parts.append("\(start)-\(end)")
        }
        return parts.joined(separator: ",")
    }

    // Must write exactly what `expansionLine` / `widgetLine` in the generator write.
    private static func expansionLine(_ day: NativeScheduleDayExpansion) -> String? {
        guard let segments = segmentsText(day.segments), let anchor = integer(day.shiftAnchorStartAtMs) else { return nil }
        return "\(day.dayKey)|\(anchor)|\(day.isWorkday ? 1 : 0)|\(segments)\n"
    }

    private static func widgetLine(_ shift: NativeWidgetShiftSnapshot) -> String? {
        guard let segments = segmentsText(shift.segments),
              let start = integer(shift.startAtMs), let end = integer(shift.endAtMs),
              let planned = integer(shift.plannedEndAtMs), let duration = integer(shift.durationMs),
              let anchor = integer(shift.countdownAnchorAtMs)
        else { return nil }
        let overtime: String
        if let overtimeEndAtMs = shift.overtimeEndAtMs {
            guard let value = integer(overtimeEndAtMs) else { return nil }
            overtime = value
        } else {
            overtime = ""
        }
        return "\(segments)|\(start)|\(end)|\(planned)|\(overtime)|\(duration)|\(anchor)\n"
    }
}

struct ScheduleRuleFixtureFile: Decodable {
    struct Profile: Decodable {
        let id: String
        let startTime: String
        let endTime: String
        let workdays: [Int]
        let schedule: NativeWorkSchedule
        let breakStartTime: String?
        let breakDurationMinutes: Int
        let timeZoneIdentifier: String

        var configuration: ScheduleHoursConfiguration {
            ScheduleHoursConfiguration(
                startTime: startTime,
                endTime: endTime,
                workdays: workdays,
                schedule: schedule,
                breakStartTime: breakStartTime,
                breakDurationMinutes: breakDurationMinutes
            )
        }
    }

    struct Salary: Decodable {
        let salaryAmount: String
        let salaryType: String
        let monthlyWorkingDays: Double
        let annualBonusMonths: Double
    }

    /// The generator writes the expected snapshot as an array in field order,
    /// which keeps a few thousand cases around a megabyte.
    struct ExpectedSnapshot: Decodable {
        let value: NativeShiftSnapshot

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            func number() throws -> Double { try row.decode(Double.self) }
            func optional() throws -> Double? { try row.decodeNil() ? nil : row.decode(Double.self) }
            let segments = try row.decode([[Double]].self).map { NativeShiftSegment(startAtMs: $0[0], endAtMs: $0[1]) }
            let startAtMs = try number()
            let endAtMs = try number()
            let plannedEndAtMs = try number()
            let overtimeEndAtMs = try optional()
            let durationMs = try number()
            let plannedDurationMs = try number()
            let elapsedMs = try number()
            let remainingMs = try number()
            let progress = try number()
            let payRatio = try number()
            let activeBreakEndAtMs = try optional()
            let isWorkday = try row.decode(Bool.self)
            let nextRestAtMs = try optional()
            let dailySalary = try optional()
            let earnedSoFar = try optional()
            let nextShiftStartAtMs = try optional()
            let nextShiftEndAtMs = try optional()
            let countdownTargetAtMs = try optional()
            let countdownAnchorAtMs = try optional()
            let countdownProgress = try number()
            value = NativeShiftSnapshot(
                segments: segments, startAtMs: startAtMs, endAtMs: endAtMs,
                plannedEndAtMs: plannedEndAtMs, overtimeEndAtMs: overtimeEndAtMs,
                durationMs: durationMs, plannedDurationMs: plannedDurationMs,
                elapsedMs: elapsedMs, remainingMs: remainingMs, progress: progress,
                payRatio: payRatio, activeBreakEndAtMs: activeBreakEndAtMs, isWorkday: isWorkday,
                nextRestAtMs: nextRestAtMs, dailySalary: dailySalary, earnedSoFar: earnedSoFar,
                nextShiftStartAtMs: nextShiftStartAtMs, nextShiftEndAtMs: nextShiftEndAtMs,
                countdownTargetAtMs: countdownTargetAtMs, countdownAnchorAtMs: countdownAnchorAtMs,
                countdownProgress: countdownProgress
            )
        }
    }

    struct SnapshotCase: Decodable {
        let p: Int
        let s: Int
        let now: Double
        let ot: Double?
        let forced: Double?
        let expected: ExpectedSnapshot
    }

    struct WatchCase: Decodable {
        let p: Int
        let now: Double
        let ot: Double?
        let forced: Double?
        let configured: Bool
        let running: Bool
        let current: NativeWatchCurrentShift?
        let finished: Double?
        let expected: NativeWatchRulesProjection
    }

    struct WidgetCase: Decodable {
        let p: Int
        let now: Double
        let ot: Double?
        let through: Double
        let max: Int
        let expected: [NativeWidgetShiftSnapshot]
    }

    struct WidgetDigest: Decodable {
        let p: Int
        let now: Double
        let through: Double
        let max: Int
        let count: Int
        let sha256: String
    }

    struct ExpansionCase: Decodable {
        let p: Int
        let from: Double
        let through: Double
        let expected: [NativeScheduleDayExpansion]
    }

    struct ExpansionDigest: Decodable {
        let p: Int
        let from: Double
        let through: Double
        let count: Int
        let sha256: String
    }

    struct BreakCase: Decodable {
        let p: Int
        let now: Double
        let breakStartTime: String?
        let breakDurationMinutes: Int
        let ot: Double?
        let expected: Bool
    }

    /// A reminder written as an array in field order.
    struct ExpectedReminder: Decodable {
        let value: NativeReminder

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            func number() throws -> Double? { try row.decodeNil() ? nil : row.decode(Double.self) }
            func text() throws -> String? { try row.decodeNil() ? nil : row.decode(String.self) }
            let id = try row.decode(String.self)
            let kind = try row.decode(String.self)
            let atMs = try row.decode(Double.self)
            let expiresAtMs = try number()
            let maxTickGapMs = try number()
            let collapseGroup = try text()
            let title = try text()
            let body = try text()
            value = NativeReminder(
                id: id, kind: kind, atMs: atMs, expiresAtMs: expiresAtMs, maxTickGapMs: maxTickGapMs,
                collapseGroup: collapseGroup, title: title, body: body
            )
        }
    }

    struct ReminderCase: Decodable {
        let p: Int
        let v: Int
        let now: Double
        let ot: Double?
        let forced: Double?
        let count: Int
        let sha256: String
        let expected: [ExpectedReminder]?
    }

    struct ApplyTodayCase: Decodable {
        let p: Int
        let c: Int
        let now: Double
        let forced: Double?
        let expected: Bool
    }

    struct SummaryCase: Decodable {
        let input: NativeSummaryInput
        let expected: NativePeriodSummary
    }

    struct RecordsIncomeCase: Decodable {
        let s: Int
        let n: Int
        let expected: Double?
    }

    struct MonthlyEquivalentCase: Decodable {
        let s: Int
        let type: String
        let expected: Double?
    }

    struct LifetimeIncomeCase: Decodable {
        let input: NativeLifetimeIncomeInput
        let expected: NativeLifetimeIncomeSummary
    }

    struct ActualForecastCase: Decodable {
        let input: NativeRecordsActualForecastInput
        let expected: NativeRecordsActualForecastSummary
    }

    /// Plan 024: scheduled-month daily pay. Each case names its scenario.
    struct MonthBasis: Decodable {
        struct Scenario: Decodable {
            struct Extended: Decodable { let handSet: [String: String] }
            let id: String
            let startTime: String
            let endTime: String
            let workdays: [Int]
            let schedule: NativeWorkSchedule
            let breakStartTime: String?
            let breakDurationMinutes: Int
            let timeZoneIdentifier: String
            let extended: Extended?

            /// Hand-set work and rest days laid over the weekday pattern.
            var plan: ExtendedSchedulePlan? {
                guard let extended else { return nil }
                let work = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
                let rest = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
                func type(_ id: UUID, _ name: String, _ kind: ShiftType.Kind) -> ShiftType {
                    ShiftType(id: id, name: name, kind: kind, startMinutes: 540, endMinutes: 1_020, breakEnabled: true,
                              breakStartMinutes: 720, breakDurationMinutes: 60, colorHex: "#3366CC", isArchived: false)
                }
                return ExtendedSchedulePlan(
                    shiftTypes: [type(work, "Day", .work), type(rest, "Rest", .rest)],
                    rule: nil,
                    handSetDays: extended.handSet.mapValues { $0 == "work" ? work : rest },
                    fallsBackToBaseSchedule: true
                )
            }
        }

        struct Salary: Decodable {
            let salaryAmount: String
            let salaryType: String
            let monthlyWorkingDays: Double
            let annualBonusMonths: Double
            let dailySalaryBasis: DailySalaryBasis
        }

        struct SnapshotCase: Decodable {
            struct Expected: Decodable {
                let dailySalary: Double?
                let earnedSoFar: Double?
                let payRatio: Double
                let startAtMs: Double
                let isWorkday: Bool

                init(from decoder: any Decoder) throws {
                    var row = try decoder.unkeyedContainer()
                    dailySalary = try row.decodeNil() ? nil : row.decode(Double.self)
                    earnedSoFar = try row.decodeNil() ? nil : row.decode(Double.self)
                    payRatio = try row.decode(Double.self)
                    startAtMs = try row.decode(Double.self)
                    isWorkday = try row.decode(Bool.self)
                }
            }
            let sc: Int
            let s: Int
            let now: Double
            let expected: Expected
        }

        struct SummaryCase: Decodable {
            let sc: Int
            let input: NativeSummaryInput
            let expected: NativePeriodSummary
        }

        struct RecordsIncomeCase: Decodable {
            let sc: Int
            let s: Int
            let m: Int
            let completedWorkdays: Int
            let completedByMonth: [NativeMonthWorkdayCount]
            let expected: Double?
        }

        struct MonthlyEquivalentCase: Decodable {
            let s: Int
            let type: String
            let expected: Double?
        }

        struct MonthCountCase: Decodable {
            let sc: Int
            let anchorMs: Double
            let expected: Int
        }

        let scenarios: [Scenario]
        let salaries: [Salary]
        let snapshots: [SnapshotCase]
        let summaries: [SummaryCase]
        let recordsIncome: [RecordsIncomeCase]
        let monthlyEquivalent: [MonthlyEquivalentCase]
        let monthCounts: [MonthCountCase]

        func rules(_ scenario: Scenario, nowMs: Double, salary: Salary, salaryType: String? = nil) -> NativeRulesInput {
            NativeRulesInput(
                startTime: scenario.startTime,
                endTime: scenario.endTime,
                nowMs: nowMs,
                workdays: scenario.workdays,
                schedule: scenario.schedule,
                breakStartTime: scenario.breakStartTime,
                breakDurationMinutes: scenario.breakDurationMinutes,
                overtimeEndAtMs: nil,
                salaryAmount: salary.salaryAmount,
                salaryType: salaryType ?? salary.salaryType,
                monthlyWorkingDays: salary.monthlyWorkingDays,
                annualBonusMonths: salary.annualBonusMonths,
                forcedWorkdayStartMs: nil,
                timeZoneIdentifier: scenario.timeZoneIdentifier,
                extendedSchedule: scenario.plan,
                dailySalaryBasis: salary.dailySalaryBasis
            )
        }
    }

    /// Plan 024 phase 3: the overtime pay multiplier.
    struct OvertimePayFixtures: Decodable {
        struct Scenario: Decodable {
            let id: String
            let startTime: String
            let endTime: String
            let breakStartTime: String?
            let breakDurationMinutes: Int
            let zone: String
            let workdays: [Int]
            let schedule: NativeWorkSchedule
        }

        struct Salary: Decodable {
            let salaryAmount: String
            let salaryType: String
            let monthlyWorkingDays: Double
            let annualBonusMonths: Double
            let dailySalaryBasis: DailySalaryBasis
        }

        struct NormalizeCase: Decodable {
            let value: Double?
            let expected: Double
        }

        struct Comparison: Decodable {
            let elapsedOvertimeMs: Double
            let unpaidHourlyRate: Double?
            let unpaidRateDecreasePercent: Double?
        }

        struct Expected: Decodable {
            let dailySalary: Double?
            let earnedSoFar: Double?
            let payRatio: Double
            let overtimeElapsedMs: Double
            let comparison: Comparison?
        }

        struct SnapshotCase: Decodable {
            let sc: Int
            let s: Int
            let m: Double
            let ot: Double?
            let now: Double
            let expected: Expected
        }

        struct ForecastCase: Decodable {
            let sc: Int
            let input: NativeRecordsActualForecastInput
            let expected: NativeRecordsActualForecastSummary
        }

        let scenarios: [Scenario]
        let salaries: [Salary]
        let normalize: [NormalizeCase]
        let snapshots: [SnapshotCase]
        let forecasts: [ForecastCase]

        func rules(_ scenario: Scenario, nowMs: Double, salary: Salary, overtimeEndAtMs: Double?, multiplier: Double) -> NativeRulesInput {
            NativeRulesInput(
                startTime: scenario.startTime,
                endTime: scenario.endTime,
                nowMs: nowMs,
                workdays: scenario.workdays,
                schedule: scenario.schedule,
                breakStartTime: scenario.breakStartTime,
                breakDurationMinutes: scenario.breakDurationMinutes,
                overtimeEndAtMs: overtimeEndAtMs,
                salaryAmount: salary.salaryAmount,
                salaryType: salary.salaryType,
                monthlyWorkingDays: salary.monthlyWorkingDays,
                annualBonusMonths: salary.annualBonusMonths,
                forcedWorkdayStartMs: nil,
                timeZoneIdentifier: scenario.zone,
                dailySalaryBasis: salary.dailySalaryBasis,
                overtimePayMultiplier: multiplier
            )
        }
    }

    let version: Int
    let profiles: [Profile]
    let salaries: [Salary]
    let reminderInputs: [NativeReminderInputs]
    let reminders: [ReminderCase]
    let applyToday: [ApplyTodayCase]
    let snapshots: [SnapshotCase]
    let watch: [WatchCase]
    let widgetShifts: [WidgetCase]
    let widgetDigests: [WidgetDigest]
    let expansions: [ExpansionCase]
    let expansionDigests: [ExpansionDigest]
    let validateBreak: [BreakCase]
    let summaries: [SummaryCase]
    let recordsIncome: [RecordsIncomeCase]
    let monthlyEquivalent: [MonthlyEquivalentCase]
    let lifetimeIncome: [LifetimeIncomeCase]
    let actualForecast: [ActualForecastCase]
    let monthBasis: MonthBasis
    let overtimePay: OvertimePayFixtures

    func input(
        _ profile: Profile,
        nowMs: Double,
        salary: Salary? = nil,
        salaryType: String? = nil,
        overtimeEndAtMs: Double? = nil,
        forcedWorkdayStartMs: Double? = nil
    ) -> NativeRulesInput {
        let salary = salary ?? salaries[0]
        return NativeRulesInput(
            startTime: profile.startTime,
            endTime: profile.endTime,
            nowMs: nowMs,
            workdays: profile.workdays,
            schedule: profile.schedule,
            breakStartTime: profile.breakStartTime,
            breakDurationMinutes: profile.breakDurationMinutes,
            overtimeEndAtMs: overtimeEndAtMs,
            salaryAmount: salary.salaryAmount,
            salaryType: salaryType ?? salary.salaryType,
            monthlyWorkingDays: salary.monthlyWorkingDays,
            annualBonusMonths: salary.annualBonusMonths,
            forcedWorkdayStartMs: forcedWorkdayStartMs,
            timeZoneIdentifier: profile.timeZoneIdentifier
        )
    }
}
