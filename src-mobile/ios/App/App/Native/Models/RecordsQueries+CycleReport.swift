import Foundation

extension RecordsQueries {
    /// The week or month holding `date`, cut the way Records cuts them.
    func reportPeriod(_ kind: CycleReportKind, containing date: Date) -> CycleReportPeriod {
        CycleReportPeriod.containing(date, kind: kind, calendar: recordsGridCalendar)
    }

    /// Reads a period the way the Records page does: one day of lead-in for a
    /// shift that began the night before, the same cells and the same headline.
    /// `nil` when the period names dates this calendar cannot read.
    func cycleReportSnapshot(for period: CycleReportPeriod, now: Date = .now) async -> CycleReportSnapshot? {
        let calendar = recordsGridCalendar
        guard let measured = await reportMeasurement(of: period, calendar: calendar, now: now) else { return nil }
        let previous: CycleReportFigures?
        if let before = period.previous(calendar: calendar) {
            previous = await reportMeasurement(of: before, calendar: calendar, now: now)?.figures
        } else {
            previous = nil
        }
        return CycleReportBuilder.snapshot(
            period: period,
            cells: measured.cells,
            figures: measured.figures,
            previous: previous,
            isInProgress: !period.isComplete(at: now, calendar: calendar)
        )
    }

    private func reportMeasurement(
        of period: CycleReportPeriod,
        calendar: Calendar,
        now: Date
    ) async -> (cells: [RecordsDayCell], figures: CycleReportFigures)? {
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
        return (cells, CycleReportFigures(headline: headline))
    }
}
