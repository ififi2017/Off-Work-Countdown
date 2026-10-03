import Foundation
import Testing
import UserNotifications
@testable import App

/// Period reports, their Records queries and notification delivery.

@Suite("Cycle reports")
struct CycleReportTests {
    // MARK: Periods

    private static func calendar(_ zone: String = "Asia/Shanghai", firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private static func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test("A week follows the calendar's first weekday, a month its own edges")
    func periodsFollowTheRecordsPage() {
        let monday = Self.calendar(firstWeekday: 2)
        let wednesday = Self.date(monday, 2026, 9, 23)
        let weekMonday = CycleReportPeriod.containing(wednesday, kind: .week, calendar: monday)
        #expect(weekMonday.startDayKey == "2026-09-21")
        #expect(weekMonday.endDayKey == "2026-09-27")

        let sunday = Self.calendar(firstWeekday: 1)
        let weekSunday = CycleReportPeriod.containing(wednesday, kind: .week, calendar: sunday)
        #expect(weekSunday.startDayKey == "2026-09-20")
        #expect(weekSunday.endDayKey == "2026-09-26")

        let leap = CycleReportPeriod.containing(Self.date(monday, 2028, 2, 10), kind: .month, calendar: monday)
        #expect(leap.startDayKey == "2028-02-01")
        #expect(leap.endDayKey == "2028-02-29")
        #expect(leap.dayKeys(calendar: monday).count == 29)
    }

    @Test("Neighbouring periods keep their kind and cross month and year edges")
    func neighbours() {
        let calendar = Self.calendar()
        let december = CycleReportPeriod.containing(Self.date(calendar, 2026, 12, 15), kind: .month, calendar: calendar)
        #expect(december.following(calendar: calendar)?.startDayKey == "2027-01-01")
        #expect(december.previous(calendar: calendar)?.startDayKey == "2026-11-01")
        #expect(december.previous(calendar: calendar)?.endDayKey == "2026-11-30")

        let week = CycleReportPeriod.containing(Self.date(calendar, 2026, 12, 30), kind: .week, calendar: calendar)
        #expect(week.startDayKey == "2026-12-28")
        #expect(week.following(calendar: calendar)?.startDayKey == "2027-01-04")
        #expect(week.previous(calendar: calendar)?.endDayKey == "2026-12-27")
    }

    @Test("A period is complete only after its last day has passed")
    func completion() {
        let calendar = Self.calendar()
        let week = CycleReportPeriod.containing(Self.date(calendar, 2026, 9, 23), kind: .week, calendar: calendar)
        #expect(!week.isComplete(at: Self.date(calendar, 2026, 9, 27, 23), calendar: calendar))
        #expect(week.isComplete(at: Self.date(calendar, 2026, 9, 28, 0), calendar: calendar))
    }

    @Test("A natural year includes leap day and changes only at civil midnight")
    func naturalYears() {
        for zone in ["Asia/Shanghai", "America/New_York"] {
            let calendar = Self.calendar(zone)
            let leap = CycleReportPeriod.containing(Self.date(calendar, 2028, 12, 31, 23), kind: .year, calendar: calendar)
            #expect(leap.startDayKey == "2028-01-01")
            #expect(leap.endDayKey == "2028-12-31")
            #expect(leap.dayKeys(calendar: calendar).count == 366)
            #expect(leap.dayKeys(calendar: calendar).contains("2028-02-29"))
            #expect(!leap.isComplete(at: Self.date(calendar, 2028, 12, 31, 23), calendar: calendar))
            #expect(leap.isComplete(at: Self.date(calendar, 2029, 1, 1, 0), calendar: calendar))
            #expect(leap.previous(calendar: calendar)?.startDayKey == "2027-01-01")
            #expect(leap.previous(calendar: calendar)?.dayKeys(calendar: calendar).count == 365)
            #expect(leap.following(calendar: calendar)?.endDayKey == "2029-12-31")
        }
    }

    @Test("A completed period keeps its own final day as the look-ahead reference")
    func historicalReference() {
        let calendar = Self.calendar()
        let month = CycleReportPeriod.containing(Self.date(calendar, 2026, 9, 15), kind: .month, calendar: calendar)
        #expect(month.referenceDate(at: Self.date(calendar, 2027, 4, 10), calendar: calendar) == Self.date(calendar, 2026, 9, 30, 0))
        #expect(month.referenceDate(at: Self.date(calendar, 2026, 9, 15, 23), calendar: calendar) == Self.date(calendar, 2026, 9, 15, 0))
    }

    // MARK: Link

    @Test("A report link names its period and reads back unchanged")
    func linkRoundTrip() throws {
        let calendar = Self.calendar("America/New_York")
        for kind in CycleReportKind.allCases {
            let period = CycleReportPeriod.containing(Self.date(calendar, 2026, 3, 11), kind: kind, calendar: calendar)
            let url = period.url
            #expect(url.scheme == "offworkcountdown" && url.host == "report")
            #expect(CycleReportPeriod(url: url) == period)
        }
    }

    @Test("A link must name a well-formed report period")
    func linkRejectsMalformed() throws {
        func parse(_ query: String) -> CycleReportPeriod? {
            CycleReportPeriod(url: URL(string: "offworkcountdown://report?\(query)")!)
        }
        #expect(parse("kind=week&start=2026-09-21&end=2026-09-27&tz=Asia/Shanghai") != nil)
        #expect(parse("kind=month&start=2026-09-01&end=2026-09-30&tz=Asia/Shanghai") != nil)
        #expect(parse("kind=year&start=2026-01-01&end=2026-12-31&tz=Asia/Shanghai") != nil)
        #expect(parse("kind=year&start=2028-01-01&end=2028-12-31&tz=Asia/Shanghai") != nil)
        #expect(parse("kind=year&start=2026-02-01&end=2027-01-31&tz=Asia/Shanghai") == nil)
        #expect(parse("kind=year&start=2028-01-01&end=2028-12-30&tz=Asia/Shanghai") == nil)
        #expect(parse("kind=year&start=2026-01-01&end=2027-01-01&tz=Asia/Shanghai") == nil)
        #expect(parse("kind=week&start=2026-09-27&end=2026-09-21&tz=Asia/Shanghai") == nil)
        #expect(parse("kind=week&start=2026-09-21&end=2026-10-21&tz=Asia/Shanghai") == nil)
        #expect(parse("kind=month&start=2026-09-01&end=2026-09-07&tz=Asia/Shanghai") == nil)
        #expect(parse("kind=week&start=2026-9-21&end=2026-09-27&tz=Asia/Shanghai") == nil)
        #expect(parse("kind=week&start=2026-09-21&end=2026-09-27&tz=Nowhere/Land") == nil)
        #expect(parse("kind=week&start=2026-09-21&end=2026-09-27") == nil)
        #expect(CycleReportPeriod(url: URL(string: "offworkcountdown://timer")!) == nil)
        #expect(CycleReportPeriod(url: URL(string: "https://example.com/report?kind=week")!) == nil)
    }

    // MARK: Notifications

    @Test("The next period of each enabled kind is scheduled for the morning after it ends")
    func notificationPlan() {
        let calendar = Self.calendar()
        let now = Self.date(calendar, 2026, 9, 23, 15)
        let both = CycleReportNotificationPlan.items(weekly: true, monthly: true, now: now, calendar: calendar)
        #expect(both.map(\.period.kind) == [.week, .month])
        #expect(both[0].period.startDayKey == "2026-09-21")
        #expect(both[0].fireDate == Self.date(calendar, 2026, 9, 28, 9))
        #expect(both[1].period.startDayKey == "2026-09-01")
        #expect(both[1].fireDate == Self.date(calendar, 2026, 10, 1, 9))

        let weeklyOnly = CycleReportNotificationPlan.items(weekly: true, monthly: false, now: now, calendar: calendar)
        #expect(weeklyOnly.map(\.period.kind) == [.week])
        #expect(CycleReportNotificationPlan.items(weekly: false, monthly: false, now: now, calendar: calendar).isEmpty)
    }

    @Test("On the closing day the report is still tomorrow's, and a tap days later keeps its period")
    func notificationOnClosingDay() {
        let calendar = Self.calendar()
        let sundayEvening = Self.date(calendar, 2026, 9, 27, 21)
        let item = CycleReportNotificationPlan.items(weekly: true, monthly: false, now: sundayEvening, calendar: calendar)[0]
        #expect(item.period.endDayKey == "2026-09-27")
        #expect(item.fireDate == Self.date(calendar, 2026, 9, 28, 9))

        // After 09:00 on Monday that report is out; the plan moves on to the
        // week now running, and the delivered one still opens its own week.
        let mondayNoon = Self.date(calendar, 2026, 9, 28, 12)
        let next = CycleReportNotificationPlan.items(weekly: true, monthly: false, now: mondayNoon, calendar: calendar)[0]
        #expect(next.period.startDayKey == "2026-09-28")
        #expect(CycleReportPeriod(url: item.period.url)?.startDayKey == "2026-09-21")
    }

    @Test("Report notifications fit in the budget the shift reminders give up")
    func notificationBudget() {
        let calendar = Self.calendar()
        let now = Self.date(calendar, 2026, 9, 23)
        let items = CycleReportNotificationPlan.items(weekly: true, monthly: true, yearly: true, now: now, calendar: calendar)
        #expect(items.count == 3)
        #expect(CycleReportNotificationPlan.reservedSlots == 3)
        #expect(items.count <= CycleReportNotificationPlan.reservedSlots)
    }

    @Test("January 1 before nine still schedules the preceding year, then moves to the running year")
    func januaryNotificationBoundary() throws {
        for zone in ["Asia/Shanghai", "America/New_York"] {
            let calendar = Self.calendar(zone)
            for now in [Self.date(calendar, 2028, 12, 31, 23), Self.date(calendar, 2029, 1, 1, 8)] {
                let item = try #require(CycleReportNotificationPlan.items(weekly: false, monthly: false, yearly: true,
                    now: now, calendar: calendar).first)
                #expect(item.period.startDayKey == "2028-01-01")
                #expect(item.period.endDayKey == "2028-12-31")
                #expect(item.fireDate == Self.date(calendar, 2029, 1, 1, 9))
                #expect(CycleReportPeriod(url: item.period.url) == item.period)
            }
            let after = try #require(CycleReportNotificationPlan.items(weekly: false, monthly: false, yearly: true,
                now: Self.date(calendar, 2029, 1, 1, 9), calendar: calendar).first)
            #expect(after.period.startDayKey == "2029-01-01")
            #expect(after.fireDate == Self.date(calendar, 2030, 1, 1, 9))
        }
    }

    // MARK: Snapshot

    private func cell(
        _ key: String, work: Int64 = 0, overtime: Int64 = 0, future: Bool = false, today: Bool = false
    ) -> RecordsDayCell {
        let calendar = Self.calendar()
        return RecordsDayCell(
            dayKey: key,
            date: RecordJSON.date(fromDayKey: key, calendar: calendar)!,
            appearance: work > 0 ? .recorded : .rest,
            workMs: work, overtimeMs: overtime, breakMs: 0, freeMs: 0,
            observationCount: 0, isToday: today, isFuture: future,
            isProjection: false, hasConflict: false
        )
    }

    private let hour: Int64 = 3_600_000
    private var week: CycleReportPeriod {
        CycleReportPeriod(kind: .week, startDayKey: "2026-09-21", endDayKey: "2026-09-27", timeZoneIdentifier: "Asia/Shanghai")
    }

    private func weekCells() -> [RecordsDayCell] {
        [
            cell("2026-09-21", work: 8 * hour), cell("2026-09-22", work: 8 * hour, overtime: 2 * hour),
            cell("2026-09-23"), cell("2026-09-24"),
            cell("2026-09-25", work: 8 * hour), cell("2026-09-26"), cell("2026-09-27"),
        ]
    }

    @Test("Rest days, the longest stretch and its position come from the day cells")
    func restStretches() {
        let snapshot = CycleReportBuilder.snapshot(
            period: week, cells: weekCells(),
            figures: .init(workdays: 3, workedMs: 26 * hour, overtimeMs: 2 * hour, income: nil),
            isInProgress: false
        )
        #expect(snapshot.days.map(\.kind) == [.work, .work, .rest, .rest, .work, .rest, .rest])
        #expect(snapshot.restDayCount == 4)
        #expect(snapshot.longestRestRun == 2)
        #expect(snapshot.longestRestStart == 2) // the first of two equal stretches wins
        #expect(snapshot.baseline == nil)
    }

    @Test("Days after today are upcoming, never rest, and do not extend a stretch")
    func upcomingDays() {
        var cells = weekCells()
        cells[5] = cell("2026-09-26", future: true)
        cells[6] = cell("2026-09-27", future: true)
        let snapshot = CycleReportBuilder.snapshot(
            period: week, cells: cells,
            figures: .init(workdays: 3, workedMs: 26 * hour, overtimeMs: 2 * hour, income: nil),
            isInProgress: true
        )
        #expect(snapshot.days.suffix(2).map(\.kind) == [.upcoming, .upcoming])
        #expect(snapshot.restDayCount == 2)
        #expect(snapshot.isInProgress)
    }

    @Test("A day that only carries a night shift's tail is not a rest day")
    func nightShiftTail() {
        var cells = weekCells()
        cells[2] = cell("2026-09-23", work: 6 * hour)
        let snapshot = CycleReportBuilder.snapshot(
            period: week, cells: cells,
            figures: .init(workdays: 3, workedMs: 32 * hour, overtimeMs: 0, income: nil),
            isInProgress: false
        )
        #expect(snapshot.days[2].kind == .work)
        #expect(snapshot.restDayCount == 3)
    }

    @Test("Against your usual: the average of earlier periods that hold records, never a running period")
    func baselineUsesTheOwnPast() {
        let now = CycleReportFigures(workdays: 3, workedMs: 26 * hour, overtimeMs: 2 * hour, income: nil)
        func figures(_ h: Int64) -> CycleReportFigures { .init(workdays: 5, workedMs: h * hour, overtimeMs: 0, income: nil) }
        let empty = CycleReportFigures(workdays: 0, workedMs: 0, overtimeMs: 0, income: nil)

        let usual = CycleReportBaseline.make(current: now, priors: [figures(40), empty, figures(44), figures(42)], window: 4, isInProgress: false)
        #expect(usual?.kind == .usual(periods: 3))
        #expect(usual?.baselineWorkedMs == 42 * hour)
        #expect(usual?.deltaMs == -16 * hour)

        // One earlier period with records is only "the period before".
        let previous = CycleReportBaseline.make(current: now, priors: [figures(40), empty], window: 4, isInProgress: false)
        #expect(previous?.kind == .previous)
        #expect(previous?.deltaMs == -14 * hour)

        #expect(CycleReportBaseline.make(current: now, priors: [empty, empty], window: 4, isInProgress: false) == nil)
        // Where records began: a single day on file is not a usual to measure against.
        let thin = CycleReportFigures(workdays: 1, workedMs: 8 * hour, overtimeMs: 0, income: nil)
        #expect(CycleReportBaseline.make(current: now, priors: [thin, thin], window: 4, isInProgress: false) == nil)
        #expect(CycleReportBaseline.make(current: now, priors: [figures(40), thin, thin], window: 4, isInProgress: false)?.kind == .previous)
        #expect(CycleReportBaseline.make(current: empty, priors: [figures(40), figures(42)], window: 4, isInProgress: false) == nil)
        #expect(CycleReportBaseline.make(current: now, priors: [figures(40), figures(42)], window: 4, isInProgress: true) == nil)
        // Only the window counts: a fifth week back is not "your last four".
        #expect(CycleReportBaseline.make(current: now, priors: [empty, empty, empty, empty, figures(40), figures(42)], window: 4, isInProgress: false) == nil)
    }

    @Test("Every elapsed overtime entry counts, including five minutes and a night-shift tail")
    @MainActor
    func overtimeDays() throws {
        let cells = [
            cell("2026-09-21", work: 8 * hour),
            cell("2026-09-22", work: 8 * hour, overtime: 5 * 60_000),
            cell("2026-09-23", overtime: 2 * hour),
            cell("2026-09-24", work: 8 * hour, overtime: hour),
            cell("2026-09-25", overtime: 9 * hour, future: true),
        ]
        let snapshot = CycleReportBuilder.snapshot(period: week, cells: cells,
            figures: .init(workdays: 4, workedMs: 27 * hour, overtimeMs: 3 * hour + 5 * 60_000, income: nil),
            isInProgress: true)
        let overtime = try #require(snapshot.overtime)
        #expect(overtime.dayCount == 3)
        #expect(overtime.longestDay.dayKey == "2026-09-23")
        #expect(overtime.longestDay.overtimeMs == 2 * hour)
        let expectedDayKeys = cells.prefix(4).map { $0.dayKey }
        #expect(overtime.days.map(\.dayKey) == expectedDayKeys)
        #expect(snapshot.days[2].kind == .work)
        #expect(snapshot.figures.overtimeMs == 3 * hour + 5 * 60_000)
        #expect(CycleReportOvertime.make(days: [snapshot.days[0], snapshot.days[4]]) == nil)
    }

    @Test("The next break is the first run of three rest days, counted from tomorrow")
    func nextBreak() {
        let calendar = Self.calendar()
        func days(_ rest: [Bool]) -> [(dayKey: String, date: Date, isRest: Bool)] {
            rest.enumerated().map { index, isRest in
                let date = calendar.date(byAdding: .day, value: index + 1, to: Self.date(calendar, 2026, 9, 30))!
                return (RecordJSON.dayKey(date, calendar: calendar), date, isRest)
            }
        }
        // A two-day weekend first, then a four-day break.
        let next = CycleReportAhead.findBreak(in: days([false, false, true, true, false, false, true, true, true, true, false]))
        #expect(next?.length == 4)
        #expect(next?.daysAway == 7)
        #expect(next?.startDayKey == "2026-10-07")
        #expect(CycleReportAhead.findBreak(in: days([false, true, true, false, true, true, false])) == nil)
        #expect(CycleReportAhead.make(upcoming: days([false, true, false]), leaveUsedHalfDays: 0, leaveRemainingHalfDays: nil) == nil)
        #expect(CycleReportAhead.make(upcoming: days([false, true, false]), leaveUsedHalfDays: 0, leaveRemainingHalfDays: 7)?.leaveRemainingHalfDays == 7)
    }

    @Test("Focus: busiest day, most common kind, and nothing under two rounds")
    func focusRounds() {
        let rounds: [(dayIndex: Int, ms: Int64, icon: FocusTaskIcon?)] = [
            (1, 1_500_000, .code), (1, 1_500_000, .code), (3, 1_500_000, .writing), (3, 1_500_000, .code), (3, 1_500_000, nil),
        ]
        let focus = CycleReportFocus.make(rounds: rounds, dayCount: 7)
        #expect(focus?.rounds == 5)
        #expect(focus?.perDay == [0, 2, 0, 3, 0, 0, 0])
        #expect(focus?.bestDayIndex == 3)
        #expect(focus?.topIcon == .code)
        #expect(CycleReportFocus.make(rounds: [(0, 1_500_000, .code)], dayCount: 7) == nil)
    }

    @Test("Pay as a rate; overtime adds only where the rules pay it")
    func payReading() {
        let figures = CycleReportFigures(workdays: 5, workedMs: 40 * hour, overtimeMs: 4 * hour, income: 4_400)
        let paid = CycleReportPay.make(figures: figures, overtimeIsPaid: true)
        #expect(paid?.perHour == 110)
        #expect(paid?.overtimeExtra == 440)
        let fixed = CycleReportPay.make(figures: figures, overtimeIsPaid: false)
        #expect(fixed?.overtimeExtra == nil)
        #expect(CycleReportPay.make(figures: .init(workdays: 5, workedMs: 40 * hour, overtimeMs: 0, income: nil), overtimeIsPaid: true) == nil)
        #expect(CycleReportPay.make(figures: .init(workdays: 1, workedMs: hour / 2, overtimeMs: 0, income: 50), overtimeIsPaid: true)?.perHour == nil)
    }

    @Test("The headline follows plain rules and never an outcome word")
    func headlines() {
        let base = CycleReportFigures(workdays: 5, workedMs: 40 * hour, overtimeMs: 0, income: nil)
        func baseline(_ delta: Int64) -> CycleReportBaseline {
            .init(kind: .usual(periods: 4), baselineWorkedMs: 40 * hour, deltaMs: delta * hour)
        }
        func pick(_ b: CycleReportBaseline?, figures: CycleReportFigures = base, rest: Int = 2, run: Int = 2,
                  next: CycleReportNextBreak? = nil, running: Bool = false) -> CycleReportHeadline {
            CycleReportHeadline.choose(figures: figures, baseline: b, restDayCount: rest, longestRestRun: run, kind: .week, nextBreak: next, isInProgress: running)
        }
        #expect(pick(nil, running: true) == .inProgress)
        #expect(pick(baseline(1)) == .steady)
        #expect(pick(baseline(6)) == .fullStretch)
        #expect(pick(baseline(-6)) == .lighter)
        #expect(pick(nil) == .plain)
        #expect(pick(nil, rest: 5, run: 3) == .roomToBreathe)
        let soon = CycleReportNextBreak(startDayKey: "2026-10-01", startDate: .now, length: 4, daysAway: 3)
        #expect(pick(baseline(3), next: soon) == .sprint)
        #expect(pick(baseline(0), next: soon) == .steady)
        let heavy = CycleReportFigures(workdays: 5, workedMs: 44 * hour, overtimeMs: 4 * hour, income: nil)
        #expect(pick(nil, figures: heavy) == .fullStretch)
    }

    @Test("Pay is carried only until a report is told not to show it")
    func incomeIsStripped() {
        let figures = CycleReportFigures(workdays: 3, workedMs: 26 * hour, overtimeMs: 0, income: 1_800)
        let snapshot = CycleReportBuilder.snapshot(period: week, cells: weekCells(), figures: figures, isInProgress: false)
        #expect(snapshot.income == 1_800)
        let hidden = snapshot.withoutIncome()
        #expect(hidden.income == nil)
        #expect(hidden.figures.workedMs == snapshot.figures.workedMs)
        #expect(!CycleReportStage.stages(for: hidden).contains(.income))
        #expect(CycleReportStage.stages(for: snapshot).contains(.income))
    }

    @Test("Removing income also removes every monthly amount and preserves time and leave")
    func yearlyIncomeIsStripped() {
        let calendar = Self.calendar()
        let year = CycleReportPeriod.containing(Self.date(calendar, 2026, 6, 1), kind: .year, calendar: calendar)
        let figures = CycleReportFigures(workdays: 3, workedMs: 24 * hour, overtimeMs: hour, income: 1_800)
        var extras = CycleReportExtras()
        extras.months = (1...12).map { month in
            CycleReportMonth(period: .containing(Self.date(calendar, 2026, month, 1), kind: .month, calendar: calendar),
                figures: figures, restDayCount: month, focusRounds: 1)
        }
        extras.leaveUsedHalfDays = 7
        let snapshot = CycleReportBuilder.snapshot(period: year, cells: weekCells(), figures: figures,
            extras: extras, isInProgress: false)
        let hidden = snapshot.withoutIncome()
        #expect(snapshot.months.allSatisfy { $0.figures.income == 1_800 })
        #expect(hidden.months.count == 12)
        #expect(hidden.months.allSatisfy { $0.figures.income == nil })
        #expect(hidden.pay == nil && hidden.income == nil)
        #expect(hidden.months.map(\.figures.workedMs) == snapshot.months.map(\.figures.workedMs))
        #expect(hidden.months.map(\.focusRounds) == snapshot.months.map(\.focusRounds))
        #expect(hidden.leaveUsedHalfDays == 7)
    }

    @Test("The overtime chapter depends on the Records period total")
    func overtimeStageUsesTotal() {
        let none = CycleReportBuilder.snapshot(period: week, cells: weekCells(),
            figures: .init(workdays: 3, workedMs: 24 * hour, overtimeMs: 0, income: nil), isInProgress: false)
        #expect(none.overtime != nil)
        #expect(!CycleReportStage.stages(for: none).contains(.overtime))
        let positive = CycleReportBuilder.snapshot(period: week, cells: [cell("2026-09-21", work: hour)],
            figures: .init(workdays: 1, workedMs: hour, overtimeMs: 5 * 60_000, income: nil), isInProgress: false)
        #expect(positive.overtime == nil)
        #expect(CycleReportStage.stages(for: positive).contains(.overtime))
    }

    // MARK: Figures

    @Test("Figures count what happened; a forecast is not worked time")
    func figuresIgnoreForecast() {
        let headline = RecordsHeadlineSummary(
            workdays: 4, regularWorkMs: 30 * hour, overtimeMs: 2 * hour, wakingFreeMs: 0,
            estimatedIncome: 999, completedScheduledWorkdays: 4, allocationDays: 7,
            allocation: .init(workMs: 0, overtimeMs: 0, sleepMs: 0, freeMs: 0, dayLengthMs: 0),
            sleepSourceKey: "recordsSleepEstimated",
            actualForecast: NativeRecordsActualForecastSummary(
                actualOvertimeHours: 2,
                actual: .init(days: 3, hours: 26, earnings: 1_800),
                forecast: .init(days: 2, hours: 16, earnings: 1_200),
                total: .init(days: 5, hours: 42, earnings: 3_000)
            )
        )
        let figures = CycleReportFigures(headline: headline)
        #expect(figures.workdays == 3)
        #expect(figures.workedMs == 26 * hour)
        #expect(figures.overtimeMs == 2 * hour)
        #expect(figures.income == 1_800)
    }

    @Test("Without the actual/forecast split the plain headline is used; none means no data")
    func figuresFallBack() {
        let headline = RecordsHeadlineSummary(
            workdays: 4, regularWorkMs: 30 * hour, overtimeMs: 2 * hour, wakingFreeMs: 0,
            estimatedIncome: nil, completedScheduledWorkdays: 4, allocationDays: 7,
            allocation: .init(workMs: 0, overtimeMs: 0, sleepMs: 0, freeMs: 0, dayLengthMs: 0),
            sleepSourceKey: "recordsSleepEstimated"
        )
        let figures = CycleReportFigures(headline: headline)
        #expect(figures.workdays == 4 && figures.workedMs == 32 * hour && figures.income == nil)
        #expect(!CycleReportFigures(headline: nil).hasData)
        #expect(CycleReportStage.stages(for: CycleReportBuilder.snapshot(
            period: week, cells: weekCells(), figures: .init(headline: nil), isInProgress: false
        )).isEmpty)
    }

    @Test("Pages are told in order, and a page with nothing to say is left out")
    func stageOrder() {
        let base = CycleReportFigures(workdays: 3, workedMs: 26 * hour, overtimeMs: 0, income: nil)
        let plain = CycleReportBuilder.snapshot(period: week, cells: weekCells(), figures: base, isInProgress: false)
        #expect(CycleReportStage.stages(for: plain) == [.calendar, .hours, .rest, .summary])

        var figures = base
        figures.income = 100
        let before = CycleReportFigures(workdays: 5, workedMs: 40 * hour, overtimeMs: 0, income: nil)
        var extras = CycleReportExtras(priors: [before])
        figures.overtimeMs = 2 * hour
        extras.ahead = CycleReportAhead.make(upcoming: [], leaveUsedHalfDays: 0, leaveRemainingHalfDays: 4)
        extras.focus = CycleReportFocus.make(rounds: [(0, 1, .code), (1, 1, .code)], dayCount: 7)
        extras.overtimeIsPaid = true
        let full = CycleReportBuilder.snapshot(period: week, cells: weekCells(), figures: figures, extras: extras, isInProgress: false)
        #expect(CycleReportStage.stages(for: full) == [.calendar, .hours, .overtime, .baseline, .rest, .ahead, .focus, .income, .summary])
        #expect(CycleReportStage.stages(for: full.withoutIncome()) == [.calendar, .hours, .overtime, .baseline, .rest, .ahead, .focus, .summary])
    }

    // MARK: Player

    @MainActor
    private func player(autoplay: Bool = true) -> CycleReportPlayer {
        let figures = CycleReportFigures(workdays: 3, workedMs: 26 * hour, overtimeMs: 0, income: nil)
        let snapshot = CycleReportBuilder.snapshot(period: week, cells: weekCells(), figures: figures, isInProgress: false)
        return CycleReportPlayer(snapshot: snapshot, autoplay: autoplay)
    }

    @Test("The clock builds each chapter, holds it, hands over, and stops built on the summary")
    @MainActor
    func playsThrough() {
        let player = player()
        var seen: [CycleReportStage] = [player.stage]
        var lastProgress = 0.0
        for _ in 0..<2_000 where player.isPlaying {
            player.advance(by: 0.05)
            if player.stage != seen.last { seen.append(player.stage); lastProgress = 0 }
            #expect(player.progress >= lastProgress)
            lastProgress = player.progress
            if player.isLastStage, player.isBuilt { break }
        }
        #expect(seen == player.stages)
        #expect(player.stage == .summary && player.isBuilt)
        #expect(player.build == 1)
    }

    @Test("A finger holding the screen, or a pause, stops the clock; neither loses the place")
    @MainActor
    func holdAndPause() {
        let player = player()
        player.advance(by: 1)
        let t = player.time
        player.isHeld = true
        player.advance(by: 5)
        #expect(player.time == t)
        player.isHeld = false
        player.pause()
        player.advance(by: 5)
        #expect(player.time == t && player.stageIndex == 0)
        player.resume()
        player.advance(by: 0.5)
        #expect(player.time > t)
    }

    @Test("Previous restarts a chapter that has begun, then steps back; next and skip stay in range")
    @MainActor
    func navigation() {
        let player = player(autoplay: false)
        player.previous()
        #expect(player.stageIndex == 0)
        player.next()
        player.next()
        #expect(player.stage == .rest)
        player.resume()
        player.advance(by: 1.5)
        player.previous() // restarts this chapter
        #expect(player.stage == .rest && player.time == 0)
        player.previous() // then steps back
        #expect(player.stage == .hours)
        player.skipToSummary()
        #expect(player.isLastStage && player.isBuilt && !player.isPlaying)
        player.next()
        #expect(player.isLastStage)
        player.resume() // at the end, playing again means from the top
        #expect(player.stageIndex == 0 && player.time == 0 && player.isPlaying)
    }

    @Test("Easing stays inside its range and staggering starts items one after another")
    func easing() {
        for x in stride(from: -0.5, through: 1.5, by: 0.1) {
            #expect((0...1).contains(ReportEase.outCubic(x)))
            #expect((0...1).contains(ReportEase.inOutCubic(x)))
        }
        #expect(ReportEase.staggered(0, index: 3, count: 7) == 0)
        #expect(ReportEase.staggered(1, index: 0, count: 7) == 1)
        #expect(ReportEase.staggered(0.3, index: 0, count: 7) > ReportEase.staggered(0.3, index: 5, count: 7))
        #expect(ReportEase.window(0.5, 0.25, 0.75) == 0.5)
    }

    // MARK: Notification delivery

    @MainActor
    private final class FakeCenter {
        var allowed = true
        var requests: [String: UNNotificationRequest] = [:]
        var center: NotificationService.ShiftCenter {
            .init(
                authorization: { self.allowed ? .allowed : .denied },
                pendingIDs: { Array(self.requests.keys) },
                deliveredIDs: { [] },
                add: { self.requests[$0.identifier] = $0 },
                removePending: { ids in for id in ids { self.requests[id] = nil } },
                removeDelivered: { _ in }
            )
        }
        var reportIDs: [String] { requests.keys.filter { $0.hasPrefix("owc.report.") }.sorted() }
    }

    @MainActor
    private func makeRuntime(plus: Bool) throws -> (AppRuntime, UserDefaults, () -> Void) {
        let suite = "owc.cycleReports.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        if plus { defaults.set(true, forKey: "ios.native.debugPlusAuthorized") }
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        runtime.preferences.onboardingComplete = true
        runtime.preferences.applyPreferences {
            $0.languageOverride = "en"
            $0.recordsTimeZoneIdentifier = "Asia/Shanghai"
        }
        return (runtime, defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test("Each switch leaves its own request; turning one off removes only it; links carry the period, copy carries no figures")
    @MainActor
    func schedulesAndCleansUp() async throws {
        let (runtime, _, cleanup) = try makeRuntime(plus: true)
        defer { cleanup() }
        let fake = FakeCenter()
        let service = NotificationService(shiftCenter: fake.center)
        runtime.preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = true }
        runtime.preferences.monthlyReportNotificationEnabled = true

        await service.reschedule(shifts: runtime.shifts)
        #expect(fake.reportIDs.count == 2)
        runtime.preferences.yearlyReportNotificationEnabled = true
        await service.reschedule(shifts: runtime.shifts)
        #expect(fake.reportIDs.count == 3)
        for id in fake.reportIDs {
            let request = try #require(fake.requests[id])
            let link = try #require(request.content.userInfo["url"] as? String)
            let period = try #require(CycleReportPeriod(url: URL(string: link)!))
            #expect(id == period.notificationIdentifier)
            let copy = request.content.title + request.content.body
            #expect(copy.rangeOfCharacter(from: .decimalDigits) == nil)
        }

        runtime.preferences.monthlyReportNotificationEnabled = false
        await service.reschedule(shifts: runtime.shifts)
        #expect(fake.reportIDs.count == 2)
        #expect(fake.reportIDs.contains { $0.hasPrefix("owc.report.week.") })
        #expect(fake.reportIDs.contains { $0.hasPrefix("owc.report.year.") })

        runtime.preferences.yearlyReportNotificationEnabled = false
        await service.reschedule(shifts: runtime.shifts)
        #expect(fake.reportIDs.count == 1)
        #expect(fake.reportIDs[0].hasPrefix("owc.report.week."))

        runtime.preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = false }
        await service.reschedule(shifts: runtime.shifts)
        #expect(fake.reportIDs.isEmpty)
    }

    @Test("Without Plus or without permission nothing is scheduled; rescheduling does not double a request")
    @MainActor
    func gatesAndIdempotence() async throws {
        let (free, _, cleanFree) = try makeRuntime(plus: false)
        defer { cleanFree() }
        let fakeFree = FakeCenter()
        free.preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = true }
        await NotificationService(shiftCenter: fakeFree.center).reschedule(shifts: free.shifts)
        #expect(fakeFree.reportIDs.isEmpty)

        let (paid, _, cleanPaid) = try makeRuntime(plus: true)
        defer { cleanPaid() }
        let fake = FakeCenter()
        let service = NotificationService(shiftCenter: fake.center)
        paid.preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = true }
        await service.reschedule(shifts: paid.shifts)
        await service.reschedule(shifts: paid.shifts)
        #expect(fake.reportIDs.count == 1)

        fake.allowed = false
        await service.reschedule(shifts: paid.shifts)
        #expect(fake.reportIDs.isEmpty)
    }

    @Test("A user the schedule does not drive still gets their reports")
    @MainActor
    func reportsWithoutALiveSchedule() async throws {
        let (runtime, _, cleanup) = try makeRuntime(plus: true)
        defer { cleanup() }
        runtime.preferences.applyPreferences { $0.scheduleMode = .off }
        runtime.preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = true }
        let fake = FakeCenter()
        await NotificationService(shiftCenter: fake.center).rescheduleCycleReports(shifts: runtime.shifts)
        #expect(fake.reportIDs.count == 1)
    }

    @Test("The yearly preference starts off, persists locally, and has its own Plus gate")
    @MainActor
    func yearlyPreferenceAndGate() async throws {
        let (free, _, cleanFree) = try makeRuntime(plus: false)
        defer { cleanFree() }
        #expect(!free.preferences.yearlyReportNotificationEnabled)
        free.preferences.yearlyReportNotificationEnabled = true
        #expect(!free.shifts.yearlyReportNotificationsAreActive)
        let fakeFree = FakeCenter()
        await NotificationService(shiftCenter: fakeFree.center).rescheduleCycleReports(shifts: free.shifts)
        #expect(fakeFree.reportIDs.isEmpty)

        let (paid, defaults, cleanPaid) = try makeRuntime(plus: true)
        defer { cleanPaid() }
        #expect(!paid.preferences.yearlyReportNotificationEnabled)
        paid.preferences.yearlyReportNotificationEnabled = true
        #expect(paid.shifts.yearlyReportNotificationsAreActive)
        #expect(!paid.shifts.weeklyReportNotificationsAreActive)
        #expect(!paid.shifts.monthlyReportNotificationsAreActive)
        let reloaded = AppRuntime(defaults: defaults, records: .inMemory())
        #expect(reloaded.preferences.yearlyReportNotificationEnabled)
        paid.preferences.applyPreferences { $0.scheduleMode = .off }
        let fake = FakeCenter()
        let service = NotificationService(shiftCenter: fake.center)
        await service.rescheduleCycleReports(shifts: paid.shifts)
        await service.rescheduleCycleReports(shifts: paid.shifts)
        #expect(fake.reportIDs.count == 1)
        #expect(fake.reportIDs.first?.hasPrefix("owc.report.year.") == true)
        fake.allowed = false
        await service.rescheduleCycleReports(shifts: paid.shifts)
        #expect(fake.reportIDs.isEmpty)
    }

    @Test("A yearly request uses the Records zone and only follows completed onboarding")
    @MainActor
    func yearlyNotificationUsesRecordsZone() throws {
        let (runtime, _, cleanup) = try makeRuntime(plus: true)
        defer { cleanup() }
        runtime.preferences.yearlyReportNotificationEnabled = true
        runtime.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "America/New_York" }
        let calendar = runtime.preferences.recordsCalendar
        let now = Self.date(calendar, 2029, 1, 1, 8)
        let request = try #require(runtime.shifts.cycleReportNotifications(at: now).first)
        #expect(request.period.kind == .year)
        #expect(request.period.startDayKey == "2028-01-01")
        #expect(request.period.timeZoneIdentifier == "America/New_York")
        #expect(request.trigger.year == 2029 && request.trigger.month == 1 && request.trigger.day == 1)
        #expect(request.trigger.hour == 9 && request.trigger.minute == 0)
        #expect(request.trigger.timeZone?.identifier == "America/New_York")
        #expect(request.fireDate == Self.date(calendar, 2029, 1, 1, 9))
        runtime.preferences.onboardingComplete = false
        #expect(runtime.shifts.cycleReportNotifications(at: now).isEmpty)
    }

    @Test("Historical look-ahead starts after the report and excludes current leave balances")
    @MainActor
    func historicalQueryUsesItsOwnEnd() async throws {
        let (runtime, _, cleanup) = try makeRuntime(plus: true)
        defer { cleanup() }
        runtime.preferences.applyPreferences { $0.scheduleMode = .off }
        let calendar = runtime.preferences.recordsCalendar
        runtime.records.upsertLeaveBalance(LeaveBalance(id: UUID(), kind: .annual, name: nil,
            entitledHalfDays: 20, usedHalfDays: 3, validFromDayKey: nil, validThroughDayKey: nil))
        runtime.records.upsertLeaveDay(LeaveDay(dayKey: "2026-09-23", portion: .firstHalf,
            uses: [], planID: nil, timeZoneIdentifier: calendar.timeZone.identifier))
        let completed = try #require(await runtime.queries.cycleReportSnapshot(for: week, now: Self.date(calendar, 2026, 11, 15)))
        let historical = try #require(completed.ahead)
        #expect(historical.isHistorical)
        #expect(historical.nextBreak?.startDayKey == "2026-09-28")
        #expect(historical.nextBreak?.daysAway == 1)
        #expect(historical.leaveRemainingHalfDays == nil)
        #expect(historical.leaveEntitledHalfDays == nil)
        #expect(historical.leaveUsedHalfDays == 1)
        let current = try #require(await runtime.queries.cycleReportSnapshot(for: week, now: Self.date(calendar, 2026, 9, 24)))
        let live = try #require(current.ahead)
        #expect(!live.isHistorical)
        #expect(live.nextBreak?.startDayKey == "2026-09-25")
        #expect(live.leaveRemainingHalfDays == 17)
        #expect(live.leaveEntitledHalfDays == 20)
    }

    @Test("Annual Records queries return twelve calendar months and keep a lone focus round")
    @MainActor
    func annualQueryKeepsMonthlyFocus() async throws {
        let (runtime, _, cleanup) = try makeRuntime(plus: true)
        defer { cleanup() }
        runtime.preferences.applyPreferences { $0.scheduleMode = .off }
        let calendar = runtime.preferences.recordsCalendar
        let start = Self.date(calendar, 2024, 2, 29, 10)
        let end = start.addingTimeInterval(25 * 60)
        runtime.records.upsertFocusSession(FocusSession(id: UUID(), taskID: nil,
            shiftAnchorDate: calendar.startOfDay(for: start), startedAt: start, plannedEndAt: end,
            endedAt: end, endReason: .completed, editedAt: end, editCount: 1, editTieBreaker: UUID(),
            kind: .focus, timeZoneIdentifier: calendar.timeZone.identifier, anchorDayKey: "2024-02-29"), at: end)
        runtime.records.upsertLeaveDay(LeaveDay(dayKey: "2024-02-29", portion: .whole,
            uses: [], planID: nil, timeZoneIdentifier: calendar.timeZone.identifier))
        let year = runtime.queries.reportPeriod(.year, containing: start)
        let now = Self.date(calendar, 2025, 1, 2)
        let snapshot = try #require(await runtime.queries.cycleReportSnapshot(for: year, now: now))
        #expect(snapshot.hasData)
        #expect(CycleReportStage.stages(for: snapshot).contains(.focus))
        #expect(snapshot.days.count == 366)
        #expect(snapshot.months.count == 12)
        #expect(snapshot.months.first?.period.startDayKey == "2024-01-01")
        #expect(snapshot.months.last?.period.endDayKey == "2024-12-31")
        #expect(snapshot.months[1].period.endDayKey == "2024-02-29")
        #expect(snapshot.months[1].focusRounds == 1)
        #expect(snapshot.months.filter { $0.focusRounds > 0 }.count == 1)
        #expect(snapshot.focus?.rounds == 1)
        #expect(snapshot.focus?.perDay[59] == 1)
        #expect(snapshot.leaveUsedHalfDays == 2)
        #expect(snapshot.baseline == nil && snapshot.ahead == nil)
        let month = try #require(await runtime.queries.cycleReportSnapshot(for: snapshot.months[1].period, now: now))
        #expect(snapshot.months[1].figures == month.figures)
        #expect(snapshot.months[1].restDayCount == month.restDayCount)
        #expect(month.focus == nil)
    }

    @Test("Pay a report was asked to show is not masked by the global hide setting")
    @MainActor
    func chosenPayIsNotMasked() throws {
        let (runtime, _, cleanup) = try makeRuntime(plus: true)
        defer { cleanup() }
        runtime.preferences.hideEarnings = true
        let copy = CycleReportCopy(text: runtime.text, queries: runtime.queries)
        #expect(runtime.text.moneyText(1_234.5) == "••••")
        #expect(copy.money(1_234.5) == runtime.text.formatMoney(1_234.5))
        #expect(!copy.money(1_234.5).contains("•"))
    }

    @Test("The old 100% reminder no longer carries a cycle summary")
    @MainActor
    func noMoreStaticSummaryInTheReminder() throws {
        let (runtime, _, cleanup) = try makeRuntime(plus: true)
        defer { cleanup() }
        runtime.preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = true }
        runtime.preferences.applyPreferences { $0.notificationMode = .off }
        #expect(runtime.shifts.reminderInputs().cycleEndSummaryBody == nil)
    }
}
