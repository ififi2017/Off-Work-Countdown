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
        // Classic mode with nothing selected is off in practice, even though
        // the mode itself is still set.
        if scheduleMode == .classic, workdays.isEmpty { return t("disabledShort") }
        return switch scheduleMode {
        case .classic: t("scheduleClassic")
        case .alternating: t("scheduleAlternating")
        case .rotation: t("scheduleRotation")
        case .off: t("disabledShort")
        }
    }

    var lunchLabel: String {
        guard lunchEnabled else { return t("disabledShort") }
        return "\(timeString(lunchStartMinutes)) · \(formatRelativeDuration(Double(lunchDurationMinutes) * 60_000))"
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

    /// Planned working time for today, lunch already deducted.
    var plannedWorkLabel: String {
        guard let snapshot = snapshot() else { return "—" }
        return formatRelativeDuration(snapshot.plannedDurationMs)
    }
}
