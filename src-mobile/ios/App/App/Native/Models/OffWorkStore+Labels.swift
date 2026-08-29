import Foundation
import LocalAuthentication

/// One vocabulary for the setting summaries shown next to a row.
///
/// These used to be private computed properties copy-pasted into every layout —
/// `scheduleLabel` existed in six places, `lunchLabel` in four — which is how
/// the "schedule off" case ended up worded two different ways. Portrait,
/// landscape, iPad and the settings list all read them from here now.
extension OffWorkStore {
    var scheduleLabel: String {
        return switch effectiveScheduleMode() {
        case .classic: t("scheduleClassic")
        case .alternating: t("scheduleAlternating")
        case .rotation: t("scheduleRotation")
        case .off: t("scheduleOff")
        }
    }

    /// One-line confirmation of what the schedule form just set.
    ///
    /// Classic uses a range when the chosen days are one run on the week
    /// ("Mon–Fri"), and lists them when they are not ("Mon, Wed, Fri").
    /// Alternating and rotation use the mode name; the details were on the
    /// previous page. Hours always join with the same middle dot.
    func onboardingScheduleRecap() -> String {
        let hours = "\(timeString(startMinutes))–\(timeString(endMinutes))"
        switch scheduleMode {
        case .off:
            return hours
        case .alternating:
            return "\(t("scheduleAlternating")) · \(hours)"
        case .rotation:
            return "\(t("scheduleRotation")) · \(hours)"
        case .classic:
            let days = classicWeekdayRecap()
            return days.map { "\($0) · \(hours)" } ?? hours
        }
    }

    /// Monday-first order, matching `weekdayLabels()`.
    private static let weekOrder = [1, 2, 3, 4, 5, 6, 0]

    private func classicWeekdayRecap() -> String? {
        let order = Self.weekOrder
        let labels = weekdayLabels()
        let selected = order.filter { workdays.contains($0) }
        guard !selected.isEmpty else { return nil }
        if selected.count >= 2, let range = contiguousWeekdayRange(Set(selected), order: order) {
            let start = weekdayName(range.start, order: order, labels: labels)
            let end = weekdayName(range.end, order: order, labels: labels)
            return t("weekdayRange", values: ["start": start, "end": end])
        }
        let names = selected.map { weekdayName($0, order: order, labels: labels) }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }

    private func weekdayName(_ day: Int, order: [Int], labels: [String]) -> String {
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

    var lunchLabel: String {
        guard lunchEnabled else { return t("disabledShort") }
        return "\(timeString(lunchStartMinutes)) · \(formatRelativeDuration(Double(lunchDurationMinutes) * 60_000))"
    }

    func lunchLabel(at date: Date) -> String {
        guard effectiveLunchEnabled(at: date) else { return t("disabledShort") }
        return "\(timeString(effectiveLunchStartMinutes(at: date))) · \(formatRelativeDuration(Double(effectiveLunchDurationMinutes(at: date)) * 60_000))"
    }

    var healthLabel: String {
        microBreakEnabled
            ? t("minutesShort", values: ["count": "\(microBreakIntervalMinutes)"])
            : t("disabledShort")
    }

    var salaryTypeLabel: String {
        guard salaryEnabled else { return t("disabledShort") }
        return salaryType == .monthly ? t("monthly") : t("daily")
    }

    var notificationModeLabel: String {
        switch notificationMode {
        case .off: t("notificationModeOff")
        case .simple: t("notificationModeSimple")
        case .milestones: t("notificationModeMilestones")
        }
    }

    var themeLabel: String {
        switch theme {
        case .auto: t("auto")
        case .light: t("light")
        case .dark: t("dark")
        }
    }

    /// Reads like the theme row: say "System" when following it, name the
    /// language when it has been pinned.
    /// What this device's biometry is called, for copy that used to say
    /// "Face ID" no matter what the hardware was.
    ///
    /// Falls back to the generic word when there is no biometric hardware, so a
    /// sentence built around it still reads.
    func biometryName(_ biometry: LABiometryType) -> String {
        guard let key = biometry.nameKey else { return t("biometrics") }
        return t(key)
    }

    var languageLabel: String {
        guard let languageOverride else { return t("auto") }
        return localizer.languageName(for: languageOverride)
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Planned working time for today, lunch already deducted. Uses the hours
    /// the setup page is showing, including uncommitted edits.
    var plannedWorkLabel: String {
        guard let snapshot = setupSnapshot() else { return "—" }
        return formatRelativeDuration(snapshot.plannedDurationMs)
    }
}
