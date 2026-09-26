import Foundation
import LocalAuthentication

/// Localized presentation and native formatting, shared by feature surfaces.
/// Depends on committed preferences and has no application or session lifetime.
@MainActor
final class AppText {
    let localizer: NativeLocalizer
    private let preferences: PreferencesStore

    init(preferences: PreferencesStore, localizer: NativeLocalizer = NativeLocalizer()) {
        self.preferences = preferences
        self.localizer = localizer
    }

    func t(_ key: String, values: [String: String] = [:]) -> String {
        localizer.string(key, locale: preferences.languageCode, values: values)
    }

    /// Plural-aware lookup. `count` picks the grammatical variant and, unless
    /// the caller supplies its own, also fills `{{count}}` with the
    /// locale-formatted number. Keeping both on one argument is the point:
    /// when a call site formatted the number itself and left the lookup
    /// countless, German rendered a single recorded day as "1 Arbeitstage".
    func t(_ key: String, count: Int, values: [String: String] = [:]) -> String {
        var merged = values
        if merged["count"] == nil { merged["count"] = formatCount(count) }
        return localizer.string(key, locale: preferences.languageCode, count: count, values: merged)
    }

    func strings(_ key: String) -> [String] {
        localizer.strings(key, locale: preferences.languageCode)
    }

    func formatTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(preferences.locale))
    }

    /// A calendar date in the app's language and the device's own zone — for
    /// things that belong to the device rather than to the records archive,
    /// such as when a subscription renews.
    func formatDate(_ date: Date) -> String {
        RecordsDateFormatters.shared
            .formatter(template: "yMMMd", locale: preferences.locale, timeZone: .current)
            .string(from: date)
    }

    func formatDuration(_ milliseconds: Double, includeSeconds: Bool = true) -> String {
        let total = max(0, Int(milliseconds / 1_000))
        guard includeSeconds else { return formatRelativeDuration(milliseconds) }
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }

    func formatDays(_ value: Double) -> String {
        let precision = value.rounded() == value ? 0 : 1
        let number = value.formatted(.number.precision(.fractionLength(precision)).locale(preferences.locale))
        return t("daysShort", values: ["count": number])
    }

    func formatRelativeDuration(_ milliseconds: Double) -> String {
        RelativeDurationFormatter.string(milliseconds: milliseconds, languageCode: preferences.languageCode)
    }

    func formatRecordsDuration(_ milliseconds: Double) -> String {
        RelativeDurationFormatter.string(milliseconds: milliseconds, languageCode: preferences.languageCode, includesDays: true)
    }

    /// A duration equivalent, not a calendar age or a schedule calculation.
    func formatApproximateLifeYears(_ milliseconds: Double) -> String? {
        let yearMs = 365.2425 * 86_400_000
        guard milliseconds.isFinite, milliseconds >= yearMs else { return nil }
        let years = (milliseconds / yearMs).formatted(
            .number.precision(.fractionLength(0...2)).locale(preferences.locale)
        )
        return t("lifeApproxYears", values: ["years": years])
    }

    func formatHours(_ value: Double) -> String {
        let fractionDigits = value.rounded() == value ? 0 : 1
        let key = "\(preferences.locale.identifier)|\(fractionDigits)"
        let formatter = hoursFormatters[key] ?? {
            let formatter = MeasurementFormatter()
            formatter.locale = preferences.locale
            formatter.unitOptions = .providedUnit
            formatter.unitStyle = .short
            formatter.numberFormatter.maximumFractionDigits = fractionDigits
            hoursFormatters[key] = formatter
            return formatter
        }()
        return formatter.string(from: Measurement(value: value, unit: UnitDuration.hours))
    }

    /// The timer's summary rows format hours every second; a formatter per
    /// call was a fresh ICU setup each time.
    private var hoursFormatters: [String: MeasurementFormatter] = [:]

    /// A plain count. Interpolating an `Int` into a string skips the locale's
    /// digits and grouping separator entirely.
    func formatCount(_ value: Int) -> String {
        value.formatted(.number.locale(preferences.locale))
    }

    /// A calendar year is a label, not a quantity: grouping separators turn
    /// 1992 into "1,992", which then wraps to two lines in the Life grid gutter.
    func formatYear(_ value: Int) -> String {
        value.formatted(.number.grouping(.never).locale(preferences.locale))
    }

    func formatMoney(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2)).locale(preferences.locale))
    }

    /// The only way money should reach the screen.
    ///
    /// `preferences.hideEarnings` is one switch for the whole product, so every amount has
    /// to consult it. Spelling the mask out at each call site meant the next
    /// screen to show an amount simply forgot — which is how the Records tab
    /// shipped an income figure the eye toggle could not hide. Ask for the
    /// text here and the mask cannot be left out.
    func moneyText(_ value: Double?) -> String {
        preferences.hideEarnings ? "••••" : formatMoney(value)
    }

    func formatPercent(_ value: Double, fractionDigits: Int = 1) -> String {
        (value / 100).formatted(
            .percent.precision(.fractionLength(fractionDigits)).locale(preferences.locale)
        )
    }

    func weekdayLabels() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = preferences.locale
        let symbols = calendar.shortWeekdaySymbols
        return [1, 2, 3, 4, 5, 6, 0].map { day in
            let calendarIndex = day == 0 ? 0 : day
            return symbols[calendarIndex]
        }
    }

    func relativeDayLabel(for date: Date, from now: Date = .now) -> String {
        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return t("tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).locale(preferences.locale))
    }

    func weekdayName(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).locale(preferences.locale))
    }

    /// The full weekday name of a civil day number (days since 1970-01-01),
    /// which names the same day whatever zone the device is in.
    func weekdayName(civilDayNumber: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = preferences.locale
        // 1970-01-01 was a Thursday; `weekdaySymbols` starts on Sunday.
        return calendar.weekdaySymbols[((civilDayNumber + 4) % 7 + 7) % 7]
    }

    /// A civil date read as a label, so the device's zone cannot move it to a
    /// neighbouring day. `template` is a date format skeleton, e.g. "yMMMM".
    func formatCivilDate(year: Int, month: Int, day: Int = 1, template: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            return "\(year)-\(month)-\(day)"
        }
        return RecordsDateFormatters.shared
            .formatter(template: template, locale: preferences.locale, timeZone: .gmt)
            .string(from: date)
    }

}

extension AppText {
    var salaryTypeLabel: String {
        guard preferences.salaryEnabled else { return t("disabledShort") }
        return preferences.salaryType == .monthly ? t("monthly") : t("daily")
    }

    var notificationModeLabel: String {
        switch preferences.notificationMode {
        case .off: t("notificationModeOff")
        case .simple: t("notificationModeSimple")
        case .milestones: t("notificationModeMilestones")
        }
    }

    var themeLabel: String {
        switch preferences.theme {
        case .auto: t("auto")
        case .light: t("light")
        case .dark: t("dark")
        }
    }

    /// Reads like the preferences.theme row: say "System" when following it, name the
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
        guard let languageOverride = preferences.languageOverride else { return t("auto") }
        return localizer.languageName(for: languageOverride)
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Planned working time for a caller-supplied preview, lunch already deducted.
    func plannedWorkLabel(for snapshot: NativeShiftSnapshot?) -> String {
        guard let snapshot else { return "—" }
        return formatRelativeDuration(snapshot.plannedDurationMs)
    }
}

extension AppText {
    /// One name for the current Plus state, so the settings row, the Plus page
    /// and the paywall cannot disagree.
    ///
    /// The settings row used to print "Plus" for every authorized state, so a
    /// lifetime purchase, a trial and a failed-payment grace period all read
    /// the same — including to someone about to lose access in three days.
    func plusStatusLabel(for plus: PlusEntitlement) -> String {
        switch plus.authorization {
        case .authorized(.lifetime):
            return t("plusStatusLifetime")
        case .authorized(.subscribed):
            return t(plus.isInTrial ? "plusStatusTrial" : "plusStatusSubscribed")
        case .authorized(.inGracePeriod):
            return t("plusStatusGrace")
        case .pendingAskToBuy:
            return t("plusStatusPending")
        case .unauthorized:
            return t("plusStatusNone")
        }
    }


}
