import Foundation

extension OffWorkStore {
    /// Whether the pomodoro owns the break rhythm for the shift being drawn.
    ///
    /// The health reminder and the pomodoro both say "time to get up", on
    /// different clocks — every 60 minutes by default against a break every 25.
    /// Once a shift has a plan, the plan is the answer, so the reminder follows
    /// it instead of running its own schedule alongside it.
    ///
    /// Keyed on the plan rather than on a running session because notifications
    /// are scheduled up front: a phone cannot decide this at firing time. It
    /// also means someone who plans a day but never presses start still gets
    /// reminded.
    func focusOwnsBreaks(at date: Date = .now) -> Bool {
        guard microBreakEnabled, plus.isAuthorized, let shift = focusCanvasShift(at: date)?.snapshot else { return false }
        let dayKey = RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar)
        return focusPlanning.plans[dayKey]?.assignments.contains { $0.kind == .task && $0.taskID != nil } ?? false
    }

    /// The reminders that stand in for the fixed-interval ones.
    ///
    /// Only long breaks. They land roughly every two hours on the default
    /// cadence — the same order of magnitude as the 60-minute health reminder —
    /// whereas notifying on every short break would triple the interruptions.
    /// A short break is already announced by the running block's own end
    /// notification, and when nothing is running the user is not in that rhythm
    /// anyway.
    func focusBreakReminders(at date: Date = .now) -> [NativeReminder] {
        guard focusOwnsBreaks(at: date) else { return [] }
        let nowMs = date.timeIntervalSince1970 * 1_000
        return focusTemplateBlocks(at: date)
            .filter { $0.breakKind == .longBreak }
            .filter { Double($0.startAtMs) > nowMs }
            .map { block in
                NativeReminder(
                    // Same shape as the rule bundle's ids so the scheduler's
                    // "owc.shift." prefix housekeeping keeps working.
                    id: "focusBreak:\(block.startAtMs)",
                    kind: "microBreak",
                    atMs: Double(block.startAtMs),
                    expiresAtMs: block.end.timeIntervalSince1970 * 1_000,
                    maxTickGapMs: nil,
                    collapseGroup: "microBreak:focus",
                    title: t("microBreakReminder"),
                    body: t("focusBreakReminderBody", values: [
                        "count": "\(block.durationMinutes)"
                    ])
                )
            }
    }

    /// Swaps fixed-interval health reminders for the plan's own breaks, for the
    /// stretch of time the plan covers.
    ///
    /// The next shift is left alone: it rarely has a plan yet, and the reminder
    /// it would replace has not been scheduled against anything the user drew.
    func applyingFocusBreakTakeover(
        to reminders: [NativeReminder],
        at date: Date = .now
    ) -> [NativeReminder] {
        guard focusOwnsBreaks(at: date),
              let shift = focusCanvasShift(at: date)?.snapshot
        else { return reminders }
        let start = shift.startAtMs
        let end = Double(shift.segments.map(\.endAtMs).max() ?? shift.startAtMs)
        let kept = reminders.filter { reminder in
            guard reminder.kind == "microBreak" else { return true }
            return reminder.atMs < start || reminder.atMs > end
        }
        return (kept + focusBreakReminders(at: date)).sorted { $0.atMs < $1.atMs }
    }
}
