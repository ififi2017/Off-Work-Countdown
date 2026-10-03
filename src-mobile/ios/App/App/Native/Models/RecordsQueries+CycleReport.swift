import Foundation

extension RecordsQueries {
    /// The week, month or year holding `date`, cut the way Records cuts them.
    func reportPeriod(_ kind: CycleReportKind, containing date: Date) -> CycleReportPeriod {
        CycleReportPeriod.containing(date, kind: kind, calendar: recordsGridCalendar)
    }

    /// Reads a period the way the Records page does: one day of lead-in for a
    /// shift that began the night before, the same cells and the same headline.
    /// The insights beside it come from records the app already keeps. `nil`
    /// when the period names dates this calendar cannot read.
    func cycleReportSnapshot(for period: CycleReportPeriod, now: Date = .now) async -> CycleReportSnapshot? {
        let calendar = recordsGridCalendar
        guard let measured = await reportMeasurement(of: period, calendar: calendar, now: now) else { return nil }
        let isInProgress = !period.isComplete(at: now, calendar: calendar)

        // The person's own past: up to four weeks or three months before.
        var priors: [CycleReportFigures] = []
        if !isInProgress, period.kind != .year {
            var cursor = period
            for _ in 0..<(period.kind == .week ? 4 : 3) {
                guard let before = cursor.previous(calendar: calendar),
                      let earlier = await reportMeasurement(of: before, calendar: calendar, now: now)
                else { break }
                priors.append(earlier.figures)
                cursor = before
            }
        }
        guard !Task.isCancelled else { return nil }

        var months: [CycleReportMonth] = []
        if period.kind == .year, let start = period.startDate(calendar: calendar) {
            for offset in 0..<12 {
                guard !Task.isCancelled,
                      let date = calendar.date(byAdding: .month, value: offset, to: start) else { return nil }
                let month = CycleReportPeriod.containing(date, kind: .month, calendar: calendar)
                guard let measuredMonth = await reportMeasurement(of: month, calendar: calendar, now: now) else { return nil }
                let snapshot = CycleReportBuilder.snapshot(period: month, cells: measuredMonth.cells,
                    figures: measuredMonth.figures, isInProgress: !month.isComplete(at: now, calendar: calendar))
                months.append(CycleReportMonth(period: month, figures: measuredMonth.figures,
                    restDayCount: snapshot.restDayCount, focusRounds: reportFocus(period: month, calendar: calendar, minimumRounds: 1)?.rounds ?? 0))
            }
        }
        guard !Task.isCancelled else { return nil }
        let extras = CycleReportExtras(
            priors: priors,
            ahead: period.kind == .year ? nil : reportAhead(period: period, calendar: calendar, now: now),
            focus: reportFocus(period: period, calendar: calendar, minimumRounds: period.kind == .year ? 1 : CycleReportFocus.minimumRounds),
            months: months,
            leaveUsedHalfDays: reportLeaveUsed(period: period, calendar: calendar, now: now),
            overtimeIsPaid: reportOvertimeIsPaid
        )
        return CycleReportBuilder.snapshot(
            period: period, cells: measured.cells, figures: measured.figures,
            extras: extras, isInProgress: isInProgress
        )
    }

    private func reportMeasurement(
        of period: CycleReportPeriod,
        calendar: Calendar,
        now: Date
    ) async -> (cells: [RecordsDayCell], days: [DayResolution], figures: CycleReportFigures)? {
        guard let start = period.startDate(calendar: calendar),
              let end = period.endDate(calendar: calendar),
              let leadIn = calendar.date(byAdding: .day, value: -1, to: start)
        else { return nil }
        let resolved = await prepareRecordsDisplayDays(from: leadIn, through: end, now: now)
        guard !Task.isCancelled else { return nil }
        let recordsCalendar = self.recordsCalendar
        let firstKey = RecordJSON.dayKey(start, calendar: recordsCalendar)
        var cells: [RecordsDayCell] = []
        for (index, day) in resolved.enumerated() where day.dayKey >= firstKey {
            cells.append(recordsDayCell(
                for: day,
                previous: index > 0 ? resolved[index - 1] : nil,
                now: now,
                includesLifeProjection: true
            ))
        }
        let headline = recordsHeadline(cells: cells, days: resolved, now: now)
        return (cells, resolved, CycleReportFigures(headline: headline))
    }

    // MARK: Insights

    /// Leave taken in the period, what is left to take, and the next run of
    /// three or more days off in the live schedule (adopted leave and holidays
    /// included), counted from the period end for completed reports.
    private func reportAhead(period: CycleReportPeriod, calendar: Calendar, now: Date) -> CycleReportAhead? {
        let recordsCalendar = self.recordsCalendar
        let today = period.referenceDate(at: now, calendar: calendar)
        let historical = period.isComplete(at: now, calendar: calendar)
        guard let tomorrow = recordsCalendar.date(byAdding: .day, value: 1, to: today),
              let through = recordsCalendar.date(byAdding: .day, value: CycleReportAhead.horizonDays - 1, to: tomorrow)
        else { return nil }
        let upcoming = resolvedDays(from: tomorrow, through: through, now: now).map { day in
            (dayKey: day.dayKey,
             date: recordsCalendar.startOfDay(for: day.shiftAnchorDate),
             isRest: !day.isScheduledWorkday || day.segments.isEmpty)
        }
        let state = records.state
        let used = reportLeaveUsed(period: period, calendar: calendar, now: now)
        var remaining: Int?
        var entitled: Int?
        if !historical, !state.leaveBalances.isEmpty {
            let todayNumber = ExtendedScheduleResolver.dayNumber(dayKey: RecordJSON.dayKey(today, calendar: recordsCalendar))
            let live = LeaveAdoption.budgets(balances: state.leaveBalances, leaveDays: state.leaveDays)
                .filter { budget in todayNumber.map(budget.covers(dayNumber:)) ?? true }
            remaining = live.reduce(0) { $0 + $1.availableHalfDays }
            let liveIDs = Set(live.map(\.id))
            entitled = state.leaveBalances.filter { liveIDs.contains($0.id) }.reduce(0) { $0 + $1.entitledHalfDays }
        }
        var ahead = CycleReportAhead.make(upcoming: upcoming, leaveUsedHalfDays: used, leaveRemainingHalfDays: remaining,
                                         leaveEntitledHalfDays: entitled)
        ahead?.isHistorical = historical
        return ahead
    }

    private func reportLeaveUsed(period: CycleReportPeriod, calendar: Calendar, now: Date) -> Int {
        let keys = Set(period.dayKeys(calendar: calendar))
        let todayKey = RecordJSON.dayKey(now, calendar: calendar)
        return records.state.leaveDays.filter { keys.contains($0.dayKey) && $0.dayKey <= todayKey }
            .reduce(0) { $0 + $1.portion.halfDays }
    }

    private func reportFocus(period: CycleReportPeriod, calendar: Calendar, minimumRounds: Int = CycleReportFocus.minimumRounds) -> CycleReportFocus? {
        let keys = period.dayKeys(calendar: calendar)
        let index = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        let state = records.state
        let icons = Dictionary(state.focusTasks.map { ($0.id, $0.icon) }, uniquingKeysWith: { first, _ in first })
        var rounds: [(dayIndex: Int, ms: Int64, icon: FocusTaskIcon?)] = []
        for session in state.focusSessions where session.kind == .focus && session.endReason == .completed {
            let key = session.anchorDayKey ?? RecordJSON.dayKey(session.startedAt, calendar: recordsCalendar)
            guard let dayIndex = index[key] else { continue }
            let ms = session.actualDurationSeconds.map { Int64($0) * 1_000 }
                ?? Int64(max(0, (session.endedAt ?? session.plannedEndAt).timeIntervalSince(session.startedAt) * 1_000))
            rounds.append((dayIndex, ms, session.taskID.flatMap { icons[$0] }))
        }
        return CycleReportFocus.make(rounds: rounds, dayCount: keys.count, minimumRounds: minimumRounds)
    }
}
