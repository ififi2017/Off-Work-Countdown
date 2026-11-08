import Foundation

extension RecordsQueries {
    /// Plan 021: the planned shifts around `date` that automation events can
    /// match, from the same three-layer resolution Records uses.
    ///
    /// Calendar exceptions (holidays, makeup days) and leave decide whether a
    /// day has a shift. A day the person marked as not working has none. The
    /// day's own override is left out on purpose: it holds the adopted times
    /// automation compares against, not the plan, which stays the baseline for
    /// overtime (§3.2).
    func automationShifts(around date: Date) -> [AutomationShift] {
        let calendar = recordsCalendar
        guard let from = calendar.date(byAdding: .day, value: -1, to: date),
              let through = calendar.date(byAdding: .day, value: 1, to: date)
        else { return [] }
        let state = records.state
        let restDays = Set(
            state.overrides
                .filter { $0.kind == .notWorking && !state.isErased(.dayOverride, key: $0.dayKey) }
                .map(\.dayKey)
        )
        let days = Self.walkResolutions(
            from: calendar.startOfDay(for: from),
            through: calendar.startOfDay(for: through),
            calendar: calendar,
            periods: state.periods,
            snapshots: state.snapshots,
            exceptions: state.exceptions,
            overrides: [],
            leaveDays: state.leaveDays,
            expansions: gatherScheduleExpansions(
                from: from,
                through: through,
                periods: state.periods,
                snapshots: state.snapshots
            )
        )
        return days.compactMap { day in
            guard day.isScheduledWorkday, !day.expansionFailed, !restDays.contains(day.dayKey),
                  let first = day.segments.first, let last = day.segments.last
            else { return nil }
            return AutomationShift(
                shiftKey: "\(day.dayKey)#\(Int64(first.startAtMs))",
                anchorDayKey: day.dayKey,
                plannedStart: Date(timeIntervalSince1970: first.startAtMs / 1_000),
                plannedEnd: Date(timeIntervalSince1970: last.endAtMs / 1_000),
                segments: day.segments
            )
        }
    }
}
