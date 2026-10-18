import Foundation
import WidgetKit

/// Builds the widget suite's payloads (plan 023) from what the app already
/// resolves: Records' day resolution, cycle reports, the holiday calendar,
/// Life's profile, leave and Focus. Nothing here derives a schedule; every
/// work segment comes from `RecordsQueries.resolvedDays`, which goes through
/// the shared rules.
@MainActor
final class WidgetSuiteComposer {
    static let shared = WidgetSuiteComposer()

    /// Last bytes written per file, so an unchanged payload neither rewrites
    /// the App Group nor spends a WidgetKit reload.
    private var lastWritten: [WidgetSuiteFile: Data] = [:]

    func publish(shifts: ShiftSessionStore, now: Date = .now) async {
        let locale = shifts.preferences.languageCode
        let access = Self.access(for: shifts.plus)
        let calendar = calendarPayload(shifts: shifts, now: now, locale: locale)
        write(calendar, to: .calendar)
        write(holidayPayload(shifts: shifts, calendar: calendar, access: access, now: now, locale: locale), to: .holiday)
        write(lifePayload(shifts: shifts, access: access, now: now, locale: locale), to: .life)
        write(focusPayload(shifts: shifts, access: access, now: now, locale: locale), to: .focus)
        let summary = await summaryPayload(shifts: shifts, calendar: calendar, access: access, now: now, locale: locale)
        guard !Task.isCancelled else { return }
        write(summary, to: .summary)
    }

    func clear() {
        for file in WidgetSuiteFile.allCases {
            if let url = WidgetSuiteStore.url(file) { try? FileManager.default.removeItem(at: url) }
        }
        lastWritten.removeAll()
        for kind in WidgetSuiteKind.all { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }

    // MARK: Access

    static func access(for plus: PlusEntitlement) -> WidgetAccess {
        switch plus.authorization {
        case .authorized(.lifetime):
            WidgetAccess(plus: true, validUntilMs: nil)
        case .authorized(.subscribed(let expiresAt)):
            WidgetAccess(plus: true, validUntilMs: WidgetSuiteTime.ms(expiresAt))
        case .authorized(.inGracePeriod(let graceExpiresAt)):
            WidgetAccess(plus: true, validUntilMs: WidgetSuiteTime.ms(graceExpiresAt))
        case .unauthorized, .pendingAskToBuy:
            .locked
        }
    }

    // MARK: Calendar

    func calendarPayload(shifts: ShiftSessionStore, now: Date, locale: String) -> WidgetCalendarPayload {
        let text = shifts.text
        let queries = shifts.queries
        let calendar = queries.recordsGridCalendar
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let start = min(weekStart, monthStart)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? today
        let nextMonthEnd = calendar.dateInterval(of: .month, for: nextMonth)?.end
        let end = nextMonthEnd.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) } ?? today

        let kind = scheduleKind(shifts: shifts, at: now)
        let plan = shifts.session.extendedSchedulePlan(at: now)
        let resolver = plan.map(ExtendedScheduleResolver.init(plan:))
        let region = shifts.preferences.isExtendedScheduleEnabled
            ? shifts.preferences.extendedScheduleContent?.holidayRegionIdentifier : nil
        let leaveKeys = Set(shifts.records.state.leaveDays.map(\.dayKey))

        var days: [WidgetCalendarDay] = []
        if kind != .none {
            for resolution in queries.resolvedDays(from: start, through: end, now: now) {
                guard let date = RecordJSON.date(fromDayKey: resolution.dayKey, calendar: calendar) else { continue }
                let holiday = HolidayDayAnnotation.make(dayKey: resolution.dayKey, region: region, language: locale)
                let segments = resolution.segments.map { [Int64($0.startAtMs), Int64($0.endAtMs)] }
                let type = resolver.flatMap { resolver in
                    ExtendedScheduleResolver.dayNumber(dayKey: resolution.dayKey).flatMap { number in
                        resolver.day(dayNumber: number).shiftTypeID
                    }
                }.flatMap { id in plan?.shiftTypes.first { $0.id == id } }

                let dayKind: WidgetCalendarDay.Kind
                var title: String?
                if leaveKeys.contains(resolution.dayKey), segments.isEmpty {
                    dayKind = .leave
                } else if resolution.isScheduledWorkday, !segments.isEmpty {
                    dayKind = holiday?.isMakeupWorkday == true ? .makeupWork : .work
                    title = type?.name
                } else if let holiday, !holiday.isMakeupWorkday {
                    dayKind = .holiday
                    title = holiday.name
                } else {
                    dayKind = .rest
                    title = type.flatMap { $0.kind == .rest ? $0.name : nil }
                }
                let cycle = rotationCycle(shifts: shifts, plan: plan, dayKey: resolution.dayKey, date: date)
                days.append(WidgetCalendarDay(
                    dayKey: resolution.dayKey,
                    startMs: WidgetSuiteTime.ms(date),
                    kind: dayKind,
                    title: title,
                    colorHex: dayKind == .work || dayKind == .makeupWork ? type?.colorHex : nil,
                    segments: dayKind == .work || dayKind == .makeupWork ? segments : [],
                    cycleDay: cycle?.day,
                    cycleLength: cycle?.length
                ))
            }
        }

        let weekdays = text.weekdayLabels()
        return WidgetCalendarPayload(
            generatedAtMs: WidgetSuiteTime.ms(now),
            locale: locale,
            timeZoneIdentifier: calendar.timeZone.identifier,
            firstWeekday: calendar.firstWeekday,
            scheduleKind: kind,
            days: days,
            labels: [
                WidgetCalendarLabel.work: text.t("widgetSuiteWork"),
                WidgetCalendarLabel.rest: text.t("widgetSuiteRest"),
                WidgetCalendarLabel.leave: text.t("widgetSuiteLeave"),
                WidgetCalendarLabel.makeupWork: text.t("widgetSuiteMakeupWork"),
                WidgetCalendarLabel.bigWeek: text.t("widgetSuiteBigWeek"),
                WidgetCalendarLabel.smallWeek: text.t("widgetSuiteSmallWeek"),
                WidgetCalendarLabel.weekdaysShort: weekdays.joined(separator: "|"),
            ]
        )
    }

    private func scheduleKind(shifts: ShiftSessionStore, at now: Date) -> WidgetCalendarPayload.ScheduleKind {
        guard shifts.session.followsSchedule(at: now) else { return .none }
        if shifts.preferences.isExtendedScheduleEnabled, let rule = shifts.session.extendedSchedulePlan(at: now)?.rule {
            return switch rule.preset {
            case .weekly: .weekly
            case .alternatingWeeks: .alternatingWeeks
            case .rotation: .rotation
            case .custom: .custom
            }
        }
        return switch shifts.preferences.scheduleMode {
        case .classic: .weekly
        case .alternating: .alternatingWeeks
        case .rotation: .rotation
        case .off: .none
        }
    }

    private func rotationCycle(
        shifts: ShiftSessionStore, plan: ExtendedSchedulePlan?, dayKey: String, date: Date
    ) -> (day: Int, length: Int)? {
        if shifts.preferences.isExtendedScheduleEnabled, let plan {
            guard let rule = plan.rule, rule.preset == .rotation, !rule.days.isEmpty,
                  let anchor = ExtendedScheduleResolver.dayNumber(dayKey: rule.anchorDayKey),
                  let number = ExtendedScheduleResolver.dayNumber(dayKey: dayKey) else { return nil }
            let length = rule.days.count
            return (((number - anchor) % length + length) % length + 1, length)
        }
        guard shifts.preferences.scheduleMode == .rotation else { return nil }
        return (shifts.preferences.rotationCycleDay(at: date), shifts.preferences.rotationCycleLength)
    }

    // MARK: Holidays and leave

    func holidayPayload(
        shifts: ShiftSessionStore, calendar payload: WidgetCalendarPayload,
        access: WidgetAccess, now: Date, locale: String
    ) -> WidgetHolidayPayload {
        let text = shifts.text
        let nowMs = WidgetSuiteTime.ms(now)
        let days = payload.days

        // The end of the last workday before the next day off.
        var weekendStartMs: Int64?
        if let todayIndex = payload.dayIndex(containingMs: nowMs),
           let offIndex = days[todayIndex...].firstIndex(where: { !$0.isWork }),
           let end = days[todayIndex..<offIndex].last(where: \.isWork)?.endAtMs,
           end > nowMs {
            weekendStartMs = end
        }

        let calendar = shifts.queries.recordsGridCalendar
        let region = shifts.preferences.isExtendedScheduleEnabled
            ? shifts.preferences.extendedScheduleContent?.holidayRegionIdentifier : nil
        let nextHoliday = region.flatMap { nextHoliday(region: $0, from: now, calendar: calendar, locale: locale) }

        var nextLeave: WidgetHolidayPayload.Leave?
        var remaining: Double?
        if access.isUnlocked(atMs: nowMs) {
            nextLeave = self.nextLeave(shifts: shifts, days: days, nowMs: nowMs, calendar: calendar)
            let today = RecordJSON.dayKey(now, calendar: calendar)
            let balances = shifts.records.state.leaveBalances.filter { balance in
                balance.isValid && (balance.validThroughDayKey.map { $0 >= today } ?? true)
            }
            if !balances.isEmpty {
                remaining = Double(balances.reduce(0) { $0 + $1.remainingHalfDays }) / 2
            }
        }

        let weekly = payload.scheduleKind == .weekly || payload.scheduleKind == .alternatingWeeks
        return WidgetHolidayPayload(
            generatedAtMs: nowMs,
            locale: locale,
            weekendStartMs: weekendStartMs,
            nextHoliday: nextHoliday,
            access: access,
            nextLeave: nextLeave,
            leaveRemainingDays: remaining,
            labels: [
                "untilRest": text.t(weekly ? "widgetSuiteUntilWeekend" : "widgetSuiteUntilRestDay"),
                "remaining": remaining.map { text.t("widgetSuiteLeaveRemaining", values: ["days": text.formatDays($0)]) } ?? "",
                "requested": nextLeave.map { text.t("widgetSuiteLeavePlan", values: [
                    "leave": text.formatDays($0.requestedDays),
                    "total": text.formatDays(Double($0.totalDays)),
                ]) } ?? "",
                "holidayDays": nextHoliday.map { text.formatDays(Double($0.days)) } ?? "",
                "holidayDate": nextHoliday.flatMap { holiday in
                    RecordJSON.date(fromDayKey: holiday.startDayKey, calendar: calendar).map { text.relativeDayLabel(for: $0, from: now) }
                } ?? "",
            ]
        )
    }

    /// The next run of days off the holiday calendar names, with the weekend
    /// days that join it. Never predicts a year the calendar does not cover.
    private func nextHoliday(region: String, from now: Date, calendar: Calendar, locale: String) -> WidgetHolidayPayload.Holiday? {
        let today = calendar.startOfDay(for: now)
        func annotation(_ date: Date) -> HolidayDayAnnotation? {
            HolidayDayAnnotation.make(dayKey: RecordJSON.dayKey(date, calendar: calendar), region: region, language: locale)
        }
        func isWeekend(_ date: Date) -> Bool { calendar.isDateInWeekend(date) }
        for offset in 0..<400 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                  let first = annotation(date), !first.isMakeupWorkday else { continue }
            var start = date
            while let previous = calendar.date(byAdding: .day, value: -1, to: start), previous >= today,
                  isWeekend(previous), annotation(previous)?.isMakeupWorkday != true {
                start = previous
            }
            var end = date
            while let next = calendar.date(byAdding: .day, value: 1, to: end) {
                if let holiday = annotation(next) {
                    if holiday.isMakeupWorkday { break }
                } else if !isWeekend(next) {
                    break
                }
                end = next
            }
            let count = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
            return .init(
                name: first.name,
                startDayKey: RecordJSON.dayKey(start, calendar: calendar),
                startMs: WidgetSuiteTime.ms(start),
                endDayKey: RecordJSON.dayKey(end, calendar: calendar),
                days: count,
                isEstimated: first.isEstimated
            )
        }
        return nil
    }

    /// The next leave the user recorded or adopted, with the days off that
    /// join it on either side.
    private func nextLeave(
        shifts: ShiftSessionStore, days: [WidgetCalendarDay], nowMs: Int64, calendar: Calendar
    ) -> WidgetHolidayPayload.Leave? {
        let todayKey = RecordJSON.dayKey(WidgetSuiteTime.date(nowMs), calendar: calendar)
        let leaves = Dictionary(shifts.records.state.leaveDays.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
        guard let firstKey = leaves.keys.filter({ $0 >= todayKey }).min(),
              var index = days.firstIndex(where: { $0.dayKey == firstKey }) else { return nil }
        while index > 0, !days[index - 1].isWork, days[index - 1].dayKey >= todayKey { index -= 1 }
        var run: [WidgetHolidayPayload.Leave.Day] = []
        var requested = 0.0
        var cursor = index
        while cursor < days.count, !days[cursor].isWork || leaves[days[cursor].dayKey] != nil {
            let day = days[cursor]
            if let leave = leaves[day.dayKey] {
                requested += Double(leave.portion.halfDays) / 2
                run.append(.init(dayKey: day.dayKey, kind: .leave))
            } else {
                run.append(.init(dayKey: day.dayKey, kind: day.kind == .holiday ? .holiday : .rest))
            }
            cursor += 1
        }
        guard let first = run.first, requested > 0 else { return nil }
        return .init(
            startDayKey: first.dayKey,
            startMs: days[index].startMs,
            requestedDays: requested,
            totalDays: run.count,
            days: run
        )
    }

    // MARK: Life

    func lifePayload(shifts: ShiftSessionStore, access: WidgetAccess, now: Date, locale: String) -> WidgetLifePayload {
        let nowMs = WidgetSuiteTime.ms(now)
        let base = WidgetLifePayload(
            generatedAtMs: nowMs, locale: locale, access: access, bornDay: nil, bornIsApproximate: false,
            careerStartDay: nil, retirementDay: nil, lifeYears: 80, hidesExactAges: false, labels: [:]
        )
        guard access.isUnlocked(atMs: nowMs), var profile = shifts.records.state.lifeProfile else { return base }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        profile.migrateLegacyFields(calendar: calendar)
        func dayNumber(_ date: Date?) -> Int? {
            date.map { Int(floor(calendar.startOfDay(for: $0).timeIntervalSince1970 / 86_400 + 0.5)) }
        }
        let born = profile.bornOn?.calculationAnchor(in: calendar)
        let career = profile.workStartedPartial?.calculationAnchor(in: calendar)
            ?? profile.workStartedOn
            ?? born.flatMap { calendar.date(byAdding: .year, value: 22, to: $0) }
        let retirement = profile.retirementOn?.calculationAnchor(in: calendar)
        var payload = base
        payload.bornDay = dayNumber(born)
        payload.bornIsApproximate = profile.bornOn?.precision == .year
        payload.careerStartDay = dayNumber(career)
        payload.retirementDay = dayNumber(retirement)
        payload.hidesExactAges = profile.hidesExactAges
        return payload
    }

    // MARK: Focus

    func focusPayload(shifts: ShiftSessionStore, access: WidgetAccess, now: Date, locale: String) -> WidgetFocusPayload {
        let nowMs = WidgetSuiteTime.ms(now)
        var payload = WidgetFocusPayload(generatedAtMs: nowMs, locale: locale, access: access, blocks: [], labels: [:])
        guard access.isUnlocked(atMs: nowMs) else { return payload }
        let text = shifts.text
        let focus = shifts.focus
        var blocks: [WidgetFocusPayload.Block] = []
        if let session = focus.activeFocusSession() {
            for leg in focus.focusChain(for: session, at: now) {
                let isBreak = leg.kind != .focus
                blocks.append(.init(
                    title: isBreak ? text.t("focusBreak") : (leg.taskTitle ?? text.t("focusTitle")),
                    symbol: isBreak ? "cup.and.saucer.fill" : leg.icon?.systemName,
                    startMs: WidgetSuiteTime.ms(leg.start),
                    endMs: WidgetSuiteTime.ms(leg.end),
                    round: leg.pomodoroIndex ?? 1,
                    rounds: leg.pomodoroTotal ?? 1,
                    isBreak: isBreak
                ))
            }
        }
        let canvas = focus.focusDayCanvas(at: now)
        let afterMs = blocks.last?.endMs ?? nowMs
        for block in canvas.blocks where block.startAtMs >= afterMs && block.taskID != nil {
            guard blocks.count < 6 else { break }
            blocks.append(.init(
                title: block.taskTitle ?? text.t("focusTitle"),
                symbol: block.taskIcon?.systemName,
                startMs: block.startAtMs,
                endMs: block.endAtMs,
                round: 1,
                rounds: 1,
                isBreak: false
            ))
        }
        payload.blocks = blocks
        payload.labels = [
            "minutes": text.t("widgetSuiteMinutes"),
        ]
        return payload
    }

    // MARK: Summary

    func summaryPayload(
        shifts: ShiftSessionStore, calendar payload: WidgetCalendarPayload,
        access: WidgetAccess, now: Date, locale: String
    ) async -> WidgetSummaryPayload {
        let nowMs = WidgetSuiteTime.ms(now)
        var result = WidgetSummaryPayload(
            generatedAtMs: nowMs, locale: locale, access: access, periods: [], liveSegments: [], labels: [:]
        )
        guard access.isUnlocked(atMs: nowMs) else { return result }
        let text = shifts.text
        let queries = shifts.queries
        let calendar = queries.recordsGridCalendar
        let todayKey = RecordJSON.dayKey(now, calendar: calendar)
        let dayByKey = Dictionary(payload.days.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })

        for kind in WidgetSummaryPeriod.Kind.allCases {
            let reportKind: CycleReportKind = switch kind {
            case .week: .week
            case .month: .month
            case .year: .year
            }
            let period = CycleReportPeriod.containing(now, kind: reportKind, calendar: calendar)
            guard let snapshot = await queries.cycleReportSnapshot(for: period, now: now) else { continue }
            guard !Task.isCancelled else { return result }

            let resolutions = period.startDate(calendar: calendar).flatMap { start in
                period.endDate(calendar: calendar).map { queries.resolvedDays(from: start, through: $0, now: now) }
            } ?? []
            let planned = resolutions.filter { $0.isScheduledWorkday && !$0.segments.isEmpty }
            let remaining = planned.filter { $0.dayKey > todayKey }.count
            let worked = snapshot.figures.workdays

            var bars: [WidgetSummaryPeriod.Bar] = []
            if kind == .year {
                let labels = (1...12).map { text.formatCount($0) }
                for (index, month) in snapshot.months.enumerated() {
                    let isCurrent = month.period.startDayKey <= todayKey && todayKey <= month.period.endDayKey
                    let isFuture = month.period.startDayKey > todayKey
                    bars.append(.init(label: labels[min(index, 11)], valueMs: month.figures.workedMs,
                                      state: isCurrent ? .current : (isFuture ? .future : .past)))
                }
            } else if kind == .week {
                for day in snapshot.days {
                    let date = day.date
                    let state: WidgetSummaryPeriod.Bar.State = day.isToday ? .current
                        : (day.kind == .upcoming ? .future : (day.kind == .rest ? .rest : .past))
                    bars.append(.init(label: text.weekdayName(for: date), valueMs: day.workMs, state: state))
                }
            }

            let previous = await previousTotal(queries: queries, period: period, calendar: calendar, now: now)
            let title: String = switch kind {
            case .week: text.t("widgetSuiteThisWeek")
            case .month: text.t("widgetSuiteThisMonth")
            case .year: text.t("widgetSuiteThisYear")
            }
            let comparisonKey: String = switch kind {
            case .week: "widgetSuiteLastWeekTotal"
            case .month: "widgetSuiteLastMonthTotal"
            case .year: "widgetSuiteLastYearTotal"
            }
            result.periods.append(WidgetSummaryPeriod(
                kind: kind,
                title: title,
                subtitle: subtitle(kind: kind, period: period, calendar: calendar, text: text),
                startDayKey: period.startDayKey,
                endDayKey: period.endDayKey,
                workedMs: snapshot.figures.workedMs,
                overtimeMs: snapshot.figures.overtimeMs,
                workdays: worked,
                plannedWorkdays: max(planned.count, worked),
                remainingWorkdays: remaining,
                progress: planned.isEmpty ? 0 : min(1, Double(planned.count - remaining) / Double(planned.count)),
                bars: bars,
                comparison: previous.map { text.t(comparisonKey, values: ["hours": text.formatHours(Double($0) / 3_600_000)]) },
                includesToday: true
            ))
        }

        if shifts.session.countdownStarted, let today = dayByKey[todayKey] {
            result.liveSegments = today.segments.filter { $0[1] > nowMs }
        }
        result.labels = [
            "hoursUnit": text.formatHours(0).replacingOccurrences(of: "0", with: "").trimmingCharacters(in: .whitespaces),
        ]
        return result
    }

    private func previousTotal(
        queries: RecordsQueries, period: CycleReportPeriod, calendar: Calendar, now: Date
    ) async -> Int64? {
        guard let previous = period.previous(calendar: calendar),
              let snapshot = await queries.cycleReportSnapshot(for: previous, now: now),
              snapshot.figures.hasData else { return nil }
        return snapshot.figures.workedMs
    }

    private func subtitle(kind: WidgetSummaryPeriod.Kind, period: CycleReportPeriod, calendar: Calendar, text: AppText) -> String? {
        guard let start = period.startDate(calendar: calendar) else { return nil }
        switch kind {
        case .week:
            return text.t("widgetSuiteWeekNumber", values: ["week": text.formatCount(calendar.component(.weekOfYear, from: start))])
        case .month:
            return text.formatCivilDate(year: calendar.component(.year, from: start),
                                        month: calendar.component(.month, from: start), template: "MMMM")
        case .year:
            return text.formatYear(calendar.component(.year, from: start))
        }
    }

    // MARK: Writing

    private func write<Payload: Encodable>(_ payload: Payload, to file: WidgetSuiteFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let url = WidgetSuiteStore.url(file) else { return }
        // Generation time changes on every call; compare without it.
        let comparable = Self.withoutGenerationTime(data)
        if let previous = lastWritten[file], previous == comparable { return }
        do {
            try data.write(to: url, options: .atomic)
            lastWritten[file] = comparable
            for kind in file.kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        } catch {
            lastWritten[file] = nil
        }
    }

    private static func withoutGenerationTime(_ data: Data) -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        object["generatedAtMs"] = nil
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? data
    }
}
