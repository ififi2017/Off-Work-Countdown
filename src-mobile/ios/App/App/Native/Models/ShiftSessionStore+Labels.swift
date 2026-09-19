import Foundation

/// One vocabulary for the setting summaries shown next to a row.
///
/// These used to be private computed properties copy-pasted into every layout —
/// `scheduleLabel` existed in six places, `lunchLabel` in four — which is how
/// the "schedule off" case ended up worded two different ways. Portrait,
/// landscape, iPad and the settings list all read them from here now.
extension ShiftSessionStore {
    var scheduledBreakTitle: String {
        text.t(preferences.isExtendedScheduleEnabled ? "extendedBreak" : "lunchBreak")
    }

    var scheduledBreakInProgressTitle: String {
        text.t(preferences.isExtendedScheduleEnabled ? "extendedBreak" : "lunchInProgress")
    }

    var scheduledBreakStartTitle: String {
        text.t(preferences.isExtendedScheduleEnabled ? "extendedBreakStart" : "lunchStartTime")
    }

    var scheduleLabel: String {
        return switch self.session.effectiveScheduleMode() {
        case .classic: text.t("scheduleClassic")
        case .alternating: text.t("scheduleAlternating")
        case .rotation: text.t("scheduleRotation")
        case .off: text.t("scheduleOff")
        }
    }

    /// One-line confirmation of what the schedule form just set.
    ///
    /// Classic uses a range when the chosen days are one run on the week
    /// ("Mon–Fri"), and lists them when they are not ("Mon, Wed, Fri").
    /// Alternating and rotation use the mode name; the details were on the
    /// previous page. Hours always join with the same middle dot.
    func onboardingScheduleRecap() -> String {
        let hours = "\(self.session.timeString(preferences.startMinutes))–\(self.session.timeString(preferences.endMinutes))"
        switch preferences.scheduleMode {
        case .off:
            return hours
        case .alternating:
            return "\(text.t("scheduleAlternating")) · \(hours)"
        case .rotation:
            return "\(text.t("scheduleRotation")) · \(hours)"
        case .classic:
            let days = classicWeekdayRecap()
            return days.map { "\($0) · \(hours)" } ?? hours
        }
    }

    /// Monday-first order, matching `text.weekdayLabels()`.
    private static let weekOrder = [1, 2, 3, 4, 5, 6, 0]

    private func classicWeekdayRecap() -> String? {
        let order = Self.weekOrder
        let labels = text.weekdayLabels()
        let selected = order.filter { preferences.workdays.contains($0) }
        guard !selected.isEmpty else { return nil }
        if selected.count >= 2, let range = contiguousWeekdayRange(Set(selected), order: order) {
            let start = weekdayLabel(range.start, order: order, labels: labels)
            let end = weekdayLabel(range.end, order: order, labels: labels)
            return text.t("weekdayRange", values: ["start": start, "end": end])
        }
        let names = selected.map { weekdayLabel($0, order: order, labels: labels) }
        let formatter = ListFormatter()
        formatter.locale = preferences.locale
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }

    private func weekdayLabel(_ day: Int, order: [Int], labels: [String]) -> String {
        guard let index = order.firstIndex(of: day), index < labels.count else { return "" }
        return labels[index]
    }

    /// One arc on the Mon–Sun circle. Walking the week twice finds a wrap
    /// such as Friday–Sunday without treating Mon/Wed/Fri as a span.
    private func contiguousWeekdayRange(
        _ selected: Set<Int>,
        order: [Int]
    ) -> (start: Int, end: Int)? {
        var run: [Int] = []
        var best: [Int] = []
        for day in order + order {
            if selected.contains(day) {
                run.append(day)
                // Walking the week twice finds a wrap such as Friday–Sunday.
                // Without the one-cycle cap, a full-week selection grows to
                // 14 and the equality guard below rejects Monday–Sunday.
                if run.count <= order.count, run.count > best.count {
                    best = run
                }
            } else {
                run = []
            }
        }
        guard best.count == selected.count else { return nil }
        return (best[0], best[best.count - 1])
    }

    var healthLabel: String { healthLabel(at: .now) }

    func healthLabel(at date: Date) -> String {
        guard preferences.microBreakEnabled else { return text.t("disabledShort") }
        // The pomodoro's long breaks stand in for the fixed interval on a
        // planned shift, so nothing is counting to 60 minutes any more. The
        // row advertised the interval regardless, and the detail page it opens
        // then said the opposite. Same wording as that page, so the two agree.
        guard !focus.focusOwnsBreaks(at: date) else { return text.t("microBreakFollowsFocus") }
        return text.t("minutesShort", values: ["count": "\(preferences.microBreakIntervalMinutes)"])
    }

}
